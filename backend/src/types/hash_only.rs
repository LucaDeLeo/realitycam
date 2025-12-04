//! Hash-only capture types (Story 8-4)
//!
//! Defines request and response types for hash-only (privacy mode) captures.
//! Hash-only captures allow clients to prove photo authenticity without
//! uploading the actual media to the server.
//!
//! ## Payload Structure
//! The `HashOnlyCapturePayload` matches the iOS `HashOnlyCapturePayload` from Story 8-3.
//! Key difference from full captures: JSON body (not multipart), no media files.
//!
//! ## Assertion Binding
//! For hash-only captures, the assertion's clientDataHash is computed from the
//! serialized JSON payload (excluding the assertion field itself).

use base64::Engine;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::ApiError;

// ============================================================================
// Enums
// ============================================================================

/// Capture mode discriminator
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CaptureMode {
    /// Full capture with media upload
    #[default]
    Full,
    /// Hash-only capture (privacy mode) - no media uploaded
    HashOnly,
}

impl std::fmt::Display for CaptureMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CaptureMode::Full => write!(f, "full"),
            CaptureMode::HashOnly => write!(f, "hash_only"),
        }
    }
}

impl std::str::FromStr for CaptureMode {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "full" => Ok(CaptureMode::Full),
            "hash_only" => Ok(CaptureMode::HashOnly),
            _ => Err(format!("Invalid capture mode: {s}")),
        }
    }
}

/// Source of depth analysis
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnalysisSource {
    /// Depth analysis performed on the server
    #[default]
    Server,
    /// Depth analysis performed on the client device
    Device,
}

impl std::fmt::Display for AnalysisSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AnalysisSource::Server => write!(f, "server"),
            AnalysisSource::Device => write!(f, "device"),
        }
    }
}

// ============================================================================
// Request Structures
// ============================================================================

/// Hash-only capture request payload
///
/// Sent from iOS client when capturing in privacy mode.
/// Contains pre-computed depth analysis and filtered metadata.
/// No media files are included - only the hash of the media.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HashOnlyCapturePayload {
    /// Capture mode - must be "hash_only"
    pub capture_mode: String,

    /// SHA-256 hash of the media as hex string (64 characters)
    pub media_hash: String,

    /// Media type - "photo" for this story, "video" in Story 8-8
    pub media_type: String,

    /// Client-computed depth analysis results
    pub depth_analysis: ClientDepthAnalysis,

    /// Filtered metadata per privacy settings
    pub metadata: FilteredMetadata,

    /// Flags indicating what metadata was included
    pub metadata_flags: MetadataFlags,

    /// ISO8601 timestamp of when capture was taken
    pub captured_at: String,

    /// DCAppAttest assertion (Base64-encoded CBOR)
    /// Signs the hash of the serialized payload (excluding this field)
    pub assertion: String,

    // ========================================================================
    // Video-specific fields (Story 8-8)
    // ========================================================================
    /// Hash chain data for video captures
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hash_chain: Option<VideoHashChainData>,

    /// Temporal depth analysis for video captures (replaces depth_analysis for videos)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temporal_depth_analysis: Option<ClientTemporalDepthAnalysis>,

    /// Frame count for video captures
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frame_count: Option<i32>,

    /// Duration in milliseconds for video captures
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<i32>,
}

impl HashOnlyCapturePayload {
    /// Validates the hash-only capture payload
    ///
    /// Returns `Ok(())` if all validations pass, or an `ApiError::Validation` with
    /// a specific error message describing the first validation failure.
    pub fn validate(&self) -> Result<(), ApiError> {
        // AC 2.1: capture_mode must be "hash_only"
        if self.capture_mode != "hash_only" {
            return Err(ApiError::Validation(format!(
                "capture_mode must be 'hash_only', got '{}'",
                self.capture_mode
            )));
        }

        // AC 2.2: media_hash must be valid SHA-256 hex string (64 characters)
        if self.media_hash.len() != 64 {
            return Err(ApiError::Validation(format!(
                "media_hash must be 64 hex characters, got {} characters",
                self.media_hash.len()
            )));
        }
        if !self.media_hash.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(ApiError::Validation(
                "media_hash must contain only hexadecimal characters".to_string(),
            ));
        }

        // AC 2.3: media_type must be "photo" or "video" (Story 8-8 added video support)
        if self.media_type != "photo" && self.media_type != "video" {
            return Err(ApiError::Validation(format!(
                "media_type must be 'photo' or 'video', got '{}'",
                self.media_type
            )));
        }

