# RealityCam PRD v2

## 0. Overview

**Working title**: RealityCam

**One-liner**: A mobile camera app providing cryptographically-attested, physics-verified media provenance—showing viewers not just "this came from a camera" but "here's the strength of evidence that this came from THIS environment at THIS moment."

**Core insight**: Provenance claims are only as strong as their weakest assumption. A software-only hash proves nothing if the software layer is compromised. Hardware attestation must be the foundation, not a later enhancement.

**What this is NOT**: 
- Not an "AI detector" or "deepfake detector"
- Not a claim of absolute truth—we provide *evidence strength*, not binary verification
- Not a social platform

**Standards alignment**: C2PA / Content Credentials for interoperability with ecosystem tools (Adobe, Google Photos, news organizations).

---

## 1. Goals & Non-Goals

### 1.1 Goals

**G1: Provide graduated evidence of authenticity**
- Hardware-attested device identity where available
- Physics-based consistency checks (sun angle, depth, motion)
- Cross-modal sensor correlation
- Clear communication of what evidence IS and ISN'T available

**G2: Make evidence legibility scale with viewer expertise**
- Casual viewer: confidence summary + primary evidence type
- Journalist: expandable evidence panel with pass/fail/unavailable per check
- Forensic analyst: raw data export, methodology documentation

**G3: Align with open standards (C2PA)**
- Use c2pa-rs and CAI SDK for manifest generation
- Interoperable with Content Credentials ecosystem
- Publishable methodology (security through robust design, not obscurity)

**G4: Privacy-preserving and user-controlled**
- GPS coarse by default (city-level)
- Environmental context stored locally until explicit capture action
- Clear disclosure of what's uploaded

### 1.2 Non-Goals

**NG1: Binary "verified" / "not verified" claims**
- We provide evidence strength, not ground truth
- Even hardware attestation can theoretically be defeated (nation-state, supply chain)
- Viewers must understand they're seeing "strength of evidence," not certainty

**NG2: Preventing all attacks**
- We harden against specific attack classes (see Threat Model)
- We explicitly acknowledge what we CAN'T detect
- We don't claim to solve the epistemological problem of media trust

**NG3: Enterprise workflow features (v1)**
- No claims management, underwriting integration, chain-of-custody for legal proceedings
- Focus on capture + verify flow

---

## 2. Personas & Use Cases

### 2.1 Personas

**Citizen Journalist "Alex"**
- Documents protests, police actions, disasters
- Needs to prove footage is genuine, not fabricated
- Technical sophistication: medium
- Key need: credible evidence that survives scrutiny

**Human Rights Worker "Sam"**
- Collects testimonies and visual evidence in conflict zones
- Often on low bandwidth, hostile network environments
- Key need: offline-first, exportable evidence packages

**Everyday User "Jordan"**
- Proving authenticity for insurance claims, marketplace listings
- Technical sophistication: low
- Key need: simple "this is trustworthy" signal for recipients

**Forensic Analyst "Riley"**
- Receives captures for investigation
- Needs raw data, methodology transparency, reproducible verification
- Technical sophistication: high
- Key need: expert-mode access to all evidence

### 2.2 Primary Use Cases

**UC1: Capture with environmental context**
1. User opens app, enters "capture mode"
2. App prompts: "Scan your environment" — user does slow 360° pan (10-15s)
3. User "locks" on subject, takes photo/video
4. App computes: target capture + environment context + sensor traces
5. Upload includes all evidence; user receives shareable link

**UC2: Quick capture (degraded evidence)**
1. User takes photo without environment scan
2. Evidence tier reduced (no 3D-ness proof)
3. Clear indication in verification: "Environment scan: not performed"

**UC3: Verify received media**
1. Recipient opens verification link
2. Sees confidence summary + expandable evidence panel
3. Can download raw evidence package for independent analysis

**UC4: Upload external file for hash lookup**
1. User uploads file to verification page
2. System checks if hash matches any registered capture
3. If match: show linked evidence. If no match: "No record found"

---

## 3. Evidence Hierarchy

This is the core conceptual model. Evidence tiers are ordered by cost-to-spoof.

### 3.1 Tier 1: Hardware-Rooted (highest)

**What it proves**: The capture request originated from code running in a hardware-protected environment on a device with intact firmware.

**Checks**:
| Check | Implementation | Spoofing cost |
|-------|---------------|---------------|
| Device identity attested by TEE | Android Key Attestation (StrongBox) | Custom silicon / firmware exploit |
| Device identity attested by Secure Enclave | iOS DCAppAttest | Custom silicon / firmware exploit |
| Key generated in HSM | Hardware-backed key generation | Physical device extraction |

**Display**: "Device integrity: Hardware-verified ✓" or "Device integrity: Not available (device lacks hardware attestation)"

### 3.2 Tier 2: Physics-Constrained

**What it proves**: Faking would require manipulating physical world, not just software.

**Checks**:
| Check | Implementation | Spoofing cost |
|-------|---------------|---------------|
| Sun angle consistency | Compute expected sun position from (GPS, timestamp, compass), compare to shadow direction in image | Requires knowing attacker's actual time/location, building physical scene with correct lighting |
| LiDAR depth | Depth map shows 3D geometry inconsistent with flat surface | Requires building physical 3D scene |
| Barometric pressure | Pressure reading matches GPS altitude ± expected variance | Requires pressure chamber or GPS spoofing + altitude coordination |
| Environment is 3D | 360° scan shows parallax inconsistent with flat projection | Requires dome of synchronized displays or full 3D scene construction |

