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
use crate::services::{
    verify_android_attestation, verify_attestation, AndroidAttestationError, ChallengeError,
};
use crate::types::ApiResponse;

// ============================================================================
// Request/Response Types (AC-1, AC-11)
// ============================================================================

/// Nested attestation payload (tech-spec format for iOS)
#[derive(Debug, Deserialize)]
pub struct AttestationPayload {
    /// Base64-encoded key ID from DCAppAttest
    pub key_id: String,
    /// Base64-encoded CBOR attestation object
    pub attestation_object: String,
    /// Base64-encoded challenge that was used for attestation
    pub challenge: String,
}

/// Android attestation payload (Story 10-3)
///
/// Contains the certificate chain and challenge for Android Key Attestation verification.
#[derive(Debug, Deserialize)]
pub struct AndroidAttestationPayload {
    /// Optional key identifier (can be derived from leaf cert if not provided)
    #[serde(default)]
    pub key_id: Option<String>,
    /// Base64-encoded DER certificate chain [leaf, intermediate(s)..., root]
    pub certificate_chain: Vec<String>,
    /// Base64-encoded challenge used for attestation
    pub challenge: String,
}

/// Device registration request payload supporting iOS and Android (AC-11, Story 10-3).
///
/// Contains device information, public key, and attestation object from the mobile app.
/// For iOS: attestation_object is base64-encoded CBOR data from DCAppAttest.
/// For Android: android_attestation contains certificate chain for Key Attestation.
#[derive(Debug, Deserialize)]
pub struct DeviceRegistrationRequest {
    /// Platform identifier: "ios" or "android"
    pub platform: String,
    /// Device model (e.g., "iPhone 15 Pro", "Pixel 8 Pro")
    pub model: String,
    /// Whether the device has LiDAR sensor (must be false for Android)
    pub has_lidar: bool,

    // iOS attestation: Tech-spec nested format (preferred)
    /// Nested attestation payload for iOS DCAppAttest
    #[serde(default)]
    pub attestation: Option<AttestationPayload>,

    // Android attestation (Story 10-3)
    /// Android Key Attestation payload
    #[serde(default)]
    pub android_attestation: Option<AndroidAttestationPayload>,

    // Story 2.4 flattened format (backward compatibility for iOS)
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
    /// Extracts iOS attestation data, supporting both nested and flattened formats.
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

