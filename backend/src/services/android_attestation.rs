//! Android Key Attestation verification service
//!
//! Implements Android Key Attestation verification including:
//! - X.509 certificate chain parsing and verification
//! - Certificate chain verification to Google Hardware Attestation Root
//! - Key Attestation Extension (OID 1.3.6.1.4.1.11129.2.1.17) parsing
//! - KeyDescription ASN.1 structure parsing
//! - Security level extraction and validation
//! - Challenge freshness validation
//! - Public key extraction
//!
//! Reference: https://developer.android.com/privacy-and-security/security-key-attestation

use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::Utc;
use der_parser::ber::{BerObject, BerObjectContent};
use der_parser::oid::Oid;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use x509_parser::prelude::*;

use crate::config::Config;
use crate::services::challenge_store::ChallengeStore;

// ============================================================================
// Google Hardware Attestation Root Certificates
// ============================================================================

/// Google Hardware Attestation Root 1 (RSA) - Current production root
/// Subject: Serial Number = f92009e853b6b045
/// Valid: 2022-03-20 to 2042-03-15
const GOOGLE_HARDWARE_ATTESTATION_ROOT_1: &[u8] =
    include_bytes!("../../certs/google_hardware_attestation_root_1.der");

/// Google Hardware Attestation Root 2 (EC P-384) - New root effective Jul 2025
/// Subject: CN=Key Attestation CA1, OU=Android, O=Google LLC, C=US
/// Valid: 2025-07-17 to 2035-07-15
const GOOGLE_HARDWARE_ATTESTATION_ROOT_2: &[u8] =
    include_bytes!("../../certs/google_hardware_attestation_root_2.der");

// Android Key Attestation extension OID: 1.3.6.1.4.1.11129.2.1.17
const KEY_ATTESTATION_EXTENSION_OID: &[u64] = &[1, 3, 6, 1, 4, 1, 11129, 2, 1, 17];

// ============================================================================
// Error Types (AC10)
// ============================================================================

/// Errors that can occur during Android attestation verification
#[derive(Debug, Clone)]
pub enum AndroidAttestationError {
    // Certificate parsing
    /// Invalid base64 encoding in certificate chain
    InvalidBase64,
    /// Certificate parsing failed
    InvalidCertificate(String),
    /// Certificate chain is incomplete (less than 2 certificates)
    IncompleteCertChain,

    // Chain verification
    /// Certificate has expired or is not yet valid
    CertificateExpired,
    /// Certificate chain verification failed
    ChainVerificationFailed(String),
    /// Root CA does not match Google Hardware Attestation Root
    RootCaMismatch,

    // Attestation extension
    /// Key Attestation extension not found in leaf certificate
    MissingAttestationExtension,
    /// Invalid or unparseable attestation extension
    InvalidAttestationExtension(String),

    // Security level
    /// Software-only attestation rejected (FR72)
    SoftwareOnlyAttestation,

    // Challenge
    /// Challenge does not match server-issued challenge
    ChallengeMismatch,
    /// Challenge has expired (older than 5 minutes)
    ChallengeExpired,
    /// Challenge was not found in the store
    ChallengeNotFound,

    // Key extraction
    /// Invalid public key format
    InvalidPublicKey(String),
    /// Unsupported key type
    UnsupportedKeyType(String),
}

impl std::fmt::Display for AndroidAttestationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AndroidAttestationError::InvalidBase64 => write!(f, "Invalid base64 encoding"),
            AndroidAttestationError::InvalidCertificate(msg) => {
                write!(f, "Invalid certificate: {msg}")
            }
            AndroidAttestationError::IncompleteCertChain => {
                write!(f, "Incomplete certificate chain (minimum 2 required)")
            }
            AndroidAttestationError::CertificateExpired => {
                write!(f, "Certificate expired or not yet valid")
            }
            AndroidAttestationError::ChainVerificationFailed(msg) => {
                write!(f, "Chain verification failed: {msg}")
            }
            AndroidAttestationError::RootCaMismatch => {
                write!(f, "Root CA does not match Google Hardware Attestation Root")
            }
            AndroidAttestationError::MissingAttestationExtension => {
                write!(f, "Key Attestation extension not found in leaf certificate")
            }
            AndroidAttestationError::InvalidAttestationExtension(msg) => {
                write!(f, "Invalid attestation extension: {msg}")
            }
            AndroidAttestationError::SoftwareOnlyAttestation => {
                write!(
                    f,
                    "Software-only attestation rejected. Device requires TEE or StrongBox."
                )
            }
            AndroidAttestationError::ChallengeMismatch => {
                write!(f, "Challenge does not match server-issued challenge")
            }
            AndroidAttestationError::ChallengeExpired => {
                write!(f, "Challenge has expired")
            }
            AndroidAttestationError::ChallengeNotFound => {
                write!(f, "Challenge was not found")
            }
            AndroidAttestationError::InvalidPublicKey(msg) => {
                write!(f, "Invalid public key: {msg}")
            }
            AndroidAttestationError::UnsupportedKeyType(msg) => {
                write!(f, "Unsupported key type: {msg}")
            }
        }
    }
}

impl std::error::Error for AndroidAttestationError {}

// ============================================================================
// Security Level Types (AC3, AC4)
// ============================================================================

/// Android attestation security level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[repr(u8)]
pub enum SecurityLevel {
    /// Software: Key material in non-secure memory (REJECTED per FR72)
    Software = 0,
    /// TrustedEnvironment: Key material in TEE (MEDIUM trust)
    TrustedEnvironment = 1,
    /// StrongBox: Key material in hardware security module (HIGH trust)
    StrongBox = 2,
}

impl TryFrom<i64> for SecurityLevel {
    type Error = AndroidAttestationError;

    fn try_from(value: i64) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(SecurityLevel::Software),
            1 => Ok(SecurityLevel::TrustedEnvironment),
            2 => Ok(SecurityLevel::StrongBox),
            _ => Err(AndroidAttestationError::InvalidAttestationExtension(
                format!("Unknown security level: {value}"),
            )),
        }
    }
}

