# rial. - Architecture Document

**Author:** Luca
**Architect:** Winston (BMAD)
**Date:** 2025-11-26
**Version:** 1.3 (MVP + Video)

---

## Executive Summary

rial. is a focused MVP providing cryptographically-attested, LiDAR-verified photo and video provenance for iPhone Pro devices. The architecture prioritizes hardware-rooted trust and depth-based authenticity verification.

**Core Components:**
- **iOS App** (Native Swift/SwiftUI): Photo and video capture with LiDAR depth and hardware attestation
- **Backend** (Rust/Axum): Evidence computation, C2PA manifest generation
- **Verification Web** (Next.js 16): Public verification interface

**Key Architectural Principles:**
1. Hardware attestation as foundation (Secure Enclave + DCAppAttest)
2. LiDAR depth as primary authenticity signal
3. iPhone Pro only — no cross-platform complexity
4. Photo and video with synchronized depth — hash chain integrity for video

**Why iPhone Pro Only:**
- LiDAR sensor enables "real 3D scene" vs "flat image" detection
- Consistent hardware: all Pro models have Secure Enclave + LiDAR
- Eliminates Android fragmentation (StrongBox availability varies)
- 50% less native code, faster iteration to working demo

---

## Project Initialization

**First implementation story should execute these commands:**

### iOS App (Rial)
```bash
# Create new Xcode project:
# - Product Name: Rial
# - Interface: SwiftUI
# - Language: Swift
# - Storage: None (Core Data added manually)
# - Include Tests: Yes (Unit + UI)
# - Minimum Deployment: iOS 15.0
# - Device: iPhone only
```

### Verification Web
```bash
npx create-next-app@latest realitycam-web --typescript --tailwind --app --turbopack
```

### Backend
```bash
cargo new realitycam-api
cd realitycam-api
# Configure Cargo.toml with dependencies below
```

---

## Decision Summary

| Category | Decision | Version | Rationale |
|----------|----------|---------|-----------|
| Platform | iPhone Pro only | iOS 15+ | LiDAR required, modern Swift concurrency |
| Mobile Framework | Native Swift/SwiftUI | Swift 5.9+ | Direct OS access, minimal attack surface |
| Web Framework | Next.js | 16 | Turbopack default, Cache Components, React 19.2 |
| Backend Framework | Axum | 0.8.x | Type-safe, Tokio ecosystem, c2pa-rs native |
| Database | PostgreSQL | 16 | JSONB for evidence, TIMESTAMPTZ |
| ORM | SQLx | 0.8.x | Compile-time checked queries |
| C2PA SDK | c2pa-rs | 0.51.x | Official CAI SDK, Rust 1.82+ |
| State Management | SwiftUI + Keychain | Native | @State, @StateObject, secure persistence |
| File Storage | S3 + CloudFront | - | Presigned URLs, CDN delivery |
| Attestation | DeviceCheck (DCAppAttest) | iOS 15+ | Direct Secure Enclave, no wrappers |
| Cryptography | CryptoKit | Native | Hardware-accelerated, Secure Enclave keys |
| Depth Capture | ARKit | Native | Unified RGB+Depth in single ARFrame |
| Depth Visualization | Metal | Native | 60fps GPU-native shaders |
| Auth Pattern | Device Signature | Ed25519 | No tokens, hardware-bound |
| Networking | URLSession | Native | Background uploads, cert pinning |
| Testing (Mobile) | XCTest + XCUITest | - | Unit + UI tests, real devices |
| Testing (Backend) | cargo test + testcontainers | - | Integration with real Postgres |
| Testing (Web) | Vitest + Playwright | - | Fast unit + E2E |

---

## Project Structure

