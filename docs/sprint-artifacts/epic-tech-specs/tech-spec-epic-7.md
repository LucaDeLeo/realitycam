# Epic Technical Specification: Video Capture with LiDAR Depth

Date: 2025-11-26
Author: Luca
Epic ID: 7
Status: Draft

---

## Overview

Epic 7 extends the photo capture system to record authenticated video with continuous frame-by-frame LiDAR depth data. This enables verification of dynamic real-world events that single-frame analysis cannot adequately assess. Users can capture short video clips (up to 15 seconds) with the same hardware attestation and depth verification as photos.

The epic builds on the native Swift implementation from Epic 6, leveraging ARKit's unified RGB+depth capture for perfect frame synchronization. Key innovations include:
- **10fps depth keyframes** for manageable file sizes (~10MB compressed)
- **Frame hash chain** for tamper-evident integrity (no frames can be inserted, removed, or reordered)
- **Checkpoint attestation** for partial video recovery on interruption
- **Edge-only depth overlay** for minimal performance impact during recording

**Business Value:** Users can capture verified video evidence of incidents, events, or processes. The temporal depth analysis detects manipulation attempts that single-frame analysis would miss (e.g., spliced footage, inserted frames).

**FRs Covered:** FR47-FR55 (Video Capture)

## Objectives and Scope

### Objectives

1. **Video Recording with Depth** - Capture 30fps video with synchronized 10fps LiDAR depth keyframes
2. **Hash Chain Integrity** - Cryptographically chain every frame to prevent tampering
3. **Checkpoint Attestation** - Enable partial video verification on recording interruption
4. **Edge Depth Overlay** - Real-time depth visualization without performance degradation
5. **Temporal Depth Analysis** - Backend detection of depth inconsistencies across frames
6. **C2PA Video Support** - Generate Content Credentials manifests for video files

### In Scope

| Component | Scope |
|-----------|-------|
| iOS App | Video recording session, depth keyframe extraction, edge overlay, hash chain, attestation |
| Backend | Video upload endpoint, hash chain verification, temporal depth analysis, evidence package |
| Web | Video verification page with playback and evidence display |
| C2PA | Video manifest generation and MP4 embedding |

### Out of Scope

- Extended duration beyond 15 seconds (post-MVP)
- Delta compression for depth data (v2 optimization)
- Full colormap overlay during recording (performance)
- Audio capture and analysis
- Gyroscope/accelerometer correlation (post-MVP)

## System Architecture Alignment

### Components Referenced

| Component | Location | Role |
|-----------|----------|------|
| iOS Video Recording | `ios/Rial/Core/Capture/VideoRecordingSession.swift` | ARKit + AVAssetWriter integration |
| Depth Keyframe Buffer | `ios/Rial/Core/Capture/DepthKeyframeBuffer.swift` | 10fps depth extraction and storage |
| Hash Chain Service | `ios/Rial/Core/Crypto/HashChainService.swift` | Frame-by-frame hash chaining |
| Video Attestation | `ios/Rial/Core/Attestation/VideoAttestationService.swift` | Checkpoint and final attestation |
| Edge Overlay Shader | `ios/Rial/Shaders/EdgeDepthVisualization.metal` | Sobel edge detection on depth |
| Backend Video Routes | `backend/src/routes/captures_video.rs` | Video upload and processing |
| Video Depth Analysis | `backend/src/services/video_depth_analysis.rs` | Temporal depth consistency checks |
| Hash Chain Verifier | `backend/src/services/hash_chain_verifier.rs` | Chain integrity verification |
| Video Verification Page | `apps/web/src/app/verify/[id]/video/page.tsx` | Video playback with evidence |

### Architecture Patterns Applied

1. **ARKit Unified Capture (ADR-002):** Video uses same ARSession as photo for synchronized RGB+depth
2. **Hash Chain Integrity (New):** Each frame's hash includes previous frame's hash
3. **Checkpoint Attestation (New):** 5-second intervals for partial video recovery
4. **Edge-Only Overlay (Performance):** Sobel edge detection instead of full colormap

