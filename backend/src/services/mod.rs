//! Service modules for RealityCam backend
//!
//! This module contains business logic services that are used by route handlers.

pub mod attestation;
pub mod challenge_store;

pub use attestation::{
    decode_attestation_object, extract_public_key, parse_authenticator_data, verify_attestation,
    verify_certificate_chain, AttestationError, AttestationObject, AuthenticatorData,
    VerificationResult,
};
pub use challenge_store::{ChallengeEntry, ChallengeError, ChallengeStore};
