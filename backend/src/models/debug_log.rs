//! Debug log models for cross-stack observability
//!
//! This module defines structs for storing and querying debug logs
//! with correlation IDs for tracing requests across iOS, backend, and web.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

// ============================================================================
// Log Source Enum
// ============================================================================

/// Source of a debug log entry
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogSource {
    /// iOS app
    Ios,
    /// Rust backend
    Backend,
    /// Web frontend
    Web,
}

impl LogSource {
    /// Converts to database string representation
    pub fn as_str(&self) -> &'static str {
        match self {
            LogSource::Ios => "ios",
            LogSource::Backend => "backend",
            LogSource::Web => "web",
        }
    }
}

impl std::str::FromStr for LogSource {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "ios" => Ok(LogSource::Ios),
            "backend" => Ok(LogSource::Backend),
            "web" => Ok(LogSource::Web),
            _ => Err(format!(
                "Invalid log source: {s}. Must be ios, backend, or web"
            )),
        }
    }
}

// ============================================================================
// Log Level Enum
// ============================================================================

/// Severity level of a debug log entry
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    /// Debug level - verbose diagnostic information
    Debug,
    /// Info level - general operational information
    Info,
    /// Warn level - warning conditions
    Warn,
    /// Error level - error conditions
    Error,
}

impl LogLevel {
    /// Converts to database string representation
    pub fn as_str(&self) -> &'static str {
        match self {
            LogLevel::Debug => "debug",
            LogLevel::Info => "info",
            LogLevel::Warn => "warn",
            LogLevel::Error => "error",
        }
    }
}

impl std::str::FromStr for LogLevel {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "debug" => Ok(LogLevel::Debug),
            "info" => Ok(LogLevel::Info),
            "warn" => Ok(LogLevel::Warn),
            "error" => Ok(LogLevel::Error),
            _ => Err(format!(
                "Invalid log level: {s}. Must be debug, info, warn, or error"
            )),
        }
    }
}

// ============================================================================
// DebugLog Entity
// ============================================================================

/// A debug log entry retrieved from the database
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct DebugLog {
    /// Unique identifier for this log entry
    pub id: Uuid,
    /// Correlation ID for tracing requests across layers
    pub correlation_id: Uuid,
    /// When the log event occurred (from source)
    pub timestamp: DateTime<Utc>,
    /// Origin of the log entry
    pub source: String,
    /// Log severity level
    pub level: String,
    /// Event type identifier
    pub event: String,
    /// Structured event data
    pub payload: serde_json::Value,
    /// iOS device identifier (DEBUG builds only)
    pub device_id: Option<Uuid>,
    /// App session ID for grouping related logs
    pub session_id: Option<Uuid>,
    /// When this record was created in the database
    pub created_at: DateTime<Utc>,
}

// ============================================================================
// CreateDebugLog DTO
// ============================================================================

/// DTO for creating a new debug log entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateDebugLog {
    /// Correlation ID for tracing requests across layers
    pub correlation_id: Uuid,
    /// When the log event occurred
    pub timestamp: DateTime<Utc>,
    /// Origin of the log entry
    pub source: LogSource,
    /// Log severity level
    pub level: LogLevel,
    /// Event type identifier (e.g., "UPLOAD_REQUEST", "ATTESTATION_VERIFIED")
    pub event: String,
    /// Structured event data
    #[serde(default)]
    pub payload: serde_json::Value,
    /// iOS device identifier (optional)
    #[serde(default)]
    pub device_id: Option<Uuid>,
    /// App session ID (optional)
    #[serde(default)]
    pub session_id: Option<Uuid>,
}

// ============================================================================
// DebugLogQuery Parameters
// ============================================================================

/// Query parameters for filtering debug logs
#[derive(Debug, Clone, Default, Deserialize)]
pub struct DebugLogQuery {
    /// Filter by correlation ID (exact match)
    pub correlation_id: Option<Uuid>,
    /// Filter by source
    pub source: Option<String>,
    /// Filter by level
    pub level: Option<String>,
    /// Filter by event type (substring match)
    pub event: Option<String>,
    /// Filter logs after this timestamp
    pub since: Option<DateTime<Utc>>,
    /// Maximum number of results (default: 100, max: 1000)
    pub limit: Option<u32>,
    /// Sort order: "asc" or "desc" (default: "desc")
    pub order: Option<String>,
}

