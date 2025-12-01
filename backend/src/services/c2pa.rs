//! C2PA Manifest Service (Stories 5-1, 5-2, 5-3, 7-12)
//!
//! Provides C2PA manifest generation and storage for RealityCam captures.
//! Implements FR27-FR30 (photos) and FR54 (videos) from the PRD.
//!
//! ## Features
//! - Generate C2PA-compatible manifest data with RealityCam evidence assertions
//! - Store manifest alongside captured photos
//! - Generate video manifests with hash chain and temporal depth assertions (Story 7-12)
//!
//! ## MVP Note
//! Full C2PA signing and embedding requires proper X.509 certificate chain setup.
//! For MVP, we generate and store the manifest data as JSON. The manifest
//! structure follows C2PA specification and can be upgraded to full C2PA
//! embedding when certificates are properly configured.
//!
//! ## Video Manifests (Story 7-12)
//! Video manifests are stored as separate JSON files (not embedded in MP4).
//! This approach avoids c2pa-rs MP4 complexity for MVP. Videos use
//! "c2pa.recorded" action type (vs "c2pa.created" for photos).

use serde::{Deserialize, Serialize};
use thiserror::Error;
use tracing::info;
use uuid::Uuid;

use crate::models::{CheckStatus, ConfidenceLevel, EvidencePackage};
use crate::services::video_evidence::VideoEvidenceService;
use crate::types::video_evidence::{VideoConfidenceLevel, VideoEvidence};

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

    /// Source of analysis: "server" or "device" (for hash-only captures)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
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
    pub fn generate_manifest(&self, evidence: &EvidencePackage, captured_at: &str) -> C2paManifest {
        let assertion = self.build_assertion(evidence, captured_at);

        let version = env!("CARGO_PKG_VERSION");
        let claim_generator = format!("{CLAIM_GENERATOR}/{version}");
        let software_agent = format!("{SOFTWARE_AGENT}/{version}");

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

        serde_json::to_string_pretty(&manifest).map_err(|e| C2paError::Serialization(e.to_string()))
    }

    /// Generates a C2PA manifest for hash-only (privacy mode) captures (Story 8-5)
    ///
    /// Hash-only captures use device-computed depth analysis and include
    /// "Privacy Mode" in the title. The manifest is stored as JSON only
    /// (not embedded in media, since no media is uploaded).
    ///
    /// # Arguments
    /// * `evidence` - Evidence package with source=Device depth analysis
    /// * `captured_at` - Capture timestamp (ISO 8601)
    ///
    /// # Returns
    /// C2PA manifest with privacy mode title
    pub fn generate_hash_only_manifest(
        &self,
        evidence: &EvidencePackage,
        captured_at: &str,
    ) -> C2paManifest {
        let mut manifest = self.generate_manifest(evidence, captured_at);
        manifest.title = "RealityCam Verified Photo (Privacy Mode)".to_string();
        // depth_analysis assertion already includes source from evidence.depth_analysis.source
        manifest
    }

    /// Generates a hash-only C2PA manifest as JSON string (Story 8-5)
    pub fn generate_hash_only_manifest_json(
        &self,
        evidence: &EvidencePackage,
        captured_at: &str,
    ) -> Result<String, C2paError> {
        let manifest = self.generate_hash_only_manifest(evidence, captured_at);
        serde_json::to_string_pretty(&manifest).map_err(|e| C2paError::Serialization(e.to_string()))
    }

    /// Builds the RealityCam assertion from evidence
    fn build_assertion(
        &self,
        evidence: &EvidencePackage,
        captured_at: &str,
    ) -> RealityCamAssertion {
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
                source: evidence.depth_analysis.source.map(|s| s.to_string()),
            },
            device_model: evidence.hardware_attestation.device_model.clone(),
            captured_at: captured_at.to_string(),
        }
    }

    // ========================================================================
    // Video Manifest Generation (Story 7-12)
    // ========================================================================

    /// Generates a C2PA manifest from a video evidence package (Story 7-12)
    ///
    /// # Arguments
    /// * `evidence` - Video evidence package from capture processing
    /// * `captured_at` - Capture timestamp (ISO 8601)
    ///
    /// # Returns
    /// C2PA manifest structure with video-specific assertions
    ///
    /// # Example
    /// ```ignore
    /// let service = C2paService::new();
    /// let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");
    /// ```
    pub fn generate_video_manifest(
        &self,
        evidence: &VideoEvidence,
        captured_at: &str,
    ) -> C2paVideoManifest {
        let assertion = self.build_video_assertion(evidence, captured_at);

        let version = env!("CARGO_PKG_VERSION");
        let claim_generator = format!("{CLAIM_GENERATOR}/{version}");
        let software_agent = format!("{SOFTWARE_AGENT}/{version}");

        info!(
            "Generated video C2PA manifest: {} frames, {}ms, confidence={}",
            evidence.frame_count, evidence.duration_ms, assertion.confidence_level
        );

        C2paVideoManifest {
            claim_generator,
            title: "RealityCam Verified Video".to_string(),
            created_at: captured_at.to_string(),
            actions: vec![C2paAction {
                action: "c2pa.recorded".to_string(), // Note: "recorded" for videos
                when: captured_at.to_string(),
                software_agent,
            }],
            realitycam: assertion,
        }
    }

    /// Generates a C2PA video manifest as JSON string (Story 7-12)
    ///
    /// # Arguments
    /// * `evidence` - Video evidence package from capture processing
    /// * `captured_at` - Capture timestamp (ISO 8601)
    ///
    /// # Returns
    /// Pretty-printed JSON string of the manifest
    pub fn generate_video_manifest_json(
        &self,
        evidence: &VideoEvidence,
        captured_at: &str,
    ) -> Result<String, C2paError> {
        let manifest = self.generate_video_manifest(evidence, captured_at);
        serde_json::to_string_pretty(&manifest).map_err(|e| C2paError::Serialization(e.to_string()))
    }

    /// Builds the RealityCam video assertion from evidence (Story 7-12)
    fn build_video_assertion(
        &self,
        evidence: &VideoEvidence,
        captured_at: &str,
    ) -> RealityCamVideoAssertion {
        // Calculate confidence using VideoEvidenceService
        let evidence_service = VideoEvidenceService::new();
        let confidence = evidence_service.calculate_confidence(evidence);
        let confidence_level = self.map_video_confidence_level(confidence);

        // Map hardware attestation (reuse existing HardwareAssertionData)
        let hardware_attestation = HardwareAssertionData {
            status: evidence.hardware_attestation.status.clone(),
            level: "secure_enclave".to_string(),
            verified: evidence.hardware_attestation.assertion_valid,
        };

        // Map hash chain verification to summary
        let hash_chain_summary = HashChainSummaryData {
            status: evidence.hash_chain.status.clone(),
            chain_intact: evidence.hash_chain.chain_intact,
            attestation_valid: evidence.hash_chain.attestation_valid,
            verified_frames: evidence.hash_chain.verified_frames,
            total_frames: evidence.hash_chain.total_frames,
            broken_at_frame: None, // Hash chain evidence doesn't expose broken_at_frame
        };

        // Map temporal depth analysis (optional)
        let temporal_depth_summary = evidence.depth_analysis.as_ref().map(|depth| {
            let status = if depth.is_likely_real_scene {
                "pass"
            } else {
                "fail"
            };

            TemporalDepthSummaryData {
                status: status.to_string(),
                is_likely_real_scene: depth.is_likely_real_scene,
                depth_consistency: depth.depth_consistency,
                motion_coherence: depth.motion_coherence,
                scene_stability: depth.scene_stability,
            }
        });

        // Map partial attestation
        let partial_attestation = PartialAttestationData {
            is_partial: evidence.partial_attestation.is_partial,
            checkpoint_index: evidence.partial_attestation.checkpoint_index,
            verified_frames: evidence.partial_attestation.verified_frames,
            total_frames: evidence.partial_attestation.total_frames,
            reason: evidence.partial_attestation.reason.clone(),
        };

        RealityCamVideoAssertion {
            confidence_level,
            media_type: "video".to_string(),
            duration_ms: evidence.duration_ms,
            frame_count: evidence.frame_count,
            verified_frames: evidence.hash_chain.verified_frames,
            hardware_attestation,
            hash_chain_summary,
            temporal_depth_summary,
            partial_attestation,
            device_model: evidence.metadata.device_model.clone(),
            captured_at: captured_at.to_string(),
        }
    }

    /// Map VideoConfidenceLevel to string (Story 7-12)
    fn map_video_confidence_level(&self, confidence: VideoConfidenceLevel) -> String {
        match confidence {
            VideoConfidenceLevel::High => "high",
            VideoConfidenceLevel::Medium => "medium",
            VideoConfidenceLevel::Low => "low",
            VideoConfidenceLevel::Suspicious => "suspicious",
        }
        .to_string()
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
// Video C2PA Types (Story 7-12)
// ============================================================================

/// C2PA manifest structure for video (Story 7-12)
///
/// Videos use "c2pa.recorded" action (vs "c2pa.created" for photos)
/// and include video-specific assertions like hash chain and temporal depth.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct C2paVideoManifest {
    /// Claim generator (e.g., "RealityCam/0.1.0")
    pub claim_generator: String,

    /// Title of the asset
    pub title: String,

    /// Creation timestamp (ISO 8601)
    pub created_at: String,

    /// Actions performed on the asset
    pub actions: Vec<C2paAction>,

    /// RealityCam-specific video assertions
    pub realitycam: RealityCamVideoAssertion,
}

