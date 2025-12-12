//! Evidence types for capture verification (Story 4-4, Story 10-5)
//!
//! This module defines the evidence package structure for capture verification,
//! including hardware attestation results and confidence level calculations.
//!
//! Story 10-5: Extended for unified evidence schema supporting both iOS and Android platforms.

use serde::{Deserialize, Serialize};

use crate::types::hash_only::AnalysisSource;

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
pub enum AttestationLevel {
    /// Device with verified Secure Enclave attestation (iOS)
    #[serde(rename = "secure_enclave")]
    SecureEnclave,
    /// Device with verified StrongBox attestation (Android HSM) - Story 10-2
    #[serde(rename = "strongbox")]
    StrongBox,
    /// Device with verified TEE attestation (Android Trusted Execution Environment) - Story 10-2
    #[serde(rename = "tee")]
    TrustedEnvironment,
    /// Unverified device
    #[serde(rename = "unverified")]
    Unverified,
}

impl From<&str> for AttestationLevel {
    fn from(s: &str) -> Self {
        match s {
            "secure_enclave" => AttestationLevel::SecureEnclave,
            "strongbox" => AttestationLevel::StrongBox,
            "tee" => AttestationLevel::TrustedEnvironment,
            _ => AttestationLevel::Unverified,
        }
    }
}

// ============================================================================
// Security Level Info Structure (Story 10-2)
// ============================================================================

/// Detailed security level information for attestation (Story 10-2)
///
/// Provides platform-specific attestation details for display
/// on verification pages and API responses.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SecurityLevelInfo {
    /// Primary attestation security level: "strongbox", "tee", "secure_enclave"
    pub attestation_level: String,
    /// Android KeyMaster security level (may differ from attestation level)
    /// NULL for iOS devices
    #[serde(skip_serializing_if = "Option::is_none")]
    pub keymaster_level: Option<String>,
    /// Platform identifier: "ios" or "android"
    pub platform: String,
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
    /// Detailed security level information (Story 10-2)
    /// Omitted when not available (backward compatibility)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub security_level: Option<SecurityLevelInfo>,
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
            security_level: None,
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
            security_level: None,
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
            security_level: None,
        }
    }

    /// Sets the security level info (Story 10-2)
    pub fn with_security_level(mut self, security_level: Option<SecurityLevelInfo>) -> Self {
        self.security_level = security_level;
        self
    }
}

// ============================================================================
// Depth Analysis Structure (Placeholder for Story 4-5)
// ============================================================================

/// Depth analysis evidence for a capture
///
/// Records the result of analyzing the LiDAR depth map
/// to verify it represents a real 3D scene.
///
/// Story 10-5: Added `method` and `unavailable_reason` fields for cross-platform support.
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
    /// Source of depth analysis: "server" for full captures, "device" for hash-only captures (Story 8-5)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<AnalysisSource>,
    /// Depth analysis method: "lidar", "parallax" (future), or None if unavailable (Story 10-5)
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(default)]
    pub method: Option<String>,
    /// Reason why depth is unavailable, e.g., "android_no_lidar", "depth_map_missing" (Story 10-5)
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(default)]
    pub unavailable_reason: Option<String>,
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
            source: None,
            method: None,
            unavailable_reason: None,
        }
    }
}

impl DepthAnalysis {
    /// Creates depth analysis marked as unavailable for Android (no LiDAR) (Story 10-5)
    ///
    /// Android devices currently don't have LiDAR sensors. This helper creates
    /// a DepthAnalysis with appropriate unavailable status and reason.
    /// Note: Android parallax depth will be added in Epic 12.
    pub fn unavailable_android() -> Self {
        Self {
            status: CheckStatus::Unavailable,
            depth_variance: 0.0,
            depth_layers: 0,
            edge_coherence: 0.0,
            min_depth: 0.0,
            max_depth: 0.0,
            is_likely_real_scene: false,
            source: None,
            method: None,
            unavailable_reason: Some("android_no_lidar".to_string()),
        }
    }

    /// Sets the depth analysis method (Story 10-5)
    pub fn with_method(mut self, method: &str) -> Self {
        self.method = Some(method.to_string());
        self
    }

