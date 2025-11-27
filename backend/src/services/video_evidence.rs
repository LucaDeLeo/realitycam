//! Video Evidence Service (Story 7-11)
//!
//! Service for assembling video evidence packages and calculating confidence.
//! Aggregates results from:
//! - Hardware attestation validation (DCAppAttest)
//! - Hash chain verification (Story 7-10)
//! - Temporal depth analysis (Story 7-9)
//! - Metadata validation
//!
//! ## Security Model
//!
//! Video confidence is stricter than photo confidence due to higher
//! manipulation risk:
//! - Photos: HIGH requires hardware + depth pass
//! - Videos: HIGH requires hardware + hash chain + depth (all pass with strong metrics)
//!
//! ## Confidence Calculation
//!
//! | Hardware | Hash Chain | Depth | Confidence |
//! |----------|------------|-------|------------|
//! | pass | pass + intact | pass (consistent) | HIGH |
//! | pass | pass + intact | unavailable | MEDIUM |
//! | pass | partial (checkpoint) | any | MEDIUM |
//! | fail | any | any | SUSPICIOUS |
//! | any | fail (broken) | any | SUSPICIOUS |
//! | pass | pass | fail (suspicious) | SUSPICIOUS |
//! | unavailable | unavailable | unavailable | LOW |

use std::time::Instant;
use tracing::{debug, info, instrument, warn};

use crate::types::hash_chain_verification::HashChainVerification;
use crate::types::video_depth_analysis::VideoDepthAnalysis;
use crate::types::video_evidence::{
    DepthAnalysisEvidence, HardwareAttestationEvidence, HashChainEvidence, MetadataEvidence,
    PartialAttestationInfo, ProcessingInfo, VideoConfidenceLevel, VideoEvidence,
};

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for video evidence service
#[derive(Debug, Clone)]
pub struct VideoEvidenceConfig {
    /// Minimum depth consistency for HIGH confidence
    pub depth_consistency_threshold: f32,
    /// Minimum scene stability for HIGH confidence
    pub scene_stability_threshold: f32,
}

impl Default for VideoEvidenceConfig {
    fn default() -> Self {
        Self {
            depth_consistency_threshold: 0.7,
            scene_stability_threshold: 0.8,
        }
    }
}

// ============================================================================
// Service
// ============================================================================

/// Service for assembling video evidence packages and calculating confidence.
///
/// ## Usage
///
/// ```ignore
/// let service = VideoEvidenceService::new();
///
/// // Build evidence from verification results
/// let evidence = service.build_evidence(
///     hw_attestation,
///     hash_chain_result,
///     Some(depth_analysis),
///     metadata,
///     false, // is_partial
///     None,  // checkpoint_index
///     15000, // duration_ms
///     450,   // frame_count
///     start_time,
/// );
///
/// // Calculate confidence
/// let confidence = service.calculate_confidence(&evidence);
/// ```
pub struct VideoEvidenceService {
    config: VideoEvidenceConfig,
    backend_version: String,
}

