# Epic Technical Specification: Device Registration & Hardware Attestation

Date: 2025-11-22
Author: Luca
Epic ID: 2
Status: Draft

---

## Overview

Epic 2 establishes the foundational hardware-rooted trust mechanism for RealityCam. This epic implements device registration with DCAppAttest hardware attestation, enabling iPhone Pro devices to cryptographically prove their identity and integrity. The attestation flow creates a trust anchor that all subsequent captures depend upon - without this, photos cannot receive the "secure_enclave" attestation level that signals genuine hardware provenance.

The epic spans both mobile (Expo/React Native) and backend (Rust/Axum) components, implementing the complete attestation lifecycle: device capability detection, Secure Enclave key generation, one-time attestation with Apple's DCAppAttest, server-side verification against Apple's certificate chain, and per-request device signature authentication.

**Business Value:** Device owners can register their iPhone Pro and receive cryptographic attestation proving their device is genuine and uncompromised - the foundation for all provenance claims.

**FRs Covered:** FR1-FR5, FR41-FR43

## Objectives and Scope

### Objectives

1. **Detect iPhone Pro capabilities** - Verify device has LiDAR sensor and Secure Enclave before allowing attestation
2. **Generate hardware-bound keys** - Create Ed25519-compatible key pairs in iOS Secure Enclave via @expo/app-integrity
3. **Integrate DCAppAttest** - Request and obtain attestation certificate from Apple for device registration
4. **Backend device verification** - Verify attestation objects against Apple's certificate chain
5. **Device signature authentication** - Enable per-request signing for all authenticated API calls
6. **Pseudonymous device identity** - Establish device-level identity without user accounts

### In Scope

| Component | Scope |
|-----------|-------|
| Mobile | Device model detection, LiDAR availability check, key generation, attestation request, device signature for requests |
| Backend | Challenge endpoint, device registration endpoint, attestation verification, device auth middleware |
| Database | devices table usage for storing attestation data |
| Storage | Attestation key ID and chain storage |

### Out of Scope

- User accounts (device-only auth for MVP)
- Per-capture assertions (Epic 3)
- Capture upload flow (Epic 4)
- Certificate pinning (post-MVP)
- Android Key Attestation (post-MVP)

## System Architecture Alignment

### Components Referenced

| Component | Location | Role |
|-----------|----------|------|
| Mobile App | `apps/mobile/` | Device detection, key generation, attestation requests |
| Backend API | `backend/` | Attestation verification, device registration |
| Database | PostgreSQL | devices table for attestation storage |

### Architecture Patterns Applied

1. **Device-Based Authentication (ADR-005):** Sign every request with Secure Enclave-backed key - no bearer tokens
2. **@expo/app-integrity for DCAppAttest (ADR-007):** Official Expo package handles attestation
3. **iPhone Pro Only (ADR-001):** LiDAR check gates full attestation flow

### Technology Stack

| Layer | Technology | Version |
|-------|------------|---------|
| Mobile | @expo/app-integrity | ~1.0.0 |
| Mobile | expo-device | Latest |
| Mobile | expo-secure-store | ~15.0.0 |
| Mobile | zustand | ^5.0.0 |
| Backend | x509-parser | 0.16 |
| Backend | ed25519-dalek | 2 |
| Backend | sha2 | 0.10 |

### Constraints

- DCAppAttest requires iOS 14.0+
- Attestation is ONE-TIME per key - cannot re-attest
- Key generation fails on jailbroken devices
- Challenge nonces expire after 5 minutes

## Detailed Design

### Services and Modules

#### Mobile Services

| Module | Location | Responsibilities |
|--------|----------|------------------|
| useDeviceCapabilities | `hooks/useDeviceCapabilities.ts` | Detect device model, iOS version, LiDAR, Secure Enclave |
| useDeviceAttestation | `hooks/useDeviceAttestation.ts` | Wrap @expo/app-integrity, manage attestation lifecycle |
| deviceStore | `store/deviceStore.ts` | Zustand store for device state, attestation level |
| api.ts | `services/api.ts` | API client with device signature headers |

