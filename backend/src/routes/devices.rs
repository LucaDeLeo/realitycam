//! Device registration routes
//!
//! Implements device challenge and registration endpoints for the RealityCam API.
//! Device registration stores device information with attestation data for future verification.
//!
//! ## API Contract Note (Story 2.4)
//!
//! This implementation uses a simplified/flattened request structure:
//! ```json
//! { "device_id": "...", "public_key": "...", "attestation_object": "...", "platform": "...", "model": "...", "has_lidar": true }
//! ```
//!
//! The tech-spec describes a nested structure with an `attestation` object containing `key_id`,
//! `attestation_object`, and `challenge` fields. This simplification was intentional for Story 2.4
//! which focuses on storage without verification. Story 2.5 will add the `challenge` field when
//! verification is implemented. The optional `challenge` field is already included for forward
//! compatibility.

use axum::{
    extract::{Extension, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::borrow::Cow;
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::models::Device;
use crate::types::{ApiErrorResponse, ApiResponse};

// ============================================================================
// Request/Response Types (AC-8)
// ============================================================================

/// Device registration request payload.
///
/// Contains device information, public key, and attestation object from the mobile app.
/// The attestation_object is base64-encoded CBOR data from DCAppAttest.
#[derive(Debug, Deserialize)]
pub struct DeviceRegistrationRequest {
    /// Attestation key ID from DCAppAttest (unique device identifier)
    pub device_id: String,
    /// Base64-encoded public key
    pub public_key: String,
    /// Base64-encoded CBOR attestation object from DCAppAttest
    pub attestation_object: String,
    /// Platform identifier (must be "ios" for MVP)
    pub platform: String,
    /// Device model (e.g., "iPhone 15 Pro")
    pub model: String,
    /// Whether the device has LiDAR sensor
    pub has_lidar: bool,
    /// Optional challenge for attestation verification (Story 2.5)
    /// Included for forward compatibility - will be required when verification is implemented
    #[serde(default)]
    pub challenge: Option<String>,
}

/// Device registration response payload.
///
/// Returned after successful device registration with the assigned device ID
/// and initial attestation level.
#[derive(Debug, Serialize)]
pub struct DeviceRegistrationResponse {
    /// Unique device ID assigned by the backend
    pub device_id: Uuid,
    /// Current attestation level ("unverified" until Story 2.5 verification)
    pub attestation_level: String,
    /// Whether the device has LiDAR sensor
    pub has_lidar: bool,
}

// ============================================================================
// Router Setup
// ============================================================================

/// Creates the device routes router.
///
/// Routes:
/// - GET /challenge - Request attestation challenge (Story 2.5)
/// - POST /register - Register a new device
pub fn router() -> Router<PgPool> {
    Router::new()
        .route("/challenge", get(get_challenge))
        .route("/register", post(register_device))
}

// ============================================================================
// Validation Functions (AC-2, AC-3)
// ============================================================================

/// Validates the device registration request.
///
/// Checks:
/// - All required fields are non-empty (AC-2)
/// - Platform is "ios" (MVP constraint)
/// - Base64 fields decode successfully (AC-3)
///
/// Returns decoded attestation bytes on success.
fn validate_registration_request(
    req: &DeviceRegistrationRequest,
) -> Result<(Vec<u8>, Vec<u8>), ApiError> {
    // Validate required fields are non-empty (AC-2)
    if req.device_id.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: device_id");
        return Err(ApiError::Validation(
            "missing required field: device_id".to_string(),
        ));
    }
    if req.public_key.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: public_key");
        return Err(ApiError::Validation(
            "missing required field: public_key".to_string(),
        ));
    }
    if req.attestation_object.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: attestation_object");
        return Err(ApiError::Validation(
            "missing required field: attestation_object".to_string(),
        ));
    }
    if req.platform.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: platform");
        return Err(ApiError::Validation(
            "missing required field: platform".to_string(),
        ));
    }
    if req.model.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: model");
        return Err(ApiError::Validation(
            "missing required field: model".to_string(),
        ));
    }

    // Validate platform is "ios" (MVP constraint)
    if req.platform.to_lowercase() != "ios" {
        tracing::warn!(
            platform = %req.platform,
            "Validation failed: unsupported platform"
        );
        return Err(ApiError::Validation(
            "platform must be 'ios' (only supported platform for MVP)".to_string(),
        ));
    }

    // Validate and decode base64 fields (AC-3)
    let public_key_bytes = decode_base64(&req.public_key, "public_key")?;
    let attestation_bytes = decode_base64(&req.attestation_object, "attestation_object")?;

    Ok((public_key_bytes, attestation_bytes))
}

/// Decodes a base64 string, returning an error with the field name on failure.
fn decode_base64(input: &str, field_name: &str) -> Result<Vec<u8>, ApiError> {
    STANDARD.decode(input).map_err(|_| {
        tracing::warn!(
            field = field_name,
            "Validation failed: invalid base64 encoding"
        );
        ApiError::Validation(format!("Invalid base64 encoding for {field_name}"))
    })
}

// ============================================================================
// Database Operations (AC-5, AC-7)
// ============================================================================

