//! Hash Chain Verification Service (Story 7-10)
//!
//! Verifies video frame hash chain integrity through STRUCTURAL validation
//! and ATTESTATION verification. Does NOT recompute hashes from video frames
//! because video compression makes exact recomputation impossible.
//!
//! ## Security Model
//!
//! 1. iOS captures raw camera frames and computes SHA256 hash chain
//! 2. iOS gets the final hash ATTESTED by Apple's DCAppAttest
//! 3. iOS encodes video (lossy compression) and uploads with hash chain
//! 4. Backend verifies:
//!    - Chain structure is valid (proper format, correct lengths)
//!    - Checkpoints are at correct positions with matching hashes
//!    - Final hash matches last frame hash
//!    - Attestation hash matches submitted hash chain
//!
//! Trust is established through DCAppAttest attestation, not recomputation.
//! The attestation proves the hash chain was created on a genuine iOS device
//! from real camera frames at capture time.
//!
//! ## What We Verify
//!
//! - **Structure:** All hashes are valid base64-encoded SHA256 (32 bytes)
//! - **Checkpoints:** Located at correct frames (150, 300, 450) with matching hashes
//! - **Consistency:** Final hash matches last frame hash
//! - **Attestation:** Attested hash matches submitted final hash
//! - **Metadata:** Frame count and duration are consistent
//!
//! ## What We Cannot Verify
//!
//! - **Content:** Cannot recompute hashes from video frames (compression)
//! - **Chain derivation:** Cannot verify each hash chains from previous
//!   (would require raw frame data)
//!
//! The chain derivation is trusted through attestation - if Apple DCAppAttest
//! signed this hash, it came from our iOS app processing real camera data.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use tracing::{debug, info, instrument, warn};

use crate::types::hash_chain_verification::{
    HashChainData, HashChainVerification, HashChainVerificationError, HashChainVerifierConfig,
    VideoAttestation,
};

// ============================================================================
// Service
// ============================================================================

/// Service for verifying video hash chain structure and attestation.
///
/// This service validates that the submitted hash chain is properly formed
/// and that the attestation matches the submitted data. It does NOT attempt
/// to recompute hashes from video frames (impossible due to compression).
///
/// ## Usage
///
/// ```ignore
/// let verifier = HashChainVerifier::new();
///
/// // During video capture processing
/// let result = verifier.verify(&hash_chain_data, &attestation);
///
/// if result.is_valid() {
///     // Chain structure is valid and attestation matches
///     // Trust is established through DCAppAttest
/// }
/// ```
pub struct HashChainVerifier {
    config: HashChainVerifierConfig,
}

impl HashChainVerifier {
    /// Create a new verifier with default configuration.
    pub fn new() -> Self {
        Self {
            config: HashChainVerifierConfig::default(),
        }
    }

    /// Create a new verifier with custom configuration.
    pub fn with_config(config: HashChainVerifierConfig) -> Self {
        Self { config }
    }

