# Epic Technical Specification: Upload, Processing & Evidence Generation

Date: 2025-11-23
Author: Luca
Epic ID: 4
Status: Draft

---

## Overview

Epic 4 implements the complete upload and evidence processing pipeline for RealityCam, bridging the capture experience (Epic 3) with the verification interface (Epic 5). This epic transforms locally-captured photos with LiDAR depth data into fully-analyzed, cryptographically-attested evidence packages with confidence scores.

The epic spans two system boundaries: (1) the iOS mobile client handling upload queue management, offline storage, and automatic synchronization, and (2) the Rust backend performing attestation verification, LiDAR depth analysis, metadata validation, and confidence calculation. Together, these components fulfill the PRD's core value proposition: "cryptographically-attested, LiDAR-verified photo provenance."

**FRs Covered:** FR14-FR26, FR44-FR46 (13 functional requirements)

## Objectives and Scope

### In-Scope

**Mobile Client (apps/mobile)**
- Multipart upload of photo + depth_map + metadata to backend
- Upload queue with exponential backoff retry (1s, 2s, 4s, 8s, max 5 minutes)
- Encrypted offline storage using Secure Enclave-backed keys
- Automatic upload when connectivity returns
- Upload progress and status UI in History tab
- TLS 1.3 for all API communication

**Backend Services (backend/)**
- `POST /api/v1/captures` multipart endpoint with streaming to S3
- Per-capture assertion verification against registered device keys
- LiDAR depth analysis service (variance, layers, edge coherence)
- Metadata validation (timestamp, device model, location plausibility)
- Evidence package assembly (JSONB structure)
- Confidence level calculation (HIGH/MEDIUM/LOW/SUSPICIOUS)
- Privacy coarsening for GPS coordinates (city-level public, precise internal)

### Out-of-Scope

- C2PA manifest generation (Epic 5, Story 5-1)
- C2PA signing and embedding (Epic 5, Stories 5-2, 5-3)
- Verification page UI (Epic 5, Stories 5-4 through 5-8)
- User accounts and authentication (device-only auth per PRD)
- Video capture processing (post-MVP)
- Advanced evidence checks: sun angle, barometric pressure, gyro correlation (post-MVP)

## System Architecture Alignment

### Component References

| Component | Location | Role in Epic 4 |
|-----------|----------|----------------|
| Upload Queue | `apps/mobile/hooks/useUploadQueue.ts` | Queue management, retry logic |
| API Service | `apps/mobile/services/api.ts` | HTTP client with device auth headers |
| Capture Store | `apps/mobile/store/captureStore.ts` | Local state, offline persistence |
| Captures Route | `backend/src/routes/captures.rs` | Upload endpoint handler |
| Device Auth Middleware | `backend/src/middleware/device_auth.rs` | Request signature verification |
| Evidence Services | `backend/src/services/evidence/` | Depth, hardware, metadata analysis |
| Storage Service | `backend/src/services/storage.rs` | S3 operations |

### Architecture Constraints

1. **Device Signature Required**: All upload requests must include `X-Device-Id`, `X-Device-Timestamp`, `X-Device-Signature` headers (ADR-005)
2. **JSONB Evidence Storage**: Evidence package stored as JSONB for schema flexibility (ADR-006)
3. **Streaming Upload**: Large files (photo ~3MB, depth ~1MB) streamed directly to S3, not buffered in memory
4. **Rate Limiting**: 10 captures/hour/device (PRD Section: API Authentication Flow)

---

## Detailed Design

### Services and Modules

#### Mobile Modules

| Module | Responsibility | Inputs | Outputs |
|--------|---------------|--------|---------|
| `useUploadQueue` | Manages persistent upload queue, retry logic, background sync | Capture from local storage | Upload status, capture_id on success |
| `useNetworkStatus` | Monitors connectivity via @react-native-community/netinfo | System events | Online/offline boolean |
| `OfflineStorage` | Encrypts captures with SE-backed key, manages pending queue | Raw capture data | Encrypted files in document directory |
| `api.ts` | HTTP client with device auth, multipart upload | Capture parts + metadata | API response |

