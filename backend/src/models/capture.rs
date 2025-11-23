//! Capture entity model
//!
//! Represents a photo capture with verification evidence and confidence scoring.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A photo capture with verification evidence and confidence scoring.
///
/// Captures store the hash of the original media, optional depth map,
/// and accumulated evidence from various verification checks.
#[derive(Debug, sqlx::FromRow, Serialize, Deserialize)]
pub struct Capture {
    /// Unique identifier for the capture
    pub id: Uuid,

    /// ID of the device that created this capture
    pub device_id: Uuid,

    /// SHA-256 hash of the original media file
    pub target_media_hash: Vec<u8>,

    /// S3 object key for the stored photo (Story 4.1)
    pub photo_s3_key: String,

    /// S3 object key for the stored depth map (Story 4.1)
    pub depth_map_s3_key: String,

    /// S3 object key for the thumbnail (optional, generated later)
    pub thumbnail_s3_key: Option<String>,

    /// JSONB evidence from verification checks
    pub evidence: serde_json::Value,

    /// Computed confidence level: "low", "medium", "high", or "verified"
    pub confidence_level: String,

    /// Processing status: "pending", "processing", "completed", "failed"
    pub status: String,

    /// Precise location data as JSONB (optional)
    pub location_precise: Option<serde_json::Value>,

    /// Coarse location (city/region) for privacy (optional)
    pub location_coarse: Option<String>,

    /// When the photo was originally captured
    pub captured_at: DateTime<Utc>,

    /// When the capture was uploaded to the server
    pub uploaded_at: DateTime<Utc>,
}

/// Parameters for creating a new capture record
#[derive(Debug)]
pub struct CreateCaptureParams {
    /// Device ID from DeviceContext
    pub device_id: Uuid,
    /// SHA-256 hash of the photo (raw bytes)
    pub target_media_hash: Vec<u8>,
    /// S3 key for the photo
    pub photo_s3_key: String,
    /// S3 key for the depth map
    pub depth_map_s3_key: String,
    /// When the capture was taken
    pub captured_at: DateTime<Utc>,
    /// Optional precise location
    pub location_precise: Option<serde_json::Value>,
}
