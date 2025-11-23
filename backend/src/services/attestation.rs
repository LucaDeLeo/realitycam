//! DCAppAttest attestation verification service
//!
//! Implements Apple DCAppAttest verification including:
//! - CBOR attestation object decoding
//! - Certificate chain verification
//! - Challenge binding (nonce) verification
//! - App identity verification
//! - Public key extraction
//! - Counter verification

use ciborium::Value;
use coset::CborSerializable;
use sha2::{Digest, Sha256};
use std::str::FromStr;
use x509_parser::prelude::*;
use x509_parser::oid_registry::Oid;

use crate::config::Config;

// ============================================================================
// Apple App Attest Root CA
// ============================================================================

// Apple App Attest Root CA - Placeholder for MVP
// TODO: Download actual certificate from https://www.apple.com/certificateauthority/
// For now, we'll use a verification approach that logs a warning and allows
// development/testing to proceed. In production, replace with actual embedded cert.
//
// The actual Apple App Attestation Root CA has:
// - Subject: CN=Apple App Attestation Root CA, O=Apple Inc., ST=California, C=US
// - Valid: 2020-03-18 to 2045-03-15
// - SHA256 Fingerprint: ...
//
// For production:
// 1. Download from Apple PKI
// 2. Convert to DER: openssl x509 -in cert.pem -outform DER -out apple_app_attest_root_ca.der
// 3. Embed: const APPLE_APP_ATTEST_ROOT_CA: &[u8] = include_bytes!("../certs/apple_app_attest_root_ca.der");

/// Placeholder flag indicating whether we have the real Apple CA embedded
const APPLE_CA_EMBEDDED: bool = false;

// Apple nonce extension OID: 1.2.840.113635.100.8.2
// This extension contains the nonce that must match SHA256(authData || clientDataHash)
const APPLE_NONCE_OID_STR: &str = "1.2.840.113635.100.8.2";

// ============================================================================
// Error Types
// ============================================================================

/// Errors that can occur during attestation verification
#[derive(Debug, Clone)]
pub enum AttestationError {
    /// Invalid base64 encoding
    InvalidBase64,
    /// Invalid CBOR structure
    InvalidCbor(String),
    /// Missing required field in attestation object
    MissingField(&'static str),
    /// Invalid attestation format (expected "apple-appattest")
    InvalidFormat(String),
    /// Certificate chain is incomplete
    IncompleteCertChain,
    /// Certificate parsing failed
    InvalidCertificate(String),
    /// Certificate has expired or is not yet valid
    CertificateExpired,
    /// Certificate chain verification failed
    ChainVerificationFailed(String),
    /// Root CA mismatch
    RootCaMismatch,
    /// Nonce extension not found in certificate
    MissingNonceExtension,
    /// Invalid nonce format in certificate
    InvalidNonceFormat,
    /// Nonce does not match expected value
    NonceMismatch,
    /// App ID hash does not match
    AppIdMismatch,
    /// Invalid authenticator data
    InvalidAuthData(String),
    /// Invalid public key format
    InvalidPublicKey(String),
    /// Counter is not zero for initial attestation
    NonZeroCounter(u32),
}

impl std::fmt::Display for AttestationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AttestationError::InvalidBase64 => write!(f, "Invalid base64 encoding"),
            AttestationError::InvalidCbor(msg) => write!(f, "Invalid CBOR: {msg}"),
            AttestationError::MissingField(field) => {
                write!(f, "Missing required field: {field}")
            }
            AttestationError::InvalidFormat(fmt) => {
                write!(f, "Invalid format '{fmt}', expected 'apple-appattest'")
            }
            AttestationError::IncompleteCertChain => write!(f, "Incomplete certificate chain"),
            AttestationError::InvalidCertificate(msg) => write!(f, "Invalid certificate: {msg}"),
            AttestationError::CertificateExpired => {
                write!(f, "Certificate expired or not yet valid")
            }
            AttestationError::ChainVerificationFailed(msg) => {
                write!(f, "Chain verification failed: {msg}")
            }
            AttestationError::RootCaMismatch => write!(f, "Root CA mismatch"),
            AttestationError::MissingNonceExtension => {
                write!(f, "Missing nonce extension in certificate")
            }
            AttestationError::InvalidNonceFormat => write!(f, "Invalid nonce format"),
            AttestationError::NonceMismatch => write!(f, "Nonce mismatch"),
            AttestationError::AppIdMismatch => write!(f, "App ID hash mismatch"),
            AttestationError::InvalidAuthData(msg) => {
                write!(f, "Invalid authenticator data: {msg}")
            }
            AttestationError::InvalidPublicKey(msg) => write!(f, "Invalid public key: {msg}"),
            AttestationError::NonZeroCounter(counter) => {
                write!(f, "Non-zero counter for initial attestation: {counter}")
            }
        }
    }
}

