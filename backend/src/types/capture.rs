//! Capture upload request/response types (Story 4.1)
//!
//! Defines types for the POST /api/v1/captures endpoint including:
//! - CaptureMetadata: JSON metadata payload from multipart form
//! - CaptureUploadResponse: Response with capture_id and status
//! - Validation helpers for metadata fields

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::ApiError;

// ============================================================================
// Constants
// ============================================================================

/// Maximum photo file size: 10MB
pub const MAX_PHOTO_SIZE: usize = 10 * 1024 * 1024;
/// Maximum depth map file size: 5MB
pub const MAX_DEPTH_MAP_SIZE: usize = 5 * 1024 * 1024;
/// Maximum depth map dimension (width or height)
pub const MAX_DEPTH_DIMENSION: u32 = 1000;

// ============================================================================
// Request Types
// ============================================================================

/// Depth map dimensions as reported by the mobile app
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DepthMapDimensions {
    pub width: u32,
    pub height: u32,
}

/// Optional location data from the capture
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CaptureLocation {
    /// Latitude in degrees (-90 to 90)
    pub latitude: f64,
    /// Longitude in degrees (-180 to 180)
    pub longitude: f64,
    /// Altitude in meters (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub altitude: Option<f64>,
    /// Accuracy in meters (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub accuracy: Option<f64>,
}

/// Metadata JSON payload from the multipart form "metadata" field
///
/// This matches the CaptureMetadata type from packages/shared/src/types/capture.ts
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CaptureMetadataPayload {
    /// When the photo was captured (ISO 8601)
    pub captured_at: String,
    /// Device model (e.g., "iPhone 15 Pro")
    pub device_model: String,
    /// SHA-256 hash of the photo, base64-encoded
    pub photo_hash: String,
    /// Dimensions of the depth map
    pub depth_map_dimensions: DepthMapDimensions,
    /// Per-capture assertion from DCAppAttest (base64), optional
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assertion: Option<String>,
    /// Capture location, optional
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location: Option<CaptureLocation>,
}

/// Parsed and validated capture data from multipart form
#[derive(Debug)]
pub struct ParsedCaptureUpload {
    /// Raw photo bytes (JPEG)
    pub photo_bytes: Vec<u8>,
    /// Raw depth map bytes (gzipped)
    pub depth_map_bytes: Vec<u8>,
    /// Parsed and validated metadata
    pub metadata: CaptureMetadataPayload,
}

// ============================================================================
// Response Types
// ============================================================================

/// Response data for successful capture upload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureUploadResponse {
    /// Unique capture identifier
    pub capture_id: Uuid,
    /// Current processing status ("processing")
    pub status: String,
    /// URL to view verification results
    pub verification_url: String,
}

// ============================================================================
// Validation Functions
// ============================================================================

impl CaptureMetadataPayload {
    /// Validates all metadata fields
    pub fn validate(&self) -> Result<(), ApiError> {
        // Validate captured_at is a valid ISO 8601 timestamp
        self.validate_captured_at()?;

        // Validate device_model is non-empty
        self.validate_device_model()?;

        // Validate photo_hash is non-empty (base64 validation happens later)
        self.validate_photo_hash()?;

        // Validate depth_map_dimensions
        self.validate_depth_dimensions()?;

        // Validate location if present
        self.validate_location()?;

        Ok(())
    }

    fn validate_captured_at(&self) -> Result<(), ApiError> {
        if self.captured_at.is_empty() {
            return Err(ApiError::Validation(
                "captured_at is required".to_string(),
            ));
        }

        // Try to parse as ISO 8601
        DateTime::parse_from_rfc3339(&self.captured_at).map_err(|_| {
            ApiError::Validation(format!(
                "captured_at must be a valid ISO 8601 timestamp, got: {}",
                self.captured_at
            ))
        })?;

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

    fn validate_photo_hash(&self) -> Result<(), ApiError> {
        if self.photo_hash.trim().is_empty() {
            return Err(ApiError::Validation(
                "photo_hash is required and cannot be empty".to_string(),
            ));
        }
        Ok(())
    }

    fn validate_depth_dimensions(&self) -> Result<(), ApiError> {
        let dims = &self.depth_map_dimensions;

        if dims.width == 0 || dims.height == 0 {
            return Err(ApiError::Validation(
                "depth_map_dimensions width and height must be > 0".to_string(),
            ));
        }

        if dims.width > MAX_DEPTH_DIMENSION || dims.height > MAX_DEPTH_DIMENSION {
            return Err(ApiError::Validation(format!(
                "depth_map_dimensions must be <= {}x{}, got {}x{}",
                MAX_DEPTH_DIMENSION, MAX_DEPTH_DIMENSION, dims.width, dims.height
            )));
        }

        Ok(())
    }

    fn validate_location(&self) -> Result<(), ApiError> {
        if let Some(ref loc) = self.location {
            // Validate latitude range
            if loc.latitude < -90.0 || loc.latitude > 90.0 {
                return Err(ApiError::Validation(format!(
                    "latitude must be between -90 and 90, got {}",
                    loc.latitude
                )));
            }

            // Validate longitude range
            if loc.longitude < -180.0 || loc.longitude > 180.0 {
                return Err(ApiError::Validation(format!(
                    "longitude must be between -180 and 180, got {}",
                    loc.longitude
                )));
            }
        }
        Ok(())
    }

    /// Parses the captured_at timestamp into a DateTime<Utc>
    pub fn captured_at_datetime(&self) -> Result<DateTime<Utc>, ApiError> {
        DateTime::parse_from_rfc3339(&self.captured_at)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|_| {
                ApiError::Validation(format!(
                    "captured_at must be a valid ISO 8601 timestamp, got: {}",
                    self.captured_at
                ))
            })
    }
}

