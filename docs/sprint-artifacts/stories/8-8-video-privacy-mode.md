# Story 8-8: Video Privacy Mode Support

Status: drafted

## Story

As a **privacy-conscious user**,
I want **to record videos in Privacy Mode with hash-only uploads**,
So that **I can prove video authenticity with temporal depth verification without uploading the video file to the server**.

## Acceptance Criteria

### AC 1: Video Privacy Mode Capture Flow
**Given** Privacy Mode is enabled in settings
**When** user switches to video mode and records
**Then**:
1. Video recording works with all Privacy Mode settings active
2. Privacy Mode indicator visible during video recording
3. Frame-by-frame hash chain computed locally (30fps)
4. Depth keyframes extracted at 10fps for temporal analysis
5. Client-side depth analysis performed on each depth keyframe
6. Video attestation checkpoints generated every 5 seconds
7. Full video file retained in local encrypted storage
8. Recording completes successfully with privacy payload prepared

### AC 2: Client-Side Temporal Depth Analysis
**Given** a video has been recorded in Privacy Mode
**When** preparing the hash-only payload
**Then**:
1. DepthAnalysisService analyzes each depth keyframe (~150 frames for 15s video)
2. Temporal consistency checked across keyframes (variance stability)
3. Aggregate temporal depth result computed (mean variance, consistency score)
4. Analysis completes in < 2 seconds for 15s video
5. Results include per-keyframe analysis + temporal summary
6. Algorithm version tracked for determinism ("1.0")

### AC 3: Video Hash-Only Payload Builder
**Given** video recording and analysis complete
**When** constructing upload payload
**Then** payload contains:
1. `media_hash`: SHA-256 of complete video file
2. `media_type`: "video"
3. `hash_chain`: Complete frame hash chain with integrity data
4. `frame_count`: Total frames in video
5. `duration_ms`: Video duration in milliseconds
6. `depth_analysis`: Temporal depth analysis results
7. `checkpoint_attestations`: Array of attestation checkpoints
8. `metadata`: Filtered per privacy settings (location, timestamp, device)
9. `metadata_flags`: Privacy level indicators
10. `assertion`: DCAppAttest signature covering entire payload
11. Upload size < 50KB (vs ~30-45MB for full video)

### AC 4: Video Hash Chain Structure for Privacy Mode
**Given** video recording in Privacy Mode
**When** computing hash chain
**Then**:
1. Each frame hash includes: previous_hash + frame_data + frame_index
2. Chain starts with seed hash (device ID + capture timestamp)
3. Chain integrity verified locally before upload
4. Chain includes keyframe markers for depth frames
5. Checkpoint attestations every 5 seconds reference chain state
6. Final hash matches computed media_hash

### AC 5: Backend Hash-Only Video Endpoint Extension
**Given** POST /api/v1/captures with mode: "hash_only" and media_type: "video"
**When** backend processes request
**Then**:
1. Validates assertion signature covers payload
2. Verifies hash chain integrity (chain_intact computed)
3. Validates temporal depth analysis results
4. Verifies checkpoint attestations match hash chain state
5. Stores capture with capture_mode: "hash_only", media_stored: false
6. No S3 upload occurs (video never touches server)
7. Response includes capture_id and verification_url
8. Processing completes in < 5 seconds

### AC 6: Video Hash-Only Evidence Package
**Given** a hash-only video capture is stored
**When** generating evidence package
**Then** evidence includes:
1. `hardware_attestation`: Device attestation status
2. `depth_analysis`: Temporal depth analysis with keyframe count
3. `hash_chain`: Chain integrity status, checkpoint count
4. `video_metadata`: Duration, frame count, frame rate
5. `metadata`: Per metadata_flags privacy settings
6. `analysis_source`: "device"
7. `capture_mode`: "hash_only"
8. `media_stored`: false
9. Confidence calculation works identically to full video capture

