# Story 7-12-c2pa-video-manifest-generation: C2PA Video Manifest Generation

## Story Overview
- **Epic:** 7 - Video Capture with LiDAR Depth
- **Story ID:** 7-12-c2pa-video-manifest-generation
- **Priority:** P0
- **Estimated Effort:** M
- **Dependencies:** Story 7-11-video-evidence-package (VideoEvidence struct and confidence calculation)

## User Story

As a **backend processing system**,
I want **to generate C2PA Content Credentials manifests for video captures**,
So that **video evidence packages are cryptographically signed and machine-verifiable according to industry standards**.

## Story Context

This story extends the existing C2PA manifest generation from photos (Story 5-1) to support video captures. C2PA (Coalition for Content Provenance and Authenticity) provides a standard way to embed tamper-evident metadata directly into media files, making RealityCam videos verifiable by any C2PA-compliant tool.

The key differences for video manifests:

**Video-Specific Assertions:**
- Duration and frame count (verified vs total)
- Hash chain summary (chain intact, verified frames)
- Temporal depth analysis results (depth_consistency, motion_coherence, scene_stability)
- Partial attestation information (if recording was interrupted)

**Storage Strategy:**
- Video files are NOT modified (MP4 embedding deferred to post-MVP)
- Manifest stored as separate JSON file in S3
- Future enhancement: Use c2pa-rs to embed manifest in MP4 per ISO BMFF spec

**Integration Points:**
1. **Story 7-11 (Evidence Package):** Consumes VideoEvidence struct
2. **Story 5-2 (C2PA Signing):** Reuses Ed25519 signing service
3. **Story 7-13 (Video Verification Page):** Manifest displayed to users

### Key Design Decisions

1. **Reuse existing C2PA service patterns:** Follow the same service structure and manifest format from photo C2PA (Story 5-1), extending with video-specific assertions.

2. **Manifest-only storage (MVP):** Store manifests as separate JSON files rather than embedding in MP4. This avoids c2pa-rs complexity with video encoding and allows faster iteration. Future enhancement can add embedding.

3. **Video-specific assertion structure:** Include hash_chain_summary, temporal_depth_summary, and partial_attestation fields in the RealityCam assertion.

4. **Action type differentiation:** Use "c2pa.recorded" action type for videos (vs "c2pa.created" for photos) to indicate video recording provenance.

5. **Frame count and duration tracking:** Manifest includes both total and verified metrics to handle partial videos transparently.

---

## Acceptance Criteria

### AC-7.12.1: Video Manifest Generation
**Given** a complete VideoEvidence package (from Story 7-11)
**When** C2PA manifest generation is triggered
**Then**:
1. Generate C2PA manifest structure following spec 2.0
2. Include video-specific RealityCam assertion
3. Include hash chain summary (chain_intact, verified_frames, attestation_valid)
4. Include temporal depth analysis summary (depth_consistency, motion_coherence, scene_stability)
5. Include partial attestation info if is_partial=true
6. Set title to "RealityCam Verified Video"
7. Use "c2pa.recorded" action type

### AC-7.12.2: Video RealityCam Assertion Structure
**Given** VideoEvidence package
**When** building RealityCam assertion
**Then** structure includes:
```json
{
  "confidence_level": "high",
  "type": "video",
  "duration_ms": 15000,
  "frame_count": 450,
  "verified_frames": 450,
  "hardware_attestation": {
    "status": "pass",
    "level": "secure_enclave",
    "verified": true
  },
  "hash_chain_summary": {
    "status": "pass",
    "chain_intact": true,
    "attestation_valid": true,
    "verified_frames": 450,
    "total_frames": 450
  },
  "temporal_depth_summary": {
    "status": "pass",
    "is_likely_real_scene": true,
    "depth_consistency": 0.85,
    "motion_coherence": 0.72,
    "scene_stability": 0.95
  },
  "partial_attestation": {
    "is_partial": false,
    "checkpoint_index": null,
    "verified_frames": 450,
    "total_frames": 450
  },
  "device_model": "iPhone 15 Pro",
  "captured_at": "2025-11-27T12:00:00Z"
}
```

### AC-7.12.3: Partial Video Manifest
**Given** VideoEvidence with is_partial=true (interrupted recording)
**When** manifest is generated
**Then**:
1. Include partial_attestation with checkpoint details
2. verified_frames < total_frames
3. duration_ms reflects only verified portion
4. Confidence level reflects partial verification
5. Manifest clearly indicates verification scope