### Technology Stack

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| Video Encoding | AVAssetWriter | iOS 15+ | H.264/HEVC encoding during capture |
| Depth Capture | ARKit | iOS 15+ | sceneDepth at 30fps |
| Edge Detection | Metal | iOS 15+ | Sobel edge shader for overlay |
| Hash Chain | CryptoKit | iOS 15+ | SHA256 for frame hashing |
| Attestation | DCAppAttest | iOS 14+ | Checkpoint and final signing |
| Video Processing | ffmpeg/rust bindings | - | Backend frame extraction |
| Depth Analysis | image crate | - | Optical flow, depth comparison |
| C2PA Video | c2pa-rs | 0.51.x | MP4 manifest embedding |

### Constraints

- **15-second maximum** - Thermal throttling, file size, UX considerations
- **10fps depth keyframes** - Balance between coverage and size (150 frames max)
- **Edge overlay only** - Full colormap exceeds performance budget during recording
- **30fps hash chain** - All frames chained (450 hashes for 15s)
- **H.264/HEVC only** - C2PA MP4 support requirements

## Detailed Design

### Services and Modules

#### iOS Video Recording

| File | Location | Responsibilities |
|------|----------|------------------|
| VideoRecordingSession.swift | `Core/Capture/` | ARSession + AVAssetWriter coordination |
| DepthKeyframeBuffer.swift | `Core/Capture/` | Extract, store, index depth at 10fps |
| HashChainService.swift | `Core/Crypto/` | Compute frame hashes, maintain chain |
| VideoAttestationService.swift | `Core/Attestation/` | Checkpoint and final attestation |
| EdgeDepthVisualization.metal | `Shaders/` | Sobel edge detection for overlay |
| VideoProcessingPipeline.swift | `Core/Capture/` | Package video, depth, chain for upload |

#### Backend Services

| File | Location | Responsibilities |
|------|----------|------------------|
| captures_video.rs | `routes/` | Video upload endpoint |
| video_depth_analysis.rs | `services/` | Temporal depth consistency |
| hash_chain_verifier.rs | `services/` | Recompute and verify chain |
| video_evidence.rs | `services/` | Assemble video evidence package |
| c2pa_video.rs | `services/` | Generate and embed video manifest |

### Data Models and Contracts

#### Video Capture Data Model (Swift)

```swift
// Core/Models/VideoCapture.swift

struct VideoCapture {
    let id: UUID
    let videoURL: URL                    // Local MP4/MOV file
    let depthData: DepthKeyframeData     // Compressed depth blob
    let hashChain: HashChainData         // All intermediate hashes
    let attestation: VideoAttestation    // Final or checkpoint attestation
    let metadata: VideoMetadata
    let status: CaptureStatus
    let createdAt: Date
}

struct DepthKeyframeData {
    let frames: [DepthKeyframe]          // 10fps, up to 150 frames
    let resolution: CGSize               // 256x192
    let compressedBlob: Data             // Gzipped Float32 array
}

struct DepthKeyframe {
    let index: Int                       // 0-based frame index
    let timestamp: TimeInterval          // Video timestamp
    let offset: Int                      // Offset in blob
}

struct HashChainData {
    let frameHashes: [Data]              // All frame hashes (30fps)
    let checkpoints: [HashCheckpoint]    // Every 5 seconds
    let finalHash: Data                  // Last frame hash
}

struct HashCheckpoint {
    let index: Int                       // 0=5s, 1=10s, 2=15s
    let frameNumber: Int                 // Frame at checkpoint
    let hash: Data                       // Chain hash at this point
    let timestamp: TimeInterval          // Video timestamp
}

struct VideoAttestation {
    let finalHash: Data                  // Hash that was attested
    let assertion: Data                  // DCAppAttest signature
    let durationMs: Int64                // Attested duration
    let frameCount: Int                  // Attested frame count
    let isPartial: Bool                  // True if interrupted
    let checkpointIndex: Int?            // Which checkpoint (if partial)
}

struct VideoMetadata: Codable {
    let type: String = "video"
    let startedAt: Date
    let endedAt: Date
    let durationMs: Int64
    let frameCount: Int
    let depthKeyframeCount: Int
    let resolution: Resolution
    let codec: String                    // "h264" or "hevc"
    let deviceModel: String
    let location: CaptureLocation?
    let attestationLevel: String
    let hashChainFinal: String           // Base64
    let assertion: String                // Base64
}
```

#### Backend Models (Rust)