**Display**: "Physics verification: Sun angle ✓, LiDAR depth — N/A (no sensor), Environment scan ✓"

### 3.3 Tier 3: Cross-Modal Consistency

**What it proves**: Faking would require generating coordinated synthetic data across multiple independent sensors.

**Checks**:
| Check | Implementation | Spoofing cost |
|-------|---------------|---------------|
| Gyroscope × optical flow | If gyro reports 30° rotation, video should show ~30° scene shift | Requires geometrically consistent fake video generation |
| Multi-camera lighting | Front/back/wide cameras show consistent global illumination direction | Requires multi-angle consistent synthetic lighting |
| Audio reverb × room geometry | Reverb characteristics match visible room size/materials (video only) | Requires acoustic simulation matching fake visual |
| Accelerometer × motion blur | Motion blur direction/magnitude matches accelerometer trace | Requires coordinated blur synthesis |

**Display**: "Sensor consistency: Gyro/optical flow ✓, Multi-camera lighting — N/A (single camera used)"

### 3.4 Tier 4: Metadata Consistency (lowest)

**What it proves**: Basic plausibility checks passed; trivially spoofable by motivated attacker.

**Checks**:
| Check | Implementation | Spoofing cost |
|-------|---------------|---------------|
| EXIF timestamp | Within ±30s of server receipt | EXIF editor |
| Device model string | EXIF matches platform API report | Hook platform API |
| Resolution/lens | Matches claimed device capabilities | Metadata editing |
| App integrity | App signature valid, not repackaged | Reverse engineering |

**Display**: "Metadata: Consistent ✓" (never displayed as strong evidence alone)

### 3.5 Evidence Status Values

Critical distinction in display:

| Status | Meaning | Visual | Implication |
|--------|---------|--------|-------------|
| **PASS** | Check performed, evidence consistent | ✓ Green | Positive signal |
| **FAIL** | Check performed, evidence inconsistent | ✗ Red | Red flag—possible manipulation |
| **UNAVAILABLE** | Check not possible (device/conditions) | — Gray | Reduces confidence ceiling, not suspicious |
| **SKIPPED** | User chose not to perform (e.g., no env scan) | ○ Yellow | User choice, noted in evidence |

---

## 4. Functional Requirements

### 4.1 Secure Capture (Mobile App)

**FR-1.1: Hardware Attestation (Phase 0 critical path)**

On app launch and periodically:
- Android (Pixel 6+, Samsung Knox devices): Generate key in StrongBox, request attestation certificate chain, verify server-side
- iOS (iPhone SE 2+): Use DCAppAttest to generate assertion, verify server-side
- Fallback: Mark device as `attestation_level: software_only`

The attestation level determines maximum achievable confidence.

**FR-1.2: Scan Mode Capture**

Flow:
1. User taps "Capture" → enters scan mode
2. App displays AR overlay: "Slowly pan 360° around you"
3. App records:
   - Video stream from all available cameras (front, back, wide, tele)
   - Gyroscope trace (100Hz minimum)
   - Accelerometer trace (100Hz minimum)
   - Magnetometer (compass) readings
   - GPS (if permitted)
   - Barometer (if available)
   - LiDAR depth frames (if available, iPhone Pro/iPad Pro)
4. User taps "Lock" → scan phase ends
5. User frames subject, taps "Capture" → target photo/video taken
6. App records additional sensor burst during target capture

**FR-1.3: Local Processing (before upload)**

Compute:
- SHA-256 hash of target media file
- SHA-256 hash of environment context package
- Gyro × optical flow consistency score (local estimate)
- LiDAR flatness analysis (if available)

Construct Capture Request:
```json
{
  "target_media_hash": "sha256:base64",
  "context_hash": "sha256:base64",
  "device": {
    "id": "attested-key-id or local-uuid",
    "attestation_level": "hardware_strongbox | hardware_secure_enclave | software_only | unknown",
    "attestation_chain": ["base64-cert", "..."] | null,
    "model": "Pixel 8 Pro",
    "platform": "android",
    "sensors_available": ["gyro", "accel", "magnet", "baro", "lidar", "front_cam", "back_cam", "wide_cam"]
  },
  "capture": {
    "target_captured_at": "ISO-8601",
    "scan_started_at": "ISO-8601",
    "scan_ended_at": "ISO-8601",
    "gps": { "lat": 0.0, "lon": 0.0, "accuracy_m": 0.0, "altitude_m": 0.0 } | null,
    "scan_performed": true
  },
  "local_checks": {
    "gyro_optical_flow_score": 0.0-1.0,
    "lidar_flatness_score": 0.0-1.0 | null
  },
  "app_version": "1.0.0",
  "app_signature_hash": "sha256:base64"
}
```

**FR-1.4: Upload**

- Multipart POST: target media + context package (compressed) + JSON request
- TLS 1.3 required
- Certificate pinning recommended (Phase 1)
- Retry with exponential backoff on failure

**FR-1.5: Offline Mode**

