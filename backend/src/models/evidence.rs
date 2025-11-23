//! Evidence types for capture verification (Story 4-4)
//!
//! This module defines the evidence package structure for capture verification,
//! including hardware attestation results and confidence level calculations.

use serde::{Deserialize, Serialize};

// ============================================================================
// Check Status Enum
// ============================================================================

/// Status of an evidence check
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CheckStatus {
    /// Check passed successfully
    Pass,
    /// Check explicitly failed
    Fail,
    /// Check could not be performed (data unavailable)
    Unavailable,
}

// ============================================================================
// Attestation Level Enum
// ============================================================================

/// Level of hardware attestation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AttestationLevel {
    /// Device with verified Secure Enclave attestation
    SecureEnclave,
    /// Unverified device
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

// ============================================================================
// Confidence Level Enum
// ============================================================================

/// Confidence level for a capture based on evidence analysis
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConfidenceLevel {
    /// Both hardware attestation and depth analysis pass
    High,
    /// One of hardware attestation or depth analysis passes
    Medium,
    /// Both are unavailable (no evidence to verify)
    Low,
    /// Any check explicitly failed (possible tampering)
    Suspicious,
}

// ============================================================================
// Hardware Attestation Structure
// ============================================================================

/// Hardware attestation evidence for a capture
///
/// Records the result of verifying the per-capture assertion
/// against the device's registered public key.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareAttestation {
    /// Overall status of the hardware attestation check
    pub status: CheckStatus,
    /// Attestation level of the device
    pub level: AttestationLevel,
    /// Device model that produced the capture
    pub device_model: String,
    /// Whether the assertion signature was verified successfully
    pub assertion_verified: bool,
    /// Whether the counter was valid (strictly increasing)
    pub counter_valid: bool,
}

impl HardwareAttestation {
    /// Creates a new HardwareAttestation with "unavailable" status
    /// Used when no assertion is provided in the capture metadata
    pub fn unavailable(device_model: String, level: AttestationLevel) -> Self {
        Self {
            status: CheckStatus::Unavailable,
            level,
            device_model,
            assertion_verified: false,
            counter_valid: false,
        }
    }

    /// Creates a new HardwareAttestation with "pass" status
    pub fn pass(device_model: String, level: AttestationLevel) -> Self {
        Self {
            status: CheckStatus::Pass,
            level,
            device_model,
            assertion_verified: true,
            counter_valid: true,
        }
    }

    /// Creates a new HardwareAttestation with "fail" status
    pub fn fail(
        device_model: String,
        level: AttestationLevel,
        assertion_verified: bool,
        counter_valid: bool,
    ) -> Self {
        Self {
            status: CheckStatus::Fail,
            level,
            device_model,
            assertion_verified,
            counter_valid,
        }
    }
}

// ============================================================================
// Depth Analysis Structure (Placeholder for Story 4-5)
// ============================================================================

/// Depth analysis evidence for a capture
///
/// Records the result of analyzing the LiDAR depth map
/// to verify it represents a real 3D scene.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepthAnalysis {
    /// Overall status of the depth analysis check
    pub status: CheckStatus,
    /// Variance in depth values (higher = more 3D structure)
    pub depth_variance: f64,
    /// Number of distinct depth layers detected
    pub depth_layers: u32,
    /// Edge coherence score (0.0 - 1.0)
    pub edge_coherence: f64,
    /// Minimum depth value in meters
    pub min_depth: f64,
    /// Maximum depth value in meters
    pub max_depth: f64,
    /// Whether the depth map likely represents a real scene
    pub is_likely_real_scene: bool,
}

impl Default for DepthAnalysis {
    /// Creates a default unavailable depth analysis
    fn default() -> Self {
        Self {
            status: CheckStatus::Unavailable,
            depth_variance: 0.0,
            depth_layers: 0,
            edge_coherence: 0.0,
            min_depth: 0.0,
            max_depth: 0.0,
            is_likely_real_scene: false,
        }
    }
}

// ============================================================================
// Metadata Evidence Structure
// ============================================================================