#### Backend Services

| Module | Location | Responsibilities |
|--------|----------|------------------|
| devices.rs | `routes/devices.rs` | `/challenge` and `/register` endpoints |
| attestation.rs | `services/attestation.rs` | DCAppAttest verification logic |
| device_auth.rs | `middleware/device_auth.rs` | Request signature verification |
| challenge_store.rs | `services/challenge_store.rs` | In-memory challenge storage with expiry |

### Data Models and Contracts

#### Database: devices Table

```sql
CREATE TABLE devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attestation_level   TEXT NOT NULL,        -- 'secure_enclave' | 'unverified'
    attestation_key_id  TEXT NOT NULL UNIQUE, -- DCAppAttest key ID
    attestation_chain   BYTEA,                -- Certificate chain (DER encoded)
    platform            TEXT NOT NULL,        -- 'ios'
    model               TEXT NOT NULL,        -- 'iPhone 15 Pro'
    has_lidar           BOOLEAN NOT NULL DEFAULT true,
    assertion_counter   BIGINT NOT NULL DEFAULT 0, -- Replay protection
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_devices_key_id ON devices(attestation_key_id);
```

#### TypeScript Types (Mobile)

```typescript
// Device capability detection result
interface DeviceCapabilities {
  model: string;                    // "iPhone 15 Pro"
  iosVersion: string;               // "17.1"
  hasLiDAR: boolean;
  hasSecureEnclave: boolean;
  isSupported: boolean;             // All requirements met
  unsupportedReason?: string;       // Human-readable explanation
}

// Device registration state
interface DeviceState {
  deviceId: string | null;          // UUID from backend
  keyId: string | null;             // Secure Enclave key ID
  attestationLevel: 'secure_enclave' | 'unverified' | null;
  isRegistered: boolean;
  registrationError?: string;
}

// Challenge response
interface ChallengeResponse {
  data: {
    challenge: string;              // Base64-encoded 32 bytes
    expires_at: string;             // ISO timestamp
  }
}

// Registration request
interface DeviceRegistrationRequest {
  platform: 'ios';
  model: string;
  has_lidar: boolean;
  attestation: {
    key_id: string;                 // Base64
    attestation_object: string;     // Base64 CBOR
    challenge: string;              // Base64
  }
}

// Registration response
interface DeviceRegistrationResponse {
  data: {
    device_id: string;              // UUID
    attestation_level: 'secure_enclave' | 'unverified';
    has_lidar: boolean;
  }
}
```

#### Rust Types (Backend)

```rust
// Challenge storage entry
pub struct ChallengeEntry {
    pub challenge: [u8; 32],
    pub expires_at: DateTime<Utc>,
    pub used: bool,
}

// Device registration request
#[derive(Deserialize)]
pub struct DeviceRegistrationRequest {
    pub platform: String,
    pub model: String,
    pub has_lidar: bool,
    pub attestation: AttestationPayload,
}

#[derive(Deserialize)]
pub struct AttestationPayload {
    pub key_id: String,             // Base64
    pub attestation_object: String, // Base64 CBOR
    pub challenge: String,          // Base64
}

// Device registration response
#[derive(Serialize)]
pub struct DeviceRegistrationResponse {
    pub device_id: Uuid,
    pub attestation_level: String,
    pub has_lidar: bool,
}

// Verified attestation result
pub struct VerifiedAttestation {
    pub key_id: String,
    pub level: AttestationLevel,
    pub certificate_chain: Vec<u8>,
    pub counter: u64,
}

pub enum AttestationLevel {
    SecureEnclave,
    Unverified,
}

// Device auth header values
pub struct DeviceAuthHeaders {
    pub device_id: Uuid,
    pub timestamp: i64,             // Unix ms
    pub signature: Vec<u8>,         // Ed25519 signature
}
```

### APIs and Interfaces

#### GET /api/v1/devices/challenge

**Purpose:** Generate cryptographically random challenge for attestation binding

**Request:**
```
GET /api/v1/devices/challenge
```

