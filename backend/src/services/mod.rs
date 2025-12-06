//! Service modules for RealityCam backend
//!
//! This module contains business logic services that are used by route handlers.

pub mod attestation;
pub mod c2pa;
pub mod capture_attestation;
pub mod challenge_store;
pub mod debug_logs;
pub mod depth_analysis;
pub mod hash_chain_verifier;
pub mod metadata_validation;
pub mod privacy;
pub mod storage;
pub mod video_depth_analysis;
pub mod video_evidence;

pub use attestation::{
    decode_attestation_object, extract_public_key, parse_authenticator_data, verify_attestation,
    verify_certificate_chain, AttestationError, AttestationObject, AuthenticatorData,
    VerificationResult,
};
pub use c2pa::{
    c2pa_manifest_s3_key, c2pa_photo_s3_key, c2pa_video_manifest_s3_key, C2paError, C2paManifest,
    C2paManifestInfo, C2paService, C2paVideoManifest, HashChainSummaryData, PartialAttestationData,
    RealityCamVideoAssertion, TemporalDepthSummaryData,
};
pub use capture_attestation::{
    compute_hash_only_client_data_hash, verify_capture_assertion, verify_hash_only_assertion,
    CaptureAssertionError, CaptureAssertionResult,
};
pub use challenge_store::{ChallengeEntry, ChallengeError, ChallengeStore};
pub use depth_analysis::{analyze_depth_map, analyze_depth_map_from_bytes};
pub use hash_chain_verifier::HashChainVerifier;
pub use metadata_validation::validate_metadata;
pub use privacy::process_location_for_evidence;
pub use storage::{depth_map_s3_key, photo_s3_key, StorageService};
pub use video_depth_analysis::VideoDepthAnalysisService;
pub use video_evidence::{VideoEvidenceConfig, VideoEvidenceService};