    /// Verify hash chain structure and attestation.
    ///
    /// This performs structural validation of the hash chain and verifies
    /// that the attestation matches the submitted data. Returns a verification
    /// result that can be included in the evidence package.
    ///
    /// ## Verification Steps
    ///
    /// 1. Validate chain is not empty and within size limits
    /// 2. Validate all hashes are properly formatted (base64 SHA256)
    /// 3. Verify checkpoints are at correct positions with matching hashes
    /// 4. Verify final hash matches last frame hash
    /// 5. Verify attestation hash matches submitted final hash
    /// 6. Verify frame count matches attestation claim
    ///
    /// ## Graceful Degradation
    ///
    /// On verification failure, returns a result with status=Fail and
    /// failure_reason set. Does not panic or return errors - always
    /// returns a usable HashChainVerification for the evidence package.
    #[instrument(skip(self, chain_data, attestation), fields(frames = chain_data.frame_count()))]
    pub fn verify(
        &self,
        chain_data: &HashChainData,
        attestation: &VideoAttestation,
    ) -> HashChainVerification {
        info!(
            "Starting hash chain verification: {} frames, {} checkpoints",
            chain_data.frame_count(),
            chain_data.checkpoints.len()
        );

        // Step 1: Validate chain size
        if let Err(e) = self.validate_chain_size(chain_data) {
            warn!("Chain size validation failed: {}", e);
            return HashChainVerification::fail(e.to_string());
        }

        // Step 2: Validate hash formats
        if let Err(e) = self.validate_hash_formats(chain_data) {
            warn!("Hash format validation failed: {}", e);
            return HashChainVerification::fail(e.to_string());
        }

        // Step 3: Verify checkpoints
        if let Err(e) = self.verify_checkpoints(chain_data) {
            warn!("Checkpoint verification failed: {}", e);
            return HashChainVerification::fail(e.to_string());
        }

        // Step 4: Verify final hash matches last frame
        if let Err(e) = self.verify_final_hash(chain_data) {
            warn!("Final hash verification failed: {}", e);
            return HashChainVerification::fail(e.to_string());
        }

        // Step 5: Verify attestation matches
        if let Err(e) = self.verify_attestation_hash(chain_data, attestation) {
            warn!("Attestation verification failed: {}", e);
            return HashChainVerification::fail(e.to_string());
        }

        // Step 6: Verify frame count consistency
        if let Err(e) = self.verify_frame_count(chain_data, attestation) {
            warn!("Frame count verification failed: {}", e);
            return HashChainVerification::fail(e.to_string());
        }

        // Calculate duration
        let frame_count = chain_data.frame_count() as u32;
        let duration_ms = (frame_count as f64 / self.config.expected_fps as f64 * 1000.0) as u32;

        // Determine if this is a partial verification
        if attestation.is_partial {
            if let Some(checkpoint_idx) = attestation.checkpoint_index {
                // Verify we have the required checkpoint
                if let Err(e) = self.verify_partial_checkpoint(chain_data, checkpoint_idx) {
                    warn!("Partial checkpoint verification failed: {}", e);
                    return HashChainVerification::fail(e.to_string());
                }

                info!(
                    "Hash chain verification PARTIAL: {} frames, checkpoint {}",
                    frame_count, checkpoint_idx
                );
                return HashChainVerification::partial(frame_count, duration_ms, checkpoint_idx);
            }
        }

        info!(
            "Hash chain verification PASSED: {} frames, {}ms duration",
            frame_count, duration_ms
        );
        HashChainVerification::success(frame_count, duration_ms)
    }

    /// Validate chain is not empty and within size limits.
    fn validate_chain_size(
        &self,
        chain_data: &HashChainData,
    ) -> Result<(), HashChainVerificationError> {
        if chain_data.frame_hashes.is_empty() {
            return Err(HashChainVerificationError::EmptyChain);
        }

        if chain_data.frame_hashes.len() > self.config.max_frames {
            return Err(HashChainVerificationError::ChainTooLong {
                count: chain_data.frame_hashes.len(),
                max: self.config.max_frames,
            });
        }

        debug!(
            "Chain size valid: {} frames (max: {})",
            chain_data.frame_hashes.len(),
            self.config.max_frames
        );
        Ok(())
    }

    /// Validate all hashes are properly formatted base64-encoded SHA256.
    fn validate_hash_formats(
        &self,
        chain_data: &HashChainData,
    ) -> Result<(), HashChainVerificationError> {
        // Validate frame hashes
        for (i, hash) in chain_data.frame_hashes.iter().enumerate() {
            self.validate_single_hash(hash, i)?;
        }

        // Validate checkpoint hashes
        for checkpoint in &chain_data.checkpoints {
            self.validate_single_hash(&checkpoint.hash, checkpoint.frame_number as usize)?;
        }

        // Validate final hash
        self.validate_single_hash(&chain_data.final_hash, chain_data.frame_hashes.len())?;

        debug!("All {} hash formats valid", chain_data.frame_hashes.len());
        Ok(())
    }

    /// Validate a single hash is properly formatted.
    fn validate_single_hash(
        &self,
        hash: &str,
        index: usize,
    ) -> Result<(), HashChainVerificationError> {
        // Decode from base64
        let decoded =
            BASE64
                .decode(hash)
                .map_err(|e| HashChainVerificationError::InvalidHashFormat {
                    index,
                    reason: format!("base64 decode failed: {e}"),
                })?;

        // Verify length (SHA256 = 32 bytes)
        if decoded.len() != 32 {
            return Err(HashChainVerificationError::HashLengthMismatch {
                index,
                actual: decoded.len(),
            });
        }

        Ok(())
    }