        // Video-specific validation (Story 8-8)
        if self.media_type == "video" {
            // Video must have hash_chain, frame_count, and duration_ms
            if self.hash_chain.is_none() {
                return Err(ApiError::Validation(
                    "video captures require hash_chain data".to_string(),
                ));
            }
            if self.frame_count.is_none() {
                return Err(ApiError::Validation(
                    "video captures require frame_count".to_string(),
                ));
            }
            if self.duration_ms.is_none() {
                return Err(ApiError::Validation(
                    "video captures require duration_ms".to_string(),
                ));
            }
            // Validate frame count and duration are positive
            if let Some(fc) = self.frame_count {
                if fc <= 0 {
                    return Err(ApiError::Validation(
                        "frame_count must be positive".to_string(),
                    ));
                }
            }
            if let Some(dur) = self.duration_ms {
                if dur <= 0 {
                    return Err(ApiError::Validation(
                        "duration_ms must be positive".to_string(),
                    ));
                }
            }
        }

        // AC 2.4: depth_analysis must have all required fields (validated by struct)
        self.depth_analysis.validate()?;

        // AC 2.7: captured_at must be valid ISO8601 timestamp
        if chrono::DateTime::parse_from_rfc3339(&self.captured_at).is_err() {
            return Err(ApiError::Validation(format!(
                "captured_at must be valid ISO8601 timestamp, got '{}'",
                self.captured_at
            )));
        }

        // AC 2.8: assertion must be non-empty Base64 string
        if self.assertion.trim().is_empty() {
            return Err(ApiError::Validation(
                "assertion must be non-empty".to_string(),
            ));
        }
        // Validate base64 can be decoded
        if base64::engine::general_purpose::STANDARD
            .decode(&self.assertion)
            .is_err()
        {
            return Err(ApiError::Validation(
                "assertion must be valid Base64".to_string(),
            ));
        }

        Ok(())
    }

    /// Parses captured_at as DateTime<Utc>
    pub fn captured_at_datetime(&self) -> Result<chrono::DateTime<chrono::Utc>, ApiError> {
        chrono::DateTime::parse_from_rfc3339(&self.captured_at)
            .map(|dt| dt.with_timezone(&chrono::Utc))
            .map_err(|e| ApiError::Validation(format!("Invalid captured_at timestamp: {e}")))
    }

    /// Converts media_hash hex string to bytes
    pub fn media_hash_bytes(&self) -> Result<Vec<u8>, ApiError> {
        hex::decode(&self.media_hash)
            .map_err(|e| ApiError::Validation(format!("Invalid media_hash hex: {e}")))
    }
}

/// Client-computed depth analysis from the iOS device
///
/// Matches the `DepthAnalysisResult` struct from iOS Story 8-3.
/// Contains the same fields as server-side depth analysis for consistency.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClientDepthAnalysis {
    /// Variance in depth values (higher = more 3D structure)
    pub depth_variance: f32,

    /// Number of distinct depth layers detected
    pub depth_layers: i32,

    /// Edge coherence score (0.0 - 1.0)
    pub edge_coherence: f32,

    /// Minimum depth value in meters
    pub min_depth: f32,

    /// Maximum depth value in meters
    pub max_depth: f32,

    /// Whether the scene is likely real (not a flat image)
    pub is_likely_real_scene: bool,

    /// Algorithm version for future compatibility
    pub algorithm_version: String,
}

impl ClientDepthAnalysis {
    /// Validates the depth analysis fields
    pub fn validate(&self) -> Result<(), ApiError> {
        // Validate algorithm_version format (e.g., "1.0" or "1.0.0")
        if self.algorithm_version.is_empty() {
            return Err(ApiError::Validation(
                "depth_analysis.algorithm_version must not be empty".to_string(),
            ));
        }

        // Validate ranges
        if self.depth_layers < 0 {
            return Err(ApiError::Validation(
                "depth_analysis.depth_layers must be non-negative".to_string(),
            ));
        }

        if !(0.0..=1.0).contains(&self.edge_coherence) {
            return Err(ApiError::Validation(
                "depth_analysis.edge_coherence must be between 0.0 and 1.0".to_string(),
            ));
        }

        Ok(())
    }
}

/// Filtered metadata based on privacy settings
///
/// Contains only the metadata fields the user chose to include.
/// All fields are optional because any can be excluded by privacy settings.
#[derive(Debug, Clone, Deserialize, Serialize, Default)]
pub struct FilteredMetadata {
    /// Location data (optional, can be precise or coarse)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location: Option<FilteredLocation>,