**Response (200 OK):**
```json
{
  "data": {
    "challenge": "A1B2C3D4E5F6...",
    "expires_at": "2025-11-22T10:35:00Z"
  },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-11-22T10:30:00Z"
  }
}
```

**Error Responses:**
- 429 Too Many Requests (rate limit: 10/min/IP)

**Implementation Notes:**
- Generate 32 cryptographically random bytes
- Store in memory with 5-minute TTL
- Challenge is single-use (invalidated after verification)

---

#### POST /api/v1/devices/register

**Purpose:** Register device with DCAppAttest verification

**Request:**
```
POST /api/v1/devices/register
Content-Type: application/json

{
  "platform": "ios",
  "model": "iPhone 15 Pro",
  "has_lidar": true,
  "attestation": {
    "key_id": "base64...",
    "attestation_object": "base64...",
    "challenge": "base64..."
  }
}
```

**Response (201 Created):**
```json
{
  "data": {
    "device_id": "550e8400-e29b-41d4-a716-446655440000",
    "attestation_level": "secure_enclave",
    "has_lidar": true
  },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-11-22T10:30:00Z"
  }
}
```

**Error Responses:**
- 400 VALIDATION_ERROR - Missing required fields
- 401 ATTESTATION_FAILED - Certificate chain verification failed
- 409 CONFLICT - Key ID already registered

**Implementation Notes:**
- Verify challenge exists and not expired
- Decode CBOR attestation object
- Verify certificate chain roots to Apple CA
- Extract and store public key for future signature verification

---

#### Authenticated Request Format

All authenticated endpoints require these headers:

```
X-Device-Id: {device_uuid}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {base64_signature}
```

**Signature Computation:**
```
message = timestamp_str + "|" + sha256_hex(request_body)
signature = ed25519_sign(message, device_key)
```

**Verification Steps:**
1. Parse device ID, lookup in database
2. Verify timestamp within 5-minute window of server time
3. Reconstruct message from headers + body hash
4. Verify Ed25519 signature against stored public key

### Workflows and Sequencing

#### Device Registration Flow (First Launch)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  DEVICE REGISTRATION FLOW                                                    │
│                                                                              │
│  ┌─────────┐                                        ┌─────────────┐          │
│  │ Mobile  │                                        │   Backend   │          │
│  └────┬────┘                                        └──────┬──────┘          │
│       │                                                    │                 │
│       │  1. Detect device capabilities                     │                 │
│       │     - Check model (iPhone Pro?)                    │                 │
│       │     - Check LiDAR (ARKit)                          │                 │
│       │     - Check Secure Enclave                         │                 │
│       │                                                    │                 │
│       │  2. Generate Secure Enclave key                    │                 │
│       │     AppIntegrity.generateKeyAsync()                │                 │
│       │     → keyId                                        │                 │
│       │                                                    │                 │
│       │  3. Request challenge ────────────────────────────►│                 │
│       │                        GET /devices/challenge      │                 │
│       │                        ◄──────────────────────────│                 │
│       │                        { challenge, expires_at }   │                 │
│       │                                                    │                 │
│       │  4. Request attestation from iOS                   │                 │
│       │     AppIntegrity.attestKeyAsync(keyId, challenge)  │                 │
│       │     → attestationObject (base64)                   │                 │
│       │                                                    │                 │
│       │  5. Register device ───────────────────────────────►│                │
│       │     POST /devices/register                         │                 │
│       │     { platform, model, attestation: {...} }        │                 │
│       │                                                    │                 │
│       │                                                    │  6. Verify:     │
│       │                                                    │     - Challenge │
│       │                                                    │     - Cert chain│
│       │                                                    │     - App ID    │
│       │                                                    │     - Counter   │
│       │                                                    │                 │
│       │                        ◄───────────────────────────│  7. Create      │
│       │                        { device_id, level }        │     device      │
│       │                                                    │                 │
│       │  8. Store device_id, keyId in SecureStore          │                 │
│       │  9. Update Zustand with attestation level          │                 │
│       │ 10. Navigate to capture screen                     │                 │
│       │                                                    │                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Subsequent Launch Flow