### AC-7.12.4: Manifest Storage
**Given** generated C2PA manifest
**When** storing manifest
**Then**:
1. Serialize manifest to JSON
2. Store to S3 at key: `captures/{capture_id}/video_manifest.json`
3. Update capture record with manifest_key
4. Do NOT modify original video file
5. Manifest retrievable for verification page

### AC-7.12.5: Hash Chain Summary Mapping
**Given** HashChainVerification result (from Story 7-10)
**When** mapping to manifest
**Then**:
1. Map status: Pass/Partial/Fail → "pass"/"partial"/"fail"
2. Include chain_intact boolean
3. Include attestation_valid boolean
4. Include verified_frames count
5. Include total_frames count
6. Include broken_at_frame if chain broken

### AC-7.12.6: Temporal Depth Summary Mapping
**Given** VideoDepthAnalysis result (from Story 7-9)
**When** mapping to manifest
**Then**:
1. Map status: Pass/Fail/Unavailable → "pass"/"fail"/"unavailable"
2. Include is_likely_real_scene boolean
3. Include depth_consistency (0.0-1.0)
4. Include motion_coherence (0.0-1.0)
5. Include scene_stability (0.0-1.0)
6. Handle missing depth analysis gracefully (status="unavailable")

### AC-7.12.7: Integration with Evidence Pipeline
**Given** video capture fully processed (Story 7-11)
**When** evidence package complete
**Then**:
1. C2PA manifest generation runs automatically
2. Manifest stored to S3
3. Capture record updated with manifest reference
4. Processing continues even if manifest generation fails
5. Error logged if manifest generation fails

---

## Technical Requirements

### Video C2PA Service Extension

```rust
// services/c2pa.rs (extend existing service)

use crate::types::video_evidence::{VideoEvidence, HashChainVerification, VideoDepthAnalysis};

impl C2paService {
    /// Generates a C2PA manifest from a video evidence package
    ///
    /// # Arguments
    /// * `evidence` - Video evidence package from capture processing
    /// * `captured_at` - Capture timestamp (ISO 8601)
    ///
    /// # Returns
    /// C2PA manifest structure with video-specific assertions
    pub fn generate_video_manifest(
        &self,
        evidence: &VideoEvidence,
        captured_at: &str,
    ) -> C2paVideoManifest {
        let assertion = self.build_video_assertion(evidence, captured_at);

        let version = env!("CARGO_PKG_VERSION");
        let claim_generator = format!("{CLAIM_GENERATOR}/{version}");
        let software_agent = format!("{SOFTWARE_AGENT}/{version}");

        C2paVideoManifest {
            claim_generator,
            title: "RealityCam Verified Video".to_string(),
            created_at: captured_at.to_string(),
            actions: vec![C2paAction {
                action: "c2pa.recorded".to_string(),  // Note: "recorded" not "created"
                when: captured_at.to_string(),
                software_agent,
            }],
            realitycam: assertion,
        }
    }

    /// Generates a C2PA video manifest as JSON string
    pub fn generate_video_manifest_json(
        &self,
        evidence: &VideoEvidence,
        captured_at: &str,
    ) -> Result<String, C2paError> {
        let manifest = self.generate_video_manifest(evidence, captured_at);
        serde_json::to_string_pretty(&manifest)
            .map_err(|e| C2paError::Serialization(e.to_string()))
    }

    /// Builds the RealityCam video assertion from evidence
    fn build_video_assertion(
        &self,
        evidence: &VideoEvidence,
        captured_at: &str,
    ) -> RealityCamVideoAssertion {
        let confidence_level = self.map_confidence_level(&evidence);

        let hardware_attestation = HardwareAssertionData {
            status: evidence.hardware_attestation.status.clone(),
            level: "secure_enclave".to_string(),  // From attestation
            verified: evidence.hardware_attestation.assertion_valid,
        };

        let hash_chain_summary = HashChainSummaryData {
            status: self.map_verification_status(&evidence.hash_chain.status),
            chain_intact: evidence.hash_chain.chain_intact,
            attestation_valid: evidence.hash_chain.attestation_valid,
            verified_frames: evidence.hash_chain.verified_frames,
            total_frames: evidence.hash_chain.total_frames,
            broken_at_frame: evidence.hash_chain.broken_at_frame,
        };

        let temporal_depth_summary = evidence.depth_analysis.as_ref().map(|depth| {
            TemporalDepthSummaryData {
                status: "pass".to_string(),  // Derived from checks
                is_likely_real_scene: depth.is_likely_real_scene,
                depth_consistency: depth.depth_consistency,
                motion_coherence: depth.motion_coherence,
                scene_stability: depth.scene_stability,
            }
        });

        let partial_attestation = PartialAttestationData {
            is_partial: evidence.partial_attestation.is_partial,
            checkpoint_index: evidence.partial_attestation.checkpoint_index,
            verified_frames: evidence.partial_attestation.verified_frames,
            total_frames: evidence.partial_attestation.total_frames,
            reason: evidence.partial_attestation.reason.clone(),
        };

        RealityCamVideoAssertion {
            confidence_level,
            r#type: "video".to_string(),
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

    /// Map VideoEvidence confidence to string
    fn map_confidence_level(&self, evidence: &VideoEvidence) -> String {
        // Use confidence calculation from VideoEvidenceService
        // This is already computed in evidence package
        match evidence.calculate_confidence() {
            ConfidenceLevel::High => "high",
            ConfidenceLevel::Medium => "medium",
            ConfidenceLevel::Low => "low",
            ConfidenceLevel::Suspicious => "suspicious",
        }.to_string()
    }

    /// Map VerificationStatus to string
    fn map_verification_status(&self, status: &VerificationStatus) -> String {
        match status {
            VerificationStatus::Pass => "pass",
            VerificationStatus::Partial => "partial",
            VerificationStatus::Fail => "fail",
        }.to_string()
    }
}
```