    /// Timestamp (optional, can be exact or day-only)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timestamp: Option<String>,

    /// Device model (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_model: Option<String>,
}

/// Location data with precision based on privacy settings
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FilteredLocation {
    /// Latitude (may be coarsened)
    pub latitude: f64,

    /// Longitude (may be coarsened)
    pub longitude: f64,

    /// Altitude in meters (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub altitude: Option<f64>,

    /// Accuracy in meters (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub accuracy: Option<f64>,
}

/// Flags indicating what metadata was included in the capture
///
/// Stored in the database to track privacy choices for audit/display.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct MetadataFlags {
    /// Whether location is included
    pub location_included: bool,

    /// Location precision level: "none", "coarse", "precise"
    pub location_level: String,

    /// Whether timestamp is included
    pub timestamp_included: bool,

    /// Timestamp precision level: "none", "day_only", "exact"
    pub timestamp_level: String,

    /// Whether device info is included
    pub device_info_included: bool,

    /// Device info level: "none", "model_only", "full"
    pub device_info_level: String,
}

// ============================================================================
// Video-specific Types (Story 8-8)
// ============================================================================

/// Hash chain data for video integrity verification in privacy mode.
///
/// Contains a summary of the frame hash chain for video verification.
/// Sent with video hash-only captures to prove temporal integrity.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct VideoHashChainData {
    /// Final hash of the hash chain (SHA-256 hex)
    pub final_hash: String,

    /// Number of frame hashes in the chain
    pub chain_length: i32,

    /// Hash chain algorithm version
    #[serde(default = "default_version")]
    pub version: String,

    /// Number of checkpoint attestations included
    #[serde(default)]
    pub checkpoint_count: i32,
}

fn default_version() -> String {
    "1.0".to_string()
}

/// Client-computed temporal depth analysis for video privacy mode.
///
/// Contains per-keyframe analyses and aggregate temporal metrics.
/// Matches the iOS TemporalDepthAnalysisResult structure.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClientTemporalDepthAnalysis {
    /// Per-keyframe depth analysis results (typically 10fps = ~150 keyframes for 15s video)
    #[serde(default)]
    pub keyframe_analyses: Vec<ClientDepthAnalysis>,

    /// Mean depth variance across all keyframes (meters)
    pub mean_variance: f32,

    /// Variance stability score (0.0 - 1.0+)
    /// Formula: 1.0 - (stddev(variances) / mean(variances))
    pub variance_stability: f32,

    /// Temporal edge coherence score (0.0 - 1.0)
    /// Average edge coherence across all keyframes
    pub temporal_coherence: f32,

    /// Final temporal authenticity determination
    /// Requires: all keyframes pass AND variance_stability > 0.8
    pub is_likely_real_scene: bool,

    /// Number of keyframes analyzed
    pub keyframe_count: i32,

    /// Algorithm version for server compatibility
    pub algorithm_version: String,
}

impl ClientTemporalDepthAnalysis {
    /// Validates the temporal depth analysis fields
    pub fn validate(&self) -> Result<(), ApiError> {
        if self.algorithm_version.is_empty() {
            return Err(ApiError::Validation(
                "temporal_depth_analysis.algorithm_version must not be empty".to_string(),
            ));
        }

        if self.keyframe_count < 0 {
            return Err(ApiError::Validation(
                "temporal_depth_analysis.keyframe_count must be non-negative".to_string(),
            ));
        }

        // Validate variance_stability is reasonable (can exceed 1.0 in edge cases)
        if self.variance_stability < 0.0 {
            return Err(ApiError::Validation(
                "temporal_depth_analysis.variance_stability must be non-negative".to_string(),
            ));
        }

        if !(0.0..=1.0).contains(&self.temporal_coherence) {
            return Err(ApiError::Validation(
                "temporal_depth_analysis.temporal_coherence must be between 0.0 and 1.0"
                    .to_string(),
            ));
        }

        Ok(())
    }
}

// ============================================================================
// Response Structures
// ============================================================================

/// Response for successful hash-only capture upload
///
/// Returned with HTTP 202 Accepted when a hash-only capture is processed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashOnlyCaptureResponse {
    /// Unique ID for the capture record
    pub capture_id: Uuid,

    /// Processing status - always "complete" for hash-only (no async processing)
    pub status: String,

    /// Capture mode - always "hash_only" for this endpoint
    pub capture_mode: String,

    /// Whether media is stored on server - always false for hash-only
    pub media_stored: bool,

    /// URL for public verification page
    pub verification_url: String,
}

