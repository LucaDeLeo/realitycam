//! Debug log endpoints for cross-stack observability
//!
//! SECURITY: These endpoints are ONLY available when DEBUG_LOGS_ENABLED=true
//! They should NEVER be enabled in production environments.
//!
//! ## Endpoints
//! - POST /api/v1/debug/logs - Batch insert log entries
//! - GET /api/v1/debug/logs - Query logs with filters
//! - GET /api/v1/debug/logs/{id} - Get single log entry
//! - DELETE /api/v1/debug/logs - Delete logs with filters
//! - GET /api/v1/debug/logs/stats - Get aggregated statistics

use axum::{
    extract::{Extension, Path, Query, State},
    http::StatusCode,
    routing::{delete, get, post},
    Json, Router,
};
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::models::{
    BatchInsertResponse, CreateDebugLog, DebugLogDelete, DebugLogQuery, DebugLogStats,
    DeleteResponse, QueryLogsResponse,
};
use crate::routes::AppState;
use crate::services::debug_logs;
use crate::types::ApiResponse;

// ============================================================================
// Router Setup
// ============================================================================

/// Creates the debug routes router.
///
/// Routes:
/// - POST /logs - Batch insert log entries
/// - GET /logs - Query logs with filters
/// - GET /logs/stats - Get aggregated statistics (must be before /{id})
/// - GET /logs/{id} - Get single log entry
/// - DELETE /logs - Delete logs with filters
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/logs", post(create_logs))
        .route("/logs", get(query_logs))
        .route("/logs", delete(delete_logs))
        .route("/logs/stats", get(get_stats))
        .route("/logs/{id}", get(get_log_by_id))
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/v1/debug/logs - Batch insert log entries
///
/// Accepts an array of log entries (up to max_batch size).
///
/// # Request Body
/// Array of log entry objects with:
/// - correlation_id: UUID for tracing
/// - timestamp: ISO 8601 timestamp
/// - source: "ios" | "backend" | "web"
/// - level: "debug" | "info" | "warn" | "error"
/// - event: Event type string
/// - payload: Optional JSON object
/// - device_id: Optional UUID
/// - session_id: Optional UUID
///
/// # Responses
/// - 201 Created: Returns count of inserted entries
/// - 400 Bad Request: Invalid data or batch too large
/// - 404 Not Found: Debug logging disabled
async fn create_logs(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Json(logs): Json<Vec<CreateDebugLog>>,
) -> Result<(StatusCode, Json<ApiResponse<BatchInsertResponse>>), ApiErrorWithRequestId> {
    // Check batch size
    let max_batch = state.config.debug_logs_max_batch;
    if logs.len() > max_batch {
        return Err(ApiErrorWithRequestId {
            error: ApiError::Validation(format!(
                "Batch size {} exceeds maximum of {max_batch}",
                logs.len()
            )),
            request_id,
        });
    }

    tracing::info!(
        request_id = %request_id,
        count = logs.len(),
        "Inserting debug log batch"
    );

    // Insert logs
    let count = debug_logs::insert_batch(&state.db, logs)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    let response = BatchInsertResponse { count };

    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(response, request_id)),
    ))
}

/// GET /api/v1/debug/logs - Query logs with filters
///
/// # Query Parameters
/// - correlation_id: Filter by correlation ID (exact match)
/// - source: Filter by source (ios, backend, web)
/// - level: Filter by level (debug, info, warn, error)
/// - event: Filter by event type (substring match)
/// - since: ISO timestamp, logs after this time
/// - limit: Max results (default 100, max 1000)
/// - order: "asc" or "desc" (default "desc")
///
/// # Responses
/// - 200 OK: Returns logs with count and has_more pagination info
/// - 400 Bad Request: Invalid query parameters
/// - 404 Not Found: Debug logging disabled
async fn query_logs(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Query(query): Query<DebugLogQuery>,
) -> Result<Json<ApiResponse<QueryLogsResponse>>, ApiErrorWithRequestId> {
    // Validate query parameters
    query.validate().map_err(|e| ApiErrorWithRequestId {
        error: ApiError::Validation(e),
        request_id,
    })?;

    let limit = query.effective_limit();

    tracing::debug!(
        request_id = %request_id,
        correlation_id = ?query.correlation_id,
        source = ?query.source,
        level = ?query.level,
        event = ?query.event,
        limit = ?query.limit,
        "Querying debug logs"
    );

    let logs = debug_logs::query(&state.db, &query)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    // Determine if there are more results (if we got exactly limit results, there may be more)
    let count = logs.len();
    let has_more = count as u32 == limit;

    let response = QueryLogsResponse {
        logs,
        count,
        has_more,
    };

    Ok(Json(ApiResponse::new(response, request_id)))
}