### Video-Specific Data Structures

```rust
// services/c2pa.rs (add to existing module)

/// C2PA manifest structure for video
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

/// RealityCam video assertion for C2PA manifest
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RealityCamVideoAssertion {
    /// Confidence level from evidence analysis
    pub confidence_level: String,

    /// Media type (always "video")
    pub r#type: String,

    /// Total video duration in milliseconds
    pub duration_ms: u64,

    /// Total frame count
    pub frame_count: u32,

    /// Frames successfully verified
    pub verified_frames: u32,

    /// Hardware attestation summary
    pub hardware_attestation: HardwareAssertionData,

    /// Hash chain verification summary
    pub hash_chain_summary: HashChainSummaryData,

    /// Temporal depth analysis summary (optional)
    pub temporal_depth_summary: Option<TemporalDepthSummaryData>,

    /// Partial attestation information
    pub partial_attestation: PartialAttestationData,

    /// Device information
    pub device_model: String,

    /// Capture timestamp (ISO 8601)
    pub captured_at: String,
}

/// Hash chain verification summary for C2PA assertion
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
    pub broken_at_frame: Option<u32>,
}

/// Temporal depth analysis summary for C2PA assertion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalDepthSummaryData {
    /// Analysis status: "pass", "fail", "unavailable"
    pub status: String,

    /// Whether scene is likely real (not flat)
    pub is_likely_real_scene: bool,

    /// Depth consistency across frames (0.0-1.0)
    pub depth_consistency: f64,

    /// Motion coherence with depth changes (0.0-1.0)
    pub motion_coherence: f64,

    /// Scene stability (lack of suspicious jumps) (0.0-1.0)
    pub scene_stability: f64,
}

/// Partial attestation information for C2PA assertion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartialAttestationData {
    /// Whether video was interrupted
    pub is_partial: bool,

    /// Checkpoint index if partial (0=5s, 1=10s, 2=15s)
    pub checkpoint_index: Option<u32>,

    /// Frames successfully verified
    pub verified_frames: u32,

    /// Total frames captured
    pub total_frames: u32,

    /// Reason for partial attestation
    pub reason: Option<String>,
}
```

### Storage Integration

```rust
// services/c2pa.rs (add to existing module)

/// S3 key pattern for video C2PA manifest
pub fn c2pa_video_manifest_s3_key(capture_id: Uuid) -> String {
    format!("captures/{capture_id}/video_manifest.json")
}

// Note: Future enhancement for embedded manifests
// pub fn c2pa_video_embedded_s3_key(capture_id: Uuid) -> String {
//     format!("captures/{capture_id}/c2pa_video.mp4")
// }
```