impl DebugLogQuery {
    /// Maximum allowed limit value
    pub const MAX_LIMIT: u32 = 1000;
    /// Default limit if not specified
    pub const DEFAULT_LIMIT: u32 = 100;

    /// Returns the effective limit, clamped to MAX_LIMIT
    pub fn effective_limit(&self) -> u32 {
        self.limit
            .map(|l| l.min(Self::MAX_LIMIT))
            .unwrap_or(Self::DEFAULT_LIMIT)
    }

    /// Returns true if order is ascending
    pub fn is_ascending(&self) -> bool {
        self.order.as_deref() == Some("asc")
    }

    /// Validates query parameters
    pub fn validate(&self) -> Result<(), String> {
        if let Some(source) = &self.source {
            source.parse::<LogSource>()?;
        }
        if let Some(level) = &self.level {
            level.parse::<LogLevel>()?;
        }
        if let Some(order) = &self.order {
            if order != "asc" && order != "desc" {
                return Err(format!("Invalid order: {order}. Must be asc or desc"));
            }
        }
        Ok(())
    }
}

// ============================================================================
// DebugLogDelete Parameters
// ============================================================================

/// Parameters for deleting debug logs
#[derive(Debug, Clone, Default, Deserialize)]
pub struct DebugLogDelete {
    /// Filter by source
    pub source: Option<String>,
    /// Filter by level
    pub level: Option<String>,
    /// Delete logs older than this timestamp
    pub older_than: Option<DateTime<Utc>>,
}

impl DebugLogDelete {
    /// Validates delete parameters
    pub fn validate(&self) -> Result<(), String> {
        if let Some(source) = &self.source {
            source.parse::<LogSource>()?;
        }
        if let Some(level) = &self.level {
            level.parse::<LogLevel>()?;
        }
        Ok(())
    }
}

// ============================================================================
// DebugLogStats Response
// ============================================================================

/// Aggregated statistics for debug logs
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DebugLogStats {
    /// Total number of log entries
    pub total: i64,
    /// Counts grouped by source
    pub by_source: SourceCounts,
    /// Counts grouped by level
    pub by_level: LevelCounts,
    /// Timestamp of oldest log entry
    pub oldest: Option<DateTime<Utc>>,
    /// Timestamp of newest log entry
    pub newest: Option<DateTime<Utc>>,
}

/// Counts by log source
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SourceCounts {
    pub ios: i64,
    pub backend: i64,
    pub web: i64,
}

/// Counts by log level
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LevelCounts {
    pub debug: i64,
    pub info: i64,
    pub warn: i64,
    pub error: i64,
}

// ============================================================================
// Query Logs Response
// ============================================================================

/// Response for query logs operation with pagination info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryLogsResponse {
    /// The log entries
    pub logs: Vec<DebugLog>,
    /// Number of entries returned
    pub count: usize,
    /// Whether there are more results available
    pub has_more: bool,
}

// ============================================================================
// Batch Insert Response
// ============================================================================

/// Response for batch insert operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchInsertResponse {
    /// Number of entries inserted
    pub count: usize,
}

// ============================================================================
// Delete Response
// ============================================================================