```
┌──────────────────────────────────────────────────────────┐
│  SUBSEQUENT LAUNCH                                        │
│                                                           │
│  1. Check SecureStore for existing keyId and device_id    │
│                                                           │
│  IF EXISTS:                                               │
│     - Load into Zustand store                             │
│     - Skip registration, proceed to capture               │
│                                                           │
│  IF NOT EXISTS:                                           │
│     - Trigger registration flow                           │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

#### Device Signature Flow (Per Request)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  DEVICE SIGNATURE (Every Authenticated Request)                           │
│                                                                           │
│  ┌─────────┐                                        ┌─────────────┐       │
│  │ Mobile  │                                        │   Backend   │       │
│  └────┬────┘                                        └──────┬──────┘       │
│       │                                                    │              │
│       │  1. Prepare request body                           │              │
│       │                                                    │              │
│       │  2. Generate clientDataHash:                       │              │
│       │     hash = sha256(request_body)                    │              │
│       │                                                    │              │
│       │  3. Create assertion:                              │              │
│       │     AppIntegrity.generateAssertionAsync(           │              │
│       │       keyId, hash                                  │              │
│       │     )                                              │              │
│       │     → assertion (base64)                           │              │
│       │                                                    │              │
│       │  4. Set headers:                                   │              │
│       │     X-Device-Id: {device_id}                       │              │
│       │     X-Device-Timestamp: {unix_ms}                  │              │
│       │     X-Device-Signature: {assertion}                │              │
│       │                                                    │              │
│       │  5. Send request ──────────────────────────────────►│             │
│       │                                                    │              │
│       │                                     6. Middleware: │              │
│       │                                        - Parse headers           │
│       │                                        - Lookup device           │
│       │                                        - Verify timestamp        │
│       │                                        - Decode assertion        │
│       │                                        - Verify signature        │
│       │                                        - Check counter           │
│       │                                                    │              │
│       │                        ◄───────────────────────────│              │
│       │                        Response or 401             │              │
│       │                                                    │              │
└──────────────────────────────────────────────────────────────────────────┘
```

## Non-Functional Requirements

### Performance

| Metric | Target | Implementation Strategy |
|--------|--------|------------------------|
| Key generation | < 500ms | Secure Enclave is hardware-optimized |
| Attestation request | < 2s | Network-dependent (Apple servers) |
| Challenge generation | < 10ms | CSPRNG, in-memory storage |
| Registration verification | < 500ms | Certificate parsing is fast |
| Signature verification | < 50ms | Ed25519 is performant |

### Security

| Requirement | Implementation |
|-------------|----------------|
| Key protection | Secure Enclave (hardware-bound, non-extractable) |
| Challenge freshness | 5-minute TTL, single-use |
| Replay protection | Assertion counter must strictly increase |
| Transport security | TLS 1.3 required |
| Certificate validation | Apple App Attest CA root embedded in binary |

**DCAppAttest Verification Checklist:**
1. Decode CBOR attestation object
2. Extract `authData` and `attestation statement`
3. Verify `fmt` is `"apple-appattest"`
4. Parse X.509 certificate chain
5. Verify chain roots to Apple App Attest CA
6. Verify `rpIdHash` matches your App ID hash (Team ID + Bundle ID)
7. Verify challenge hash is embedded in `nonce`
8. Extract public key from leaf certificate
9. Verify counter starts at 0

**Threat Mitigations:**

| Threat | Mitigation |
|--------|------------|
| Jailbreak/Frida hooks | DCAppAttest fails on compromised devices |
| Replay attacks | Counter must increase, challenge single-use |
| MITM | TLS 1.3 (cert pinning post-MVP) |
| Key extraction | Secure Enclave keys never leave hardware |
| Spoofed device | Certificate chain verifies Apple origin |

### Reliability/Availability

| Requirement | Target | Strategy |
|-------------|--------|----------|
| Registration success rate | > 99% for genuine devices | Graceful degradation to "unverified" |
| Challenge availability | 99.9% | In-memory with periodic cleanup |
| Offline handling | Full support | Registration only needed once, stored locally |