### Integration with Video Processing Pipeline

```rust
// routes/captures_video.rs (or processing module)

use crate::services::c2pa::C2paService;
use crate::services::storage::StorageService;

async fn finalize_video_processing(
    capture_id: Uuid,
    evidence: &VideoEvidence,
    captured_at: &str,
    pool: &PgPool,
    storage: &StorageService,
) -> Result<(), ProcessingError> {
    // Generate C2PA manifest
    let c2pa_service = C2paService::new();
    let manifest_json = c2pa_service
        .generate_video_manifest_json(evidence, captured_at)
        .map_err(|e| {
            tracing::error!("C2PA manifest generation failed: {}", e);
            ProcessingError::C2paError(e.to_string())
        })?;

    // Store manifest to S3
    let manifest_key = c2pa::c2pa_video_manifest_s3_key(capture_id);
    storage
        .upload(&manifest_key, manifest_json.as_bytes(), "application/json")
        .await
        .map_err(|e| {
            tracing::error!("Failed to upload C2PA manifest: {}", e);
            ProcessingError::StorageError(e.to_string())
        })?;

    // Update capture record with manifest reference
    sqlx::query!(
        r#"
        UPDATE captures
        SET manifest_key = $1
        WHERE id = $2
        "#,
        manifest_key,
        capture_id
    )
    .execute(pool)
    .await?;

    tracing::info!(
        "C2PA video manifest generated and stored: capture_id={}, manifest_key={}",
        capture_id,
        manifest_key
    );

    Ok(())
}
```

---

## Implementation Tasks

### Task 1: Extend C2PA Service with Video Types
**File:** `backend/src/services/c2pa.rs`

Add video-specific types:
- [ ] Create `C2paVideoManifest` struct
- [ ] Create `RealityCamVideoAssertion` struct
- [ ] Create `HashChainSummaryData` struct
- [ ] Create `TemporalDepthSummaryData` struct
- [ ] Create `PartialAttestationData` struct
- [ ] Add serde Serialize/Deserialize derives
- [ ] Add documentation comments

### Task 2: Implement Video Manifest Generation
**File:** `backend/src/services/c2pa.rs`

Add video manifest methods:
- [ ] Implement `generate_video_manifest()` method
- [ ] Implement `generate_video_manifest_json()` method
- [ ] Implement `build_video_assertion()` helper
- [ ] Use "c2pa.recorded" action type for videos
- [ ] Set title to "RealityCam Verified Video"
- [ ] Add tracing for manifest generation

### Task 3: Implement Assertion Mapping
**File:** `backend/src/services/c2pa.rs`

Map evidence to assertions:
- [ ] Implement `map_confidence_level()` helper
- [ ] Implement `map_verification_status()` helper
- [ ] Map hardware attestation to HardwareAssertionData
- [ ] Map hash chain results to HashChainSummaryData
- [ ] Map depth analysis to TemporalDepthSummaryData
- [ ] Map partial attestation to PartialAttestationData
- [ ] Handle optional depth analysis (set status="unavailable")

### Task 4: Add Video Manifest Storage
**File:** `backend/src/services/c2pa.rs`

Add storage helpers:
- [ ] Implement `c2pa_video_manifest_s3_key()` function
- [ ] Export function for use in processing pipeline
- [ ] Add documentation for storage patterns
- [ ] Document future embedding enhancement path

### Task 5: Integrate with Video Processing Pipeline
**File:** `backend/src/routes/captures_video.rs` or processing module

Wire up manifest generation:
- [ ] Call C2PA service after evidence package complete
- [ ] Serialize manifest to JSON
- [ ] Upload manifest to S3
- [ ] Update capture record with manifest_key
- [ ] Add error handling (graceful degradation)
- [ ] Add tracing for manifest lifecycle
- [ ] Log manifest generation time

### Task 6: Add Database Schema Support
**File:** `backend/migrations/YYYYMMDDHHMMSS_add_manifest_key.sql` (if needed)

Ensure database supports manifest storage:
- [ ] Verify captures.manifest_key column exists
- [ ] Add column if missing: `manifest_key VARCHAR(512)`
- [ ] Add index for manifest_key if needed
- [ ] Test migration up/down

---

## Test Requirements

### Unit Tests
**File:** `backend/src/services/c2pa_tests.rs`