```
realitycam/
├── ios/                                 # Native Swift app (PRIMARY)
│   ├── Rial/
│   │   ├── App/
│   │   │   ├── RialApp.swift            # @main entry point
│   │   │   └── AppDelegate.swift        # Background task handling
│   │   ├── Core/                        # Security-critical services
│   │   │   ├── Attestation/
│   │   │   │   ├── DeviceAttestation.swift    # DCAppAttest direct
│   │   │   │   ├── CaptureAssertion.swift     # Per-capture signing
│   │   │   │   └── VideoAttestationService.swift # Video checkpoint attestation
│   │   │   ├── Capture/
│   │   │   │   ├── ARCaptureSession.swift     # Unified RGB+Depth
│   │   │   │   ├── DepthProcessor.swift       # Depth analysis prep
│   │   │   │   ├── VideoRecordingSession.swift # ARKit + AVAssetWriter
│   │   │   │   └── DepthKeyframeBuffer.swift  # 10fps depth extraction
│   │   │   ├── Crypto/
│   │   │   │   ├── SecureKeychain.swift       # Keychain wrapper
│   │   │   │   ├── CaptureEncryption.swift    # AES-GCM offline
│   │   │   │   ├── HashingService.swift       # CryptoKit SHA-256
│   │   │   │   └── HashChainService.swift     # Video frame hash chain
│   │   │   ├── Networking/
│   │   │   │   ├── APIClient.swift            # URLSession + signing
│   │   │   │   ├── DeviceSignature.swift      # Request auth
│   │   │   │   └── UploadService.swift        # Background uploads
│   │   │   └── Storage/
│   │   │       ├── CaptureStore.swift         # Core Data persistence
│   │   │       └── OfflineQueue.swift         # Upload queue
│   │   ├── Features/                    # SwiftUI views + view models
│   │   │   ├── Capture/
│   │   │   │   ├── CaptureView.swift
│   │   │   │   ├── CaptureViewModel.swift
│   │   │   │   └── DepthOverlayView.swift     # Metal shader overlay
│   │   │   ├── Preview/
│   │   │   │   ├── PreviewView.swift
│   │   │   │   └── PreviewViewModel.swift
│   │   │   ├── History/
│   │   │   │   ├── HistoryView.swift
│   │   │   │   └── HistoryViewModel.swift
│   │   │   └── Result/
│   │   │       └── ResultView.swift
│   │   ├── Models/
│   │   │   ├── Capture.swift
│   │   │   ├── Device.swift
│   │   │   └── Evidence.swift
│   │   ├── Shaders/
│   │   │   ├── DepthColormap.metal      # GPU depth visualization
│   │   │   └── EdgeDepthVisualization.metal # Sobel edge detection for video
│   │   └── Resources/
│   │       └── Assets.xcassets
│   ├── RialTests/                       # XCTest unit tests
│   ├── RialUITests/                     # XCUITest UI tests
│   └── Rial.xcodeproj
│
├── apps/
│   ├── mobile/                          # Expo/RN (REFERENCE for feature parity)
│   │   └── ...                          # Kept for parallel testing
│   └── web/                             # Next.js 16 verification site
│       ├── app/
│       │   ├── page.tsx
│       │   ├── verify/[id]/page.tsx
│       │   └── layout.tsx
│       ├── components/
│       │   ├── Evidence/
│       │   │   ├── EvidencePanel.tsx
│       │   │   ├── DepthAnalysis.tsx
│       │   │   └── ConfidenceSummary.tsx
│       │   ├── Media/
│       │   │   └── SecureImage.tsx
│       │   └── Upload/
│       │       └── FileDropzone.tsx
│       ├── lib/
│       │   └── api.ts
│       └── package.json
│
├── packages/
│   └── shared/                          # Shared TypeScript types
│       └── src/types/
│           ├── evidence.ts
│           ├── capture.ts
│           └── api.ts
│
├── backend/                             # Rust API server
│   ├── src/
│   │   ├── main.rs
│   │   ├── config.rs
│   │   ├── routes/
│   │   │   ├── captures.rs              # Photo capture endpoint
│   │   │   ├── captures_video.rs        # Video capture endpoint
│   │   │   └── ...
│   │   ├── middleware/
│   │   ├── services/
│   │   │   ├── c2pa.rs                  # Photo C2PA manifest
│   │   │   ├── c2pa_video.rs            # Video C2PA manifest
│   │   │   ├── depth_analysis.rs        # Photo depth analysis
│   │   │   ├── video_depth_analysis.rs  # Temporal depth analysis
│   │   │   ├── hash_chain_verifier.rs   # Video hash chain verification
│   │   │   └── ...
│   │   ├── models/
│   │   └── error.rs
│   ├── migrations/
│   └── Cargo.toml
│
├── infrastructure/
│   └── docker-compose.yml
│
└── docs/
    ├── prd.md
    ├── epics.md
    └── architecture.md
```

---

## FR Category to Architecture Mapping (MVP)

| FR Category | Primary Location | Notes |
|-------------|------------------|-------|
| Device & Attestation | `ios/Rial/Core/Attestation/` | DCAppAttest direct via DeviceCheck |
| LiDAR Depth Capture | `ios/Rial/Core/Capture/` | ARKit unified RGB+Depth |
| Photo Capture | `ios/Rial/Features/Capture/` | SwiftUI + ARKit |
| Video Capture | `ios/Rial/Core/Capture/` | VideoRecordingSession + DepthKeyframeBuffer |
| Video Hash Chain | `ios/Rial/Core/Crypto/` | HashChainService for frame integrity |
| Video Attestation | `ios/Rial/Core/Attestation/` | VideoAttestationService with checkpoints |
| Cryptography | `ios/Rial/Core/Crypto/` | CryptoKit, Keychain |
| Upload & Sync | `ios/Rial/Core/Networking/` | URLSession background uploads |
| Offline Storage | `ios/Rial/Core/Storage/` | Core Data + AES-GCM encryption |
| Evidence Generation | `backend/services/evidence/` | Hardware + Depth + Metadata |
| Video Evidence | `backend/services/` | hash_chain_verifier + video_depth_analysis |
| C2PA Integration | `backend/services/c2pa.rs` | Photo manifest embedding |
| C2PA Video | `backend/services/c2pa_video.rs` | Video manifest embedding (MP4) |
| Verification Interface | `web/app/verify/`, `web/components/` | Public verification page |
| File Verification | `web/components/Upload/` | Hash-based lookup |
| Device Management | `backend/routes/devices.rs` | No user accounts for MVP |