impl std::fmt::Display for SecurityLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SecurityLevel::Software => write!(f, "Software"),
            SecurityLevel::TrustedEnvironment => write!(f, "TrustedEnvironment"),
            SecurityLevel::StrongBox => write!(f, "StrongBox"),
        }
    }
}

/// Verified boot state from RootOfTrust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[repr(u8)]
pub enum VerifiedBootState {
    /// Boot chain is verified
    Verified = 0,
    /// Self-signed boot (custom ROM)
    SelfSigned = 1,
    /// Unverified boot (unlocked bootloader)
    Unverified = 2,
    /// Boot verification failed
    Failed = 3,
}

impl TryFrom<i64> for VerifiedBootState {
    type Error = AndroidAttestationError;

    fn try_from(value: i64) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(VerifiedBootState::Verified),
            1 => Ok(VerifiedBootState::SelfSigned),
            2 => Ok(VerifiedBootState::Unverified),
            3 => Ok(VerifiedBootState::Failed),
            _ => Err(AndroidAttestationError::InvalidAttestationExtension(
                format!("Unknown verified boot state: {value}"),
            )),
        }
    }
}

// ============================================================================
// Key Description and Authorization Structures (AC3, AC7)
// ============================================================================

/// Root of Trust information from attestation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RootOfTrust {
    /// Hash of verified boot key
    pub verified_boot_key: Vec<u8>,
    /// Whether device is locked
    pub device_locked: bool,
    /// Verified boot state
    pub verified_boot_state: VerifiedBootState,
    /// Hash of verified boot metadata (optional)
    pub verified_boot_hash: Option<Vec<u8>>,
}

/// Authorization list from KeyDescription
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AuthorizationList {
    // Key properties
    /// Key purpose (Tag 1)
    pub purpose: Option<Vec<i32>>,
    /// Algorithm (Tag 2)
    pub algorithm: Option<i32>,
    /// Key size in bits (Tag 3)
    pub key_size: Option<i32>,
    /// Key origin (Tag 702)
    pub origin: Option<i32>,

    // Device identity (for logging/debugging)
    /// Brand (Tag 710)
    pub attestation_id_brand: Option<Vec<u8>>,
    /// Device (Tag 711)
    pub attestation_id_device: Option<Vec<u8>>,
    /// Product (Tag 712)
    pub attestation_id_product: Option<Vec<u8>>,
    /// Serial number (Tag 713)
    pub attestation_id_serial: Option<Vec<u8>>,
    /// Manufacturer (Tag 716)
    pub attestation_id_manufacturer: Option<Vec<u8>>,
    /// Model (Tag 717)
    pub attestation_id_model: Option<Vec<u8>>,

    // Security properties
    /// OS version (Tag 705)
    pub os_version: Option<i32>,
    /// OS patch level YYYYMM (Tag 706)
    pub os_patch_level: Option<i32>,
    /// Vendor patch level (Tag 718)
    pub vendor_patch_level: Option<i32>,
    /// Boot patch level (Tag 719)
    pub boot_patch_level: Option<i32>,
    /// Root of trust (Tag 704)
    pub root_of_trust: Option<RootOfTrust>,
}

/// Key Description extracted from attestation extension
#[derive(Debug, Clone)]
pub struct KeyDescription {
    /// Attestation version
    pub attestation_version: i32,
    /// Attestation security level (PRIMARY indicator)
    pub attestation_security_level: SecurityLevel,
    /// KeyMaster/KeyMint version
    pub keymaster_version: i32,
    /// KeyMaster security level
    pub keymaster_security_level: SecurityLevel,
    /// Challenge bytes (must match server-issued challenge)
    pub attestation_challenge: Vec<u8>,
    /// Unique ID (device-specific, may be empty)
    pub unique_id: Vec<u8>,
    /// Software-enforced properties
    pub software_enforced: AuthorizationList,
    /// TEE-enforced properties
    pub tee_enforced: AuthorizationList,
}

// ============================================================================
// Result Structures (AC9)
// ============================================================================

/// Device information extracted from attestation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AndroidDeviceInfo {
    /// Device brand (e.g., "Google", "Samsung")
    pub brand: Option<String>,
    /// Device codename
    pub device: Option<String>,
    /// Product name
    pub product: Option<String>,
    /// Manufacturer
    pub manufacturer: Option<String>,
    /// Model name (e.g., "Pixel 8 Pro")
    pub model: Option<String>,
    /// OS version (YYYYMMDD format)
    pub os_version: Option<i32>,
    /// Security patch level (YYYYMM format)
    pub os_patch_level: Option<i32>,
}

/// Result of successful Android attestation verification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AndroidAttestationResult {
    /// Extracted public key bytes
    pub public_key: Vec<u8>,
    /// Attestation security level
    pub attestation_security_level: SecurityLevel,
    /// KeyMaster security level
    pub keymaster_security_level: SecurityLevel,
    /// Attestation version
    pub attestation_version: i32,
    /// KeyMaster version
    pub keymaster_version: i32,
    /// Full certificate chain (DER-encoded)
    pub certificate_chain: Vec<Vec<u8>>,
    /// Extracted device info
    pub device_info: AndroidDeviceInfo,
    /// Root of trust information
    pub root_of_trust: Option<RootOfTrust>,
}

// ============================================================================
// Certificate Chain Parsing (AC1)
// ============================================================================

/// Parsed attestation object from certificate chain
#[derive(Debug)]
pub struct AndroidAttestationObject {
    /// DER-encoded certificate chain
    pub certificate_chain: Vec<Vec<u8>>,
    /// Parsed leaf certificate
    pub leaf_cert_der: Vec<u8>,
}

