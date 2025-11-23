//! C2PA Manifest Service (Stories 5-1, 5-2, 5-3)
//!
//! Provides C2PA manifest generation and storage for RealityCam captures.
//! Implements FR27-FR30 from the PRD.
//!
//! ## Features
//! - Generate C2PA-compatible manifest data with RealityCam evidence assertions
//! - Store manifest alongside captured photos
//!
//! ## MVP Note
//! Full C2PA signing and embedding requires proper X.509 certificate chain setup.
//! For MVP, we generate and store the manifest data as JSON. The manifest
//! structure follows C2PA specification and can be upgraded to full C2PA
//! embedding when certificates are properly configured.

use serde::{Deserialize, Serialize};
use thiserror::Error;
// Note: tracing macros available for future use when C2PA signing is implemented
#[allow(unused_imports)]
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::models::{CheckStatus, ConfidenceLevel, EvidencePackage};

// ============================================================================
// Constants
// ============================================================================

/// Claim generator identifier for RealityCam manifests
const CLAIM_GENERATOR: &str = "RealityCam";

/// Software agent for capture action
const SOFTWARE_AGENT: &str = "RealityCam iOS";

// ============================================================================
// Error Types
// ============================================================================

/// Errors that can occur during C2PA operations
#[derive(Debug, Error)]
pub enum C2paError {
    #[error("Failed to create C2PA manifest: {0}")]
    ManifestCreation(String),

    #[error("Failed to sign manifest: {0}")]
    Signing(String),

    #[error("Failed to embed manifest: {0}")]
    Embedding(String),

    #[error("Failed to read C2PA manifest: {0}")]
    Reading(String),

    #[error("Signing key not configured")]
    SigningKeyNotConfigured,

    #[error("Invalid signing key: {0}")]
    InvalidSigningKey(String),

    #[error("Storage error: {0}")]
    Storage(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialization(String),
}

// ============================================================================
// Custom Assertions
// ============================================================================

/// RealityCam evidence assertion for C2PA manifest
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RealityCamAssertion {
    /// Confidence level from evidence analysis
    pub confidence_level: String,

    /// Hardware attestation summary
    pub hardware_attestation: HardwareAssertionData,

    /// Depth analysis summary
    pub depth_analysis: DepthAssertionData,

    /// Device information
    pub device_model: String,

    /// Capture timestamp (ISO 8601)
    pub captured_at: String,
}

/// Hardware attestation data for C2PA assertion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareAssertionData {
    /// Status: "pass", "fail", or "unavailable"
    pub status: String,

    /// Attestation level: "secure_enclave" or "unverified"
    pub level: String,

    /// Whether assertion was verified
    pub verified: bool,
}

/// Depth analysis data for C2PA assertion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepthAssertionData {
    /// Status: "pass", "fail", or "unavailable"
    pub status: String,

    /// Whether scene is likely real (not a flat image)
    pub is_real_scene: bool,

    /// Number of depth layers detected
    pub depth_layers: u32,

    /// Depth variance value
    pub depth_variance: f64,
}

/// C2PA-style manifest structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct C2paManifest {
    /// Claim generator (e.g., "RealityCam/0.1.0")
    pub claim_generator: String,

    /// Title of the asset
    pub title: String,

    /// Creation timestamp (ISO 8601)
    pub created_at: String,

    /// Actions performed on the asset
    pub actions: Vec<C2paAction>,

    /// RealityCam-specific assertions
    pub realitycam: RealityCamAssertion,
}

/// C2PA action record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct C2paAction {
    /// Action type (e.g., "c2pa.created")
    pub action: String,

    /// When the action occurred (ISO 8601)
    pub when: String,

    /// Software that performed the action
    pub software_agent: String,
}

// ============================================================================
// C2PA Service
// ============================================================================

/// Service for C2PA manifest operations
pub struct C2paService;