---

## Technology Stack Details

### Backend Dependencies (Cargo.toml)

```toml
[package]
name = "realitycam-api"
version = "0.1.0"
edition = "2021"

[dependencies]
# Web framework
axum = "0.8"
axum-extra = { version = "0.10", features = ["typed-header"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["cors", "trace", "request-id"] }

# Async runtime
tokio = { version = "1", features = ["full"] }

# Database
sqlx = { version = "0.8", features = ["runtime-tokio", "postgres", "uuid", "chrono", "json"] }

# C2PA (v0.63 for improved video/MP4 support)
c2pa = { version = "0.63", features = ["file_io"] }

# Video processing (for hash chain verification)
ffmpeg-next = "7"

# Cryptography
ed25519-dalek = "2"
sha2 = "0.10"
x509-parser = "0.16"

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# AWS
aws-sdk-s3 = "1"
aws-config = "1"

# Utilities
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
thiserror = "2"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["json"] }
dotenvy = "0.15"
```

### Native iOS Dependencies

**rial.** uses only Apple's native frameworks—no third-party dependencies for security-critical functionality:

| Framework | Purpose | Notes |
|-----------|---------|-------|
| **DeviceCheck** | DCAppAttest hardware attestation | Direct Secure Enclave access |
| **CryptoKit** | SHA-256, AES-GCM, key management | Hardware-accelerated |
| **ARKit** | RGB + LiDAR depth capture | Unified ARFrame |
| **Metal** | Depth visualization shaders | 60fps GPU-native |
| **Security** | Keychain services | Secure Enclave-backed keys |
| **Foundation** | URLSession networking | Background uploads, cert pinning |
| **CoreData** | Local capture persistence | Offline queue management |
| **CoreLocation** | GPS coordinates | Location metadata |

**Swift Package Dependencies:**
```swift
// Package.swift - intentionally minimal
dependencies: []  // No external packages for security-critical code
```

**Why Zero External Dependencies:**
- Smaller attack surface (no supply chain risk)
- Direct OS API access (no abstraction layers)
- Easier security auditing (single language, known frameworks)
- No dependency version conflicts

### Native Security Architecture

**Attestation Flow (Direct DeviceCheck):**

```swift
import DeviceCheck

// ONE-TIME: Device registration (on first launch)
let service = DCAppAttestService.shared
let keyId = try await service.generateKey()
let attestation = try await service.attestKey(keyId, clientDataHash: challenge)
// → Send to POST /api/v1/devices/register

// PER-CAPTURE: Assertion binds signature to specific photo bytes
let photoHash = SHA256.hash(data: photoData)
let clientDataHash = Data(photoHash)
let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
// → Include in POST /api/v1/captures
```

**Key Insight:** In native Swift, `clientDataHash` is computed directly from photo bytes—no serialization to JS, no bridge crossing. The assertion is cryptographically bound to the exact data being uploaded.

### ARKit Unified Capture

Unlike React Native (which requires separate camera + LiDAR modules), native ARKit provides synchronized RGB + depth in a single frame:

```swift
let config = ARWorldTrackingConfiguration()
config.frameSemantics = [.sceneDepth]

func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // PERFECTLY SYNCHRONIZED - same timestamp
    let rgbImage = frame.capturedImage       // CVPixelBuffer
    let depthMap = frame.sceneDepth?.depthMap // CVPixelBuffer (Float32)
    let confidence = frame.sceneDepth?.confidenceMap
    let intrinsics = frame.camera.intrinsics
}
```

This eliminates the timing coordination problems inherent in the multi-module RN approach.

---

## Evidence Architecture (MVP)

The MVP focuses on two high-value evidence dimensions plus basic metadata:

### Primary Evidence: Hardware Attestation
- **What:** Device identity attested by iOS Secure Enclave via DCAppAttest
- **How:** Key generated in hardware, cert chain verified server-side
- **Proves:** Photo originated from a real, uncompromised iPhone Pro
- **Spoofing cost:** Custom silicon or firmware exploit (~impossible for attacker)

