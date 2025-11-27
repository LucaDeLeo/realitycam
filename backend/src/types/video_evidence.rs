//! Video Evidence Types (Story 7-11)
//!
//! Types for video evidence package assembly and confidence calculation.
//! Aggregates results from:
//! - Hardware attestation (DCAppAttest assertion validation)
//! - Hash chain verification (Story 7-10)
//! - Temporal depth analysis (Story 7-9)
//! - Metadata validation
//!
//! Video evidence has stricter confidence thresholds than photo evidence
//! due to higher manipulation risk (splice attacks, frame insertion).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::types::hash_chain_verification::HashChainVerification;
use crate::types::video_depth_analysis::VideoDepthAnalysis;

// ============================================================================
// Confidence Level (shared with photos, re-exported for convenience)
// ============================================================================

/// Confidence level for evidence assessment
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VideoConfidenceLevel {
    /// All checks pass with strong metrics
    High,
    /// Core checks pass, some degraded/unavailable
    Medium,
    /// Multiple checks unavailable but no failures
    Low,
    /// Any check explicitly failed
    Suspicious,
}

impl std::fmt::Display for VideoConfidenceLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VideoConfidenceLevel::High => write!(f, "high"),
            VideoConfidenceLevel::Medium => write!(f, "medium"),
            VideoConfidenceLevel::Low => write!(f, "low"),
            VideoConfidenceLevel::Suspicious => write!(f, "suspicious"),
        }
    }
}

// ============================================================================
// Video Evidence Package
// ============================================================================

/// Complete video evidence package
///
/// Aggregates all verification results into a single package for
/// storage, confidence calculation, and C2PA manifest generation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoEvidence {
    /// Evidence type (always "video")
    #[serde(rename = "type")]
    pub evidence_type: String,

    /// Total video duration in milliseconds
    pub duration_ms: u64,

    /// Total frame count
    pub frame_count: u32,

    /// Hardware attestation validation results
    pub hardware_attestation: HardwareAttestationEvidence,

    /// Hash chain verification results (Story 7-10)
    pub hash_chain: HashChainEvidence,

    /// Temporal depth analysis results (Story 7-9)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub depth_analysis: Option<DepthAnalysisEvidence>,

    /// Metadata validation results
    pub metadata: MetadataEvidence,

    /// Partial attestation information (for interrupted recordings)
    pub partial_attestation: PartialAttestationInfo,

    /// Processing metadata
    pub processing: ProcessingInfo,
}

impl VideoEvidence {
    /// Create a new video evidence package
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        duration_ms: u64,
        frame_count: u32,
        hardware_attestation: HardwareAttestationEvidence,
        hash_chain: HashChainEvidence,
        depth_analysis: Option<DepthAnalysisEvidence>,
        metadata: MetadataEvidence,
        partial_attestation: PartialAttestationInfo,
        processing: ProcessingInfo,
    ) -> Self {
        Self {
            evidence_type: "video".to_string(),
            duration_ms,
            frame_count,
            hardware_attestation,
            hash_chain,
            depth_analysis,
            metadata,
            partial_attestation,
            processing,
        }
    }
}

// ============================================================================
// Hardware Attestation Evidence
// ============================================================================

/// Hardware attestation evidence from DCAppAttest
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareAttestationEvidence {
    /// Status: "pass", "fail", "unavailable"
    pub status: String,

    /// Assertion signature was verified
    pub assertion_valid: bool,

    /// Device is registered and verified
    pub device_verified: bool,

    /// Attestation timestamp
    pub attestation_time: DateTime<Utc>,
}

impl HardwareAttestationEvidence {
    /// Create a passing attestation result
    pub fn pass(attestation_time: DateTime<Utc>) -> Self {
        Self {
            status: "pass".to_string(),
            assertion_valid: true,
            device_verified: true,
            attestation_time,
        }
    }

    /// Create a failing attestation result
    pub fn fail(attestation_time: DateTime<Utc>) -> Self {
        Self {
            status: "fail".to_string(),
            assertion_valid: false,
            device_verified: false,
            attestation_time,
        }
    }

    /// Create an unavailable attestation result
    pub fn unavailable() -> Self {
        Self {
            status: "unavailable".to_string(),
            assertion_valid: false,
            device_verified: false,
            attestation_time: Utc::now(),
        }
    }
}

// ============================================================================
// Hash Chain Evidence
// ============================================================================