#### Backend Modules

| Module | Responsibility | Inputs | Outputs | Owner |
|--------|---------------|--------|---------|-------|
| `routes/captures.rs` | Endpoint handler, multipart parsing, orchestration | HTTP request | CaptureResponse | Backend |
| `middleware/device_auth.rs` | Validates device signature on every request | Request headers | Authenticated device_id | Backend |
| `services/attestation.rs` | Verifies per-capture assertions | Assertion object, device record | Verification result | Backend |
| `services/evidence/depth.rs` | LiDAR depth analysis algorithms | Float32 depth array, RGB image | DepthAnalysis struct | Backend |
| `services/evidence/metadata.rs` | EXIF validation, device model check | Photo bytes, metadata JSON | MetadataChecks struct | Backend |
| `services/evidence/pipeline.rs` | Orchestrates all checks, assembles evidence | Capture data | EvidencePackage, confidence | Backend |
| `services/storage.rs` | S3 upload, presigned URLs | Binary data | S3 keys, URLs | Backend |

### Data Models and Contracts

#### Capture Entity (PostgreSQL)

```sql
-- Existing from Epic 1, Story 1-3
CREATE TABLE captures (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id           UUID NOT NULL REFERENCES devices(id),
    target_media_hash   BYTEA NOT NULL UNIQUE,
    evidence            JSONB NOT NULL,
    confidence_level    TEXT NOT NULL CHECK (confidence_level IN ('high', 'medium', 'low', 'suspicious')),
    status              TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'complete', 'failed')),
    captured_at         TIMESTAMPTZ NOT NULL,
    uploaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Added for Epic 4
    photo_s3_key        TEXT NOT NULL,
    depth_map_s3_key    TEXT NOT NULL,
    thumbnail_s3_key    TEXT,
    location_precise    JSONB,  -- Full precision, internal only
    location_coarse     TEXT    -- City-level string, public
);

-- Hash index for O(1) lookup (from Epic 1)
CREATE INDEX idx_captures_hash ON captures USING hash(target_media_hash);
CREATE INDEX idx_captures_device ON captures USING btree(device_id);
CREATE INDEX idx_captures_status ON captures USING btree(status);
```

#### Evidence Package Schema (JSONB)

```typescript
interface EvidencePackage {
  hardware_attestation: {
    status: 'pass' | 'fail' | 'unavailable';
    level: 'secure_enclave' | 'unverified';
    device_model: string;
    assertion_verified: boolean;
    counter_valid: boolean;
  };
  depth_analysis: {
    status: 'pass' | 'fail';
    depth_variance: number;      // f32, threshold > 0.5
    depth_layers: number;        // u32, threshold >= 3
    edge_coherence: number;      // f32, threshold > 0.7
    min_depth: number;           // f32, meters
    max_depth: number;           // f32, meters
    is_likely_real_scene: boolean;
  };
  metadata: {
    timestamp_valid: boolean;    // EXIF within 15 min of server time
    timestamp_delta_seconds: number;
    model_verified: boolean;     // iPhone Pro with LiDAR
    model_name: string;
    resolution_valid: boolean;
    location_available: boolean;
    location_opted_out: boolean;
  };
  processing: {
    processed_at: string;        // ISO 8601
    processing_time_ms: number;
    backend_version: string;
  };
}
```

#### Rust Types

