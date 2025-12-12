//! Capture assertion verification service (Story 4-4, Story 8-4)
//!
//! Verifies per-capture attestation assertions during upload.
//! This is different from device_auth (request-level) in that the
//! clientDataHash binds to the capture content.
//!
//! ## Full Capture Verification Flow (Story 4-4)
//! 1. Decode base64 assertion into CBOR
//! 2. Parse CBOR to extract authenticatorData and signature
//! 3. Extract counter from authenticatorData
//! 4. Verify counter is strictly greater than stored counter
//! 5. Compute clientDataHash = SHA256(photo_hash|captured_at)
//! 6. Build message = authenticatorData || clientDataHash
//! 7. Verify EC P-256 signature using device's public key
//! 8. Return verification result for evidence package
//!
//! ## Hash-Only Capture Verification Flow (Story 8-4)
//! Same as above, but clientDataHash = SHA256(serialized_payload_json)
//! where the payload is the HashOnlyCapturePayload with assertion field excluded.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use ciborium::Value;
use p256::ecdsa::{signature::Verifier, Signature, VerifyingKey};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::config::Config;
use crate::models::{
    AttestationLevel, CheckStatus, Device, HardwareAttestation, SecurityLevelInfo,
};

// ============================================================================
// Error Types
// ============================================================================

/// Errors that can occur during capture assertion verification
#[derive(Debug, Clone)]
pub enum CaptureAssertionError {
    /// Invalid base64 encoding
    InvalidBase64,
    /// Invalid CBOR structure
    InvalidCbor(String),
    /// Missing required field in assertion
    MissingField(&'static str),
    /// Authenticator data too short
    InvalidAuthData(String),
    /// Counter not increasing (replay detected)
    CounterNotIncreasing { received: u32, stored: i64 },
    /// Public key missing on device
    MissingPublicKey,
    /// Invalid public key format
    InvalidPublicKey(String),
    /// Signature verification failed
    SignatureInvalid(String),
    /// RP ID hash mismatch
    RpIdMismatch,
}

impl std::fmt::Display for CaptureAssertionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CaptureAssertionError::InvalidBase64 => write!(f, "Invalid base64 encoding"),
            CaptureAssertionError::InvalidCbor(msg) => write!(f, "Invalid CBOR: {msg}"),
            CaptureAssertionError::MissingField(field) => write!(f, "Missing field: {field}"),
            CaptureAssertionError::InvalidAuthData(msg) => {
                write!(f, "Invalid authenticator data: {msg}")
            }
            CaptureAssertionError::CounterNotIncreasing { received, stored } => {
                write!(
                    f,
                    "Counter not increasing: received {received}, stored {stored}"
                )
            }
            CaptureAssertionError::MissingPublicKey => write!(f, "Device has no public key"),
            CaptureAssertionError::InvalidPublicKey(msg) => write!(f, "Invalid public key: {msg}"),
            CaptureAssertionError::SignatureInvalid(msg) => {
                write!(f, "Signature verification failed: {msg}")
            }
            CaptureAssertionError::RpIdMismatch => write!(f, "RP ID hash mismatch"),
        }
    }
}

impl std::error::Error for CaptureAssertionError {}

// ============================================================================
// Data Structures
// ============================================================================

/// Parsed assertion from CBOR
#[derive(Debug)]
struct ParsedAssertion {
    authenticator_data: Vec<u8>,
    signature: Vec<u8>,
}

/// Parsed authenticator data from assertion (37 bytes minimum)
#[derive(Debug)]
struct AssertionAuthData {
    rp_id_hash: [u8; 32],
    #[allow(dead_code)]
    flags: u8,
    counter: u32,
}

/// Result of capture assertion verification
#[derive(Debug)]
pub struct CaptureAssertionResult {
    /// Overall verification status
    pub status: CheckStatus,
    /// Attestation level of the device
    pub level: AttestationLevel,
    /// Device model
    pub device_model: String,
    /// Whether signature was verified
    pub assertion_verified: bool,
    /// Whether counter was valid
    pub counter_valid: bool,
    /// New counter value if verification succeeded (for database update)
    pub new_counter: Option<u32>,
    /// Error message if verification failed
    pub error_message: Option<String>,
    /// Security level info from device (Story 10-2)
    pub security_level: Option<SecurityLevelInfo>,
}

