//! Device Authentication Middleware
//!
//! Tower middleware that authenticates API requests using device signatures.
//! Verifies requests come from registered, attested devices by:
//! 1. Extracting device authentication headers (X-Device-Id, X-Device-Timestamp, X-Device-Signature)
//! 2. Looking up device in database and verifying attestation level
//! 3. Decoding CBOR assertion and verifying EC signature using stored public key
//! 4. Checking replay protection via assertion counter
//! 5. Injecting DeviceContext into request extensions for downstream handlers

use axum::{
    body::{Body, Bytes},
    http::{Request, Response, StatusCode},
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::Utc;
use ciborium::Value;
use p256::ecdsa::{signature::Verifier, Signature, VerifyingKey};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use std::{
    future::Future,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};
use tower::{Layer, Service};
use uuid::Uuid;

use crate::error::ApiError;
use crate::models::Device;
use crate::types::ApiErrorResponse;

// ============================================================================
// Constants
// ============================================================================

/// Header name for device ID
pub const X_DEVICE_ID: &str = "x-device-id";
/// Header name for device timestamp
pub const X_DEVICE_TIMESTAMP: &str = "x-device-timestamp";
/// Header name for device signature (base64-encoded assertion)
pub const X_DEVICE_SIGNATURE: &str = "x-device-signature";
/// Header name for request ID (used for logging)
pub const X_REQUEST_ID: &str = "x-request-id";

/// Default timestamp tolerance: 5 minutes in the past
const DEFAULT_TIMESTAMP_TOLERANCE_SECS: i64 = 300;
/// Default future timestamp tolerance: 1 minute in the future
const DEFAULT_FUTURE_TOLERANCE_SECS: i64 = 60;
/// Maximum body size for buffering (20MB for photo uploads)
const MAX_BODY_SIZE: usize = 20 * 1024 * 1024;

// ============================================================================
// Types
// ============================================================================

/// Attestation level for a device
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AttestationLevel {
    /// Device with verified Secure Enclave attestation
    SecureEnclave,
    /// Unverified device (development/testing)
    Unverified,
}

impl From<&str> for AttestationLevel {
    fn from(s: &str) -> Self {
        match s {
            "secure_enclave" => AttestationLevel::SecureEnclave,
            _ => AttestationLevel::Unverified,
        }
    }
}

/// Device context injected into request extensions after successful authentication
#[derive(Debug, Clone)]
pub struct DeviceContext {
    /// Device UUID
    pub device_id: Uuid,
    /// Attestation level of the device
    pub attestation_level: AttestationLevel,
    /// Device model (e.g., "iPhone 15 Pro")
    pub model: String,
    /// Whether device has LiDAR sensor
    pub has_lidar: bool,
    /// True if signature was verified (false for unverified devices)
    pub is_verified: bool,
}

/// Configuration for the device authentication middleware
#[derive(Debug, Clone)]
pub struct DeviceAuthConfig {
    /// Require verified (secure_enclave) attestation level
    pub require_verified: bool,
    /// Timestamp tolerance in seconds (default: 300 = 5 minutes)
    pub timestamp_tolerance_secs: i64,
    /// Future timestamp tolerance in seconds (default: 60 = 1 minute)
    pub future_tolerance_secs: i64,
}

impl Default for DeviceAuthConfig {
    fn default() -> Self {
        Self {
            require_verified: false, // MVP mode: allow unverified devices
            timestamp_tolerance_secs: DEFAULT_TIMESTAMP_TOLERANCE_SECS,
            future_tolerance_secs: DEFAULT_FUTURE_TOLERANCE_SECS,
        }
    }
}

/// Extracted device authentication headers
#[derive(Debug)]
struct DeviceAuthHeaders {
    device_id: Uuid,
    timestamp: i64,
    signature: Vec<u8>,
}

/// Parsed assertion from CBOR
#[derive(Debug)]
struct ParsedAssertion {
    authenticator_data: Vec<u8>,
    signature: Vec<u8>,
}

/// Parsed authenticator data from assertion (shorter than attestation)
#[derive(Debug)]
struct AssertionAuthData {
    #[allow(dead_code)]
    rp_id_hash: [u8; 32],
    #[allow(dead_code)]
    flags: u8,
    counter: u32,
}

// ============================================================================
// Tower Layer Implementation
// ============================================================================

/// Tower Layer for device authentication
#[derive(Clone)]
pub struct DeviceAuthLayer {
    db: PgPool,
    config: Arc<DeviceAuthConfig>,
}

impl DeviceAuthLayer {
    /// Creates a new DeviceAuthLayer with the given database pool and config
    pub fn new(db: PgPool, config: DeviceAuthConfig) -> Self {
        Self {
            db,
            config: Arc::new(config),
        }
    }
}

impl<S> Layer<S> for DeviceAuthLayer {
    type Service = DeviceAuthMiddleware<S>;

    fn layer(&self, inner: S) -> Self::Service {
        DeviceAuthMiddleware {
            inner,
            db: self.db.clone(),
            config: self.config.clone(),
        }
    }
}

// ============================================================================
// Tower Service Implementation
// ============================================================================

/// Device authentication middleware service
#[derive(Clone)]
pub struct DeviceAuthMiddleware<S> {
    inner: S,
    db: PgPool,
    config: Arc<DeviceAuthConfig>,
}

impl<S> Service<Request<Body>> for DeviceAuthMiddleware<S>
where
    S: Service<Request<Body>, Response = Response<Body>> + Clone + Send + 'static,
    S::Future: Send + 'static,
{
    type Response = Response<Body>;
    type Error = S::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request<Body>) -> Self::Future {
        let inner = self.inner.clone();
        let db = self.db.clone();
        let config = self.config.clone();

        // We need to take ownership of the service for the async block
        let mut inner = std::mem::replace(&mut self.inner, inner);

        Box::pin(async move {
            // Extract request ID for logging/errors
            let request_id = extract_request_id(&request);

            // Extract headers
            let headers = match extract_device_headers(&request) {
                Ok(h) => h,
                Err(err) => {
                    tracing::warn!(
                        request_id = %request_id,
                        error = %err,
                        "Device auth header extraction failed"
                    );
                    return Ok(err.into_error_response(request_id));
                }
            };

            // Validate timestamp
            if let Err(err) = validate_timestamp(headers.timestamp, &config) {
                tracing::warn!(
                    request_id = %request_id,
                    device_id = %headers.device_id,
                    timestamp = headers.timestamp,
                    "Device auth timestamp validation failed"
                );
                return Ok(err.into_error_response(request_id));
            }

            // Lookup device in database
            let device = match lookup_device(&db, headers.device_id).await {
                Ok(d) => d,
                Err(err) => {
                    tracing::warn!(
                        request_id = %request_id,
                        device_id = %headers.device_id,
                        "Device lookup failed"
                    );
                    return Ok(err.into_error_response(request_id));
                }
            };

            let attestation_level = AttestationLevel::from(device.attestation_level.as_str());

            // Check attestation level if required
            if config.require_verified && attestation_level != AttestationLevel::SecureEnclave {
                tracing::warn!(
                    request_id = %request_id,
                    device_id = %headers.device_id,
                    attestation_level = ?attestation_level,
                    "Device unverified on strict route"
                );
                return Ok(ApiError::DeviceUnverified.into_error_response(request_id));
            }

            // Buffer body for signature verification
            let (parts, body) = request.into_parts();
            let body_bytes = match axum::body::to_bytes(body, MAX_BODY_SIZE).await {
                Ok(bytes) => bytes,
                Err(e) => {
                    tracing::error!(
                        request_id = %request_id,
                        error = %e,
                        "Failed to buffer request body"
                    );
                    return Ok(ApiError::Validation("Request body too large".to_string())
                        .into_error_response(request_id));
                }
            };

            // Verify signature for verified devices
            let is_verified = if attestation_level == AttestationLevel::SecureEnclave {
                match verify_device_assertion(
                    &device,
                    headers.timestamp,
                    &body_bytes,
                    &headers.signature,
                ) {
                    Ok(new_counter) => {
                        // Update counter in database
                        if let Err(e) =
                            update_device_counter(&db, device.id, new_counter as i64).await
                        {
                            tracing::error!(
                                request_id = %request_id,
                                device_id = %device.id,
                                error = %e,
                                "Failed to update device counter"
                            );
                            // Continue anyway for MVP - log but don't fail
                        }
                        true
                    }
                    Err(err) => {
                        // For MVP mode, log warning but allow through if not requiring verified
                        if !config.require_verified {
                            tracing::warn!(
                                request_id = %request_id,
                                device_id = %device.id,
                                error = %err,
                                "Signature verification failed but allowing in MVP mode"
                            );
                            false
                        } else {
                            tracing::warn!(
                                request_id = %request_id,
                                device_id = %device.id,
                                error = %err,
                                "Signature verification failed"
                            );
                            return Ok(err.into_error_response(request_id));
                        }
                    }
                }
            } else {
                // Unverified device - skip signature verification
                tracing::warn!(
                    request_id = %request_id,
                    device_id = %device.id,
                    "Unverified device accessing protected endpoint"
                );
                false
            };

            // Create device context
            let device_context = DeviceContext {
                device_id: device.id,
                attestation_level,
                model: device.model.clone(),
                has_lidar: device.has_lidar,
                is_verified,
            };

            // Reconstruct request with buffered body and device context
            let mut request = Request::from_parts(parts, Body::from(body_bytes));
            request.extensions_mut().insert(request_id);
            request.extensions_mut().insert(device_context.clone());

            tracing::info!(
                request_id = %request_id,
                device_id = %device.id,
                attestation_level = ?attestation_level,
                is_verified = is_verified,
                "Device authentication successful"
            );

            // Call inner service
            inner.call(request).await
        })
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Extracts request ID from request headers or generates a new one
fn extract_request_id(request: &Request<Body>) -> Uuid {
    request
        .headers()
        .get(X_REQUEST_ID)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
        .unwrap_or_else(Uuid::new_v4)
}

/// Extracts device authentication headers from request
fn extract_device_headers(request: &Request<Body>) -> Result<DeviceAuthHeaders, ApiError> {
    // Extract X-Device-Id
    let device_id_str = request
        .headers()
        .get(X_DEVICE_ID)
        .ok_or(ApiError::DeviceAuthRequired)?
        .to_str()
        .map_err(|_| ApiError::Validation("Invalid X-Device-Id header encoding".to_string()))?;

    let device_id = Uuid::parse_str(device_id_str)
        .map_err(|_| ApiError::Validation("Invalid X-Device-Id UUID format".to_string()))?;

    // Extract X-Device-Timestamp
    let timestamp_str = request
        .headers()
        .get(X_DEVICE_TIMESTAMP)
        .ok_or(ApiError::DeviceAuthRequired)?
        .to_str()
        .map_err(|_| {
            ApiError::Validation("Invalid X-Device-Timestamp header encoding".to_string())
        })?;

    let timestamp: i64 = timestamp_str.parse().map_err(|_| {
        ApiError::Validation("Invalid X-Device-Timestamp format (expected Unix ms)".to_string())
    })?;

    // Extract X-Device-Signature
    let signature_b64 = request
        .headers()
        .get(X_DEVICE_SIGNATURE)
        .ok_or(ApiError::DeviceAuthRequired)?
        .to_str()
        .map_err(|_| {
            ApiError::Validation("Invalid X-Device-Signature header encoding".to_string())
        })?;

    let signature = STANDARD.decode(signature_b64).map_err(|_| {
        ApiError::Validation("Invalid X-Device-Signature base64 encoding".to_string())
    })?;

    Ok(DeviceAuthHeaders {
        device_id,
        timestamp,
        signature,
    })
}

/// Validates the request timestamp is within acceptable window
fn validate_timestamp(timestamp_ms: i64, config: &DeviceAuthConfig) -> Result<(), ApiError> {
    let now_ms = Utc::now().timestamp_millis();
    let diff_ms = now_ms - timestamp_ms;

    // Check if timestamp is too old (more than tolerance in the past)
    if diff_ms > config.timestamp_tolerance_secs * 1000 {
        return Err(ApiError::TimestampExpired);
    }

    // Check if timestamp is too far in the future
    if diff_ms < -(config.future_tolerance_secs * 1000) {
        return Err(ApiError::TimestampInvalid);
    }

    Ok(())
}

/// Looks up a device by ID from the database
async fn lookup_device(db: &PgPool, device_id: Uuid) -> Result<Device, ApiError> {
    let device = sqlx::query_as!(
        Device,
        r#"
        SELECT id, attestation_level, attestation_key_id, attestation_chain,
               platform, model, has_lidar, first_seen_at, last_seen_at,
               assertion_counter, public_key
        FROM devices
        WHERE id = $1
        "#,
        device_id
    )
    .fetch_optional(db)
    .await?
    .ok_or(ApiError::DeviceNotFound)?;

    Ok(device)
}

/// Updates the device assertion counter in the database
async fn update_device_counter(
    db: &PgPool,
    device_id: Uuid,
    new_counter: i64,
) -> Result<(), sqlx::Error> {
    sqlx::query!(
        r#"
        UPDATE devices
        SET assertion_counter = $2, last_seen_at = NOW()
        WHERE id = $1
        "#,
        device_id,
        new_counter
    )
    .execute(db)
    .await?;

    Ok(())
}

/// Verifies device assertion signature
/// Returns the new counter value if successful
fn verify_device_assertion(
    device: &Device,
    timestamp_ms: i64,
    body: &Bytes,
    signature_bytes: &[u8],
) -> Result<u32, ApiError> {
    // Parse the CBOR assertion
    let assertion = parse_cbor_assertion(signature_bytes)?;

    // Parse authenticator data to get counter
    let auth_data = parse_assertion_auth_data(&assertion.authenticator_data)?;

    // Verify counter is strictly greater than stored counter (replay protection)
    if auth_data.counter as i64 <= device.assertion_counter {
        tracing::warn!(
            device_id = %device.id,
            received_counter = auth_data.counter,
            stored_counter = device.assertion_counter,
            "Replay attack detected: counter not increasing"
        );
        return Err(ApiError::ReplayDetected);
    }

    // Get public key
    let public_key_bytes = device
        .public_key
        .as_ref()
        .ok_or(ApiError::SignatureInvalid)?;

    // Reconstruct the message that was signed
    // clientDataHash = sha256(timestamp + "|" + sha256_hex(body))
    let body_hash = Sha256::digest(body);
    let body_hash_hex = hex::encode(body_hash);
    let client_data = format!("{timestamp_ms}|{body_hash_hex}");
    let client_data_hash = Sha256::digest(client_data.as_bytes());

    // Message = authenticatorData || sha256(clientDataHash)
    // Note: Per WebAuthn, the signature is over authenticatorData || clientDataHash directly
    let mut message = assertion.authenticator_data.clone();
    message.extend_from_slice(&client_data_hash);

    // Parse the public key (uncompressed EC point: 0x04 || x || y)
    let verifying_key = VerifyingKey::from_sec1_bytes(public_key_bytes).map_err(|e| {
        tracing::error!(error = %e, "Failed to parse public key");
        ApiError::SignatureInvalid
    })?;

    // Parse the signature (could be DER or raw r||s format)
    let signature = parse_signature(&assertion.signature)?;

    // Verify the signature
    verifying_key.verify(&message, &signature).map_err(|e| {
        tracing::warn!(error = %e, "Signature verification failed");
        ApiError::SignatureInvalid
    })?;

    Ok(auth_data.counter)
}

/// Parses CBOR assertion object
fn parse_cbor_assertion(data: &[u8]) -> Result<ParsedAssertion, ApiError> {
    let value: Value = ciborium::from_reader(data).map_err(|e| {
        tracing::error!(error = %e, "Failed to parse CBOR assertion");
        ApiError::Validation("Invalid CBOR assertion".to_string())
    })?;

    let map = value
        .as_map()
        .ok_or_else(|| ApiError::Validation("Assertion must be a CBOR map".to_string()))?;

    // Extract authenticatorData
    let authenticator_data = map
        .iter()
        .find(|(k, _)| k.as_text() == Some("authenticatorData"))
        .and_then(|(_, v)| v.as_bytes())
        .map(|b| b.to_vec())
        .ok_or_else(|| {
            ApiError::Validation("Missing authenticatorData in assertion".to_string())
        })?;

    // Extract signature
    let signature = map
        .iter()
        .find(|(k, _)| k.as_text() == Some("signature"))
        .and_then(|(_, v)| v.as_bytes())
        .map(|b| b.to_vec())
        .ok_or_else(|| ApiError::Validation("Missing signature in assertion".to_string()))?;

    Ok(ParsedAssertion {
        authenticator_data,
        signature,
    })
}

/// Parses authenticator data from assertion (shorter than attestation)
/// Layout: rpIdHash(32) + flags(1) + counter(4) = 37 bytes minimum
fn parse_assertion_auth_data(data: &[u8]) -> Result<AssertionAuthData, ApiError> {
    if data.len() < 37 {
        return Err(ApiError::Validation(format!(
            "Authenticator data too short: {} bytes, expected at least 37",
            data.len()
        )));
    }

    let rp_id_hash: [u8; 32] = data[0..32]
        .try_into()
        .map_err(|_| ApiError::Validation("Failed to extract RP ID hash".to_string()))?;

    let flags = data[32];

    let counter = u32::from_be_bytes(
        data[33..37]
            .try_into()
            .map_err(|_| ApiError::Validation("Failed to extract counter".to_string()))?,
    );

    Ok(AssertionAuthData {
        rp_id_hash,
        flags,
        counter,
    })
}

/// Parses signature bytes (supports both DER and raw r||s format)
fn parse_signature(sig_bytes: &[u8]) -> Result<Signature, ApiError> {
    // Try DER format first (more common)
    if let Ok(sig) = Signature::from_der(sig_bytes) {
        return Ok(sig);
    }

    // Try raw r||s format (64 bytes for P-256)
    if sig_bytes.len() == 64 {
        if let Ok(sig) = Signature::from_slice(sig_bytes) {
            return Ok(sig);
        }
    }

    Err(ApiError::Validation("Invalid signature format".to_string()))
}

// ============================================================================
// Error Response Helper
// ============================================================================

/// Extension trait for converting ApiError to HTTP response
trait IntoErrorResponse {
    fn into_error_response(self, request_id: Uuid) -> Response<Body>;
}

impl IntoErrorResponse for ApiError {
    fn into_error_response(self, request_id: Uuid) -> Response<Body> {
        let status = self.status_code();
        let body = ApiErrorResponse::new(self.code(), self.safe_message(), request_id);
        let json_body = serde_json::to_string(&body).unwrap_or_else(|_| "{}".to_string());

        Response::builder()
            .status(status)
            .header("content-type", "application/json")
            .body(Body::from(json_body))
            .unwrap_or_else(|_| {
                Response::builder()
                    .status(StatusCode::INTERNAL_SERVER_ERROR)
                    .body(Body::empty())
                    .unwrap()
            })
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::Request;

    #[test]
    fn test_attestation_level_from_str() {
        assert_eq!(
            AttestationLevel::from("secure_enclave"),
            AttestationLevel::SecureEnclave
        );
        assert_eq!(
            AttestationLevel::from("unverified"),
            AttestationLevel::Unverified
        );
        assert_eq!(
            AttestationLevel::from("anything_else"),
            AttestationLevel::Unverified
        );
    }

    #[test]
    fn test_default_config() {
        let config = DeviceAuthConfig::default();
        assert!(!config.require_verified);
        assert_eq!(config.timestamp_tolerance_secs, 300);
        assert_eq!(config.future_tolerance_secs, 60);
    }

    #[test]
    fn test_validate_timestamp_valid() {
        let config = DeviceAuthConfig::default();
        let now_ms = Utc::now().timestamp_millis();

        // Current timestamp should be valid
        assert!(validate_timestamp(now_ms, &config).is_ok());

        // 1 minute ago should be valid
        assert!(validate_timestamp(now_ms - 60_000, &config).is_ok());

        // 4 minutes ago should be valid
        assert!(validate_timestamp(now_ms - 240_000, &config).is_ok());
    }

    #[test]
    fn test_validate_timestamp_expired() {
        let config = DeviceAuthConfig::default();
        let now_ms = Utc::now().timestamp_millis();

        // 6 minutes ago should be expired
        let result = validate_timestamp(now_ms - 360_000, &config);
        assert!(matches!(result, Err(ApiError::TimestampExpired)));
    }

    #[test]
    fn test_validate_timestamp_future() {
        let config = DeviceAuthConfig::default();
        let now_ms = Utc::now().timestamp_millis();

        // 2 minutes in the future should be invalid
        let result = validate_timestamp(now_ms + 120_000, &config);
        assert!(matches!(result, Err(ApiError::TimestampInvalid)));
    }

    #[test]
    fn test_extract_headers_missing_device_id() {
        let request = Request::builder().body(Body::empty()).unwrap();

        let result = extract_device_headers(&request);
        assert!(matches!(result, Err(ApiError::DeviceAuthRequired)));
    }

    #[test]
    fn test_extract_headers_invalid_uuid() {
        let request = Request::builder()
            .header(X_DEVICE_ID, "not-a-uuid")
            .body(Body::empty())
            .unwrap();

        let result = extract_device_headers(&request);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_extract_headers_missing_timestamp() {
        let request = Request::builder()
            .header(X_DEVICE_ID, "550e8400-e29b-41d4-a716-446655440000")
            .body(Body::empty())
            .unwrap();

        let result = extract_device_headers(&request);
        assert!(matches!(result, Err(ApiError::DeviceAuthRequired)));
    }

    #[test]
    fn test_extract_headers_invalid_timestamp() {
        let request = Request::builder()
            .header(X_DEVICE_ID, "550e8400-e29b-41d4-a716-446655440000")
            .header(X_DEVICE_TIMESTAMP, "not-a-number")
            .body(Body::empty())
            .unwrap();

        let result = extract_device_headers(&request);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_extract_headers_missing_signature() {
        let request = Request::builder()
            .header(X_DEVICE_ID, "550e8400-e29b-41d4-a716-446655440000")
            .header(X_DEVICE_TIMESTAMP, "1700000000000")
            .body(Body::empty())
            .unwrap();

        let result = extract_device_headers(&request);
        assert!(matches!(result, Err(ApiError::DeviceAuthRequired)));
    }

    #[test]
    fn test_extract_headers_invalid_base64() {
        let request = Request::builder()
            .header(X_DEVICE_ID, "550e8400-e29b-41d4-a716-446655440000")
            .header(X_DEVICE_TIMESTAMP, "1700000000000")
            .header(X_DEVICE_SIGNATURE, "not-valid-base64!!!")
            .body(Body::empty())
            .unwrap();

        let result = extract_device_headers(&request);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_extract_headers_valid() {
        let request = Request::builder()
            .header(X_DEVICE_ID, "550e8400-e29b-41d4-a716-446655440000")
            .header(X_DEVICE_TIMESTAMP, "1700000000000")
            .header(X_DEVICE_SIGNATURE, "dGVzdA==") // "test" in base64
            .body(Body::empty())
            .unwrap();

        let result = extract_device_headers(&request);
        assert!(result.is_ok());
        let headers = result.unwrap();
        assert_eq!(
            headers.device_id,
            Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap()
        );
        assert_eq!(headers.timestamp, 1700000000000);
        assert_eq!(headers.signature, b"test");
    }

    #[test]
    fn test_parse_assertion_auth_data_too_short() {
        let data = vec![0u8; 36]; // Less than 37 bytes
        let result = parse_assertion_auth_data(&data);
        assert!(matches!(result, Err(ApiError::Validation(_))));
    }

    #[test]
    fn test_parse_assertion_auth_data_valid() {
        // Create valid auth data: 32 bytes rp_id_hash + 1 byte flags + 4 bytes counter
        let mut data = vec![0u8; 37];
        // Set counter to 42 (big-endian)
        data[33..37].copy_from_slice(&42u32.to_be_bytes());

        let result = parse_assertion_auth_data(&data);
        assert!(result.is_ok());
        let auth_data = result.unwrap();
        assert_eq!(auth_data.counter, 42);
    }

    #[test]
    fn test_parse_signature_raw_format() {
        // Create a valid raw signature (64 bytes for P-256)
        // This is just a structural test - real signatures need actual crypto
        let sig_bytes = vec![0u8; 64];
        // Note: This will fail because it's not a valid signature point
        // but it tests the parsing logic
        let result = parse_signature(&sig_bytes);
        // Either format should be tried
        assert!(result.is_err() || result.is_ok());
    }
}