```rust
// models/video_capture.rs

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoCapture {
    pub id: Uuid,
    pub device_id: Uuid,
    pub video_key: String,           // S3 key for video
    pub depth_key: String,           // S3 key for depth blob
    pub hash_chain_key: String,      // S3 key for hash chain
    pub metadata: VideoMetadata,
    pub evidence: Option<VideoEvidence>,
    pub confidence_level: Option<ConfidenceLevel>,
    pub status: CaptureStatus,
    pub captured_at: DateTime<Utc>,
    pub uploaded_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoDepthAnalysis {
    // Per-frame metrics (sampled at 1fps)
    pub frame_analyses: Vec<FrameDepthAnalysis>,

    // Temporal metrics
    pub depth_consistency: f32,       // 0-1: depth stable across frames
    pub motion_coherence: f32,        // 0-1: depth motion matches RGB
    pub scene_stability: f32,         // 0-1: no impossible depth jumps

    // Aggregate
    pub is_likely_real_scene: bool,
    pub suspicious_frames: Vec<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashChainVerification {
    pub status: VerificationStatus,   // Pass, Fail, Partial
    pub verified_frames: u32,
    pub total_frames: u32,
    pub chain_intact: bool,
    pub attestation_valid: bool,
    pub partial_reason: Option<String>,
    pub verified_duration_ms: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoEvidence {
    pub r#type: String,               // "video"
    pub duration_ms: u64,
    pub frame_count: u32,

    pub hardware_attestation: AttestationEvidence,
    pub hash_chain: HashChainVerification,
    pub depth_analysis: VideoDepthAnalysis,
    pub metadata: MetadataEvidence,
    pub partial_attestation: PartialAttestationInfo,
}
```

### APIs and Interfaces

#### Video Upload Endpoint

```rust
// POST /api/v1/captures/video
// Content-Type: multipart/form-data

// Parts:
// - video: MP4/MOV binary (~20MB)
// - depth_data: gzipped depth keyframes (~10MB)
// - hash_chain: JSON with frame hashes and checkpoints
// - metadata: JSON with attestation

#[derive(Debug, Deserialize)]
pub struct VideoUploadMetadata {
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub duration_ms: u64,
    pub frame_count: u32,
    pub depth_keyframe_count: u32,
    pub resolution: Resolution,
    pub codec: String,
    pub device_model: String,
    pub location: Option<CaptureLocation>,
    pub attestation_level: String,
    pub hash_chain_final: String,      // Base64
    pub assertion: String,             // Base64 DCAppAttest
    pub checkpoints: Vec<HashCheckpoint>,
    pub is_partial: bool,
}

#[derive(Debug, Serialize)]
pub struct VideoUploadResponse {
    pub capture_id: Uuid,
    pub r#type: String,                // "video"
    pub status: String,                // "processing"
    pub verification_url: String,
}
```

#### Hash Chain Computation (Swift)

```swift
// Core/Crypto/HashChainService.swift

actor HashChainService {
    private var previousHash: Data? = nil
    private var frameHashes: [Data] = []
    private var checkpoints: [HashCheckpoint] = []

    func processFrame(
        rgbBuffer: CVPixelBuffer,
        depthBuffer: CVPixelBuffer?,
        timestamp: TimeInterval,
        frameNumber: Int
    ) async -> Data {
        // Compute hash of current frame
        var hasher = SHA256()

        // Add RGB data
        hasher.update(data: extractPixelData(rgbBuffer))

        // Add depth data (if available at this frame)
        if let depth = depthBuffer {
            hasher.update(data: extractDepthData(depth))
        }

        // Add timestamp
        var ts = timestamp
        hasher.update(data: Data(bytes: &ts, count: MemoryLayout<TimeInterval>.size))

        // Chain with previous hash
        if let prev = previousHash {
            hasher.update(data: prev)
        }

        let hash = Data(hasher.finalize())
        frameHashes.append(hash)
        previousHash = hash

        // Checkpoint every 5 seconds (150 frames at 30fps)
        if frameNumber > 0 && frameNumber % 150 == 0 {
            let checkpointIndex = (frameNumber / 150) - 1
            checkpoints.append(HashCheckpoint(
                index: checkpointIndex,
                frameNumber: frameNumber,
                hash: hash,
                timestamp: timestamp
            ))
        }

        return hash
    }

    func getChainData() -> HashChainData {
        return HashChainData(
            frameHashes: frameHashes,
            checkpoints: checkpoints,
            finalHash: previousHash ?? Data()
        )
    }

    func reset() {
        previousHash = nil
        frameHashes = []
        checkpoints = []
    }
}
```

#### Edge Detection Shader (Metal)