impl From<CaptureAssertionResult> for HardwareAttestation {
    fn from(result: CaptureAssertionResult) -> Self {
        HardwareAttestation {
            status: result.status,
            level: result.level,
            device_model: result.device_model,
            assertion_verified: result.assertion_verified,
            counter_valid: result.counter_valid,
            security_level: result.security_level,
        }
    }
}

// ============================================================================
// Main Verification Function
// ============================================================================

/// Builds SecurityLevelInfo from device fields (Story 10-2)
fn build_security_level_info(device: &Device) -> Option<SecurityLevelInfo> {
    device.security_level.as_ref().map(|sl| SecurityLevelInfo {
        attestation_level: sl.clone(),
        keymaster_level: device.keymaster_security_level.clone(),
        platform: device.platform.to_lowercase(),
    })
}

/// Verifies a per-capture assertion against the device's registered public key.
///
/// This function is NON-BLOCKING: verification failures do not reject the upload.
/// Instead, the failure is recorded in the HardwareAttestation evidence.
///
/// ## Arguments
/// * `device` - The device that produced the capture
/// * `assertion_b64` - Base64-encoded CBOR assertion (from metadata.assertion)
/// * `photo_hash` - SHA256 hash of the photo (base64), used for clientDataHash binding
/// * `captured_at` - ISO 8601 timestamp of capture, used for clientDataHash binding
/// * `config` - Application config (for RP ID verification)
/// * `request_id` - Request ID for logging
///
/// ## Returns
/// `CaptureAssertionResult` containing verification outcome and new counter if successful
pub fn verify_capture_assertion(
    device: &Device,
    assertion_b64: Option<&str>,
    photo_hash: &str,
    captured_at: &str,
    config: &Config,
    request_id: Uuid,
) -> CaptureAssertionResult {
    let device_model = device.model.clone();
    let level = AttestationLevel::from(device.attestation_level.as_str());
    let security_level = build_security_level_info(device);

    // Handle missing assertion
    let assertion_b64 = match assertion_b64 {
        Some(s) if !s.trim().is_empty() => s,
        _ => {
            tracing::info!(
                request_id = %request_id,
                device_id = %device.id,
                "[capture_attestation] No assertion provided, status=unavailable"
            );
            return CaptureAssertionResult {
                status: CheckStatus::Unavailable,
                level,
                device_model,
                assertion_verified: false,
                counter_valid: false,
                new_counter: None,
                error_message: None,
                security_level,
            };
        }
    };

    // Attempt verification - any error results in status=fail
    match verify_assertion_internal(
        device,
        assertion_b64,
        photo_hash,
        captured_at,
        config,
        request_id,
    ) {
        Ok(new_counter) => {
            tracing::info!(
                request_id = %request_id,
                device_id = %device.id,
                new_counter = new_counter,
                "[capture_attestation] Assertion verified successfully, status=pass"
            );
            CaptureAssertionResult {
                status: CheckStatus::Pass,
                level,
                device_model,
                assertion_verified: true,
                counter_valid: true,
                new_counter: Some(new_counter),
                error_message: None,
                security_level,
            }
        }
        Err(e) => {
            // Determine which component failed
            let (assertion_verified, counter_valid) = match &e {
                CaptureAssertionError::CounterNotIncreasing { .. } => (true, false),
                CaptureAssertionError::SignatureInvalid(_)
                | CaptureAssertionError::RpIdMismatch => (false, true),
                _ => (false, false),
            };

            tracing::warn!(
                request_id = %request_id,
                device_id = %device.id,
                error = %e,
                assertion_verified = assertion_verified,
                counter_valid = counter_valid,
                "[capture_attestation] Assertion verification failed, status=fail"
            );

            CaptureAssertionResult {
                status: CheckStatus::Fail,
                level,
                device_model,
                assertion_verified,
                counter_valid,
                new_counter: None,
                error_message: Some(e.to_string()),
                security_level,
            }
        }
    }
}