/// Inserts a new device record into the database.
///
/// The device is created with:
/// - attestation_level = "unverified" (verification is Story 2.5)
/// - first_seen_at and last_seen_at set to current timestamp
///
/// Returns DeviceAlreadyRegistered error if attestation_key_id already exists (AC-4).
async fn insert_device(
    pool: &PgPool,
    req: &DeviceRegistrationRequest,
    attestation_bytes: &[u8],
) -> Result<Device, ApiError> {
    // Note: We're not storing public_key separately as it's contained in attestation_object
    // The attestation_chain column stores the full attestation object for later verification
    sqlx::query_as!(
        Device,
        r#"
        INSERT INTO devices (attestation_key_id, platform, model, has_lidar, attestation_chain)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING
            id,
            attestation_level,
            attestation_key_id,
            attestation_chain,
            platform,
            model,
            has_lidar,
            first_seen_at,
            last_seen_at
        "#,
        req.device_id,
        req.platform,
        req.model,
        req.has_lidar,
        attestation_bytes
    )
    .fetch_one(pool)
    .await
    .map_err(|e| {
        // Check for unique constraint violation (PostgreSQL error code 23505)
        if let sqlx::Error::Database(db_err) = &e {
            if db_err.code() == Some(Cow::Borrowed("23505")) {
                tracing::warn!(
                    device_id = %req.device_id,
                    "Device registration conflict: device already registered"
                );
                return ApiError::DeviceAlreadyRegistered;
            }
        }
        tracing::error!(
            error = %e,
            "Database error during device registration"
        );
        ApiError::Database(e)
    })
}

// ============================================================================
// Route Handlers
// ============================================================================

/// GET /api/v1/devices/challenge - Request attestation challenge
///
/// Returns a unique challenge for device attestation.
/// Currently returns 501 Not Implemented (Story 2.5).
async fn get_challenge(
    Extension(request_id): Extension<Uuid>,
) -> (StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}

/// POST /api/v1/devices/register - Register a new device (AC-1)
///
/// Registers a device with its attestation data. The device is stored with
/// attestation_level = "unverified" until verification is implemented in Story 2.5.
///
/// # Request Body
/// - device_id: Attestation key ID from DCAppAttest
/// - public_key: Base64-encoded public key
/// - attestation_object: Base64-encoded CBOR attestation from DCAppAttest
/// - platform: Must be "ios"
/// - model: Device model string
/// - has_lidar: Boolean indicating LiDAR presence
///
/// # Responses
/// - 201 Created: Device successfully registered (AC-6)
/// - 400 Bad Request: Validation error (AC-2, AC-3)
/// - 409 Conflict: Device already registered (AC-4)
/// - 500 Internal Server Error: Database error (AC-7)
async fn register_device(
    State(pool): State<PgPool>,
    Extension(request_id): Extension<Uuid>,
    Json(req): Json<DeviceRegistrationRequest>,
) -> Result<(StatusCode, Json<ApiResponse<DeviceRegistrationResponse>>), ApiErrorWithRequestId> {
    tracing::info!(
        request_id = %request_id,
        device_id = %req.device_id,
        platform = %req.platform,
        model = %req.model,
        has_lidar = %req.has_lidar,
        "Processing device registration request"
    );

    // Validate request (AC-2, AC-3)
    let (_public_key_bytes, attestation_bytes) =
        validate_registration_request(&req).map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    // Insert device into database (AC-5, AC-7)
    let device = insert_device(&pool, &req, &attestation_bytes)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    // Build response (AC-6)
    let response_data = DeviceRegistrationResponse {
        device_id: device.id,
        attestation_level: device.attestation_level.clone(),
        has_lidar: device.has_lidar,
    };

    // Log successful registration (AC-9)
    tracing::info!(
        request_id = %request_id,
        device_id = %device.id,
        attestation_key_id = %device.attestation_key_id,
        model = %device.model,
        attestation_level = %device.attestation_level,
        "Device registered successfully"
    );

    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(response_data, request_id)),
    ))
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_request() -> DeviceRegistrationRequest {
        DeviceRegistrationRequest {
            device_id: "test-device-id".to_string(),
            public_key: "dGVzdC1wdWJsaWMta2V5".to_string(), // "test-public-key" in base64
            attestation_object: "dGVzdC1hdHRlc3RhdGlvbg==".to_string(), // "test-attestation" in base64
            platform: "ios".to_string(),
            model: "iPhone 15 Pro".to_string(),
            has_lidar: true,
            challenge: None,
        }
    }

    #[test]
    fn test_validate_registration_request_success() {
        let req = valid_request();
        let result = validate_registration_request(&req);
        assert!(result.is_ok());
        let (public_key, attestation) = result.unwrap();
        assert_eq!(public_key, b"test-public-key");
        assert_eq!(attestation, b"test-attestation");
    }

    #[test]
    fn test_validate_registration_request_empty_device_id() {
        let mut req = valid_request();
        req.device_id = "".to_string();
        let result = validate_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_registration_request_empty_public_key() {
        let mut req = valid_request();
        req.public_key = "".to_string();
        let result = validate_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_registration_request_invalid_platform() {
        let mut req = valid_request();
        req.platform = "android".to_string();
        let result = validate_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_registration_request_platform_case_insensitive() {
        let mut req = valid_request();
        req.platform = "iOS".to_string();
        let result = validate_registration_request(&req);
        assert!(result.is_ok());
    }

    #[test]
    fn test_decode_base64_success() {
        let result = decode_base64("SGVsbG8gV29ybGQ=", "test_field");
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), b"Hello World");
    }

    #[test]
    fn test_decode_base64_invalid() {
        let result = decode_base64("not-valid-base64!!!", "test_field");
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }
}