    /// Verify checkpoints are at correct positions with matching hashes.
    fn verify_checkpoints(
        &self,
        chain_data: &HashChainData,
    ) -> Result<(), HashChainVerificationError> {
        for checkpoint in &chain_data.checkpoints {
            // Verify checkpoint is at expected frame number
            let expected_frame = (checkpoint.index + 1) * self.config.checkpoint_interval;
            if checkpoint.frame_number != expected_frame {
                return Err(HashChainVerificationError::CheckpointWrongPosition {
                    index: checkpoint.index,
                    expected: expected_frame,
                    actual: checkpoint.frame_number,
                });
            }

            // Verify checkpoint hash matches frame hash at that position
            // Frame numbers are 1-based in checkpoints, array is 0-based
            let frame_idx = checkpoint.frame_number as usize - 1;
            if frame_idx >= chain_data.frame_hashes.len() {
                // Checkpoint beyond chain length - valid for interrupted recordings
                debug!(
                    "Checkpoint {} at frame {} beyond chain length {}",
                    checkpoint.index,
                    checkpoint.frame_number,
                    chain_data.frame_hashes.len()
                );
                continue;
            }

            let frame_hash = &chain_data.frame_hashes[frame_idx];
            if checkpoint.hash != *frame_hash {
                return Err(HashChainVerificationError::CheckpointMismatch {
                    index: checkpoint.index,
                });
            }

            debug!(
                "Checkpoint {} at frame {} verified",
                checkpoint.index, checkpoint.frame_number
            );
        }

        Ok(())
    }

    /// Verify final hash matches last frame hash.
    fn verify_final_hash(
        &self,
        chain_data: &HashChainData,
    ) -> Result<(), HashChainVerificationError> {
        let last_frame_hash = chain_data.frame_hashes.last().ok_or_else(|| {
            HashChainVerificationError::InvalidHashFormat {
                index: 0,
                reason: "no frame hashes".to_string(),
            }
        })?;

        if chain_data.final_hash != *last_frame_hash {
            return Err(HashChainVerificationError::FinalHashMismatch);
        }

        debug!("Final hash matches last frame hash");
        Ok(())
    }

    /// Verify attestation hash matches submitted final hash.
    fn verify_attestation_hash(
        &self,
        chain_data: &HashChainData,
        attestation: &VideoAttestation,
    ) -> Result<(), HashChainVerificationError> {
        // For full attestation, verify against final hash
        // For partial attestation with checkpoint, verify against checkpoint hash
        let expected_hash = if attestation.is_partial {
            if let Some(checkpoint_idx) = attestation.checkpoint_index {
                // Find the checkpoint hash
                chain_data
                    .checkpoints
                    .iter()
                    .find(|c| c.index == checkpoint_idx)
                    .map(|c| &c.hash)
                    .ok_or(HashChainVerificationError::MissingCheckpoint {
                        index: checkpoint_idx,
                    })?
            } else {
                // Partial but no checkpoint specified - use final hash
                &chain_data.final_hash
            }
        } else {
            &chain_data.final_hash
        };

        if attestation.final_hash != *expected_hash {
            return Err(HashChainVerificationError::AttestationHashMismatch);
        }

        debug!("Attestation hash matches submitted chain");
        Ok(())
    }

    /// Verify frame count matches attestation claim.
    fn verify_frame_count(
        &self,
        chain_data: &HashChainData,
        attestation: &VideoAttestation,
    ) -> Result<(), HashChainVerificationError> {
        let chain_count = chain_data.frame_hashes.len() as u32;

        // Allow some tolerance for frame count (dropped frames possible)
        let diff = (chain_count as i32 - attestation.frame_count as i32).unsigned_abs();
        let tolerance = 5; // Allow up to 5 frames difference

        if diff > tolerance {
            return Err(HashChainVerificationError::FrameCountMismatch {
                attested: attestation.frame_count,
                actual: chain_count,
            });
        }

        if diff > 0 {
            debug!(
                "Frame count within tolerance: attested {}, actual {} (diff: {})",
                attestation.frame_count, chain_count, diff
            );
        }

        Ok(())
    }