/// Internal verification logic that can return errors
fn verify_assertion_internal(
    device: &Device,
    assertion_b64: &str,
    photo_hash: &str,
    captured_at: &str,
    config: &Config,
    request_id: Uuid,
) -> Result<u32, CaptureAssertionError> {
    // Step 1: Decode base64
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Decoding base64 assertion"
    );
    let assertion_bytes = STANDARD
        .decode(assertion_b64)
        .map_err(|_| CaptureAssertionError::InvalidBase64)?;

    // Step 2: Parse CBOR assertion
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing CBOR assertion"
    );
    let assertion = parse_cbor_assertion(&assertion_bytes)?;

    // Step 3: Parse authenticator data
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing authenticator data"
    );
    let auth_data = parse_assertion_auth_data(&assertion.authenticator_data)?;

    // Step 4: Verify RP ID hash (optional but recommended)
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Verifying RP ID hash"
    );
    verify_rp_id_hash(&auth_data.rp_id_hash, config)?;

    // Step 5: Verify counter is strictly greater
    tracing::debug!(
        request_id = %request_id,
        received_counter = auth_data.counter,
        stored_counter = device.assertion_counter,
        "[capture_attestation] Verifying counter"
    );
    if (auth_data.counter as i64) <= device.assertion_counter {
        return Err(CaptureAssertionError::CounterNotIncreasing {
            received: auth_data.counter,
            stored: device.assertion_counter,
        });
    }

    // Step 6: Get device public key
    let public_key_bytes = device
        .public_key
        .as_ref()
        .ok_or(CaptureAssertionError::MissingPublicKey)?;

    // Step 7: Compute clientDataHash for capture binding
    // clientDataHash = SHA256(photo_hash|captured_at)
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Computing client data hash"
    );
    let client_data_hash = compute_capture_client_data_hash(photo_hash, captured_at);

    // Step 8: Build message = authenticatorData || clientDataHash
    let mut message = assertion.authenticator_data.clone();
    message.extend_from_slice(&client_data_hash);

    // Step 9: Parse public key
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing public key"
    );
    let verifying_key = VerifyingKey::from_sec1_bytes(public_key_bytes)
        .map_err(|e| CaptureAssertionError::InvalidPublicKey(format!("Failed to parse: {e}")))?;

    // Step 10: Parse signature (supports DER and raw r||s)
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing signature"
    );
    let signature = parse_signature(&assertion.signature)?;

    // Step 11: Verify signature
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Verifying signature"
    );
    verifying_key.verify(&message, &signature).map_err(|e| {
        CaptureAssertionError::SignatureInvalid(format!("Verification failed: {e}"))
    })?;

    Ok(auth_data.counter)
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Computes the clientDataHash for capture assertion binding
///
/// Different from request authentication which uses the request body.
/// For captures: clientDataHash = SHA256(photo_hash|captured_at)
fn compute_capture_client_data_hash(photo_hash: &str, captured_at: &str) -> [u8; 32] {
    let binding = format!("{photo_hash}|{captured_at}");
    Sha256::digest(binding.as_bytes()).into()
}

/// Parses CBOR assertion to extract authenticatorData and signature
fn parse_cbor_assertion(data: &[u8]) -> Result<ParsedAssertion, CaptureAssertionError> {
    let value: Value = ciborium::from_reader(data)
        .map_err(|e| CaptureAssertionError::InvalidCbor(e.to_string()))?;

    let map = value
        .as_map()
        .ok_or_else(|| CaptureAssertionError::InvalidCbor("Expected CBOR map".to_string()))?;

    // Extract authenticatorData
    let authenticator_data = map
        .iter()
        .find(|(k, _)| k.as_text() == Some("authenticatorData"))
        .and_then(|(_, v)| v.as_bytes())
        .map(|b| b.to_vec())
        .ok_or(CaptureAssertionError::MissingField("authenticatorData"))?;

    // Extract signature
    let signature = map
        .iter()
        .find(|(k, _)| k.as_text() == Some("signature"))
        .and_then(|(_, v)| v.as_bytes())
        .map(|b| b.to_vec())
        .ok_or(CaptureAssertionError::MissingField("signature"))?;

    Ok(ParsedAssertion {
        authenticator_data,
        signature,
    })
}