Video manifest tests:
- [ ] Test `generate_video_manifest()` with complete evidence
- [ ] Test video assertion structure matches spec
- [ ] Test hash chain summary mapping (pass/partial/fail)
- [ ] Test temporal depth summary mapping (all metrics)
- [ ] Test partial attestation mapping (checkpoint info)
- [ ] Test confidence level mapping (high/medium/low/suspicious)
- [ ] Test manifest with missing depth analysis
- [ ] Test manifest JSON serialization
- [ ] Test action type is "c2pa.recorded"
- [ ] Test title is "RealityCam Verified Video"
- [ ] Test software agent includes version
- [ ] Test S3 key generation pattern

### Integration Tests
**File:** `backend/tests/c2pa_video_integration.rs`

End-to-end manifest tests:
- [ ] Test full manifest generation from VideoEvidence fixture
- [ ] Test manifest JSON deserializes correctly
- [ ] Test manifest stored to S3 successfully
- [ ] Test capture record updated with manifest_key
- [ ] Test manifest generation with partial video
- [ ] Test graceful handling of manifest generation failure
- [ ] Test manifest includes all required fields
- [ ] Test manifest is valid JSON

### Test Fixtures

Create fixtures in `backend/tests/fixtures/`:
- [ ] `video_evidence_complete.json` - Full video with all checks passing
- [ ] `video_evidence_partial.json` - Partial video with checkpoint
- [ ] `video_evidence_no_depth.json` - Video without depth analysis
- [ ] `expected_video_manifest_complete.json` - Expected manifest output
- [ ] `expected_video_manifest_partial.json` - Expected partial manifest

---

## Definition of Done

- [ ] All acceptance criteria met (AC-7.12.1 through AC-7.12.7)
- [ ] Video manifest types defined in c2pa.rs
- [ ] `generate_video_manifest()` and `generate_video_manifest_json()` implemented
- [ ] Assertion mapping implemented for all evidence components
- [ ] Video manifest uses "c2pa.recorded" action type
- [ ] Manifest stored as JSON to S3 (no embedding)
- [ ] Capture record updated with manifest_key
- [ ] Integration with evidence pipeline working
- [ ] Unit tests passing with >= 85% coverage
- [ ] Integration tests passing with fixture data
- [ ] Graceful error handling (processing continues on failure)
- [ ] No new lint errors (Clippy)
- [ ] Tracing/logging for manifest lifecycle
- [ ] Ready for Story 7-13 (Video Verification Page) integration

---

## Technical Notes

### Why Manifest-Only Storage (No Embedding)?

**MVP Decision:** Store C2PA manifests as separate JSON files rather than embedding in MP4.

**Reasons:**
1. **Complexity:** c2pa-rs MP4 embedding requires careful handling of video encoding
2. **Iteration speed:** Separate manifests allow faster development and testing
3. **Video preservation:** Avoids risk of corrupting uploaded videos
4. **Sufficient for MVP:** Manifests are still cryptographically signed and verifiable

**Future Enhancement:** Post-MVP, add MP4 embedding using c2pa-rs per ISO BMFF spec. This requires:
- Re-encoding video with embedded manifest
- Storing both original and C2PA-embedded versions
- Web player support for embedded manifests

### Action Type: "c2pa.recorded" vs "c2pa.created"

C2PA spec distinguishes between different provenance actions:
- **c2pa.created:** Digital creation (photos in our case)
- **c2pa.recorded:** Real-world recording (videos in our case)

This distinction helps downstream tools understand the content's origin.

### Partial Video Manifests

Interrupted videos include complete partial attestation information:
- `is_partial: true`
- `checkpoint_index`: Which checkpoint was attested
- `verified_frames` < `total_frames`
- Confidence level reflects partial verification

This transparency ensures users and verifiers understand the verification scope.

### Hash Chain Summary

The hash chain summary provides high-level verification results without exposing full chain:
- `chain_intact`: Boolean indicating no tampering
- `attestation_valid`: Boolean indicating signature match
- `broken_at_frame`: Forensic detail if chain broken

This allows quick assessment while preserving detailed evidence.

### Temporal Depth Summary

Video-specific metrics capture 3D scene consistency:
- `depth_consistency`: How stable depth values are across frames
- `motion_coherence`: Whether motion matches depth changes
- `scene_stability`: Lack of suspicious jumps or discontinuities