    /// Verify partial attestation has required checkpoint.
    fn verify_partial_checkpoint(
        &self,
        chain_data: &HashChainData,
        checkpoint_idx: u32,
    ) -> Result<(), HashChainVerificationError> {
        let has_checkpoint = chain_data
            .checkpoints
            .iter()
            .any(|c| c.index == checkpoint_idx);

        if !has_checkpoint {
            return Err(HashChainVerificationError::MissingCheckpoint {
                index: checkpoint_idx,
            });
        }

        debug!("Partial checkpoint {} found", checkpoint_idx);
        Ok(())
    }
}

impl Default for HashChainVerifier {
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
    use crate::types::hash_chain_verification::{HashCheckpoint, VerificationStatus};

    /// Create a valid base64-encoded SHA256 hash (32 bytes -> 44 chars)
    fn make_hash(seed: u8) -> String {
        let hash_bytes: [u8; 32] = [seed; 32];
        BASE64.encode(hash_bytes)
    }

    /// Create a minimal valid hash chain
    fn make_chain(frame_count: usize) -> HashChainData {
        let frame_hashes: Vec<String> = (0..frame_count).map(|i| make_hash(i as u8)).collect();
        let final_hash = frame_hashes.last().cloned().unwrap_or_else(|| make_hash(0));

        HashChainData {
            frame_hashes,
            checkpoints: vec![],
            final_hash,
        }
    }

    /// Create a valid attestation matching a chain
    fn make_attestation(chain: &HashChainData) -> VideoAttestation {
        VideoAttestation {
            final_hash: chain.final_hash.clone(),
            assertion: BASE64.encode(b"test_assertion"),
            duration_ms: (chain.frame_count() as u64 * 1000) / 30,
            frame_count: chain.frame_count() as u32,
            is_partial: false,
            checkpoint_index: None,
        }
    }