/// Parses authenticator data from assertion (37 bytes minimum)
/// Layout: rpIdHash(32) + flags(1) + counter(4)
fn parse_assertion_auth_data(data: &[u8]) -> Result<AssertionAuthData, CaptureAssertionError> {
    if data.len() < 37 {
        return Err(CaptureAssertionError::InvalidAuthData(format!(
            "Data too short: {} bytes, expected at least 37",
            data.len()
        )));
    }

    let rp_id_hash: [u8; 32] = data[0..32].try_into().map_err(|_| {
        CaptureAssertionError::InvalidAuthData("Failed to extract RP ID hash".to_string())
    })?;

    let flags = data[32];

    let counter = u32::from_be_bytes(data[33..37].try_into().map_err(|_| {
        CaptureAssertionError::InvalidAuthData("Failed to extract counter".to_string())
    })?);

    Ok(AssertionAuthData {
        rp_id_hash,
        flags,
        counter,
    })
}

/// Verifies the RP ID hash matches the expected app identity
fn verify_rp_id_hash(rp_id_hash: &[u8; 32], config: &Config) -> Result<(), CaptureAssertionError> {
    let app_id = format!("{}.{}", config.apple_team_id, config.apple_bundle_id);
    let expected_hash: [u8; 32] = Sha256::digest(app_id.as_bytes()).into();

    if rp_id_hash != &expected_hash {
        return Err(CaptureAssertionError::RpIdMismatch);
    }

    Ok(())
}

/// Parses signature bytes (supports both DER and raw r||s format)
fn parse_signature(sig_bytes: &[u8]) -> Result<Signature, CaptureAssertionError> {
    // Try DER format first (more common from Apple)
    if let Ok(sig) = Signature::from_der(sig_bytes) {
        return Ok(sig);
    }

    // Try raw r||s format (64 bytes for P-256)
    if sig_bytes.len() == 64 {
        if let Ok(sig) = Signature::from_slice(sig_bytes) {
            return Ok(sig);
        }
    }

    Err(CaptureAssertionError::SignatureInvalid(
        "Invalid signature format (not DER or raw r||s)".to_string(),
    ))
}

// ============================================================================
// Hash-Only Capture Verification (Story 8-4)
// ============================================================================

use crate::types::HashOnlyCapturePayload;

/// Verifies a hash-only capture assertion against the device's registered public key.
///
/// This function is BLOCKING: verification failures REJECT the upload with 401.
/// Unlike full captures where failures are recorded in evidence, hash-only captures
/// cannot verify the media itself - the assertion is the only proof.
///
/// ## Arguments
/// * `device` - The device that produced the capture
/// * `payload` - The HashOnlyCapturePayload (assertion is extracted from this)
/// * `config` - Application config (for RP ID verification)
/// * `request_id` - Request ID for logging
///
/// ## Returns
/// `Ok(CaptureAssertionResult)` on success, or `Err(CaptureAssertionError)` on failure.
/// The caller should convert errors to 401 Unauthorized responses.
pub fn verify_hash_only_assertion(
    device: &Device,
    payload: &HashOnlyCapturePayload,
    config: &Config,
    request_id: Uuid,
) -> Result<CaptureAssertionResult, CaptureAssertionError> {
    let device_model = device.model.clone();
    let level = AttestationLevel::from(device.attestation_level.as_str());
    let security_level = build_security_level_info(device);

    // Hash-only captures MUST have an assertion (validated earlier, but double-check)
    if payload.assertion.trim().is_empty() {
        tracing::warn!(
            request_id = %request_id,
            device_id = %device.id,
            "[capture_attestation] Hash-only capture missing assertion"
        );
        return Err(CaptureAssertionError::MissingField("assertion"));
    }

    // Perform verification
    let new_counter = verify_hash_only_assertion_internal(device, payload, config, request_id)?;

    tracing::info!(
        request_id = %request_id,
        device_id = %device.id,
        new_counter = new_counter,
        "[capture_attestation] Hash-only assertion verified successfully"
    );

    Ok(CaptureAssertionResult {
        status: CheckStatus::Pass,
        level,
        device_model,
        assertion_verified: true,
        counter_valid: true,
        new_counter: Some(new_counter),
        error_message: None,
        security_level,
    })
}