/// Parses a base64-encoded certificate chain.
///
/// Expected input: JSON array of base64-encoded DER certificates
/// Chain order: [leaf, intermediate(s)..., root]
pub fn parse_certificate_chain(
    certs_base64: &[String],
) -> Result<AndroidAttestationObject, AndroidAttestationError> {
    if certs_base64.len() < 2 {
        return Err(AndroidAttestationError::IncompleteCertChain);
    }

    let mut certificate_chain = Vec::with_capacity(certs_base64.len());

    for (i, cert_b64) in certs_base64.iter().enumerate() {
        let cert_der = STANDARD
            .decode(cert_b64)
            .map_err(|_| AndroidAttestationError::InvalidBase64)?;

        // Validate it's a valid X.509 certificate
        X509Certificate::from_der(&cert_der)
            .map_err(|e| AndroidAttestationError::InvalidCertificate(format!("Cert {i}: {e:?}")))?;

        certificate_chain.push(cert_der);
    }

    let leaf_cert_der = certificate_chain[0].clone();

    Ok(AndroidAttestationObject {
        certificate_chain,
        leaf_cert_der,
    })
}

// ============================================================================
// Certificate Chain Verification (AC2)
// ============================================================================

/// Verifies the certificate chain against Google Hardware Attestation Roots.
///
/// Steps:
/// 1. Parse all certificates
/// 2. Verify validity periods
/// 3. Verify issuer/subject hierarchy
/// 4. Verify cryptographic signatures
/// 5. Compare root against embedded Google roots
pub fn verify_certificate_chain(
    certs: &[Vec<u8>],
    strict: bool,
    request_id: uuid::Uuid,
) -> Result<(), AndroidAttestationError> {
    if certs.len() < 2 {
        return Err(AndroidAttestationError::IncompleteCertChain);
    }

    let now = Utc::now();

    // Parse all certificates from the attestation chain
    let mut parsed_certs = Vec::new();
    for (i, cert_der) in certs.iter().enumerate() {
        let (_, cert) = X509Certificate::from_der(cert_der).map_err(|e| {
            AndroidAttestationError::InvalidCertificate(format!("Certificate {i}: {e:?}"))
        })?;
        parsed_certs.push(cert);
    }

    // Parse embedded Google Root CAs
    let (_, google_root_1) = X509Certificate::from_der(GOOGLE_HARDWARE_ATTESTATION_ROOT_1)
        .map_err(|e| {
            AndroidAttestationError::InvalidCertificate(format!("Google Root 1: {e:?}"))
        })?;
    let (_, google_root_2) = X509Certificate::from_der(GOOGLE_HARDWARE_ATTESTATION_ROOT_2)
        .map_err(|e| {
            AndroidAttestationError::InvalidCertificate(format!("Google Root 2: {e:?}"))
        })?;

    // Verify validity periods for all certificates
    for (i, cert) in parsed_certs.iter().enumerate() {
        let validity = cert.validity();
        let now_ts = now.timestamp();
        let not_before_ts = validity.not_before.timestamp();
        let not_after_ts = validity.not_after.timestamp();

        if now_ts < not_before_ts || now_ts > not_after_ts {
            tracing::warn!(
                request_id = %request_id,
                cert_index = i,
                not_before = %validity.not_before,
                not_after = %validity.not_after,
                now = %now,
                "Certificate validity check failed"
            );
            return Err(AndroidAttestationError::CertificateExpired);
        }
    }

    // Verify chain hierarchy
    let leaf = &parsed_certs[0];
    let chain_root = parsed_certs.last().unwrap();

    // For chains with intermediates, verify the hierarchy
    for i in 0..parsed_certs.len() - 1 {
        let cert = &parsed_certs[i];
        let issuer_cert = &parsed_certs[i + 1];

        if cert.issuer() != issuer_cert.subject() {
            tracing::warn!(
                request_id = %request_id,
                cert_index = i,
                cert_issuer = ?cert.issuer(),
                issuer_subject = ?issuer_cert.subject(),
                "Certificate chain hierarchy mismatch"
            );
            return Err(AndroidAttestationError::ChainVerificationFailed(format!(
                "Certificate {i} not issued by certificate {}",
                i + 1
            )));
        }

        // Verify cryptographic signature
        let sig_verification = cert.verify_signature(Some(issuer_cert.public_key()));
        if let Err(e) = sig_verification {
            tracing::warn!(
                request_id = %request_id,
                cert_index = i,
                error = ?e,
                strict = strict,
                "Certificate signature verification failed"
            );
            if strict {
                return Err(AndroidAttestationError::ChainVerificationFailed(format!(
                    "Certificate {i} signature invalid: {e:?}"
                )));
            }
        }
    }

    // Verify root certificate matches Google root
    let root_matches = matches_google_root(chain_root, &google_root_1, &google_root_2);

    if !root_matches {
        let msg = "Root certificate does not match Google Hardware Attestation Root";
        tracing::warn!(
            request_id = %request_id,
            chain_root_subject = ?chain_root.subject(),
            strict = strict,
            "{}", msg
        );
        if strict {
            return Err(AndroidAttestationError::RootCaMismatch);
        }
    }

    // Verify the root's signature (self-signed)
    if root_matches {
        // Verify against the matching Google root
        let google_root = if is_same_cert(chain_root, &google_root_1) {
            &google_root_1
        } else {
            &google_root_2
        };

        let root_sig_verification = chain_root.verify_signature(Some(google_root.public_key()));
        if let Err(e) = root_sig_verification {
            tracing::warn!(
                request_id = %request_id,
                error = ?e,
                strict = strict,
                "Root certificate signature verification failed"
            );
            if strict {
                return Err(AndroidAttestationError::ChainVerificationFailed(format!(
                    "Root certificate signature invalid: {e:?}"
                )));
            }
        }
    }

    tracing::info!(
        request_id = %request_id,
        strict = strict,
        chain_length = certs.len(),
        leaf_subject = ?leaf.subject(),
        root_subject = ?chain_root.subject(),
        root_matches_google = root_matches,
        "Certificate chain verification completed"
    );

    Ok(())
}

/// Checks if the chain root matches either Google Hardware Attestation Root
fn matches_google_root(
    chain_root: &X509Certificate,
    google_root_1: &X509Certificate,
    google_root_2: &X509Certificate,
) -> bool {
    is_same_cert(chain_root, google_root_1) || is_same_cert(chain_root, google_root_2)
}

