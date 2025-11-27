//! Video capture upload request/response types (Story 7-8)
//!
//! Defines types for the POST /api/v1/captures/video endpoint including:
//! - VideoUploadMetadata: JSON metadata payload from multipart form
//! - VideoUploadResponse: Response with capture_id, type, status, verification_url
//! - HashCheckpoint: Attestation checkpoint within the hash chain
//! - Size validation helpers for video-specific constraints

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::ApiError;
use crate::types::capture::CaptureLocation;

// ============================================================================
// Constants
// ============================================================================

/// Maximum video file size: 100MB (allows 4K 15s video worst case)
pub const MAX_VIDEO_SIZE: usize = 100 * 1024 * 1024;

/// Maximum depth data file size: 20MB (compressed keyframes)
pub const MAX_VIDEO_DEPTH_SIZE: usize = 20 * 1024 * 1024;

/// Maximum hash chain JSON size: 1MB (up to 450 hashes + checkpoints)
pub const MAX_HASH_CHAIN_SIZE: usize = 1024 * 1024;

/// Maximum metadata JSON size: 100KB
pub const MAX_VIDEO_METADATA_SIZE: usize = 100 * 1024;

/// Maximum videos per hour per device (rate limit)
pub const VIDEO_RATE_LIMIT_PER_HOUR: i64 = 5;

// ============================================================================
// Request Types
// ============================================================================

/// Video resolution dimensions
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Resolution {
    pub width: u32,
    pub height: u32,
}

/// Hash checkpoint for attestation verification
///
/// Checkpoints are created at regular intervals during video recording
/// to provide attestation points for integrity verification.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HashCheckpoint {
    /// Checkpoint index (sequential, 0-based)
    pub index: u32,
    /// Frame number at this checkpoint
    pub frame_number: u32,
    /// Cumulative hash at this point (Base64)
    pub hash: String,
    /// Timestamp within video (seconds)
    pub timestamp: f64,
}

/// Metadata JSON payload from the multipart form "metadata" field
///
/// Contains all video capture metadata including attestation information.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct VideoUploadMetadata {
    /// When the video capture started (ISO 8601)
    pub started_at: String,
    /// When the video capture ended (ISO 8601)
    pub ended_at: String,
    /// Video duration in milliseconds
    pub duration_ms: u64,
    /// Total frame count (typically 30fps)
    pub frame_count: u32,
    /// Number of depth keyframes (typically 10fps)
    pub depth_keyframe_count: u32,
    /// Video resolution
    pub resolution: Resolution,
    /// Video codec: "h264" or "hevc"
    pub codec: String,
    /// Device model (e.g., "iPhone 15 Pro")
    pub device_model: String,
    /// Capture location (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location: Option<CaptureLocation>,
    /// Attestation level achieved: "none", "basic", "full"
    pub attestation_level: String,
    /// Final hash of the complete hash chain (Base64)
    pub hash_chain_final: String,
    /// DCAppAttest assertion for final checkpoint (Base64)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assertion: Option<String>,
    /// Attestation checkpoints within the video
    #[serde(default)]
    pub checkpoints: Vec<HashCheckpoint>,
    /// Whether this is a partial (interrupted) recording
    #[serde(default)]
    pub is_partial: bool,
}

impl VideoUploadMetadata {
    /// Validates all metadata fields
    pub fn validate(&self) -> Result<(), ApiError> {
        self.validate_timestamps()?;
        self.validate_duration()?;
        self.validate_frame_counts()?;
        self.validate_resolution()?;
        self.validate_codec()?;
        self.validate_device_model()?;
        self.validate_hash_chain_final()?;
        self.validate_checkpoints()?;
        self.validate_location()?;
        Ok(())
    }

    fn validate_timestamps(&self) -> Result<(), ApiError> {
        if self.started_at.is_empty() {
            return Err(ApiError::Validation("started_at is required".to_string()));
        }
        if self.ended_at.is_empty() {
            return Err(ApiError::Validation("ended_at is required".to_string()));
        }

        // Parse timestamps
        let start = DateTime::parse_from_rfc3339(&self.started_at).map_err(|_| {
            ApiError::Validation(format!(
                "started_at must be a valid ISO 8601 timestamp, got: {}",
                self.started_at
            ))
        })?;

        let end = DateTime::parse_from_rfc3339(&self.ended_at).map_err(|_| {
            ApiError::Validation(format!(
                "ended_at must be a valid ISO 8601 timestamp, got: {}",
                self.ended_at
            ))
        })?;

        // Validate order
        if end < start {
            return Err(ApiError::Validation(
                "ended_at must be after started_at".to_string(),
            ));
        }

        Ok(())
    }