/// Metadata validation evidence (Story 4-6)
///
/// Records the result of validating capture metadata including:
/// - Timestamp (within 15 minute window of server time)
/// - Device model (iPhone Pro whitelist)
/// - Resolution (known LiDAR formats)
/// - Location (valid GPS coordinates)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[derive(Default)]
pub struct MetadataEvidence {
    /// Whether the timestamp is within acceptable bounds (15 min window)
    pub timestamp_valid: bool,
    /// Delta between captured_at and server time in seconds
    /// Positive = captured in past, Negative = captured in future
    pub timestamp_delta_seconds: i64,
    /// Whether the device model is verified (iPhone Pro whitelist)
    pub model_verified: bool,
    /// The device model name
    pub model_name: String,
    /// Whether depth map resolution matches known LiDAR formats
    pub resolution_valid: bool,
    /// Whether valid location data is available
    pub location_available: bool,
    /// Whether user opted out of location sharing
    pub location_opted_out: bool,
    /// Coarse location (city/region level, for display)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location_coarse: Option<String>,
}


// ============================================================================
// Processing Info Structure (Story 4-7)
// ============================================================================

/// Processing information for evidence generation
///
/// Records timing and version info for the evidence processing pipeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[derive(Default)]
pub struct ProcessingInfo {
    /// When processing completed (ISO 8601)
    pub processed_at: String,
    /// Total processing time in milliseconds
    pub processing_time_ms: u64,
    /// Backend version that processed the capture
    pub backend_version: String,
}


impl ProcessingInfo {
    /// Creates a new ProcessingInfo with current timestamp
    pub fn new(processing_time_ms: u64, backend_version: &str) -> Self {
        Self {
            processed_at: chrono::Utc::now().to_rfc3339(),
            processing_time_ms,
            backend_version: backend_version.to_string(),
        }
    }
}

// ============================================================================
// Evidence Package Structure
// ============================================================================

/// Complete evidence package for a capture (Story 4-7)
///
/// Contains all verification evidence collected during
/// capture processing: hardware attestation, depth analysis,
/// metadata validation, and processing info.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidencePackage {
    /// Hardware attestation evidence
    pub hardware_attestation: HardwareAttestation,
    /// Depth analysis evidence
    pub depth_analysis: DepthAnalysis,
    /// Metadata validation evidence
    pub metadata: MetadataEvidence,
    /// Processing information (timing, version)
    pub processing: ProcessingInfo,
}