/// Validates photo file size
pub fn validate_photo_size(size: usize) -> Result<(), ApiError> {
    if size > MAX_PHOTO_SIZE {
        return Err(ApiError::PayloadTooLarge(format!(
            "photo exceeds maximum size of {} bytes (got {} bytes)",
            MAX_PHOTO_SIZE, size
        )));
    }
    if size == 0 {
        return Err(ApiError::Validation("photo cannot be empty".to_string()));
    }
    Ok(())
}

/// Validates depth map file size
pub fn validate_depth_map_size(size: usize) -> Result<(), ApiError> {
    if size > MAX_DEPTH_MAP_SIZE {
        return Err(ApiError::PayloadTooLarge(format!(
            "depth_map exceeds maximum size of {} bytes (got {} bytes)",
            MAX_DEPTH_MAP_SIZE, size
        )));
    }
    if size == 0 {
        return Err(ApiError::Validation(
            "depth_map cannot be empty".to_string(),
        ));
    }
    Ok(())
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_metadata() -> CaptureMetadataPayload {
        CaptureMetadataPayload {
            captured_at: "2025-11-23T10:30:00.123Z".to_string(),
            device_model: "iPhone 15 Pro".to_string(),
            photo_hash: "dGVzdC1oYXNo".to_string(),
            depth_map_dimensions: DepthMapDimensions {
                width: 256,
                height: 192,
            },
            assertion: None,
            location: None,
        }
    }

    #[test]
    fn test_valid_metadata() {
        let metadata = valid_metadata();
        assert!(metadata.validate().is_ok());
    }

    #[test]
    fn test_invalid_captured_at_empty() {
        let mut metadata = valid_metadata();
        metadata.captured_at = "".to_string();
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_captured_at_format() {
        let mut metadata = valid_metadata();
        metadata.captured_at = "not-a-timestamp".to_string();
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
    fn test_invalid_photo_hash_empty() {
        let mut metadata = valid_metadata();
        metadata.photo_hash = "".to_string();
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_depth_dimensions_zero() {
        let mut metadata = valid_metadata();
        metadata.depth_map_dimensions.width = 0;
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_invalid_depth_dimensions_too_large() {
        let mut metadata = valid_metadata();
        metadata.depth_map_dimensions.width = 1001;
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
    fn test_invalid_latitude_out_of_range() {
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

    #[test]
    fn test_invalid_longitude_out_of_range() {
        let mut metadata = valid_metadata();
        metadata.location = Some(CaptureLocation {
            latitude: 0.0,
            longitude: -181.0,
            altitude: None,
            accuracy: None,
        });
        let result = metadata.validate();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_photo_size_valid() {
        assert!(validate_photo_size(1024).is_ok());
        assert!(validate_photo_size(MAX_PHOTO_SIZE).is_ok());
    }

    #[test]
    fn test_validate_photo_size_too_large() {
        let result = validate_photo_size(MAX_PHOTO_SIZE + 1);
        assert!(matches!(result, Err(ApiError::PayloadTooLarge(_))));
    }

    #[test]
    fn test_validate_photo_size_empty() {
        let result = validate_photo_size(0);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_depth_map_size_valid() {
        assert!(validate_depth_map_size(1024).is_ok());
        assert!(validate_depth_map_size(MAX_DEPTH_MAP_SIZE).is_ok());
    }

    #[test]
    fn test_validate_depth_map_size_too_large() {
        let result = validate_depth_map_size(MAX_DEPTH_MAP_SIZE + 1);
        assert!(matches!(result, Err(ApiError::PayloadTooLarge(_))));
    }

    #[test]
    fn test_validate_depth_map_size_empty() {
        let result = validate_depth_map_size(0);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_captured_at_datetime() {
        let metadata = valid_metadata();
        let dt = metadata.captured_at_datetime();
        assert!(dt.is_ok());
    }
}