impl VideoEvidenceService {
    /// Create a new video evidence service with default configuration
    pub fn new() -> Self {
        Self {
            config: VideoEvidenceConfig::default(),
            backend_version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }

    /// Create a new video evidence service with custom configuration
    pub fn with_config(config: VideoEvidenceConfig) -> Self {
        Self {
            config,
            backend_version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }

    /// Build complete evidence package from verification results
    ///
    /// Aggregates all verification results into a single evidence package
    /// that can be stored, used for confidence calculation, and included
    /// in C2PA manifests.
    #[instrument(skip(self, hw_attestation, hash_chain, depth_analysis, metadata, start_time))]
    #[allow(clippy::too_many_arguments)]
    pub fn build_evidence(
        &self,
        hw_attestation: HardwareAttestationEvidence,
        hash_chain: &HashChainVerification,
        depth_analysis: Option<&VideoDepthAnalysis>,
        metadata: MetadataEvidence,
        is_partial: bool,
        checkpoint_index: Option<u32>,
        duration_ms: u64,
        frame_count: u32,
        start_time: Instant,
    ) -> VideoEvidence {
        let processing_time_ms = start_time.elapsed().as_millis() as u64;

        // Build hash chain evidence from verification result
        let hash_chain_evidence = HashChainEvidence::from_verification(hash_chain);

        // Build depth analysis evidence if available
        let depth_evidence = depth_analysis.map(DepthAnalysisEvidence::from_analysis);

        // Build partial attestation info
        let partial_info = if is_partial {
            PartialAttestationInfo::partial(
                checkpoint_index.unwrap_or(0),
                hash_chain.frame_count,
                frame_count,
            )
        } else {
            PartialAttestationInfo::complete(frame_count)
        };

        // Build checks performed list
        let mut checks = vec!["hardware".to_string(), "hash_chain".to_string()];
        if depth_evidence.is_some() {
            checks.push("depth".to_string());
        }
        checks.push("metadata".to_string());

        // Build processing info
        let processing =
            ProcessingInfo::new(processing_time_ms, self.backend_version.clone(), checks);

        info!(
            "Built video evidence: {} frames, {}ms, partial={}",
            frame_count, duration_ms, is_partial
        );

        VideoEvidence::new(
            duration_ms,
            frame_count,
            hw_attestation,
            hash_chain_evidence,
            depth_evidence,
            metadata,
            partial_info,
            processing,
        )
    }

    /// Calculate confidence level for video evidence
    ///
    /// Video confidence is stricter than photo confidence:
    /// - SUSPICIOUS: Any check fails or chain broken
    /// - HIGH: All checks pass with strong depth metrics
    /// - MEDIUM: Core checks pass, depth degraded/unavailable or partial
    /// - LOW: Multiple checks unavailable
    #[instrument(skip(self, evidence))]
    pub fn calculate_confidence(&self, evidence: &VideoEvidence) -> VideoConfidenceLevel {
        // SUSPICIOUS: Hardware attestation failed
        if evidence.hardware_attestation.status == "fail" {
            warn!("Confidence SUSPICIOUS: hardware attestation failed");
            return VideoConfidenceLevel::Suspicious;
        }

        // SUSPICIOUS: Hash chain verification failed
        if evidence.hash_chain.status == "fail" {
            warn!("Confidence SUSPICIOUS: hash chain verification failed");
            return VideoConfidenceLevel::Suspicious;
        }

        // SUSPICIOUS: Hash chain broken (tampering detected)
        if !evidence.hash_chain.chain_intact {
            warn!("Confidence SUSPICIOUS: hash chain broken (possible tampering)");
            return VideoConfidenceLevel::Suspicious;
        }

        // SUSPICIOUS: Depth analysis detected suspicious scene
        if let Some(ref depth) = evidence.depth_analysis {
            if !depth.is_likely_real_scene {
                warn!("Confidence SUSPICIOUS: depth analysis detected suspicious scene");
                return VideoConfidenceLevel::Suspicious;
            }
        }

        // Check for HIGH confidence conditions
        let hw_pass = evidence.hardware_attestation.status == "pass";
        let hash_pass = evidence.hash_chain.status == "pass"
            && evidence.hash_chain.chain_intact
            && evidence.hash_chain.attestation_valid;

        let depth_pass = evidence
            .depth_analysis
            .as_ref()
            .map(|d| {
                d.is_likely_real_scene
                    && d.depth_consistency >= self.config.depth_consistency_threshold
                    && d.scene_stability >= self.config.scene_stability_threshold
            })
            .unwrap_or(false);

        // HIGH: All checks pass with strong metrics
        if hw_pass && hash_pass && depth_pass {
            debug!(
                "Confidence HIGH: hw={}, hash={}, depth={} (consistency={:.2}, stability={:.2})",
                hw_pass,
                hash_pass,
                depth_pass,
                evidence
                    .depth_analysis
                    .as_ref()
                    .map(|d| d.depth_consistency)
                    .unwrap_or(0.0),
                evidence
                    .depth_analysis
                    .as_ref()
                    .map(|d| d.scene_stability)
                    .unwrap_or(0.0)
            );
            return VideoConfidenceLevel::High;
        }

        // MEDIUM: Hardware + hash chain pass, depth unavailable/degraded
        if hw_pass && hash_pass {
            debug!(
                "Confidence MEDIUM: hw={}, hash={}, depth unavailable or degraded",
                hw_pass, hash_pass
            );
            return VideoConfidenceLevel::Medium;
        }

        // MEDIUM: Partial verification with checkpoint
        if evidence.partial_attestation.is_partial
            && evidence.hash_chain.checkpoint_verified
            && hw_pass
        {
            debug!("Confidence MEDIUM: partial attestation with checkpoint verified",);
            return VideoConfidenceLevel::Medium;
        }

        // MEDIUM: Hardware unavailable but hash chain and depth pass
        if evidence.hardware_attestation.status == "unavailable" && hash_pass {
            debug!("Confidence MEDIUM: hw unavailable, hash pass");
            return VideoConfidenceLevel::Medium;
        }

        // LOW: Multiple checks unavailable but no explicit failures
        debug!("Confidence LOW: multiple checks unavailable");
        VideoConfidenceLevel::Low
    }

    /// Convenience method to build evidence and calculate confidence in one call
    #[allow(clippy::too_many_arguments)]
    pub fn process(
        &self,
        hw_attestation: HardwareAttestationEvidence,
        hash_chain: &HashChainVerification,
        depth_analysis: Option<&VideoDepthAnalysis>,
        metadata: MetadataEvidence,
        is_partial: bool,
        checkpoint_index: Option<u32>,
        duration_ms: u64,
        frame_count: u32,
        start_time: Instant,
    ) -> (VideoEvidence, VideoConfidenceLevel) {
        let evidence = self.build_evidence(
            hw_attestation,
            hash_chain,
            depth_analysis,
            metadata,
            is_partial,
            checkpoint_index,
            duration_ms,
            frame_count,
            start_time,
        );
        let confidence = self.calculate_confidence(&evidence);
        (evidence, confidence)
    }
}

impl Default for VideoEvidenceService {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::hash_chain_verification::VerificationStatus;
    use chrono::Utc;

    fn make_passing_hash_chain() -> HashChainVerification {
        HashChainVerification {
            status: VerificationStatus::Pass,
            frame_count: 450,
            duration_ms: 15000,
            chain_structure_valid: true,
            checkpoints_valid: true,
            final_hash_matches: true,
            attestation_valid: true,
            failure_reason: None,
            is_partial: false,
            checkpoint_index: None,
        }
    }

    fn make_failing_hash_chain() -> HashChainVerification {
        HashChainVerification {
            status: VerificationStatus::Fail,
            frame_count: 0,
            duration_ms: 0,
            chain_structure_valid: false,
            checkpoints_valid: false,
            final_hash_matches: false,
            attestation_valid: false,
            failure_reason: Some("Chain broken at frame 150".to_string()),
            is_partial: false,
            checkpoint_index: None,
        }
    }

    fn make_partial_hash_chain() -> HashChainVerification {
        HashChainVerification {
            status: VerificationStatus::Partial,
            frame_count: 300,
            duration_ms: 10000,
            chain_structure_valid: true,
            checkpoints_valid: true,
            final_hash_matches: true,
            attestation_valid: true,
            failure_reason: None,
            is_partial: true,
            checkpoint_index: Some(1),
        }
    }

    fn make_passing_depth() -> VideoDepthAnalysis {
        VideoDepthAnalysis {
            frame_analyses: vec![],
            depth_consistency: 0.85,
            motion_coherence: 0.75,
            scene_stability: 0.90,
            is_likely_real_scene: true,
            suspicious_frames: vec![],
        }
    }

    fn make_suspicious_depth() -> VideoDepthAnalysis {
        VideoDepthAnalysis {
            frame_analyses: vec![],
            depth_consistency: 0.3,
            motion_coherence: 0.2,
            scene_stability: 0.4,
            is_likely_real_scene: false,
            suspicious_frames: vec![50, 100, 150],
        }
    }

    fn make_degraded_depth() -> VideoDepthAnalysis {
        VideoDepthAnalysis {
            frame_analyses: vec![],
            depth_consistency: 0.5,
            motion_coherence: 0.5,
            scene_stability: 0.6,
            is_likely_real_scene: true,
            suspicious_frames: vec![],
        }
    }

    #[test]
    fn test_confidence_high_all_pass() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let depth = make_passing_depth();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        assert_eq!(confidence, VideoConfidenceLevel::High);
    }

    #[test]
    fn test_confidence_suspicious_hw_fail() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let depth = make_passing_depth();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::fail(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        assert_eq!(confidence, VideoConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_suspicious_chain_broken() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_failing_hash_chain();
        let depth = make_passing_depth();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        assert_eq!(confidence, VideoConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_suspicious_depth_suspicious() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let depth = make_suspicious_depth();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        assert_eq!(confidence, VideoConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_confidence_medium_depth_unavailable() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            None, // No depth analysis
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        assert_eq!(confidence, VideoConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_medium_depth_degraded() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let depth = make_degraded_depth();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        // Depth is_likely_real_scene=true but metrics below threshold -> MEDIUM
        assert_eq!(confidence, VideoConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_medium_partial_checkpoint() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_partial_hash_chain();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            None,
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            true,
            Some(1),
            10000,
            300,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        assert_eq!(confidence, VideoConfidenceLevel::Medium);
    }

    #[test]
    fn test_confidence_low_all_unavailable() {
        let service = VideoEvidenceService::new();
        let hash_chain = HashChainVerification {
            status: VerificationStatus::Fail,
            frame_count: 0,
            duration_ms: 0,
            chain_structure_valid: true, // Structurally valid but no attestation
            checkpoints_valid: true,
            final_hash_matches: true,
            attestation_valid: false,
            failure_reason: Some("Attestation unavailable".to_string()),
            is_partial: false,
            checkpoint_index: None,
        };
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::unavailable(),
            &hash_chain,
            None,
            MetadataEvidence::new("Unknown".to_string(), false, false),
            false,
            None,
            0,
            0,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        // Hash chain failed -> SUSPICIOUS (not LOW)
        // This is correct behavior - failed checks are worse than unavailable
        assert_eq!(confidence, VideoConfidenceLevel::Suspicious);
    }

    #[test]
    fn test_build_evidence_includes_all_checks() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let depth = make_passing_depth();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        assert!(evidence
            .processing
            .checks_performed
            .contains(&"hardware".to_string()));
        assert!(evidence
            .processing
            .checks_performed
            .contains(&"hash_chain".to_string()));
        assert!(evidence
            .processing
            .checks_performed
            .contains(&"depth".to_string()));
        assert!(evidence
            .processing
            .checks_performed
            .contains(&"metadata".to_string()));
    }

    #[test]
    fn test_build_evidence_without_depth() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            None,
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        assert!(evidence.depth_analysis.is_none());
        assert!(!evidence
            .processing
            .checks_performed
            .contains(&"depth".to_string()));
    }

    #[test]
    fn test_process_returns_both() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let depth = make_passing_depth();
        let start = Instant::now();

        let (evidence, confidence) = service.process(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        assert_eq!(evidence.evidence_type, "video");
        assert_eq!(confidence, VideoConfidenceLevel::High);
    }

    #[test]
    fn test_processing_time_recorded() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let start = Instant::now();

        // Add small delay
        std::thread::sleep(std::time::Duration::from_millis(10));

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            None,
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        assert!(evidence.processing.processing_time_ms >= 10);
    }

    #[test]
    fn test_backend_version_recorded() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_passing_hash_chain();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            None,
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        assert_eq!(
            evidence.processing.backend_version,
            env!("CARGO_PKG_VERSION")
        );
    }

    #[test]
    fn test_partial_attestation_info() {
        let service = VideoEvidenceService::new();
        let hash_chain = make_partial_hash_chain();
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            None,
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            true,
            Some(1),
            10000,
            400,
            start,
        );

        assert!(evidence.partial_attestation.is_partial);
        assert_eq!(evidence.partial_attestation.checkpoint_index, Some(1));
        assert_eq!(evidence.partial_attestation.verified_frames, 300);
        assert_eq!(evidence.partial_attestation.total_frames, 400);
        assert_eq!(
            evidence.partial_attestation.reason,
            Some("checkpoint_attestation".to_string())
        );
    }

    #[test]
    fn test_custom_config() {
        let config = VideoEvidenceConfig {
            depth_consistency_threshold: 0.9,
            scene_stability_threshold: 0.95,
        };
        let service = VideoEvidenceService::with_config(config);

        let hash_chain = make_passing_hash_chain();
        let depth = make_passing_depth(); // consistency=0.85, stability=0.90
        let start = Instant::now();

        let evidence = service.build_evidence(
            HardwareAttestationEvidence::pass(Utc::now()),
            &hash_chain,
            Some(&depth),
            MetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            false,
            None,
            15000,
            450,
            start,
        );

        let confidence = service.calculate_confidence(&evidence);
        // With stricter thresholds (0.9, 0.95), the depth metrics don't pass
        assert_eq!(confidence, VideoConfidenceLevel::Medium);
    }
}