impl EvidencePackage {
    /// Calculates the confidence level based on all evidence
    ///
    /// Logic:
    /// - If any check explicitly failed -> Suspicious
    /// - If both hw and depth pass -> High
    /// - If either hw or depth pass -> Medium
    /// - If both unavailable -> Low
    pub fn calculate_confidence(&self) -> ConfidenceLevel {
        // If any check explicitly failed, mark as suspicious
        if self.hardware_attestation.status == CheckStatus::Fail
            || self.depth_analysis.status == CheckStatus::Fail
        {
            return ConfidenceLevel::Suspicious;
        }

        let hw_pass = self.hardware_attestation.status == CheckStatus::Pass;
        let depth_pass = self.depth_analysis.is_likely_real_scene
            && self.depth_analysis.status == CheckStatus::Pass;

        match (hw_pass, depth_pass) {
            (true, true) => ConfidenceLevel::High,
            (true, false) | (false, true) => ConfidenceLevel::Medium,
            (false, false) => ConfidenceLevel::Low,
        }
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_check_status_serialization() {
        assert_eq!(serde_json::to_string(&CheckStatus::Pass).unwrap(), "\"pass\"");
        assert_eq!(serde_json::to_string(&CheckStatus::Fail).unwrap(), "\"fail\"");
        assert_eq!(
            serde_json::to_string(&CheckStatus::Unavailable).unwrap(),
            "\"unavailable\""
        );
    }

    #[test]
    fn test_attestation_level_serialization() {
        assert_eq!(
            serde_json::to_string(&AttestationLevel::SecureEnclave).unwrap(),
            "\"secure_enclave\""
        );
        assert_eq!(
            serde_json::to_string(&AttestationLevel::Unverified).unwrap(),
            "\"unverified\""
        );
    }

    #[test]
    fn test_attestation_level_from_str() {
        assert_eq!(AttestationLevel::from("secure_enclave"), AttestationLevel::SecureEnclave);
        assert_eq!(AttestationLevel::from("unverified"), AttestationLevel::Unverified);
        assert_eq!(AttestationLevel::from("anything_else"), AttestationLevel::Unverified);
    }

    #[test]
    fn test_confidence_level_serialization() {
        assert_eq!(serde_json::to_string(&ConfidenceLevel::High).unwrap(), "\"high\"");
        assert_eq!(serde_json::to_string(&ConfidenceLevel::Medium).unwrap(), "\"medium\"");
        assert_eq!(serde_json::to_string(&ConfidenceLevel::Low).unwrap(), "\"low\"");
        assert_eq!(
            serde_json::to_string(&ConfidenceLevel::Suspicious).unwrap(),
            "\"suspicious\""
        );
    }

    #[test]
    fn test_hardware_attestation_unavailable() {
        let hw = HardwareAttestation::unavailable("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave);
        assert_eq!(hw.status, CheckStatus::Unavailable);
        assert!(!hw.assertion_verified);
        assert!(!hw.counter_valid);
    }

    #[test]
    fn test_hardware_attestation_pass() {
        let hw = HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave);
        assert_eq!(hw.status, CheckStatus::Pass);
        assert!(hw.assertion_verified);
        assert!(hw.counter_valid);
    }

    #[test]
    fn test_hardware_attestation_fail() {
        let hw = HardwareAttestation::fail(
            "iPhone 15 Pro".to_string(),
            AttestationLevel::SecureEnclave,
            false,
            true,
        );
        assert_eq!(hw.status, CheckStatus::Fail);
        assert!(!hw.assertion_verified);
        assert!(hw.counter_valid);
    }

    #[test]
    fn test_confidence_hw_fail_is_suspicious() {
        let evidence = EvidencePackage {
            hardware_attestation: HardwareAttestation::fail(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
                false,
                false,
            ),
            depth_analysis: DepthAnalysis::default(),
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::default(),
        };
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_both_pass_is_high() {
        let mut depth = DepthAnalysis::default();
        depth.status = CheckStatus::Pass;
        depth.is_likely_real_scene = true;

        let evidence = EvidencePackage {
            hardware_attestation: HardwareAttestation::pass(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth_analysis: depth,
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::default(),
        };
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::High);
    }

    #[test]
    fn test_confidence_hw_pass_depth_unavailable_is_medium() {
        let evidence = EvidencePackage {
            hardware_attestation: HardwareAttestation::pass(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth_analysis: DepthAnalysis::default(),
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::default(),
        };
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_both_unavailable_is_low() {
        let evidence = EvidencePackage {
            hardware_attestation: HardwareAttestation::unavailable(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth_analysis: DepthAnalysis::default(),
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::default(),
        };
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Low);
    }

    #[test]
    fn test_confidence_depth_fail_is_suspicious() {
        let mut depth = DepthAnalysis::default();
        depth.status = CheckStatus::Fail;
        depth.is_likely_real_scene = false;

        let evidence = EvidencePackage {
            hardware_attestation: HardwareAttestation::pass(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth_analysis: depth,
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::default(),
        };
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_depth_pass_hw_unavailable_is_medium() {
        let mut depth = DepthAnalysis::default();
        depth.status = CheckStatus::Pass;
        depth.is_likely_real_scene = true;

        let evidence = EvidencePackage {
            hardware_attestation: HardwareAttestation::unavailable(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth_analysis: depth,
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::default(),
        };
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Medium);
    }

    #[test]
    fn test_processing_info_new() {
        let info = ProcessingInfo::new(1500, "0.1.0");
        assert_eq!(info.processing_time_ms, 1500);
        assert_eq!(info.backend_version, "0.1.0");
        assert!(!info.processed_at.is_empty());
    }

    #[test]
    fn test_evidence_package_serialization() {
        let evidence = EvidencePackage {
            hardware_attestation: HardwareAttestation::pass(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth_analysis: DepthAnalysis::default(),
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::new(1000, "0.1.0"),
        };

        let json = serde_json::to_string(&evidence).unwrap();
        assert!(json.contains("\"hardware_attestation\""));
        assert!(json.contains("\"depth_analysis\""));
        assert!(json.contains("\"metadata\""));
        assert!(json.contains("\"processing\""));
        assert!(json.contains("\"processing_time_ms\":1000"));
    }
}