/// Checks if two certificates are the same by comparing public key, subject, issuer, and serial number.
/// This comprehensive comparison prevents spoofing attacks where an attacker might create
/// a certificate with the same subject but different key material.
fn is_same_cert(cert1: &X509Certificate, cert2: &X509Certificate) -> bool {
    cert1.public_key().raw == cert2.public_key().raw
        && cert1.subject() == cert2.subject()
        && cert1.issuer() == cert2.issuer()
        && cert1.raw_serial() == cert2.raw_serial()
}

// ============================================================================
// Key Attestation Extension Parsing (AC3)
// ============================================================================

/// Parses the Key Attestation extension from the leaf certificate.
///
/// Extension OID: 1.3.6.1.4.1.11129.2.1.17
///
/// ASN.1 Structure:
/// ```asn1
/// KeyDescription ::= SEQUENCE {
///     attestationVersion         INTEGER,
///     attestationSecurityLevel   SecurityLevel,
///     keymasterVersion          INTEGER,
///     keymasterSecurityLevel    SecurityLevel,
///     attestationChallenge      OCTET STRING,
///     uniqueId                  OCTET STRING,
///     softwareEnforced          AuthorizationList,
///     teeEnforced               AuthorizationList,
/// }
/// ```
pub fn parse_key_attestation_extension(
    leaf_cert_der: &[u8],
) -> Result<KeyDescription, AndroidAttestationError> {
    let (_, cert) = X509Certificate::from_der(leaf_cert_der)
        .map_err(|e| AndroidAttestationError::InvalidCertificate(format!("{e:?}")))?;

    // Build the OID for the Key Attestation extension
    let attestation_oid =
        Oid::from(KEY_ATTESTATION_EXTENSION_OID).expect("Invalid Key Attestation OID constant");

    // Find the Key Attestation extension
    let attestation_ext = cert
        .extensions()
        .iter()
        .find(|ext| ext.oid == attestation_oid)
        .ok_or(AndroidAttestationError::MissingAttestationExtension)?;

    // Parse the extension value as ASN.1 SEQUENCE
    let (_, key_desc_seq) = der_parser::parse_der(attestation_ext.value)
        .map_err(|e| AndroidAttestationError::InvalidAttestationExtension(format!("{e:?}")))?;

    parse_key_description(&key_desc_seq)
}

/// Parses the KeyDescription SEQUENCE
fn parse_key_description(der: &BerObject) -> Result<KeyDescription, AndroidAttestationError> {
    let items = match &der.content {
        BerObjectContent::Sequence(items) => items,
        _ => {
            return Err(AndroidAttestationError::InvalidAttestationExtension(
                "Expected SEQUENCE for KeyDescription".to_string(),
            ))
        }
    };

    if items.len() < 8 {
        return Err(AndroidAttestationError::InvalidAttestationExtension(
            format!("KeyDescription requires 8 fields, got {}", items.len()),
        ));
    }

    // Parse attestationVersion (INTEGER)
    let attestation_version = parse_integer(&items[0])? as i32;

    // Parse attestationSecurityLevel (ENUMERATED/INTEGER)
    let attestation_security_level = SecurityLevel::try_from(parse_integer(&items[1])?)?;

    // Parse keymasterVersion (INTEGER)
    let keymaster_version = parse_integer(&items[2])? as i32;

    // Parse keymasterSecurityLevel (ENUMERATED/INTEGER)
    let keymaster_security_level = SecurityLevel::try_from(parse_integer(&items[3])?)?;

    // Parse attestationChallenge (OCTET STRING)
    let attestation_challenge = parse_octet_string(&items[4])?;

    // Parse uniqueId (OCTET STRING)
    let unique_id = parse_octet_string(&items[5])?;

    // Parse softwareEnforced (AuthorizationList)
    let software_enforced = parse_authorization_list(&items[6])?;

    // Parse teeEnforced (AuthorizationList)
    let tee_enforced = parse_authorization_list(&items[7])?;

    Ok(KeyDescription {
        attestation_version,
        attestation_security_level,
        keymaster_version,
        keymaster_security_level,
        attestation_challenge,
        unique_id,
        software_enforced,
        tee_enforced,
    })
}

/// Parses an INTEGER from ASN.1 using proper two's complement handling.
/// ASN.1 INTEGER encoding uses two's complement with sign extension:
/// - If the high bit is set on a positive number, a 0x00 byte is prepended
/// - Negative numbers have the high bit set in the first byte
fn parse_integer(obj: &BerObject) -> Result<i64, AndroidAttestationError> {
    match &obj.content {
        BerObjectContent::Integer(bytes) => {
            if bytes.is_empty() {
                return Ok(0);
            }
            // ASN.1 INTEGER uses two's complement encoding
            // Check if negative (high bit set in first byte)
            let is_negative = (bytes[0] & 0x80) != 0;
            let mut value: i64 = if is_negative { -1 } else { 0 };
            for &byte in *bytes {
                value = (value << 8) | (byte as i64);
            }
            Ok(value)
        }
        BerObjectContent::Enum(val) => Ok(*val as i64),
        _ => Err(AndroidAttestationError::InvalidAttestationExtension(
            format!("Expected INTEGER, got {:?}", obj.content),
        )),
    }
}

/// Parses an OCTET STRING from ASN.1
fn parse_octet_string(obj: &BerObject) -> Result<Vec<u8>, AndroidAttestationError> {
    match &obj.content {
        BerObjectContent::OctetString(bytes) => Ok(bytes.to_vec()),
        _ => Err(AndroidAttestationError::InvalidAttestationExtension(
            format!("Expected OCTET STRING, got {:?}", obj.content),
        )),
    }
}

// ============================================================================
// AuthorizationList Parsing (AC7)
// ============================================================================