```metal
// Shaders/EdgeDepthVisualization.metal

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Sobel edge detection on depth buffer
fragment float4 edgeDepthFragment(
    VertexOut in [[stage_in]],
    texture2d<float> depthTexture [[texture(0)]],
    constant float& nearPlane [[buffer(0)]],
    constant float& farPlane [[buffer(1)]],
    constant float& edgeThreshold [[buffer(2)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float2 texelSize = 1.0 / float2(depthTexture.get_width(), depthTexture.get_height());

    // Sample 3x3 neighborhood
    float tl = depthTexture.sample(s, in.texCoord + float2(-1, -1) * texelSize).r;
    float tm = depthTexture.sample(s, in.texCoord + float2( 0, -1) * texelSize).r;
    float tr = depthTexture.sample(s, in.texCoord + float2( 1, -1) * texelSize).r;
    float ml = depthTexture.sample(s, in.texCoord + float2(-1,  0) * texelSize).r;
    float mr = depthTexture.sample(s, in.texCoord + float2( 1,  0) * texelSize).r;
    float bl = depthTexture.sample(s, in.texCoord + float2(-1,  1) * texelSize).r;
    float bm = depthTexture.sample(s, in.texCoord + float2( 0,  1) * texelSize).r;
    float br = depthTexture.sample(s, in.texCoord + float2( 1,  1) * texelSize).r;

    // Sobel operators
    float gx = (tr + 2*mr + br) - (tl + 2*ml + bl);
    float gy = (bl + 2*bm + br) - (tl + 2*tm + tr);
    float edge = sqrt(gx*gx + gy*gy);

    // Normalize depth for color
    float center = depthTexture.sample(s, in.texCoord).r;
    float normalizedDepth = saturate((center - nearPlane) / (farPlane - nearPlane));

    // Edge color based on depth (near=cyan, far=magenta)
    float3 nearColor = float3(0.0, 1.0, 1.0);  // Cyan
    float3 farColor = float3(1.0, 0.0, 1.0);   // Magenta
    float3 edgeColor = mix(nearColor, farColor, normalizedDepth);

    // Only show edges above threshold
    float alpha = edge > edgeThreshold ? 0.8 : 0.0;

    return float4(edgeColor, alpha);
}
```

### Workflows and Sequencing

#### Video Recording Flow

```
User                 CaptureView       VideoRecordingSession    HashChainService    DepthKeyframeBuffer
  |                      |                      |                      |                      |
  |  Hold record button  |                      |                      |                      |
  |--------------------->|                      |                      |                      |
  |                      |  startRecording()    |                      |                      |
  |                      |--------------------->|                      |                      |
  |                      |                      |  AVAssetWriter.start |                      |
  |                      |                      |                      |                      |
  |                      |                      |  [ARKit frame loop]  |                      |
  |                      |                      |                      |                      |
  |                      |  <-- onFrame(rgb, depth, timestamp) ------->|                      |
  |                      |                      |                      |                      |
  |                      |                      |  processFrame()      |                      |
  |                      |                      |--------------------->|                      |
  |                      |                      |  hash (chained)      |                      |
  |                      |                      |<---------------------|                      |
  |                      |                      |                      |                      |
  |                      |                      |  (every 3rd frame)   |                      |
  |                      |                      |  appendDepthFrame()  |                      |
  |                      |                      |--------------------->|--------------------->|
  |                      |                      |                      |                      |
  |                      |  [15s elapsed or button release]            |                      |
  |                      |                      |                      |                      |
  |  Release button      |                      |                      |                      |
  |--------------------->|                      |                      |                      |
  |                      |  stopRecording()     |                      |                      |
  |                      |--------------------->|                      |                      |
  |                      |                      |  AVAssetWriter.finish|                      |
  |                      |                      |                      |                      |
  |                      |                      |  generateAttestation()|                     |
  |                      |                      |--------------------->|                      |
  |                      |                      |  DCAppAttest.sign(finalHash)               |
  |                      |                      |                      |                      |
  |                      |  VideoCapture (complete)                    |                      |
  |                      |<--------------------|                      |                      |
  |                      |                      |                      |                      |
  |                      |  Navigate to Preview |                      |                      |
  |<---------------------|                      |                      |                      |
```

#### Recording Interruption Flow