```rust
// backend/src/models/evidence.rs

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidencePackage {
    pub hardware_attestation: HardwareAttestation,
    pub depth_analysis: DepthAnalysis,
    pub metadata: MetadataChecks,
    pub processing: ProcessingInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareAttestation {
    pub status: CheckStatus,
    pub level: AttestationLevel,
    pub device_model: String,
    pub assertion_verified: bool,
    pub counter_valid: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepthAnalysis {
    pub status: CheckStatus,
    pub depth_variance: f32,
    pub depth_layers: u32,
    pub edge_coherence: f32,
    pub min_depth: f32,
    pub max_depth: f32,
    pub is_likely_real_scene: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetadataChecks {
    pub timestamp_valid: bool,
    pub timestamp_delta_seconds: i64,
    pub model_verified: bool,
    pub model_name: String,
    pub resolution_valid: bool,
    pub location_available: bool,
    pub location_opted_out: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CheckStatus {
    Pass,
    Fail,
    Unavailable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AttestationLevel {
    SecureEnclave,
    Unverified,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConfidenceLevel {
    High,
    Medium,
    Low,
    Suspicious,
}

impl ConfidenceLevel {
    pub fn calculate(evidence: &EvidencePackage) -> Self {
        // If any check explicitly failed, mark as suspicious
        if evidence.hardware_attestation.status == CheckStatus::Fail
            || evidence.depth_analysis.status == CheckStatus::Fail
        {
            return ConfidenceLevel::Suspicious;
        }

        let hw_pass = evidence.hardware_attestation.status == CheckStatus::Pass;
        let depth_pass = evidence.depth_analysis.is_likely_real_scene;

        match (hw_pass, depth_pass) {
            (true, true) => ConfidenceLevel::High,
            (true, false) | (false, true) => ConfidenceLevel::Medium,
            (false, false) => ConfidenceLevel::Low,
        }
    }
}
```

#### Mobile Types (TypeScript)

```typescript
// packages/shared/src/types/capture.ts

export interface CaptureUploadRequest {
  photo: Blob;              // JPEG binary
  depth_map: Blob;          // gzipped float32 array
  metadata: CaptureMetadata;
}

export interface CaptureMetadata {
  captured_at: string;      // ISO 8601
  device_model: string;
  photo_hash: string;       // SHA-256 base64
  assertion: string;        // Base64 assertion from @expo/app-integrity
  location?: {
    latitude: number;
    longitude: number;
    altitude?: number;
    accuracy?: number;
  };
  depth_map_dimensions: {
    width: number;
    height: number;
  };
}

export interface CaptureUploadResponse {
  data: {
    capture_id: string;
    status: 'processing' | 'complete';
    verification_url: string;
  };
}

export type UploadStatus =
  | 'pending'
  | 'uploading'
  | 'processing'
  | 'complete'
  | 'failed';

export interface QueuedCapture {
  id: string;               // Local UUID
  capture_id?: string;      // Server UUID after upload
  status: UploadStatus;
  created_at: string;
  retry_count: number;
  last_retry_at?: string;
  error?: string;
  photo_path: string;       // Local file path
  depth_path: string;       // Local file path
  metadata: CaptureMetadata;
}
```

### APIs and Interfaces

#### POST /api/v1/captures

**Purpose:** Upload captured photo with depth map and metadata for evidence processing.

**Request:**
```http
POST /api/v1/captures
Content-Type: multipart/form-data
X-Device-Id: {device_uuid}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {base64_signature}

--boundary
Content-Disposition: form-data; name="photo"; filename="capture.jpg"
Content-Type: image/jpeg

{JPEG binary data ~3MB}
--boundary
Content-Disposition: form-data; name="depth_map"; filename="depth.gz"
Content-Type: application/gzip

{gzipped float32 array ~1MB}
--boundary
Content-Disposition: form-data; name="metadata"
Content-Type: application/json

{
  "captured_at": "2025-11-23T10:30:00.123Z",
  "device_model": "iPhone 15 Pro",
  "photo_hash": "base64-sha256-hash",
  "assertion": "base64-assertion-object",
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "altitude": 10.5,
    "accuracy": 5.0
  },
  "depth_map_dimensions": {
    "width": 256,
    "height": 192
  }
}
--boundary--
```

**Response (Success - 202 Accepted):**
```json
{
  "data": {
    "capture_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/550e8400-e29b-41d4-a716-446655440000"
  },
  "meta": {
    "request_id": "req-abc123",
    "timestamp": "2025-11-23T10:30:01Z"
  }
}
```

**Error Responses:**

