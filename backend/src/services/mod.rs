//! Service modules for RealityCam backend
//!
//! This module contains business logic services that are used by route handlers.

pub mod attestation;
pub mod capture_attestation;
pub mod challenge_store;
pub mod storage;

pub use attestation::{
    decode_attestation_object, extract_public_key, parse_authenticator_data, verify_attestation,
    verify_certificate_chain, AttestationError, AttestationObject, AuthenticatorData,
    VerificationResult,
};
pub use capture_attestation::{verify_capture_assertion, CaptureAssertionError, CaptureAssertionResult};
pub use challenge_store::{ChallengeEntry, ChallengeError, ChallengeStore};
pub use storage::{depth_map_s3_key, photo_s3_key, StorageService};
