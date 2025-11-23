//! Capture entity model
//!
//! Represents a photo capture with verification evidence and confidence scoring.

use chrono::{DateTime, Utc};
use serde::Serialize;
use uuid::Uuid;

/// A photo capture with verification evidence and confidence scoring.
///
/// Captures store the hash of the original media, optional depth map,
/// and accumulated evidence from various verification checks.
#[derive(Debug, sqlx::FromRow, Serialize)]
pub struct Capture {
    /// Unique identifier for the capture
    pub id: Uuid,

    /// ID of the device that created this capture
    pub device_id: Uuid,

    /// SHA-256 hash of the original media file
    pub target_media_hash: Vec<u8>,

    /// S3 object key for the stored depth map (if available)
    pub depth_map_key: Option<String>,

    /// JSONB evidence from verification checks
    pub evidence: serde_json::Value,

    /// Computed confidence level: "low", "medium", "high", or "verified"
    pub confidence_level: String,

    /// Processing status: "pending", "processing", "completed", "failed"
    pub status: String,

    /// When the photo was originally captured
    pub captured_at: DateTime<Utc>,

    /// When the capture was uploaded to the server
    pub uploaded_at: DateTime<Utc>,
}
