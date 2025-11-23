//! Device registration routes
//!
//! Implements device challenge and registration endpoints for the RealityCam API.
//! Device registration stores device information with attestation data and performs
//! DCAppAttest verification when attestation data is provided.
//!
//! ## API Contract
//!
//! Supports both nested (tech-spec) and flattened (Story 2.4) request formats:
//!
//! ### Nested format (tech-spec, preferred):
//! ```json
//! {
//!   "platform": "ios",
//!   "model": "iPhone 15 Pro",
//!   "has_lidar": true,
//!   "attestation": {
//!     "key_id": "base64...",
//!     "attestation_object": "base64...",
//!     "challenge": "base64..."
//!   }
//! }
//! ```
//!
//! ### Flattened format (Story 2.4, backward compatible):
//! ```json
//! {
//!   "device_id": "key_id_value",
//!   "public_key": "base64...",
//!   "attestation_object": "base64...",
//!   "platform": "ios",
//!   "model": "iPhone 15 Pro",
//!   "has_lidar": true,
//!   "challenge": "base64..."
//! }
//! ```

use axum::{
    extract::{ConnectInfo, Extension, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::net::SocketAddr;
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::models::Device;
use crate::routes::AppState;
use crate::services::{verify_attestation, ChallengeError};
use crate::types::ApiResponse;

// ============================================================================
// Request/Response Types (AC-1, AC-11)
// ============================================================================

/// Nested attestation payload (tech-spec format)
#[derive(Debug, Deserialize)]
pub struct AttestationPayload {
    /// Base64-encoded key ID from DCAppAttest
    pub key_id: String,
    /// Base64-encoded CBOR attestation object
    pub attestation_object: String,
    /// Base64-encoded challenge that was used for attestation
    pub challenge: String,
}

/// Device registration request payload supporting both formats (AC-11).
///
/// Contains device information, public key, and attestation object from the mobile app.
/// The attestation_object is base64-encoded CBOR data from DCAppAttest.
#[derive(Debug, Deserialize)]
pub struct DeviceRegistrationRequest {
    /// Platform identifier (must be "ios" for MVP)
    pub platform: String,
    /// Device model (e.g., "iPhone 15 Pro")
    pub model: String,
    /// Whether the device has LiDAR sensor
    pub has_lidar: bool,

    // Tech-spec nested format (preferred)
    /// Nested attestation payload
    #[serde(default)]
    pub attestation: Option<AttestationPayload>,

    // Story 2.4 flattened format (backward compatibility)
    /// Attestation key ID from DCAppAttest (unique device identifier)
    #[serde(default)]
    pub device_id: Option<String>,
    /// Base64-encoded public key (from Story 2.4)
    #[serde(default)]
    pub public_key: Option<String>,
    /// Base64-encoded CBOR attestation object from DCAppAttest
    #[serde(default)]
    pub attestation_object: Option<String>,
    /// Optional challenge for attestation verification
    #[serde(default)]
    pub challenge: Option<String>,
}

impl DeviceRegistrationRequest {
    /// Extracts attestation data, supporting both nested and flattened formats.
    /// Returns (key_id, attestation_object_b64, challenge_b64_option)
    pub fn get_attestation_data(&self) -> Result<(String, String, Option<String>), ApiError> {
        // Prefer nested format
        if let Some(ref att) = self.attestation {
            return Ok((
                att.key_id.clone(),
                att.attestation_object.clone(),
                Some(att.challenge.clone()),
            ));
        }

        // Fall back to flattened format
        let key_id = self
            .device_id
            .clone()
            .ok_or_else(|| ApiError::Validation("missing key_id or device_id".to_string()))?;
        let attestation_object = self
            .attestation_object
            .clone()
            .ok_or_else(|| ApiError::Validation("missing attestation_object".to_string()))?;
        let challenge = self.challenge.clone();

        Ok((key_id, attestation_object, challenge))
    }
}

/// Device registration response payload.
///
/// Returned after successful device registration with the assigned device ID
/// and attestation level.
#[derive(Debug, Serialize)]
pub struct DeviceRegistrationResponse {
    /// Unique device ID assigned by the backend
    pub device_id: Uuid,
    /// Current attestation level ("unverified" or "secure_enclave")
    pub attestation_level: String,
    /// Whether the device has LiDAR sensor
    pub has_lidar: bool,
}

/// Challenge response payload (AC-1).
#[derive(Debug, Serialize)]
pub struct ChallengeResponse {
    /// Base64-encoded 32-byte challenge
    pub challenge: String,
    /// ISO 8601 timestamp when the challenge expires
    pub expires_at: DateTime<Utc>,
}

// ============================================================================
// Router Setup
// ============================================================================

/// Creates the device routes router.
///
/// Routes:
/// - GET /challenge - Request attestation challenge (AC-1)
/// - POST /register - Register a new device (AC-9, AC-10, AC-11)
pub fn router() -> Router<AppState> {
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
/// - Platform is "ios" (MVP constraint)
/// - Model is non-empty
/// - Attestation data is valid base64
fn validate_registration_request(
    req: &DeviceRegistrationRequest,
) -> Result<(String, String, Option<Vec<u8>>), ApiError> {
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

    // Validate model is non-empty
    if req.model.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: model");
        return Err(ApiError::Validation(
            "missing required field: model".to_string(),
        ));
    }

    // Extract attestation data
    let (key_id, attestation_object_b64, challenge_b64) = req.get_attestation_data()?;

    // Validate key_id is non-empty
    if key_id.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: key_id");
        return Err(ApiError::Validation(
            "missing required field: key_id".to_string(),
        ));
    }

    // Validate and decode attestation_object base64
    let _attestation_bytes = decode_base64(&attestation_object_b64, "attestation_object")?;

    // Validate and decode challenge if present
    let challenge_bytes = if let Some(ref challenge_b64) = challenge_b64 {
        Some(decode_base64(challenge_b64, "challenge")?)
    } else {
        None
    };

    Ok((key_id, attestation_object_b64, challenge_bytes))
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
// Database Operations (AC-5, AC-7, AC-9)
// ============================================================================

/// Parameters for device insertion
struct InsertDeviceParams<'a> {
    key_id: &'a str,
    platform: &'a str,
    model: &'a str,
    has_lidar: bool,
    attestation_bytes: &'a [u8],
    attestation_level: &'a str,
    public_key: Option<&'a [u8]>,
    assertion_counter: i64,
}

/// Inserts a new device record into the database.
///
/// For unverified devices:
/// - attestation_level = "unverified"
/// - public_key = NULL
/// - assertion_counter = 0
///
/// Returns DeviceAlreadyRegistered error if attestation_key_id already exists (AC-4).
async fn insert_device(pool: &sqlx::PgPool, params: InsertDeviceParams<'_>) -> Result<Device, ApiError> {
    sqlx::query_as!(
        Device,
        r#"
        INSERT INTO devices (
            attestation_key_id, platform, model, has_lidar,
            attestation_chain, attestation_level, public_key, assertion_counter
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING
            id,
            attestation_level,
            attestation_key_id,
            attestation_chain,
            platform,
            model,
            has_lidar,
            first_seen_at,
            last_seen_at,
            assertion_counter,
            public_key
        "#,
        params.key_id,
        params.platform,
        params.model,
        params.has_lidar,
        params.attestation_bytes,
        params.attestation_level,
        params.public_key,
        params.assertion_counter
    )
    .fetch_one(pool)
    .await
    .map_err(|e| {
        // Check for unique constraint violation (PostgreSQL error code 23505)
        if let sqlx::Error::Database(db_err) = &e {
            if db_err.code() == Some(Cow::Borrowed("23505")) {
                tracing::warn!(
                    device_id = %params.key_id,
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

/// GET /api/v1/devices/challenge - Request attestation challenge (AC-1, AC-2)
///
/// Returns a unique challenge for device attestation with:
/// - Base64-encoded 32 cryptographically random bytes
/// - Expiration timestamp 5 minutes in the future
///
/// Rate limited to 10 challenges per minute per IP address.
///
/// # Responses
/// - 200 OK: Challenge generated successfully
/// - 429 Too Many Requests: Rate limit exceeded
async fn get_challenge(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
) -> Result<(StatusCode, Json<ApiResponse<ChallengeResponse>>), ApiErrorWithRequestId> {
    let client_ip = addr.ip();

    tracing::info!(
        request_id = %request_id,
        client_ip = %client_ip,
        "Processing challenge request"
    );

    // Check rate limit (AC-1: 10 challenges/minute/IP)
    state
        .challenge_store
        .check_rate_limit(client_ip)
        .await
        .map_err(|e| {
            tracing::warn!(
                request_id = %request_id,
                client_ip = %client_ip,
                "Rate limit exceeded for challenge generation"
            );
            ApiErrorWithRequestId {
                error: match e {
                    ChallengeError::RateLimitExceeded => ApiError::TooManyRequests,
                    _ => ApiError::Internal(anyhow::anyhow!("Unexpected challenge error")),
                },
                request_id,
            }
        })?;

    // Generate challenge (AC-1: 32 cryptographically random bytes)
    let (challenge_bytes, expires_at) = state.challenge_store.generate_challenge().await;

    // Encode to base64
    let challenge_b64 = STANDARD.encode(challenge_bytes);

    tracing::info!(
        request_id = %request_id,
        expires_at = %expires_at,
        "Challenge generated successfully"
    );

    let response = ChallengeResponse {
        challenge: challenge_b64,
        expires_at,
    };

    Ok((StatusCode::OK, Json(ApiResponse::new(response, request_id))))
}

/// POST /api/v1/devices/register - Register a new device (AC-9, AC-10, AC-11)
///
/// Registers a device with its attestation data. Performs DCAppAttest verification
/// when challenge is provided. On verification success, device is stored with
/// attestation_level = "secure_enclave". On failure or no challenge, device is
/// stored with attestation_level = "unverified".
///
/// # Request Body
/// Supports both nested and flattened formats (see module docs).
///
/// # Responses
/// - 201 Created: Device successfully registered
/// - 400 Bad Request: Validation error
/// - 409 Conflict: Device already registered
/// - 500 Internal Server Error: Database error
async fn register_device(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Json(req): Json<DeviceRegistrationRequest>,
) -> Result<(StatusCode, Json<ApiResponse<DeviceRegistrationResponse>>), ApiErrorWithRequestId> {
    tracing::info!(
        request_id = %request_id,
        platform = %req.platform,
        model = %req.model,
        has_lidar = %req.has_lidar,
        has_attestation = req.attestation.is_some(),
        "Processing device registration request"
    );

    // Validate request
    let (key_id, attestation_object_b64, challenge_bytes) =
        validate_registration_request(&req).map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    tracing::info!(
        request_id = %request_id,
        key_id = %key_id,
        has_challenge = challenge_bytes.is_some(),
        "Validation passed"
    );

    // Decode attestation object for storage
    let attestation_bytes = decode_base64(&attestation_object_b64, "attestation_object")
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    // Attempt verification if challenge is provided
    let (attestation_level, public_key, assertion_counter) = if let Some(ref challenge) =
        challenge_bytes
    {
        // Try to verify the challenge first
        let challenge_array: [u8; 32] = challenge.as_slice().try_into().map_err(|_| {
            tracing::warn!(
                request_id = %request_id,
                challenge_len = challenge.len(),
                "Invalid challenge length"
            );
            ApiErrorWithRequestId {
                error: ApiError::ChallengeInvalid("Invalid challenge length".to_string()),
                request_id,
            }
        })?;

        // Verify and consume the challenge (AC-2: single-use, check expiry)
        match state.challenge_store.verify_and_consume(&challenge_array).await {
            Ok(()) => {
                tracing::info!(
                    request_id = %request_id,
                    step = "challenge_validation",
                    status = "pass",
                    "Challenge validated and consumed"
                );
            }
            Err(e) => {
                let reason = match e {
                    ChallengeError::NotFound => "Challenge not found",
                    ChallengeError::AlreadyUsed => "Challenge already used",
                    ChallengeError::Expired => "Challenge expired",
                    ChallengeError::RateLimitExceeded => "Rate limit exceeded",
                };
                tracing::warn!(
                    request_id = %request_id,
                    step = "challenge_validation",
                    status = "fail",
                    reason = reason,
                    "Challenge validation failed"
                );
                // On challenge failure, degrade to unverified (AC-10)
                return register_unverified_device(
                    &state,
                    request_id,
                    &key_id,
                    &req,
                    &attestation_bytes,
                )
                .await;
            }
        }

        // Perform attestation verification (AC-3 through AC-8)
        match verify_attestation(
            &attestation_object_b64,
            challenge,
            &state.config,
            request_id,
        )
        .await
        {
            Ok(result) => {
                tracing::info!(
                    request_id = %request_id,
                    status = "verified",
                    public_key_len = result.public_key.len(),
                    counter = result.counter,
                    "Attestation verification successful"
                );
                (
                    "secure_enclave",
                    Some(result.public_key),
                    result.counter as i64,
                )
            }
            Err(e) => {
                // Log internal details but don't expose to client (AC-10)
                tracing::warn!(
                    request_id = %request_id,
                    error = %e,
                    "Attestation verification failed - degrading to unverified"
                );
                ("unverified", None, 0)
            }
        }
    } else {
        // No challenge provided - device is unverified
        tracing::info!(
            request_id = %request_id,
            "No challenge provided - registering as unverified"
        );
        ("unverified", None, 0)
    };

    // Insert device into database
    let device = insert_device(
        &state.db,
        InsertDeviceParams {
            key_id: &key_id,
            platform: &req.platform,
            model: &req.model,
            has_lidar: req.has_lidar,
            attestation_bytes: &attestation_bytes,
            attestation_level,
            public_key: public_key.as_deref(),
            assertion_counter,
        },
    )
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: e,
        request_id,
    })?;

    // Build response (AC-9)
    let response_data = DeviceRegistrationResponse {
        device_id: device.id,
        attestation_level: device.attestation_level.clone(),
        has_lidar: device.has_lidar,
    };

    // Log successful registration (AC-12)
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

/// Helper to register a device as unverified (AC-10)
async fn register_unverified_device(
    state: &AppState,
    request_id: Uuid,
    key_id: &str,
    req: &DeviceRegistrationRequest,
    attestation_bytes: &[u8],
) -> Result<(StatusCode, Json<ApiResponse<DeviceRegistrationResponse>>), ApiErrorWithRequestId> {
    let device = insert_device(
        &state.db,
        InsertDeviceParams {
            key_id,
            platform: &req.platform,
            model: &req.model,
            has_lidar: req.has_lidar,
            attestation_bytes,
            attestation_level: "unverified",
            public_key: None,
            assertion_counter: 0,
        },
    )
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: e,
        request_id,
    })?;

    let response_data = DeviceRegistrationResponse {
        device_id: device.id,
        attestation_level: device.attestation_level.clone(),
        has_lidar: device.has_lidar,
    };

    tracing::info!(
        request_id = %request_id,
        device_id = %device.id,
        attestation_level = "unverified",
        "Device registered as unverified due to challenge failure"
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

    fn valid_nested_request() -> DeviceRegistrationRequest {
        DeviceRegistrationRequest {
            platform: "ios".to_string(),
            model: "iPhone 15 Pro".to_string(),
            has_lidar: true,
            attestation: Some(AttestationPayload {
                key_id: "dGVzdC1rZXktaWQ=".to_string(),
                attestation_object: "dGVzdC1hdHRlc3RhdGlvbg==".to_string(),
                challenge: "dGVzdC1jaGFsbGVuZ2U=".to_string(),
            }),
            device_id: None,
            public_key: None,
            attestation_object: None,
            challenge: None,
        }
    }

    fn valid_flattened_request() -> DeviceRegistrationRequest {
        DeviceRegistrationRequest {
            platform: "ios".to_string(),
            model: "iPhone 15 Pro".to_string(),
            has_lidar: true,
            attestation: None,
            device_id: Some("test-device-id".to_string()),
            public_key: Some("dGVzdC1wdWJsaWMta2V5".to_string()),
            attestation_object: Some("dGVzdC1hdHRlc3RhdGlvbg==".to_string()),
            challenge: None,
        }
    }

    #[test]
    fn test_get_attestation_data_nested_format() {
        let req = valid_nested_request();
        let result = req.get_attestation_data();
        assert!(result.is_ok());
        let (key_id, attestation, challenge) = result.unwrap();
        assert_eq!(key_id, "dGVzdC1rZXktaWQ=");
        assert_eq!(attestation, "dGVzdC1hdHRlc3RhdGlvbg==");
        assert_eq!(challenge, Some("dGVzdC1jaGFsbGVuZ2U=".to_string()));
    }

    #[test]
    fn test_get_attestation_data_flattened_format() {
        let req = valid_flattened_request();
        let result = req.get_attestation_data();
        assert!(result.is_ok());
        let (key_id, attestation, challenge) = result.unwrap();
        assert_eq!(key_id, "test-device-id");
        assert_eq!(attestation, "dGVzdC1hdHRlc3RhdGlvbg==");
        assert_eq!(challenge, None);
    }

    #[test]
    fn test_validate_registration_request_success_nested() {
        let req = valid_nested_request();
        let result = validate_registration_request(&req);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_registration_request_success_flattened() {
        let req = valid_flattened_request();
        let result = validate_registration_request(&req);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_registration_request_invalid_platform() {
        let mut req = valid_nested_request();
        req.platform = "android".to_string();
        let result = validate_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_registration_request_empty_model() {
        let mut req = valid_nested_request();
        req.model = "".to_string();
        let result = validate_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_registration_request_platform_case_insensitive() {
        let mut req = valid_nested_request();
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

    #[test]
    fn test_missing_key_id_flattened() {
        let mut req = valid_flattened_request();
        req.device_id = None;
        let result = req.get_attestation_data();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_missing_attestation_object_flattened() {
        let mut req = valid_flattened_request();
        req.attestation_object = None;
        let result = req.get_attestation_data();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }
}