### Primary Evidence: LiDAR Depth Analysis
- **What:** Depth map captured simultaneously with photo using ARKit
- **How:** Analyze depth variance, edge coherence, 3D structure
- **Proves:** Camera pointed at real 3D scene, not flat image/screen
- **Spoofing cost:** Building physical 3D replica of scene

**Depth Analysis Algorithm:**
```rust
pub struct DepthAnalysis {
    pub depth_variance: f32,      // High = real scene, Low = flat
    pub edge_coherence: f32,      // Depth edges align with RGB edges
    pub min_depth: f32,           // Nearest point (screens are ~0.3-0.5m)
    pub depth_layers: u32,        // Distinct depth planes detected
}

pub fn analyze_depth(depth_map: &[f32], rgb: &Image) -> DepthAnalysis {
    // Real scenes: high variance, multiple layers, edges match
    // Flat surfaces: low variance, 1-2 layers, no edge correlation
}

pub fn is_likely_real_scene(analysis: &DepthAnalysis) -> bool {
    analysis.depth_variance > 0.5
        && analysis.depth_layers >= 3
        && analysis.edge_coherence > 0.7
}
```

### Secondary Evidence: Metadata Consistency
- EXIF timestamp within tolerance of server time
- Device model matches iPhone Pro (has LiDAR)
- Resolution matches device capability
- **Spoofing cost:** Low (EXIF editor), but adds friction

### Confidence Calculation (Simplified)

```rust
pub fn calculate_confidence(evidence: &Evidence) -> ConfidenceLevel {
    let hw_pass = evidence.hardware_attestation.status == Status::Pass;
    let depth_pass = evidence.depth_analysis.is_likely_real_scene;
    let any_fail = evidence.has_any_failure();

    if any_fail {
        return ConfidenceLevel::Suspicious;
    }

    match (hw_pass, depth_pass) {
        (true, true) => ConfidenceLevel::High,      // Both pass = strong
        (true, false) | (false, true) => ConfidenceLevel::Medium,
        (false, false) => ConfidenceLevel::Low,
    }
}
```

### Deferred Evidence (Post-MVP)
These checks add value but require more implementation effort:
- **Sun angle:** Compare computed solar position to shadow direction
- **Barometric pressure:** Match reported pressure to GPS altitude
- **Gyro × optical flow:** Correlate device rotation with image motion (video)
- **360° environment scan:** Require user to pan device for parallax proof

---

## Implementation Patterns

### Naming Conventions

| Context | Convention | Example |
|---------|------------|---------|
| REST endpoints | Plural nouns, kebab-case | `/api/v1/captures`, `/api/v1/verify-file` |
| Route params | Axum `/{id}` syntax | `/api/v1/captures/{id}` |
| Database tables | Plural, snake_case | `devices`, `captures`, `verification_logs` |
| Database columns | snake_case | `device_id`, `captured_at`, `attestation_level` |
| TypeScript files | PascalCase for components | `EvidencePanel.tsx`, `useCapture.ts` |
| Rust files | snake_case | `device_auth.rs`, `tier2_physics.rs` |
| Environment vars | SCREAMING_SNAKE_CASE | `DATABASE_URL`, `S3_BUCKET` |

### API Response Format

```typescript
// Success
{
  "data": { /* payload */ },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-11-21T10:30:00Z"
  }
}

// Error
{
  "error": {
    "code": "ATTESTATION_FAILED",
    "message": "Certificate chain verification failed",
    "details": { /* optional debug info */ }
  },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-11-21T10:30:00Z"
  }
}
```

### Error Codes

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `ATTESTATION_FAILED` | 401 | Device attestation verification failed |
| `DEVICE_NOT_FOUND` | 404 | Unknown device ID |
| `CAPTURE_NOT_FOUND` | 404 | Unknown capture ID |
| `HASH_NOT_FOUND` | 404 | No capture matches uploaded file hash |
| `VALIDATION_ERROR` | 400 | Request payload invalid |
| `SIGNATURE_INVALID` | 401 | Device signature verification failed |
| `TIMESTAMP_EXPIRED` | 401 | Request timestamp outside 5-minute window |
| `PROCESSING_FAILED` | 500 | Evidence computation failed |
| `STORAGE_ERROR` | 500 | S3 operation failed |

### File Organization

```
# Tests live alongside source files
src/
├── services/
│   ├── evidence/
│   │   ├── mod.rs
│   │   ├── pipeline.rs
│   │   └── pipeline_test.rs    # Unit tests

# Integration tests in separate directory
tests/
├── api_captures_test.rs
└── api_devices_test.rs
```

---

## Data Architecture