/// Internal verification logic for hash-only captures
fn verify_hash_only_assertion_internal(
    device: &Device,
    payload: &HashOnlyCapturePayload,
    config: &Config,
    request_id: Uuid,
) -> Result<u32, CaptureAssertionError> {
    // Step 1: Decode base64 assertion
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Decoding base64 assertion (hash-only)"
    );
    let assertion_bytes = STANDARD
        .decode(&payload.assertion)
        .map_err(|_| CaptureAssertionError::InvalidBase64)?;

    // Step 2: Parse CBOR assertion
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing CBOR assertion (hash-only)"
    );
    let assertion = parse_cbor_assertion(&assertion_bytes)?;

    // Step 3: Parse authenticator data
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing authenticator data (hash-only)"
    );
    let auth_data = parse_assertion_auth_data(&assertion.authenticator_data)?;

    // Step 4: Verify RP ID hash
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Verifying RP ID hash (hash-only)"
    );
    verify_rp_id_hash(&auth_data.rp_id_hash, config)?;

    // Step 5: Verify counter is strictly greater
    tracing::debug!(
        request_id = %request_id,
        received_counter = auth_data.counter,
        stored_counter = device.assertion_counter,
        "[capture_attestation] Verifying counter (hash-only)"
    );
    if (auth_data.counter as i64) <= device.assertion_counter {
        return Err(CaptureAssertionError::CounterNotIncreasing {
            received: auth_data.counter,
            stored: device.assertion_counter,
        });
    }

    // Step 6: Get device public key
    let public_key_bytes = device
        .public_key
        .as_ref()
        .ok_or(CaptureAssertionError::MissingPublicKey)?;

    // Step 7: Compute clientDataHash for hash-only binding
    // clientDataHash = SHA256(serialized payload JSON excluding assertion)
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Computing client data hash (hash-only)"
    );
    let client_data_hash = compute_hash_only_client_data_hash(payload);

    // Step 8: Build message = authenticatorData || clientDataHash
    let mut message = assertion.authenticator_data.clone();
    message.extend_from_slice(&client_data_hash);

    // Step 9: Parse public key
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing public key (hash-only)"
    );
    let verifying_key = VerifyingKey::from_sec1_bytes(public_key_bytes)
        .map_err(|e| CaptureAssertionError::InvalidPublicKey(format!("Failed to parse: {e}")))?;

    // Step 10: Parse signature
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Parsing signature (hash-only)"
    );
    let signature = parse_signature(&assertion.signature)?;

    // Step 11: Verify signature
    tracing::debug!(
        request_id = %request_id,
        "[capture_attestation] Verifying signature (hash-only)"
    );
    verifying_key.verify(&message, &signature).map_err(|e| {
        CaptureAssertionError::SignatureInvalid(format!("Verification failed: {e}"))
    })?;

    Ok(auth_data.counter)
}