```
Recording in progress (8 seconds elapsed)
         |
         |  [Phone call / App backgrounded]
         |
         V
+--------------------+
| Interruption       |
| Detected           |
+--------------------+
         |
         V
+--------------------+
| Check last         |
| checkpoint         |
| (5s = checkpoint 0)|
+--------------------+
         |
         V
+--------------------+
| Sign checkpoint    |
| hash with          |
| DCAppAttest        |
+--------------------+
         |
         V
+--------------------+
| Save partial       |
| VideoCapture       |
| isPartial = true   |
| checkpointIndex = 0|
+--------------------+
         |
         V
+--------------------+
| On resume:         |
| Show preview with  |
| "5s of 8s verified"|
+--------------------+
```

## Non-Functional Requirements

### Performance

| Metric | Target | Measurement |
|--------|--------|-------------|
| Recording frame rate | 30fps maintained | FPS counter |
| Edge overlay latency | < 3ms per frame | GPU profiler |
| Hash chain computation | < 5ms per frame | CPU profiler |
| Depth extraction (10fps) | < 10ms per frame | CPU profiler |
| Video encoding | Real-time (no dropped frames) | AVAssetWriter stats |
| Local processing | < 5 seconds post-recording | Total duration |
| Memory during recording | < 300MB | Memory profiler |
| Battery impact | < 2x photo capture rate | Energy gauge |

### Performance Strategies

1. **Edge-only overlay** - Sobel edge detection ~3x faster than full colormap
2. **10fps depth capture** - Reduces memory and storage by 66% vs 30fps
3. **Background hash computation** - Dedicated queue for SHA256 chains
4. **Streaming video encoding** - AVAssetWriter writes directly to disk
5. **Lazy depth compression** - Compress after recording, not during

### Security

| Aspect | Implementation | Rationale |
|--------|----------------|-----------|
| Frame chain integrity | SHA256 chain with previous hash | Detects any tampering |
| Checkpoint attestation | DCAppAttest every 5s | Partial recovery |
| Hash binding | Attestation signs final/checkpoint hash | Proves video is from device |
| Temporal binding | Timestamps in hash input | Proves when frames were captured |

### Threat Mitigations (Video)

| Threat | Mitigation |
|--------|------------|
| Frame insertion | Hash chain breaks if foreign frame inserted |
| Frame removal | Hash chain breaks if any frame removed |
| Frame reordering | Previous hash in chain prevents reordering |
| Splice attack | Depth motion coherence detects temporal discontinuities |
| Video replay | Assertion counter prevents replay of old attestations |
| Recording interruption | Checkpoint attestation preserves partial evidence |

### Reliability

| Scenario | Behavior | Recovery |
|----------|----------|----------|
| Phone call during recording | Checkpoint attestation, save partial | User sees "5s of 12s verified" |
| App crash during recording | Data may be lost | User informed, can retry |
| Low storage during recording | Recording stops early | Attest what was captured |
| Thermal throttling | FPS may drop | Recording continues at reduced rate |
| ARSession interrupted | Recording stops | Checkpoint attestation if available |

## Dependencies and Integrations

### External Dependencies

| Dependency | Version | Purpose | Notes |
|------------|---------|---------|-------|
| AVFoundation | iOS 15+ | Video encoding | Built-in |
| ARKit | iOS 15+ | Depth capture | Built-in |
| Metal | iOS 15+ | Edge overlay | Built-in |
| CryptoKit | iOS 15+ | Hash chain | Built-in |
| DCAppAttest | iOS 14+ | Attestation | Built-in |
| c2pa-rs | 0.51.x | Video manifest | Backend |
| ffmpeg-next | latest | Frame extraction | Backend, video verification |

### Internal Dependencies (From Epic 6)

| Dependency | Location | Usage |
|------------|----------|-------|
| ARCaptureSession | `Core/Capture/` | Base class for video session |
| CryptoService | `Core/Crypto/` | SHA256 implementation |
| KeychainService | `Core/Storage/` | Attestation key access |
| UploadService | `Core/Networking/` | Background video upload |
| CaptureStore | `Core/Storage/` | CoreData persistence |

### New Backend Dependencies

| Dependency | Purpose |
|------------|---------|
| ffmpeg-next | Extract frames from video for hash verification |
| image | Optical flow computation |
| rayon | Parallel frame processing |

## Acceptance Criteria (Authoritative)

### AC-7.1: Video Recording with Depth