### Database Schema

```sql
-- Core entities (see Decision #2 for full schema)

CREATE TABLE devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attestation_level   TEXT NOT NULL,
    attestation_key_id  TEXT NOT NULL UNIQUE,
    attestation_chain   BYTEA,
    platform            TEXT NOT NULL,
    model               TEXT NOT NULL,
    user_id             UUID REFERENCES users(id),
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE captures (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id           UUID NOT NULL REFERENCES devices(id),
    target_media_hash   BYTEA NOT NULL UNIQUE,
    evidence            JSONB NOT NULL,
    confidence_level    TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'pending',
    captured_at         TIMESTAMPTZ NOT NULL,
    uploaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_captures_hash ON captures USING hash(target_media_hash);
```

### S3 Structure

```
realitycam-media-{env}/
├── captures/{capture_id}/
│   ├── original.jpg
│   ├── c2pa.jpg
│   ├── manifest.c2pa
│   └── thumbnail.jpg
└── context/{capture_id}/
    ├── scan.mp4
    └── sensors.msgpack
```

---

## API Contracts

### Device Registration

```
POST /api/v1/devices/register
Content-Type: application/json

Request:
{
  "platform": "ios",
  "model": "iPhone 15 Pro",
  "attestation": {
    "key_id": "base64...",           // DCAppAttest key ID
    "attestation_object": "base64..."  // CBOR attestation from Apple
  }
}

Response:
{
  "data": {
    "device_id": "uuid",
    "attestation_level": "secure_enclave",
    "has_lidar": true
  }
}
```

### Capture Upload

```
POST /api/v1/captures
Content-Type: multipart/form-data
X-Device-Id: {device_id}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {signature}

Parts:
- photo: binary (JPEG)
- depth_map: binary (float32 array, gzipped)
- metadata: JSON { captured_at, location?, device_model }

Response:
{
  "data": {
    "capture_id": "uuid",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/{id}"
  }
}
```

### Video Capture Upload

```
POST /api/v1/captures/video
Content-Type: multipart/form-data
X-Device-Id: {device_id}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {signature}

Parts:
- video: binary (MP4/MOV, ~20MB)
- depth_data: binary (gzipped depth keyframes at 10fps, ~10MB)
- hash_chain: JSON { frame_hashes[], checkpoints[], final_hash }
- metadata: JSON (see below)

Metadata Schema:
{
  "type": "video",
  "started_at": "ISO timestamp",
  "ended_at": "ISO timestamp",
  "duration_ms": 12500,
  "frame_count": 375,
  "depth_keyframe_count": 125,
  "resolution": { "width": 1920, "height": 1080 },
  "codec": "hevc",
  "device_model": "iPhone 15 Pro",
  "location": { "lat": 37.7749, "lng": -122.4194 },
  "attestation_level": "secure_enclave",
  "hash_chain_final": "base64...",
  "assertion": "base64...",
  "is_partial": false,
  "checkpoint_index": null
}

Response:
{
  "data": {
    "capture_id": "uuid",
    "type": "video",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/{id}"
  }
}
```

### Verification Page Data

```
GET /api/v1/captures/{id}

Response:
{
  "data": {
    "id": "uuid",
    "confidence_level": "high",
    "captured_at": "2025-11-21T10:30:00Z",
    "media_url": "https://cdn.../signed-url",
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
        "is_likely_real_scene": true
      },
      "metadata": {
        "timestamp_valid": true,
        "model_has_lidar": true
      }
    },
    "c2pa_manifest_url": "https://cdn.../manifest.c2pa",
    "depth_visualization_url": "https://cdn.../depth-preview.png"
  }
}
```

---

## Security Architecture

### Authentication Flow

```
┌─────────────────────────────────────────────────────────────┐
│  DEVICE AUTHENTICATION (Every Request)                      │
│                                                             │
│  Headers:                                                   │
│    X-Device-Id: {uuid}                                      │
│    X-Device-Timestamp: {unix_ms}                            │
│    X-Device-Signature: sign(timestamp + sha256(body))       │
│                                                             │
│  Server:                                                    │
│    1. Lookup device by ID                                   │
│    2. Verify timestamp within 5 minutes                     │
│    3. Verify Ed25519 signature with stored public key       │
│    4. Proceed or reject                                     │
└─────────────────────────────────────────────────────────────┘
```

### Key Management

| Key | Storage | Rotation |
|-----|---------|----------|
| Device attestation key | iOS Secure Enclave | Never (device-bound) |
| C2PA signing key | AWS KMS (HSM-backed) | Yearly |
| Database encryption | AWS RDS encryption | Managed |

### Transport Security

- TLS 1.3 required for all endpoints
- Certificate pinning in mobile app (Phase 1)
- Presigned URLs expire in 1 hour