// ============================================================================
// Database Insert Params
// ============================================================================

/// Parameters for inserting a hash-only capture into the database
#[derive(Debug)]
pub struct InsertHashOnlyCaptureParams {
    /// Generated capture ID
    pub capture_id: Uuid,

    /// Device ID from DeviceContext
    pub device_id: Uuid,

    /// SHA-256 hash of the media (bytes)
    pub target_media_hash: Vec<u8>,

    /// When the capture was taken
    pub captured_at: chrono::DateTime<chrono::Utc>,

    /// Evidence package as JSON
    pub evidence: serde_json::Value,

    /// Calculated confidence level
    pub confidence_level: String,

    /// Metadata flags JSON
    pub metadata_flags: serde_json::Value,

    /// Optional coarse location from filtered metadata
    pub location_coarse: Option<String>,
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    use chrono::Datelike;

    fn valid_payload() -> HashOnlyCapturePayload {
        HashOnlyCapturePayload {
            capture_mode: "hash_only".to_string(),
            media_hash: "a".repeat(64),
            media_type: "photo".to_string(),
            depth_analysis: ClientDepthAnalysis {
                depth_variance: 0.5,
                depth_layers: 5,
                edge_coherence: 0.8,
                min_depth: 0.5,
                max_depth: 5.0,
                is_likely_real_scene: true,
                algorithm_version: "1.0".to_string(),
            },
            metadata: FilteredMetadata::default(),
            metadata_flags: MetadataFlags {
                location_included: false,
                location_level: "none".to_string(),
                timestamp_included: true,
                timestamp_level: "exact".to_string(),
                device_info_included: true,
                device_info_level: "model_only".to_string(),
            },
            captured_at: "2025-12-01T10:00:00Z".to_string(),
            assertion: STANDARD.encode("test-assertion"),
            hash_chain: None,
            temporal_depth_analysis: None,
            frame_count: None,
            duration_ms: None,
        }
    }

    fn valid_video_payload() -> HashOnlyCapturePayload {
        HashOnlyCapturePayload {
            capture_mode: "hash_only".to_string(),
            media_hash: "b".repeat(64),
            media_type: "video".to_string(),
            depth_analysis: ClientDepthAnalysis {
                depth_variance: 0.5,
                depth_layers: 5,
                edge_coherence: 0.8,
                min_depth: 0.5,
                max_depth: 5.0,
                is_likely_real_scene: true,
                algorithm_version: "1.0".to_string(),
            },
            metadata: FilteredMetadata::default(),
            metadata_flags: MetadataFlags {
                location_included: false,
                location_level: "none".to_string(),
                timestamp_included: true,
                timestamp_level: "exact".to_string(),
                device_info_included: true,
                device_info_level: "model_only".to_string(),
            },
            captured_at: "2025-12-01T10:00:00Z".to_string(),
            assertion: STANDARD.encode("test-assertion"),
            hash_chain: Some(VideoHashChainData {
                final_hash: "c".repeat(64),
                chain_length: 450,
                version: "1.0".to_string(),
                checkpoint_count: 3,
            }),
            temporal_depth_analysis: Some(ClientTemporalDepthAnalysis {
                keyframe_analyses: vec![],
                mean_variance: 0.6,
                variance_stability: 0.9,
                temporal_coherence: 0.75,
                is_likely_real_scene: true,
                keyframe_count: 150,
                algorithm_version: "1.0".to_string(),
            }),
            frame_count: Some(450),
            duration_ms: Some(15000),
        }
    }

    #[test]
    fn test_valid_payload_passes_validation() {
        let payload = valid_payload();
        assert!(payload.validate().is_ok());
    }