/// GET /api/v1/debug/logs/{id} - Get single log entry
///
/// # Path Parameters
/// - id: UUID of the log entry
///
/// # Responses
/// - 200 OK: Returns the log entry
/// - 404 Not Found: Log entry not found or debug logging disabled
async fn get_log_by_id(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<crate::models::DebugLog>>, ApiErrorWithRequestId> {
    tracing::debug!(
        request_id = %request_id,
        log_id = %id,
        "Getting debug log by ID"
    );

    let log = debug_logs::get_by_id(&state.db, id)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?
        .ok_or_else(|| ApiErrorWithRequestId {
            error: ApiError::DebugLogNotFound,
            request_id,
        })?;

    Ok(Json(ApiResponse::new(log, request_id)))
}

/// DELETE /api/v1/debug/logs - Delete logs with filters
///
/// # Query Parameters
/// - source: Filter by source (ios, backend, web)
/// - level: Filter by level (debug, info, warn, error)
/// - older_than: ISO timestamp, delete logs before this time
///
/// # Responses
/// - 200 OK: Returns count of deleted entries
/// - 400 Bad Request: Invalid parameters
/// - 404 Not Found: Debug logging disabled
async fn delete_logs(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Query(params): Query<DebugLogDelete>,
) -> Result<Json<ApiResponse<DeleteResponse>>, ApiErrorWithRequestId> {
    // Validate parameters
    params.validate().map_err(|e| ApiErrorWithRequestId {
        error: ApiError::Validation(e),
        request_id,
    })?;

    tracing::info!(
        request_id = %request_id,
        source = ?params.source,
        level = ?params.level,
        older_than = ?params.older_than,
        "Deleting debug logs"
    );

    let deleted =
        debug_logs::delete(&state.db, &params)
            .await
            .map_err(|e| ApiErrorWithRequestId {
                error: e,
                request_id,
            })?;

    let response = DeleteResponse { deleted };

    Ok(Json(ApiResponse::new(response, request_id)))
}

/// GET /api/v1/debug/logs/stats - Get aggregated statistics
///
/// # Responses
/// - 200 OK: Returns aggregated counts by source and level
/// - 404 Not Found: Debug logging disabled
async fn get_stats(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
) -> Result<Json<ApiResponse<DebugLogStats>>, ApiErrorWithRequestId> {
    tracing::debug!(request_id = %request_id, "Getting debug log stats");

    let stats = debug_logs::get_stats(&state.db)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    Ok(Json(ApiResponse::new(stats, request_id)))
}

// ============================================================================
// Integration Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::models::{LogLevel, LogSource};
    use crate::services::ChallengeStore;
    use axum::body::Body;
    use axum::http::{Method, Request, StatusCode};
    use chrono::{Duration, Utc};
    use serde_json::json;
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use tower::ServiceExt;

    /// Creates a test app state with a real database connection
    async fn create_test_state() -> AppState {
        // Load test configuration
        dotenvy::dotenv().ok();
        let config = Config::default_for_test();

        // Connect to test database
        let database_url =
            std::env::var("DATABASE_URL").unwrap_or_else(|_| config.database_url.clone());

        let pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(&database_url)
            .await
            .expect("Failed to connect to test database");

        // Run migrations
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .expect("Failed to run migrations");

        // Create minimal storage service (not used by debug endpoints)
        let storage = Arc::new(crate::services::StorageService::new(&config).await);

        AppState {
            db: pool,
            challenge_store: ChallengeStore::new(),
            config: Arc::new(config),
            storage,
        }
    }

    /// Creates a test router with the debug routes
    fn create_test_router(state: AppState) -> Router {
        Router::new()
            .nest("/debug", router())
            .with_state(state)
            .layer(axum::middleware::from_fn(
                |req: axum::http::Request<Body>, next: axum::middleware::Next| async {
                    // Inject request ID
                    let request_id = Uuid::new_v4();
                    let mut req = req;
                    req.extensions_mut().insert(request_id);
                    next.run(req).await
                },
            ))
    }

    /// Cleans up test data before/after tests
    async fn cleanup_test_data(state: &AppState) {
        sqlx::query("DELETE FROM debug_logs")
            .execute(&state.db)
            .await
            .expect("Failed to cleanup test data");
    }

    /// Creates a sample log entry for testing
    fn sample_log(source: LogSource, level: LogLevel, event: &str) -> CreateDebugLog {
        CreateDebugLog {
            correlation_id: Uuid::new_v4(),
            timestamp: Utc::now(),
            source,
            level,
            event: event.to_string(),
            payload: json!({"test": true}),
            device_id: None,
            session_id: None,
        }
    }

    // ========================================================================
    // POST /debug/logs Tests
    // ========================================================================

    #[tokio::test]
    async fn test_create_logs_valid_batch() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;
        let app = create_test_router(state.clone());

        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Info, "TEST_EVENT_1"),
            sample_log(LogSource::Backend, LogLevel::Debug, "TEST_EVENT_2"),
        ];

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/debug/logs")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_string(&logs).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::CREATED);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["data"]["count"], 2);

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_create_logs_oversized_batch() {
        let state = create_test_state().await;
        let app = create_test_router(state.clone());

        // Create more logs than max_batch (101 > 100)
        let logs: Vec<CreateDebugLog> = (0..101)
            .map(|i| sample_log(LogSource::Ios, LogLevel::Info, &format!("EVENT_{i}")))
            .collect();

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/debug/logs")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_string(&logs).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn test_create_logs_empty_batch() {
        let state = create_test_state().await;
        let app = create_test_router(state.clone());

        let logs: Vec<CreateDebugLog> = vec![];

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/debug/logs")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_string(&logs).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::CREATED);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["data"]["count"], 0);
    }

    // ========================================================================
    // GET /debug/logs Tests
    // ========================================================================

    #[tokio::test]
    async fn test_query_logs_returns_entries() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert test data directly
        let log = sample_log(LogSource::Ios, LogLevel::Info, "QUERY_TEST");
        debug_logs::insert_batch(&state.db, vec![log])
            .await
            .unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert!(!json["data"]["logs"].as_array().unwrap().is_empty());
        assert!(json["data"]["count"].as_u64().unwrap() > 0);

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_filter_by_source() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert logs from different sources
        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Info, "IOS_EVENT"),
            sample_log(LogSource::Backend, LogLevel::Info, "BACKEND_EVENT"),
        ];
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs?source=ios")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let logs = json["data"]["logs"].as_array().unwrap();
        assert!(logs.iter().all(|log| log["source"] == "ios"));

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_filter_by_level() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Error, "ERROR_EVENT"),
            sample_log(LogSource::Ios, LogLevel::Info, "INFO_EVENT"),
        ];
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs?level=error")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let logs = json["data"]["logs"].as_array().unwrap();
        assert!(logs.iter().all(|log| log["level"] == "error"));

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_filter_by_event_substring() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Info, "UPLOAD_REQUEST"),
            sample_log(LogSource::Ios, LogLevel::Info, "DOWNLOAD_COMPLETE"),
        ];
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs?event=UPLOAD")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let logs = json["data"]["logs"].as_array().unwrap();
        assert!(logs.iter().all(|log| {
            log["event"]
                .as_str()
                .unwrap()
                .to_uppercase()
                .contains("UPLOAD")
        }));

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_filter_by_correlation_id() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        let correlation_id = Uuid::new_v4();
        let mut log = sample_log(LogSource::Ios, LogLevel::Info, "CORR_TEST");
        log.correlation_id = correlation_id;
        debug_logs::insert_batch(&state.db, vec![log])
            .await
            .unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri(format!("/debug/logs?correlation_id={correlation_id}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let logs = json["data"]["logs"].as_array().unwrap();
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0]["correlation_id"], correlation_id.to_string());

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_respects_limit() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert 10 logs
        let logs: Vec<CreateDebugLog> = (0..10)
            .map(|i| sample_log(LogSource::Ios, LogLevel::Info, &format!("LIMIT_TEST_{i}")))
            .collect();
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs?limit=5")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let logs = json["data"]["logs"].as_array().unwrap();
        assert_eq!(logs.len(), 5);
        assert_eq!(json["data"]["count"], 5);
        assert!(json["data"]["has_more"].as_bool().unwrap()); // 5 == limit, so has_more = true

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_order_asc() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert logs with different timestamps
        let mut log1 = sample_log(LogSource::Ios, LogLevel::Info, "FIRST");
        log1.timestamp = Utc::now() - Duration::seconds(10);
        let log2 = sample_log(LogSource::Ios, LogLevel::Info, "SECOND");
        debug_logs::insert_batch(&state.db, vec![log1, log2])
            .await
            .unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs?order=asc")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let logs = json["data"]["logs"].as_array().unwrap();
        assert!(logs.len() >= 2);
        // First entry should be older (FIRST)
        assert_eq!(logs[0]["event"], "FIRST");

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_combined_filters() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Error, "IOS_ERROR"),
            sample_log(LogSource::Ios, LogLevel::Info, "IOS_INFO"),
            sample_log(LogSource::Backend, LogLevel::Error, "BACKEND_ERROR"),
        ];
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs?source=ios&level=error")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let logs = json["data"]["logs"].as_array().unwrap();
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0]["source"], "ios");
        assert_eq!(logs[0]["level"], "error");

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_query_logs_invalid_source() {
        let state = create_test_state().await;
        let app = create_test_router(state);

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs?source=invalid")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    // ========================================================================
    // GET /debug/logs/{id} Tests
    // ========================================================================

    #[tokio::test]
    async fn test_get_log_by_id_found() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert and get the ID
        let log = sample_log(LogSource::Ios, LogLevel::Info, "GETBYID_TEST");
        debug_logs::insert_batch(&state.db, vec![log])
            .await
            .unwrap();

        // Query to get the ID
        let logs = debug_logs::query(&state.db, &DebugLogQuery::default())
            .await
            .unwrap();
        let log_id = logs[0].id;

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri(format!("/debug/logs/{log_id}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["data"]["id"], log_id.to_string());

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_get_log_by_id_not_found() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;
        let app = create_test_router(state.clone());

        let fake_id = Uuid::new_v4();
        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri(format!("/debug/logs/{fake_id}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::NOT_FOUND);

        cleanup_test_data(&state).await;
    }

    // ========================================================================
    // DELETE /debug/logs Tests
    // ========================================================================

    #[tokio::test]
    async fn test_delete_logs_all() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert test data
        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Info, "DELETE_TEST_1"),
            sample_log(LogSource::Backend, LogLevel::Error, "DELETE_TEST_2"),
        ];
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::DELETE)
                    .uri("/debug/logs")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["data"]["deleted"], 2);

        // Verify deletion
        let remaining = debug_logs::query(&state.db, &DebugLogQuery::default())
            .await
            .unwrap();
        assert!(remaining.is_empty());

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_delete_logs_filter_by_source() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Info, "IOS_DELETE"),
            sample_log(LogSource::Backend, LogLevel::Info, "BACKEND_KEEP"),
        ];
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::DELETE)
                    .uri("/debug/logs?source=ios")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["data"]["deleted"], 1);

        // Verify only backend log remains
        let remaining = debug_logs::query(&state.db, &DebugLogQuery::default())
            .await
            .unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].source, "backend");

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_delete_logs_filter_by_older_than() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert old and new logs
        let mut old_log = sample_log(LogSource::Ios, LogLevel::Info, "OLD_LOG");
        old_log.timestamp = Utc::now() - Duration::hours(2);
        let new_log = sample_log(LogSource::Ios, LogLevel::Info, "NEW_LOG");
        debug_logs::insert_batch(&state.db, vec![old_log, new_log])
            .await
            .unwrap();

        let app = create_test_router(state.clone());

        let cutoff = (Utc::now() - Duration::hours(1)).to_rfc3339();
        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::DELETE)
                    .uri(format!("/debug/logs?older_than={cutoff}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["data"]["deleted"], 1);

        // Verify only new log remains
        let remaining = debug_logs::query(&state.db, &DebugLogQuery::default())
            .await
            .unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].event, "NEW_LOG");

        cleanup_test_data(&state).await;
    }

    // ========================================================================
    // GET /debug/logs/stats Tests
    // ========================================================================

    #[tokio::test]
    async fn test_get_stats() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        // Insert logs with different sources and levels
        let logs = vec![
            sample_log(LogSource::Ios, LogLevel::Info, "STATS_1"),
            sample_log(LogSource::Ios, LogLevel::Error, "STATS_2"),
            sample_log(LogSource::Backend, LogLevel::Info, "STATS_3"),
            sample_log(LogSource::Web, LogLevel::Warn, "STATS_4"),
        ];
        debug_logs::insert_batch(&state.db, logs).await.unwrap();

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs/stats")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let stats = &json["data"];

        assert_eq!(stats["total"], 4);
        assert_eq!(stats["by_source"]["ios"], 2);
        assert_eq!(stats["by_source"]["backend"], 1);
        assert_eq!(stats["by_source"]["web"], 1);
        assert_eq!(stats["by_level"]["info"], 2);
        assert_eq!(stats["by_level"]["error"], 1);
        assert_eq!(stats["by_level"]["warn"], 1);
        assert_eq!(stats["by_level"]["debug"], 0);

        cleanup_test_data(&state).await;
    }

    #[tokio::test]
    async fn test_get_stats_empty() {
        let state = create_test_state().await;
        cleanup_test_data(&state).await;

        let app = create_test_router(state.clone());

        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/debug/logs/stats")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let stats = &json["data"];

        assert_eq!(stats["total"], 0);
        assert_eq!(stats["by_source"]["ios"], 0);
        assert_eq!(stats["by_level"]["error"], 0);

        cleanup_test_data(&state).await;
    }
}
