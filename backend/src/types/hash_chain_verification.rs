//! Hash Chain Verification Types (Story 7-10)
//!
//! Types for verifying video frame hash chain integrity.
//! The backend validates the STRUCTURE and ATTESTATION of the hash chain
//! submitted by iOS, but does NOT recompute hashes from video frames
//! (video compression makes exact recomputation impossible).
//!
//! Security model:
//! - iOS computes hashes from raw camera frames BEFORE encoding
//! - iOS gets the final hash ATTESTED by Apple's DCAppAttest
//! - Backend verifies attestation is valid for the submitted hash
//! - Trust established through attestation, not recomputation

use serde::{Deserialize, Serialize};
use thiserror::Error;

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for hash chain verifier
#[derive(Debug, Clone)]
pub struct HashChainVerifierConfig {
    /// Maximum frames to accept (safety limit)
    pub max_frames: usize,
    /// Expected frame rate (for consistency checks)
    pub expected_fps: u32,
    /// Maximum video duration in seconds
    pub max_duration_secs: u32,
    /// Checkpoint interval in frames (should match iOS: 150 = 5s at 30fps)
    pub checkpoint_interval: u32,
}

impl Default for HashChainVerifierConfig {
    fn default() -> Self {
        Self {
            max_frames: 450, // 15s at 30fps
            expected_fps: 30,
            max_duration_secs: 15,
            checkpoint_interval: 150, // 5 seconds at 30fps
        }
    }
}

// ============================================================================
// Data Structures - Input from iOS
// ============================================================================

/// Hash chain data submitted by iOS app with video upload.
///
/// Contains all frame hashes, checkpoint hashes, and the final hash
/// that was attested. The backend validates structure and attestation
/// but does not recompute hashes (video compression makes this impossible).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashChainData {
    /// All frame hashes at 30fps (up to 450 for 15-second video)
    /// Each hash is base64-encoded SHA256 (32 bytes -> 44 chars)
    pub frame_hashes: Vec<String>,

    /// Checkpoint hashes every 5 seconds (frames 150, 300, 450)
    pub checkpoints: Vec<HashCheckpoint>,

    /// Final hash (last frame hash) for attestation verification
    /// Base64-encoded SHA256
    pub final_hash: String,
}

impl HashChainData {
    /// Number of frames in the chain
    pub fn frame_count(&self) -> usize {
        self.frame_hashes.len()
    }

    /// Estimated video duration in seconds
    pub fn estimated_duration_secs(&self, fps: u32) -> f64 {
        self.frame_hashes.len() as f64 / fps as f64
    }
}

/// Checkpoint hash at 5-second intervals.
///
/// Checkpoints enable partial verification for interrupted recordings
/// and efficient attestation at known boundaries.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashCheckpoint {
    /// Checkpoint index (0=5s, 1=10s, 2=15s)
    pub index: u32,

    /// Frame number at checkpoint (150, 300, 450)
    pub frame_number: u32,

    /// Hash at this checkpoint (base64-encoded SHA256)
    pub hash: String,

    /// Timestamp at checkpoint (seconds)
    pub timestamp: f64,
}

/// Video attestation from iOS app.
///
/// Contains the DCAppAttest assertion for the final (or checkpoint) hash,
/// proving the hash chain was created on a genuine iOS device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoAttestation {
    /// Hash that was attested (base64-encoded SHA256)
    pub final_hash: String,

    /// DCAppAttest assertion signature (base64-encoded)
    pub assertion: String,

    /// Attested duration in milliseconds
    pub duration_ms: u64,

    /// Attested frame count
    pub frame_count: u32,

    /// True if recording was interrupted (partial attestation)
    pub is_partial: bool,

    /// Checkpoint index if partial (0, 1, or 2)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkpoint_index: Option<u32>,
}

// ============================================================================
// Data Structures - Verification Results
// ============================================================================