    #[test]
    fn test_wrong_capture_mode_fails() {
        let mut payload = valid_payload();
        payload.capture_mode = "full".to_string();
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("capture_mode"));
    }

    #[test]
    fn test_invalid_media_hash_length_fails() {
        let mut payload = valid_payload();
        payload.media_hash = "abc123".to_string();
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("64 hex characters"));
    }

    #[test]
    fn test_invalid_media_hash_chars_fails() {
        let mut payload = valid_payload();
        payload.media_hash = "g".repeat(64); // 'g' is not hex
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("hexadecimal"));
    }

    #[test]
    fn test_wrong_media_type_fails() {
        let mut payload = valid_payload();
        payload.media_type = "audio".to_string(); // Not photo or video
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("media_type"));
    }

    #[test]
    fn test_valid_video_payload_passes_validation() {
        let payload = valid_video_payload();
        assert!(payload.validate().is_ok());
    }

    #[test]
    fn test_video_missing_hash_chain_fails() {
        let mut payload = valid_video_payload();
        payload.hash_chain = None;
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("hash_chain"));
    }

    #[test]
    fn test_video_missing_frame_count_fails() {
        let mut payload = valid_video_payload();
        payload.frame_count = None;
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("frame_count"));
    }

    #[test]
    fn test_video_missing_duration_fails() {
        let mut payload = valid_video_payload();
        payload.duration_ms = None;
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("duration_ms"));
    }

    #[test]
    fn test_video_negative_frame_count_fails() {
        let mut payload = valid_video_payload();
        payload.frame_count = Some(-1);
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("frame_count must be positive"));
    }

    #[test]
    fn test_video_negative_duration_fails() {
        let mut payload = valid_video_payload();
        payload.duration_ms = Some(-100);
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("duration_ms must be positive"));
    }

    #[test]
    fn test_invalid_timestamp_fails() {
        let mut payload = valid_payload();
        payload.captured_at = "not-a-timestamp".to_string();
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("captured_at"));
    }

    #[test]
    fn test_empty_assertion_fails() {
        let mut payload = valid_payload();
        payload.assertion = "".to_string();
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("assertion"));
    }

    #[test]
    fn test_whitespace_assertion_fails() {
        let mut payload = valid_payload();
        payload.assertion = "   ".to_string();
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("assertion"));
    }

    #[test]
    fn test_invalid_base64_assertion_fails() {
        let mut payload = valid_payload();
        payload.assertion = "not-valid-base64!!!".to_string();
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("Base64"));
    }

    #[test]
    fn test_empty_algorithm_version_fails() {
        let mut payload = valid_payload();
        payload.depth_analysis.algorithm_version = "".to_string();
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("algorithm_version"));
    }

    #[test]
    fn test_negative_depth_layers_fails() {
        let mut payload = valid_payload();
        payload.depth_analysis.depth_layers = -1;
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("depth_layers"));
    }

    #[test]
    fn test_edge_coherence_out_of_range_fails() {
        let mut payload = valid_payload();
        payload.depth_analysis.edge_coherence = 1.5;
        let err = payload.validate().unwrap_err();
        assert!(err.to_string().contains("edge_coherence"));
    }

    #[test]
    fn test_media_hash_bytes_conversion() {
        let payload = valid_payload();
        let bytes = payload.media_hash_bytes().unwrap();
        assert_eq!(bytes.len(), 32); // SHA-256 = 32 bytes
    }

    #[test]
    fn test_captured_at_datetime_parsing() {
        let payload = valid_payload();
        let dt = payload.captured_at_datetime().unwrap();
        assert_eq!(dt.year(), 2025);
        assert_eq!(dt.month(), 12);
    }

    #[test]
    fn test_capture_mode_display() {
        assert_eq!(CaptureMode::Full.to_string(), "full");
        assert_eq!(CaptureMode::HashOnly.to_string(), "hash_only");
    }

    #[test]
    fn test_capture_mode_from_str() {
        assert_eq!("full".parse::<CaptureMode>().unwrap(), CaptureMode::Full);
        assert_eq!(
            "hash_only".parse::<CaptureMode>().unwrap(),
            CaptureMode::HashOnly
        );
        assert!("invalid".parse::<CaptureMode>().is_err());
    }

    #[test]
    fn test_analysis_source_display() {
        assert_eq!(AnalysisSource::Server.to_string(), "server");
        assert_eq!(AnalysisSource::Device.to_string(), "device");
    }

    #[test]
    fn test_hash_only_response_serialization() {
        let response = HashOnlyCaptureResponse {
            capture_id: Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap(),
            status: "complete".to_string(),
            capture_mode: "hash_only".to_string(),
            media_stored: false,
            verification_url: "https://example.com/verify/123".to_string(),
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"status\":\"complete\""));
        assert!(json.contains("\"capture_mode\":\"hash_only\""));
        assert!(json.contains("\"media_stored\":false"));
    }

    #[test]
    fn test_metadata_flags_serialization() {
        let flags = MetadataFlags {
            location_included: true,
            location_level: "coarse".to_string(),
            timestamp_included: true,
            timestamp_level: "exact".to_string(),
            device_info_included: false,
            device_info_level: "none".to_string(),
        };

        let json = serde_json::to_value(&flags).unwrap();
        assert_eq!(json["location_included"], true);
        assert_eq!(json["location_level"], "coarse");
    }
}