/// Hash chain verification evidence (from Story 7-10)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashChainEvidence {
    /// Status: "pass", "partial", "fail"
    pub status: String,

    /// Frames successfully verified
    pub verified_frames: u32,

    /// Total frames in chain
    pub total_frames: u32,

    /// Hash chain is intact (no breaks)
    pub chain_intact: bool,

    /// Attestation hash matches submitted chain
    pub attestation_valid: bool,

    /// Reason for partial verification
    #[serde(skip_serializing_if = "Option::is_none")]
    pub partial_reason: Option<String>,

    /// Verified duration in milliseconds
    pub verified_duration_ms: u32,

    /// Checkpoint was verified (for partial videos)
    pub checkpoint_verified: bool,

    /// Checkpoint index if partial
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkpoint_index: Option<u32>,
}

impl HashChainEvidence {
    /// Create from HashChainVerification result
    pub fn from_verification(v: &HashChainVerification) -> Self {
        use crate::types::hash_chain_verification::VerificationStatus;

        let status = match v.status {
            VerificationStatus::Pass => "pass",
            VerificationStatus::Partial => "partial",
            VerificationStatus::Fail => "fail",
        };

        Self {
            status: status.to_string(),
            verified_frames: v.frame_count,
            total_frames: v.frame_count,
            chain_intact: v.chain_structure_valid && v.final_hash_matches,
            attestation_valid: v.attestation_valid,
            partial_reason: v.failure_reason.clone(),
            verified_duration_ms: v.duration_ms,
            checkpoint_verified: v.is_partial && v.checkpoint_index.is_some(),
            checkpoint_index: v.checkpoint_index,
        }
    }

    /// Create a failing hash chain result
    pub fn fail(reason: &str) -> Self {
        Self {
            status: "fail".to_string(),
            verified_frames: 0,
            total_frames: 0,
            chain_intact: false,
            attestation_valid: false,
            partial_reason: Some(reason.to_string()),
            verified_duration_ms: 0,
            checkpoint_verified: false,
            checkpoint_index: None,
        }
    }
}

// ============================================================================
// Depth Analysis Evidence
// ============================================================================

/// Depth analysis evidence (from Story 7-9)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepthAnalysisEvidence {
    /// Depth consistency score (0-1)
    pub depth_consistency: f32,

    /// Motion coherence score (0-1)
    pub motion_coherence: f32,

    /// Scene stability score (0-1)
    pub scene_stability: f32,

    /// Aggregate assessment: likely a real 3D scene
    pub is_likely_real_scene: bool,

    /// Frame indices with anomalies
    pub suspicious_frames: Vec<u32>,
}

impl DepthAnalysisEvidence {
    /// Create from VideoDepthAnalysis result
    pub fn from_analysis(a: &VideoDepthAnalysis) -> Self {
        Self {
            depth_consistency: a.depth_consistency,
            motion_coherence: a.motion_coherence,
            scene_stability: a.scene_stability,
            is_likely_real_scene: a.is_likely_real_scene,
            suspicious_frames: a.suspicious_frames.clone(),
        }
    }
}

// ============================================================================
// Metadata Evidence
// ============================================================================

/// Metadata validation evidence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetadataEvidence {
    /// Device model name
    pub device_model: String,

    /// Valid location data available
    pub location_valid: bool,

    /// Timestamp is within acceptable bounds
    pub timestamp_valid: bool,
}

impl MetadataEvidence {
    /// Create metadata evidence
    pub fn new(device_model: String, location_valid: bool, timestamp_valid: bool) -> Self {
        Self {
            device_model,
            location_valid,
            timestamp_valid,
        }
    }
}

// ============================================================================
// Partial Attestation Info
// ============================================================================

/// Information about partial video attestation
///
/// When a recording is interrupted, the last checkpoint before
/// interruption is used for attestation instead of the final hash.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartialAttestationInfo {
    /// Whether video was interrupted
    pub is_partial: bool,

    /// Checkpoint index if partial (0=5s, 1=10s, 2=15s)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkpoint_index: Option<u32>,

    /// Frames successfully verified
    pub verified_frames: u32,

    /// Total frames captured
    pub total_frames: u32,

    /// Reason for partial attestation
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

impl PartialAttestationInfo {
    /// Create non-partial attestation info
    pub fn complete(frame_count: u32) -> Self {
        Self {
            is_partial: false,
            checkpoint_index: None,
            verified_frames: frame_count,
            total_frames: frame_count,
            reason: None,
        }
    }

    /// Create partial attestation info
    pub fn partial(checkpoint_index: u32, verified_frames: u32, total_frames: u32) -> Self {
        Self {
            is_partial: true,
            checkpoint_index: Some(checkpoint_index),
            verified_frames,
            total_frames,
            reason: Some("checkpoint_attestation".to_string()),
        }
    }
}

// ============================================================================
// Processing Info
// ============================================================================

/// Processing metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessingInfo {
    /// When processing completed
    pub processed_at: DateTime<Utc>,

    /// Total processing time in milliseconds
    pub processing_time_ms: u64,

    /// Backend version that processed the capture
    pub backend_version: String,

    /// List of checks performed
    pub checks_performed: Vec<String>,
}