**Failure Modes:**

| Failure | Response |
|---------|----------|
| DCAppAttest fails | Continue with attestation_level = "unverified" |
| Network timeout | Retry with exponential backoff |
| Challenge expired | Re-request challenge |
| Backend unavailable | Cache device state, retry later |

### Observability

| Metric | Implementation |
|--------|----------------|
| Registration attempts | Counter with outcome (success/fail/degraded) |
| Attestation verification time | Histogram |
| Challenge generation rate | Counter per IP |
| Signature verification failures | Counter with failure reason |

**Logging:**
```rust
// Registration success
tracing::info!(
    device_id = %device.id,
    attestation_level = %device.attestation_level,
    model = %device.model,
    "Device registered"
);

// Verification failure
tracing::warn!(
    device_id = %device_id,
    error = %reason,
    "Attestation verification failed"
);
```

## Dependencies and Integrations

### External Dependencies

| Dependency | Purpose | Version | Risk |
|------------|---------|---------|------|
| @expo/app-integrity | DCAppAttest wrapper | ~1.0.0 | Low - Official Expo |
| expo-device | Model detection | Latest | Low - Official Expo |
| expo-secure-store | Key ID storage | ~15.0.0 | Low - Official Expo |
| x509-parser | Certificate parsing | 0.16 | Low - Well-maintained |
| ed25519-dalek | Signature verification | 2 | Low - Standard |

### Apple Services

| Service | Purpose | Availability |
|---------|---------|--------------|
| DCAppAttest | Device attestation | Requires iOS 14+, device network |
| Apple App Attest CA | Certificate root | Bundled in app |

### Internal Dependencies

| Dependency | From Story | Purpose |
|------------|------------|---------|
| Database schema | 1.3 | devices table |
| API skeleton | 1.4 | Route structure |
| Mobile shell | 1.5 | Navigation, hooks directory |

### Shared Types

Epic 2 introduces these types to `packages/shared/`:

```typescript
// packages/shared/src/types/device.ts
export type AttestationLevel = 'secure_enclave' | 'unverified';
export type Platform = 'ios';

export interface DeviceCapabilities {
  model: string;
  iosVersion: string;
  hasLiDAR: boolean;
  hasSecureEnclave: boolean;
  isSupported: boolean;
  unsupportedReason?: string;
}

export interface DeviceRegistrationRequest {
  platform: Platform;
  model: string;
  has_lidar: boolean;
  attestation: {
    key_id: string;
    attestation_object: string;
    challenge: string;
  };
}

export interface DeviceRegistrationResponse {
  device_id: string;
  attestation_level: AttestationLevel;
  has_lidar: boolean;
}
```

## Acceptance Criteria (Authoritative)

### AC-2.1: Device Capability Detection

| ID | Criterion | Component | Testable |
|----|-----------|-----------|----------|
| AC-2.1.1 | App detects device model string (e.g., "iPhone 15 Pro") on launch | Mobile | Yes |
| AC-2.1.2 | App checks iOS version is 14.0+ | Mobile | Yes |
| AC-2.1.3 | App checks LiDAR availability via ARKit configuration support | Mobile | Yes |
| AC-2.1.4 | App checks Secure Enclave availability | Mobile | Yes |
| AC-2.1.5 | Non-Pro device displays blocking message: "RealityCam requires iPhone Pro with LiDAR sensor" | Mobile | Yes |
| AC-2.1.6 | Supported device proceeds to registration flow | Mobile | Yes |
| AC-2.1.7 | Capabilities stored in Zustand for later use | Mobile | Yes |

### AC-2.2: Secure Enclave Key Generation

| ID | Criterion | Component | Testable |
|----|-----------|-----------|----------|
| AC-2.2.1 | On first launch, `AppIntegrity.generateKeyAsync()` generates hardware-bound key | Mobile | Yes |
| AC-2.2.2 | Key ID returned and stored in `expo-secure-store` with key `attestation_key_id` | Mobile | Yes |
| AC-2.2.3 | Subsequent launches retrieve existing key ID from secure storage | Mobile | Yes |
| AC-2.2.4 | Key generation failure shows error message and sets attestation to "unverified" | Mobile | Yes |

