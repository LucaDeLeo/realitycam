# Epic Technical Specification: Privacy-First Capture Mode

Date: 2025-12-01
Author: Luca
Epic ID: 8
Status: Draft

---

## Overview

Epic 8 enables **zero-knowledge provenance** for rial. by allowing users to capture attested photos and videos without uploading raw media. The device performs depth analysis locally, signs the results with DCAppAttest, and uploads only a hash plus evidence metadata. This addresses privacy requirements for journalists, lawyers, medical professionals, and HR personnel who need to prove capture authenticity without exposing sensitive content.

The core innovation: **hardware attestation proves an uncompromised device computed the depth analysis**, so the server can trust client-side results with the same confidence as server-side computation.

## Objectives and Scope

### Objectives

1. **Zero-knowledge media provenance** — Prove a capture is authentic without the server ever seeing the raw photo/video
2. **Parity with full capture** — Hash-only captures achieve the same HIGH confidence level when all checks pass
3. **Granular metadata control** — Users choose exactly what context accompanies each capture
4. **Video support** — Privacy mode works for both photos and videos (including hash chain verification)

### In Scope

- Client-side depth analysis service (port from Rust to Swift)
- Privacy Mode toggle and settings UI
- Hash-only capture payload format
- Backend endpoint modifications for `mode: "hash_only"`
- Evidence package generation without stored media
- Verification page hash-only display variant
- File upload verification for hash matching
- Video privacy mode (hash chain + temporal depth analysis on-device)

### Out of Scope