impl ProcessingInfo {
    /// Create processing info
    pub fn new(processing_time_ms: u64, backend_version: String, checks: Vec<String>) -> Self {
        Self {
            processed_at: Utc::now(),
            processing_time_ms,
            backend_version,
            checks_performed: checks,
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
    fn test_confidence_level_display() {
        assert_eq!(VideoConfidenceLevel::High.to_string(), "high");
        assert_eq!(VideoConfidenceLevel::Medium.to_string(), "medium");
        assert_eq!(VideoConfidenceLevel::Low.to_string(), "low");
        assert_eq!(VideoConfidenceLevel::Suspicious.to_string(), "suspicious");
    }

    #[test]
    fn test_confidence_level_serialization() {
        let json = serde_json::to_string(&VideoConfidenceLevel::High).unwrap();
        assert_eq!(json, "\"high\"");

        let json = serde_json::to_string(&VideoConfidenceLevel::Suspicious).unwrap();
        assert_eq!(json, "\"suspicious\"");
    }

    #[test]
    fn test_hardware_attestation_pass() {
        let hw = HardwareAttestationEvidence::pass(Utc::now());
        assert_eq!(hw.status, "pass");
        assert!(hw.assertion_valid);
        assert!(hw.device_verified);
    }

    #[test]
    fn test_hardware_attestation_fail() {
        let hw = HardwareAttestationEvidence::fail(Utc::now());
        assert_eq!(hw.status, "fail");
        assert!(!hw.assertion_valid);
    }

    #[test]
    fn test_hash_chain_evidence_fail() {
        let chain = HashChainEvidence::fail("test failure");
        assert_eq!(chain.status, "fail");
        assert!(!chain.chain_intact);
        assert_eq!(chain.partial_reason, Some("test failure".to_string()));
    }

    #[test]
    fn test_partial_attestation_complete() {
        let partial = PartialAttestationInfo::complete(450);
        assert!(!partial.is_partial);
        assert_eq!(partial.verified_frames, 450);
        assert!(partial.checkpoint_index.is_none());
    }

    #[test]
    fn test_partial_attestation_partial() {
        let partial = PartialAttestationInfo::partial(1, 300, 450);
        assert!(partial.is_partial);
        assert_eq!(partial.checkpoint_index, Some(1));
        assert_eq!(partial.verified_frames, 300);
        assert_eq!(partial.total_frames, 450);
        assert_eq!(partial.reason, Some("checkpoint_attestation".to_string()));
    }

    #[test]
    fn test_processing_info_creation() {
        let info = ProcessingInfo::new(1500, "0.1.0".to_string(), vec!["hardware".to_string()]);
        assert_eq!(info.processing_time_ms, 1500);
        assert_eq!(info.backend_version, "0.1.0");
        assert_eq!(info.checks_performed.len(), 1);
    }

    #[test]
    fn test_video_evidence_serialization() {
        let evidence = VideoEvidence::new(
            15000,
            450,
            HardwareAttestationEvidence::pass(Utc::now()),
            HashChainEvidence {
                status: "pass".to_string(),
                verified_frames: 450,
                total_frames: 450,
                chain_intact: true,
                attestation_valid: true,
                partial_reason: None,
                verified_duration_ms: 15000,
                checkpoint_verified: false,
                checkpoint_index: None,
            },
            None,
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            PartialAttestationInfo::complete(450),
            ProcessingInfo::new(1000, "0.1.0".to_string(), vec!["hardware".to_string()]),
        );

        let json = serde_json::to_string(&evidence).unwrap();
        assert!(json.contains("\"type\":\"video\""));
        assert!(json.contains("\"duration_ms\":15000"));
        assert!(json.contains("\"hardware_attestation\""));
        assert!(json.contains("\"hash_chain\""));
    }

    #[test]
    fn test_depth_analysis_evidence_from_analysis() {
        let analysis = VideoDepthAnalysis {
            frame_analyses: vec![],
            depth_consistency: 0.85,
            motion_coherence: 0.72,
            scene_stability: 0.95,
            is_likely_real_scene: true,
            suspicious_frames: vec![],
        };

        let evidence = DepthAnalysisEvidence::from_analysis(&analysis);
        assert_eq!(evidence.depth_consistency, 0.85);
        assert_eq!(evidence.motion_coherence, 0.72);
        assert_eq!(evidence.scene_stability, 0.95);
        assert!(evidence.is_likely_real_scene);
    }

    #[test]
    fn test_metadata_evidence_creation() {
        let metadata = MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true);
        assert_eq!(metadata.device_model, "iPhone 15 Pro");
        assert!(metadata.location_valid);
        assert!(metadata.timestamp_valid);
    }
}