### AC-2.3: Challenge Generation (Backend)

| ID | Criterion | Component | Testable |
|----|-----------|-----------|----------|
| AC-2.3.1 | `GET /api/v1/devices/challenge` returns 32-byte base64 challenge | Backend | Yes |
| AC-2.3.2 | Response includes `expires_at` timestamp 5 minutes in future | Backend | Yes |
| AC-2.3.3 | Challenge stored server-side with TTL | Backend | Yes |
| AC-2.3.4 | Rate limiting: 10 challenges/minute/IP returns 429 | Backend | Yes |
| AC-2.3.5 | Challenge is cryptographically random (CSPRNG) | Backend | Yes |

### AC-2.4: DCAppAttest Attestation Request

| ID | Criterion | Component | Testable |
|----|-----------|-----------|----------|
| AC-2.4.1 | App requests challenge from backend before attestation | Mobile | Yes |
| AC-2.4.2 | App calls `AppIntegrity.attestKeyAsync(keyId, challengeData)` | Mobile | Yes |
| AC-2.4.3 | Attestation object (base64 string) captured for registration | Mobile | Yes |
| AC-2.4.4 | Attestation failure (compromised device) displays warning and continues | Mobile | Yes |

### AC-2.5: Backend DCAppAttest Verification

| ID | Criterion | Component | Testable |
|----|-----------|-----------|----------|
| AC-2.5.1 | `POST /api/v1/devices/register` accepts registration request | Backend | Yes |
| AC-2.5.2 | Backend decodes CBOR attestation object | Backend | Yes |
| AC-2.5.3 | Backend verifies certificate chain roots to Apple App Attest CA | Backend | Yes |
| AC-2.5.4 | Backend verifies challenge matches stored, unexpired challenge | Backend | Yes |
| AC-2.5.5 | Backend verifies App ID hash (Team ID + Bundle ID) | Backend | Yes |
| AC-2.5.6 | Successful verification creates device with `attestation_level: "secure_enclave"` | Backend | Yes |
| AC-2.5.7 | Failed verification creates device with `attestation_level: "unverified"` | Backend | Yes |
| AC-2.5.8 | Device record stores `attestation_key_id`, `attestation_chain`, `model`, `has_lidar` | Backend | Yes |
| AC-2.5.9 | Response returns `device_id` and `attestation_level` | Backend | Yes |
| AC-2.5.10 | Duplicate key_id returns 409 Conflict | Backend | Yes |

### AC-2.6: Device Registration Completion

| ID | Criterion | Component | Testable |
|----|-----------|-----------|----------|
| AC-2.6.1 | App stores `device_id` in secure storage on successful registration | Mobile | Yes |
| AC-2.6.2 | App updates Zustand store with device state | Mobile | Yes |
| AC-2.6.3 | Registration success screen displays device ID (truncated) and attestation badge | Mobile | Yes |
| AC-2.6.4 | User can proceed to capture screen after registration | Mobile | Yes |
| AC-2.6.5 | Device state persists across app restarts | Mobile | Yes |

### AC-2.7: Device Signature Authentication

| ID | Criterion | Component | Testable |
|----|-----------|-----------|----------|
| AC-2.7.1 | Authenticated requests include `X-Device-Id` header | Mobile | Yes |
| AC-2.7.2 | Authenticated requests include `X-Device-Timestamp` header (Unix ms) | Mobile | Yes |
| AC-2.7.3 | Authenticated requests include `X-Device-Signature` header (base64 assertion) | Mobile | Yes |
| AC-2.7.4 | Signature computed over `timestamp + "|" + sha256(body)` | Mobile | Yes |
| AC-2.7.5 | Backend middleware verifies device exists in database | Backend | Yes |
| AC-2.7.6 | Backend middleware verifies timestamp within 5-minute window | Backend | Yes |
| AC-2.7.7 | Backend middleware verifies Ed25519 signature | Backend | Yes |
| AC-2.7.8 | Backend middleware verifies assertion counter increases | Backend | Yes |
| AC-2.7.9 | Invalid device returns 401 DEVICE_NOT_FOUND | Backend | Yes |
| AC-2.7.10 | Expired timestamp returns 401 TIMESTAMP_EXPIRED | Backend | Yes |
| AC-2.7.11 | Invalid signature returns 401 SIGNATURE_INVALID | Backend | Yes |

