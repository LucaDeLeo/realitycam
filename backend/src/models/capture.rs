//! Capture entity model
//!
//! Represents a photo or video capture with verification evidence and confidence scoring.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Capture type discriminator
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "varchar", rename_all = "lowercase")]
pub enum CaptureType {
    /// Photo capture (default)
    #[serde(rename = "photo")]
    Photo,
    /// Video capture with depth keyframes
    #[serde(rename = "video")]
    Video,
}

impl Default for CaptureType {
    fn default() -> Self {
        Self::Photo
    }
}

impl std::fmt::Display for CaptureType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CaptureType::Photo => write!(f, "photo"),
            CaptureType::Video => write!(f, "video"),
        }
    }
}

impl std::str::FromStr for CaptureType {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "photo" => Ok(CaptureType::Photo),
            "video" => Ok(CaptureType::Video),
            _ => Err(format!("Invalid capture type: {s}")),
        }
    }
}

/// A photo or video capture with verification evidence and confidence scoring.
///
/// Captures store the hash of the original media, optional depth map,
/// and accumulated evidence from various verification checks.
///
/// The `capture_type` field discriminates between photo and video captures,
/// with video captures using additional fields for video-specific storage.
#[derive(Debug, sqlx::FromRow, Serialize, Deserialize)]
pub struct Capture {
    /// Unique identifier for the capture
    pub id: Uuid,

    /// ID of the device that created this capture
    pub device_id: Uuid,

    /// SHA-256 hash of the original media file
    pub target_media_hash: Vec<u8>,

    /// S3 object key for the stored photo (Story 4.1)
    /// Nullable for backward compatibility with pre-migration captures
    pub photo_s3_key: Option<String>,

    /// S3 object key for the stored depth map (Story 4.1)
    /// Nullable for backward compatibility with pre-migration captures
    pub depth_map_s3_key: Option<String>,

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

    // ========================================================================
    // Video-specific fields (Story 7-8)
    // ========================================================================
    /// Capture type: "photo" (default) or "video"
    #[sqlx(default)]
    pub capture_type: Option<String>,

    /// S3 object key for the video file (video captures only)
    pub video_s3_key: Option<String>,

    /// S3 object key for the hash chain JSON (video captures only)
    pub hash_chain_s3_key: Option<String>,

    /// Video duration in milliseconds (video captures only)
    pub duration_ms: Option<i64>,

    /// Total frames in the video (video captures only)
    pub frame_count: Option<i32>,

    /// Whether this is a partial (interrupted) recording (video captures only)
    pub is_partial: Option<bool>,

    /// Latest verified checkpoint index (video captures only)
    pub checkpoint_index: Option<i32>,

    // ========================================================================
    // Hash-only (privacy mode) fields (Story 8-4, 8-5)
    // ========================================================================
    /// Capture mode: "full" (default) or "hash_only"
    pub capture_mode: Option<String>,

    /// Whether media files are stored on server (false for hash-only)
    pub media_stored: Option<bool>,

    /// Source of depth analysis: "server" (default) or "device"
    pub analysis_source: Option<String>,

    /// Privacy metadata flags (JSONB)
    pub metadata_flags: Option<serde_json::Value>,
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

/// Parameters for creating a new video capture record (Story 7-8)
///
/// MED-1: Currently unused - video capture creation is done inline in
/// captures_video.rs::insert_video_capture(). This struct is defined for
/// future refactoring to align with CreateCaptureParams pattern when the
/// video upload flow matures. Consider using this struct in Stories 7-9/7-10
/// when implementing video verification pipeline.
#[derive(Debug)]
#[allow(dead_code)]
pub struct CreateVideoCaptureParams {
    /// Unique capture ID (generated before S3 upload)
    pub capture_id: Uuid,
    /// Device ID from DeviceContext
    pub device_id: Uuid,
    /// S3 key for the video file
    pub video_s3_key: String,
    /// S3 key for the depth keyframes
    pub depth_s3_key: String,
    /// S3 key for the hash chain JSON
    pub hash_chain_s3_key: String,
    /// When the capture started
    pub captured_at: DateTime<Utc>,
    /// Optional precise location
    pub location_precise: Option<serde_json::Value>,
    /// Duration in milliseconds
    pub duration_ms: i64,
    /// Total frame count
    pub frame_count: i32,
    /// Whether recording was interrupted
    pub is_partial: bool,
}