### AC 7: Video Hash-Only Verification Display
**Given** a user views a hash-only video capture verification page
**When** page loads
**Then**:
1. Shows "Video Hash Verified" badge
2. Shows Privacy Mode badge
3. Displays video metadata (duration, frame count)
4. Shows hash chain verification status with checkpoint count
5. Displays temporal depth analysis summary
6. Shows evidence panel with device analysis source
7. No video playback (no media stored)
8. Hash value displayed prominently
9. Confidence badge shows HIGH when all checks pass

### AC 8: Error Handling and Edge Cases
**Given** various video privacy mode scenarios
**When** errors occur
**Then** appropriate handling:
1. Recording interrupted: Partial hash chain + checkpoint attestation preserved
2. Depth analysis fails: Degrades to hash-only without depth (MEDIUM confidence)
3. Assertion generation fails: Falls back to offline queue
4. Upload fails: Full retry with exponential backoff
5. Backend validation fails: Clear error message returned
6. Hash chain integrity check fails: Capture rejected with explanation

## Tasks / Subtasks

- [ ] Task 1: Extend VideoRecordingSession for Privacy Mode (AC: #1)
  - [ ] Detect Privacy Mode from PrivacySettingsManager
  - [ ] Add privacy mode indicator to recording UI
  - [ ] Ensure hash chain computed regardless of mode
  - [ ] Trigger client-side analysis on recording complete
  - [ ] File: ios/Rial/Core/Capture/VideoRecordingSession.swift

- [ ] Task 2: Implement Video Temporal Depth Analysis (AC: #2)
  - [ ] Extend DepthAnalysisService.swift for video
  - [ ] Add analyzeTemporalDepth(keyframes: [CVPixelBuffer]) method
  - [ ] Compute per-keyframe analysis results
  - [ ] Calculate temporal consistency metrics
  - [ ] Return TemporalDepthAnalysisResult struct
  - [ ] Performance target: < 2s for 15s video
  - [ ] File: ios/Rial/Core/Capture/DepthAnalysisService.swift

- [ ] Task 3: Create Video Hash-Only Payload Builder (AC: #3, #4)
  - [ ] Create VideoHashOnlyCapturePayload.swift model
  - [ ] Build payload from video, hash chain, depth analysis
  - [ ] Apply metadata filters per privacy settings
  - [ ] Generate assertion over complete payload
  - [ ] Validate payload size < 50KB
  - [ ] File: ios/Rial/Models/VideoHashOnlyCapturePayload.swift

- [ ] Task 4: Update UploadService for Video Privacy Mode (AC: #3, #8)
  - [ ] Detect video + privacy mode combination
  - [ ] Route to hash-only payload builder
  - [ ] Send POST /api/v1/captures with mode: "hash_only"
  - [ ] Handle video-specific error cases
  - [ ] Retain full video in local storage
  - [ ] File: ios/Rial/Core/Networking/UploadService.swift

- [ ] Task 5: Backend Video Hash-Only Endpoint (AC: #5)
  - [ ] Extend POST /api/v1/captures for video hash-only
  - [ ] Add VideoHashOnlyPayload struct
  - [ ] Validate hash chain integrity
  - [ ] Verify checkpoint attestations
  - [ ] Skip S3 upload for hash-only mode
  - [ ] File: backend/src/routes/captures.rs

- [ ] Task 6: Video Hash Chain Verifier for Privacy Mode (AC: #5, #6)
  - [ ] Add verify_hash_chain_privacy_mode function
  - [ ] Validate chain integrity from payload
  - [ ] Verify checkpoint attestations
  - [ ] Compute chain_intact status
  - [ ] File: backend/src/services/hash_chain_verifier.rs

- [ ] Task 7: Video Hash-Only Evidence Package (AC: #6)
  - [ ] Extend Evidence::from_hash_only for video type
  - [ ] Include temporal depth analysis
  - [ ] Include hash chain status
  - [ ] Include video metadata (duration, frames)
  - [ ] Set analysis_source: "device"
  - [ ] File: backend/src/services/evidence.rs

- [ ] Task 8: Update Verification Page for Video Hash-Only (AC: #7)
  - [ ] Extend verify/[id]/page.tsx for video hash-only
  - [ ] Display "Video Hash Verified" badge
  - [ ] Show hash chain status with checkpoint count
  - [ ] Display temporal depth analysis summary
  - [ ] Show video metadata (duration, frame count)
  - [ ] No video player (media not stored)
  - [ ] File: apps/web/src/app/verify/[id]/page.tsx

- [ ] Task 9: Update HashOnlyVerificationResult for Video (AC: #7)
  - [ ] Add video-specific display variant
  - [ ] Show temporal depth analysis summary
  - [ ] Display hash chain checkpoint count
  - [ ] Show frame count and duration
  - [ ] "Video Hash Verified" badge
  - [ ] File: apps/web/src/components/Evidence/HashOnlyVerificationResult.tsx

- [ ] Task 10: Video Privacy Mode Integration Tests (AC: all)
  - [ ] Test video recording in privacy mode
  - [ ] Test temporal depth analysis
  - [ ] Test hash-only payload construction
  - [ ] Test backend endpoint acceptance
  - [ ] Test verification page display
  - [ ] Test interrupted recording handling
  - [ ] File: ios/RialTests/PrivacyMode/VideoHashOnlyTests.swift

## Dev Notes

### Technical Approach

**Video Privacy Mode Flow:**
```
1. User enables Privacy Mode → records video
2. VideoRecordingSession computes hash chain (30fps)
3. DepthKeyframeBuffer extracts depth at 10fps
4. On recording complete:
   a. DepthAnalysisService.analyzeTemporalDepth(keyframes)
   b. Compute per-keyframe depth analysis
   c. Calculate temporal consistency metrics
   d. Build VideoHashOnlyCapturePayload
   e. Generate assertion over payload
5. UploadService sends hash-only payload (< 50KB)
6. Full video retained in encrypted local storage
7. Backend verifies, stores evidence (no S3)
8. User receives verification URL
```

**Temporal Depth Analysis Algorithm:**
```swift
struct TemporalDepthAnalysisResult: Codable {
    let keyframeAnalyses: [DepthAnalysisResult]  // Per-keyframe results
    let meanVariance: Float                       // Average depth variance
    let varianceStability: Float                  // Consistency across frames
    let temporalCoherence: Float                  // Edge coherence stability
    let isLikelyRealScene: Bool                   // All keyframes pass
    let keyframeCount: Int
    let algorithmVersion: String                  // "1.0"
}

// Temporal analysis
func analyzeTemporalDepth(keyframes: [CVPixelBuffer], rgbFrames: [CVPixelBuffer]) async throws -> TemporalDepthAnalysisResult {
    // 1. Analyze each keyframe individually
    var analyses: [DepthAnalysisResult] = []
    for (depth, rgb) in zip(keyframes, rgbFrames) {
        let analysis = try await analyze(depthMap: depth, rgbImage: rgb)
        analyses.append(analysis)
    }

    // 2. Compute temporal metrics
    let variances = analyses.map { $0.depthVariance }
    let meanVariance = variances.reduce(0, +) / Float(variances.count)
    let varianceStability = 1.0 - (standardDeviation(variances) / meanVariance)

    let coherences = analyses.map { $0.edgeCoherence }
    let temporalCoherence = coherences.reduce(0, +) / Float(coherences.count)

    // 3. Determine scene authenticity
    let isLikelyRealScene = analyses.allSatisfy { $0.isLikelyRealScene } &&
                            varianceStability > 0.8

    return TemporalDepthAnalysisResult(
        keyframeAnalyses: analyses,
        meanVariance: meanVariance,
        varianceStability: varianceStability,
        temporalCoherence: temporalCoherence,
        isLikelyRealScene: isLikelyRealScene,
        keyframeCount: keyframes.count,
        algorithmVersion: "1.0"
    )
}
```

**Video Hash-Only Payload Structure:**
```swift
// ios/Rial/Models/VideoHashOnlyCapturePayload.swift
struct VideoHashOnlyCapturePayload: Codable {
    let captureMode: String = "hash_only"
    let mediaHash: String                      // SHA-256 of video file
    let mediaType: String = "video"
    let hashChain: HashChainData
    let frameCount: Int
    let durationMs: Int
    let depthAnalysis: TemporalDepthAnalysisResult
    let checkpointAttestations: [CheckpointAttestation]
    let metadata: FilteredMetadata
    let metadataFlags: MetadataFlags
    let capturedAt: Date
    let assertion: String                      // Base64 DCAppAttest
}

struct HashChainData: Codable {
    let seedHash: String
    let finalHash: String
    let chainIntegrity: Bool                   // Pre-verified on device
    let frameHashes: [FrameHashEntry]          // Sparse: every 10th frame
    let keyframeIndices: [Int]                 // Depth keyframe positions
}

struct FrameHashEntry: Codable {
    let frameIndex: Int
    let hash: String
}

struct CheckpointAttestation: Codable {
    let timestamp: Date
    let frameIndex: Int
    let chainStateHash: String
    let assertion: String                      // DCAppAttest assertion
}
```

**Backend Validation Flow:**
```rust
// backend/src/routes/captures.rs
async fn handle_video_hash_only(
    payload: VideoHashOnlyPayload,
    device_id: Uuid,
    state: &AppState,
) -> Result<CreateCaptureResponse, ApiError> {
    // 1. Verify assertion signature
    verify_assertion(&payload.assertion, &device_id, &state.attestation_service).await?;

    // 2. Validate hash chain integrity
    let chain_status = verify_hash_chain_privacy_mode(
        &payload.hash_chain,
        &payload.media_hash,
    )?;

    // 3. Verify checkpoint attestations
    for checkpoint in &payload.checkpoint_attestations {
        verify_checkpoint_attestation(checkpoint, &device_id).await?;
    }

    // 4. Build evidence package
    let evidence = Evidence {
        hardware_attestation: HardwareAttestation {
            status: EvidenceStatus::Pass,
            level: "secure_enclave".to_string(),
            device_model: payload.metadata.device_model.clone(),
        },
        depth_analysis: DepthAnalysis {
            status: if payload.depth_analysis.is_likely_real_scene {
                EvidenceStatus::Pass
            } else {
                EvidenceStatus::Fail
            },
            depth_variance: payload.depth_analysis.mean_variance,
            temporal_coherence: Some(payload.depth_analysis.temporal_coherence),
            keyframe_count: Some(payload.depth_analysis.keyframe_count),
            is_likely_real_scene: payload.depth_analysis.is_likely_real_scene,
        },
        hash_chain: Some(HashChainEvidence {
            status: if chain_status.intact {
                EvidenceStatus::Pass
            } else {
                EvidenceStatus::Fail
            },
            chain_intact: chain_status.intact,
            checkpoint_count: payload.checkpoint_attestations.len(),
            frame_count: payload.frame_count,
        }),
        video_metadata: Some(VideoMetadata {
            duration_ms: payload.duration_ms,
            frame_count: payload.frame_count,
            frame_rate: 30.0,
        }),
        capture_mode: CaptureMode::HashOnly,
        media_stored: false,
        analysis_source: AnalysisSource::Device,
        metadata_flags: Some(payload.metadata_flags),
        // ... other fields
    };

    // 5. Calculate confidence
    let confidence = calculate_confidence(&evidence);

    // 6. Store capture (no S3 upload)
    let capture_id = store_hash_only_capture(
        device_id,
        &payload,
        &evidence,
        confidence,
        &state.db,
    ).await?;

    Ok(CreateCaptureResponse {
        capture_id,
        status: "complete".to_string(),
        capture_mode: "hash_only".to_string(),
        media_stored: false,
        verification_url: format!("/verify/{}", capture_id),
    })
}
```

**Verification Page Display:**
```tsx
// apps/web/src/app/verify/[id]/page.tsx
// Extend existing hash-only detection for video type

{captureData.capture_mode === 'hash_only' && (
  <div className="space-y-6">
    {/* Video Hash Verified Badge */}
    {captureData.media_type === 'video' && (
      <div className="flex items-center gap-2 text-green-600">
        <CheckCircleIcon className="h-6 w-6" />
        <span className="font-semibold">Video Hash Verified</span>
      </div>
    )}

    {/* Privacy Mode Badge */}
    <PrivacyModeBadge />

    {/* Hash Display */}
    <div className="bg-zinc-50 dark:bg-zinc-900 rounded-lg p-4">
      <div className="text-sm text-zinc-500">File Hash (SHA-256)</div>
      <div className="font-mono text-xs break-all">{captureData.media_hash}</div>
    </div>

    {/* Video Metadata */}
    {captureData.media_type === 'video' && (
      <div className="grid grid-cols-2 gap-4">
        <div>
          <span className="text-zinc-500">Duration:</span>{' '}
          {captureData.video_metadata.duration_ms / 1000}s
        </div>
        <div>
          <span className="text-zinc-500">Frames:</span>{' '}
          {captureData.video_metadata.frame_count}
        </div>
        <div>
          <span className="text-zinc-500">Hash Chain:</span>{' '}
          <span className={captureData.evidence.hash_chain.chain_intact ?
            'text-green-600' : 'text-red-600'}>
            {captureData.evidence.hash_chain.chain_intact ?
              `Verified (${captureData.evidence.hash_chain.checkpoint_count} checkpoints)` :
              'Failed'}
          </span>
        </div>
        <div>
          <span className="text-zinc-500">Temporal Depth:</span>{' '}
          <span className={captureData.evidence.depth_analysis.status === 'pass' ?
            'text-green-600' : 'text-red-600'}>
            {captureData.evidence.depth_analysis.keyframe_count} keyframes
          </span>
        </div>
      </div>
    )}

    {/* Evidence Panel */}
    <EvidencePanel
      evidence={captureData.evidence}
      isHashOnly={true}
      showPreview={false}
    />
  </div>
)}
```

### Performance Targets

| Metric | Target | Implementation |
|--------|--------|----------------|
| Temporal depth analysis | < 2s for 15s video | Metal GPU acceleration for batch processing |
| Hash-only payload size | < 50KB | Sparse frame hashes (every 10th frame) |
| Backend processing | < 5s | Skip S3, parallel verification |
| Local storage | < 100MB/video | AES-GCM encryption, user's device |

### Data Models

**iOS Models:**
```
ios/Rial/Models/
  VideoHashOnlyCapturePayload.swift       # NEW - Video privacy mode payload
  TemporalDepthAnalysisResult.swift       # NEW - Temporal analysis result
```

**Backend Models:**
```rust
// backend/src/models/capture.rs
pub struct VideoHashOnlyPayload {
    pub media_hash: String,
    pub hash_chain: HashChainData,
    pub frame_count: i32,
    pub duration_ms: i32,
    pub depth_analysis: TemporalDepthAnalysis,
    pub checkpoint_attestations: Vec<CheckpointAttestation>,
    pub metadata: serde_json::Value,
    pub metadata_flags: MetadataFlags,
    pub captured_at: DateTime<Utc>,
    pub assertion: String,
}

pub struct TemporalDepthAnalysis {
    pub mean_variance: f32,
    pub variance_stability: f32,
    pub temporal_coherence: f32,
    pub is_likely_real_scene: bool,
    pub keyframe_count: i32,
    pub algorithm_version: String,
}
```

### Project Structure Notes

**iOS Extensions:**
```
ios/Rial/
  Core/
    Capture/
      DepthAnalysisService.swift           # MODIFY - Add temporal analysis
      VideoRecordingSession.swift          # MODIFY - Privacy mode detection
    Networking/
      UploadService.swift                  # MODIFY - Video hash-only routing
  Models/
    VideoHashOnlyCapturePayload.swift      # NEW - Video privacy payload
    TemporalDepthAnalysisResult.swift      # NEW - Temporal result struct
```

**Backend Extensions:**
```
backend/src/
  routes/
    captures.rs                            # MODIFY - Video hash-only endpoint
  services/
    hash_chain_verifier.rs                 # MODIFY - Privacy mode verification
    evidence.rs                            # MODIFY - Video hash-only evidence
  models/
    capture.rs                             # MODIFY - VideoHashOnlyPayload
```

**Web Extensions:**
```
apps/web/src/
  app/verify/[id]/
    page.tsx                               # MODIFY - Video hash-only display
  components/Evidence/
    HashOnlyVerificationResult.tsx         # MODIFY - Video variant
```

### Algorithm Parity Requirements

**Critical:** Temporal depth analysis on iOS must match server-side algorithm:

1. **Per-keyframe analysis:** Same thresholds as Story 8-1
   - Variance > 0.5, layers >= 3, coherence > 0.7
2. **Temporal consistency:** Variance stability > 0.8
3. **Deterministic:** Same keyframes → same result
4. **Version tracking:** "1.0" for both client and server

**Testing Strategy:**
- Record test video with known depth characteristics
- Run client-side temporal analysis
- Compare with server-side analysis on same depth keyframes
- Assert: meanVariance, varianceStability, temporalCoherence within 0.01

### Security Considerations

**Trust Model:**
- DCAppAttest assertion covers entire video hash-only payload
- Hash chain proves frame integrity (no insertion/deletion)
- Checkpoint attestations prove capture continuity
- Temporal depth analysis proves 3D scene across time
- Server trusts attested device's computation

**Threat Mitigation:**
| Threat | Defense |
|--------|---------|
| Video file substitution | Hash mismatch detected |
| Frame insertion/deletion | Hash chain breaks |
| Fake depth analysis | Secure Enclave signature required |
| Recording interrupted | Checkpoint attestations preserve partial evidence |

### Error Handling Strategy

**Graceful Degradation:**
1. **No depth available:** Hash-only without depth (MEDIUM confidence)
2. **Partial keyframes:** Use available frames, note incomplete
3. **Attestation fails:** Offline queue with retry
4. **Upload fails:** Exponential backoff, preserve local copy
5. **Chain integrity fails:** Reject with clear message

### References

- **Epic:** [Source: docs/epics.md - Epic 8: Privacy-First Capture Mode]
  - Story 8.8: Video Privacy Mode Support (lines 3106-3130)
  - Extends hash-only capture to video with temporal depth analysis
- **Tech Spec:** [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-8.md]
  - Section: Story 8.8 Acceptance Criteria (lines 676-683)
  - AC 8.8.1: Hash chain computed locally
  - AC 8.8.2: Temporal depth analysis on-device
  - AC 8.8.3: Video hash-only payload accepted
  - AC 8.8.4: Verification shows video metadata
  - Section: Video Privacy Mode Flow (lines 510-518)
  - Section: Video Hash-Only Payload (lines 165-196)
  - Section: Backend Hash-Only Mode Handling (lines 197-247)
- **PRD:** [Source: docs/prd.md]
  - FR56-62: Privacy Mode functional requirements
  - FR58: Hash-only uploads with device depth analysis
  - FR60: Backend accepts pre-computed analysis
  - Video capture requirements (FR47-55)
- **Architecture:** [Source: docs/architecture.md]
  - Video capture architecture (lines 211-212)
  - Hash chain service pattern
  - Checkpoint attestation flow
- **Previous Stories:**
  - Story 8-1: Client-side depth analysis service (foundation)
  - Story 8-3: Hash-only capture payload (photo pattern)
  - Story 8-4: Backend hash-only endpoint (photo handling)
  - Epic 7 Stories: Video capture infrastructure (7-1 through 7-14)
  - Story 7-4: Frame hash chain (reused for privacy mode)
  - Story 7-5: Video attestation checkpoints (extended for hash-only)

## Learnings from Previous Stories

Based on Story 8-1 (Client-Side Depth Analysis):
1. **Algorithm Parity Critical:** Ensure exact threshold matching with backend
2. **Performance Target:** < 500ms per frame, batch processing for video
3. **Deterministic Results:** Version tracking essential for reproducibility
4. **GPU Acceleration:** Metal shaders for performance on keyframe batches
5. **Edge Coherence Computation:** Sobel operator on both depth and RGB

Based on Story 8-3 (Hash-Only Capture Payload):
1. **Assertion Coverage:** DCAppAttest must sign entire payload
2. **Metadata Filtering:** Apply privacy settings before payload construction
3. **Local Retention:** Full media retained on device even after hash upload
4. **Payload Size:** Keep under limits (50KB for video with sparse hashes)
5. **Metadata Flags:** Document what was included/excluded

Based on Story 8-4 (Backend Hash-Only Endpoint):
1. **Validation Order:** Assertion → Hash verification → Store
2. **Skip S3 Upload:** No media storage for hash-only mode
3. **Evidence Source Field:** Mark as "device" for client-computed analysis
4. **Confidence Calculation:** Same HIGH threshold as full captures
5. **Error Responses:** Clear validation failure messages

Based on Epic 7 (Video Capture):
1. **Hash Chain Pattern:** Reuse HashChainService from Story 7-4
2. **Checkpoint Attestations:** Extend VideoAttestationService for hash-only
3. **Keyframe Extraction:** 10fps depth already implemented in DepthKeyframeBuffer
4. **Interrupted Handling:** Checkpoint attestations preserve partial evidence
5. **Backend Verification:** Hash chain verifier exists, extend for privacy mode
6. **Temporal Analysis:** Backend already has video_depth_analysis.rs pattern
7. **C2PA Video:** Not needed for hash-only (no manifest embedding)
8. **Verification Display:** Extend existing video verification page components

Based on Story 8-7 (File Verification Hash-Only):
1. **Hash-Only Display Pattern:** Reuse HashOnlyVerificationResult component
2. **Video Variant:** Component already supports video-specific fields
3. **Hash Chain Display:** Show checkpoint count and integrity status
4. **Temporal Depth Display:** Show keyframe count and consistency score
5. **No Media Preview:** Consistent with hash-only philosophy
6. **Privacy Mode Badge:** Reuse existing badge component
7. **Trust Model Messaging:** Use established "device attestation" language
8. **Evidence Panel Extension:** Show "(Device)" suffix for analysis source
9. **Metadata Flags Handling:** Respect privacy settings in display
10. **File Upload Support:** Video hash-only files verifiable via upload

Key Patterns to Apply:
- **Privacy Mode Detection:** Check PrivacySettingsManager.shared.settings.privacyModeEnabled
- **Temporal Extension:** Batch process keyframes through DepthAnalysisService
- **Payload Construction:** Follow HashOnlyCapturePayload pattern from Story 8-3
- **Upload Routing:** Detect video + privacy mode, route to hash-only builder
- **Backend Extension:** Add video handling to existing hash-only endpoint
- **Verification Display:** Extend hash-only page variant for video metadata
- **Error Handling:** Graceful degradation with checkpoint preservation

---

_Story created: 2025-12-01_
_Depends on: Story 8-1 (client-side depth analysis), Story 8-3 (hash-only payload), Story 8-4 (backend hash-only), Epic 7 (video infrastructure)_
_Completes: Epic 8 Privacy-First Capture Mode_

---

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

claude-sonnet-4-5-20250929

### Debug Log References

### Completion Notes List

### File List