    fn validate_duration(&self) -> Result<(), ApiError> {
        if self.duration_ms == 0 {
            return Err(ApiError::Validation(
                "duration_ms must be greater than 0".to_string(),
            ));
        }

        // Maximum 15 seconds = 15000ms (with some buffer for timing variations)
        if self.duration_ms > 20000 {
            return Err(ApiError::Validation(format!(
                "duration_ms exceeds maximum of 20000ms, got: {}",
                self.duration_ms
            )));
        }

        Ok(())
    }

    fn validate_frame_counts(&self) -> Result<(), ApiError> {
        if self.frame_count == 0 {
            return Err(ApiError::Validation(
                "frame_count must be greater than 0".to_string(),
            ));
        }

        // Maximum ~450 frames for 15s @ 30fps (with buffer)
        if self.frame_count > 600 {
            return Err(ApiError::Validation(format!(
                "frame_count exceeds maximum of 600, got: {}",
                self.frame_count
            )));
        }

        if self.depth_keyframe_count == 0 {
            return Err(ApiError::Validation(
                "depth_keyframe_count must be greater than 0".to_string(),
            ));
        }

        // Maximum ~150 depth keyframes for 15s @ 10fps (with buffer)
        if self.depth_keyframe_count > 200 {
            return Err(ApiError::Validation(format!(
                "depth_keyframe_count exceeds maximum of 200, got: {}",
                self.depth_keyframe_count
            )));
        }

        Ok(())
    }

    fn validate_resolution(&self) -> Result<(), ApiError> {
        if self.resolution.width == 0 || self.resolution.height == 0 {
            return Err(ApiError::Validation(
                "resolution width and height must be > 0".to_string(),
            ));
        }

        // Maximum 4K resolution
        if self.resolution.width > 4096 || self.resolution.height > 4096 {
            return Err(ApiError::Validation(format!(
                "resolution exceeds maximum of 4096x4096, got: {}x{}",
                self.resolution.width, self.resolution.height
            )));
        }

        Ok(())
    }

    fn validate_codec(&self) -> Result<(), ApiError> {
        let valid_codecs = ["h264", "hevc", "H264", "HEVC"];
        if !valid_codecs.contains(&self.codec.as_str()) {
            return Err(ApiError::Validation(format!(
                "codec must be 'h264' or 'hevc', got: {}",
                self.codec
            )));
        }
        Ok(())
    }

    fn validate_device_model(&self) -> Result<(), ApiError> {
        if self.device_model.trim().is_empty() {
            return Err(ApiError::Validation(
                "device_model is required and cannot be empty".to_string(),
            ));
        }
        Ok(())
    }

    fn validate_hash_chain_final(&self) -> Result<(), ApiError> {
        if self.hash_chain_final.trim().is_empty() {
            return Err(ApiError::Validation(
                "hash_chain_final is required and cannot be empty".to_string(),
            ));
        }

        // Validate base64 format
        use base64::{engine::general_purpose::STANDARD, Engine as _};
        STANDARD.decode(&self.hash_chain_final).map_err(|_| {
            ApiError::Validation("hash_chain_final must be valid base64".to_string())
        })?;

        Ok(())
    }

    fn validate_checkpoints(&self) -> Result<(), ApiError> {
        // Checkpoints are optional for partial recordings
        if self.checkpoints.is_empty() && !self.is_partial {
            tracing::warn!("Video upload missing checkpoints - attestation may be limited");
        }

        // Validate checkpoint ordering
        let mut prev_index = None;
        for cp in &self.checkpoints {
            if let Some(prev) = prev_index {
                if cp.index <= prev {
                    return Err(ApiError::Validation(
                        "checkpoints must be in ascending index order".to_string(),
                    ));
                }
            }
            prev_index = Some(cp.index);

            // Validate hash is base64
            use base64::{engine::general_purpose::STANDARD, Engine as _};
            STANDARD.decode(&cp.hash).map_err(|_| {
                ApiError::Validation(format!("checkpoint {} hash must be valid base64", cp.index))
            })?;
        }

        Ok(())
    }

    fn validate_location(&self) -> Result<(), ApiError> {
        if let Some(ref loc) = self.location {
            if loc.latitude < -90.0 || loc.latitude > 90.0 {
                return Err(ApiError::Validation(format!(
                    "latitude must be between -90 and 90, got {}",
                    loc.latitude
                )));
            }
            if loc.longitude < -180.0 || loc.longitude > 180.0 {
                return Err(ApiError::Validation(format!(
                    "longitude must be between -180 and 180, got {}",
                    loc.longitude
                )));
            }
        }
        Ok(())
    }

