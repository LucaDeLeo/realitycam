//! Verification log entity model
//!
//! Represents a record of verification requests for audit trail.

use chrono::{DateTime, Utc};
use serde::Serialize;
use uuid::Uuid;

/// A verification log entry for audit trail.
///
/// Tracks all verification requests including the requesting client's
/// IP address and user agent for security and analytics purposes.
#[derive(Debug, sqlx::FromRow, Serialize)]
pub struct VerificationLog {
    /// Unique identifier for the log entry
    pub id: Uuid,

    /// ID of the capture being verified (if applicable)
    pub capture_id: Option<Uuid>,

    /// Type of action performed (e.g., "verify", "upload", "check")
    pub action: String,

    /// Client IP address (PostgreSQL INET type stored as String)
    pub client_ip: Option<String>,

    /// HTTP User-Agent header from the request
    pub user_agent: Option<String>,

    /// When the action occurred
    pub created_at: DateTime<Utc>,
}