- Store media + metadata in encrypted local storage
- Encryption key: hardware-backed if attestation available, otherwise derived from device-specific entropy
- Mark as "Pending upload"
- Auto-upload when connectivity returns
- Display warning: "Evidence timestamping delayed—server receipt time will differ from capture time"

### 4.2 Evidence Generation (Backend)

**FR-2.1: Attestation Verification**

On capture receipt:
1. If `attestation_level` claims hardware:
   - Android: Verify certificate chain against Google's root, check extension data (OS version, patch level, app signature)
   - iOS: Verify assertion against Apple's attestation service
2. Downgrade `attestation_level` if verification fails
3. Store verified attestation level with capture

**FR-2.2: Physics Checks**

Sun angle verification:
1. Extract shadow direction from image (edge detection + heuristics, or ML model)
2. Compute expected sun position: `sun_position(lat, lon, timestamp)` using astronomical algorithms
3. Compare angles, compute confidence interval
4. Result: `{ "check": "sun_angle", "status": "pass|fail|unavailable", "expected_azimuth": 145.2, "observed_azimuth": 143.8, "confidence": 0.87 }`

LiDAR depth analysis:
1. If LiDAR frames present, analyze depth variance
2. Flat surface (screen) has near-zero depth variance
3. Real 3D scene has structured depth variation
4. Result: `{ "check": "lidar_depth", "status": "pass|fail|unavailable", "flatness_score": 0.12, "threshold": 0.3 }`

Barometric consistency:
1. Compare barometer reading to expected pressure at GPS altitude
2. Allow for weather variation (±15 hPa typical)
3. Result: `{ "check": "barometric", "status": "pass|fail|unavailable", "expected_hpa": 1013.25, "observed_hpa": 1011.8 }`

Environment 3D-ness (from scan):
1. Compute optical flow between scan frames
2. Check for parallax consistent with camera motion (near objects move more than far)
3. Flat projection shows no parallax
4. Result: `{ "check": "environment_3d", "status": "pass|fail|skipped", "parallax_score": 0.91 }`

**FR-2.3: Cross-Modal Consistency Checks**

Gyro × optical flow:
1. Integrate gyroscope to get rotation estimate
2. Compute optical flow between frames
3. Compare rotation estimates
4. Result: `{ "check": "gyro_optical_flow", "status": "pass|fail|unavailable", "gyro_rotation_deg": 28.4, "flow_rotation_deg": 27.1, "deviation": 1.3 }`

Multi-camera lighting (if multiple cameras used):
1. Estimate dominant light direction from each camera's image
2. Transform to common coordinate frame
3. Check consistency
4. Result: `{ "check": "multicam_lighting", "status": "pass|fail|unavailable", "light_direction_variance_deg": 12.3 }`

**FR-2.4: Metadata Consistency Checks**

- EXIF timestamp vs server receipt: flag if |delta| > 60s
- Device model vs EXIF vs platform API: flag mismatches
- Resolution vs device capabilities: flag impossibilities

**FR-2.5: Evidence Package Generation**

Create Evidence Package:
```json
{
  "capture_id": "cap_01ABC...",
  "evidence_generated_at": "ISO-8601",
  "device": {
    "attestation_level": "hardware_strongbox",
    "attestation_verified": true,
    "model": "Pixel 8 Pro"
  },
  "checks": {
    "tier1_hardware": [
      { "check": "device_attestation", "status": "pass", "details": {...} }
    ],
    "tier2_physics": [
      { "check": "sun_angle", "status": "pass", "details": {...} },
      { "check": "lidar_depth", "status": "unavailable", "reason": "sensor_not_present" },
      { "check": "environment_3d", "status": "pass", "details": {...} }
    ],
    "tier3_crossmodal": [
      { "check": "gyro_optical_flow", "status": "pass", "details": {...} }
    ],
    "tier4_metadata": [
      { "check": "exif_timestamp", "status": "pass", "details": {...} },
      { "check": "device_model", "status": "pass", "details": {...} }
    ]
  },
  "confidence_summary": {
    "level": "high | medium | low | insufficient",
    "primary_evidence": "Hardware-attested device + sun angle + environment scan",
    "limiting_factors": ["LiDAR unavailable"],
    "red_flags": []
  }
}
```

**FR-2.6: C2PA Manifest Embedding**

Using c2pa-rs:
1. Create C2PA manifest with:
   - Claim generator: "RealityCam/1.0.0"
   - Actions: capture event with timestamp, location (coarse), device info
   - Assertions: evidence package summary (not full raw data)
2. Sign manifest with server key (Ed25519, key in HSM for production)
3. Embed manifest in media file
4. Store both original and C2PA-embedded versions

**FR-2.7: Storage**

- Target media: S3-compatible, content-addressed (hash as key for deduplication)
- Context package: S3-compatible, linked to capture
- Evidence package: Postgres JSONB
- C2PA-embedded media: S3-compatible

### 4.3 Verification Interface

**FR-3.1: Summary View (default)**

Display:
```
┌─────────────────────────────────────────────┐
│  [Thumbnail]                                │
│                                             │
│  Confidence: HIGH                           │
│  ───────────────────────────────────────    │
│  Primary evidence:                          │
│  • Hardware-attested device identity        │
│  • Sun position matches claimed time/place  │
│  • Environment scan shows 3D scene          │
│                                             │
│  Captured: Nov 21, 2025, 14:32 UTC          │
│  Location: Within 5km of Berlin, Germany    │
│  Device: Pixel 8 Pro                        │
│                                             │
│  [▼ View detailed evidence]                 │
└─────────────────────────────────────────────┘
```