### Local Storage Encryption

Offline captures use multiple layers of native iOS protection:

| Layer | Implementation | Notes |
|-------|---------------|-------|
| **iOS Data Protection** | `.completeFileProtection` | Files encrypted at rest, tied to device passcode |
| **Key Storage** | Keychain + Secure Enclave | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| **Encryption** | CryptoKit AES-GCM | Real AEAD encryption (not workaround) |
| **IV** | 12-byte random | Unique per capture via `AES.GCM.Nonce()` |

```swift
import CryptoKit

// Generate Secure Enclave-backed key (one-time)
let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()

// Derive symmetric key for AES-GCM
let symmetricKey = SymmetricKey(size: .bits256)

// Encrypt capture data
let sealedBox = try AES.GCM.seal(captureData, using: symmetricKey)
let encryptedData = sealedBox.combined! // nonce + ciphertext + tag

// Decrypt
let box = try AES.GCM.SealedBox(combined: encryptedData)
let decryptedData = try AES.GCM.open(box, using: symmetricKey)
```

**Security Properties:**
- AES-256-GCM: Authenticated encryption with associated data
- Secure Enclave: Key never leaves hardware boundary
- iOS Data Protection: Additional encryption layer when device locked
- No FIPS workarounds needed—using actual standard algorithms

**Files:**
- `ios/Rial/Core/Crypto/CaptureEncryption.swift` - AES-GCM encryption
- `ios/Rial/Core/Crypto/SecureKeychain.swift` - Keychain wrapper
- `ios/Rial/Core/Storage/OfflineQueue.swift` - Encrypted file I/O

---

## Performance Considerations

| Metric | Target | Strategy |
|--------|--------|----------|
| Capture → processing complete | < 30s | Parallel tier computation |
| Verification page FCP | < 1.5s | CDN for media, edge caching |
| Upload throughput | 10 MB/s | Multipart upload, presigned URLs |
| Evidence computation | < 10s | Tokio task parallelism |

---

## Deployment Architecture

### Phase 0 (Hackathon)

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Mobile App    │────▶│  Rust Backend   │────▶│   PostgreSQL    │
│   (Rial)        │     │  (Single node)  │     │   (RDS)         │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ▼                        ▼                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   S3 Bucket     │     │   CloudFront    │     │   Next.js Web   │
│   (Media)       │◀────│   (CDN)         │────▶│   (Vercel)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## Development Environment

### Prerequisites

- Xcode 16+ with Swift 5.9+
- Rust 1.82+ (for c2pa-rs 0.51)
- PostgreSQL 16
- Docker (for local dev)
- Node.js 22+ (web app only)
- iPhone Pro device (12 Pro or later) — required for LiDAR and Secure Enclave

### Setup Commands

```bash
# Clone and setup
git clone https://github.com/your-org/rial.git
cd rial

# Start local services
docker-compose up -d  # Postgres, LocalStack (S3)

# Backend
cd backend
cp .env.example .env
cargo run

# iOS App (requires Mac + Xcode + iPhone Pro device)
cd ios
open Rial.xcodeproj
# In Xcode: Select your iPhone Pro device (not simulator)
# Press ⌘R to build and run

# Web
cd apps/web
npm install
npm run dev
```

**Note:** The iOS app requires a physical iPhone Pro device. Simulator cannot access LiDAR or Secure Enclave for attestation.

---

## Architecture Decision Records (ADRs)

### ADR-001: iPhone Pro Only (MVP)

**Context:** Cross-platform development doubles native code complexity.

**Decision:** Target iPhone Pro exclusively for MVP.

**Rationale:**
- LiDAR sensor is our primary authenticity signal
- All iPhone Pro models (12+) have consistent hardware
- Eliminates Android StrongBox fragmentation issues
- 50% less native code to write and maintain

**Consequences:** No Android users for MVP. Can expand post-validation.

---

### ADR-002: ~~Expo Modules API for LiDAR Depth Capture~~ DEPRECATED

**Status:** DEPRECATED — Superseded by ADR-009 (Native Swift Architecture)

**Original Decision:** Use Expo Modules API to create custom Swift module for LiDAR depth capture.

**Deprecated Because:** The entire mobile app is now native Swift. No Expo Modules needed—ARKit is accessed directly.

---

### ADR-003: Rust Backend with Axum

**Context:** Backend needs to verify attestation, analyze depth, generate C2PA.

**Decision:** Rust with Axum framework.

**Rationale:**
- c2pa-rs is the official C2PA SDK (Rust)
- Memory safety critical for security-focused app
- Excellent async performance with Tokio

**Consequences:** Team needs Rust expertise.

---

### ADR-004: LiDAR Depth as Primary Evidence