## Traceability Mapping

### Requirements to Acceptance Criteria

| FR | Description | Acceptance Criteria |
|----|-------------|---------------------|
| FR1 | App detects iPhone Pro with LiDAR | AC-2.1.1, AC-2.1.3 |
| FR2 | App generates Secure Enclave keys | AC-2.2.1, AC-2.2.2 |
| FR3 | App requests DCAppAttest attestation | AC-2.4.1, AC-2.4.2, AC-2.4.3 |
| FR4 | Backend verifies attestation | AC-2.5.1 through AC-2.5.9 |
| FR5 | System assigns attestation level | AC-2.5.6, AC-2.5.7 |
| FR41 | Device-level pseudonymous ID | AC-2.5.8, AC-2.6.1 |
| FR42 | Capture without account | AC-2.6.4 (registration enables anonymous capture) |
| FR43 | Device registration storage | AC-2.5.8 |

### Stories to Acceptance Criteria

| Story | Description | Acceptance Criteria |
|-------|-------------|---------------------|
| 2.1 | iPhone Pro detection | AC-2.1.1 through AC-2.1.7 |
| 2.2 | Secure Enclave key generation | AC-2.2.1 through AC-2.2.4 |
| 2.3 | DCAppAttest integration | AC-2.3.1-5, AC-2.4.1-4 |
| 2.4 | Backend challenge endpoint | AC-2.3.1 through AC-2.3.5 |
| 2.5 | DCAppAttest verification | AC-2.5.1 through AC-2.5.10 |
| 2.6 | Device registration completion | AC-2.6.1 through AC-2.6.5 |
| 2.7 | Device signature middleware | AC-2.7.1 through AC-2.7.11 |

### Acceptance Criteria to Tests

| AC ID | Test Type | Test Description |
|-------|-----------|------------------|
| AC-2.1.1 | Unit | `useDeviceCapabilities` returns model string |
| AC-2.1.3 | Unit/Manual | ARKit configuration check returns LiDAR availability |
| AC-2.1.5 | E2E | Non-Pro simulator shows blocking screen |
| AC-2.2.1 | Integration | Key generation succeeds on real device |
| AC-2.2.2 | Unit | Key ID stored in SecureStore |
| AC-2.3.1 | Integration | Challenge endpoint returns base64 string |
| AC-2.3.4 | Integration | Rate limit triggers 429 after 10 requests |
| AC-2.5.3 | Unit | Certificate chain verification logic |
| AC-2.5.6 | Integration | Valid attestation creates secure_enclave device |
| AC-2.5.7 | Integration | Invalid attestation creates unverified device |
| AC-2.7.6 | Unit | Timestamp validation logic |
| AC-2.7.7 | Unit | Signature verification logic |
| AC-2.7.8 | Integration | Counter replay detection |

## Risks, Assumptions, Open Questions

### Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| DCAppAttest unavailable on some devices | Medium | Low | Graceful degradation to "unverified" |
| Apple CA certificate rotation | High | Low | Monitor Apple announcements, quick update process |
| Attestation rate limiting by Apple | Medium | Low | Cache attestation, don't re-attest unnecessarily |
| Jailbroken users frustrated | Low | Medium | Clear messaging about why attestation matters |
| @expo/app-integrity API changes | Medium | Low | Pin version, test before upgrading |

### Assumptions