/// Response for delete operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteResponse {
    /// Number of entries deleted
    pub deleted: u64,
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_source_serialization() {
        assert_eq!(serde_json::to_string(&LogSource::Ios).unwrap(), "\"ios\"");
        assert_eq!(
            serde_json::to_string(&LogSource::Backend).unwrap(),
            "\"backend\""
        );
        assert_eq!(serde_json::to_string(&LogSource::Web).unwrap(), "\"web\"");
    }

    #[test]
    fn test_log_source_from_str() {
        assert_eq!("ios".parse::<LogSource>().unwrap(), LogSource::Ios);
        assert_eq!("backend".parse::<LogSource>().unwrap(), LogSource::Backend);
        assert_eq!("web".parse::<LogSource>().unwrap(), LogSource::Web);
        assert_eq!("IOS".parse::<LogSource>().unwrap(), LogSource::Ios);
        assert!("invalid".parse::<LogSource>().is_err());
    }

    #[test]
    fn test_log_level_serialization() {
        assert_eq!(
            serde_json::to_string(&LogLevel::Debug).unwrap(),
            "\"debug\""
        );
        assert_eq!(serde_json::to_string(&LogLevel::Info).unwrap(), "\"info\"");
        assert_eq!(serde_json::to_string(&LogLevel::Warn).unwrap(), "\"warn\"");
        assert_eq!(
            serde_json::to_string(&LogLevel::Error).unwrap(),
            "\"error\""
        );
    }

    #[test]
    fn test_log_level_from_str() {
        assert_eq!("debug".parse::<LogLevel>().unwrap(), LogLevel::Debug);
        assert_eq!("info".parse::<LogLevel>().unwrap(), LogLevel::Info);
        assert_eq!("warn".parse::<LogLevel>().unwrap(), LogLevel::Warn);
        assert_eq!("error".parse::<LogLevel>().unwrap(), LogLevel::Error);
        assert_eq!("ERROR".parse::<LogLevel>().unwrap(), LogLevel::Error);
        assert!("invalid".parse::<LogLevel>().is_err());
    }

    #[test]
    fn test_query_effective_limit() {
        let query = DebugLogQuery::default();
        assert_eq!(query.effective_limit(), 100);

        let query = DebugLogQuery {
            limit: Some(50),
            ..Default::default()
        };
        assert_eq!(query.effective_limit(), 50);

        let query = DebugLogQuery {
            limit: Some(5000),
            ..Default::default()
        };
        assert_eq!(query.effective_limit(), 1000);
    }

    #[test]
    fn test_query_is_ascending() {
        let query = DebugLogQuery::default();
        assert!(!query.is_ascending());

        let query = DebugLogQuery {
            order: Some("asc".to_string()),
            ..Default::default()
        };
        assert!(query.is_ascending());

        let query = DebugLogQuery {
            order: Some("desc".to_string()),
            ..Default::default()
        };
        assert!(!query.is_ascending());
    }

    #[test]
    fn test_query_validation() {
        let query = DebugLogQuery::default();
        assert!(query.validate().is_ok());

        let query = DebugLogQuery {
            source: Some("ios".to_string()),
            level: Some("error".to_string()),
            order: Some("desc".to_string()),
            ..Default::default()
        };
        assert!(query.validate().is_ok());

        let query = DebugLogQuery {
            source: Some("invalid".to_string()),
            ..Default::default()
        };
        assert!(query.validate().is_err());

        let query = DebugLogQuery {
            order: Some("invalid".to_string()),
            ..Default::default()
        };
        assert!(query.validate().is_err());
    }

    #[test]
    fn test_delete_validation() {
        let delete = DebugLogDelete::default();
        assert!(delete.validate().is_ok());

        let delete = DebugLogDelete {
            source: Some("invalid".to_string()),
            ..Default::default()
        };
        assert!(delete.validate().is_err());
    }

    #[test]
    fn test_create_debug_log_deserialization() {
        let json = r#"{
            "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
            "timestamp": "2024-01-01T12:00:00Z",
            "source": "ios",
            "level": "info",
            "event": "UPLOAD_REQUEST",
            "payload": {"size": 1024}
        }"#;

        let log: CreateDebugLog = serde_json::from_str(json).unwrap();
        assert_eq!(log.source, LogSource::Ios);
        assert_eq!(log.level, LogLevel::Info);
        assert_eq!(log.event, "UPLOAD_REQUEST");
        assert!(log.device_id.is_none());
    }

    #[test]
    fn test_stats_serialization() {
        let oldest = Utc::now() - chrono::Duration::hours(24);
        let newest = Utc::now();
        let stats = DebugLogStats {
            total: 100,
            by_source: SourceCounts {
                ios: 50,
                backend: 30,
                web: 20,
            },
            by_level: LevelCounts {
                debug: 10,
                info: 60,
                warn: 20,
                error: 10,
            },
            oldest: Some(oldest),
            newest: Some(newest),
        };

        let json = serde_json::to_string(&stats).unwrap();
        assert!(json.contains("\"total\":100"));
        assert!(json.contains("\"ios\":50"));
        assert!(json.contains("\"error\":10"));
        assert!(json.contains("\"oldest\":"));
        assert!(json.contains("\"newest\":"));
    }
}