**Context:** Need a signal that's hard to spoof for "real scene" verification.

**Decision:** Use LiDAR depth map analysis as primary authenticity check.

**Rationale:**
- Real 3D scenes have high depth variance, multiple layers
- Flat images/screens have uniform depth (~0.3-0.5m)
- Captured simultaneously with photo, hard to fake
- iPhone Pro has consistent LiDAR implementation

**Consequences:** Limits to iPhone Pro users. Worth it for signal quality.

---

### ADR-005: Device-Based Authentication (No Tokens)

**Context:** Need to authenticate API requests without user accounts.

**Decision:** Sign every request with Secure Enclave-backed key.

**Rationale:**
- No bearer tokens to steal
- Authentication tied to hardware attestation
- Each request independently verifiable

**Consequences:** Slightly higher request overhead (signature computation).

---

### ADR-006: JSONB for Evidence Storage

**Context:** Evidence structure will evolve as we add new checks.

**Decision:** Store evidence as JSONB column in PostgreSQL.

**Rationale:**
- Flexible schema for evolving checks
- Native PostgreSQL indexing
- Easy to add new evidence types

**Consequences:** Must validate JSON structure in application code.

---

### ADR-007: ~~@expo/app-integrity for DCAppAttest~~ DEPRECATED

**Status:** DEPRECATED — Superseded by ADR-009 (Native Swift Architecture)

**Original Decision:** Use `@expo/app-integrity` as primary attestation library.

**Deprecated Because:** Native Swift uses DeviceCheck framework directly. No wrapper needed.

---

### ADR-008: ~~react-native-vision-camera for Photo Capture~~ DEPRECATED

**Status:** DEPRECATED — Superseded by ADR-009 (Native Swift Architecture)

**Original Decision:** Replace `expo-camera` with `react-native-vision-camera` for physical lens switching.

**Deprecated Because:** Native Swift uses ARKit directly, which provides both camera capture and depth in a single unified frame. No camera library needed.

---

### ADR-009: Native Swift Architecture for iOS App

**Context:** RealityCam (now **rial.**) is a security-focused photo verification app where trust is the core value proposition. The original architecture used Expo/React Native with custom native modules for security-critical functionality (DCAppAttest, LiDAR depth capture). This introduced multiple abstraction layers and JS↔Native bridge crossings for sensitive data.

**Decision:** Rebuild the iOS app as pure Swift/SwiftUI using only Apple's native frameworks.

**Rationale:**

| Aspect | React Native | Native Swift | Winner |
|--------|--------------|--------------|--------|
| Attack surface | JS engine + bridge + native modules | Single compiled binary | Native |
| Sensitive data handling | Crosses JS↔Native boundary | Stays in process memory | Native |
| Cryptography | Workarounds (SHA-256 stream cipher) | Real AES-GCM via CryptoKit | Native |
| Camera/Depth sync | Two modules + JS coordination | Single ARFrame | Native |
| Background uploads | Foreground only, dies if app killed | URLSession continues after termination | Native |
| Security audit | Multiple languages, frameworks | Single language, known APIs | Native |
| Dependencies | npm + native modules (supply chain risk) | Zero external packages | Native |

**Key Technical Benefits:**

1. **Security Boundary:** Photo bytes → hash → assertion → encrypted upload happens entirely within controlled Swift memory. No JS bridge crossings.

2. **Perfect Capture Sync:** ARKit provides RGB + depth in a single `ARFrame`—no timing coordination needed.

3. **Real Encryption:** CryptoKit AES-GCM instead of SHA-256 stream cipher workaround.

4. **Background Uploads:** URLSession background tasks continue even if iOS terminates the app.

5. **Smaller Binary:** No Hermes JS engine, no Metro bundler, no JS bundle.

**Trade-offs:**

- (+) Maximum security posture for a trust-focused product
- (+) Direct OS API access
- (+) Easier to audit
- (-) Requires Swift expertise (not TypeScript)
- (-) Longer initial development (rewrite, not iteration)
- (-) Separate codebase from web (but backend/API shared)

**Consequences:**

- New `ios/` directory with Xcode project
- `apps/mobile/` (Expo/RN) kept as reference for feature parity testing
- All mobile stories in Epics 2-4 superseded by new Epic 6
- Team needs Swift/SwiftUI skills
- No path to Android from this codebase (would be separate Kotlin app if ever needed)

**Decision Date:** 2025-11-25
**Decision Maker:** Luca

---

### ADR-010: Video Architecture with LiDAR Depth

**Context:** Epic 7 extends rial. to capture authenticated video with LiDAR depth verification. Video introduces unique challenges: frame-by-frame integrity, recording interruptions, and temporal depth analysis.

**Decision:** Implement video capture with these core patterns:

