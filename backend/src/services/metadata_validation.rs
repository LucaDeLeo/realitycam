//! Metadata Validation Service (Story 4-6)
//!
//! Validates capture metadata including timestamp, device model, location, and resolution.
//! All validation is NON-BLOCKING - failures do not reject the upload.
//!
//! ## Validation Checks
//! 1. Timestamp: Within 15 minutes of server time
//! 2. Device Model: iPhone Pro whitelist (LiDAR-capable)
//! 3. Location: Valid GPS coordinate bounds
//! 4. Resolution: Known LiDAR depth map dimensions
//!
//! ## Thresholds (from Epic 4 Tech Spec AC-4.6)
//! - Timestamp window: 15 minutes (900 seconds)
//! - Valid latitude: -90 to 90
//! - Valid longitude: -180 to 180
//! - Valid resolutions: 256x192, 320x240, 640x480 (+/- 10px tolerance)

use chrono::{DateTime, Utc};
use tracing::{debug, info};

use crate::models::MetadataEvidence;
use crate::types::capture::{CaptureLocation, CaptureMetadataPayload};

// ============================================================================
// Configuration Constants
// ============================================================================

/// Maximum allowed timestamp delta in seconds (15 minutes)
const TIMESTAMP_WINDOW_SECONDS: i64 = 900;

/// Resolution tolerance in pixels (allow +/- 10 pixels per dimension)
const RESOLUTION_TOLERANCE: u32 = 10;

/// Known LiDAR depth map resolutions (width, height)
const VALID_RESOLUTIONS: &[(u32, u32)] = &[
    (256, 192),  // iPhone Pro LiDAR standard
    (320, 240),  // QVGA
    (640, 480),  // VGA
    (384, 288),  // Alternative resolution
];

/// iPhone Pro models with LiDAR capability
/// Using lowercase for case-insensitive matching
const IPHONE_PRO_WHITELIST: &[&str] = &[
    "iphone 12 pro",
    "iphone 12 pro max",
    "iphone 13 pro",
    "iphone 13 pro max",
    "iphone 14 pro",
    "iphone 14 pro max",
    "iphone 15 pro",
    "iphone 15 pro max",
    "iphone 16 pro",
    "iphone 16 pro max",
    "iphone 17 pro",      // Future-proofing
    "iphone 17 pro max",  // Future-proofing
];

// ============================================================================
// Validation Result Types
// ============================================================================

/// Result of timestamp validation
#[derive(Debug, Clone)]
pub struct TimestampValidation {
    /// Whether the timestamp is within acceptable bounds
    pub is_valid: bool,
    /// Delta in seconds (positive = captured in past, negative = future)
    pub delta_seconds: i64,
}

/// Result of device model verification
#[derive(Debug, Clone)]
pub struct ModelVerification {
    /// Whether the model is in the Pro whitelist
    pub is_verified: bool,
    /// The model name (cleaned up)
    pub model_name: String,
}

/// Result of location validation
#[derive(Debug, Clone)]
pub struct LocationValidation {
    /// Whether valid location data is available
    pub is_available: bool,
    /// Whether user opted out of location sharing
    pub opted_out: bool,
}

// ============================================================================
// Validation Functions
// ============================================================================

/// Validates the capture timestamp against server time
///
/// # Arguments
/// * `captured_at` - When the capture was taken (from metadata)
/// * `server_time` - Current server time
///
/// # Returns
/// TimestampValidation with validity and delta
pub fn validate_timestamp(
    captured_at: DateTime<Utc>,
    server_time: DateTime<Utc>,
) -> TimestampValidation {
    let delta = server_time.signed_duration_since(captured_at);
    let delta_seconds = delta.num_seconds();

    // Valid if within window (past or future)
    let is_valid = delta_seconds.abs() <= TIMESTAMP_WINDOW_SECONDS;

    debug!(
        captured_at = %captured_at,
        server_time = %server_time,
        delta_seconds = delta_seconds,
        is_valid = is_valid,
        "[metadata_validation] Timestamp validated"
    );

    TimestampValidation {
        is_valid,
        delta_seconds,
    }
}

/// Verifies the device model against iPhone Pro whitelist
///
/// Uses case-insensitive partial matching to handle various formats:
/// - "iPhone 15 Pro"
/// - "iPhone15Pro"
/// - "Apple iPhone 15 Pro Max"
///
/// # Arguments
/// * `model` - Device model string from metadata
///
/// # Returns
/// ModelVerification with verification result and cleaned model name
pub fn verify_device_model(model: &str) -> ModelVerification {
    let model_lower = model.to_lowercase();

    // Check if any whitelist entry is contained in the model string
    let is_verified = IPHONE_PRO_WHITELIST.iter().any(|&whitelist_model| {
        // Remove spaces for flexible matching
        let model_normalized = model_lower.replace(' ', "");
        let whitelist_normalized = whitelist_model.replace(' ', "");

        model_normalized.contains(&whitelist_normalized)
    });

    debug!(
        model = %model,
        is_verified = is_verified,
        "[metadata_validation] Device model verified"
    );

    ModelVerification {
        is_verified,
        model_name: model.to_string(),
    }
}