**Given** user has selected video mode on capture screen
**When** user presses and holds record button
**Then**:
- Recording starts at 30fps with haptic feedback
- ARSession captures RGB and depth per frame
- Timer shows elapsed time (0:00 → 0:15)
- Recording auto-stops at 15 seconds

### AC-7.2: Depth Keyframe Extraction

**Given** video recording is in progress
**When** frames are captured at 30fps
**Then**:
- Depth extracted every 3rd frame (10fps)
- 150 depth keyframes maximum for 15s video
- Each keyframe indexed by video timestamp
- Total depth data ~10MB compressed

### AC-7.3: Edge Depth Overlay

**Given** video mode with depth overlay enabled
**When** recording is in progress
**Then**:
- Edge-only overlay renders at 30fps
- Overlay does NOT appear in recorded video
- Toggle button controls overlay visibility
- CPU/GPU impact within performance budget

### AC-7.4: Frame Hash Chain

**Given** video recording is in progress
**When** each frame is captured
**Then**:
- Hash computed: SHA256(frame + depth + timestamp + prevHash)
- All 30fps frames included in chain (450 for 15s)
- Checkpoints saved at 5s, 10s, 15s

### AC-7.5: Normal Recording Completion

**Given** user completes 15s recording (or releases early)
**When** recording finishes normally
**Then**:
- Final hash signed with DCAppAttest assertion
- Full hash chain saved
- VideoCapture with isPartial=false created

### AC-7.6: Interrupted Recording

**Given** recording is interrupted (phone call, background)
**When** interruption occurs at 12 seconds
**Then**:
- Last checkpoint (10s) hash is attested
- VideoCapture with isPartial=true, checkpointIndex=1 created
- Preview shows "Verified: 10s of 12s recorded"

### AC-7.7: Video Upload

**Given** video capture is ready for upload
**When** upload initiated
**Then**:
- Multipart upload: video + depth + chain + metadata
- Background upload survives app termination
- Progress tracked in history view

### AC-7.8: Hash Chain Verification (Backend)

**Given** backend receives video with hash chain
**When** verification runs
**Then**:
- Recompute chain from video frames + depth
- Compare to submitted chain
- Verify attested hash matches computed
- Report any chain breaks

### AC-7.9: Temporal Depth Analysis (Backend)

**Given** backend receives video with depth keyframes
**When** depth analysis runs
**Then**:
- Compute depth_consistency (stable across frames)
- Compute motion_coherence (depth motion matches RGB)
- Compute scene_stability (no impossible jumps)
- Flag suspicious frames

### AC-7.10: Video Evidence Package

**Given** all video checks complete
**When** evidence package assembled
**Then**:
- Includes hardware attestation, hash chain, depth analysis
- Includes partial attestation info if applicable
- Confidence level calculated

### AC-7.11: C2PA Video Manifest

**Given** video evidence package complete
**When** C2PA generation runs
**Then**:
- Valid C2PA manifest per spec 2.0
- Embedded in MP4 per ISO Base Media File Format
- Includes all evidence assertions

### AC-7.12: Video Verification Page

**Given** user opens video verification URL
**When** page loads
**Then**:
- Video player with playback controls
- Confidence badge overlay
- Hash chain status display
- Depth analysis temporal metrics
- Partial attestation explanation if applicable

### AC-7.13: Video Capture UI

**Given** capture screen displayed
**When** user views mode options
**Then**:
- Photo/Video toggle available
- Video mode shows hold-to-record button
- Timer shows remaining time
- Cannot switch modes while recording

## Traceability Mapping

| AC | FR | Story | Component | Test Approach |
|----|-----|-------|-----------|---------------|
| AC-7.1 | FR47 | 7.1 | VideoRecordingSession | Integration test on device |
| AC-7.2 | FR47 | 7.2 | DepthKeyframeBuffer | Unit test with mock frames |
| AC-7.3 | FR48 | 7.3 | EdgeDepthVisualization.metal | Visual test on device |
| AC-7.4 | FR49 | 7.4 | HashChainService | Unit test with fixtures |
| AC-7.5 | FR50 | 7.5 | VideoAttestationService | Integration test on device |
| AC-7.6 | FR50 | 7.5 | VideoAttestationService | Integration test with interruption |
| AC-7.7 | FR51 | 7.7, 7.8 | UploadService | Integration test |
| AC-7.8 | FR52 | 7.10 | hash_chain_verifier.rs | Unit test with fixtures |
| AC-7.9 | FR53 | 7.9 | video_depth_analysis.rs | Unit test with sample videos |
| AC-7.10 | FR52, FR53 | 7.11 | video_evidence.rs | Integration test |
| AC-7.11 | FR54 | 7.12 | c2pa_video.rs | Unit test with c2pa verification |
| AC-7.12 | FR55 | 7.13 | verify/[id]/video/page.tsx | E2E test |
| AC-7.13 | - | 7.14 | CaptureView | Component test |

