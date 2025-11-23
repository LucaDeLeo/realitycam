# RealityCam - Architecture Document

**Author:** Luca
**Architect:** Winston (BMAD)
**Date:** 2025-11-21
**Version:** 1.1 (MVP)

---

## Executive Summary

RealityCam is a focused MVP providing cryptographically-attested, LiDAR-verified photo provenance for iPhone Pro devices. The architecture prioritizes hardware-rooted trust and depth-based authenticity verification.

**Core Components:**
- **iOS App** (Expo/React Native): Photo capture with LiDAR depth and hardware attestation
- **Backend** (Rust/Axum): Evidence computation, C2PA manifest generation
- **Verification Web** (Next.js 16): Public verification interface

**Key Architectural Principles:**
1. Hardware attestation as foundation (Secure Enclave + DCAppAttest)
2. LiDAR depth as primary authenticity signal
3. iPhone Pro only — no cross-platform complexity
4. Photo-first — video deferred to post-MVP

**Why iPhone Pro Only:**
- LiDAR sensor enables "real 3D scene" vs "flat image" detection
- Consistent hardware: all Pro models have Secure Enclave + LiDAR
- Eliminates Android fragmentation (StrongBox availability varies)
- 50% less native code, faster iteration to working demo

---

## Project Initialization

**First implementation story should execute these commands:**

### iOS App
```bash
bunx create-expo-app@latest realitycam-mobile --template blank-typescript
cd realitycam-mobile
bunx expo install expo-camera expo-sensors expo-crypto expo-secure-store expo-file-system
bunx expo prebuild --platform ios  # iOS only for MVP
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
| Platform | iPhone Pro only | iOS 14+ | LiDAR required for depth verification |
| Mobile Framework | Expo + React Native | SDK 53 | TypeScript, React Native 0.79, prebuild for native |
| Web Framework | Next.js | 16 | Turbopack default, Cache Components, React 19.2 |
| Backend Framework | Axum | 0.8.x | Type-safe, Tokio ecosystem, c2pa-rs native |
| Database | PostgreSQL | 16 | JSONB for evidence, TIMESTAMPTZ |
| ORM | SQLx | 0.8.x | Compile-time checked queries |
| C2PA SDK | c2pa-rs | 0.51.x | Official CAI SDK, Rust 1.82+ |
| State Management | Zustand | Latest | Lightweight, persist middleware |
| File Storage | S3 + CloudFront | - | Presigned URLs, CDN delivery |
| Attestation Library | @expo/app-integrity | ~1.0.0 | Official Expo DCAppAttest wrapper |
| Attestation API | DCAppAttest | iOS 14+ | Secure Enclave backed |
| Depth Capture | Custom Expo Module | Swift | ARKit LiDAR (~400 lines) |
| Auth Pattern | Device Signature | Ed25519 | No tokens, hardware-bound |
| Testing (Mobile) | Jest + Maestro | - | Unit + E2E on real devices |
| Testing (Backend) | cargo test + testcontainers | - | Integration with real Postgres |
| Testing (Web) | Vitest + Playwright | - | Fast unit + E2E |

---

## Project Structure

```
realitycam/
├── apps/
│   ├── mobile/                          # iOS Expo app (iPhone Pro only)
│   │   ├── app/                         # Expo Router file-based routing
│   │   │   ├── (tabs)/
│   │   │   │   ├── _layout.tsx
│   │   │   │   ├── capture.tsx          # Main capture screen
│   │   │   │   └── history.tsx          # Local capture history
│   │   │   ├── preview.tsx              # Pre-upload preview with depth viz
│   │   │   ├── result.tsx               # Post-upload verification link
│   │   │   └── _layout.tsx
│   │   ├── components/
│   │   │   ├── Camera/
│   │   │   │   ├── CaptureButton.tsx
│   │   │   │   └── DepthOverlay.tsx     # LiDAR depth visualization
│   │   │   └── Evidence/
│   │   │       └── ConfidenceBadge.tsx
│   │   ├── hooks/
│   │   │   ├── useDeviceAttestation.ts  # @expo/app-integrity wrapper
│   │   │   ├── useCapture.ts            # Photo + depth capture orchestration
│   │   │   ├── useLiDAR.ts              # Custom LiDAR module wrapper
│   │   │   └── useUploadQueue.ts
│   │   ├── modules/
│   │   │   └── lidar-depth/             # Custom Expo Module (iOS only, ~400 lines)
│   │   │       ├── index.ts
│   │   │       ├── ios/
│   │   │       │   ├── LiDARDepthModule.swift
│   │   │       │   └── DepthCaptureSession.swift
│   │   │       └── expo-module.config.json
│   │   ├── store/
│   │   │   └── captureStore.ts
│   │   ├── services/
│   │   │   └── api.ts
│   │   ├── app.config.ts
│   │   └── package.json
│   │
│   └── web/                             # Next.js 16 verification site
│       ├── app/
│       │   ├── page.tsx
│       │   ├── verify/[id]/page.tsx
│       │   └── layout.tsx
│       ├── components/
│       │   ├── Evidence/
│       │   │   ├── EvidencePanel.tsx
│       │   │   ├── DepthAnalysis.tsx    # LiDAR depth visualization
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
│   │   │   ├── devices.rs
│   │   │   ├── captures.rs
│   │   │   └── verify.rs
│   │   ├── middleware/
│   │   │   ├── device_auth.rs
│   │   │   └── request_id.rs
│   │   ├── services/
│   │   │   ├── attestation.rs           # iOS DCAppAttest verification
│   │   │   ├── evidence/
│   │   │   │   ├── mod.rs
│   │   │   │   ├── hardware.rs          # Attestation checks
│   │   │   │   ├── depth.rs             # LiDAR depth analysis
│   │   │   │   └── metadata.rs          # EXIF/device checks
│   │   │   ├── c2pa.rs
│   │   │   └── storage.rs
│   │   ├── models/
│   │   │   ├── device.rs
│   │   │   ├── capture.rs
│   │   │   └── evidence.rs
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
| Device & Attestation | `mobile/hooks/useDeviceAttestation.ts` | @expo/app-integrity wrapper |
| LiDAR Depth Capture | `mobile/modules/lidar-depth/ios/` | Custom ARKit depth module |
| Photo Capture | `mobile/app/capture.tsx`, `mobile/hooks/` | Photo only for MVP |
| Upload & Sync | `mobile/hooks/useUploadQueue.ts` | `backend/routes/captures.rs` |
| Evidence Generation | `backend/services/evidence/` | Hardware + Depth + Metadata |
| C2PA Integration | `backend/services/c2pa.rs` | Manifest embedding |
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