Confidence level logic:
- **HIGH**: Tier 1 pass + at least 2 Tier 2 passes + no fails
- **MEDIUM**: Tier 1 pass OR 2+ Tier 2 passes, no fails
- **LOW**: Only Tier 3-4 passes, no Tier 1-2
- **INSUFFICIENT**: Major checks failed or almost all unavailable
- **SUSPICIOUS**: Any check FAILED (not unavailable—actually inconsistent)

**FR-3.2: Evidence Panel (expandable)**

```
Hardware Attestation
  Device identity          ✓ PASS    [strongest]
  Key storage             ✓ Hardware-backed (StrongBox)

Physics Verification  
  Sun angle               ✓ PASS    Expected 145°, observed 144° ±5°
  LiDAR depth             — N/A     Sensor not present on device
  Barometric pressure     ✓ PASS    1012 hPa vs expected 1013 hPa
  Environment 3D-ness     ✓ PASS    Parallax detected in scan

Sensor Consistency
  Gyro × optical flow     ✓ PASS    Rotation: 28° gyro, 27° optical
  Multi-camera lighting   — N/A     Single camera used

Metadata
  EXIF timestamp          ✓ PASS    Within 3s of submission
  Device model            ✓ PASS    Consistent across sources
```

**FR-3.3: Expert Panel (forensic analysts)**

- Download: Raw sensor data package (gyro traces, accel traces, LiDAR frames)
- Download: Evidence computation logs
- View: Methodology documentation
- View: Confidence intervals and thresholds used
- Verify: Independent hash verification tool
- View: C2PA manifest (raw JUMBF)

**FR-3.4: Context Viewer**

For captures with environment scan:
- Viewer can scrub through 360° scan video
- Overlay shows: "This is the environmental context captured before the target image"
- Parallax visualization highlighting depth cues

**FR-3.5: File Upload Verification**

POST /api/v1/verify-file:
1. Compute hash of uploaded file
2. Search for matching hash in database
3. If match: return linked capture_id and evidence package
4. If no match but file has C2PA manifest: extract and display manifest info with note "Not captured through RealityCam"
5. If no match and no manifest: "No provenance record found"

### 4.4 User Accounts & Device Management

**FR-4.1: Anonymous by Default (Phase 0)**

- Device-level pseudonymous ID
- Hardware-attested ID if available, otherwise random UUID
- No account required for capture or verify

**FR-4.2: Optional Account (Phase 1)**

- Passkey-based authentication (no passwords)
- Benefits: gallery of captures, revocation capability, device management
- Can link multiple devices to account

**FR-4.3: Capture Revocation**

- User can mark capture as "withdrawn"
- Verification page shows: "This capture was withdrawn by the creator on [date]"
- Media optionally deleted; evidence package retained (tombstone) for audit

---

## 5. Technical Architecture

### 5.1 High-Level Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Mobile App                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ Camera   │ │ Sensors  │ │ Local    │ │ Hardware │              │
│  │ Module   │ │ Module   │ │ Crypto   │ │ Attest   │              │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘              │
│       └────────────┴────────────┴────────────┘                     │
│                          │                                          │
│                    Upload Manager                                   │
│                          │                                          │
└──────────────────────────┼──────────────────────────────────────────┘
                           │ HTTPS + TLS 1.3
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        Backend (Rust)                                │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Axum API Server                           │    │
│  │  POST /captures  GET /captures/:id  POST /verify-file       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│       │                    │                     │                   │
│       ▼                    ▼                     ▼                   │
│  ┌──────────┐      ┌──────────────┐      ┌─────────────┐           │
│  │ Attest   │      │ Evidence     │      │ C2PA        │           │
│  │ Verifier │      │ Processor    │      │ (c2pa-rs)   │           │
│  └──────────┘      └──────────────┘      └─────────────┘           │
│       │                    │                     │                   │
│       └────────────────────┴─────────────────────┘                   │
│                            │                                         │
│       ┌────────────────────┼────────────────────┐                   │
│       ▼                    ▼                    ▼                   │
│  ┌──────────┐      ┌──────────────┐      ┌─────────────┐           │
│  │ Postgres │      │ S3 Storage   │      │ Task Queue  │           │
│  │ (SQLx)   │      │              │      │ (Redis)     │           │
│  └──────────┘      └──────────────┘      └─────────────┘           │
└──────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  Verification Frontend (Next.js)                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ Summary     │  │ Evidence    │  │ Expert      │                 │
│  │ View        │  │ Panel       │  │ Panel       │                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.2 Tech Stack

**Mobile App**
- Framework: React Native (Expo prebuild for native module escape hatch)
- Camera: react-native-vision-camera v4
- Sensors: expo-sensors
- Crypto: expo-crypto (native SHA-256)
- Local storage: expo-sqlite with SQLCipher encryption
- Native modules (Phase 0.5+):
  - Android: Kotlin module for Key Attestation
  - iOS: Swift module for DCAppAttest

**Backend (all Rust)**
- HTTP: Axum 0.8
- Database: SQLx 0.8 with Postgres
- C2PA: c2pa-rs 0.35
- Async runtime: Tokio
- Serialization: Serde
- Task queue: Redis + Tokio background tasks
- Object storage: aws-sdk-s3 or rust-s3
- Cryptography: ring (Ed25519 signing)