| HTTP Status | Error Code | Condition |
|-------------|------------|-----------|
| 400 | `VALIDATION_ERROR` | Missing required parts, invalid metadata |
| 401 | `SIGNATURE_INVALID` | Device signature verification failed |
| 401 | `TIMESTAMP_EXPIRED` | Request timestamp outside 5-minute window |
| 404 | `DEVICE_NOT_FOUND` | Unknown device ID |
| 413 | `PAYLOAD_TOO_LARGE` | Photo > 10MB or depth > 5MB |
| 429 | `RATE_LIMITED` | Exceeded 10 captures/hour/device |
| 500 | `STORAGE_ERROR` | S3 upload failed |
| 500 | `PROCESSING_FAILED` | Evidence computation failed |

#### GET /api/v1/captures/{id}

**Purpose:** Retrieve capture with evidence package (already exists from Epic 1).

**Response for complete capture:**
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "confidence_level": "high",
    "status": "complete",
    "captured_at": "2025-11-23T10:30:00Z",
    "uploaded_at": "2025-11-23T10:30:01Z",
    "media_url": "https://cdn.../signed-url?expires=3600",
    "thumbnail_url": "https://cdn.../thumb-signed-url?expires=3600",
    "depth_preview_url": "https://cdn.../depth-preview.png?expires=3600",
    "evidence": {
      "hardware_attestation": {
        "status": "pass",
        "level": "secure_enclave",
        "device_model": "iPhone 15 Pro",
        "assertion_verified": true,
        "counter_valid": true
      },
      "depth_analysis": {
        "status": "pass",
        "depth_variance": 2.4,
        "depth_layers": 5,
        "edge_coherence": 0.87,
        "min_depth": 0.8,
        "max_depth": 4.2,
        "is_likely_real_scene": true
      },
      "metadata": {
        "timestamp_valid": true,
        "timestamp_delta_seconds": 2,
        "model_verified": true,
        "model_name": "iPhone 15 Pro",
        "resolution_valid": true,
        "location_available": true,
        "location_opted_out": false
      },
      "processing": {
        "processed_at": "2025-11-23T10:30:05Z",
        "processing_time_ms": 4200,
        "backend_version": "0.1.0"
      }
    },
    "location_coarse": "San Francisco, CA"
  }
}
```

### Workflows and Sequencing

#### Upload Flow (Mobile to Backend)

```
Mobile App                              Backend                              S3
    |                                      |                                  |
    |-- (1) Prepare upload request ------->|                                  |
    |   - Add device auth headers          |                                  |
    |   - Build multipart form data        |                                  |
    |                                      |                                  |
    |      POST /api/v1/captures           |                                  |
    |------------------------------------->|                                  |
    |                                      |                                  |
    |                             (2) Validate request                        |
    |                             - Check device signature                    |
    |                             - Verify timestamp window                   |
    |                             - Parse multipart parts                     |
    |                                      |                                  |
    |                             (3) Stream to S3----------------------------->
    |                                      |         PUT original.jpg         |
    |                                      |         PUT depth.gz             |
    |                                      |<-------------------------------- |
    |                                      |                                  |
    |                             (4) Create capture record                   |
    |                             - status: "processing"                      |
    |                             - Store S3 keys                             |
    |                                      |                                  |
    |<-- (5) Return capture_id, status ----|                                  |
    |                                      |                                  |
    |                             (6) Background processing                   |
    |                             - Spawn Tokio task                          |
    |                             - Run evidence pipeline                     |
    |                                      |                                  |
    |                             (7) Update capture record                   |
    |                             - evidence: {package}                       |
    |                             - confidence_level                          |
    |                             - status: "complete"                        |
```

#### Evidence Processing Pipeline (Backend)

```
Capture Upload Received
        |
        v
+-------------------+
| Parse & Validate  |
| Multipart Request |
+-------------------+
        |
        v
+-------------------+     +-------------------+
| Device Auth       |---->| Lookup Device     |
| Middleware        |     | Verify Signature  |
+-------------------+     +-------------------+
        |
        v
+-------------------+
| Stream to S3      |
| (photo, depth_map)|
+-------------------+
        |
        v