    #[test]
    fn test_verify_valid_chain() {
        let verifier = HashChainVerifier::new();
        let chain = make_chain(150);
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Pass);
        assert!(result.is_valid());
        assert!(result.chain_structure_valid);
        assert!(result.final_hash_matches);
        assert!(result.attestation_valid);
    }

    #[test]
    fn test_verify_empty_chain() {
        let verifier = HashChainVerifier::new();
        let chain = HashChainData {
            frame_hashes: vec![],
            checkpoints: vec![],
            final_hash: make_hash(0),
        };
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("Empty"));
    }

    #[test]
    fn test_verify_chain_too_long() {
        let verifier = HashChainVerifier::with_config(HashChainVerifierConfig {
            max_frames: 100,
            ..Default::default()
        });
        let chain = make_chain(150);
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("too long"));
    }

    #[test]
    fn test_verify_invalid_hash_format() {
        let verifier = HashChainVerifier::new();
        let mut chain = make_chain(10);
        chain.frame_hashes[5] = "not_valid_base64!!!".to_string();
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("format"));
    }

    #[test]
    fn test_verify_wrong_hash_length() {
        let verifier = HashChainVerifier::new();
        let mut chain = make_chain(10);
        // Valid base64 but wrong length (not 32 bytes)
        chain.frame_hashes[3] = BASE64.encode(b"too_short");
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("length"));
    }

    #[test]
    fn test_verify_final_hash_mismatch() {
        let verifier = HashChainVerifier::new();
        let mut chain = make_chain(10);
        chain.final_hash = make_hash(255); // Different from last frame
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("Final hash"));
    }

    #[test]
    fn test_verify_attestation_mismatch() {
        let verifier = HashChainVerifier::new();
        let chain = make_chain(10);
        let mut attestation = make_attestation(&chain);
        attestation.final_hash = make_hash(255); // Different from chain

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("Attestation"));
    }

    #[test]
    fn test_verify_frame_count_mismatch() {
        let verifier = HashChainVerifier::new();
        let chain = make_chain(100);
        let mut attestation = make_attestation(&chain);
        attestation.frame_count = 50; // Way off

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("Frame count"));
    }

    #[test]
    fn test_verify_frame_count_tolerance() {
        let verifier = HashChainVerifier::new();
        let chain = make_chain(100);
        let mut attestation = make_attestation(&chain);
        attestation.frame_count = 98; // Within tolerance

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Pass);
    }

    #[test]
    fn test_verify_with_checkpoints() {
        let verifier = HashChainVerifier::new();
        let mut chain = make_chain(300);

        // Add checkpoints at frames 150 and 300
        chain.checkpoints = vec![
            HashCheckpoint {
                index: 0,
                frame_number: 150,
                hash: chain.frame_hashes[149].clone(), // 0-based index
                timestamp: 5.0,
            },
            HashCheckpoint {
                index: 1,
                frame_number: 300,
                hash: chain.frame_hashes[299].clone(),
                timestamp: 10.0,
            },
        ];
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Pass);
        assert!(result.checkpoints_valid);
    }

    #[test]
    fn test_verify_checkpoint_mismatch() {
        let verifier = HashChainVerifier::new();
        let mut chain = make_chain(200);

        // Add checkpoint with wrong hash
        chain.checkpoints = vec![HashCheckpoint {
            index: 0,
            frame_number: 150,
            hash: make_hash(255), // Wrong hash
            timestamp: 5.0,
        }];
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("Checkpoint"));
    }

    #[test]
    fn test_verify_checkpoint_wrong_position() {
        let verifier = HashChainVerifier::new();
        let mut chain = make_chain(200);

        // Add checkpoint at wrong frame number
        chain.checkpoints = vec![HashCheckpoint {
            index: 0,
            frame_number: 100, // Should be 150
            hash: chain.frame_hashes[99].clone(),
            timestamp: 3.33,
        }];
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result.failure_reason.unwrap().contains("wrong position"));
    }

    #[test]
    fn test_verify_partial_attestation() {
        let verifier = HashChainVerifier::new();
        let mut chain = make_chain(200);

        // Add checkpoint
        chain.checkpoints = vec![HashCheckpoint {
            index: 0,
            frame_number: 150,
            hash: chain.frame_hashes[149].clone(),
            timestamp: 5.0,
        }];

        // Partial attestation pointing to checkpoint
        // Note: frame_count should match actual chain length for verification
        let attestation = VideoAttestation {
            final_hash: chain.checkpoints[0].hash.clone(),
            assertion: BASE64.encode(b"test_assertion"),
            duration_ms: 6666, // ~200 frames at 30fps
            frame_count: 200,  // Match chain length
            is_partial: true,
            checkpoint_index: Some(0),
        };

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Partial);
        assert!(result.is_partial);
        assert_eq!(result.checkpoint_index, Some(0));
    }

    #[test]
    fn test_verify_partial_missing_checkpoint() {
        let verifier = HashChainVerifier::new();
        let chain = make_chain(100); // No checkpoints

        let attestation = VideoAttestation {
            final_hash: chain.final_hash.clone(),
            assertion: BASE64.encode(b"test_assertion"),
            duration_ms: 3333,
            frame_count: 100,
            is_partial: true,
            checkpoint_index: Some(0), // References missing checkpoint
        };

        let result = verifier.verify(&chain, &attestation);
        assert_eq!(result.status, VerificationStatus::Fail);
        assert!(result
            .failure_reason
            .unwrap()
            .contains("Missing checkpoint"));
    }

    #[test]
    fn test_default_impl() {
        let verifier: HashChainVerifier = Default::default();
        let chain = make_chain(10);
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert!(result.is_valid());
    }

    #[test]
    fn test_custom_config() {
        let config = HashChainVerifierConfig {
            max_frames: 1000,
            expected_fps: 60,
            max_duration_secs: 30,
            checkpoint_interval: 300,
        };
        let verifier = HashChainVerifier::with_config(config);

        let chain = make_chain(500);
        let attestation = make_attestation(&chain);

        let result = verifier.verify(&chain, &attestation);
        assert!(result.is_valid());
        // Duration calculated at 60fps
        assert_eq!(result.duration_ms, 8333); // 500 frames / 60 fps * 1000
    }
}