**Verification Frontend**
- Next.js 14 (App Router)
- React
- TailwindCSS
- TypeScript

**Infrastructure**
- Database: Postgres 16
- Object storage: S3-compatible (AWS S3, MinIO, or Cloudflare R2)
- Task queue: Redis
- Key management: AWS KMS or HashiCorp Vault (production)
- CDN: Cloudflare (for verification page and media delivery)

### 5.3 Why All-Rust Backend

The original PRD proposed Node.js + Rust microservice. Problems:
1. Network hop latency for every c2pa-rs call
2. Two deployment targets, two dependency trees
3. Type translation at boundary (JSON serialization overhead)
4. Security surface doubled

With Axum + c2pa-rs in same process:
- c2pa-rs calls are library calls, not network calls
- Single deployment artifact
- Full type safety from request parsing to C2PA generation
- Rust's memory safety applies to entire request path

The trade-off is Rust's longer compile times and steeper learning curve, but for a security-critical system processing cryptographic proofs, this is acceptable.

---

## 6. Data Model

### 6.1 Core Tables

```sql
-- Devices
CREATE TABLE devices (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    model TEXT NOT NULL,
    attestation_level TEXT NOT NULL CHECK (attestation_level IN (
        'hardware_strongbox', 'hardware_secure_enclave', 'software_only', 'unknown'
    )),
    attestation_key_id TEXT,  -- For hardware-attested devices
    attestation_verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Captures
CREATE TABLE captures (
    id TEXT PRIMARY KEY,  -- ULID
    device_id UUID NOT NULL REFERENCES devices(id),
    user_id UUID REFERENCES users(id),
    
    -- Media references
    target_media_key TEXT NOT NULL,  -- S3 key (content-addressed)
    target_media_hash TEXT NOT NULL,  -- sha256
    target_media_type TEXT NOT NULL,  -- image/jpeg, video/mp4
    context_package_key TEXT,  -- S3 key, null if no scan
    c2pa_media_key TEXT,  -- S3 key for C2PA-embedded version
    
    -- Timestamps
    captured_at TIMESTAMPTZ NOT NULL,
    scan_started_at TIMESTAMPTZ,
    scan_ended_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ NOT NULL,
    
    -- Location (coarse)
    gps_lat DOUBLE PRECISION,
    gps_lon DOUBLE PRECISION,
    gps_precision_m DOUBLE PRECISION,
    
    -- Evidence
    evidence_package JSONB NOT NULL,
    confidence_level TEXT NOT NULL CHECK (confidence_level IN (
        'high', 'medium', 'low', 'insufficient', 'suspicious'
    )),
    
    -- Status
    status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN (
        'processing', 'complete', 'failed', 'revoked'
    )),
    revoked_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for hash lookup
CREATE UNIQUE INDEX captures_target_media_hash_idx ON captures(target_media_hash);

-- Users (optional, Phase 1)
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email TEXT UNIQUE,
    passkey_credential_id BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Verification logs (analytics)
CREATE TABLE verification_logs (
    id BIGSERIAL PRIMARY KEY,
    capture_id TEXT REFERENCES captures(id),
    action TEXT NOT NULL CHECK (action IN ('view', 'file_verify', 'expert_download')),
    client_ip INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 6.2 Evidence Package Schema (JSONB)

```typescript
interface EvidencePackage {
  version: 1;
  generated_at: string;  // ISO-8601
  
  device: {
    attestation_level: 'hardware_strongbox' | 'hardware_secure_enclave' | 'software_only' | 'unknown';
    attestation_verified: boolean;
    model: string;
    platform: 'android' | 'ios';
    sensors_available: string[];
  };
  
  checks: {
    tier1_hardware: EvidenceCheck[];
    tier2_physics: EvidenceCheck[];
    tier3_crossmodal: EvidenceCheck[];
    tier4_metadata: EvidenceCheck[];
  };
  
  confidence_summary: {
    level: 'high' | 'medium' | 'low' | 'insufficient' | 'suspicious';
    primary_evidence: string;  // Human-readable summary
    limiting_factors: string[];  // What prevented higher confidence
    red_flags: string[];  // Any failed checks
  };
}

interface EvidenceCheck {
  check: string;  // e.g., 'sun_angle', 'gyro_optical_flow'
  status: 'pass' | 'fail' | 'unavailable' | 'skipped';
  reason?: string;  // For unavailable/skipped
  details?: Record<string, unknown>;  // Check-specific data
  confidence?: number;  // 0-1, where applicable
}
```

---

## 7. API Design

### 7.1 Create Capture

```
POST /api/v1/captures
Content-Type: multipart/form-data

Parts:
- target_media: file (required)
- context_package: file (optional, compressed)
- request: JSON (required, schema below)

Request JSON:
{
  "target_media_hash": "sha256:...",
  "context_hash": "sha256:..." | null,
  "device": { ... },  // As specified in FR-1.3
  "capture": { ... },
  "local_checks": { ... },
  "app_version": "1.0.0"
}

Response 202 Accepted:
{
  "capture_id": "cap_01ABC...",
  "status": "processing",
  "verify_url": "https://verify.realitycam.app/cap_01ABC...",
  "short_code": "R8D7XP"
}