/// Parses an AuthorizationList from ASN.1 SEQUENCE
fn parse_authorization_list(obj: &BerObject) -> Result<AuthorizationList, AndroidAttestationError> {
    let items = match &obj.content {
        BerObjectContent::Sequence(items) => items,
        _ => {
            return Err(AndroidAttestationError::InvalidAttestationExtension(
                "Expected SEQUENCE for AuthorizationList".to_string(),
            ))
        }
    };

    let mut auth_list = AuthorizationList::default();

    for item in items {
        // Each item is a tagged value [TAG] EXPLICIT value
        let tag = item.tag().0;

        match tag {
            1 => {
                // purpose: SET OF INTEGER
                auth_list.purpose = parse_tagged_int_set(item).ok();
            }
            2 => {
                // algorithm: INTEGER
                auth_list.algorithm = parse_tagged_integer(item).ok().map(|v| v as i32);
            }
            3 => {
                // keySize: INTEGER
                auth_list.key_size = parse_tagged_integer(item).ok().map(|v| v as i32);
            }
            702 => {
                // origin: INTEGER
                auth_list.origin = parse_tagged_integer(item).ok().map(|v| v as i32);
            }
            704 => {
                // rootOfTrust: RootOfTrust
                auth_list.root_of_trust = parse_root_of_trust(item).ok();
            }
            705 => {
                // osVersion: INTEGER
                auth_list.os_version = parse_tagged_integer(item).ok().map(|v| v as i32);
            }
            706 => {
                // osPatchLevel: INTEGER
                auth_list.os_patch_level = parse_tagged_integer(item).ok().map(|v| v as i32);
            }
            710 => {
                // attestationIdBrand: OCTET STRING
                auth_list.attestation_id_brand = parse_tagged_octet_string(item).ok();
            }
            711 => {
                // attestationIdDevice: OCTET STRING
                auth_list.attestation_id_device = parse_tagged_octet_string(item).ok();
            }
            712 => {
                // attestationIdProduct: OCTET STRING
                auth_list.attestation_id_product = parse_tagged_octet_string(item).ok();
            }
            713 => {
                // attestationIdSerial: OCTET STRING
                auth_list.attestation_id_serial = parse_tagged_octet_string(item).ok();
            }
            716 => {
                // attestationIdManufacturer: OCTET STRING
                auth_list.attestation_id_manufacturer = parse_tagged_octet_string(item).ok();
            }
            717 => {
                // attestationIdModel: OCTET STRING
                auth_list.attestation_id_model = parse_tagged_octet_string(item).ok();
            }
            718 => {
                // vendorPatchLevel: INTEGER
                auth_list.vendor_patch_level = parse_tagged_integer(item).ok().map(|v| v as i32);
            }
            719 => {
                // bootPatchLevel: INTEGER
                auth_list.boot_patch_level = parse_tagged_integer(item).ok().map(|v| v as i32);
            }
            _ => {
                // Unknown tag, skip
            }
        }
    }

    Ok(auth_list)
}

/// Parses a tagged INTEGER value [TAG] EXPLICIT INTEGER
fn parse_tagged_integer(obj: &BerObject) -> Result<i64, AndroidAttestationError> {
    // The content is wrapped in Unknown (context-specific tag)
    let inner = match &obj.content {
        BerObjectContent::Unknown(any) => {
            let (_, inner) = der_parser::parse_der(any.data).map_err(|e| {
                AndroidAttestationError::InvalidAttestationExtension(format!("{e:?}"))
            })?;
            inner
        }
        _ => obj.clone(),
    };

    parse_integer(&inner)
}

/// Parses a tagged SET OF INTEGER
fn parse_tagged_int_set(obj: &BerObject) -> Result<Vec<i32>, AndroidAttestationError> {
    let inner = match &obj.content {
        BerObjectContent::Unknown(any) => {
            let (_, inner) = der_parser::parse_der(any.data).map_err(|e| {
                AndroidAttestationError::InvalidAttestationExtension(format!("{e:?}"))
            })?;
            inner
        }
        _ => obj.clone(),
    };

    match &inner.content {
        BerObjectContent::Set(items) => {
            let mut values = Vec::new();
            for item in items {
                values.push(parse_integer(item)? as i32);
            }
            Ok(values)
        }
        _ => Err(AndroidAttestationError::InvalidAttestationExtension(
            "Expected SET for tagged int set".to_string(),
        )),
    }
}

/// Parses a tagged OCTET STRING value
fn parse_tagged_octet_string(obj: &BerObject) -> Result<Vec<u8>, AndroidAttestationError> {
    let inner = match &obj.content {
        BerObjectContent::Unknown(any) => {
            let (_, inner) = der_parser::parse_der(any.data).map_err(|e| {
                AndroidAttestationError::InvalidAttestationExtension(format!("{e:?}"))
            })?;
            inner
        }
        _ => obj.clone(),
    };

    parse_octet_string(&inner)
}

/// Parses RootOfTrust structure
fn parse_root_of_trust(obj: &BerObject) -> Result<RootOfTrust, AndroidAttestationError> {
    let inner = match &obj.content {
        BerObjectContent::Unknown(any) => {
            let (_, inner) = der_parser::parse_der(any.data).map_err(|e| {
                AndroidAttestationError::InvalidAttestationExtension(format!("{e:?}"))
            })?;
            inner
        }
        _ => obj.clone(),
    };

    let items = match &inner.content {
        BerObjectContent::Sequence(items) => items,
        _ => {
            return Err(AndroidAttestationError::InvalidAttestationExtension(
                "Expected SEQUENCE for RootOfTrust".to_string(),
            ))
        }
    };

    if items.len() < 3 {
        return Err(AndroidAttestationError::InvalidAttestationExtension(
            "RootOfTrust requires at least 3 fields".to_string(),
        ));
    }

    let verified_boot_key = parse_octet_string(&items[0])?;
    let device_locked = parse_boolean(&items[1])?;
    let verified_boot_state = VerifiedBootState::try_from(parse_integer(&items[2])?)?;
    let verified_boot_hash = if items.len() > 3 {
        parse_octet_string(&items[3]).ok()
    } else {
        None
    };

    Ok(RootOfTrust {
        verified_boot_key,
        device_locked,
        verified_boot_state,
        verified_boot_hash,
    })
}