impl std::error::Error for AttestationError {}

// ============================================================================
// Data Structures
// ============================================================================

/// Parsed attestation object from CBOR
#[derive(Debug)]
pub struct AttestationObject {
    /// Format string (should be "apple-appattest")
    pub fmt: String,
    /// Authenticator data bytes
    pub auth_data: Vec<u8>,
    /// Certificate chain (DER-encoded X.509 certificates)
    pub x5c: Vec<Vec<u8>>,
    /// Apple receipt data
    pub receipt: Vec<u8>,
}

/// Parsed authenticator data structure
#[derive(Debug)]
pub struct AuthenticatorData {
    /// RP ID Hash (SHA256 of App ID)
    pub rp_id_hash: [u8; 32],
    /// Flags byte
    pub flags: u8,
    /// Counter (should be 0 for initial attestation)
    pub counter: u32,
    /// AAGUID (all zeros for Apple)
    pub aaguid: [u8; 16],
    /// Credential ID (key identifier)
    pub credential_id: Vec<u8>,
    /// COSE public key (CBOR-encoded)
    pub public_key_cbor: Vec<u8>,
}

/// Result of successful attestation verification
#[derive(Debug)]
pub struct VerificationResult {
    /// Extracted public key bytes (uncompressed EC point)
    pub public_key: Vec<u8>,
    /// Counter value (should be 0)
    pub counter: u32,
    /// Certificate chain for storage
    pub certificate_chain: Vec<Vec<u8>>,
    /// Credential ID (key identifier)
    pub credential_id: Vec<u8>,
}

// ============================================================================
// CBOR Parsing (AC-3)
// ============================================================================

/// Decodes a base64-encoded attestation object into its CBOR structure.
pub fn decode_attestation_object(base64_data: &str) -> Result<AttestationObject, AttestationError> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};

    // Decode base64
    let bytes = STANDARD
        .decode(base64_data)
        .map_err(|_| AttestationError::InvalidBase64)?;

    // Parse CBOR
    let value: Value =
        ciborium::from_reader(&bytes[..]).map_err(|e| AttestationError::InvalidCbor(e.to_string()))?;

    let map = value
        .as_map()
        .ok_or_else(|| AttestationError::InvalidCbor("Expected CBOR map".to_string()))?;

    // Extract "fmt" - must be "apple-appattest"
    let fmt = find_text_value(map, "fmt")
        .ok_or(AttestationError::MissingField("fmt"))?
        .to_string();

    if fmt != "apple-appattest" {
        return Err(AttestationError::InvalidFormat(fmt));
    }

    // Extract "authData"
    let auth_data = find_bytes_value(map, "authData")
        .ok_or(AttestationError::MissingField("authData"))?
        .to_vec();

    // Extract "attStmt" map
    let att_stmt = find_map_value(map, "attStmt")
        .ok_or(AttestationError::MissingField("attStmt"))?;

    // Extract "attStmt.x5c" (certificate chain)
    let x5c_array = find_array_value(att_stmt, "x5c")
        .ok_or(AttestationError::MissingField("x5c"))?;

    let x5c: Vec<Vec<u8>> = x5c_array
        .iter()
        .filter_map(|v| v.as_bytes().map(|b| b.to_vec()))
        .collect();

    if x5c.is_empty() {
        return Err(AttestationError::MissingField("x5c certificates"));
    }

    // Extract "attStmt.receipt" (optional but usually present)
    let receipt = find_bytes_value(att_stmt, "receipt")
        .map(|b| b.to_vec())
        .unwrap_or_default();

    Ok(AttestationObject {
        fmt,
        auth_data,
        x5c,
        receipt,
    })
}