/// RealityCam video assertion for C2PA manifest (Story 7-12)
///
/// Extends photo assertions with video-specific fields:
/// - Hash chain verification summary
/// - Temporal depth analysis
/// - Partial attestation information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RealityCamVideoAssertion {
    /// Confidence level from evidence analysis
    pub confidence_level: String,

    /// Media type (always "video")
    #[serde(rename = "type")]
    pub media_type: String,

    /// Total video duration in milliseconds
    pub duration_ms: u64,

    /// Total frame count
    pub frame_count: u32,

    /// Frames successfully verified
    pub verified_frames: u32,

    /// Hardware attestation summary
    pub hardware_attestation: HardwareAssertionData,

    /// Hash chain verification summary (video-specific)
    pub hash_chain_summary: HashChainSummaryData,

    /// Temporal depth analysis summary (video-specific, optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temporal_depth_summary: Option<TemporalDepthSummaryData>,

    /// Partial attestation information (video-specific)
    pub partial_attestation: PartialAttestationData,

    /// Device information
    pub device_model: String,

    /// Capture timestamp (ISO 8601)
    pub captured_at: String,
}

/// Hash chain verification summary for C2PA video assertion (Story 7-12)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashChainSummaryData {
    /// Verification status: "pass", "partial", "fail"
    pub status: String,

    /// Whether hash chain is intact (no tampering)
    pub chain_intact: bool,

    /// Whether attestation hash matches computed hash
    pub attestation_valid: bool,

    /// Frames successfully verified
    pub verified_frames: u32,

    /// Total frames in video
    pub total_frames: u32,

    /// Frame number where chain broke (if failed)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub broken_at_frame: Option<u32>,
}