/// Parses a BOOLEAN from ASN.1
fn parse_boolean(obj: &BerObject) -> Result<bool, AndroidAttestationError> {
    match &obj.content {
        BerObjectContent::Boolean(val) => Ok(*val),
        _ => Err(AndroidAttestationError::InvalidAttestationExtension(
            format!("Expected BOOLEAN, got {:?}", obj.content),
        )),
    }
}

// ============================================================================
// Security Level Validation (AC4, AC5)
// ============================================================================

/// Validates that the attestation security level is TEE or StrongBox.
///
/// Per FR72, Software-only attestation (level 0) is REJECTED.
pub fn validate_security_level(
    key_description: &KeyDescription,
    request_id: uuid::Uuid,
) -> Result<(), AndroidAttestationError> {
    let level = key_description.attestation_security_level;

    match level {
        SecurityLevel::Software => {
            tracing::warn!(
                request_id = %request_id,
                attestation_security_level = %level,
                keymaster_security_level = %key_description.keymaster_security_level,
                "Software-only attestation REJECTED"
            );
            Err(AndroidAttestationError::SoftwareOnlyAttestation)
        }
        SecurityLevel::TrustedEnvironment => {
            tracing::info!(
                request_id = %request_id,
                security_level = "TEE",
                trust = "MEDIUM",
                "TEE attestation accepted"
            );
            Ok(())
        }
        SecurityLevel::StrongBox => {
            tracing::info!(
                request_id = %request_id,
                security_level = "StrongBox",
                trust = "HIGH",
                "StrongBox attestation accepted"
            );
            Ok(())
        }
    }
}

// ============================================================================
// Challenge Validation (AC6)
// ============================================================================

/// Validates challenge freshness against the ChallengeStore.
///
/// Steps:
/// 1. Extract attestationChallenge from KeyDescription
/// 2. Lookup challenge in ChallengeStore
/// 3. Validate freshness (5-minute window)
/// 4. Mark as consumed (single-use)
pub async fn validate_challenge(
    key_description: &KeyDescription,
    challenge_store: Arc<ChallengeStore>,
    request_id: uuid::Uuid,
) -> Result<(), AndroidAttestationError> {
    let challenge_bytes = &key_description.attestation_challenge;

    // Challenge must be exactly 32 bytes
    if challenge_bytes.len() != 32 {
        tracing::warn!(
            request_id = %request_id,
            challenge_len = challenge_bytes.len(),
            "Invalid challenge length"
        );
        return Err(AndroidAttestationError::ChallengeMismatch);
    }

    let challenge: [u8; 32] = challenge_bytes
        .as_slice()
        .try_into()
        .map_err(|_| AndroidAttestationError::ChallengeMismatch)?;

    // Verify and consume the challenge
    match challenge_store.verify_and_consume(&challenge).await {
        Ok(()) => {
            tracing::info!(
                request_id = %request_id,
                "Challenge verified and consumed"
            );
            Ok(())
        }
        Err(crate::services::challenge_store::ChallengeError::NotFound) => {
            tracing::warn!(
                request_id = %request_id,
                "Challenge not found in store"
            );
            Err(AndroidAttestationError::ChallengeNotFound)
        }
        Err(crate::services::challenge_store::ChallengeError::AlreadyUsed) => {
            tracing::warn!(
                request_id = %request_id,
                "Challenge already used"
            );
            Err(AndroidAttestationError::ChallengeMismatch)
        }
        Err(crate::services::challenge_store::ChallengeError::Expired) => {
            tracing::warn!(
                request_id = %request_id,
                "Challenge expired"
            );
            Err(AndroidAttestationError::ChallengeExpired)
        }
        Err(crate::services::challenge_store::ChallengeError::RateLimitExceeded) => {
            // This shouldn't happen during verification, but handle it
            tracing::warn!(
                request_id = %request_id,
                "Rate limit exceeded during challenge verification"
            );
            Err(AndroidAttestationError::ChallengeMismatch)
        }
    }
}

// ============================================================================
// Public Key Extraction (AC8)
// ============================================================================

/// Extracts the public key from the leaf certificate.
///
/// Supports EC (P-256, P-384) and RSA key types.
pub fn extract_public_key(leaf_cert_der: &[u8]) -> Result<Vec<u8>, AndroidAttestationError> {
    let (_, cert) = X509Certificate::from_der(leaf_cert_der)
        .map_err(|e| AndroidAttestationError::InvalidCertificate(format!("{e:?}")))?;

    let public_key = cert.public_key();
    let key_data = public_key.raw;

    // For SubjectPublicKeyInfo, we return the raw bytes which include
    // the algorithm identifier and the actual key bytes
    // For EC keys, the key bytes are the uncompressed point (0x04 || x || y)
    // For RSA keys, the key bytes are the RSA public key structure

    // Extract just the BIT STRING content (the actual key bytes)
    let spki = public_key.parsed().map_err(|e| {
        AndroidAttestationError::InvalidPublicKey(format!("Failed to parse public key: {e:?}"))
    })?;

    match spki {
        x509_parser::public_key::PublicKey::EC(ec_point) => {
            // EC point is already in uncompressed format (0x04 || x || y)
            Ok(ec_point.data().to_vec())
        }
        x509_parser::public_key::PublicKey::RSA(_rsa) => {
            // For RSA, return the full SubjectPublicKeyInfo for compatibility
            Ok(key_data.to_vec())
        }
        _ => Err(AndroidAttestationError::UnsupportedKeyType(format!(
            "Unsupported key type: {:?}",
            public_key.algorithm
        ))),
    }
}

// ============================================================================
// Device Info Extraction
// ============================================================================