impl C2paService {
    /// Creates a new C2PA service
    pub fn new() -> Self {
        Self
    }

    /// Generates a C2PA manifest from an evidence package
    ///
    /// # Arguments
    /// * `evidence` - Evidence package from capture processing
    /// * `captured_at` - Capture timestamp (ISO 8601)
    ///
    /// # Returns
    /// C2PA manifest structure
    pub fn generate_manifest(
        &self,
        evidence: &EvidencePackage,
        captured_at: &str,
    ) -> C2paManifest {
        let assertion = self.build_assertion(evidence, captured_at);

        let version = env!("CARGO_PKG_VERSION");
        let claim_generator = format!("{}/{}", CLAIM_GENERATOR, version);
        let software_agent = format!("{}/{}", SOFTWARE_AGENT, version);

        C2paManifest {
            claim_generator,
            title: "RealityCam Verified Photo".to_string(),
            created_at: captured_at.to_string(),
            actions: vec![C2paAction {
                action: "c2pa.created".to_string(),
                when: captured_at.to_string(),
                software_agent,
            }],
            realitycam: assertion,
        }
    }

    /// Generates a C2PA manifest as JSON string
    pub fn generate_manifest_json(
        &self,
        evidence: &EvidencePackage,
        captured_at: &str,
    ) -> Result<String, C2paError> {
        let manifest = self.generate_manifest(evidence, captured_at);

        serde_json::to_string_pretty(&manifest)
            .map_err(|e| C2paError::Serialization(e.to_string()))
    }

    /// Builds the RealityCam assertion from evidence
    fn build_assertion(&self, evidence: &EvidencePackage, captured_at: &str) -> RealityCamAssertion {
        let confidence_level = match evidence.calculate_confidence() {
            ConfidenceLevel::High => "high",
            ConfidenceLevel::Medium => "medium",
            ConfidenceLevel::Low => "low",
            ConfidenceLevel::Suspicious => "suspicious",
        };

        let hw_status = match evidence.hardware_attestation.status {
            CheckStatus::Pass => "pass",
            CheckStatus::Fail => "fail",
            CheckStatus::Unavailable => "unavailable",
        };

        let hw_level = match evidence.hardware_attestation.level {
            crate::models::AttestationLevel::SecureEnclave => "secure_enclave",
            crate::models::AttestationLevel::Unverified => "unverified",
        };

        let depth_status = match evidence.depth_analysis.status {
            CheckStatus::Pass => "pass",
            CheckStatus::Fail => "fail",
            CheckStatus::Unavailable => "unavailable",
        };

        RealityCamAssertion {
            confidence_level: confidence_level.to_string(),
            hardware_attestation: HardwareAssertionData {
                status: hw_status.to_string(),
                level: hw_level.to_string(),
                verified: evidence.hardware_attestation.assertion_verified,
            },
            depth_analysis: DepthAssertionData {
                status: depth_status.to_string(),
                is_real_scene: evidence.depth_analysis.is_likely_real_scene,
                depth_layers: evidence.depth_analysis.depth_layers,
                depth_variance: evidence.depth_analysis.depth_variance,
            },
            device_model: evidence.hardware_attestation.device_model.clone(),
            captured_at: captured_at.to_string(),
        }
    }
}

impl Default for C2paService {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// C2PA Manifest Info (for extraction/verification)
// ============================================================================

/// Extracted C2PA manifest information (for file verification)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct C2paManifestInfo {
    /// Claim generator (e.g., "RealityCam/0.1.0")
    pub claim_generator: String,

    /// Creation timestamp
    pub created_at: Option<String>,

    /// RealityCam-specific assertions (if present)
    pub assertions: Option<RealityCamAssertion>,
}

impl From<C2paManifest> for C2paManifestInfo {
    fn from(manifest: C2paManifest) -> Self {
        Self {
            claim_generator: manifest.claim_generator,
            created_at: Some(manifest.created_at),
            assertions: Some(manifest.realitycam),
        }
    }
}