/// Temporal depth analysis summary for C2PA video assertion (Story 7-12)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalDepthSummaryData {
    /// Analysis status: "pass", "fail", "unavailable"
    pub status: String,

    /// Whether scene is likely real (not flat)
    pub is_likely_real_scene: bool,

    /// Depth consistency across frames (0.0-1.0)
    pub depth_consistency: f32,

    /// Motion coherence with depth changes (0.0-1.0)
    pub motion_coherence: f32,

    /// Scene stability (lack of suspicious jumps) (0.0-1.0)
    pub scene_stability: f32,
}

/// Partial attestation information for C2PA video assertion (Story 7-12)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartialAttestationData {
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

/// S3 key pattern for video C2PA manifest (Story 7-12)
///
/// Video manifests are stored as separate JSON files (not embedded in MP4).
/// Future enhancement: Add `c2pa_video_embedded_s3_key()` for embedded manifests.
pub fn c2pa_video_manifest_s3_key(capture_id: Uuid) -> String {
    format!("captures/{capture_id}/video_manifest.json")
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
                source: None,
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

    // ========================================================================
    // Video Manifest Tests (Story 7-12)
    // ========================================================================

    use crate::types::video_evidence::{
        DepthAnalysisEvidence, HardwareAttestationEvidence, HashChainEvidence,
        MetadataEvidence as VideoMetadataEvidence, PartialAttestationInfo,
        ProcessingInfo as VideoProcessingInfo, VideoEvidence,
    };
    use chrono::Utc;

    fn create_test_video_evidence() -> VideoEvidence {
        VideoEvidence::new(
            15000, // 15 seconds
            450,   // 30 fps * 15 seconds
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
            Some(DepthAnalysisEvidence {
                depth_consistency: 0.85,
                motion_coherence: 0.72,
                scene_stability: 0.90,
                is_likely_real_scene: true,
                suspicious_frames: vec![],
            }),
            VideoMetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            PartialAttestationInfo::complete(450),
            VideoProcessingInfo::new(
                1500,
                "0.1.0".to_string(),
                vec![
                    "hardware".to_string(),
                    "hash_chain".to_string(),
                    "depth".to_string(),
                ],
            ),
        )
    }

    fn create_test_video_evidence_partial() -> VideoEvidence {
        VideoEvidence::new(
            10000, // 10 seconds
            300,   // 30 fps * 10 seconds
            HardwareAttestationEvidence::pass(Utc::now()),
            HashChainEvidence {
                status: "partial".to_string(),
                verified_frames: 300,
                total_frames: 450,
                chain_intact: true,
                attestation_valid: true,
                partial_reason: Some("Recording interrupted".to_string()),
                verified_duration_ms: 10000,
                checkpoint_verified: true,
                checkpoint_index: Some(1),
            },
            None, // No depth analysis
            VideoMetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            PartialAttestationInfo::partial(1, 300, 450),
            VideoProcessingInfo::new(
                1200,
                "0.1.0".to_string(),
                vec!["hardware".to_string(), "hash_chain".to_string()],
            ),
        )
    }

    fn create_test_video_evidence_no_depth() -> VideoEvidence {
        VideoEvidence::new(
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
            None, // No depth analysis
            VideoMetadataEvidence::new("iPhone 15 Pro".to_string(), true, true),
            PartialAttestationInfo::complete(450),
            VideoProcessingInfo::new(
                1000,
                "0.1.0".to_string(),
                vec!["hardware".to_string(), "hash_chain".to_string()],
            ),
        )
    }

    #[test]
    fn test_generate_video_manifest() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        assert!(manifest.claim_generator.starts_with("RealityCam/"));
        assert_eq!(manifest.title, "RealityCam Verified Video");
        assert_eq!(manifest.actions.len(), 1);
        assert_eq!(manifest.actions[0].action, "c2pa.recorded");
        assert_eq!(manifest.realitycam.media_type, "video");
        assert_eq!(manifest.realitycam.duration_ms, 15000);
        assert_eq!(manifest.realitycam.frame_count, 450);
        assert_eq!(manifest.realitycam.confidence_level, "high");
    }

    #[test]
    fn test_video_manifest_uses_recorded_action() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        // Video uses "c2pa.recorded" not "c2pa.created"
        assert_eq!(manifest.actions[0].action, "c2pa.recorded");
    }

    #[test]
    fn test_video_manifest_hash_chain_summary() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        let hash_chain = &manifest.realitycam.hash_chain_summary;
        assert_eq!(hash_chain.status, "pass");
        assert!(hash_chain.chain_intact);
        assert!(hash_chain.attestation_valid);
        assert_eq!(hash_chain.verified_frames, 450);
        assert_eq!(hash_chain.total_frames, 450);
    }

    #[test]
    fn test_video_manifest_temporal_depth() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        let depth = manifest.realitycam.temporal_depth_summary.unwrap();
        assert_eq!(depth.status, "pass");
        assert!(depth.is_likely_real_scene);
        assert_eq!(depth.depth_consistency, 0.85);
        assert_eq!(depth.motion_coherence, 0.72);
        assert_eq!(depth.scene_stability, 0.90);
    }

    #[test]
    fn test_video_manifest_partial_attestation() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        let partial = &manifest.realitycam.partial_attestation;
        assert!(!partial.is_partial);
        assert!(partial.checkpoint_index.is_none());
        assert_eq!(partial.verified_frames, 450);
        assert_eq!(partial.total_frames, 450);
    }

    #[test]
    fn test_video_manifest_partial_video() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence_partial();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        // Partial video should have medium confidence
        assert_eq!(manifest.realitycam.confidence_level, "medium");

        let partial = &manifest.realitycam.partial_attestation;
        assert!(partial.is_partial);
        assert_eq!(partial.checkpoint_index, Some(1));
        assert_eq!(partial.verified_frames, 300);
        assert_eq!(partial.total_frames, 450);

        let hash_chain = &manifest.realitycam.hash_chain_summary;
        assert_eq!(hash_chain.status, "partial");
    }

    #[test]
    fn test_video_manifest_no_depth() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence_no_depth();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        // No depth -> medium confidence (hw + hash pass, depth unavailable)
        assert_eq!(manifest.realitycam.confidence_level, "medium");
        assert!(manifest.realitycam.temporal_depth_summary.is_none());
    }

    #[test]
    fn test_generate_video_manifest_json() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let json = service
            .generate_video_manifest_json(&evidence, "2025-11-27T12:00:00Z")
            .unwrap();

        assert!(json.contains("claim_generator"));
        assert!(json.contains("RealityCam"));
        assert!(json.contains("\"type\": \"video\""));
        assert!(json.contains("c2pa.recorded"));
        assert!(json.contains("hash_chain_summary"));
        assert!(json.contains("temporal_depth_summary"));
        assert!(json.contains("partial_attestation"));
        assert!(json.contains("confidence_level"));
    }

    #[test]
    fn test_video_manifest_json_no_depth_skip() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence_no_depth();

        let json = service
            .generate_video_manifest_json(&evidence, "2025-11-27T12:00:00Z")
            .unwrap();

        // temporal_depth_summary should be absent when None (skip_serializing_if)
        assert!(!json.contains("temporal_depth_summary"));
    }

    #[test]
    fn test_c2pa_video_manifest_s3_key() {
        let capture_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();

        let key = c2pa_video_manifest_s3_key(capture_id);

        assert_eq!(
            key,
            "captures/550e8400-e29b-41d4-a716-446655440000/video_manifest.json"
        );
    }

    #[test]
    fn test_video_manifest_device_model() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        assert_eq!(manifest.realitycam.device_model, "iPhone 15 Pro");
    }

    #[test]
    fn test_video_manifest_captured_at() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        assert_eq!(manifest.realitycam.captured_at, "2025-11-27T12:00:00Z");
        assert_eq!(manifest.created_at, "2025-11-27T12:00:00Z");
    }

    #[test]
    fn test_video_manifest_verified_frames() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        assert_eq!(manifest.realitycam.verified_frames, 450);
        assert_eq!(manifest.realitycam.frame_count, 450);
    }

    #[test]
    fn test_video_manifest_hardware_attestation() {
        let service = C2paService::new();
        let evidence = create_test_video_evidence();

        let manifest = service.generate_video_manifest(&evidence, "2025-11-27T12:00:00Z");

        let hw = &manifest.realitycam.hardware_attestation;
        assert_eq!(hw.status, "pass");
        assert_eq!(hw.level, "secure_enclave");
        assert!(hw.verified);
    }

    // ========================================================================
    // Story 8-5: Hash-Only Manifest Tests
    // ========================================================================

    use crate::types::hash_only::AnalysisSource;

    fn create_test_hash_only_evidence() -> EvidencePackage {
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
                source: Some(AnalysisSource::Device), // Hash-only uses device analysis
            },
            metadata: MetadataEvidence::default(),
            processing: ProcessingInfo::new(100, "0.1.0"), // Faster processing for hash-only
        }
    }

    #[test]
    fn test_hash_only_manifest_title() {
        let service = C2paService::new();
        let evidence = create_test_hash_only_evidence();

        let manifest = service.generate_hash_only_manifest(&evidence, "2025-12-01T10:30:00Z");

        assert_eq!(manifest.title, "RealityCam Verified Photo (Privacy Mode)");
    }

    #[test]
    fn test_hash_only_manifest_includes_device_source() {
        let service = C2paService::new();
        let evidence = create_test_hash_only_evidence();

        let manifest = service.generate_hash_only_manifest(&evidence, "2025-12-01T10:30:00Z");

        assert_eq!(
            manifest.realitycam.depth_analysis.source,
            Some("device".to_string())
        );
    }

    #[test]
    fn test_hash_only_manifest_confidence_high() {
        let service = C2paService::new();
        let evidence = create_test_hash_only_evidence();

        let manifest = service.generate_hash_only_manifest(&evidence, "2025-12-01T10:30:00Z");

        assert_eq!(manifest.realitycam.confidence_level, "high");
    }

    #[test]
    fn test_hash_only_manifest_json() {
        let service = C2paService::new();
        let evidence = create_test_hash_only_evidence();

        let json = service
            .generate_hash_only_manifest_json(&evidence, "2025-12-01T10:30:00Z")
            .unwrap();

        assert!(json.contains("\"title\": \"RealityCam Verified Photo (Privacy Mode)\""));
        assert!(json.contains("\"source\": \"device\""));
        assert!(json.contains("\"confidence_level\": \"high\""));
        assert!(json.contains("c2pa.created"));
    }

    #[test]
    fn test_regular_manifest_no_source_when_none() {
        let service = C2paService::new();
        let evidence = create_test_evidence(); // Uses source: None

        let manifest = service.generate_manifest(&evidence, "2025-12-01T10:30:00Z");

        // Regular photo manifest should have no source field
        assert!(manifest.realitycam.depth_analysis.source.is_none());
    }

    #[test]
    fn test_regular_manifest_title() {
        let service = C2paService::new();
        let evidence = create_test_evidence();

        let manifest = service.generate_manifest(&evidence, "2025-12-01T10:30:00Z");

        // Regular manifest should NOT have "Privacy Mode" in title
        assert_eq!(manifest.title, "RealityCam Verified Photo");
    }

    #[test]
    fn test_hash_only_manifest_source_serialization() {
        let service = C2paService::new();
        let evidence = create_test_hash_only_evidence();

        let json = service
            .generate_hash_only_manifest_json(&evidence, "2025-12-01T10:30:00Z")
            .unwrap();

        // Verify source is serialized correctly in depth_analysis
        assert!(json.contains("\"source\": \"device\""));

        // Verify other standard fields are present
        assert!(json.contains("\"is_real_scene\": true"));
        assert!(json.contains("\"depth_layers\": 5"));
    }
}