/// Extracts device information from authorization lists
fn extract_device_info(key_description: &KeyDescription) -> AndroidDeviceInfo {
    // Prefer TEE-enforced values, fall back to software-enforced
    let tee = &key_description.tee_enforced;
    let sw = &key_description.software_enforced;

    AndroidDeviceInfo {
        brand: tee
            .attestation_id_brand
            .as_ref()
            .or(sw.attestation_id_brand.as_ref())
            .and_then(|b| String::from_utf8(b.clone()).ok()),
        device: tee
            .attestation_id_device
            .as_ref()
            .or(sw.attestation_id_device.as_ref())
            .and_then(|b| String::from_utf8(b.clone()).ok()),
        product: tee
            .attestation_id_product
            .as_ref()
            .or(sw.attestation_id_product.as_ref())
            .and_then(|b| String::from_utf8(b.clone()).ok()),
        manufacturer: tee
            .attestation_id_manufacturer
            .as_ref()
            .or(sw.attestation_id_manufacturer.as_ref())
            .and_then(|b| String::from_utf8(b.clone()).ok()),
        model: tee
            .attestation_id_model
            .as_ref()
            .or(sw.attestation_id_model.as_ref())
            .and_then(|b| String::from_utf8(b.clone()).ok()),
        os_version: tee.os_version.or(sw.os_version),
        os_patch_level: tee.os_patch_level.or(sw.os_patch_level),
    }
}

// ============================================================================
// Main Verification Pipeline (AC9, AC10)
// ============================================================================