Response 400 Bad Request:
{
  "error": "hash_mismatch",
  "message": "Computed hash does not match provided target_media_hash"
}
```

### 7.2 Get Capture

```
GET /api/v1/captures/:id

Response 200:
{
  "capture_id": "cap_01ABC...",
  "status": "complete",
  "media_url": "https://cdn.realitycam.app/...",  // Signed URL, expires
  "captured_at": "2025-11-21T14:32:00Z",
  "location": {
    "display": "Within 5km of Berlin, Germany",
    "lat": 52.52,  // Only if user opted for precise
    "lon": 13.40
  },
  "device": {
    "model": "Pixel 8 Pro",
    "platform": "android",
    "attestation_level": "hardware_strongbox"
  },
  "evidence": { ... },  // Full EvidencePackage
  "c2pa_media_url": "https://cdn.realitycam.app/..."  // C2PA-embedded version
}
```

### 7.3 Verify File

```
POST /api/v1/verify-file
Content-Type: multipart/form-data

Parts:
- file: file (required)

Response 200 (match found):
{
  "match": true,
  "capture_id": "cap_01ABC...",
  "verify_url": "https://verify.realitycam.app/cap_01ABC...",
  "confidence_summary": { ... }
}

Response 200 (no match, but has C2PA):
{
  "match": false,
  "c2pa_manifest_found": true,
  "c2pa_summary": {
    "generator": "Adobe Photoshop",
    "claim_time": "2025-11-20T10:00:00Z",
    "signature_valid": true
  }
}

Response 200 (no match, no C2PA):
{
  "match": false,
  "c2pa_manifest_found": false
}
```

### 7.4 Get Raw Evidence (Expert endpoint)

```
GET /api/v1/captures/:id/evidence/raw
Authorization: Bearer <optional-api-key>

Response 200:
Content-Type: application/zip