    /// Extracts and validates Android attestation data (Story 10-3).
    /// Returns the AndroidAttestationPayload reference.
    pub fn get_android_attestation_data(&self) -> Result<&AndroidAttestationPayload, ApiError> {
        let android_att = self
            .android_attestation
            .as_ref()
            .ok_or_else(|| ApiError::Validation("missing android_attestation field".to_string()))?;

        // Validate certificate_chain has at least 2 entries
        if android_att.certificate_chain.len() < 2 {
            return Err(ApiError::InvalidAttestationFormat(
                "certificate_chain requires at least 2 certificates (leaf + root)".to_string(),
            ));
        }

        // Validate challenge is not empty
        if android_att.challenge.trim().is_empty() {
            return Err(ApiError::Validation(
                "android_attestation.challenge is required".to_string(),
            ));
        }

        Ok(android_att)
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
    /// Current attestation level ("unverified", "secure_enclave", "strongbox", "tee")
    pub attestation_level: String,
    /// Whether the device has LiDAR sensor
    pub has_lidar: bool,
    /// Detailed security level information (Story 10-2)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub security_level: Option<SecurityLevelResponse>,
}

/// Security level details in registration response (Story 10-2)
#[derive(Debug, Serialize)]
pub struct SecurityLevelResponse {
    /// Primary attestation security level: "strongbox", "tee", "secure_enclave"
    pub attestation: String,
    /// KeyMaster security level (Android-only)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub keymaster: Option<String>,
    /// Platform: "ios" or "android"
    pub platform: String,
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

/// Validates the common device registration request fields.
///
/// Checks:
/// - Platform is "ios" or "android"
/// - Model is non-empty
fn validate_common_registration_request(req: &DeviceRegistrationRequest) -> Result<(), ApiError> {
    // Validate platform is "ios" or "android"
    let platform = req.platform.to_lowercase();
    if platform != "ios" && platform != "android" {
        tracing::warn!(
            platform = %req.platform,
            "Validation failed: unsupported platform"
        );
        return Err(ApiError::Validation(
            "unsupported platform - must be 'ios' or 'android'".to_string(),
        ));
    }

    // Validate model is non-empty
    if req.model.trim().is_empty() {
        tracing::warn!("Validation failed: missing required field: model");
        return Err(ApiError::Validation(
            "missing required field: model".to_string(),
        ));
    }

    Ok(())
}

/// Validates iOS device registration request.
///
/// Checks:
/// - Attestation data is valid base64
fn validate_ios_registration_request(
    req: &DeviceRegistrationRequest,
) -> Result<(String, String, Option<Vec<u8>>), ApiError> {
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

/// Validates Android device registration request (Story 10-3).
///
/// Checks:
/// - has_lidar is false (Android devices don't have LiDAR)
/// - android_attestation is present with valid certificate chain
fn validate_android_registration_request(
    req: &DeviceRegistrationRequest,
) -> Result<&AndroidAttestationPayload, ApiError> {
    // Android devices cannot have LiDAR
    if req.has_lidar {
        tracing::warn!("Validation failed: Android devices do not have LiDAR");
        return Err(ApiError::Validation(
            "has_lidar must be false for Android devices".to_string(),
        ));
    }

    // Validate and return Android attestation data
    req.get_android_attestation_data()
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
    /// Hardware security level (Story 10-2)
    security_level: Option<&'a str>,
    /// KeyMaster security level - Android only (Story 10-2)
    keymaster_security_level: Option<&'a str>,
}

/// Inserts a new device record into the database.
///
/// For unverified devices:
/// - attestation_level = "unverified"
/// - public_key = NULL
/// - assertion_counter = 0
/// - security_level = NULL
///
/// Returns DeviceAlreadyRegistered error if attestation_key_id already exists (AC-4).
async fn insert_device(
    pool: &sqlx::PgPool,
    params: InsertDeviceParams<'_>,
) -> Result<Device, ApiError> {
    sqlx::query_as!(
        Device,
        r#"
        INSERT INTO devices (
            attestation_key_id, platform, model, has_lidar,
            attestation_chain, attestation_level, public_key, assertion_counter,
            security_level, keymaster_security_level
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
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
            public_key,
            security_level,
            keymaster_security_level
        "#,
        params.key_id,
        params.platform,
        params.model,
        params.has_lidar,
        params.attestation_bytes,
        params.attestation_level,
        params.public_key,
        params.assertion_counter,
        params.security_level,
        params.keymaster_security_level
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

/// POST /api/v1/devices/register - Register a new device (AC-9, AC-10, AC-11, Story 10-3)
///
/// Registers a device with its attestation data. Routes to platform-specific handlers:
/// - iOS: DCAppAttest verification, stores with attestation_level = "secure_enclave"
/// - Android: Key Attestation verification, stores with attestation_level = "tee" or "strongbox"
///
/// # Request Body
/// Supports iOS (nested/flattened) and Android formats (see module docs).
///
/// # Responses
/// - 201 Created: Device successfully registered
/// - 400 Bad Request: Validation error
/// - 403 Forbidden: Android software-only attestation rejected (FR72)
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
        has_android_attestation = req.android_attestation.is_some(),
        "Processing device registration request"
    );

    // Validate common fields
    validate_common_registration_request(&req).map_err(|e| ApiErrorWithRequestId {
        error: e,
        request_id,
    })?;

    // Platform routing (Story 10-3)
    match req.platform.to_lowercase().as_str() {
        "ios" => register_ios_device(state, request_id, req).await,
        "android" => register_android_device(state, request_id, req).await,
        _ => Err(ApiErrorWithRequestId {
            error: ApiError::Validation("unsupported platform".to_string()),
            request_id,
        }),
    }
}

/// Registers an iOS device with DCAppAttest verification.
async fn register_ios_device(
    state: AppState,
    request_id: Uuid,
    req: DeviceRegistrationRequest,
) -> Result<(StatusCode, Json<ApiResponse<DeviceRegistrationResponse>>), ApiErrorWithRequestId> {
    // Validate iOS-specific request
    let (key_id, attestation_object_b64, challenge_bytes) = validate_ios_registration_request(&req)
        .map_err(|e| ApiErrorWithRequestId {
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
    let attestation_bytes =
        decode_base64(&attestation_object_b64, "attestation_object").map_err(|e| {
            ApiErrorWithRequestId {
                error: e,
                request_id,
            }
        })?;

    // Attempt verification if challenge is provided
    let (
        attestation_level,
        public_key,
        assertion_counter,
        security_level,
        keymaster_security_level,
    ) = if let Some(ref challenge) = challenge_bytes {
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
        match state
            .challenge_store
            .verify_and_consume(&challenge_array)
            .await
        {
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
                // Story 10-2: iOS devices get secure_enclave security level
                (
                    "secure_enclave",
                    Some(result.public_key),
                    result.counter as i64,
                    Some("secure_enclave"), // security_level
                    None::<&str>,           // keymaster_security_level (iOS has none)
                )
            }
            Err(e) => {
                // Log internal details but don't expose to client (AC-10)
                tracing::warn!(
                    request_id = %request_id,
                    error = %e,
                    "Attestation verification failed - degrading to unverified"
                );
                ("unverified", None, 0, None, None)
            }
        }
    } else {
        // No challenge provided - device is unverified
        tracing::info!(
            request_id = %request_id,
            "No challenge provided - registering as unverified"
        );
        ("unverified", None, 0, None, None)
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
            security_level,
            keymaster_security_level,
        },
    )
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: e,
        request_id,
    })?;

    // Build security level response (Story 10-2)
    let security_level_response = device
        .security_level
        .as_ref()
        .map(|sl| SecurityLevelResponse {
            attestation: sl.clone(),
            keymaster: device.keymaster_security_level.clone(),
            platform: device.platform.to_lowercase(),
        });

    // Build response (AC-9)
    let response_data = DeviceRegistrationResponse {
        device_id: device.id,
        attestation_level: device.attestation_level.clone(),
        has_lidar: device.has_lidar,
        security_level: security_level_response,
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
            security_level: None,           // Story 10-2
            keymaster_security_level: None, // Story 10-2
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
        security_level: None, // Story 10-2: unverified devices have no security level
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
// Android Device Registration (Story 10-3)
// ============================================================================

/// Registers an Android device with Key Attestation verification.
///
/// This handler integrates with `verify_android_attestation()` to:
/// 1. Parse and validate the certificate chain
/// 2. Verify chain roots to Google Hardware Attestation CA
/// 3. Extract security level from attestation extension
/// 4. Reject software-only attestation (FR72)
/// 5. Store device with TEE or StrongBox security level
async fn register_android_device(
    state: AppState,
    request_id: Uuid,
    req: DeviceRegistrationRequest,
) -> Result<(StatusCode, Json<ApiResponse<DeviceRegistrationResponse>>), ApiErrorWithRequestId> {
    // Validate Android-specific request (rejects has_lidar=true)
    let android_att =
        validate_android_registration_request(&req).map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    tracing::info!(
        request_id = %request_id,
        platform = "android",
        model = %req.model,
        cert_chain_len = android_att.certificate_chain.len(),
        has_key_id = android_att.key_id.is_some(),
        "Processing Android device registration"
    );

    // Call verify_android_attestation with certificate chain
    // Challenge validation happens inside verify_android_attestation via ChallengeStore
    let attestation_result = verify_android_attestation(
        &android_att.certificate_chain,
        state.challenge_store.clone(),
        &state.config,
        request_id,
    )
    .await
    .map_err(|e| {
        let api_error = map_android_attestation_error(e.clone(), request_id);
        tracing::warn!(
            request_id = %request_id,
            error = %e,
            error_code = %api_error.code(),
            "Android attestation verification failed"
        );
        ApiErrorWithRequestId {
            error: api_error,
            request_id,
        }
    })?;

    // Extract key_id from attestation payload or use provided value
    let key_id = android_att.key_id.clone().unwrap_or_else(|| {
        STANDARD
            .encode(&attestation_result.public_key[..32.min(attestation_result.public_key.len())])
    });

    // Get security level strings
    let security_level_str = attestation_result.attestation_security_level.as_str();
    let keymaster_level_str = attestation_result.keymaster_security_level.as_str();

    // Store certificate chain as JSON array of base64 strings for debugging/auditing
    let cert_chain_json = serde_json::to_vec(&android_att.certificate_chain).map_err(|e| {
        tracing::error!(
            request_id = %request_id,
            error = %e,
            "Failed to serialize certificate chain"
        );
        ApiErrorWithRequestId {
            error: ApiError::Internal(anyhow::anyhow!("Failed to serialize certificate chain")),
            request_id,
        }
    })?;

    // Log successful verification
    tracing::info!(
        request_id = %request_id,
        platform = "android",
        security_level = %security_level_str,
        keymaster_level = %keymaster_level_str,
        device_brand = ?attestation_result.device_info.brand,
        device_model = ?attestation_result.device_info.model,
        os_patch_level = ?attestation_result.device_info.os_patch_level,
        public_key_len = attestation_result.public_key.len(),
        "Android attestation verification successful"
    );

    // Insert device into database
    let device = insert_device(
        &state.db,
        InsertDeviceParams {
            key_id: &key_id,
            platform: "android",
            model: &req.model,
            has_lidar: false, // Android devices don't have LiDAR
            attestation_bytes: &cert_chain_json,
            attestation_level: security_level_str,
            public_key: Some(&attestation_result.public_key),
            assertion_counter: 0, // Android doesn't use counter like iOS
            security_level: Some(security_level_str),
            keymaster_security_level: Some(keymaster_level_str),
        },
    )
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: e,
        request_id,
    })?;

    // Build security level response
    let security_level_response = SecurityLevelResponse {
        attestation: security_level_str.to_string(),
        keymaster: Some(keymaster_level_str.to_string()),
        platform: "android".to_string(),
    };

    // Build response
    let response_data = DeviceRegistrationResponse {
        device_id: device.id,
        attestation_level: device.attestation_level.clone(),
        has_lidar: device.has_lidar,
        security_level: Some(security_level_response),
    };

    // Log successful registration
    tracing::info!(
        request_id = %request_id,
        device_id = %device.id,
        attestation_key_id = %device.attestation_key_id,
        model = %device.model,
        attestation_level = %device.attestation_level,
        security_level = %security_level_str,
        keymaster_security_level = %keymaster_level_str,
        "Android device registered successfully"
    );

    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(response_data, request_id)),
    ))
}