/// Computes the clientDataHash for hash-only capture assertion binding.
///
/// CRITICAL: Must match iOS implementation exactly.
/// Creates a JSON object with all payload fields EXCEPT assertion,
/// serializes to bytes, and computes SHA-256 hash.
///
/// The fields are serialized in alphabetical key order by serde_json.
pub fn compute_hash_only_client_data_hash(payload: &HashOnlyCapturePayload) -> [u8; 32] {
    // Create JSON with all fields except assertion
    // Using serde_json::json! macro for consistent serialization
    let hashable = serde_json::json!({
        "capture_mode": payload.capture_mode,
        "captured_at": payload.captured_at,
        "depth_analysis": payload.depth_analysis,
        "media_hash": payload.media_hash,
        "media_type": payload.media_type,
        "metadata": payload.metadata,
        "metadata_flags": payload.metadata_flags,
    });

    // Serialize to bytes (serde_json::to_vec produces compact JSON)
    let json_bytes = serde_json::to_vec(&hashable).expect("JSON serialization should not fail");

    // Compute SHA-256 hash
    Sha256::digest(&json_bytes).into()
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;

    fn test_config() -> Config {
        Config::default_for_test()
    }

    fn test_device() -> Device {
        use chrono::Utc;
        Device {
            id: Uuid::new_v4(),
            attestation_level: "secure_enclave".to_string(),
            attestation_key_id: "test-key-id".to_string(),
            attestation_chain: None,
            platform: "iOS".to_string(),
            model: "iPhone 15 Pro".to_string(),
            has_lidar: true,
            first_seen_at: Utc::now(),
            last_seen_at: Utc::now(),
            assertion_counter: 5,
            public_key: None, // Will be set in individual tests
            security_level: Some("secure_enclave".to_string()), // Story 10-2
            keymaster_security_level: None, // Story 10-2
        }
    }

    #[test]
    fn test_verify_missing_assertion_returns_unavailable() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        let result = verify_capture_assertion(
            &device,
            None,
            "dGVzdC1oYXNo",
            "2025-11-23T10:00:00Z",
            &config,
            request_id,
        );

        assert_eq!(result.status, CheckStatus::Unavailable);
        assert!(!result.assertion_verified);
        assert!(!result.counter_valid);
        assert!(result.new_counter.is_none());
    }

    #[test]
    fn test_verify_empty_assertion_returns_unavailable() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        let result = verify_capture_assertion(
            &device,
            Some(""),
            "dGVzdC1oYXNo",
            "2025-11-23T10:00:00Z",
            &config,
            request_id,
        );

        assert_eq!(result.status, CheckStatus::Unavailable);
    }

    #[test]
    fn test_verify_whitespace_assertion_returns_unavailable() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        let result = verify_capture_assertion(
            &device,
            Some("   "),
            "dGVzdC1oYXNo",
            "2025-11-23T10:00:00Z",
            &config,
            request_id,
        );

        assert_eq!(result.status, CheckStatus::Unavailable);
    }

    #[test]
    fn test_verify_invalid_base64_returns_fail() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        let result = verify_capture_assertion(
            &device,
            Some("not-valid-base64!!!"),
            "dGVzdC1oYXNo",
            "2025-11-23T10:00:00Z",
            &config,
            request_id,
        );

        assert_eq!(result.status, CheckStatus::Fail);
        assert!(!result.assertion_verified);
        assert!(!result.counter_valid);
        assert!(result.error_message.is_some());
    }

    #[test]
    fn test_verify_invalid_cbor_returns_fail() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        // Valid base64 but invalid CBOR
        let invalid_cbor_b64 = STANDARD.encode([0xFF, 0xFF, 0xFF]);

        let result = verify_capture_assertion(
            &device,
            Some(&invalid_cbor_b64),
            "dGVzdC1oYXNo",
            "2025-11-23T10:00:00Z",
            &config,
            request_id,
        );

        assert_eq!(result.status, CheckStatus::Fail);
    }

    #[test]
    fn test_compute_capture_client_data_hash() {
        let hash1 = compute_capture_client_data_hash("abc123", "2025-11-23T10:00:00Z");
        let hash2 = compute_capture_client_data_hash("abc123", "2025-11-23T10:00:00Z");
        let hash3 = compute_capture_client_data_hash("different", "2025-11-23T10:00:00Z");

        // Same inputs should produce same hash
        assert_eq!(hash1, hash2);
        // Different inputs should produce different hash
        assert_ne!(hash1, hash3);
    }

    #[test]
    fn test_parse_assertion_auth_data_too_short() {
        let data = vec![0u8; 36]; // Less than 37 bytes
        let result = parse_assertion_auth_data(&data);
        assert!(matches!(
            result,
            Err(CaptureAssertionError::InvalidAuthData(_))
        ));
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
    fn test_verify_rp_id_hash_match() {
        let config = Config {
            apple_team_id: "XXXXXXXXXX".to_string(),
            apple_bundle_id: "com.test.app".to_string(),
            ..Config::default_for_test()
        };

        // Compute correct hash
        let app_id = format!("{}.{}", config.apple_team_id, config.apple_bundle_id);
        let expected_hash: [u8; 32] = Sha256::digest(app_id.as_bytes()).into();

        let result = verify_rp_id_hash(&expected_hash, &config);
        assert!(result.is_ok());
    }

    #[test]
    fn test_verify_rp_id_hash_mismatch() {
        let config = Config {
            apple_team_id: "XXXXXXXXXX".to_string(),
            apple_bundle_id: "com.test.app".to_string(),
            ..Config::default_for_test()
        };

        let wrong_hash = [0u8; 32];
        let result = verify_rp_id_hash(&wrong_hash, &config);
        assert!(matches!(result, Err(CaptureAssertionError::RpIdMismatch)));
    }

    #[test]
    fn test_hardware_attestation_from_result() {
        let result = CaptureAssertionResult {
            status: CheckStatus::Pass,
            level: AttestationLevel::SecureEnclave,
            device_model: "iPhone 15 Pro".to_string(),
            assertion_verified: true,
            counter_valid: true,
            new_counter: Some(10),
            error_message: None,
            security_level: Some(SecurityLevelInfo {
                attestation_level: "secure_enclave".to_string(),
                keymaster_level: None,
                platform: "ios".to_string(),
            }),
        };

        let hw: HardwareAttestation = result.into();
        assert_eq!(hw.status, CheckStatus::Pass);
        assert_eq!(hw.level, AttestationLevel::SecureEnclave);
        assert_eq!(hw.device_model, "iPhone 15 Pro");
        assert!(hw.assertion_verified);
        assert!(hw.counter_valid);
        assert!(hw.security_level.is_some());
        let sl = hw.security_level.unwrap();
        assert_eq!(sl.attestation_level, "secure_enclave");
        assert_eq!(sl.platform, "ios");
    }

    #[test]
    fn test_parse_cbor_assertion_missing_authenticator_data() {
        // CBOR map with only signature, missing authenticatorData
        let mut cbor_bytes = Vec::new();
        ciborium::into_writer(
            &ciborium::Value::Map(vec![(
                ciborium::Value::Text("signature".to_string()),
                ciborium::Value::Bytes(vec![1, 2, 3]),
            )]),
            &mut cbor_bytes,
        )
        .unwrap();

        let result = parse_cbor_assertion(&cbor_bytes);
        assert!(matches!(
            result,
            Err(CaptureAssertionError::MissingField("authenticatorData"))
        ));
    }

    #[test]
    fn test_parse_cbor_assertion_missing_signature() {
        // CBOR map with only authenticatorData, missing signature
        let mut cbor_bytes = Vec::new();
        ciborium::into_writer(
            &ciborium::Value::Map(vec![(
                ciborium::Value::Text("authenticatorData".to_string()),
                ciborium::Value::Bytes(vec![0; 37]),
            )]),
            &mut cbor_bytes,
        )
        .unwrap();

        let result = parse_cbor_assertion(&cbor_bytes);
        assert!(matches!(
            result,
            Err(CaptureAssertionError::MissingField("signature"))
        ));
    }

    #[test]
    fn test_parse_cbor_assertion_valid() {
        // CBOR map with both fields
        let mut cbor_bytes = Vec::new();
        ciborium::into_writer(
            &ciborium::Value::Map(vec![
                (
                    ciborium::Value::Text("authenticatorData".to_string()),
                    ciborium::Value::Bytes(vec![0; 37]),
                ),
                (
                    ciborium::Value::Text("signature".to_string()),
                    ciborium::Value::Bytes(vec![1, 2, 3, 4]),
                ),
            ]),
            &mut cbor_bytes,
        )
        .unwrap();

        let result = parse_cbor_assertion(&cbor_bytes);
        assert!(result.is_ok());
        let assertion = result.unwrap();
        assert_eq!(assertion.authenticator_data.len(), 37);
        assert_eq!(assertion.signature, vec![1, 2, 3, 4]);
    }

    // ========================================================================
    // Hash-Only Capture Tests (Story 8-4)
    // ========================================================================

    use crate::types::{ClientDepthAnalysis, FilteredMetadata, MetadataFlags};

    fn test_hash_only_payload() -> HashOnlyCapturePayload {
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

    #[test]
    fn test_compute_hash_only_client_data_hash_deterministic() {
        let payload = test_hash_only_payload();

        // Same payload should produce same hash
        let hash1 = compute_hash_only_client_data_hash(&payload);
        let hash2 = compute_hash_only_client_data_hash(&payload);
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_compute_hash_only_client_data_hash_different_payloads() {
        let payload1 = test_hash_only_payload();

        let mut payload2 = test_hash_only_payload();
        payload2.media_hash = "b".repeat(64);

        let hash1 = compute_hash_only_client_data_hash(&payload1);
        let hash2 = compute_hash_only_client_data_hash(&payload2);
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_compute_hash_only_client_data_hash_assertion_not_included() {
        let mut payload1 = test_hash_only_payload();
        payload1.assertion = "assertion1".to_string();

        let mut payload2 = test_hash_only_payload();
        payload2.assertion = "different_assertion".to_string();

        // Assertion field should be excluded from hash, so hashes should be equal
        let hash1 = compute_hash_only_client_data_hash(&payload1);
        let hash2 = compute_hash_only_client_data_hash(&payload2);
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_verify_hash_only_empty_assertion_fails() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        let mut payload = test_hash_only_payload();
        payload.assertion = "".to_string();

        let result = verify_hash_only_assertion(&device, &payload, &config, request_id);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CaptureAssertionError::MissingField("assertion")
        ));
    }

    #[test]
    fn test_verify_hash_only_whitespace_assertion_fails() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        let mut payload = test_hash_only_payload();
        payload.assertion = "   ".to_string();

        let result = verify_hash_only_assertion(&device, &payload, &config, request_id);
        assert!(result.is_err());
    }

    #[test]
    fn test_verify_hash_only_invalid_base64_fails() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        let mut payload = test_hash_only_payload();
        payload.assertion = "not-valid-base64!!!".to_string();

        let result = verify_hash_only_assertion(&device, &payload, &config, request_id);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CaptureAssertionError::InvalidBase64
        ));
    }

    // ========================================================================
    // Story 10-2: Security Level Info Tests
    // ========================================================================

    #[test]
    fn test_build_security_level_info_ios() {
        use chrono::Utc;
        let device = Device {
            id: Uuid::new_v4(),
            attestation_level: "secure_enclave".to_string(),
            attestation_key_id: "test".to_string(),
            attestation_chain: None,
            platform: "iOS".to_string(),
            model: "iPhone 15 Pro".to_string(),
            has_lidar: true,
            first_seen_at: Utc::now(),
            last_seen_at: Utc::now(),
            assertion_counter: 0,
            public_key: None,
            security_level: Some("secure_enclave".to_string()),
            keymaster_security_level: None,
        };

        let info = build_security_level_info(&device);
        assert!(info.is_some());
        let info = info.unwrap();
        assert_eq!(info.attestation_level, "secure_enclave");
        assert!(info.keymaster_level.is_none());
        assert_eq!(info.platform, "ios"); // lowercase
    }

    #[test]
    fn test_build_security_level_info_android_strongbox() {
        use chrono::Utc;
        let device = Device {
            id: Uuid::new_v4(),
            attestation_level: "strongbox".to_string(),
            attestation_key_id: "test".to_string(),
            attestation_chain: None,
            platform: "Android".to_string(),
            model: "Pixel 8 Pro".to_string(),
            has_lidar: false,
            first_seen_at: Utc::now(),
            last_seen_at: Utc::now(),
            assertion_counter: 0,
            public_key: None,
            security_level: Some("strongbox".to_string()),
            keymaster_security_level: Some("strongbox".to_string()),
        };

        let info = build_security_level_info(&device);
        assert!(info.is_some());
        let info = info.unwrap();
        assert_eq!(info.attestation_level, "strongbox");
        assert_eq!(info.keymaster_level, Some("strongbox".to_string()));
        assert_eq!(info.platform, "android");
    }

    #[test]
    fn test_build_security_level_info_unverified() {
        use chrono::Utc;
        let device = Device {
            id: Uuid::new_v4(),
            attestation_level: "unverified".to_string(),
            attestation_key_id: "test".to_string(),
            attestation_chain: None,
            platform: "iOS".to_string(),
            model: "iPhone 15".to_string(),
            has_lidar: false,
            first_seen_at: Utc::now(),
            last_seen_at: Utc::now(),
            assertion_counter: 0,
            public_key: None,
            security_level: None, // Unverified devices have no security level
            keymaster_security_level: None,
        };

        let info = build_security_level_info(&device);
        assert!(info.is_none()); // Should be None for unverified devices
    }

    #[test]
    fn test_verify_capture_assertion_includes_security_level() {
        let device = test_device();
        let config = test_config();
        let request_id = Uuid::new_v4();

        // Even when assertion is missing, security_level should be populated
        let result = verify_capture_assertion(
            &device,
            None,
            "dGVzdC1oYXNo",
            "2025-11-23T10:00:00Z",
            &config,
            request_id,
        );

        assert_eq!(result.status, CheckStatus::Unavailable);
        // test_device() has security_level set
        assert!(result.security_level.is_some());
        let sl = result.security_level.unwrap();
        assert_eq!(sl.attestation_level, "secure_enclave");
        assert_eq!(sl.platform, "ios");
    }
}
