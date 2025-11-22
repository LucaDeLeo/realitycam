# RealityCam - Architecture Document

**Author:** Luca
**Architect:** Winston (BMAD)
**Date:** 2025-11-21
**Version:** 1.0

---

## Executive Summary

RealityCam is a multi-component system providing cryptographically-attested, physics-verified media provenance. The architecture prioritizes hardware-rooted trust, graduated evidence strength, and C2PA ecosystem interoperability.

**Core Components:**
- **Mobile App** (React Native/Expo): Secure capture with hardware attestation
- **Backend** (Rust/Axum): Evidence computation, C2PA manifest generation
- **Verification Web** (Next.js 16): Public verification interface

**Key Architectural Principles:**
1. Hardware attestation as foundation, not enhancement
2. Evidence tiers ordered by cost-to-spoof
3. Transparency over security theater
4. Offline-first with encrypted local storage

---

## Project Initialization

**First implementation story should execute these commands:**

### Mobile App
```bash
npx create-expo-app@latest realitycam-mobile --template blank-typescript
cd realitycam-mobile
npx expo install expo-camera expo-sensors expo-crypto expo-secure-store
npx expo install react-native-vision-camera
npx expo prebuild  # Generate native projects for custom modules
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

| Category | Decision | Version | Affects FRs | Rationale |
|----------|----------|---------|-------------|-----------|
| Mobile Framework | Expo + React Native | SDK 52+ | All mobile | TypeScript, prebuild for native modules |
| Web Framework | Next.js | 16.0.x | FR44-58 | Turbopack, App Router, React 19 |
| Backend Framework | Axum | 0.8.x | All backend | Type-safe, Tokio ecosystem, Tower middleware |
| Database | PostgreSQL | 16 | All | JSONB for evidence, TIMESTAMPTZ, robust |
| ORM | SQLx | 0.8.x | All backend | Compile-time checked queries |
| C2PA SDK | c2pa-rs | 0.49.x | FR40-43 | Official CAI SDK |
| State Management | Zustand | Latest | Mobile | Lightweight, persist middleware |
| File Storage | S3 + CloudFront | - | FR43 | Presigned URLs, CDN delivery |
| Attestation (iOS) | DCAppAttest | iOS 14+ | FR1-6 | Secure Enclave backed |
| Attestation (Android) | Key Attestation | API 28+ | FR1-6 | StrongBox/TEE backed |
| Auth Pattern | Device Signature | Ed25519 | FR59-60 | No tokens, hardware-bound |
| Sensor Format | MessagePack | - | FR9-11 | 60% smaller than JSON |
| Testing (Mobile) | Jest + Maestro | - | All | Unit + E2E on real devices |
| Testing (Backend) | cargo test + testcontainers | - | All | Integration with real Postgres |
| Testing (Web) | Vitest + Playwright | - | All | Fast unit + E2E |

---

## Project Structure

```
realitycam/
├── apps/
│   ├── mobile/                          # Expo React Native app
│   │   ├── app/                         # Expo Router file-based routing
│   │   │   ├── (tabs)/
│   │   │   │   ├── _layout.tsx
│   │   │   │   ├── capture.tsx          # Main capture screen
│   │   │   │   └── history.tsx          # Local capture history
│   │   │   ├── capture/
│   │   │   │   ├── scan.tsx             # 360° environment scan
│   │   │   │   ├── preview.tsx          # Pre-upload preview
│   │   │   │   └── result.tsx           # Post-upload verification link
│   │   │   └── _layout.tsx
│   │   ├── components/
│   │   │   ├── Camera/
│   │   │   │   ├── CaptureButton.tsx
│   │   │   │   ├── ScanGuide.tsx
│   │   │   │   └── SensorOverlay.tsx
│   │   │   └── Evidence/
│   │   │       └── ConfidenceBadge.tsx
│   │   ├── hooks/
│   │   │   ├── useAttestation.ts
│   │   │   ├── useCapture.ts
│   │   │   ├── useSensors.ts
│   │   │   └── useUploadQueue.ts
│   │   ├── modules/
│   │   │   └── device-attestation/      # Custom Expo Module
│   │   │       ├── index.ts
│   │   │       ├── ios/
│   │   │       │   ├── DeviceAttestationModule.swift
│   │   │       │   └── SecureEnclaveManager.swift
│   │   │       ├── android/
│   │   │       │   ├── DeviceAttestationModule.kt
│   │   │       │   └── KeyAttestationManager.kt
│   │   │       └── expo-module.config.json
│   │   ├── store/
│   │   │   ├── captureStore.ts
│   │   │   └── deviceStore.ts
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
│       │   │   ├── TierCard.tsx
│       │   │   ├── ConfidenceSummary.tsx
│       │   │   └── StatusBadge.tsx
│       │   ├── Media/
│       │   │   ├── SecureImage.tsx
│       │   │   └── ContextViewer.tsx
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
│   │   │   ├── attestation/
│   │   │   │   ├── android.rs
│   │   │   │   └── ios.rs
│   │   │   ├── evidence/
│   │   │   │   ├── pipeline.rs
│   │   │   │   ├── tier1_hardware.rs
│   │   │   │   ├── tier2_physics.rs
│   │   │   │   ├── tier3_crossmodal.rs
│   │   │   │   └── tier4_metadata.rs
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

