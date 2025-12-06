//! Debug logs service for storage and query operations
//!
//! Provides functions for inserting, querying, and managing debug logs
//! with correlation IDs for cross-stack request tracing.

use sqlx::PgPool;
use uuid::Uuid;

use crate::error::ApiError;
use crate::models::{
    CreateDebugLog, DebugLog, DebugLogDelete, DebugLogQuery, DebugLogStats, LevelCounts,
    SourceCounts,
};

// ============================================================================
// Insert Operations
// ============================================================================

/// Inserts a batch of debug log entries
///
/// # Arguments
/// * `pool` - Database connection pool
/// * `logs` - Vector of log entries to insert
///
/// # Returns
/// * Number of entries inserted
pub async fn insert_batch(pool: &PgPool, logs: Vec<CreateDebugLog>) -> Result<usize, ApiError> {
    if logs.is_empty() {
        return Ok(0);
    }

    let count = logs.len();

    // Build batch insert
    // Using a transaction for atomicity
    let mut tx = pool.begin().await.map_err(ApiError::Database)?;

    for log in logs {
        sqlx::query(
            r#"
            INSERT INTO debug_logs (
                correlation_id, timestamp, source, level, event, payload, device_id, session_id
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            "#,
        )
        .bind(log.correlation_id)
        .bind(log.timestamp)
        .bind(log.source.as_str())
        .bind(log.level.as_str())
        .bind(&log.event)
        .bind(&log.payload)
        .bind(log.device_id)
        .bind(log.session_id)
        .execute(&mut *tx)
        .await
        .map_err(ApiError::Database)?;
    }

    tx.commit().await.map_err(ApiError::Database)?;

    tracing::debug!(count = count, "Inserted debug log batch");

    Ok(count)
}

// ============================================================================
// Query Operations
// ============================================================================

/// Queries debug logs with filters
///
/// # Arguments
/// * `pool` - Database connection pool
/// * `query` - Query parameters
///
/// # Returns
/// * Vector of matching debug log entries
pub async fn query(pool: &PgPool, query: &DebugLogQuery) -> Result<Vec<DebugLog>, ApiError> {
    let limit = query.effective_limit() as i64;
    let order_desc = !query.is_ascending();

    // Build dynamic query based on filters
    // Using raw SQL for flexibility with optional parameters
    let mut sql = String::from(
        r#"
        SELECT id, correlation_id, timestamp, source, level, event, payload,
               device_id, session_id, created_at
        FROM debug_logs
        WHERE 1=1
        "#,
    );

    let mut param_count = 0;

    if query.correlation_id.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND correlation_id = ${param_count}"));
    }
    if query.source.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND source = ${param_count}"));
    }
    if query.level.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND level = ${param_count}"));
    }
    if query.event.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND event ILIKE ${param_count}"));
    }
    if query.since.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND timestamp >= ${param_count}"));
    }

    // Order by timestamp
    if order_desc {
        sql.push_str(" ORDER BY timestamp DESC");
    } else {
        sql.push_str(" ORDER BY timestamp ASC");
    }

    // Add limit
    param_count += 1;
    sql.push_str(&format!(" LIMIT ${param_count}"));

    // Build and execute query with bindings
    let mut query_builder = sqlx::query_as::<_, DebugLog>(&sql);

    if let Some(correlation_id) = query.correlation_id {
        query_builder = query_builder.bind(correlation_id);
    }
    if let Some(ref source) = query.source {
        query_builder = query_builder.bind(source);
    }
    if let Some(ref level) = query.level {
        query_builder = query_builder.bind(level);
    }
    if let Some(ref event) = query.event {
        // Use ILIKE for substring match with wildcards
        query_builder = query_builder.bind(format!("%{event}%"));
    }
    if let Some(since) = query.since {
        query_builder = query_builder.bind(since);
    }
    query_builder = query_builder.bind(limit);

    let logs = query_builder
        .fetch_all(pool)
        .await
        .map_err(ApiError::Database)?;

    tracing::debug!(count = logs.len(), "Queried debug logs");

    Ok(logs)
}