ZIP contains:
- sensor_data/gyroscope.csv
- sensor_data/accelerometer.csv
- sensor_data/magnetometer.csv
- lidar_frames/ (if available)
- computation_logs.json
- methodology.md
- c2pa_manifest.cbor
```

---

## 8. Threat Model

### 8.1 Attack Classes and Defenses

| Attack | Method | Defense | Tier |
|--------|--------|---------|------|
| Screenshot AI image | Take screenshot of AI-generated image, upload | Only in-app captures accepted; no gallery import | App |
| Frida/Xposed hook | Hook sensor APIs, feed synthetic data | Hardware attestation detects rooted/hooked devices | Tier 1 |
| Physical replay | Project deepfake onto screen, photograph | 360 scan reveals flat surface; LiDAR shows no depth | Tier 2 |
| NeRF/3DGS fake | Generate photorealistic 3D environment | Sun angle + GPS + timestamp cross-check; active research area | Tier 2 |
| Time/location spoof | Modify GPS, backdate capture | Sun angle verification; EXIF vs server time; attestation timestamp | Tier 2 |
| Coordinated sensor spoof | Generate consistent gyro + optical flow + accel | Hardware attestation; increases attacker cost significantly | Tier 1+3 |
| Metadata editing | Modify EXIF after capture | Hash computed pre-upload; server recomputes | App |
| MITM | Intercept upload, modify media | TLS 1.3; certificate pinning; hash verification | Transport |
| Server compromise | Modify evidence post-capture | Signed certificates; C2PA manifest in media file | Tier 1 |
| Supply chain | Ship app with backdoor | App signature verification; open source (Phase 2) | App |

### 8.2 What We Cannot Detect

Being explicit about limitations:

1. **Perfectly constructed physical scenes**: If attacker builds real 3D set matching target scene, our physics checks pass. Cost: very high.

2. **Nation-state hardware attacks**: Custom silicon or firmware exploits could defeat hardware attestation. Cost: extremely high.

3. **Semantic truth**: We prove "this image came from this camera at this time in this environment." We do NOT prove "what this image depicts actually happened."

4. **Pre-capture manipulation**: If physical scene is staged (e.g., fake documents photographed), we prove authentic capture of staged scene.

5. **Future AI advances**: NeRF/3DGS quality improves. Our defenses must evolve. Sun angle + GPS + timestamp remains hard to fake without knowing attacker's actual location.

---

## 9. Security Requirements

### 9.1 Cryptographic Choices

| Component | Algorithm | Rationale |
|-----------|-----------|-----------|
| Media hash | SHA-256 | Industry standard, collision-resistant |
| Certificate signing | Ed25519 | Fast, small signatures, no ECDSA pitfalls |
| C2PA manifest | Per C2PA spec (ES256 or Ed25519) | Interoperability |
| Key storage (server) | HSM-backed (AWS KMS, Vault) | Private key never in memory |
| Device attestation | Platform-native (Android KeyStore, iOS Secure Enclave) | Hardware root of trust |

### 9.2 Key Management

**Server signing key**:
- Generate in HSM, never export
- Rotation: yearly or on suspected compromise
- Revocation: maintain CRL, embed in C2PA manifest

**Device attestation keys**:
- Generated per-device in hardware
- Server verifies attestation chain against platform root
- Device keys are device-bound, not extractable

### 9.3 Transport Security

- TLS 1.3 required for all API endpoints
- Certificate pinning in mobile app (Phase 1)
- Signed URLs for media access, expire in 1 hour

---

## 10. Privacy Requirements

### 10.1 Data Minimization

| Data | Collection | Storage | Sharing |
|------|------------|---------|---------|
| Precise GPS | Opt-in | Server | Coarsened to city-level in public view |
| Environment scan | Required for high confidence | Server | Viewable by recipients |
| Sensor traces | Automatic | Server | Available in expert download |
| Device model | Automatic | Server | Shown in verification |
| User identity | Optional account | Server | Not shown publicly |

### 10.2 User Controls

- Delete capture: removes media, marks certificate as revoked
- Opt-out of location: capture proceeds with "Location: not provided" (reduces confidence)
- Export my data: download all captures and evidence
- Delete account: delete all associated captures

### 10.3 Bystander Considerations

Environment scan may capture bystanders:
- Display clear indicator during scan ("Recording environment")
- Consider: optional face blur in context video (reduces evidence quality)
- Context video is evidence, not published content—access controlled

---

## 11. Non-Functional Requirements

### 11.1 Performance

| Metric | Target | Notes |
|--------|--------|-------|
| Capture → processing complete | < 30s | Includes evidence computation |
| Verification page load | < 1.5s FCP | Cached media via CDN |
| Upload throughput | 10 MB/s minimum | Typical capture + context ~5-15 MB |
| Evidence computation | < 10s | Parallelized across tiers |

### 11.2 Reliability

| Metric | Target |
|--------|--------|
| API availability | 99.5% (hackathon), 99.9% (production) |
| Data durability | 99.999999999% (11 nines, via S3) |
| Offline capture | Must not lose captures |

### 11.3 Scalability

Phase 0: Single backend instance, vertical scaling
Phase 1+: Horizontal scaling, read replicas for Postgres, CDN for media

---

## 12. Phased Delivery Plan

### Phase 0: Hackathon MVP (3 days)

**Goal**: Demonstrate core value proposition with hardware attestation foundation

**Mobile App (React Native)**:
- Basic camera capture (single photo)
- SHA-256 hash computation
- Android Key Attestation for Pixel 6+ (native module)
- Upload with attestation data
- Receive and display verify URL

**Backend (Rust/Axum)**:
- `POST /captures`: receive upload, verify attestation, store
- `GET /captures/:id`: return capture data and evidence
- `POST /verify-file`: hash lookup
- Basic evidence package with:
  - Tier 1: attestation verification
  - Tier 4: EXIF timestamp check
- JWS-signed certificate (not full C2PA yet)

**Verification Web (Next.js)**:
- Summary view with confidence level
- Basic evidence panel
- "Hardware attestation: ✓ PASS" vs "Device integrity: software only"

**Explicit limitations displayed**:
- "Phase 0 prototype—limited evidence checks"
- "No environment scan—3D verification unavailable"

**Outcome**: Working demo that shows WHY hardware attestation matters as foundation.

### Phase 0.5: Core Evidence (1-2 weeks post-hackathon)

**Additions**:
- iOS DCAppAttest support
- Scan mode UX (360° pan)
- Gyro × optical flow consistency check (Tier 3)
- Sun angle verification (Tier 2)
- Context video storage and viewer
- Confidence level logic fully implemented

**Outcome**: Meaningfully harder to fake than Phase 0; differentiated from basic provenance apps.

### Phase 1: Full Evidence Suite (1-2 months)

**Additions**:
- LiDAR depth analysis (iPhone Pro)
- Multi-camera lighting consistency
- Full C2PA manifest embedding via c2pa-rs
- Expert panel with raw data download
- User accounts and capture management
- Barometric pressure check
- Certificate pinning in mobile app

**Outcome**: Production-quality evidence system.

### Phase 2: Ecosystem & Hardening (3-6 months)

**Additions**:
- Open source release (transparency)
- Third-party verification tool (independent hash/signature check)
- Browser extension for inline verification
- Integration with news org verification workflows
- Advanced ML-based checks (active research)
- Formal security audit

---

## 13. Open Questions

### 13.1 Technical

**Q1**: Sun angle verification requires shadow detection. How robust is this for indoor scenes or overcast conditions?
- Mitigation: Mark as "unavailable" when confidence too low; don't claim failure

**Q2**: LiDAR frames are large. What's the storage/bandwidth trade-off for context packages?
- Options: subsample, compress, store only depth statistics

**Q3**: Gyro × optical flow check depends on good optical flow estimation. What's false positive/negative rate?
- Need: calibration study on real devices

### 13.2 Product

**Q4**: How much UX friction is acceptable for scan mode?
- Trade-off: more evidence vs user abandonment
- Consider: quick capture mode with explicit confidence reduction

**Q5**: Should we support gallery import with degraded confidence?
- Pro: utility for existing photos
- Con: dilutes trust model; may confuse users
- Tentative: No for v1; reconsider based on demand

**Q6**: Liability for "HIGH confidence" assessments that turn out wrong?
- Need: legal review of disclaimer language
- Position: we provide evidence, not guarantees

### 13.3 Strategic

**Q7**: Relationship with C2PA ecosystem—become a CA or rely on existing?
- Short-term: self-signed with published methodology
- Long-term: pursue C2PA conformance program certification

**Q8**: Open source vs proprietary methodology?
- Position: open methodology, robustness through design not obscurity
- Risk: attackers optimize against known checks
- Mitigation: checks are physics-based, hard to circumvent even if known

---

## 14. Success Metrics

### 14.1 Phase 0 (Hackathon)

- [ ] Hardware attestation working on Pixel 6+
- [ ] End-to-end flow: capture → verify URL → view evidence
- [ ] Verification page clearly shows attestation status
- [ ] Demo-able in 5 minutes

### 14.2 Phase 1 (Production)

| Metric | Target |
|--------|--------|
| Captures with hardware attestation | > 80% |
| Captures with environment scan | > 50% |
| Verification page bounce rate | < 30% |
| Evidence panel expansion rate | > 20% |
| Expert download rate | > 1% |

### 14.3 Long-term

- Adoption by at least one newsroom for verification workflow
- Cited in at least one published investigation
- C2PA conformance certification achieved

---

## Appendix A: Reference Implementation Notes

### A.1 Sun Angle Computation

```rust
// Using astronomical algorithms (simplified)
fn compute_sun_position(lat: f64, lon: f64, timestamp: DateTime<Utc>) -> SunPosition {
    let jd = julian_day(timestamp);
    let n = jd - 2451545.0;  // Days since J2000
    
    // Mean longitude and anomaly
    let l = (280.460 + 0.9856474 * n) % 360.0;
    let g = (357.528 + 0.9856003 * n) % 360.0;
    
    // Ecliptic longitude
    let lambda = l + 1.915 * g.to_radians().sin() + 0.020 * (2.0 * g).to_radians().sin();
    
    // Obliquity
    let epsilon = 23.439 - 0.0000004 * n;
    
    // Right ascension and declination
    let alpha = (epsilon.to_radians().cos() * lambda.to_radians().sin())
        .atan2(lambda.to_radians().cos()).to_degrees();
    let delta = (epsilon.to_radians().sin() * lambda.to_radians().sin()).asin().to_degrees();
    
    // Hour angle
    let gmst = (18.697374558 + 24.06570982441908 * n) % 24.0;
    let lst = gmst + lon / 15.0;
    let ha = (lst * 15.0 - alpha) % 360.0;
    
    // Altitude and azimuth
    let alt = (lat.to_radians().sin() * delta.to_radians().sin() 
        + lat.to_radians().cos() * delta.to_radians().cos() * ha.to_radians().cos())
        .asin().to_degrees();
    let az = (-ha.to_radians().sin())
        .atan2(lat.to_radians().cos() * delta.to_radians().tan() 
            - lat.to_radians().sin() * ha.to_radians().cos())
        .to_degrees();
    
    SunPosition { altitude: alt, azimuth: (az + 180.0) % 360.0 }
}
```

### A.2 Gyro × Optical Flow Consistency

```rust
fn check_gyro_optical_flow_consistency(
    gyro_samples: &[GyroSample],  // timestamp, rx, ry, rz
    frames: &[Frame],
    camera_intrinsics: &CameraIntrinsics,
) -> ConsistencyResult {
    // Integrate gyro to get rotation between frames
    let mut gyro_rotations = Vec::new();
    for window in frames.windows(2) {
        let t0 = window[0].timestamp;
        let t1 = window[1].timestamp;
        let gyro_slice: Vec<_> = gyro_samples.iter()
            .filter(|s| s.timestamp >= t0 && s.timestamp <= t1)
            .collect();
        let rotation = integrate_gyro(&gyro_slice);
        gyro_rotations.push(rotation);
    }
    
    // Compute optical flow between frames
    let mut flow_rotations = Vec::new();
    for window in frames.windows(2) {
        let flow = compute_optical_flow(&window[0], &window[1]);
        let rotation = estimate_rotation_from_flow(&flow, camera_intrinsics);
        flow_rotations.push(rotation);
    }
    
    // Compare
    let deviations: Vec<f64> = gyro_rotations.iter()
        .zip(flow_rotations.iter())
        .map(|(g, f)| rotation_angle_difference(g, f))
        .collect();
    
    let mean_deviation = deviations.iter().sum::<f64>() / deviations.len() as f64;
    let max_deviation = deviations.iter().cloned().fold(0.0, f64::max);
    
    ConsistencyResult {
        status: if max_deviation < 5.0 { "pass" } else { "fail" },
        mean_deviation_deg: mean_deviation,
        max_deviation_deg: max_deviation,
    }
}
```

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| C2PA | Coalition for Content Provenance and Authenticity—technical standard for media provenance |
| Content Credentials | User-facing brand for C2PA-based provenance metadata |
| DCAppAttest | Apple's device attestation API for iOS apps |
| Hardware attestation | Cryptographic proof that code runs in trusted hardware environment |
| HSM | Hardware Security Module—dedicated cryptographic processor |
| JUMBF | JPEG Universal Metadata Box Format—container for C2PA manifests |
| Key attestation | Android feature proving a key was generated in secure hardware |
| NeRF | Neural Radiance Field—ML technique for 3D scene synthesis |
| Optical flow | Per-pixel motion estimation between video frames |
| Secure Enclave | Apple's hardware security subsystem |
| StrongBox | Android hardware security module (highest security level) |
| TEE | Trusted Execution Environment—isolated processing environment |

---

*PRD Version: 2.0*
*Last Updated: November 2025*
*Status: Draft for review*