## FR Category to Architecture Mapping

| FR Category | Primary Location | Supporting |
|-------------|------------------|------------|
| Device & Attestation (FR1-6) | `mobile/modules/device-attestation/` | `backend/services/attestation/` |
| Capture Flow (FR7-18) | `mobile/app/capture/`, `mobile/hooks/` | - |
| Local Processing (FR19-23) | `mobile/hooks/useCapture.ts` | - |
| Upload & Sync (FR24-29) | `mobile/hooks/useUploadQueue.ts` | `backend/routes/captures.rs` |
| Evidence Generation (FR30-39) | `backend/services/evidence/` | - |
| C2PA Integration (FR40-43) | `backend/services/c2pa.rs` | - |
| Verification Interface (FR44-53) | `web/app/verify/`, `web/components/` | `backend/routes/captures.rs` |
| File Verification (FR54-58) | `web/components/Upload/` | `backend/routes/verify.rs` |
| User & Device Mgmt (FR59-65) | `backend/routes/devices.rs` | `mobile/store/deviceStore.ts` |
| Privacy Controls (FR66-70) | All components | - |

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
c2pa = { version = "0.49", features = ["file_io"] }

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
    "expo": "~52.0.0",
    "expo-camera": "~16.0.0",
    "expo-sensors": "~14.0.0",
    "expo-crypto": "~14.0.0",
    "expo-secure-store": "~14.0.0",
    "expo-file-system": "~18.0.0",
    "react-native-vision-camera": "^4.0.0",
    "zustand": "^5.0.0",
    "@msgpack/msgpack": "^3.0.0"
  }
}
```

---

## Novel Pattern: Evidence Hierarchy

This is the core innovation — evidence tiers ordered by cost-to-spoof:

### Tier 1: Hardware-Rooted (Highest)
- Device identity attested by TEE (Android StrongBox) or Secure Enclave (iOS)
- Key generated in HSM, never extractable
- **Spoofing cost:** Custom silicon / firmware exploit

### Tier 2: Physics-Constrained
- Sun angle consistency (computed vs observed shadow direction)
- LiDAR depth analysis (3D geometry vs flat surface)
- Barometric pressure (matches GPS altitude)
- Environment 3D-ness (360° scan parallax)
- **Spoofing cost:** Building physical 3D scene, pressure chamber

### Tier 3: Cross-Modal Consistency
- Gyroscope × optical flow correlation
- Multi-camera lighting consistency
- Accelerometer × motion blur
- **Spoofing cost:** Coordinated synthetic data generation

### Tier 4: Metadata Consistency (Lowest)
- EXIF timestamp within tolerance
- Device model string verification
- Resolution/lens capability match
- **Spoofing cost:** EXIF editor, API hooking

### Confidence Level Calculation

```rust
pub fn calculate_confidence(evidence: &Evidence) -> ConfidenceLevel {
    let tier1_pass = evidence.tier1.attestation.status == Status::Pass;
    let tier2_passes = evidence.tier2.checks.iter().filter(|c| c.status == Status::Pass).count();
    let any_fail = evidence.all_checks().any(|c| c.status == Status::Fail);

    if any_fail {
        return ConfidenceLevel::Suspicious;
    }

    match (tier1_pass, tier2_passes) {
        (true, n) if n >= 2 => ConfidenceLevel::High,
        (true, _) | (false, n) if n >= 2 => ConfidenceLevel::Medium,
        (false, _) => ConfidenceLevel::Low,
    }
}
```

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
  "platform": "android",
  "model": "Pixel 8 Pro",
  "attestation": {
    "public_key": "base64...",
    "cert_chain": ["base64...", "base64..."],
    "challenge": "base64...",
    "signed_challenge": "base64..."
  }
}

Response:
{
  "data": {
    "device_id": "uuid",
    "attestation_level": "hardware_strongbox"
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
- media: binary (JPEG/MP4)
- context: binary (ZIP) [optional]
- metadata: JSON

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
    "capture_type": "photo",
    "media_url": "https://cdn.../signed-url",
    "evidence": {
      "tier1_hardware": { "attestation": { "status": "pass", "level": "hardware_strongbox" } },
      "tier2_physics": { "sun_angle": { "status": "pass" }, ... },
      "tier3_crossmodal": { "gyro_optical_flow": { "status": "pass", "correlation": 0.94 } },
      "tier4_metadata": { "exif_timestamp": { "status": "pass" }, ... }
    },
    "c2pa_manifest_url": "https://cdn.../manifest.c2pa"
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
| Device attestation key | Hardware (StrongBox/Secure Enclave) | Never (device-bound) |
| C2PA signing key | AWS KMS (HSM-backed) | Yearly |
| Database encryption | AWS RDS encryption | Managed |

### Transport Security

- TLS 1.3 required for all endpoints
- Certificate pinning in mobile app (Phase 1)
- Presigned URLs expire in 1 hour

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
- Rust 1.86+ (for c2pa-rs)
- PostgreSQL 16
- Docker (for local dev)
- Xcode 16+ (iOS development)
- Android Studio (Android development)

### Setup Commands

```bash
# Clone and setup
git clone https://github.com/your-org/realitycam.git
cd realitycam