/// Complete hash chain verification results.
///
/// The verification checks:
/// 1. Chain structure is valid (correct number of hashes, proper format)
/// 2. Checkpoints are at correct positions with matching hashes
/// 3. Final hash matches the last frame hash
/// 4. Attestation hash matches submitted final hash
/// 5. Frame count and duration are consistent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashChainVerification {
    /// Overall verification status
    pub status: VerificationStatus,

    /// Number of frames in the chain
    pub frame_count: u32,

    /// Estimated video duration in milliseconds
    pub duration_ms: u32,

    /// Chain structure is valid (hashes properly formatted)
    pub chain_structure_valid: bool,

    /// Checkpoints are at correct positions with matching hashes
    pub checkpoints_valid: bool,

    /// Final hash matches last frame hash
    pub final_hash_matches: bool,

    /// Attestation hash matches submitted hash chain
    pub attestation_valid: bool,

    /// Detailed reason if verification failed
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure_reason: Option<String>,

    /// True if this is a partial (interrupted) recording
    pub is_partial: bool,

    /// Verified checkpoint index (if partial)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkpoint_index: Option<u32>,
}

impl Default for HashChainVerification {
    fn default() -> Self {
        Self {
            status: VerificationStatus::Fail,
            frame_count: 0,
            duration_ms: 0,
            chain_structure_valid: false,
            checkpoints_valid: false,
            final_hash_matches: false,
            attestation_valid: false,
            failure_reason: None,
            is_partial: false,
            checkpoint_index: None,
        }
    }
}

impl HashChainVerification {
    /// Create a successful verification result
    pub fn success(frame_count: u32, duration_ms: u32) -> Self {
        Self {
            status: VerificationStatus::Pass,
            frame_count,
            duration_ms,
            chain_structure_valid: true,
            checkpoints_valid: true,
            final_hash_matches: true,
            attestation_valid: true,
            failure_reason: None,
            is_partial: false,
            checkpoint_index: None,
        }
    }

    /// Create a partial verification result (for interrupted recordings)
    pub fn partial(frame_count: u32, duration_ms: u32, checkpoint_index: u32) -> Self {
        Self {
            status: VerificationStatus::Partial,
            frame_count,
            duration_ms,
            chain_structure_valid: true,
            checkpoints_valid: true,
            final_hash_matches: true,
            attestation_valid: true,
            failure_reason: None,
            is_partial: true,
            checkpoint_index: Some(checkpoint_index),
        }
    }

    /// Create a failed verification result
    pub fn fail(reason: impl Into<String>) -> Self {
        Self {
            status: VerificationStatus::Fail,
            failure_reason: Some(reason.into()),
            ..Default::default()
        }
    }

    /// Check if verification passed (full or partial)
    pub fn is_valid(&self) -> bool {
        matches!(
            self.status,
            VerificationStatus::Pass | VerificationStatus::Partial
        )
    }
}

/// Verification status enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VerificationStatus {
    /// All checks passed, full video verified
    Pass,
    /// Partial verification (checkpoint verified, remaining unverified)
    Partial,
    /// Verification failed (structure invalid or attestation mismatch)
    Fail,
}

// ============================================================================
// Error Types
// ============================================================================

/// Errors that can occur during hash chain verification
#[derive(Debug, Error)]
pub enum HashChainVerificationError {
    #[error("Empty hash chain: no frame hashes provided")]
    EmptyChain,

    #[error("Hash chain too long: {count} frames exceeds maximum {max}")]
    ChainTooLong { count: usize, max: usize },

    #[error("Invalid hash format at index {index}: {reason}")]
    InvalidHashFormat { index: usize, reason: String },

    #[error("Invalid base64 encoding: {0}")]
    Base64DecodeError(String),

    #[error("Hash length mismatch at index {index}: expected 32 bytes, got {actual}")]
    HashLengthMismatch { index: usize, actual: usize },

    #[error("Checkpoint mismatch at index {index}: hash doesn't match frame hash")]
    CheckpointMismatch { index: u32 },

    #[error("Checkpoint at wrong position: index {index} should be at frame {expected}, found at {actual}")]
    CheckpointWrongPosition {
        index: u32,
        expected: u32,
        actual: u32,
    },

    #[error("Final hash mismatch: submitted final hash doesn't match last frame hash")]
    FinalHashMismatch,

    #[error("Attestation hash mismatch: attested hash doesn't match submitted hash chain")]
    AttestationHashMismatch,

    #[error("Frame count mismatch: attestation claims {attested} frames, chain has {actual}")]
    FrameCountMismatch { attested: u32, actual: u32 },