# C2PA
c2pa = { version = "0.51", features = ["file_io"] }

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

### Mobile Dependencies (package.json)

```json
{
  "dependencies": {
    "expo": "~53.0.0",
    "@expo/app-integrity": "~1.0.0",
    "expo-camera": "~17.0.0",
    "expo-crypto": "~15.0.0",
    "expo-secure-store": "~15.0.0",
    "expo-file-system": "~19.0.0",
    "zustand": "^5.0.0"
  }
}
```

**Notes:**
- `@expo/app-integrity`: DCAppAttest integration (device registration + per-capture assertions)
- LiDAR depth capture: Custom Expo Module in Swift (~400 lines), see `modules/lidar-depth/`
- `expo-sensors`: Deferred to post-MVP (needed for video gyro×optical-flow analysis)

### Mobile Library Decisions

**Evaluated Libraries:**

| Library | Decision | Rationale |
|---------|----------|-----------|
| `@expo/app-integrity` | ✅ Use | Official Expo DCAppAttest wrapper, maintained, TypeScript |
| `expo-camera` | ✅ Use | Photo capture, official Expo |
| `expo-crypto` | ✅ Use | SHA-256 hashing, official Expo |
| `expo-secure-store` | ✅ Use | Encrypted offline storage |
| `expo-sensors` | ⏸️ Defer | Gyro/accel only needed for video (post-MVP) |
| `react-native-attestation` | ❌ Skip | Redundant with @expo/app-integrity |
| `react-native-secure-enclave-operations` | ❌ Skip | Redundant with @expo/app-integrity |
| `ExifReader` | ❌ Skip | Backend handles EXIF validation, not client |

**Custom Module Required:**

No existing library provides ARKit LiDAR depth capture. The `lidar-depth` Expo Module must implement:
1. Start `ARSession` with `.sceneDepth` configuration
2. Capture `ARFrame.sceneDepth.depthMap` synchronized with photo
3. Extract `CVPixelBuffer` → `float32[]` array
4. Real-time depth overlay for camera preview (FR6)

**Attestation vs Assertion (Important Distinction):**

```typescript
// ONE-TIME: Device registration (on first launch)
const keyId = await AppIntegrity.generateKeyAsync();
const attestation = await AppIntegrity.attestKeyAsync(keyId, challenge);
// → Send to POST /api/v1/devices/register

// PER-CAPTURE: Assertion for each photo (proves this capture came from attested device)
const clientDataHash = await Crypto.digestStringAsync(SHA256, captureMetadata);
const assertion = await AppIntegrity.generateAssertionAsync(keyId, clientDataHash);
// → Include in POST /api/v1/captures
```

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

### Local Storage Encryption (Story 4.3)