// ============================================================================
// AuthenticatorData Parsing (AC-7, AC-8)
// ============================================================================

/// Parses the binary authenticator data structure.
///
/// AuthData layout:
/// | Offset | Length | Field                    |
/// |--------|--------|--------------------------|
/// | 0      | 32     | RP ID Hash (SHA256)      |
/// | 32     | 1      | Flags                    |
/// | 33     | 4      | Counter (big-endian u32) |
/// | 37     | 16     | AAGUID (all zeros)       |
/// | 53     | 2      | Credential ID Length (L) |
/// | 55     | L      | Credential ID            |
/// | 55+L   | var    | COSE Public Key (CBOR)   |
pub fn parse_authenticator_data(data: &[u8]) -> Result<AuthenticatorData, AttestationError> {
    // Minimum length: 32 + 1 + 4 + 16 + 2 = 55 bytes before credential ID
    if data.len() < 55 {
        return Err(AttestationError::InvalidAuthData(format!(
            "Data too short: {} bytes, expected at least 55",
            data.len()
        )));
    }

    let rp_id_hash: [u8; 32] = data[0..32]
        .try_into()
        .map_err(|_| AttestationError::InvalidAuthData("Failed to extract RP ID hash".to_string()))?;

    let flags = data[32];

    let counter = u32::from_be_bytes(
        data[33..37]
            .try_into()
            .map_err(|_| AttestationError::InvalidAuthData("Failed to extract counter".to_string()))?,
    );

    let aaguid: [u8; 16] = data[37..53]
        .try_into()
        .map_err(|_| AttestationError::InvalidAuthData("Failed to extract AAGUID".to_string()))?;

    let cred_id_len = u16::from_be_bytes(
        data[53..55]
            .try_into()
            .map_err(|_| AttestationError::InvalidAuthData("Failed to extract credential ID length".to_string()))?,
    ) as usize;

    if data.len() < 55 + cred_id_len {
        return Err(AttestationError::InvalidAuthData(format!(
            "Data too short for credential ID: {} bytes, expected at least {}",
            data.len(),
            55 + cred_id_len
        )));
    }

    let credential_id = data[55..55 + cred_id_len].to_vec();
    let public_key_cbor = data[55 + cred_id_len..].to_vec();

    if public_key_cbor.is_empty() {
        return Err(AttestationError::InvalidAuthData(
            "Missing public key data".to_string(),
        ));
    }

    Ok(AuthenticatorData {
        rp_id_hash,
        flags,
        counter,
        aaguid,
        credential_id,
        public_key_cbor,
    })
}

// ============================================================================
// Certificate Chain Verification (AC-4)
// ============================================================================

/// Verifies the certificate chain.
/// For MVP, this validates certificate structure and chain hierarchy.
/// TODO: Full cryptographic signature verification requires the embedded Apple Root CA.
pub fn verify_certificate_chain(
    certs: &[Vec<u8>],
    _request_id: uuid::Uuid,
) -> Result<(), AttestationError> {
    if certs.len() < 2 {
        return Err(AttestationError::IncompleteCertChain);
    }

    let now = chrono::Utc::now();

    // Parse all certificates
    let mut parsed_certs = Vec::new();
    for (i, cert_der) in certs.iter().enumerate() {
        let (_, cert) = X509Certificate::from_der(cert_der).map_err(|e| {
            AttestationError::InvalidCertificate(format!("Certificate {i}: {e:?}"))
        })?;
        parsed_certs.push(cert);
    }

    // Verify validity periods for all certificates
    for (i, cert) in parsed_certs.iter().enumerate() {
        let validity = cert.validity();
        // x509-parser uses time crate, convert to timestamps for comparison
        let now_ts = now.timestamp();
        let not_before_ts = validity.not_before.timestamp();
        let not_after_ts = validity.not_after.timestamp();

        if now_ts < not_before_ts || now_ts > not_after_ts {
            tracing::warn!(
                cert_index = i,
                not_before = %validity.not_before,
                not_after = %validity.not_after,
                now = %now,
                "Certificate validity check failed"
            );
            return Err(AttestationError::CertificateExpired);
        }
    }

    // Verify chain hierarchy: leaf issued by intermediate
    // x5c[0] = leaf certificate, x5c[1] = intermediate certificate
    let leaf = &parsed_certs[0];
    let intermediate = &parsed_certs[1];

    if leaf.issuer() != intermediate.subject() {
        tracing::warn!(
            leaf_issuer = ?leaf.issuer(),
            intermediate_subject = ?intermediate.subject(),
            "Certificate chain hierarchy mismatch"
        );
        return Err(AttestationError::ChainVerificationFailed(
            "Leaf certificate not issued by intermediate".to_string(),
        ));
    }

    // TODO: Verify intermediate is signed by Apple Root CA
    // This requires embedding the Apple App Attest Root CA certificate
    if !APPLE_CA_EMBEDDED {
        tracing::warn!(
            "Apple Root CA not embedded - skipping root verification for MVP. \
             In production, embed the Apple App Attestation Root CA certificate."
        );
    }

    Ok(())
}