1. **Hash Chain Integrity**
2. **Checkpoint Attestation**
3. **10fps Depth Keyframes**
4. **Edge-Only Overlay**

**Pattern 1: Hash Chain Integrity**

Each video frame is cryptographically chained to the previous frame:

```
H(n) = SHA256(frame_n + depth_n + timestamp_n + H(n-1))
```

This ensures:
- No frames can be inserted (chain would break)
- No frames can be removed (chain would break)
- No frames can be reordered (previous hash wouldn't match)

**Rationale:** Established cryptographic pattern. Used in blockchain, Chronicle, and similar tamper-evident systems. Validated via Exa research against Facebook ThreatExchange vPDQ/TMK.

**Pattern 2: Checkpoint Attestation**

DCAppAttest signs hash at 5-second intervals:

```
Checkpoints: [H(150), H(300), H(450)]  // at 5s, 10s, 15s
```

If recording is interrupted at 12 seconds:
- Last complete checkpoint (10s) is attested
- Verification shows "Verified: 10s of 12s recorded"

**Rationale:** Novel pattern for rial. Ensures partial video evidence is still cryptographically valid. Similar to blockchain checkpoint concepts.

**Pattern 3: 10fps Depth Keyframes**

Capture depth every 3rd frame (30fps video → 10fps depth):

| Duration | Video Frames | Depth Keyframes | Depth Size |
|----------|--------------|-----------------|------------|
| 5s | 150 | 50 | ~3MB |
| 10s | 300 | 100 | ~7MB |
| 15s | 450 | 150 | ~10MB |

**Rationale:** Balance between forensic coverage and file size. 10fps is sufficient for detecting temporal depth inconsistencies while keeping total upload size manageable (~30-45MB).

**Pattern 4: Edge-Only Overlay**

Use Sobel edge detection on depth buffer instead of full colormap:

```metal
// Sobel edge detection - ~3x faster than colormap
float edge = sqrt(gx*gx + gy*gy);
float alpha = edge > threshold ? 0.8 : 0.0;
```

**Rationale:** Full colormap visualization exceeds GPU performance budget during recording. Edge detection provides sufficient depth visibility at 30fps with < 3ms per frame.

**Consequences:**

- New services: HashChainService, VideoAttestationService, DepthKeyframeBuffer
- New backend: hash_chain_verifier, video_depth_analysis, c2pa_video
- New API: POST /api/v1/captures/video
- Total upload size: ~30-45MB per 15s video
- Partial video verification possible via checkpoints

**Decision Date:** 2025-11-26
**Decision Maker:** Luca

---

## MVP Scope Summary

### In Scope
- iPhone Pro (12 Pro, 13 Pro, 14 Pro, 15 Pro, 16 Pro, 17 Pro)
- Photo capture with LiDAR depth
- **Video capture (15s max) with 10fps depth keyframes** *(Epic 7)*
- **Hash chain integrity for video frames** *(Epic 7)*
- **Checkpoint attestation for interrupted videos** *(Epic 7)*
- Hardware attestation (DCAppAttest + Secure Enclave)
- LiDAR depth analysis (photo + temporal analysis for video)
- Basic metadata checks
- C2PA manifest generation (photo + video)
- Verification web page (photo + video playback)

### Explicitly Deferred (Post-MVP)
| Feature | Reason for Deferral |
|---------|---------------------|
| Android support | Adds 50% native code, StrongBox fragmentation |
| Extended video (>15s) | Thermal throttling, larger file sizes, UX complexity |
| Delta depth compression | Optimization for v2 (simpler keyframe approach for MVP) |
| Sun angle computation | Requires solar position API integration |
| Barometric pressure | Requires weather/altitude correlation |
| 360° environment scan | Complex UX, parallax computation |
| Gyro × optical flow | Cross-modal correlation complexity |
| User accounts | Device-only auth sufficient for MVP |

### Supported Devices
| Model | Released | LiDAR | Secure Enclave |
|-------|----------|-------|----------------|
| iPhone 17 Pro / Pro Max | 2025 | ✅ | ✅ |
| iPhone 16 Pro / Pro Max | 2024 | ✅ | ✅ |
| iPhone 15 Pro / Pro Max | 2023 | ✅ | ✅ |
| iPhone 14 Pro / Pro Max | 2022 | ✅ | ✅ |
| iPhone 13 Pro / Pro Max | 2021 | ✅ | ✅ |
| iPhone 12 Pro / Pro Max | 2020 | ✅ | ✅ |

---

_Generated by BMAD Decision Architecture Workflow v1.3 (MVP + Video)_
_Date: 2025-11-26_
_For: Luca_
_Updated: Added ADR-010 for Epic 7 Video Architecture_