/// Validates GPS location coordinates
///
/// # Arguments
/// * `location` - Optional location from metadata
///
/// # Returns
/// LocationValidation with availability and opt-out status
pub fn validate_location(location: Option<&CaptureLocation>) -> LocationValidation {
    match location {
        Some(loc) => {
            // Validate coordinate bounds
            let lat_valid = (-90.0..=90.0).contains(&loc.latitude);
            let lng_valid = (-180.0..=180.0).contains(&loc.longitude);
            let is_available = lat_valid && lng_valid;

            debug!(
                latitude = loc.latitude,
                longitude = loc.longitude,
                lat_valid = lat_valid,
                lng_valid = lng_valid,
                is_available = is_available,
                "[metadata_validation] Location validated"
            );

            LocationValidation {
                is_available,
                opted_out: false,
            }
        }
        None => {
            debug!("[metadata_validation] No location provided - treating as opted out");
            LocationValidation {
                is_available: false,
                opted_out: true,
            }
        }
    }
}

/// Validates depth map resolution against known LiDAR formats
///
/// Allows tolerance of +/- 10 pixels per dimension to handle
/// device-specific variations.
///
/// # Arguments
/// * `width` - Depth map width in pixels
/// * `height` - Depth map height in pixels
///
/// # Returns
/// true if resolution matches a known format (within tolerance)
pub fn validate_resolution(width: u32, height: u32) -> bool {
    let is_valid = VALID_RESOLUTIONS.iter().any(|&(valid_w, valid_h)| {
        let width_match = width.abs_diff(valid_w) <= RESOLUTION_TOLERANCE;
        let height_match = height.abs_diff(valid_h) <= RESOLUTION_TOLERANCE;
        width_match && height_match
    });

    debug!(
        width = width,
        height = height,
        is_valid = is_valid,
        "[metadata_validation] Resolution validated"
    );

    is_valid
}

// ============================================================================
// Main Validation Orchestrator
// ============================================================================