/// Maps AndroidAttestationError to ApiError (Story 10-3, AC7, AC8)
fn map_android_attestation_error(error: AndroidAttestationError, request_id: Uuid) -> ApiError {
    match error {
        // Software-only attestation rejection (FR72) -> 403
        AndroidAttestationError::SoftwareOnlyAttestation => {
            tracing::warn!(
                request_id = %request_id,
                reason = "software_only_attestation",
                "Android device registration REJECTED - software attestation"
            );
            ApiError::AndroidSoftwareOnlyAttestation
        }

        // Certificate chain errors -> 400 (format errors) or 403 (trust errors)
        AndroidAttestationError::InvalidBase64 => ApiError::InvalidAttestationFormat(
            "Invalid base64 encoding in certificate chain".to_string(),
        ),
        AndroidAttestationError::InvalidCertificate(msg) => {
            ApiError::InvalidAttestationFormat(format!("Invalid X.509 certificate: {msg}"))
        }
        AndroidAttestationError::IncompleteCertChain => ApiError::InvalidAttestationFormat(
            "Certificate chain requires at least 2 certificates".to_string(),
        ),
        AndroidAttestationError::CertificateExpired => ApiError::CertificateExpired,
        AndroidAttestationError::ChainVerificationFailed(msg) => {
            ApiError::AndroidChainVerificationFailed(msg)
        }
        AndroidAttestationError::RootCaMismatch => ApiError::UntrustedAttestation(
            "Certificate chain does not root to Google Hardware Attestation CA".to_string(),
        ),

        // Attestation extension errors -> 400
        AndroidAttestationError::MissingAttestationExtension => ApiError::InvalidAttestationFormat(
            "Leaf certificate missing Key Attestation extension".to_string(),
        ),
        AndroidAttestationError::InvalidAttestationExtension(msg) => {
            ApiError::InvalidAttestationFormat(format!("Invalid attestation extension: {msg}"))
        }

        // Challenge errors -> 400
        AndroidAttestationError::ChallengeMismatch => {
            ApiError::ChallengeInvalid("Challenge does not match server-issued value".to_string())
        }
        AndroidAttestationError::ChallengeExpired => ApiError::ChallengeExpired,
        AndroidAttestationError::ChallengeNotFound => ApiError::ChallengeNotFound,

        // Key errors -> 400
        AndroidAttestationError::InvalidPublicKey(msg) => {
            ApiError::InvalidAttestationFormat(format!("Invalid public key: {msg}"))
        }
        AndroidAttestationError::UnsupportedKeyType(msg) => {
            ApiError::InvalidAttestationFormat(format!("Unsupported key type: {msg}"))
        }
    }
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
            android_attestation: None,
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
            android_attestation: None,
            device_id: Some("test-device-id".to_string()),
            public_key: Some("dGVzdC1wdWJsaWMta2V5".to_string()),
            attestation_object: Some("dGVzdC1hdHRlc3RhdGlvbg==".to_string()),
            challenge: None,
        }
    }

    fn valid_android_request() -> DeviceRegistrationRequest {
        DeviceRegistrationRequest {
            platform: "android".to_string(),
            model: "Pixel 8 Pro".to_string(),
            has_lidar: false,
            attestation: None,
            android_attestation: Some(AndroidAttestationPayload {
                key_id: Some("test-android-key-id".to_string()),
                certificate_chain: vec![
                    "dGVzdC1sZWFmLWNlcnQ=".to_string(), // leaf cert
                    "dGVzdC1yb290LWNlcnQ=".to_string(), // root cert
                ],
                challenge: "dGVzdC1jaGFsbGVuZ2U=".to_string(),
            }),
            device_id: None,
            public_key: None,
            attestation_object: None,
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
    fn test_validate_ios_registration_request_success_nested() {
        let req = valid_nested_request();
        let result = validate_ios_registration_request(&req);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_ios_registration_request_success_flattened() {
        let req = valid_flattened_request();
        let result = validate_ios_registration_request(&req);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_common_registration_request_invalid_platform() {
        let mut req = valid_nested_request();
        req.platform = "windows".to_string();
        let result = validate_common_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_common_registration_request_empty_model() {
        let mut req = valid_nested_request();
        req.model = "".to_string();
        let result = validate_common_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_common_registration_request_platform_case_insensitive() {
        let mut req = valid_nested_request();
        req.platform = "iOS".to_string();
        let result = validate_common_registration_request(&req);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_common_registration_request_android_platform() {
        let mut req = valid_nested_request();
        req.platform = "android".to_string();
        let result = validate_common_registration_request(&req);
        assert!(result.is_ok()); // Android is now a valid platform
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

    // ============================================================================
    // Android Registration Tests (Story 10-3)
    // ============================================================================

    #[test]
    fn test_android_attestation_payload_deserialization() {
        let json = r#"{
            "key_id": "test-key-id",
            "certificate_chain": ["Y2VydDE=", "Y2VydDI="],
            "challenge": "Y2hhbGxlbmdl"
        }"#;
        let payload: AndroidAttestationPayload = serde_json::from_str(json).unwrap();
        assert_eq!(payload.key_id, Some("test-key-id".to_string()));
        assert_eq!(payload.certificate_chain.len(), 2);
        assert_eq!(payload.challenge, "Y2hhbGxlbmdl");
    }

    #[test]
    fn test_android_attestation_payload_without_key_id() {
        let json = r#"{
            "certificate_chain": ["Y2VydDE=", "Y2VydDI="],
            "challenge": "Y2hhbGxlbmdl"
        }"#;
        let payload: AndroidAttestationPayload = serde_json::from_str(json).unwrap();
        assert!(payload.key_id.is_none());
        assert_eq!(payload.certificate_chain.len(), 2);
    }

    #[test]
    fn test_get_android_attestation_data_success() {
        let req = valid_android_request();
        let result = req.get_android_attestation_data();
        assert!(result.is_ok());
        let att = result.unwrap();
        assert_eq!(att.certificate_chain.len(), 2);
        assert_eq!(att.key_id, Some("test-android-key-id".to_string()));
    }

    #[test]
    fn test_get_android_attestation_data_missing() {
        let req = valid_nested_request(); // iOS request has no android_attestation
        let result = req.get_android_attestation_data();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_get_android_attestation_data_incomplete_chain() {
        let mut req = valid_android_request();
        req.android_attestation = Some(AndroidAttestationPayload {
            key_id: Some("test-key".to_string()),
            certificate_chain: vec!["c2luZ2xlLWNlcnQ=".to_string()], // only 1 cert
            challenge: "Y2hhbGxlbmdl".to_string(),
        });
        let result = req.get_android_attestation_data();
        assert!(matches!(result, Err(ApiError::InvalidAttestationFormat(_))));
    }

    #[test]
    fn test_get_android_attestation_data_empty_challenge() {
        let mut req = valid_android_request();
        req.android_attestation = Some(AndroidAttestationPayload {
            key_id: Some("test-key".to_string()),
            certificate_chain: vec!["Y2VydDE=".to_string(), "Y2VydDI=".to_string()],
            challenge: "   ".to_string(), // whitespace only
        });
        let result = req.get_android_attestation_data();
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_validate_android_registration_request_success() {
        let req = valid_android_request();
        let result = validate_android_registration_request(&req);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_android_registration_request_rejects_lidar() {
        let mut req = valid_android_request();
        req.has_lidar = true;
        let result = validate_android_registration_request(&req);
        assert!(matches!(result, Err(ApiError::Validation(_))));
        if let Err(ApiError::Validation(msg)) = result {
            assert!(msg.contains("has_lidar"));
        }
    }

    #[test]
    fn test_map_android_attestation_error_software_only() {
        let request_id = Uuid::new_v4();
        let error = map_android_attestation_error(
            AndroidAttestationError::SoftwareOnlyAttestation,
            request_id,
        );
        assert!(matches!(error, ApiError::AndroidSoftwareOnlyAttestation));
    }

    #[test]
    fn test_map_android_attestation_error_invalid_base64() {
        let request_id = Uuid::new_v4();
        let error =
            map_android_attestation_error(AndroidAttestationError::InvalidBase64, request_id);
        assert!(matches!(error, ApiError::InvalidAttestationFormat(_)));
    }

    #[test]
    fn test_map_android_attestation_error_root_ca_mismatch() {
        let request_id = Uuid::new_v4();
        let error =
            map_android_attestation_error(AndroidAttestationError::RootCaMismatch, request_id);
        assert!(matches!(error, ApiError::UntrustedAttestation(_)));
    }

    #[test]
    fn test_map_android_attestation_error_certificate_expired() {
        let request_id = Uuid::new_v4();
        let error =
            map_android_attestation_error(AndroidAttestationError::CertificateExpired, request_id);
        assert!(matches!(error, ApiError::CertificateExpired));
    }

    #[test]
    fn test_map_android_attestation_error_challenge_expired() {
        let request_id = Uuid::new_v4();
        let error =
            map_android_attestation_error(AndroidAttestationError::ChallengeExpired, request_id);
        assert!(matches!(error, ApiError::ChallengeExpired));
    }

    #[test]
    fn test_map_android_attestation_error_challenge_not_found() {
        let request_id = Uuid::new_v4();
        let error =
            map_android_attestation_error(AndroidAttestationError::ChallengeNotFound, request_id);
        assert!(matches!(error, ApiError::ChallengeNotFound));
    }

    #[test]
    fn test_map_android_attestation_error_missing_attestation_extension() {
        let request_id = Uuid::new_v4();
        let error = map_android_attestation_error(
            AndroidAttestationError::MissingAttestationExtension,
            request_id,
        );
        assert!(matches!(error, ApiError::InvalidAttestationFormat(_)));
    }

    #[test]
    fn test_android_registration_request_deserialization() {
        let json = r#"{
            "platform": "android",
            "model": "Pixel 8 Pro",
            "has_lidar": false,
            "android_attestation": {
                "key_id": "test-key",
                "certificate_chain": ["Y2VydDE=", "Y2VydDI="],
                "challenge": "Y2hhbGxlbmdl"
            }
        }"#;
        let req: DeviceRegistrationRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.platform, "android");
        assert_eq!(req.model, "Pixel 8 Pro");
        assert!(!req.has_lidar);
        assert!(req.android_attestation.is_some());
        assert!(req.attestation.is_none());
    }
}