    /// Sets the unavailable reason (Story 10-5)
    pub fn with_unavailable_reason(mut self, reason: &str) -> Self {
        self.unavailable_reason = Some(reason.to_string());
        self
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
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
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
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
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

/// Default platform for backward compatibility (Story 10-5)
/// All existing captures before Story 10-5 are iOS, so we default to "ios".
fn default_platform() -> String {
    "ios".to_string()
}

/// Complete evidence package for a capture (Story 4-7, Story 10-5)
///
/// Contains all verification evidence collected during
/// capture processing: hardware attestation, depth analysis,
/// metadata validation, and processing info.
///
/// Story 10-5: Added `platform` field to support both iOS and Android captures.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidencePackage {
    /// Platform: "ios" or "android" (Story 10-5)
    /// Defaults to "ios" for backward compatibility with existing evidence.
    #[serde(default = "default_platform")]
    pub platform: String,
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
    /// Creates evidence package for iOS capture (Story 10-5)
    ///
    /// Use this builder when processing captures from iOS devices with DCAppAttest.
    pub fn for_ios(
        hardware_attestation: HardwareAttestation,
        depth_analysis: DepthAnalysis,
        metadata: MetadataEvidence,
        processing: ProcessingInfo,
    ) -> Self {
        Self {
            platform: "ios".to_string(),
            hardware_attestation,
            depth_analysis,
            metadata,
            processing,
        }
    }

    /// Creates evidence package for Android capture (Story 10-5)
    ///
    /// Use this builder when processing captures from Android devices with Key Attestation.
    pub fn for_android(
        hardware_attestation: HardwareAttestation,
        depth_analysis: DepthAnalysis,
        metadata: MetadataEvidence,
        processing: ProcessingInfo,
    ) -> Self {
        Self {
            platform: "android".to_string(),
            hardware_attestation,
            depth_analysis,
            metadata,
            processing,
        }
    }

    /// Creates evidence package with specified platform (Story 10-5)
    ///
    /// Generic builder that accepts platform string. Useful when platform
    /// is determined at runtime (e.g., from device record).
    pub fn with_platform(
        platform: &str,
        hardware_attestation: HardwareAttestation,
        depth_analysis: DepthAnalysis,
        metadata: MetadataEvidence,
        processing: ProcessingInfo,
    ) -> Self {
        Self {
            platform: platform.to_lowercase(),
            hardware_attestation,
            depth_analysis,
            metadata,
            processing,
        }
    }

    /// Calculates the confidence level based on all evidence
    ///
    /// Logic:
    /// - If any check explicitly failed -> Suspicious
    /// - If both hw and depth pass -> High
    /// - If either hw or depth pass -> Medium
    /// - If both unavailable -> Low
    ///
    /// Story 10-5 Note: This logic naturally handles Android captures where
    /// depth is unavailable (hw_pass=true, depth_pass=false -> Medium).
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
        assert_eq!(
            serde_json::to_string(&CheckStatus::Pass).unwrap(),
            "\"pass\""
        );
        assert_eq!(
            serde_json::to_string(&CheckStatus::Fail).unwrap(),
            "\"fail\""
        );
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
        // Story 10-2: New Android attestation levels
        assert_eq!(
            serde_json::to_string(&AttestationLevel::StrongBox).unwrap(),
            "\"strongbox\""
        );
        assert_eq!(
            serde_json::to_string(&AttestationLevel::TrustedEnvironment).unwrap(),
            "\"tee\""
        );
    }

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
        // Story 10-2: New Android attestation levels
        assert_eq!(
            AttestationLevel::from("strongbox"),
            AttestationLevel::StrongBox
        );
        assert_eq!(
            AttestationLevel::from("tee"),
            AttestationLevel::TrustedEnvironment
        );
    }

    // ========================================================================
    // Story 10-2: Security Level Info Tests
    // ========================================================================

    #[test]
    fn test_security_level_info_serialization() {
        let info = SecurityLevelInfo {
            attestation_level: "strongbox".to_string(),
            keymaster_level: Some("strongbox".to_string()),
            platform: "android".to_string(),
        };

        let json = serde_json::to_string(&info).unwrap();
        assert!(json.contains("\"attestation_level\":\"strongbox\""));
        assert!(json.contains("\"keymaster_level\":\"strongbox\""));
        assert!(json.contains("\"platform\":\"android\""));
    }

    #[test]
    fn test_security_level_info_ios_omits_keymaster() {
        let info = SecurityLevelInfo {
            attestation_level: "secure_enclave".to_string(),
            keymaster_level: None,
            platform: "ios".to_string(),
        };

        let json = serde_json::to_string(&info).unwrap();
        assert!(json.contains("\"attestation_level\":\"secure_enclave\""));
        assert!(!json.contains("keymaster_level")); // Omitted when None
        assert!(json.contains("\"platform\":\"ios\""));
    }

    #[test]
    fn test_security_level_info_deserialization() {
        let json = r#"{"attestation_level":"tee","keymaster_level":"tee","platform":"android"}"#;
        let info: SecurityLevelInfo = serde_json::from_str(json).unwrap();
        assert_eq!(info.attestation_level, "tee");
        assert_eq!(info.keymaster_level, Some("tee".to_string()));
        assert_eq!(info.platform, "android");
    }

    #[test]
    fn test_hardware_attestation_with_security_level() {
        let hw = HardwareAttestation::pass("Pixel 8 Pro".to_string(), AttestationLevel::StrongBox)
            .with_security_level(Some(SecurityLevelInfo {
                attestation_level: "strongbox".to_string(),
                keymaster_level: Some("strongbox".to_string()),
                platform: "android".to_string(),
            }));

        assert_eq!(hw.status, CheckStatus::Pass);
        assert_eq!(hw.level, AttestationLevel::StrongBox);
        assert!(hw.security_level.is_some());
        let sl = hw.security_level.unwrap();
        assert_eq!(sl.attestation_level, "strongbox");
        assert_eq!(sl.platform, "android");
    }

    #[test]
    fn test_hardware_attestation_security_level_omitted_when_none() {
        let hw =
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave);

        let json = serde_json::to_string(&hw).unwrap();
        // security_level should be omitted when None (skip_serializing_if)
        assert!(!json.contains("security_level"));
    }

    #[test]
    fn test_confidence_level_serialization() {
        assert_eq!(
            serde_json::to_string(&ConfidenceLevel::High).unwrap(),
            "\"high\""
        );
        assert_eq!(
            serde_json::to_string(&ConfidenceLevel::Medium).unwrap(),
            "\"medium\""
        );
        assert_eq!(
            serde_json::to_string(&ConfidenceLevel::Low).unwrap(),
            "\"low\""
        );
        assert_eq!(
            serde_json::to_string(&ConfidenceLevel::Suspicious).unwrap(),
            "\"suspicious\""
        );
    }

    #[test]
    fn test_hardware_attestation_unavailable() {
        let hw = HardwareAttestation::unavailable(
            "iPhone 15 Pro".to_string(),
            AttestationLevel::SecureEnclave,
        );
        assert_eq!(hw.status, CheckStatus::Unavailable);
        assert!(!hw.assertion_verified);
        assert!(!hw.counter_valid);
    }

    #[test]
    fn test_hardware_attestation_pass() {
        let hw =
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave);
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
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::fail(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
                false,
                false,
            ),
            DepthAnalysis::default(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_both_pass_is_high() {
        let depth = DepthAnalysis {
            status: CheckStatus::Pass,
            is_likely_real_scene: true,
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::High);
    }

    #[test]
    fn test_confidence_hw_pass_depth_unavailable_is_medium() {
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            DepthAnalysis::default(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_both_unavailable_is_low() {
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::unavailable(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            DepthAnalysis::default(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Low);
    }

    #[test]
    fn test_confidence_depth_fail_is_suspicious() {
        let depth = DepthAnalysis {
            status: CheckStatus::Fail,
            is_likely_real_scene: false,
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_depth_pass_hw_unavailable_is_medium() {
        let depth = DepthAnalysis {
            status: CheckStatus::Pass,
            is_likely_real_scene: true,
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::unavailable(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
            ),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );
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
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            DepthAnalysis::default(),
            MetadataEvidence::default(),
            ProcessingInfo::new(1000, "0.1.0"),
        );

        let json = serde_json::to_string(&evidence).unwrap();
        assert!(json.contains("\"platform\":\"ios\""));
        assert!(json.contains("\"hardware_attestation\""));
        assert!(json.contains("\"depth_analysis\""));
        assert!(json.contains("\"metadata\""));
        assert!(json.contains("\"processing\""));
        assert!(json.contains("\"processing_time_ms\":1000"));
    }

    // ========================================================================
    // Story 8-5: Hash-Only Evidence Tests
    // ========================================================================

    #[test]
    fn test_depth_analysis_source_serialization_with_device() {
        let depth = DepthAnalysis {
            source: Some(AnalysisSource::Device),
            ..Default::default()
        };

        let json = serde_json::to_string(&depth).unwrap();
        assert!(json.contains("\"source\":\"device\""));
    }

    #[test]
    fn test_depth_analysis_source_serialization_with_server() {
        let depth = DepthAnalysis {
            source: Some(AnalysisSource::Server),
            ..Default::default()
        };

        let json = serde_json::to_string(&depth).unwrap();
        assert!(json.contains("\"source\":\"server\""));
    }

    #[test]
    fn test_depth_analysis_source_omitted_when_none() {
        let depth = DepthAnalysis {
            source: None,
            ..Default::default()
        };

        let json = serde_json::to_string(&depth).unwrap();
        // Source field should be omitted when None (skip_serializing_if)
        assert!(!json.contains("\"source\""));
    }

    #[test]
    fn test_confidence_hash_only_both_pass_is_high() {
        // Hash-only capture: source=Device, both checks pass -> HIGH
        // Same as full capture - source doesn't change confidence logic
        let depth = DepthAnalysis {
            status: CheckStatus::Pass,
            is_likely_real_scene: true,
            source: Some(AnalysisSource::Device),
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        // Confidence is HIGH regardless of source=Device
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::High);
    }

    #[test]
    fn test_confidence_hash_only_depth_fail_is_suspicious() {
        // Hash-only with device depth fail -> SUSPICIOUS (same as server)
        let depth = DepthAnalysis {
            status: CheckStatus::Fail,
            is_likely_real_scene: false,
            source: Some(AnalysisSource::Device),
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_hash_only_depth_unavailable_is_medium() {
        // Hash-only with attestation pass, depth unavailable -> MEDIUM
        let depth = DepthAnalysis {
            status: CheckStatus::Unavailable,
            is_likely_real_scene: false,
            source: Some(AnalysisSource::Device),
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Medium);
    }

    #[test]
    fn test_depth_analysis_deserialization_with_source() {
        let json = r#"{
            "status": "pass",
            "depth_variance": 2.4,
            "depth_layers": 5,
            "edge_coherence": 0.87,
            "min_depth": 0.8,
            "max_depth": 4.2,
            "is_likely_real_scene": true,
            "source": "device"
        }"#;

        let depth: DepthAnalysis = serde_json::from_str(json).unwrap();
        assert_eq!(depth.source, Some(AnalysisSource::Device));
        assert_eq!(depth.status, CheckStatus::Pass);
        assert!(depth.is_likely_real_scene);
    }

    #[test]
    fn test_depth_analysis_deserialization_without_source() {
        // Backward compatibility: old records without source field
        let json = r#"{
            "status": "pass",
            "depth_variance": 2.4,
            "depth_layers": 5,
            "edge_coherence": 0.87,
            "min_depth": 0.8,
            "max_depth": 4.2,
            "is_likely_real_scene": true
        }"#;

        let depth: DepthAnalysis = serde_json::from_str(json).unwrap();
        assert_eq!(depth.source, None);
    }

    // ========================================================================
    // Story 10-5: Unified Evidence Schema Tests
    // ========================================================================

    #[test]
    fn test_evidence_package_for_ios_builder() {
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            DepthAnalysis::default(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.platform, "ios");
    }

    #[test]
    fn test_evidence_package_for_android_builder() {
        let evidence = EvidencePackage::for_android(
            HardwareAttestation::pass("Pixel 8 Pro".to_string(), AttestationLevel::StrongBox),
            DepthAnalysis::unavailable_android(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.platform, "android");
    }

    #[test]
    fn test_evidence_package_with_platform_builder() {
        let evidence = EvidencePackage::with_platform(
            "Android", // Should be lowercased
            HardwareAttestation::pass("Pixel 8 Pro".to_string(), AttestationLevel::StrongBox),
            DepthAnalysis::unavailable_android(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.platform, "android");
    }

    #[test]
    fn test_evidence_package_serialization_includes_platform() {
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            DepthAnalysis::default().with_method("lidar"),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        let json = serde_json::to_string(&evidence).unwrap();
        assert!(json.contains("\"platform\":\"ios\""));
    }

    #[test]
    fn test_evidence_package_android_serialization() {
        let evidence = EvidencePackage::for_android(
            HardwareAttestation::pass("Pixel 8 Pro".to_string(), AttestationLevel::StrongBox),
            DepthAnalysis::unavailable_android(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        let json = serde_json::to_string(&evidence).unwrap();
        assert!(json.contains("\"platform\":\"android\""));
        assert!(json.contains("\"unavailable_reason\":\"android_no_lidar\""));
    }

    #[test]
    fn test_backward_compatibility_deserialize_without_platform() {
        // Legacy evidence without platform field should default to "ios"
        let json = r#"{
            "hardware_attestation": {
                "status": "pass",
                "level": "secure_enclave",
                "device_model": "iPhone 15 Pro",
                "assertion_verified": true,
                "counter_valid": true
            },
            "depth_analysis": {
                "status": "pass",
                "depth_variance": 2.4,
                "depth_layers": 5,
                "edge_coherence": 0.87,
                "min_depth": 0.8,
                "max_depth": 4.2,
                "is_likely_real_scene": true
            },
            "metadata": {
                "timestamp_valid": true,
                "timestamp_delta_seconds": 0,
                "model_verified": true,
                "model_name": "iPhone 15 Pro",
                "resolution_valid": true,
                "location_available": false,
                "location_opted_out": true
            },
            "processing": {
                "processed_at": "2025-01-01T00:00:00Z",
                "processing_time_ms": 1000,
                "backend_version": "0.1.0"
            }
        }"#;

        let evidence: EvidencePackage = serde_json::from_str(json).unwrap();
        assert_eq!(evidence.platform, "ios"); // Default value
    }

    #[test]
    fn test_depth_analysis_method_serialization() {
        let depth = DepthAnalysis {
            status: CheckStatus::Pass,
            is_likely_real_scene: true,
            method: Some("lidar".to_string()),
            ..Default::default()
        };

        let json = serde_json::to_string(&depth).unwrap();
        assert!(json.contains("\"method\":\"lidar\""));
    }

    #[test]
    fn test_depth_analysis_unavailable_reason_serialization() {
        let depth = DepthAnalysis::unavailable_android();

        let json = serde_json::to_string(&depth).unwrap();
        assert!(json.contains("\"unavailable_reason\":\"android_no_lidar\""));
        assert!(!json.contains("\"method\"")); // Method should be None/omitted
    }

    #[test]
    fn test_depth_analysis_method_omitted_when_none() {
        let depth = DepthAnalysis::default();

        let json = serde_json::to_string(&depth).unwrap();
        assert!(!json.contains("\"method\""));
        assert!(!json.contains("\"unavailable_reason\""));
    }

    #[test]
    fn test_depth_analysis_with_method_builder() {
        let depth = DepthAnalysis {
            status: CheckStatus::Pass,
            is_likely_real_scene: true,
            ..Default::default()
        }
        .with_method("lidar");

        assert_eq!(depth.method, Some("lidar".to_string()));
    }

    #[test]
    fn test_depth_analysis_with_unavailable_reason_builder() {
        let depth = DepthAnalysis::default().with_unavailable_reason("depth_map_missing");

        assert_eq!(
            depth.unavailable_reason,
            Some("depth_map_missing".to_string())
        );
    }

    #[test]
    fn test_confidence_ios_hw_pass_depth_pass_is_high() {
        // iOS: hw pass + depth pass = HIGH
        let depth = DepthAnalysis {
            status: CheckStatus::Pass,
            is_likely_real_scene: true,
            method: Some("lidar".to_string()),
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::High);
    }

    #[test]
    fn test_confidence_ios_hw_pass_depth_unavailable_is_medium() {
        // iOS: hw pass + depth unavailable = MEDIUM
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            DepthAnalysis::default(), // Unavailable
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_android_strongbox_depth_unavailable_is_medium() {
        // Android: StrongBox pass + no depth = MEDIUM (AC 6.1)
        let evidence = EvidencePackage::for_android(
            HardwareAttestation::pass("Pixel 8 Pro".to_string(), AttestationLevel::StrongBox),
            DepthAnalysis::unavailable_android(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_android_tee_depth_unavailable_is_medium() {
        // Android: TEE pass + no depth = MEDIUM (AC 6.2)
        let evidence = EvidencePackage::for_android(
            HardwareAttestation::pass(
                "Samsung Galaxy S24".to_string(),
                AttestationLevel::TrustedEnvironment,
            ),
            DepthAnalysis::unavailable_android(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_android_hw_fail_is_suspicious() {
        // Android: hw fail = SUSPICIOUS (AC 6.3)
        let evidence = EvidencePackage::for_android(
            HardwareAttestation::fail(
                "Pixel 8 Pro".to_string(),
                AttestationLevel::StrongBox,
                false,
                false,
            ),
            DepthAnalysis::unavailable_android(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_ios_hw_fail_is_suspicious() {
        // iOS: hw fail = SUSPICIOUS (unchanged from Story 4-4)
        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::fail(
                "iPhone 15 Pro".to_string(),
                AttestationLevel::SecureEnclave,
                false,
                false,
            ),
            DepthAnalysis::default(),
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_ios_depth_fail_is_suspicious() {
        // iOS: depth fail = SUSPICIOUS (unchanged from Story 4-4)
        let depth = DepthAnalysis {
            status: CheckStatus::Fail,
            is_likely_real_scene: false,
            method: Some("lidar".to_string()),
            ..Default::default()
        };

        let evidence = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            depth,
            MetadataEvidence::default(),
            ProcessingInfo::default(),
        );

        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_backward_compatibility_deserialize_depth_without_method() {
        // Legacy depth analysis without method field should work
        let json = r#"{
            "status": "pass",
            "depth_variance": 2.4,
            "depth_layers": 5,
            "edge_coherence": 0.87,
            "min_depth": 0.8,
            "max_depth": 4.2,
            "is_likely_real_scene": true,
            "source": "server"
        }"#;

        let depth: DepthAnalysis = serde_json::from_str(json).unwrap();
        assert_eq!(depth.method, None);
        assert_eq!(depth.unavailable_reason, None);
        assert_eq!(depth.source, Some(AnalysisSource::Server));
    }

    #[test]
    fn test_legacy_evidence_confidence_unchanged() {
        // Verify confidence calculation for legacy iOS evidence is unchanged
        let json = r#"{
            "hardware_attestation": {
                "status": "pass",
                "level": "secure_enclave",
                "device_model": "iPhone 15 Pro",
                "assertion_verified": true,
                "counter_valid": true
            },
            "depth_analysis": {
                "status": "pass",
                "depth_variance": 2.4,
                "depth_layers": 5,
                "edge_coherence": 0.87,
                "min_depth": 0.8,
                "max_depth": 4.2,
                "is_likely_real_scene": true
            },
            "metadata": {
                "timestamp_valid": true,
                "timestamp_delta_seconds": 0,
                "model_verified": true,
                "model_name": "iPhone 15 Pro",
                "resolution_valid": true,
                "location_available": false,
                "location_opted_out": true
            },
            "processing": {
                "processed_at": "2025-01-01T00:00:00Z",
                "processing_time_ms": 1000,
                "backend_version": "0.1.0"
            }
        }"#;

        let evidence: EvidencePackage = serde_json::from_str(json).unwrap();

        // Platform should default to "ios"
        assert_eq!(evidence.platform, "ios");

        // Confidence should be HIGH (both hw and depth pass)
        assert_eq!(evidence.calculate_confidence(), ConfidenceLevel::High);
    }

    #[test]
    fn test_depth_analysis_unavailable_android_helper() {
        let depth = DepthAnalysis::unavailable_android();

        assert_eq!(depth.status, CheckStatus::Unavailable);
        assert_eq!(depth.depth_variance, 0.0);
        assert_eq!(depth.depth_layers, 0);
        assert!(!depth.is_likely_real_scene);
        assert_eq!(depth.method, None);
        assert_eq!(
            depth.unavailable_reason,
            Some("android_no_lidar".to_string())
        );
    }

    #[test]
    fn test_evidence_serialization_round_trip_ios() {
        let original = EvidencePackage::for_ios(
            HardwareAttestation::pass("iPhone 15 Pro".to_string(), AttestationLevel::SecureEnclave),
            DepthAnalysis {
                status: CheckStatus::Pass,
                is_likely_real_scene: true,
                method: Some("lidar".to_string()),
                source: Some(AnalysisSource::Server),
                ..Default::default()
            },
            MetadataEvidence::default(),
            ProcessingInfo::new(1000, "0.1.0"),
        );

        let json = serde_json::to_string(&original).unwrap();
        let parsed: EvidencePackage = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.platform, "ios");
        assert_eq!(parsed.depth_analysis.method, Some("lidar".to_string()));
        assert_eq!(
            parsed.calculate_confidence(),
            original.calculate_confidence()
        );
    }

    #[test]
    fn test_evidence_serialization_round_trip_android() {
        let original = EvidencePackage::for_android(
            HardwareAttestation::pass("Pixel 8 Pro".to_string(), AttestationLevel::StrongBox),
            DepthAnalysis::unavailable_android(),
            MetadataEvidence::default(),
            ProcessingInfo::new(500, "0.1.0"),
        );

        let json = serde_json::to_string(&original).unwrap();
        let parsed: EvidencePackage = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.platform, "android");
        assert_eq!(
            parsed.depth_analysis.unavailable_reason,
            Some("android_no_lidar".to_string())
        );
        assert_eq!(
            parsed.calculate_confidence(),
            original.calculate_confidence()
        );
    }
}