    #[error("Missing checkpoint for partial attestation: expected checkpoint {index}")]
    MissingCheckpoint { index: u32 },
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = HashChainVerifierConfig::default();
        assert_eq!(config.max_frames, 450);
        assert_eq!(config.expected_fps, 30);
        assert_eq!(config.max_duration_secs, 15);
        assert_eq!(config.checkpoint_interval, 150);
    }

    #[test]
    fn test_hash_chain_data_frame_count() {
        let chain = HashChainData {
            frame_hashes: vec!["hash1".to_string(), "hash2".to_string()],
            checkpoints: vec![],
            final_hash: "hash2".to_string(),
        };
        assert_eq!(chain.frame_count(), 2);
    }

    #[test]
    fn test_hash_chain_data_estimated_duration() {
        let chain = HashChainData {
            frame_hashes: vec!["h".to_string(); 150],
            checkpoints: vec![],
            final_hash: "final".to_string(),
        };
        assert!((chain.estimated_duration_secs(30) - 5.0).abs() < 0.01);
    }

    #[test]
    fn test_verification_success() {
        let result = HashChainVerification::success(450, 15000);
        assert_eq!(result.status, VerificationStatus::Pass);
        assert!(result.is_valid());
        assert!(!result.is_partial);
    }

    #[test]
    fn test_verification_partial() {
        let result = HashChainVerification::partial(300, 10000, 1);
        assert_eq!(result.status, VerificationStatus::Partial);
        assert!(result.is_valid());
        assert!(result.is_partial);
        assert_eq!(result.checkpoint_index, Some(1));
    }

    #[test]
    fn test_verification_fail() {
        let result = HashChainVerification::fail("test failure");
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(!result.is_valid());
        assert_eq!(result.failure_reason, Some("test failure".to_string()));
    }

    #[test]
    fn test_verification_status_serialization() {
        let pass = VerificationStatus::Pass;
        let json = serde_json::to_string(&pass).unwrap();
        assert_eq!(json, "\"pass\"");

        let fail = VerificationStatus::Fail;
        let json = serde_json::to_string(&fail).unwrap();
        assert_eq!(json, "\"fail\"");
    }

    #[test]
    fn test_verification_result_serialization() {
        let result = HashChainVerification::success(450, 15000);
        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("\"status\":\"pass\""));
        assert!(json.contains("\"frame_count\":450"));

        // Verify None fields are skipped
        assert!(!json.contains("failure_reason"));
        assert!(!json.contains("checkpoint_index"));
    }

    #[test]
    fn test_hash_chain_data_serialization() {
        let chain = HashChainData {
            frame_hashes: vec!["YWJj".to_string()],
            checkpoints: vec![HashCheckpoint {
                index: 0,
                frame_number: 150,
                hash: "ZGVm".to_string(),
                timestamp: 5.0,
            }],
            final_hash: "YWJj".to_string(),
        };

        let json = serde_json::to_string(&chain).unwrap();
        assert!(json.contains("\"frame_hashes\""));
        assert!(json.contains("\"checkpoints\""));
        assert!(json.contains("\"final_hash\""));
    }

    #[test]
    fn test_video_attestation_serialization() {
        let attestation = VideoAttestation {
            final_hash: "YWJj".to_string(),
            assertion: "c2lnbmF0dXJl".to_string(),
            duration_ms: 15000,
            frame_count: 450,
            is_partial: false,
            checkpoint_index: None,
        };

        let json = serde_json::to_string(&attestation).unwrap();
        assert!(json.contains("\"final_hash\""));
        assert!(json.contains("\"assertion\""));
        assert!(!json.contains("checkpoint_index")); // None should be skipped
    }

    #[test]
    fn test_error_display() {
        let error = HashChainVerificationError::EmptyChain;
        assert!(error.to_string().contains("Empty hash chain"));

        let error = HashChainVerificationError::ChainTooLong {
            count: 500,
            max: 450,
        };
        assert!(error.to_string().contains("500 frames"));
        assert!(error.to_string().contains("450"));

        let error = HashChainVerificationError::CheckpointMismatch { index: 1 };
        assert!(error.to_string().contains("index 1"));
    }
}