/// Gets a single debug log by ID
///
/// # Arguments
/// * `pool` - Database connection pool
/// * `id` - Log entry ID
///
/// # Returns
/// * The debug log entry, or None if not found
pub async fn get_by_id(pool: &PgPool, id: Uuid) -> Result<Option<DebugLog>, ApiError> {
    let log = sqlx::query_as::<_, DebugLog>(
        r#"
        SELECT id, correlation_id, timestamp, source, level, event, payload,
               device_id, session_id, created_at
        FROM debug_logs
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .map_err(ApiError::Database)?;

    Ok(log)
}

// ============================================================================
// Delete Operations
// ============================================================================

/// Deletes debug logs matching the filters
///
/// # Arguments
/// * `pool` - Database connection pool
/// * `params` - Delete parameters
///
/// # Returns
/// * Number of entries deleted
pub async fn delete(pool: &PgPool, params: &DebugLogDelete) -> Result<u64, ApiError> {
    // Build dynamic delete query
    let mut sql = String::from("DELETE FROM debug_logs WHERE 1=1");
    let mut param_count = 0;

    if params.source.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND source = ${param_count}"));
    }
    if params.level.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND level = ${param_count}"));
    }
    if params.older_than.is_some() {
        param_count += 1;
        sql.push_str(&format!(" AND timestamp < ${param_count}"));
    }

    let mut query_builder = sqlx::query(&sql);

    if let Some(ref source) = params.source {
        query_builder = query_builder.bind(source);
    }
    if let Some(ref level) = params.level {
        query_builder = query_builder.bind(level);
    }
    if let Some(older_than) = params.older_than {
        query_builder = query_builder.bind(older_than);
    }

    let result = query_builder
        .execute(pool)
        .await
        .map_err(ApiError::Database)?;

    tracing::info!(deleted = result.rows_affected(), "Deleted debug logs");

    Ok(result.rows_affected())
}

// ============================================================================
// Stats Operations
// ============================================================================

/// Gets aggregated statistics for debug logs
///
/// # Arguments
/// * `pool` - Database connection pool
///
/// # Returns
/// * Aggregated counts by source and level, plus oldest/newest timestamps
pub async fn get_stats(pool: &PgPool) -> Result<DebugLogStats, ApiError> {
    // Get total count and timestamp range
    let stats_row: (
        i64,
        Option<chrono::DateTime<chrono::Utc>>,
        Option<chrono::DateTime<chrono::Utc>>,
    ) = sqlx::query_as("SELECT COUNT(*), MIN(timestamp), MAX(timestamp) FROM debug_logs")
        .fetch_one(pool)
        .await
        .map_err(ApiError::Database)?;

    let (total, oldest, newest) = stats_row;

    // Get counts by source
    let source_rows: Vec<(String, i64)> =
        sqlx::query_as("SELECT source, COUNT(*) FROM debug_logs GROUP BY source")
            .fetch_all(pool)
            .await
            .map_err(ApiError::Database)?;

    let mut by_source = SourceCounts::default();
    for (source, count) in source_rows {
        match source.as_str() {
            "ios" => by_source.ios = count,
            "backend" => by_source.backend = count,
            "web" => by_source.web = count,
            _ => {}
        }
    }

    // Get counts by level
    let level_rows: Vec<(String, i64)> =
        sqlx::query_as("SELECT level, COUNT(*) FROM debug_logs GROUP BY level")
            .fetch_all(pool)
            .await
            .map_err(ApiError::Database)?;

    let mut by_level = LevelCounts::default();
    for (level, count) in level_rows {
        match level.as_str() {
            "debug" => by_level.debug = count,
            "info" => by_level.info = count,
            "warn" => by_level.warn = count,
            "error" => by_level.error = count,
            _ => {}
        }
    }

    Ok(DebugLogStats {
        total,
        by_source,
        by_level,
        oldest,
        newest,
    })
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{LogLevel, LogSource};
    use chrono::Utc;

    #[test]
    fn test_create_debug_log_source_as_str() {
        assert_eq!(LogSource::Ios.as_str(), "ios");
        assert_eq!(LogSource::Backend.as_str(), "backend");
        assert_eq!(LogSource::Web.as_str(), "web");
    }

    #[test]
    fn test_create_debug_log_level_as_str() {
        assert_eq!(LogLevel::Debug.as_str(), "debug");
        assert_eq!(LogLevel::Info.as_str(), "info");
        assert_eq!(LogLevel::Warn.as_str(), "warn");
        assert_eq!(LogLevel::Error.as_str(), "error");
    }

    #[test]
    fn test_query_effective_limit_clamped() {
        let query = DebugLogQuery {
            limit: Some(2000),
            ..Default::default()
        };
        assert_eq!(query.effective_limit(), 1000);
    }

    #[test]
    fn test_create_log_struct() {
        let log = CreateDebugLog {
            correlation_id: Uuid::new_v4(),
            timestamp: Utc::now(),
            source: LogSource::Ios,
            level: LogLevel::Info,
            event: "TEST_EVENT".to_string(),
            payload: serde_json::json!({"key": "value"}),
            device_id: None,
            session_id: None,
        };

        assert_eq!(log.source.as_str(), "ios");
        assert_eq!(log.level.as_str(), "info");
    }
}