- Re-analysis capability (once hash-only, algorithm improvements can't retroactively apply)
- Partial metadata reveals post-capture (metadata flags set at capture time are final)
- Privacy mode for gallery imports (only in-app captures supported)
- Android implementation (iOS only per MVP scope)

## System Architecture Alignment

Epic 8 extends the existing native Swift architecture (ADR-009) and aligns with ADR-011 (Client-Side Depth Analysis for Privacy Mode).

**Trust Model:**
```
┌─────────────────────────────────────────────────────────────────┐
│                     PRIVACY MODE TRUST CHAIN                     │
├─────────────────────────────────────────────────────────────────┤
│  1. Secure Enclave generates device attestation key             │
│  2. DCAppAttest proves device is uncompromised                   │
│  3. App performs depth analysis using same algorithm as server   │
│  4. Assertion signs: hash(media) + depth_analysis + metadata     │
│  5. Server verifies assertion → trusts attested device's results │
│  6. Evidence stored: hash + analysis + attestation (no media)    │
└─────────────────────────────────────────────────────────────────┘
```

**Component Integration:**

| Layer | Existing Component | Epic 8 Addition |
|-------|-------------------|-----------------|
| iOS/Capture | `FrameProcessor.swift` | `DepthAnalysisService.swift` |
| iOS/UI | `CaptureView.swift` | `PrivacySettingsView.swift` |
| iOS/Networking | `UploadService.swift` | `HashOnlyPayload.swift` |
| Backend/Routes | `captures.rs` | `mode: "hash_only"` handling |
| Backend/Services | `depth_analysis.rs` | Skip analysis when device-provided |
| Backend/Models | `capture.rs` | `capture_mode`, `media_stored` fields |
| Web/Components | `EvidencePanel.tsx` | Hash-only display variant |

## Detailed Design

### Services and Modules

#### iOS: DepthAnalysisService (New)

**Location:** `ios/Rial/Core/Capture/DepthAnalysisService.swift`

**Responsibility:** Perform depth analysis locally using identical algorithm to backend.

```swift
struct DepthAnalysisResult: Codable {
    let depthVariance: Float     // std dev of depth values
    let depthLayers: Int         // distinct depth planes detected
    let edgeCoherence: Float     // correlation with RGB edges
    let minDepth: Float          // nearest point in meters
    let maxDepth: Float          // farthest point in meters
    let isLikelyRealScene: Bool  // variance > 0.5 && layers >= 3 && coherence > 0.3
    let computedAt: Date
    let algorithmVersion: String // "1.0" for determinism tracking
}

final class DepthAnalysisService {
    static let shared = DepthAnalysisService()

    /// Analyze depth map and return result (< 500ms target)
    func analyze(depthMap: CVPixelBuffer, rgbImage: CVPixelBuffer?) async throws -> DepthAnalysisResult

    /// GPU-accelerated variance computation
    private func computeVariance(depthMap: CVPixelBuffer) -> Float

    /// Count distinct depth layers using histogram binning
    private func countDepthLayers(depthMap: CVPixelBuffer) -> Int

    /// Correlate depth edges with RGB edges using Sobel
    private func computeEdgeCoherence(depthMap: CVPixelBuffer, rgbImage: CVPixelBuffer) -> Float
}
```

**Algorithm Parity Requirements:**
- Thresholds MUST match `backend/src/services/depth_analysis.rs`
- Variance: standard deviation across all valid depth pixels
- Layers: histogram with 0.5m bin width, count bins with >1% of pixels
- Coherence: Sobel edge on both buffers, normalized correlation

#### iOS: PrivacySettingsManager (New)

**Location:** `ios/Rial/Core/Configuration/PrivacySettingsManager.swift`

```swift
enum MetadataLevel: String, Codable, CaseIterable {
    case none = "none"
    case coarse = "coarse"
    case precise = "precise"
}

enum TimestampLevel: String, Codable, CaseIterable {
    case none = "none"
    case dayOnly = "day_only"
    case exact = "exact"
}

enum DeviceInfoLevel: String, Codable, CaseIterable {
    case none = "none"
    case modelOnly = "model_only"
    case full = "full"
}

struct PrivacySettings: Codable {
    var privacyModeEnabled: Bool
    var locationLevel: MetadataLevel
    var timestampLevel: TimestampLevel
    var deviceInfoLevel: DeviceInfoLevel
}

final class PrivacySettingsManager: ObservableObject {
    @AppStorage("privacySettings") private var settingsData: Data?
    @Published var settings: PrivacySettings

    static let `default` = PrivacySettings(
        privacyModeEnabled: false,
        locationLevel: .coarse,
        timestampLevel: .exact,
        deviceInfoLevel: .modelOnly
    )
}
```

#### iOS: HashOnlyCapturePayload (New)

**Location:** `ios/Rial/Models/HashOnlyCapturePayload.swift`

```swift
struct HashOnlyCapturePayload: Codable {
    let captureMode: String = "hash_only"
    let mediaHash: String            // SHA-256 hex
    let mediaType: String            // "photo" | "video"
    let depthAnalysis: DepthAnalysisResult
    let metadata: FilteredMetadata
    let metadataFlags: MetadataFlags
    let capturedAt: Date
    let assertion: String            // Base64 DCAppAttest assertion

    // Video-specific (optional)
    let hashChain: HashChainData?    // For video privacy mode
    let frameCount: Int?
    let durationMs: Int?
}

struct FilteredMetadata: Codable {
    let location: FilteredLocation?  // Per settings
    let timestamp: String?           // Per settings (ISO8601 or day-only)
    let deviceModel: String?         // Per settings
}

struct MetadataFlags: Codable {
    let locationIncluded: Bool
    let locationLevel: String
    let timestampIncluded: Bool
    let timestampLevel: String
    let deviceInfoIncluded: Bool
    let deviceInfoLevel: String
}
```

#### Backend: Hash-Only Mode Handling

**Location:** `backend/src/routes/captures.rs` (modify existing)

```rust
// Add to CreateCaptureRequest
#[derive(Deserialize)]
pub struct CreateCaptureRequest {
    // ... existing fields ...

    #[serde(default)]
    pub mode: CaptureMode,

    // Present only when mode == HashOnly
    pub hash_only_payload: Option<HashOnlyPayload>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum CaptureMode {
    #[default]
    Full,
    HashOnly,
}

#[derive(Deserialize)]
pub struct HashOnlyPayload {
    pub media_hash: String,
    pub media_type: String,
    pub depth_analysis: ClientDepthAnalysis,
    pub metadata: serde_json::Value,
    pub metadata_flags: MetadataFlags,
    pub captured_at: DateTime<Utc>,
    pub assertion: String,
    pub hash_chain: Option<HashChainData>,
    pub frame_count: Option<i32>,
    pub duration_ms: Option<i32>,
}

#[derive(Deserialize)]
pub struct ClientDepthAnalysis {
    pub depth_variance: f32,
    pub depth_layers: i32,
    pub edge_coherence: f32,
    pub min_depth: f32,
    pub max_depth: f32,
    pub is_likely_real_scene: bool,
    pub algorithm_version: String,
}
```

#### Backend: Evidence Package for Hash-Only

**Location:** `backend/src/services/evidence.rs` (extend)

```rust
pub struct Evidence {
    // ... existing fields ...

    pub capture_mode: CaptureMode,
    pub media_stored: bool,
    pub analysis_source: AnalysisSource,
}

#[derive(Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AnalysisSource {
    Server,
    Device,
}

impl Evidence {
    pub fn from_hash_only(
        payload: &HashOnlyPayload,
        attestation_result: &AttestationResult,
    ) -> Self {
        Evidence {
            hardware_attestation: HardwareAttestation {
                status: attestation_result.status,
                level: attestation_result.level.clone(),
                device_model: payload.metadata.device_model.clone(),
            },
            depth_analysis: DepthAnalysis {
                status: if payload.depth_analysis.is_likely_real_scene {
                    EvidenceStatus::Pass
                } else {
                    EvidenceStatus::Fail
                },
                depth_variance: payload.depth_analysis.depth_variance,
                depth_layers: payload.depth_analysis.depth_layers,
                edge_coherence: payload.depth_analysis.edge_coherence,
                is_likely_real_scene: payload.depth_analysis.is_likely_real_scene,
            },
            capture_mode: CaptureMode::HashOnly,
            media_stored: false,
            analysis_source: AnalysisSource::Device,
            // ... other fields from payload
        }
    }
}
```

### Data Models and Contracts

#### Database Schema Changes

```sql
-- Migration: Add privacy mode fields to captures table
ALTER TABLE captures
ADD COLUMN capture_mode TEXT NOT NULL DEFAULT 'full',
ADD COLUMN media_stored BOOLEAN NOT NULL DEFAULT TRUE,
ADD COLUMN analysis_source TEXT NOT NULL DEFAULT 'server',
ADD COLUMN metadata_flags JSONB;

-- Add index for hash-only queries
CREATE INDEX idx_captures_mode ON captures(capture_mode);

-- Update hash index for faster lookups (hash-only verification)
CREATE INDEX idx_captures_hash_lookup ON captures USING hash(target_media_hash)
WHERE capture_mode = 'hash_only';
```

#### Evidence Package Schema (Updated)

```typescript
// packages/shared/src/types/evidence.ts
export interface Evidence {
  hardware_attestation: HardwareAttestation;
  depth_analysis: DepthAnalysis;
  metadata: MetadataEvidence;

  // New fields for Epic 8
  capture_mode: 'full' | 'hash_only';
  media_stored: boolean;
  analysis_source: 'server' | 'device';
  metadata_flags?: MetadataFlags;
}

export interface MetadataFlags {
  location_included: boolean;
  location_level: 'none' | 'coarse' | 'precise';
  timestamp_included: boolean;
  timestamp_level: 'none' | 'day_only' | 'exact';
  device_info_included: boolean;
  device_info_level: 'none' | 'model_only' | 'full';
}
```

### APIs and Interfaces

#### POST /api/v1/captures (Updated)

**Request (Hash-Only Mode):**
```http
POST /api/v1/captures
Content-Type: application/json
X-Device-Id: {device_id}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {signature}

{
  "mode": "hash_only",
  "hash_only_payload": {
    "media_hash": "abc123...",
    "media_type": "photo",
    "depth_analysis": {
      "depth_variance": 2.4,
      "depth_layers": 5,
      "edge_coherence": 0.87,
      "min_depth": 0.8,
      "max_depth": 12.5,
      "is_likely_real_scene": true,
      "algorithm_version": "1.0"
    },
    "metadata": {
      "location": { "city": "San Francisco", "country": "US" },
      "timestamp": "2025-12-01",
      "device_model": "iPhone 15 Pro"
    },
    "metadata_flags": {
      "location_included": true,
      "location_level": "coarse",
      "timestamp_included": true,
      "timestamp_level": "day_only",
      "device_info_included": true,
      "device_info_level": "model_only"
    },
    "captured_at": "2025-12-01T10:30:00Z",
    "assertion": "base64..."
  }
}
```

**Response (Success):**
```json
{
  "data": {
    "capture_id": "uuid",
    "status": "complete",
    "capture_mode": "hash_only",
    "media_stored": false,
    "verification_url": "https://rial.app/verify/{id}"
  }
}
```

#### GET /api/v1/captures/{id} (Updated Response)

```json
{
  "data": {
    "id": "uuid",
    "confidence_level": "high",
    "capture_mode": "hash_only",
    "media_stored": false,
    "captured_at": "2025-12-01T10:30:00Z",
    "media_url": null,
    "media_hash": "abc123...",
    "evidence": {
      "hardware_attestation": {
        "status": "pass",
        "level": "secure_enclave",
        "device_model": "iPhone 15 Pro"
      },
      "depth_analysis": {
        "status": "pass",
        "depth_variance": 2.4,
        "depth_layers": 5,
        "edge_coherence": 0.87,
        "is_likely_real_scene": true,
        "source": "device"
      },
      "analysis_source": "device",
      "metadata_flags": {
        "location_level": "coarse",
        "timestamp_level": "day_only"
      }
    }
  }
}
```

### Workflows and Sequencing

#### Privacy Mode Capture Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PRIVACY MODE CAPTURE FLOW                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  User Enables Privacy Mode                                                   │
│        │                                                                     │
│        ▼                                                                     │
│  ┌──────────────┐                                                           │
│  │ Capture Mode │  User configures metadata levels                          │
│  │   Settings   │  (location, timestamp, device info)                       │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │   Capture    │  Photo/Video captured with LiDAR depth                    │
│  │  (Normal)    │                                                           │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │ Client-Side  │  DepthAnalysisService.analyze()                           │
│  │   Depth      │  Runs in < 500ms                                          │
│  │  Analysis    │                                                           │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │  Compute     │  SHA-256 of media bytes                                   │
│  │ Media Hash   │                                                           │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │   Filter     │  Apply metadata level filters                             │
│  │  Metadata    │  (coarse location, day-only timestamp, etc.)              │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │  DCAppAttest │  Sign: hash + analysis + metadata + flags                 │
│  │  Assertion   │                                                           │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │   Upload     │  POST /captures { mode: "hash_only", ... }                │
│  │  (< 10KB)    │  No media bytes in request                                │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │   Backend    │  1. Verify assertion signature                            │
│  │  Processing  │  2. Validate payload hash matches assertion               │
│  │              │  3. Store evidence (no media)                             │
│  │              │  4. Return verification URL                               │
│  └──────┬───────┘                                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────┐                                                           │
│  │   Local      │  Full media saved locally (encrypted)                     │
│  │  Storage     │  User has full control                                    │
│  └─────────────┘                                                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Video Privacy Mode Flow

For video, additional steps:
1. Hash chain computed locally (`HashChainService.swift`)
2. Temporal depth analysis on depth keyframes
3. Checkpoints attested at 5-second intervals (reuse `VideoAttestationService.swift`)
4. Final payload includes `hash_chain` with frame hashes and checkpoint attestations

## Non-Functional Requirements

### Performance

| Metric | Target | Implementation |
|--------|--------|----------------|
| Client-side depth analysis | < 500ms | Metal GPU acceleration if needed |
| Hash-only upload size | < 10KB | vs ~5MB for full photo capture |
| Hash-only processing latency | < 2s | Skip S3 upload, skip server-side depth |
| Video hash-only processing | < 5s | Proportional to frame count |

### Security

| Aspect | Requirement | Implementation |
|--------|-------------|----------------|
| Analysis integrity | Device-computed results trusted | DCAppAttest assertion covers entire payload |
| Metadata privacy | User controls exposure | Filtered before payload construction |
| Hash collision | Negligible | SHA-256 (256-bit preimage resistance) |
| Replay prevention | Assertion bound to content | `clientDataHash = SHA256(payload)` |

**Threat Model Extension:**

| Attack | Privacy Mode Defense |
|--------|---------------------|
| Server compromise | Media never stored; only hash + evidence |
| Network MITM | TLS 1.3 + assertion verification |
| Fake depth analysis | Would require Secure Enclave compromise |
| Hash collision attack | SHA-256; 2^128 operations for collision |

### Reliability/Availability

- Hash-only captures work offline (same as full captures)
- Local storage retains full media even after hash-only upload
- If assertion generation fails, fall back to offline queue

### Observability

**New Metrics:**
- `captures.privacy_mode.count` — Count of hash-only captures
- `captures.privacy_mode.analysis_time_ms` — Client-side analysis duration
- `captures.privacy_mode.payload_size_bytes` — Upload payload size
- `captures.privacy_mode.confidence_distribution` — HIGH/MEDIUM/LOW breakdown

**Log Fields:**
```json
{
  "capture_id": "uuid",
  "capture_mode": "hash_only",
  "analysis_source": "device",
  "analysis_version": "1.0",
  "metadata_flags": { ... }
}
```

## Dependencies and Integrations

### iOS Dependencies (No new external packages)

Existing native frameworks used:
- **CryptoKit** — SHA-256 hashing
- **DeviceCheck** — DCAppAttest assertions
- **Metal** — GPU-accelerated depth processing (optional)
- **ARKit** — Depth map access

### Backend Dependencies (No new crates)

Existing crates used:
- **sha2** — Hash verification
- **ed25519-dalek** — Signature verification
- **serde_json** — Payload parsing

### Database Migration

```sql
-- Version: 20251201000000
-- Description: Add privacy mode support

ALTER TABLE captures
ADD COLUMN capture_mode TEXT NOT NULL DEFAULT 'full',
ADD COLUMN media_stored BOOLEAN NOT NULL DEFAULT TRUE,
ADD COLUMN analysis_source TEXT NOT NULL DEFAULT 'server',
ADD COLUMN metadata_flags JSONB;

CREATE INDEX idx_captures_mode ON captures(capture_mode);
```

### Web Dependencies (No new packages)

UI changes use existing React/Next.js patterns.

## Acceptance Criteria (Authoritative)

### Story 8.1: Client-Side Depth Analysis Service

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.1.1 | Depth variance computed correctly | Compare with server result on same depth map |
| 8.1.2 | Depth layers counted correctly | Match server algorithm output |
| 8.1.3 | Edge coherence calculated correctly | Match server algorithm within 0.01 |
| 8.1.4 | `is_likely_real_scene` matches server logic | Same thresholds applied |
| 8.1.5 | Analysis completes in < 500ms | Performance test on iPhone 12 Pro |
| 8.1.6 | Results are deterministic | Same input → same output |

### Story 8.2: Privacy Mode Settings UI

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.2.1 | Toggle visible in Settings | UI test |
| 8.2.2 | Metadata controls appear when enabled | UI test |
| 8.2.3 | Settings persist across app launches | Kill/relaunch app |
| 8.2.4 | Default values applied correctly | Fresh install state |

### Story 8.3: Hash-Only Capture Payload

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.3.1 | Payload excludes raw media bytes | Inspect request body |
| 8.3.2 | Payload size < 10KB | Measure actual size |
| 8.3.3 | Assertion covers entire payload | Verify signature manually |
| 8.3.4 | Full media retained locally | Check local storage |

### Story 8.4: Backend Hash-Only Capture Endpoint

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.4.1 | Accepts `mode: "hash_only"` requests | API test |
| 8.4.2 | Validates assertion signature | Test with invalid signature |
| 8.4.3 | Stores capture with `media_stored: false` | DB query |
| 8.4.4 | Returns 401 on invalid assertion | API test |
| 8.4.5 | No S3 upload occurs | S3 call absence |

### Story 8.5: Hash-Only Evidence Package

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.5.1 | Evidence includes `analysis_source: "device"` | API response check |
| 8.5.2 | Confidence calculation works correctly | HIGH when both pass |
| 8.5.3 | Evidence notes device analysis source | Response inspection |

### Story 8.6: Verification Page Hash-Only Display

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.6.1 | "Hash Verified" badge displayed | E2E test |
| 8.6.2 | No media preview shown | Visual check |
| 8.6.3 | Confidence badge visible | E2E test |
| 8.6.4 | Analysis source shown in evidence panel | E2E test |

### Story 8.7: File Verification for Hash-Only

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.7.1 | File upload hashes correctly | Known hash test |
| 8.7.2 | Match found shows full evidence | E2E test |
| 8.7.3 | No match shows appropriate message | E2E test |
| 8.7.4 | Uploaded file not stored | Server storage check |

### Story 8.8: Video Privacy Mode Support

| AC# | Criterion | Test |
|-----|-----------|------|
| 8.8.1 | Hash chain computed locally | Verify chain integrity |
| 8.8.2 | Temporal depth analysis on-device | Compare with server |
| 8.8.3 | Video hash-only payload accepted | API test |
| 8.8.4 | Verification shows video metadata | E2E test |

## Traceability Mapping

| AC | Spec Section | Component(s) | Test Approach |
|----|--------------|--------------|---------------|
| 8.1.1-8.1.6 | Services/DepthAnalysisService | `DepthAnalysisService.swift` | Unit tests, parity tests vs Rust |
| 8.2.1-8.2.4 | Services/PrivacySettingsManager | `PrivacySettingsView.swift`, `PrivacySettingsManager.swift` | UI tests, UserDefaults verification |
| 8.3.1-8.3.4 | Data Models/HashOnlyCapturePayload | `HashOnlyCapturePayload.swift`, `UploadService.swift` | Integration tests, payload inspection |
| 8.4.1-8.4.5 | APIs/POST captures | `captures.rs`, `capture_attestation.rs` | API tests, DB verification |
| 8.5.1-8.5.3 | Services/Evidence | `evidence.rs` | Unit tests, API response tests |
| 8.6.1-8.6.4 | Web Components | `verify/[id]/page.tsx`, `EvidencePanel.tsx` | Playwright E2E |
| 8.7.1-8.7.4 | Web Components | `FileDropzone.tsx`, `verify.rs` | Playwright E2E, storage audit |
| 8.8.1-8.8.4 | iOS Video + Backend | `HashChainService.swift`, `captures_video.rs` | Integration tests |

## Risks, Assumptions, Open Questions

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Algorithm drift between Swift and Rust | Medium | High | Version field + deterministic tests |
| Metal not available on all Pro models | Low | Low | CPU fallback path |
| DCAppAttest rate limits | Low | Medium | Batch assertions if needed |

### Assumptions

1. All target iPhone Pro models support DCAppAttest (verified: iOS 15+)
2. Depth analysis algorithm is deterministic across platforms
3. Users understand privacy mode trade-offs (no re-analysis possible)
4. SHA-256 collision resistance sufficient for production use

### Open Questions

| Q# | Question | Owner | Status |
|----|----------|-------|--------|
| Q1 | Should we store algorithm version for future compatibility? | Architect | Resolved: Yes, include `algorithm_version` field |
| Q2 | What happens if algorithm improves? Can we notify users of old captures? | PM | Open |
| Q3 | Should verification page offer client-side re-analysis via file upload? | Architect | Deferred to post-MVP |

## Test Strategy Summary

### Unit Tests

| Component | Framework | Coverage Target |
|-----------|-----------|-----------------|
| DepthAnalysisService | XCTest | 100% algorithm branches |
| PrivacySettingsManager | XCTest | All persistence paths |
| HashOnlyCapturePayload | XCTest | Serialization, signing |
| Backend hash-only handling | cargo test | All endpoints, validation |

### Integration Tests

| Scenario | Approach |
|----------|----------|
| End-to-end hash-only capture | iOS → Backend → Verification |
| Algorithm parity | Same depth map through Swift + Rust, compare results |
| Assertion verification | Valid/invalid assertion handling |

### E2E Tests

| Test | Framework | Environment |
|------|-----------|-------------|
| Hash-only verification page | Playwright | Chromium, WebKit |
| File upload hash matching | Playwright | With test fixtures |
| Video hash-only display | Playwright | Video test capture |

### Device Testing

- Physical iPhone 12 Pro minimum (LiDAR required)
- Test all metadata level combinations
- Verify local storage retention
- Confirm upload size < 10KB