    /// Parses the started_at timestamp into a DateTime<Utc>
    pub fn started_at_datetime(&self) -> Result<DateTime<Utc>, ApiError> {
        DateTime::parse_from_rfc3339(&self.started_at)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|_| {
                ApiError::Validation(format!(
                    "started_at must be a valid ISO 8601 timestamp, got: {}",
                    self.started_at
                ))
            })
    }

    /// Parses the ended_at timestamp into a DateTime<Utc>
    pub fn ended_at_datetime(&self) -> Result<DateTime<Utc>, ApiError> {
        DateTime::parse_from_rfc3339(&self.ended_at)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|_| {
                ApiError::Validation(format!(
                    "ended_at must be a valid ISO 8601 timestamp, got: {}",
                    self.ended_at
                ))
            })
    }
}

// ============================================================================
// Response Types
// ============================================================================

/// Response data for successful video capture upload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoUploadResponse {
    /// Unique capture identifier
    pub capture_id: Uuid,
    /// Capture type ("video")
    #[serde(rename = "type")]
    pub capture_type: String,
    /// Current processing status ("processing")
    pub status: String,
    /// URL to view verification results
    pub verification_url: String,
}

// ============================================================================
// Validation Functions
// ============================================================================

/// Validates video file size
pub fn validate_video_size(size: usize) -> Result<(), ApiError> {
    if size > MAX_VIDEO_SIZE {
        return Err(ApiError::PayloadTooLarge(format!(
            "video exceeds maximum size of {MAX_VIDEO_SIZE} bytes (got {size} bytes)"
        )));
    }
    if size == 0 {
        return Err(ApiError::Validation("video cannot be empty".to_string()));
    }
    Ok(())
}

/// Validates video depth data size
pub fn validate_video_depth_size(size: usize) -> Result<(), ApiError> {
    if size > MAX_VIDEO_DEPTH_SIZE {
        return Err(ApiError::PayloadTooLarge(format!(
            "depth_data exceeds maximum size of {MAX_VIDEO_DEPTH_SIZE} bytes (got {size} bytes)"
        )));
    }
    if size == 0 {
        return Err(ApiError::Validation(
            "depth_data cannot be empty".to_string(),
        ));
    }
    Ok(())
}

/// Validates hash chain JSON size
pub fn validate_hash_chain_size(size: usize) -> Result<(), ApiError> {
    if size > MAX_HASH_CHAIN_SIZE {
        return Err(ApiError::PayloadTooLarge(format!(
            "hash_chain exceeds maximum size of {MAX_HASH_CHAIN_SIZE} bytes (got {size} bytes)"
        )));
    }
    if size == 0 {
        return Err(ApiError::Validation(
            "hash_chain cannot be empty".to_string(),
        ));
    }
    Ok(())
}