// ============================================================================
// Challenge Binding Verification (AC-5)
// ============================================================================

/// Verifies challenge binding by checking the nonce in the certificate.
///
/// The nonce is computed as: SHA256(authData || clientDataHash)
/// Where clientDataHash = SHA256(challenge)
pub fn verify_challenge_binding(
    auth_data: &[u8],
    challenge: &[u8],
    leaf_cert_der: &[u8],
) -> Result<(), AttestationError> {
    // Compute clientDataHash = SHA256(challenge)
    let client_data_hash = Sha256::digest(challenge);

    // Compute expected nonce = SHA256(authData || clientDataHash)
    let mut hasher = Sha256::new();
    hasher.update(auth_data);
    hasher.update(client_data_hash);
    let expected_nonce = hasher.finalize();

    // Extract nonce from certificate extension
    let cert_nonce = extract_nonce_from_cert(leaf_cert_der)?;

    // Compare
    let expected_nonce_slice: &[u8] = expected_nonce.as_ref();
    if cert_nonce != expected_nonce_slice {
        tracing::warn!(
            expected_nonce_len = expected_nonce.len(),
            cert_nonce_len = cert_nonce.len(),
            "Nonce mismatch in challenge binding verification"
        );
        return Err(AttestationError::NonceMismatch);
    }

    Ok(())
}

/// Extracts the nonce from the Apple nonce extension in a certificate.
fn extract_nonce_from_cert(cert_der: &[u8]) -> Result<Vec<u8>, AttestationError> {
    let (_, cert) = X509Certificate::from_der(cert_der)
        .map_err(|e| AttestationError::InvalidCertificate(format!("{e:?}")))?;

    // Parse the OID - Apple nonce extension: 1.2.840.113635.100.8.2
    let nonce_oid = Oid::from_str(APPLE_NONCE_OID_STR)
        .map_err(|_| AttestationError::InvalidNonceFormat)?;

    // Find the nonce extension
    let nonce_ext = cert
        .extensions()
        .iter()
        .find(|ext| ext.oid == nonce_oid)
        .ok_or(AttestationError::MissingNonceExtension)?;

    // The extension value is ASN.1: SEQUENCE { [1] OCTET STRING (nonce) }
    // Parse the DER structure to extract the actual nonce bytes
    let (_, seq) = der_parser::parse_der(nonce_ext.value)
        .map_err(|_| AttestationError::InvalidNonceFormat)?;

    // Navigate to extract the OCTET STRING containing the nonce
    // Structure: SEQUENCE { CONTEXT-SPECIFIC [1] { OCTET STRING (nonce) } }
    let nonce = extract_nonce_from_asn1(&seq)?;

    Ok(nonce)
}