| Assumption | Dependency | Impact if Wrong |
|------------|------------|-----------------|
| @expo/app-integrity returns base64 attestation data | ADR-007 research | Need fallback to react-native-attestation |
| DCAppAttest works in Expo managed workflow | Expo compatibility | May need bare workflow |
| Ed25519 key extraction from attestation cert | x509-parser crate | May need different parsing approach |
| Apple App Attest CA cert is stable | Apple docs | Need to bundle and update if changed |
| 5-minute challenge TTL is sufficient | Network conditions | Increase if users report issues |

### Open Questions

| Question | Owner | Status | Impact |
|----------|-------|--------|--------|
| Q1: Exact bundle ID format for App ID hash verification? | Dev | Open | AC-2.5.5 implementation |
| Q2: How to handle device reinstall (same device, new key)? | Product | Open | May need device linking feature |
| Q3: Should we store full certificate chain or just hash? | Dev | Open | Storage vs. verification flexibility |
| Q4: Assertion counter storage in assertions vs device table? | Dev | Decided: device table | - |

## Test Strategy Summary

### Unit Tests

| Component | Test Focus | Coverage Target |
|-----------|------------|-----------------|
| useDeviceCapabilities | Model detection, capability flags | 90% |
| deviceStore | State management, persistence | 90% |
| attestation.rs | CBOR parsing, cert validation | 95% |
| device_auth.rs | Signature verification, timestamp validation | 95% |
| challenge_store.rs | TTL, single-use enforcement | 95% |

### Integration Tests

| Test | Components | Method |
|------|------------|--------|
| Challenge generation | Backend | HTTP test with rate limit verification |
| Device registration | Backend + DB | Testcontainers PostgreSQL |
| Auth middleware | Backend | Mock device, verify rejection cases |
| Full registration flow | Mobile + Backend | Real device or mock responses |

### E2E Tests (Maestro)

| Test | Scenario |
|------|----------|
| Non-Pro blocking | Launch on simulator, verify blocking screen |
| Registration success | Full flow on real iPhone Pro |
| Subsequent launch | Skip registration, verify state persistence |
| Unverified fallback | Mock attestation failure, verify degraded state |

### Manual Testing Requirements

| Test | Reason |
|------|--------|
| Real DCAppAttest flow | Requires physical iPhone Pro |
| Jailbreak detection | Attestation fails differently on compromised devices |
| Certificate chain verification | Use Apple's test environment if available |

### Test Data Requirements

- Apple App Attest CA root certificate (embedded)
- Sample valid attestation object (from real device, redacted)
- Sample invalid attestation object (malformed)
- Test Team ID and Bundle ID

---

## Appendix: Apple DCAppAttest Reference

### Attestation Object Structure (CBOR)

```
{
  "fmt": "apple-appattest",
  "attStmt": {
    "x5c": [<leaf_cert>, <intermediate_cert>, <root_cert>],
    "receipt": <receipt_data>
  },
  "authData": <authenticator_data>
}
```

### authData Structure

```
| RP ID Hash (32 bytes) | Flags (1 byte) | Counter (4 bytes) | AAGUID (16 bytes) | Credential ID Length (2 bytes) | Credential ID | COSE Public Key |
```

### Verification Steps (Detailed)

1. Decode CBOR attestation object
2. Verify `fmt` == "apple-appattest"
3. Parse X.509 certificates from `attStmt.x5c`
4. Verify certificate chain:
   - Leaf cert issued by intermediate
   - Intermediate cert issued by root
   - Root cert == Apple App Attest Root CA
5. Extract nonce extension (OID 1.2.840.113635.100.8.2) from leaf cert
6. Verify nonce == SHA256(authData || clientDataHash)
7. Parse authData:
   - Verify RP ID Hash == SHA256(App ID)
   - Extract and store counter
   - Extract COSE public key
8. Store public key for future assertion verification

### Apple App Attest Root CA

- Subject: Apple App Attestation Root CA
- Valid: 2020-03-18 to 2045-03-15
- SHA-256 Fingerprint: (to be embedded in binary)

---

_Generated by Epic Tech Context Workflow_
_Epic 2: Device Registration & Hardware Attestation_
_RealityCam MVP_