These metrics detect manipulation attempts that single-frame analysis would miss.

### Confidence Level in Manifests

Confidence is calculated by VideoEvidenceService (Story 7-11) and included in manifest for transparency. This allows verifiers to:
1. Quickly assess overall authenticity
2. Understand which checks passed/failed
3. Make informed trust decisions

### Future: Embedded Manifests

Post-MVP enhancement path:
1. Use c2pa-rs `Builder` to create manifest
2. Sign with existing Ed25519 service
3. Embed manifest in MP4 per ISO BMFF spec
4. Store embedded video to S3 (separate from original)
5. Update verification page to read embedded manifests
6. Validate with c2pa-rs `Reader`

---

## Source Document References

- **Epic:** docs/epics.md - Story 7.12: C2PA Video Manifest Generation
- **Tech Spec:** docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-7.md
  - Section: Services and Modules > Backend Services > c2pa_video.rs
  - Section: AC-7.11: C2PA Video Manifest
  - Section: Data Models > VideoEvidence
- **Architecture:** docs/architecture.md
  - ADR-010: Video Architecture with LiDAR Depth
  - C2PA patterns from photo implementation
- **Previous Stories:**
  - docs/sprint-artifacts/stories/7-11-video-evidence-package.md (VideoEvidence input)
  - docs/sprint-artifacts/stories/5-1-c2pa-manifest-generation.md (Photo C2PA patterns)
  - docs/sprint-artifacts/stories/5-2-c2pa-signing-ed25519.md (Signing service)
- **C2PA Service:** backend/src/services/c2pa.rs (existing photo implementation)

---

## Learnings from Previous Stories

Based on review of Stories 5-1 (C2PA Manifest), 7-11 (Video Evidence), and existing c2pa.rs:

1. **Service Pattern (Story 5-1):** C2paService uses struct methods with clear separation: `generate_manifest()`, `generate_manifest_json()`, and `build_assertion()`. Follow same pattern for video.

2. **RealityCam Assertions (Story 5-1):** Custom assertions extend C2PA with RealityCam-specific evidence. Video assertions follow same structure but include video-specific fields.

3. **Evidence Mapping (Story 7-11):** VideoEvidence already includes all necessary data. C2PA service just maps to manifest structure.

4. **Error Handling (Story 5-1):** C2PA errors use thiserror enum. Graceful degradation: manifest generation failure doesn't block capture processing.

5. **Storage Pattern (Story 5-1):** S3 key helpers make storage paths consistent: `c2pa_video_manifest_s3_key()` matches `c2pa_manifest_s3_key()`.

6. **JSON Serialization (Story 5-1):** Use `serde_json::to_string_pretty()` for readable manifests. Add proper error mapping.

7. **Testing Strategy (Stories 5-1, 7-11):** Create fixture evidence packages with known outputs. Test serialization/deserialization round-trips.

8. **Confidence in Manifests (Story 7-11):** Confidence level is already calculated by VideoEvidenceService. Just extract and include in manifest.

9. **Optional Fields (Story 7-11):** Depth analysis may be unavailable. Use Option<> and handle gracefully with status="unavailable".

10. **Action Types (C2PA Spec):** Photos use "c2pa.created", videos use "c2pa.recorded". This is a C2PA spec distinction.

11. **Backend Version (Story 5-1):** Use env!("CARGO_PKG_VERSION") for version string in claim_generator and software_agent.

12. **Future Embedding Path (Story 5-1):** MVP stores manifests separately. Document future enhancement path for embedding without blocking current work.

---

## FR Coverage

This story implements:
- **FR54:** Backend generates C2PA Content Credentials manifests for video captures

This story enables:
- **FR55:** Video verification page displays C2PA manifest and assertions (Story 7-13)

---

_Story created: 2025-11-27_
_FR Coverage: FR54 (C2PA video manifest generation), enabling FR55_

---

## Dev Agent Record

### Status
**Status:** drafted

### Context Reference
`docs/sprint-artifacts/story-contexts/7-12-c2pa-video-manifest-generation-context.xml`

### Agent Model Used

<!-- To be filled by dev agent -->

### File List

<!-- To be filled by dev agent -->

### Completion Notes

<!-- To be filled by dev agent -->

### Debug Log References

<!-- To be filled by dev agent -->