/// Orchestrates the complete Android attestation verification process.
///
/// Steps:
/// 1. Parse certificate chain
/// 2. Verify certificate chain to Google root
/// 3. Parse Key Attestation extension
/// 4. Validate security level (reject Software)
/// 5. Validate challenge freshness
/// 6. Extract public key
/// 7. Build result
pub async fn verify_android_attestation(
    certificate_chain_b64: &[String],
    challenge_store: Arc<ChallengeStore>,
    config: &Config,
    request_id: uuid::Uuid,
) -> Result<AndroidAttestationResult, AndroidAttestationError> {
    // Step 1: Parse certificate chain
    tracing::info!(
        request_id = %request_id,
        step = "parse_certs",
        cert_count = certificate_chain_b64.len(),
        "Starting Android attestation verification"
    );
    let attestation = parse_certificate_chain(certificate_chain_b64)?;
    tracing::info!(
        request_id = %request_id,
        step = "parse_certs",
        status = "pass",
        "Certificate chain parsed"
    );

    // Step 2: Verify certificate chain
    tracing::info!(
        request_id = %request_id,
        step = "cert_chain",
        strict = config.strict_attestation,
        "Verifying certificate chain"
    );
    verify_certificate_chain(
        &attestation.certificate_chain,
        config.strict_attestation,
        request_id,
    )?;
    tracing::info!(
        request_id = %request_id,
        step = "cert_chain",
        status = "pass",
        "Certificate chain verified"
    );

    // Step 3: Parse Key Attestation extension
    tracing::info!(
        request_id = %request_id,
        step = "attestation_ext",
        "Parsing Key Attestation extension"
    );
    let key_description = parse_key_attestation_extension(&attestation.leaf_cert_der)?;
    tracing::info!(
        request_id = %request_id,
        step = "attestation_ext",
        status = "pass",
        attestation_version = key_description.attestation_version,
        attestation_security_level = %key_description.attestation_security_level,
        keymaster_version = key_description.keymaster_version,
        keymaster_security_level = %key_description.keymaster_security_level,
        challenge_len = key_description.attestation_challenge.len(),
        "Key Attestation extension parsed"
    );

    // Step 4: Validate security level
    tracing::info!(
        request_id = %request_id,
        step = "security_level",
        "Validating security level"
    );
    validate_security_level(&key_description, request_id)?;
    tracing::info!(
        request_id = %request_id,
        step = "security_level",
        status = "pass",
        "Security level validated"
    );

    // Step 5: Validate challenge
    tracing::info!(
        request_id = %request_id,
        step = "challenge",
        "Validating challenge"
    );
    validate_challenge(&key_description, challenge_store, request_id).await?;
    tracing::info!(
        request_id = %request_id,
        step = "challenge",
        status = "pass",
        "Challenge validated"
    );

    // Step 6: Extract public key
    tracing::info!(
        request_id = %request_id,
        step = "public_key",
        "Extracting public key"
    );
    let public_key = extract_public_key(&attestation.leaf_cert_der)?;
    tracing::info!(
        request_id = %request_id,
        step = "public_key",
        status = "pass",
        key_len = public_key.len(),
        "Public key extracted"
    );

    // Step 7: Extract device info
    let device_info = extract_device_info(&key_description);

    // Get root of trust from TEE-enforced or software-enforced
    let root_of_trust = key_description
        .tee_enforced
        .root_of_trust
        .clone()
        .or(key_description.software_enforced.root_of_trust.clone());

    tracing::info!(
        request_id = %request_id,
        status = "success",
        security_level = %key_description.attestation_security_level,
        device_brand = ?device_info.brand,
        device_model = ?device_info.model,
        "Android attestation verification complete"
    );

    Ok(AndroidAttestationResult {
        public_key,
        attestation_security_level: key_description.attestation_security_level,
        keymaster_security_level: key_description.keymaster_security_level,
        attestation_version: key_description.attestation_version,
        keymaster_version: key_description.keymaster_version,
        certificate_chain: attestation.certificate_chain,
        device_info,
        root_of_trust,
    })
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_security_level_from_int() {
        assert_eq!(SecurityLevel::try_from(0).unwrap(), SecurityLevel::Software);
        assert_eq!(
            SecurityLevel::try_from(1).unwrap(),
            SecurityLevel::TrustedEnvironment
        );
        assert_eq!(
            SecurityLevel::try_from(2).unwrap(),
            SecurityLevel::StrongBox
        );
        assert!(SecurityLevel::try_from(3).is_err());
    }

    #[test]
    fn test_verified_boot_state_from_int() {
        assert_eq!(
            VerifiedBootState::try_from(0).unwrap(),
            VerifiedBootState::Verified
        );
        assert_eq!(
            VerifiedBootState::try_from(1).unwrap(),
            VerifiedBootState::SelfSigned
        );
        assert_eq!(
            VerifiedBootState::try_from(2).unwrap(),
            VerifiedBootState::Unverified
        );
        assert_eq!(
            VerifiedBootState::try_from(3).unwrap(),
            VerifiedBootState::Failed
        );
        assert!(VerifiedBootState::try_from(4).is_err());
    }

    #[test]
    fn test_parse_certificate_chain_too_short() {
        let result = parse_certificate_chain(&["cert1".to_string()]);
        assert!(matches!(
            result,
            Err(AndroidAttestationError::IncompleteCertChain)
        ));
    }

    #[test]
    fn test_parse_certificate_chain_invalid_base64() {
        let result = parse_certificate_chain(&[
            "not-valid-base64!!!".to_string(),
            "also-invalid!!!".to_string(),
        ]);
        assert!(matches!(
            result,
            Err(AndroidAttestationError::InvalidBase64)
        ));
    }

    #[test]
    fn test_security_level_display() {
        assert_eq!(format!("{}", SecurityLevel::Software), "Software");
        assert_eq!(
            format!("{}", SecurityLevel::TrustedEnvironment),
            "TrustedEnvironment"
        );
        assert_eq!(format!("{}", SecurityLevel::StrongBox), "StrongBox");
    }

    #[test]
    fn test_android_attestation_error_display() {
        assert_eq!(
            format!("{}", AndroidAttestationError::InvalidBase64),
            "Invalid base64 encoding"
        );
        assert_eq!(
            format!("{}", AndroidAttestationError::SoftwareOnlyAttestation),
            "Software-only attestation rejected. Device requires TEE or StrongBox."
        );
        assert_eq!(
            format!("{}", AndroidAttestationError::RootCaMismatch),
            "Root CA does not match Google Hardware Attestation Root"
        );
    }

    #[test]
    fn test_google_root_certificates_parse() {
        // Verify we can parse the embedded Google root certificates
        let result1 = X509Certificate::from_der(GOOGLE_HARDWARE_ATTESTATION_ROOT_1);
        assert!(result1.is_ok(), "Failed to parse Google Root 1");
        let (_, cert1) = result1.unwrap();
        assert!(cert1.is_ca(), "Google Root 1 should be a CA");

        let result2 = X509Certificate::from_der(GOOGLE_HARDWARE_ATTESTATION_ROOT_2);
        assert!(result2.is_ok(), "Failed to parse Google Root 2");
        let (_, cert2) = result2.unwrap();
        assert!(cert2.is_ca(), "Google Root 2 should be a CA");
    }

    #[test]
    fn test_security_level_validation_software_rejected() {
        let request_id = uuid::Uuid::new_v4();
        let key_desc = KeyDescription {
            attestation_version: 4,
            attestation_security_level: SecurityLevel::Software,
            keymaster_version: 4,
            keymaster_security_level: SecurityLevel::Software,
            attestation_challenge: vec![0u8; 32],
            unique_id: vec![],
            software_enforced: AuthorizationList::default(),
            tee_enforced: AuthorizationList::default(),
        };

        let result = validate_security_level(&key_desc, request_id);
        assert!(matches!(
            result,
            Err(AndroidAttestationError::SoftwareOnlyAttestation)
        ));
    }

    #[test]
    fn test_security_level_validation_tee_accepted() {
        let request_id = uuid::Uuid::new_v4();
        let key_desc = KeyDescription {
            attestation_version: 4,
            attestation_security_level: SecurityLevel::TrustedEnvironment,
            keymaster_version: 4,
            keymaster_security_level: SecurityLevel::TrustedEnvironment,
            attestation_challenge: vec![0u8; 32],
            unique_id: vec![],
            software_enforced: AuthorizationList::default(),
            tee_enforced: AuthorizationList::default(),
        };

        let result = validate_security_level(&key_desc, request_id);
        assert!(result.is_ok());
    }

    #[test]
    fn test_security_level_validation_strongbox_accepted() {
        let request_id = uuid::Uuid::new_v4();
        let key_desc = KeyDescription {
            attestation_version: 4,
            attestation_security_level: SecurityLevel::StrongBox,
            keymaster_version: 4,
            keymaster_security_level: SecurityLevel::StrongBox,
            attestation_challenge: vec![0u8; 32],
            unique_id: vec![],
            software_enforced: AuthorizationList::default(),
            tee_enforced: AuthorizationList::default(),
        };

        let result = validate_security_level(&key_desc, request_id);
        assert!(result.is_ok());
    }

    #[test]
    fn test_device_info_extraction() {
        let key_desc = KeyDescription {
            attestation_version: 4,
            attestation_security_level: SecurityLevel::TrustedEnvironment,
            keymaster_version: 4,
            keymaster_security_level: SecurityLevel::TrustedEnvironment,
            attestation_challenge: vec![0u8; 32],
            unique_id: vec![],
            software_enforced: AuthorizationList::default(),
            tee_enforced: AuthorizationList {
                attestation_id_brand: Some(b"Google".to_vec()),
                attestation_id_model: Some(b"Pixel 8 Pro".to_vec()),
                attestation_id_manufacturer: Some(b"Google".to_vec()),
                os_version: Some(140000),
                os_patch_level: Some(202312),
                ..Default::default()
            },
        };

        let device_info = extract_device_info(&key_desc);
        assert_eq!(device_info.brand, Some("Google".to_string()));
        assert_eq!(device_info.model, Some("Pixel 8 Pro".to_string()));
        assert_eq!(device_info.manufacturer, Some("Google".to_string()));
        assert_eq!(device_info.os_version, Some(140000));
        assert_eq!(device_info.os_patch_level, Some(202312));
    }

    #[test]
    fn test_authorization_list_default() {
        let auth_list = AuthorizationList::default();
        assert!(auth_list.purpose.is_none());
        assert!(auth_list.algorithm.is_none());
        assert!(auth_list.key_size.is_none());
        assert!(auth_list.origin.is_none());
        assert!(auth_list.root_of_trust.is_none());
    }

    // Integration test with mock certificate chain would go here
    // Real certificate testing requires generating test attestation chains
    // which is done separately in integration tests
}