+-------------------+
| Create DB Record  |
| status: processing|
+-------------------+
        |
        v (async spawn)
+-------------------+
| Evidence Pipeline |
+-------------------+
        |
        +---> [1] Assertion Verification
        |         - Decode CBOR assertion
        |         - Verify signature vs device key
        |         - Check counter increment
        |
        +---> [2] Depth Analysis (parallel)
        |         - Decompress gzipped depth map
        |         - Calculate variance, layers
        |         - Compute edge coherence vs RGB
        |         - Determine is_likely_real_scene
        |
        +---> [3] Metadata Validation (parallel)
        |         - Parse EXIF from photo
        |         - Compare timestamps
        |         - Verify device model
        |         - Check resolution
        |
        +---> [4] Privacy Processing
                  - Coarsen GPS to city level
                  - Store precise internally
        |
        v
+-------------------+
| Assemble Evidence |
| Calculate         |
| Confidence Level  |
+-------------------+
        |
        v
+-------------------+
| Generate Depth    |
| Preview PNG       |
+-------------------+
        |
        v
+-------------------+
| Update DB Record  |
| status: complete  |
+-------------------+
```

#### Offline Upload Queue (Mobile)

```
State Machine for Queued Capture:

                    [Network Available]
    +--------+          +----------+           +-----------+
    | pending|--------->| uploading|---------->| processing|
    +--------+          +----------+           +-----------+
        ^                    |                       |
        |                    | [Upload Error]        | [Poll Complete]
        |                    v                       v
        |               +--------+             +---------+
        +---------------| failed |             | complete|
        [Retry Timer]   +--------+             +---------+
                             |
                             | [Max Retries]
                             v
                        +-----------+
                        |permanently|
                        |  failed   |
                        +-----------+