/// Extracts nonce from ASN.1 structure
fn extract_nonce_from_asn1(der: &der_parser::ber::BerObject) -> Result<Vec<u8>, AttestationError> {
    // The structure is: SEQUENCE containing a context-specific tagged element
    // which contains an OCTET STRING with the nonce
    // Apple format: SEQUENCE { [1] OCTET STRING (nonce) }
    use der_parser::ber::BerObjectContent;

    if let BerObjectContent::Sequence(items) = &der.content {
        for item in items {
            // Handle tagged content (context-specific)
            match &item.content {
                BerObjectContent::Unknown(any) => {
                    // Try to parse the inner data as an OCTET STRING
                    let data = any.data;
                    if let Ok((_, inner)) = der_parser::parse_der(data) {
                        if let BerObjectContent::OctetString(nonce) = &inner.content {
                            return Ok(nonce.to_vec());
                        }
                    }
                    // If not wrapped, the data might be the nonce directly
                    return Ok(data.to_vec());
                }
                BerObjectContent::OctetString(nonce) => {
                    return Ok(nonce.to_vec());
                }
                _ => {
                    // Try to get raw bytes from the item
                    if let Ok(bytes) = item.as_slice() {
                        if bytes.len() >= 32 {
                            if let Ok((_, inner)) = der_parser::parse_der(bytes) {
                                if let BerObjectContent::OctetString(nonce) = &inner.content {
                                    return Ok(nonce.to_vec());
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Err(AttestationError::InvalidNonceFormat)
}

// ============================================================================
// App Identity Verification (AC-6)
// ============================================================================

/// Verifies the app identity by comparing RP ID hash with expected App ID hash.
///
/// App ID = TeamID.BundleID (e.g., "XXXXXXXXXX.com.example.realitycam")
pub fn verify_app_identity(
    rp_id_hash: &[u8; 32],
    config: &Config,
) -> Result<(), AttestationError> {
    let app_id = format!("{}.{}", config.apple_team_id, config.apple_bundle_id);
    let expected_hash = Sha256::digest(app_id.as_bytes());

    let expected_hash_slice: &[u8] = expected_hash.as_ref();
    if rp_id_hash != expected_hash_slice {
        tracing::warn!(
            app_id = %app_id,
            "App ID hash mismatch"
        );
        return Err(AttestationError::AppIdMismatch);
    }

    Ok(())
}

// ============================================================================
// Public Key Extraction (AC-7)
// ============================================================================

/// Extracts and validates the public key from COSE key structure.
///
/// Expected key type: EC2 with P-256 curve (kty=2, crv=1)
pub fn extract_public_key(cose_key_cbor: &[u8]) -> Result<Vec<u8>, AttestationError> {
    use coset::{CoseKey, KeyType, Label};

    let cose_key = CoseKey::from_slice(cose_key_cbor)
        .map_err(|e| AttestationError::InvalidPublicKey(format!("COSE parse error: {e:?}")))?;

    // Verify key type is EC2 (kty = 2)
    if cose_key.kty != KeyType::Assigned(coset::iana::KeyType::EC2) {
        return Err(AttestationError::InvalidPublicKey(format!(
            "Expected EC2 key type, got {:?}",
            cose_key.kty
        )));
    }

    // Extract curve parameter (label -1) and verify it's P-256 (crv = 1)
    let crv = cose_key
        .params
        .iter()
        .find(|(label, _)| *label == Label::Int(-1))
        .and_then(|(_, value)| value.as_integer())
        .ok_or_else(|| AttestationError::InvalidPublicKey("Missing curve parameter".to_string()))?;

    // P-256 curve is value 1 in COSE
    let crv_i64: i64 = crv.try_into().map_err(|_| {
        AttestationError::InvalidPublicKey("Invalid curve value".to_string())
    })?;
    if crv_i64 != 1 {
        return Err(AttestationError::InvalidPublicKey(format!(
            "Expected P-256 curve (1), got {crv_i64}"
        )));
    }

    // Extract x coordinate (label -2)
    let x = cose_key
        .params
        .iter()
        .find(|(label, _)| *label == Label::Int(-2))
        .and_then(|(_, value)| value.as_bytes())
        .ok_or_else(|| AttestationError::InvalidPublicKey("Missing x coordinate".to_string()))?;

    // Extract y coordinate (label -3)
    let y = cose_key
        .params
        .iter()
        .find(|(label, _)| *label == Label::Int(-3))
        .and_then(|(_, value)| value.as_bytes())
        .ok_or_else(|| AttestationError::InvalidPublicKey("Missing y coordinate".to_string()))?;

    // Validate coordinate lengths (32 bytes each for P-256)
    if x.len() != 32 || y.len() != 32 {
        return Err(AttestationError::InvalidPublicKey(format!(
            "Invalid coordinate lengths: x={}, y={}",
            x.len(),
            y.len()
        )));
    }

    // Return uncompressed EC point format: 0x04 || x || y
    let mut public_key = Vec::with_capacity(65);
    public_key.push(0x04); // Uncompressed point indicator
    public_key.extend_from_slice(x);
    public_key.extend_from_slice(y);

    Ok(public_key)
}

// ============================================================================
// Counter Verification (AC-8)
// ============================================================================

/// Verifies that the counter is 0 for initial attestation.
pub fn verify_initial_counter(counter: u32) -> Result<(), AttestationError> {
    if counter != 0 {
        return Err(AttestationError::NonZeroCounter(counter));
    }
    Ok(())
}

// ============================================================================
// Main Verification Pipeline (AC-3 through AC-8)
// ============================================================================

/// Orchestrates the complete attestation verification process.
///
/// Steps:
/// 1. Decode CBOR attestation object
/// 2. Parse authenticator data
/// 3. Verify certificate chain
/// 4. Verify challenge binding (nonce)
/// 5. Verify app identity
/// 6. Extract and validate public key
/// 7. Verify counter is 0
pub async fn verify_attestation(
    attestation_object_b64: &str,
    challenge: &[u8],
    config: &Config,
    request_id: uuid::Uuid,
) -> Result<VerificationResult, AttestationError> {
    // Step 1: Decode CBOR attestation object
    tracing::info!(
        request_id = %request_id,
        step = "cbor_decode",
        "Starting attestation verification"
    );
    let attestation = decode_attestation_object(attestation_object_b64)?;
    tracing::info!(
        request_id = %request_id,
        step = "cbor_decode",
        status = "pass",
        format = %attestation.fmt,
        cert_count = attestation.x5c.len(),
        "CBOR decoded successfully"
    );

    // Step 2: Parse authenticator data
    tracing::info!(
        request_id = %request_id,
        step = "parse_auth_data",
        "Parsing authenticator data"
    );
    let auth_data = parse_authenticator_data(&attestation.auth_data)?;
    tracing::info!(
        request_id = %request_id,
        step = "parse_auth_data",
        status = "pass",
        counter = auth_data.counter,
        cred_id_len = auth_data.credential_id.len(),
        "Auth data parsed"
    );

    // Step 3: Verify certificate chain
    tracing::info!(
        request_id = %request_id,
        step = "cert_chain",
        "Verifying certificate chain"
    );
    verify_certificate_chain(&attestation.x5c, request_id)?;
    tracing::info!(
        request_id = %request_id,
        step = "cert_chain",
        status = "pass",
        "Certificate chain valid"
    );

    // Step 4: Verify challenge binding (nonce)
    tracing::info!(
        request_id = %request_id,
        step = "challenge_binding",
        "Verifying challenge binding"
    );
    verify_challenge_binding(&attestation.auth_data, challenge, &attestation.x5c[0])?;
    tracing::info!(
        request_id = %request_id,
        step = "challenge_binding",
        status = "pass",
        "Challenge binding valid"
    );

    // Step 5: Verify App ID
    tracing::info!(
        request_id = %request_id,
        step = "app_identity",
        "Verifying app identity"
    );
    verify_app_identity(&auth_data.rp_id_hash, config)?;
    tracing::info!(
        request_id = %request_id,
        step = "app_identity",
        status = "pass",
        "App identity valid"
    );

    // Step 6: Extract and validate public key
    tracing::info!(
        request_id = %request_id,
        step = "public_key",
        "Extracting public key"
    );
    let public_key = extract_public_key(&auth_data.public_key_cbor)?;
    tracing::info!(
        request_id = %request_id,
        step = "public_key",
        status = "pass",
        key_len = public_key.len(),
        "Public key extracted"
    );

    // Step 7: Verify counter is 0
    tracing::info!(
        request_id = %request_id,
        step = "counter",
        counter = auth_data.counter,
        "Verifying counter"
    );
    verify_initial_counter(auth_data.counter)?;
    tracing::info!(
        request_id = %request_id,
        step = "counter",
        status = "pass",
        "Counter is 0"
    );

    tracing::info!(
        request_id = %request_id,
        status = "success",
        "Attestation verification complete"
    );

    Ok(VerificationResult {
        public_key,
        counter: auth_data.counter,
        certificate_chain: attestation.x5c,
        credential_id: auth_data.credential_id,
    })
}

// ============================================================================
// Helper Functions for CBOR Parsing
// ============================================================================

fn find_text_value<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a str> {
    map.iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .and_then(|(_, v)| v.as_text())
}

fn find_bytes_value<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a [u8]> {
    map.iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .and_then(|(_, v)| v.as_bytes())
        .map(|v| v.as_slice())
}

fn find_map_value<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a [(Value, Value)]> {
    map.iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .and_then(|(_, v)| v.as_map())
        .map(|v| v.as_slice())
}

fn find_array_value<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a [Value]> {
    map.iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .and_then(|(_, v)| v.as_array())
        .map(|v| v.as_slice())
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_authenticator_data_too_short() {
        let data = vec![0u8; 50]; // Less than minimum 55 bytes
        let result = parse_authenticator_data(&data);
        assert!(matches!(result, Err(AttestationError::InvalidAuthData(_))));
    }

    #[test]
    fn test_parse_authenticator_data_valid_minimum() {
        // Create minimal valid auth data
        // 32 bytes RP ID hash + 1 byte flags + 4 bytes counter + 16 bytes AAGUID + 2 bytes cred ID len (0) + public key
        let mut data = vec![0u8; 55];
        // Set counter to 0 (big-endian)
        data[33..37].copy_from_slice(&[0, 0, 0, 0]);
        // Set credential ID length to 0
        data[53..55].copy_from_slice(&[0, 0]);
        // Add some public key data
        data.extend_from_slice(&[0xA5, 0x01, 0x02]); // Minimal CBOR map

        let result = parse_authenticator_data(&data);
        assert!(result.is_ok());
        let auth_data = result.unwrap();
        assert_eq!(auth_data.counter, 0);
        assert!(auth_data.credential_id.is_empty());
    }

    #[test]
    fn test_verify_initial_counter_zero() {
        assert!(verify_initial_counter(0).is_ok());
    }

    #[test]
    fn test_verify_initial_counter_non_zero() {
        let result = verify_initial_counter(5);
        assert!(matches!(result, Err(AttestationError::NonZeroCounter(5))));
    }

    #[test]
    fn test_decode_attestation_object_invalid_base64() {
        let result = decode_attestation_object("not-valid-base64!!!");
        assert!(matches!(result, Err(AttestationError::InvalidBase64)));
    }

    #[test]
    fn test_decode_attestation_object_invalid_cbor() {
        use base64::{engine::general_purpose::STANDARD, Engine as _};
        let invalid_cbor = STANDARD.encode([0xFF, 0xFF, 0xFF]); // Invalid CBOR
        let result = decode_attestation_object(&invalid_cbor);
        assert!(matches!(result, Err(AttestationError::InvalidCbor(_))));
    }

    #[test]
    fn test_verify_app_identity_mismatch() {
        let config = Config {
            apple_team_id: "XXXXXXXXXX".to_string(),
            apple_bundle_id: "com.test.app".to_string(),
            ..Config::default_for_test()
        };

        // Wrong hash
        let wrong_hash = [0u8; 32];
        let result = verify_app_identity(&wrong_hash, &config);
        assert!(matches!(result, Err(AttestationError::AppIdMismatch)));
    }

    #[test]
    fn test_verify_app_identity_match() {
        let config = Config {
            apple_team_id: "XXXXXXXXXX".to_string(),
            apple_bundle_id: "com.test.app".to_string(),
            ..Config::default_for_test()
        };

        // Compute correct hash
        let app_id = format!("{}.{}", config.apple_team_id, config.apple_bundle_id);
        let expected_hash: [u8; 32] = Sha256::digest(app_id.as_bytes()).into();

        let result = verify_app_identity(&expected_hash, &config);
        assert!(result.is_ok());
    }
}