## Risks, Assumptions, Open Questions

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **R1:** Thermal throttling during 15s recording | Medium | Medium | Early stop option, checkpoint attestation |
| **R2:** Hash chain verification too slow | Low | Medium | Parallel processing, checkpoint shortcuts |
| **R3:** Large upload size (~40MB) fails frequently | Medium | High | Chunked upload, background session |
| **R4:** c2pa-rs video support issues | Low | High | Fallback to manifest-only (no embed) |

### Assumptions

| Assumption | Validation |
|------------|------------|
| **A1:** 10fps depth sufficient for manipulation detection | Test with spliced footage |
| **A2:** Edge overlay performance acceptable | Benchmark on iPhone 12 Pro (oldest supported) |
| **A3:** 15 seconds sufficient for incident documentation | User research |
| **A4:** H.264/HEVC both supported by c2pa-rs | Test both codecs |

### Open Questions

| Question | Owner | Target Resolution |
|----------|-------|-------------------|
| **Q1:** Should we support tap-to-record in addition to hold? | UX | Story 7.14 |
| **Q2:** Optimal checkpoint interval (5s vs 3s vs 10s)? | Dev | Story 7.5 |
| **Q3:** Video verification scrubber UX for depth overlay? | UX | Story 7.13 |
| **Q4:** Should we store audio (muted by default)? | Product | Post-MVP |

## Test Strategy Summary

### Unit Tests

| Component | Coverage Target | Framework |
|-----------|-----------------|-----------|
| HashChainService | 95% | XCTest |
| DepthKeyframeBuffer | 90% | XCTest |
| VideoAttestationService | 90% | XCTest |
| hash_chain_verifier.rs | 95% | cargo test |
| video_depth_analysis.rs | 90% | cargo test |

### Integration Tests

| Scenario | Framework | Device Required |
|----------|-----------|-----------------|
| Full recording + attestation | XCTest | iPhone Pro |
| Recording interruption | XCTest | iPhone Pro |
| Video upload end-to-end | XCTest | iPhone Pro + Backend |
| Hash chain verification | cargo test | None |
| C2PA video embedding | cargo test | None |

### E2E Tests (Playwright)

| Flow | Steps |
|------|-------|
| Video capture happy path | Record 5s → Preview → Upload → Verify page |
| Video verification page | Open URL → Play video → Check evidence |
| Partial attestation display | Upload partial → Verify shows "X of Y verified" |

### Device Testing Matrix

| Model | iOS Version | Status |
|-------|-------------|--------|
| iPhone 17 Pro | iOS 18.x | Primary test device |
| iPhone 15 Pro | iOS 17.x | Secondary test device |
| iPhone 12 Pro | iOS 17.x | Oldest supported (thermal test) |

---

## Story Mapping

| Story ID | Title | ACs Covered |
|----------|-------|-------------|
| 7.1 | ARKit Video Recording Session | AC-7.1 |
| 7.2 | Depth Keyframe Extraction (10fps) | AC-7.2 |
| 7.3 | Real-time Edge Depth Overlay | AC-7.3 |
| 7.4 | Frame Hash Chain | AC-7.4 |
| 7.5 | Video Attestation with Checkpoints | AC-7.5, AC-7.6 |
| 7.6 | Video Metadata Collection | - |
| 7.7 | Video Local Processing Pipeline | AC-7.7 |
| 7.8 | Video Upload Endpoint | AC-7.7 |
| 7.9 | Video Depth Analysis Service | AC-7.9 |
| 7.10 | Video Hash Chain Verification | AC-7.8 |
| 7.11 | Video Evidence Package | AC-7.10 |
| 7.12 | C2PA Video Manifest Generation | AC-7.11 |
| 7.13 | Video Verification Page | AC-7.12 |
| 7.14 | Video Capture UI | AC-7.13 |

---

_Generated by BMAD Epic Tech Context Workflow_
_Date: 2025-11-26_
_Epic: 7 - Video Capture with LiDAR Depth_