/// Validates all capture metadata and returns MetadataEvidence
///
/// This is the main entry point for metadata validation. It:
/// 1. Validates timestamp against server time
/// 2. Verifies device model against whitelist
/// 3. Validates location coordinates
/// 4. Validates depth map resolution
///
/// # Arguments
/// * `metadata` - Capture metadata payload from upload
///
/// # Returns
/// MetadataEvidence struct with all validation results
pub fn validate_metadata(metadata: &CaptureMetadataPayload) -> MetadataEvidence {
    let server_time = Utc::now();

    info!(
        device_model = %metadata.device_model,
        has_location = metadata.location.is_some(),
        depth_width = metadata.depth_map_dimensions.width,
        depth_height = metadata.depth_map_dimensions.height,
        "[metadata_validation] Starting metadata validation"
    );

    // Parse captured_at timestamp
    let timestamp_result = match metadata.captured_at_datetime() {
        Ok(captured_at) => validate_timestamp(captured_at, server_time),
        Err(e) => {
            debug!(error = %e, "[metadata_validation] Failed to parse captured_at timestamp");
            TimestampValidation {
                is_valid: false,
                delta_seconds: 0,
            }
        }
    };

    // Verify device model
    let model_result = verify_device_model(&metadata.device_model);

    // Validate location
    let location_result = validate_location(metadata.location.as_ref());

    // Validate resolution
    let resolution_valid = validate_resolution(
        metadata.depth_map_dimensions.width,
        metadata.depth_map_dimensions.height,
    );

    info!(
        timestamp_valid = timestamp_result.is_valid,
        timestamp_delta = timestamp_result.delta_seconds,
        model_verified = model_result.is_verified,
        model_name = %model_result.model_name,
        resolution_valid = resolution_valid,
        location_available = location_result.is_available,
        location_opted_out = location_result.opted_out,
        "[metadata_validation] Metadata validation complete"
    );

    MetadataEvidence {
        timestamp_valid: timestamp_result.is_valid,
        timestamp_delta_seconds: timestamp_result.delta_seconds,
        model_verified: model_result.is_verified,
        model_name: model_result.model_name,
        resolution_valid,
        location_available: location_result.is_available,
        location_opted_out: location_result.opted_out,
        location_coarse: None, // Set by privacy controls (Story 4-8)
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;
    use crate::types::capture::DepthMapDimensions;

    // ========================================================================
    // Timestamp Validation Tests
    // ========================================================================

    #[test]
    fn test_timestamp_valid_recent() {
        let server_time = Utc::now();
        let captured_at = server_time - Duration::seconds(10);
        let result = validate_timestamp(captured_at, server_time);

        assert!(result.is_valid);
        assert_eq!(result.delta_seconds, 10);
    }

    #[test]
    fn test_timestamp_valid_at_boundary() {
        let server_time = Utc::now();
        let captured_at = server_time - Duration::seconds(900); // Exactly 15 minutes
        let result = validate_timestamp(captured_at, server_time);

        assert!(result.is_valid);
        assert_eq!(result.delta_seconds, 900);
    }

    #[test]
    fn test_timestamp_invalid_too_old() {
        let server_time = Utc::now();
        let captured_at = server_time - Duration::seconds(901); // Just over 15 minutes
        let result = validate_timestamp(captured_at, server_time);

        assert!(!result.is_valid);
        assert_eq!(result.delta_seconds, 901);
    }

    #[test]
    fn test_timestamp_valid_future_within_window() {
        let server_time = Utc::now();
        let captured_at = server_time + Duration::seconds(60); // 1 minute in future
        let result = validate_timestamp(captured_at, server_time);

        assert!(result.is_valid);
        assert_eq!(result.delta_seconds, -60);
    }

    #[test]
    fn test_timestamp_invalid_future_too_far() {
        let server_time = Utc::now();
        let captured_at = server_time + Duration::seconds(901); // Too far in future
        let result = validate_timestamp(captured_at, server_time);

        assert!(!result.is_valid);
        assert_eq!(result.delta_seconds, -901);
    }

    // ========================================================================
    // Device Model Verification Tests
    // ========================================================================

    #[test]
    fn test_model_verified_exact_match() {
        let result = verify_device_model("iPhone 15 Pro");
        assert!(result.is_verified);
        assert_eq!(result.model_name, "iPhone 15 Pro");
    }

    #[test]
    fn test_model_verified_case_insensitive() {
        let result = verify_device_model("IPHONE 15 PRO MAX");
        assert!(result.is_verified);
    }

    #[test]
    fn test_model_verified_with_prefix() {
        let result = verify_device_model("Apple iPhone 15 Pro");
        assert!(result.is_verified);
    }

    #[test]
    fn test_model_verified_no_spaces() {
        let result = verify_device_model("iPhone15Pro");
        assert!(result.is_verified);
    }

    #[test]
    fn test_model_not_verified_regular_iphone() {
        let result = verify_device_model("iPhone 15");
        assert!(!result.is_verified);
    }

    #[test]
    fn test_model_not_verified_ipad() {
        let result = verify_device_model("iPad Pro");
        assert!(!result.is_verified);
    }

    #[test]
    fn test_model_verified_all_generations() {
        let models = vec![
            "iPhone 12 Pro",
            "iPhone 12 Pro Max",
            "iPhone 13 Pro",
            "iPhone 13 Pro Max",
            "iPhone 14 Pro",
            "iPhone 14 Pro Max",
            "iPhone 15 Pro",
            "iPhone 15 Pro Max",
            "iPhone 16 Pro",
            "iPhone 16 Pro Max",
        ];

        for model in models {
            let result = verify_device_model(model);
            assert!(result.is_verified, "Model {} should be verified", model);
        }
    }

    // ========================================================================
    // Location Validation Tests
    // ========================================================================

    #[test]
    fn test_location_valid() {
        let loc = CaptureLocation {
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: Some(100.0),
            accuracy: Some(5.0),
        };
        let result = validate_location(Some(&loc));

        assert!(result.is_available);
        assert!(!result.opted_out);
    }

    #[test]
    fn test_location_valid_boundary_north_pole() {
        let loc = CaptureLocation {
            latitude: 90.0,
            longitude: 0.0,
            altitude: None,
            accuracy: None,
        };
        let result = validate_location(Some(&loc));

        assert!(result.is_available);
    }

    #[test]
    fn test_location_valid_boundary_south_pole() {
        let loc = CaptureLocation {
            latitude: -90.0,
            longitude: 0.0,
            altitude: None,
            accuracy: None,
        };
        let result = validate_location(Some(&loc));

        assert!(result.is_available);
    }

    #[test]
    fn test_location_valid_boundary_dateline() {
        let loc = CaptureLocation {
            latitude: 0.0,
            longitude: 180.0,
            altitude: None,
            accuracy: None,
        };
        let result = validate_location(Some(&loc));

        assert!(result.is_available);
    }

    #[test]
    fn test_location_invalid_latitude_too_high() {
        let loc = CaptureLocation {
            latitude: 91.0,
            longitude: 0.0,
            altitude: None,
            accuracy: None,
        };
        let result = validate_location(Some(&loc));

        assert!(!result.is_available);
        assert!(!result.opted_out); // Still has location data, just invalid
    }

    #[test]
    fn test_location_invalid_longitude_too_low() {
        let loc = CaptureLocation {
            latitude: 0.0,
            longitude: -181.0,
            altitude: None,
            accuracy: None,
        };
        let result = validate_location(Some(&loc));

        assert!(!result.is_available);
    }

    #[test]
    fn test_location_none_treated_as_opted_out() {
        let result = validate_location(None);

        assert!(!result.is_available);
        assert!(result.opted_out);
    }

    // ========================================================================
    // Resolution Validation Tests
    // ========================================================================

    #[test]
    fn test_resolution_valid_iphone_standard() {
        assert!(validate_resolution(256, 192));
    }

    #[test]
    fn test_resolution_valid_qvga() {
        assert!(validate_resolution(320, 240));
    }

    #[test]
    fn test_resolution_valid_vga() {
        assert!(validate_resolution(640, 480));
    }

    #[test]
    fn test_resolution_valid_with_tolerance() {
        // Within 10 pixel tolerance
        assert!(validate_resolution(260, 196)); // 256+4, 192+4
        assert!(validate_resolution(250, 186)); // 256-6, 192-6
    }

    #[test]
    fn test_resolution_invalid_outside_tolerance() {
        // Outside 10 pixel tolerance
        assert!(!validate_resolution(256 + 11, 192));
        assert!(!validate_resolution(256, 192 + 11));
    }

    #[test]
    fn test_resolution_invalid_unknown() {
        assert!(!validate_resolution(100, 100));
        assert!(!validate_resolution(1920, 1080));
    }

    // ========================================================================
    // Full Validation Orchestrator Tests
    // ========================================================================

    fn create_valid_metadata() -> CaptureMetadataPayload {
        CaptureMetadataPayload {
            captured_at: Utc::now().to_rfc3339(),
            device_model: "iPhone 15 Pro".to_string(),
            photo_hash: "test-hash".to_string(),
            depth_map_dimensions: DepthMapDimensions {
                width: 256,
                height: 192,
            },
            assertion: None,
            location: Some(CaptureLocation {
                latitude: 37.7749,
                longitude: -122.4194,
                altitude: None,
                accuracy: None,
            }),
        }
    }

    #[test]
    fn test_full_validation_all_valid() {
        let metadata = create_valid_metadata();
        let result = validate_metadata(&metadata);

        assert!(result.timestamp_valid);
        assert!(result.model_verified);
        assert!(result.resolution_valid);
        assert!(result.location_available);
        assert!(!result.location_opted_out);
        assert!(result.timestamp_delta_seconds.abs() < 5); // Should be very recent
    }

    #[test]
    fn test_full_validation_no_location() {
        let mut metadata = create_valid_metadata();
        metadata.location = None;
        let result = validate_metadata(&metadata);

        assert!(result.timestamp_valid);
        assert!(result.model_verified);
        assert!(result.resolution_valid);
        assert!(!result.location_available);
        assert!(result.location_opted_out);
    }

    #[test]
    fn test_full_validation_unverified_model() {
        let mut metadata = create_valid_metadata();
        metadata.device_model = "Samsung Galaxy".to_string();
        let result = validate_metadata(&metadata);

        assert!(result.timestamp_valid);
        assert!(!result.model_verified);
        assert_eq!(result.model_name, "Samsung Galaxy");
        assert!(result.resolution_valid);
    }

    #[test]
    fn test_full_validation_invalid_resolution() {
        let mut metadata = create_valid_metadata();
        metadata.depth_map_dimensions = DepthMapDimensions {
            width: 100,
            height: 100,
        };
        let result = validate_metadata(&metadata);

        assert!(result.timestamp_valid);
        assert!(result.model_verified);
        assert!(!result.resolution_valid);
    }

    #[test]
    fn test_full_validation_invalid_timestamp() {
        let mut metadata = create_valid_metadata();
        // Set timestamp to 1 hour ago (outside 15 min window)
        metadata.captured_at = (Utc::now() - Duration::hours(1)).to_rfc3339();
        let result = validate_metadata(&metadata);

        assert!(!result.timestamp_valid);
        assert!(result.timestamp_delta_seconds > 3500); // ~1 hour in seconds
        assert!(result.model_verified);
    }
}