// ============================================================================
// Storage Integration
// ============================================================================

/// S3 key patterns for C2PA files
pub fn c2pa_photo_s3_key(capture_id: Uuid) -> String {
    format!("captures/{capture_id}/c2pa.jpg")
}

pub fn c2pa_manifest_s3_key(capture_id: Uuid) -> String {
    format!("captures/{capture_id}/manifest.json")
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{
        AttestationLevel, DepthAnalysis, HardwareAttestation, MetadataEvidence, ProcessingInfo,
    };

    fn create_test_evidence() -> EvidencePackage {
        EvidencePackage {
            hardware_attestation: HardwareAttestation::pass(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth_analysis: DepthAnalysis {
                status: CheckStatus::Pass,
                depth_variance: 2.4,
                depth_layers: 5,
                edge_coherence: 0.87,
                min_depth: 0.8,
                max_depth: 4.2,
                is_likely_real_scene: true,
            },
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::new(1000, "0.1.0"),
        }
    }

    #[test]
    fn test_build_assertion() {
        let service = C2paService::new();
        let evidence = create_test_evidence();

        let assertion = service.build_assertion(&evidence, "2025-11-23T10:30:00Z");

        assert_eq!(assertion.confidence_level, "high");
        assert_eq!(assertion.hardware_attestation.status, "pass");
        assert_eq!(assertion.hardware_attestation.level, "secure_enclave");
        assert!(assertion.hardware_attestation.verified);
        assert_eq!(assertion.depth_analysis.status, "pass");
        assert!(assertion.depth_analysis.is_real_scene);
        assert_eq!(assertion.depth_analysis.depth_layers, 5);
        assert_eq!(assertion.device_model, "iPhone 15 Pro");
    }

    #[test]
    fn test_generate_manifest() {
        let service = C2paService::new();
        let evidence = create_test_evidence();

        let manifest = service.generate_manifest(&evidence, "2025-11-23T10:30:00Z");

        assert!(manifest.claim_generator.starts_with("RealityCam/"));
        assert_eq!(manifest.title, "RealityCam Verified Photo");
        assert_eq!(manifest.actions.len(), 1);
        assert_eq!(manifest.actions[0].action, "c2pa.created");
        assert_eq!(manifest.realitycam.confidence_level, "high");
    }

    #[test]
    fn test_generate_manifest_json() {
        let service = C2paService::new();
        let evidence = create_test_evidence();

        let json = service
            .generate_manifest_json(&evidence, "2025-11-23T10:30:00Z")
            .unwrap();

        assert!(json.contains("claim_generator"));
        assert!(json.contains("RealityCam"));
        assert!(json.contains("confidence_level"));
        assert!(json.contains("high"));
        assert!(json.contains("hardware_attestation"));
        assert!(json.contains("depth_analysis"));
    }

    #[test]
    fn test_c2pa_s3_keys() {
        let capture_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();

        let photo_key = c2pa_photo_s3_key(capture_id);
        let manifest_key = c2pa_manifest_s3_key(capture_id);

        assert_eq!(
            photo_key,
            "captures/550e8400-e29b-41d4-a716-446655440000/c2pa.jpg"
        );
        assert_eq!(
            manifest_key,
            "captures/550e8400-e29b-41d4-a716-446655440000/manifest.json"
        );
    }

    #[test]
    fn test_manifest_info_from_manifest() {
        let service = C2paService::new();
        let evidence = create_test_evidence();
        let manifest = service.generate_manifest(&evidence, "2025-11-23T10:30:00Z");

        let info: C2paManifestInfo = manifest.into();

        assert!(info.claim_generator.starts_with("RealityCam/"));
        assert!(info.created_at.is_some());
        assert!(info.assertions.is_some());
        assert_eq!(info.assertions.unwrap().confidence_level, "high");
    }
}