Retry Schedule:
- Attempt 1: immediate
- Attempt 2: 1 second delay
- Attempt 3: 2 seconds delay
- Attempt 4: 4 seconds delay
- Attempt 5: 8 seconds delay
- Attempts 6-10: 5 minutes delay (max backoff)
- After 10 attempts: mark permanently failed
```

---

## Non-Functional Requirements

### Performance

| Metric | Target | Source |
|--------|--------|--------|
| Capture upload time | < 10s on 10 MB/s connection | PRD: Upload throughput |
| Evidence processing time | < 5s total | PRD: Depth analysis computation |
| Depth analysis algorithm | < 2s | Part of 5s budget |
| Metadata validation | < 500ms | Part of 5s budget |
| Assertion verification | < 500ms | Part of 5s budget |
| End-to-end (capture to complete) | < 15s | PRD: Performance targets |

**Implementation Requirements:**
- Stream multipart directly to S3 (no memory buffering of full payload)
- Run depth analysis, metadata validation, and assertion verification in parallel using Tokio tasks
- Use presigned S3 URLs to avoid proxying large files through backend
- Generate thumbnail and depth preview asynchronously after main processing

### Security

**Authentication & Authorization:**
- All `/api/v1/captures` requests require valid device signature (X-Device-Id, X-Device-Timestamp, X-Device-Signature)
- Signature computed over: `timestamp + "|" + sha256(request_body)`
- Timestamp must be within 5-minute window of server time
- Device must be registered (exists in `devices` table)

**Data Protection:**
- TLS 1.3 required for all API communication (PRD: FR15)
- Offline captures encrypted with Secure Enclave-backed key (PRD: FR17)
- GPS coordinates stored at two precision levels:
  - `location_precise`: Full precision, internal only, never exposed via public API
  - `location_coarse`: City-level (~2 decimal places), exposed in public verification

**Threat Mitigations:**

| Threat | Mitigation | Evidence Check |
|--------|------------|----------------|
| Replay attack (resubmit old capture) | Assertion counter must increment | Hardware attestation |
| Spoofed timestamp | Server compares EXIF vs upload time | Metadata validation |
| Flat image as scene | Depth variance, layer, coherence checks | Depth analysis |
| MITM upload interception | TLS 1.3 + device signature | Transport |
| Unauthorized device | Device auth middleware validates signature | Hardware attestation |

**Rate Limiting:**
- 10 captures/hour/device (prevents abuse)
- 429 response with `Retry-After` header

### Reliability/Availability

**Offline Resilience (Mobile):**
- Captures stored in encrypted local storage when offline
- Queue persisted to device (survives app restart)
- Automatic retry when connectivity returns
- User notified of pending uploads with timestamp warning

**Backend Resilience:**
- If S3 upload fails: return 500, mobile will retry
- If evidence processing fails: mark capture as "failed", log error, alert
- Database transaction for capture record creation + S3 key storage
- Idempotency: Same photo_hash rejected with 409 Conflict (prevents duplicates)

**Recovery:**
- Failed captures remain in queue for manual retry
- Backend can reprocess captures with `status: failed` via admin endpoint (post-MVP)

### Observability

**Logging Requirements:**

| Log Event | Level | Fields |
|-----------|-------|--------|
| Upload received | INFO | device_id, photo_size, depth_size, request_id |
| Device auth failed | WARN | device_id, reason, request_id |
| S3 upload complete | DEBUG | capture_id, s3_keys, duration_ms |
| Evidence processing start | INFO | capture_id |
| Depth analysis result | INFO | capture_id, variance, layers, coherence, is_real |
| Assertion verification result | INFO | capture_id, verified, counter_valid |
| Evidence complete | INFO | capture_id, confidence_level, processing_time_ms |
| Processing failed | ERROR | capture_id, error, stack_trace |

**Metrics (Prometheus/StatsD):**
- `realitycam_uploads_total` (counter): device_id, status
- `realitycam_upload_size_bytes` (histogram): type (photo, depth)
- `realitycam_processing_duration_ms` (histogram): stage
- `realitycam_confidence_level` (counter): level
- `realitycam_depth_variance` (histogram)
- `realitycam_queue_depth` (gauge): Mobile upload queue size

**Tracing:**
- Request ID propagated through all logs
- Span for each pipeline stage (assertion, depth, metadata)
- Trace ID in response headers for debugging

---

## Dependencies and Integrations

### External Libraries

**Backend (Cargo.toml additions for Epic 4):**

| Crate | Version | Purpose |
|-------|---------|---------|
| `axum-extra` | 0.10 | Multipart form handling |
| `tokio-util` | 1.0 | Streaming IO utilities |
| `kamadak-exif` | 0.5 | EXIF metadata parsing |
| `image` | 0.25 | RGB image loading for edge coherence |
| `flate2` | 1.0 | Gzip decompression for depth maps |
| `byteorder` | 1.5 | Float32 array parsing |
| `reverse-geocoder` | 4.0 | Offline GPS to city name |

**Mobile (package.json additions for Epic 4):**

| Package | Version | Purpose |
|---------|---------|---------|
| `@react-native-community/netinfo` | ^11.0 | Network connectivity monitoring |
| `expo-background-fetch` | ~13.0 | Background upload scheduling |
| `pako` | ^2.1 | Gzip compression for depth maps |
| `react-native-background-upload` | ^7.0 | Background upload with progress |

### Internal Dependencies

| Module | Depends On | Status |
|--------|------------|--------|
| Upload endpoint | Device auth middleware (Epic 2) | Complete |
| Assertion verification | Device record with attestation_key_id (Epic 2) | Complete |
| Depth analysis | Depth map format from capture pipeline (Epic 3) | Complete |
| S3 storage | Storage service (Epic 1) | Complete |
| Database captures table | Schema migrations (Epic 1) | Complete |

### Third-Party Services

| Service | Purpose | Fallback |
|---------|---------|----------|
| AWS S3 | Photo and depth map storage | LocalStack for dev |
| CloudFront | CDN delivery of verification assets | Direct S3 for dev |

---

## Acceptance Criteria (Authoritative)

### AC-4.1: Multipart Upload Endpoint
1. Backend accepts `POST /api/v1/captures` with multipart/form-data containing photo (JPEG), depth_map (gzip), and metadata (JSON)
2. Request requires valid device signature headers (X-Device-Id, X-Device-Timestamp, X-Device-Signature)
3. Photo and depth_map are streamed directly to S3 without full memory buffering
4. Response returns capture_id and status "processing" within 2 seconds
5. Rate limiting enforces 10 captures/hour/device

### AC-4.2: Upload Queue with Retry
1. Mobile maintains persistent upload queue that survives app restart
2. Failed uploads retry with exponential backoff (1s, 2s, 4s, 8s, max 5 min)
3. Upload progress is visible in History tab (0-100%)
4. User can cancel pending upload or retry failed upload manually
5. After 10 failed attempts, upload marked as permanently failed with clear error message

### AC-4.3: Offline Storage and Auto-Upload
1. Captures taken offline are stored in encrypted local storage using Secure Enclave-backed key
2. Offline captures display "Pending upload" badge with timestamp warning
3. When connectivity returns, captures automatically queue for upload
4. Upload order preserves capture chronology (oldest first)
5. Encryption uses `expo-secure-store` for key management

### AC-4.4: Assertion Verification
1. Backend decodes CBOR assertion object from metadata
2. Signature verified against device's stored attestation public key
3. Counter must be strictly greater than last-seen counter for this device
4. Successful verification recorded as hardware_attestation.status = "pass"
5. Failed verification recorded as "fail" with reason logged; capture continues processing

### AC-4.5: LiDAR Depth Analysis Service
1. Depth map decompressed from gzip float32 array
2. Algorithm computes: depth_variance, depth_layers, edge_coherence, min_depth, max_depth
3. is_likely_real_scene = true when: variance > 0.5 AND layers >= 3 AND coherence > 0.7
4. Analysis completes in < 2 seconds
5. Results stored in evidence.depth_analysis JSONB field

### AC-4.6: Metadata Validation
1. EXIF timestamp extracted from photo using `kamadak-exif`
2. Timestamp valid if within 15 minutes of server receipt time
3. Device model verified against iPhone Pro whitelist (12-17 Pro/Pro Max)
4. Resolution validated against known device capabilities
5. Location plausibility checked (lat -90 to 90, lng -180 to 180)

### AC-4.7: Evidence Package and Confidence Calculation
1. Evidence package assembled with hardware_attestation, depth_analysis, metadata, processing sections
2. Confidence calculated: SUSPICIOUS if any fail; HIGH if hw+depth pass; MEDIUM if one passes; LOW if both unavailable/fail
3. Capture status updated from "processing" to "complete"
4. Processing completes within 5 seconds total
5. Evidence stored as JSONB in captures.evidence column

### AC-4.8: Privacy Controls
1. GPS coordinates stored at full precision in location_precise (internal only)
2. Public API returns location_coarse (city-level, ~2 decimal places)
3. If user opted out of location, location_opted_out = true, status = "unavailable" (not fail)
4. Depth map stored but only visualization (PNG) exposed publicly
5. Original depth float array never downloadable via public API

---

## Traceability Mapping

| AC | FR(s) | Spec Section | Component(s) | Test Approach |
|----|-------|--------------|--------------|---------------|
| AC-4.1 | FR14, FR15 | APIs: POST /captures | `routes/captures.rs`, `api.ts` | Integration test with multipart payload |
| AC-4.2 | FR16, FR19 | Workflows: Offline Queue | `useUploadQueue.ts` | Unit test retry logic, E2E queue persistence |
| AC-4.3 | FR17, FR18 | Workflows: Offline Queue | `OfflineStorage`, `useNetworkStatus` | E2E offline/online transition |
| AC-4.4 | FR20 | Services: attestation.rs | `attestation.rs`, `device_auth.rs` | Unit test CBOR decode, signature verify |
| AC-4.5 | FR21, FR22 | Services: depth.rs | `evidence/depth.rs` | Unit test with known flat/real depth samples |
| AC-4.6 | FR23, FR24 | Services: metadata.rs | `evidence/metadata.rs` | Unit test EXIF parsing, model whitelist |
| AC-4.7 | FR25, FR26 | Services: pipeline.rs | `evidence/pipeline.rs` | Integration test full pipeline |
| AC-4.8 | FR44, FR45, FR46 | Data Models: location | `pipeline.rs`, captures schema | Unit test coarsening, E2E API response |

---

## Risks, Assumptions, Open Questions

### Risks

| ID | Risk | Impact | Mitigation |
|----|------|--------|------------|
| R1 | Depth analysis thresholds may need tuning | False positives/negatives | Start with PRD values (0.5, 3, 0.7), collect telemetry, adjust |
| R2 | Large files may cause mobile memory pressure | App crashes | Stream uploads, avoid loading full photo/depth into memory |
| R3 | Offline captures have delayed timestamps | Reduced confidence | Document limitation, consider MEDIUM ceiling for delayed uploads |
| R4 | Assertion counter drift if mobile state lost | Replay detection fails | Reset counter on re-registration, track last counter server-side |
| R5 | Reverse geocoding dependency | Location display fails | Use offline geocoder library, graceful degradation to coordinates |

### Assumptions

| ID | Assumption | Validation |
|----|------------|------------|
| A1 | Depth map format is gzipped float32 array (256x192) | Confirmed in Epic 3 implementation |
| A2 | Device public key stored during registration | Verified in Epic 2, Story 2-5 |
| A3 | TLS 1.3 available on all target iOS versions | iOS 14.0+ supports TLS 1.3 |
| A4 | 10 captures/hour rate limit sufficient for typical use | Can adjust post-launch based on telemetry |
| A5 | 15-minute timestamp tolerance accounts for timezone/drift | May need adjustment for edge cases |

### Open Questions

| ID | Question | Owner | Resolution Path |
|----|----------|-------|-----------------|
| Q1 | Should failed depth analysis (flat scene) block C2PA generation? | PM | Decide before Epic 5: recommend NO, generate C2PA with low confidence |
| Q2 | What city-level precision for coarsened GPS? (~1km or ~11km) | PM | Recommend 2 decimal places (~1.1km) |
| Q3 | Background upload notification behavior on iOS? | Dev | Test with expo-background-fetch, may need native module |
| Q4 | Max offline queue size before warning user? | UX | Recommend 50 captures (~200MB), configurable |

---

## Test Strategy Summary

### Unit Tests

**Backend (Rust):**
- `depth.rs`: Test variance, layer detection, edge coherence with synthetic depth maps (flat plane, real scene samples)
- `metadata.rs`: Test EXIF parsing, timestamp validation, model whitelist
- `attestation.rs`: Test CBOR decoding, signature verification with test vectors
- `pipeline.rs`: Test confidence calculation logic with various evidence combinations

**Mobile (TypeScript/Jest):**
- `useUploadQueue`: Test retry logic, state transitions, persistence
- `OfflineStorage`: Test encryption/decryption, file management
- `api.ts`: Test header generation, multipart construction

### Integration Tests

**Backend (testcontainers):**
- Full upload flow with real PostgreSQL and LocalStack S3
- Device auth middleware with test device
- Evidence pipeline end-to-end with sample capture data
- Rate limiting behavior

**Mobile (Maestro E2E):**
- Capture -> Upload -> Verify URL flow on real device
- Offline capture -> Online -> Auto-upload
- Failed upload -> Retry -> Success

### Test Data Requirements

| Data | Source | Purpose |
|------|--------|---------|
| Flat depth map | Synthetic (uniform 0.4m) | Test depth_layers = 1 detection |
| Real scene depth | Captured from iPhone Pro | Test variance > 0.5 detection |
| Valid JPEG with EXIF | Sample capture | Test metadata extraction |
| CBOR assertion sample | @expo/app-integrity test mode | Test assertion verification |

### Coverage Targets

- Unit test coverage: > 80% for evidence modules
- All acceptance criteria have at least one automated test
- Critical paths (upload, depth analysis, confidence) have integration tests
- Regression test for each resolved bug