Offline captures are encrypted locally before storage using a Secure Enclave-backed key:

| Component | Implementation | Notes |
|-----------|---------------|-------|
| Key Storage | `expo-secure-store` | WHEN_UNLOCKED_THIS_DEVICE_ONLY (Secure Enclave backed) |
| Key Derivation | SHA-256 stream | Expands 256-bit key to data length via counter mode |
| Encryption | XOR with key stream | Provides confidentiality equivalent to AES-256-CTR |
| Auth Tag | HMAC-SHA256 | 32-byte tag appended to ciphertext for tamper detection |
| IV | 12-byte random | Unique per capture, stored in encryption.json |

**Implementation Note:** React Native lacks native AES-GCM support. The implementation uses SHA-256 in counter mode with HMAC authentication, providing equivalent security properties to AES-256-GCM but is not FIPS-compliant. For production deployments requiring FIPS compliance, consider `react-native-quick-crypto` native module.

**Files:**
- `apps/mobile/services/captureEncryption.ts` - Encryption/decryption logic
- `apps/mobile/services/offlineStorage.ts` - File I/O with encryption

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
│   (Expo Go)     │     │  (Single node)  │     │   (RDS)         │
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

- Node.js 22+
- Rust 1.82+ (for c2pa-rs 0.51)
- PostgreSQL 16
- Docker (for local dev)
- Xcode 16+ (iOS development)
- iPhone Pro device (12 Pro or later) for LiDAR testing

### Setup Commands

```bash
# Clone and setup
git clone https://github.com/your-org/realitycam.git
cd realitycam

# Start local services
docker-compose up -d  # Postgres, LocalStack (S3)

# Backend
cd backend
cp .env.example .env
cargo run

# Mobile (iOS only - requires Mac + Xcode)
cd apps/mobile
npm install
npx expo prebuild --platform ios
npx expo run:ios  # Requires iPhone Pro device for LiDAR

# Web
cd apps/web
npm install
npm run dev
```

**Note:** LiDAR features require a physical iPhone Pro device. Simulator can be used for non-LiDAR flows.

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

### ADR-002: Expo Modules API for LiDAR Depth Capture

**Context:** Need ARKit LiDAR depth capture on iOS. No existing library provides this.

**Decision:** Use Expo Modules API to create custom Swift module for LiDAR depth capture only. Use `@expo/app-integrity` for DCAppAttest (no custom attestation code needed).

**Rationale:**
- `@expo/app-integrity` handles attestation — no need to reimplement DCAppAttest
- Custom module focused solely on LiDAR depth extraction
- Type-safe bridge between JS and native via Expo Modules API
- Expo actively maintains the API

**Consequences:** ~400 lines of Swift code for LiDAR depth capture only (reduced from original estimate of 400-600 for attestation + LiDAR).

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

### ADR-007: @expo/app-integrity for DCAppAttest

**Context:** Need iOS DCAppAttest integration for hardware attestation. Options evaluated:
- Custom Swift module (original plan)
- `@expo/app-integrity` (official Expo package)
- `react-native-attestation` (bifold-wallet project)
- `react-native-secure-enclave-operations`

**Decision:** Use `@expo/app-integrity` as primary attestation library.

**Rationale:**
- Official Expo package = better maintenance, TypeScript types
- Handles both device attestation (one-time) and per-capture assertions
- Reduces custom native code significantly
- Fallback available: `react-native-attestation` if API is insufficient

**Verified:** `@expo/app-integrity` returns attestation/assertion objects as base64 strings for server-side verification (not just booleans). The iOS methods `attestKeyAsync()` and `generateAssertionAsync()` return `Promise<string>` containing the attestation data to send to your server.

**Consequences:**
- No custom Swift code for attestation
- Custom module scope reduced to LiDAR depth capture only (~400 lines vs ~600)
- Dependency on Expo maintaining the package

---

## MVP Scope Summary

### In Scope
- iPhone Pro (12 Pro, 13 Pro, 14 Pro, 15 Pro, 16 Pro)
- Photo capture only
- Hardware attestation (DCAppAttest + Secure Enclave)
- LiDAR depth analysis
- Basic metadata checks
- C2PA manifest generation
- Verification web page

### Explicitly Deferred (Post-MVP)
| Feature | Reason for Deferral |
|---------|---------------------|
| Android support | Adds 50% native code, StrongBox fragmentation |
| Video capture | Complex gyro/optical-flow analysis |
| Sun angle computation | Requires solar position API integration |
| Barometric pressure | Requires weather/altitude correlation |
| 360° environment scan | Complex UX, parallax computation |
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

_Generated by BMAD Decision Architecture Workflow v1.1 (MVP)_
_Date: 2025-11-21_
_For: Luca_