# Start local services
docker-compose up -d  # Postgres, Redis, LocalStack (S3)

# Backend
cd backend
cp .env.example .env
cargo run

# Mobile
cd apps/mobile
npm install
npx expo prebuild
npx expo run:ios  # or run:android

# Web
cd apps/web
npm install
npm run dev
```

---

## Architecture Decision Records (ADRs)

### ADR-001: Expo Modules API for Native Attestation

**Context:** Need hardware-backed key attestation on both platforms.

**Decision:** Use Expo Modules API to create custom Swift/Kotlin modules rather than raw React Native bridge or going fully native.

**Rationale:**
- Type-safe bridge between JS and native
- Better DX than raw native modules
- Maintains single codebase advantage
- Expo actively maintains the API

**Consequences:** ~500-800 lines of native code per platform required.

---

### ADR-002: Rust Backend with Axum

**Context:** Backend needs to verify attestation chains, compute evidence, generate C2PA manifests.

**Decision:** Rust with Axum framework.

**Rationale:**
- c2pa-rs is the official C2PA SDK (Rust)
- Memory safety critical for security-focused app
- Excellent async performance with Tokio
- Type system catches errors at compile time

**Consequences:** Team needs Rust expertise.

---

### ADR-003: Device-Based Authentication (No Tokens)

**Context:** Need to authenticate API requests without user accounts (Phase 0).

**Decision:** Sign every request with hardware-backed device key.

**Rationale:**
- No bearer tokens to steal
- Authentication tied to hardware attestation
- Simpler than JWT/session management
- Each request independently verifiable

**Consequences:** Slightly higher request overhead (signature computation).

---

### ADR-004: JSONB for Evidence Storage

**Context:** Evidence structure will evolve as we add new checks.

**Decision:** Store evidence as JSONB column in PostgreSQL.

**Rationale:**
- Flexible schema for evolving checks
- Native PostgreSQL indexing and querying
- Single column instead of normalized tables
- Easy to serialize/deserialize

**Consequences:** Must validate JSON structure in application code.

---

### ADR-005: Next.js 16 for Verification Web

**Context:** Public verification interface needs fast load times.

**Decision:** Next.js 16 with App Router and Turbopack.

**Rationale:**
- Turbopack provides 5-10x faster builds
- Server components for evidence data fetching
- Strong SEO capabilities
- Vercel deployment simplicity

**Consequences:** Must migrate if using Next.js 14 patterns.

---

_Generated by BMAD Decision Architecture Workflow v1.0_
_Date: 2025-11-21_
_For: Luca_