/// Validates video metadata JSON size
pub fn validate_video_metadata_size(size: usize) -> Result<(), ApiError> {
    if size > MAX_VIDEO_METADATA_SIZE {
        return Err(ApiError::PayloadTooLarge(format!(
            "metadata exceeds maximum size of {MAX_VIDEO_METADATA_SIZE} bytes (got {size} bytes)"
        )));
    }
    if size == 0 {
        return Err(ApiError::Validation("metadata cannot be empty".to_string()));
    }
    Ok(())
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_metadata() -> VideoUploadMetadata {
        VideoUploadMetadata {
            started_at: "2025-11-27T10:00:00.000Z".to_string(),
            ended_at: "2025-11-27T10:00:15.000Z".to_string(),
            duration_ms: 15000,
            frame_count: 450,
            depth_keyframe_count: 150,
            resolution: Resolution {
                width: 1920,
                height: 1080,
            },
            codec: "h264".to_string(),
            device_model: "iPhone 15 Pro".to_string(),
            location: None,
            attestation_level: "full".to_string(),
            hash_chain_final: "dGVzdC1oYXNo".to_string(), // "test-hash" in base64
            assertion: None,
            checkpoints: vec![
                HashCheckpoint {
                    index: 0,
                    frame_number: 150,
                    hash: "dGVzdC1oYXNo".to_string(),
                    timestamp: 5.0,
                },
                HashCheckpoint {
                    index: 1,
                    frame_number: 300,
                    hash: "dGVzdC1oYXNo".to_string(),
                    timestamp: 10.0,
                },
            ],
            is_partial: false,
        }
    }

    #[test]
    fn test_valid_metadata() {
        let metadata = valid_metadata();
        assert!(metadata.validate().is_ok());
    }

    #[test]
    fn test_invalid_started_at_empty() {
        let mut metadata = valid_metadata();
        metadata.started_at = "".to_string();
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_ended_at_before_started() {
        let mut metadata = valid_metadata();
        metadata.ended_at = "2025-11-27T09:59:00.000Z".to_string();
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_duration_zero() {
        let mut metadata = valid_metadata();
        metadata.duration_ms = 0;
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_duration_too_long() {
        let mut metadata = valid_metadata();
        metadata.duration_ms = 25000;
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_frame_count_zero() {
        let mut metadata = valid_metadata();
        metadata.frame_count = 0;
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_resolution_zero() {
        let mut metadata = valid_metadata();
        metadata.resolution.width = 0;
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_codec() {
        let mut metadata = valid_metadata();
        metadata.codec = "vp9".to_string();
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_device_model_empty() {
        let mut metadata = valid_metadata();
        metadata.device_model = "".to_string();
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_hash_chain_final_empty() {
        let mut metadata = valid_metadata();
        metadata.hash_chain_final = "".to_string();
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_checkpoint_order() {
        let mut metadata = valid_metadata();
        metadata.checkpoints = vec![
            HashCheckpoint {
                index: 1,
                frame_number: 300,
                hash: "dGVzdC1oYXNo".to_string(),
                timestamp: 10.0,
            },
            HashCheckpoint {
                index: 0,
                frame_number: 150,
                hash: "dGVzdC1oYXNo".to_string(),
                timestamp: 5.0,
            },
        ];
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_valid_location() {
        let mut metadata = valid_metadata();
        metadata.location = Some(CaptureLocation {
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: Some(100.0),
            accuracy: Some(5.0),
        });
        assert!(metadata.validate().is_ok());
    }

    #[test]
    fn test_invalid_latitude() {
        let mut metadata = valid_metadata();
        metadata.location = Some(CaptureLocation {
            latitude: 91.0,
            longitude: 0.0,
            altitude: None,
            accuracy: None,
        });
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    // Size validation tests
    #[test]
    fn test_validate_video_size_valid() {
        assert!(validate_video_size(1024).is_ok());
        assert!(validate_video_size(MAX_VIDEO_SIZE).is_ok());
    }

    #[test]
    fn test_validate_video_size_too_large() {
        let result = validate_video_size(MAX_VIDEO_SIZE + 1);
        assert!(matches!(result, Err(ApiError::PayloadTooLarge(_))));
    }

    #[test]
    fn test_validate_video_size_empty() {
        let result = validate_video_size(0);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_video_depth_size_valid() {
        assert!(validate_video_depth_size(1024).is_ok());
        assert!(validate_video_depth_size(MAX_VIDEO_DEPTH_SIZE).is_ok());
    }

    #[test]
    fn test_validate_video_depth_size_too_large() {
        let result = validate_video_depth_size(MAX_VIDEO_DEPTH_SIZE + 1);
        assert!(matches!(result, Err(ApiError::PayloadTooLarge(_))));
    }

    #[test]
    fn test_validate_hash_chain_size_valid() {
        assert!(validate_hash_chain_size(1024).is_ok());
        assert!(validate_hash_chain_size(MAX_HASH_CHAIN_SIZE).is_ok());
    }

    #[test]
    fn test_validate_hash_chain_size_too_large() {
        let result = validate_hash_chain_size(MAX_HASH_CHAIN_SIZE + 1);
        assert!(matches!(result, Err(ApiError::PayloadTooLarge(_))));
    }

    #[test]
    fn test_validate_video_metadata_size_valid() {
        assert!(validate_video_metadata_size(1024).is_ok());
        assert!(validate_video_metadata_size(MAX_VIDEO_METADATA_SIZE).is_ok());
    }

    #[test]
    fn test_validate_video_metadata_size_too_large() {
        let result = validate_video_metadata_size(MAX_VIDEO_METADATA_SIZE + 1);
        assert!(matches!(result, Err(ApiError::PayloadTooLarge(_))));
    }

    #[test]
    fn test_started_at_datetime() {
        let metadata = valid_metadata();
        let dt = metadata.started_at_datetime();
        assert!(dt.is_ok());
    }

    #[test]
    fn test_ended_at_datetime() {
        let metadata = valid_metadata();
        let dt = metadata.ended_at_datetime();
        assert!(dt.is_ok());
    }

    #[test]
    fn test_video_upload_response_serialization() {
        let response = VideoUploadResponse {
            capture_id: Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap(),
            capture_type: "video".to_string(),
            status: "processing".to_string(),
            verification_url: "https://realitycam.app/verify/550e8400-e29b-41d4-a716-446655440000"
                .to_string(),
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains(r#""type":"video""#));
        assert!(json.contains(r#""status":"processing""#));
    }
}
