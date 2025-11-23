# Epic Technical Specification: C2PA Integration & Verification Interface

Date: 2025-11-23
Author: Luca
Epic ID: 5
Status: Draft

---

## Overview

Epic 5 completes the RealityCam MVP by implementing C2PA (Coalition for Content Provenance and Authenticity) integration and the public verification interface. This epic transforms processed evidence packages (from Epic 4) into interoperable C2PA manifests embedded in photos, and provides a comprehensive web interface for recipients to verify photo authenticity.

The epic spans three system boundaries: (1) the Rust backend generating and signing C2PA manifests, (2) the Next.js verification web app displaying evidence and handling file uploads, and (3) the iOS mobile app showing capture results with verification URLs.

**FRs Covered:** FR27-FR40 (14 functional requirements)

## Objectives and Scope

### In-Scope

**Backend Services (backend/)**
- C2PA manifest generation using c2pa-rs 0.51.x
- Ed25519 signing of manifests with configurable key management
- Manifest embedding into JPEG photos (JUMBF format)
- Storage of original, C2PA-embedded, and manifest files
- File verification endpoint with hash lookup and C2PA extraction
- Depth preview image generation

**Verification Web (apps/web/)**
- Verification page with confidence summary display
- Depth analysis visualization with toggle overlay
- Collapsible evidence panel with per-check status
- C2PA manifest display and download links
- File upload verification with drag-drop support
- Responsive design with social sharing meta tags

**Mobile App (apps/mobile/)**
- Capture result screen with verification URL
- Share functionality for verification links
- Evidence summary display post-upload

### Out-of-Scope

- Certificate Authority (CA) setup for production (using self-signed for MVP)
- HSM integration for production key storage (file-based for MVP)
- Real-time WebSocket updates for processing status
- Video capture support (post-MVP)
- User accounts and capture revocation (post-MVP)

## System Architecture Alignment

### Component References

| Component | Location | Role in Epic 5 |
|-----------|----------|----------------|
| C2PA Service | `backend/src/services/c2pa.rs` | Manifest generation, signing, embedding |
| Verify Route | `backend/src/routes/verify.rs` | File verification endpoint |
| Captures Route | `backend/src/routes/captures.rs` | Capture data retrieval with C2PA URLs |
| Storage Service | `backend/src/services/storage.rs` | S3 operations for C2PA files |
| Verification Page | `apps/web/src/app/verify/[id]/page.tsx` | Main verification UI |
| Evidence Components | `apps/web/src/components/Evidence/` | Evidence display components |
| Upload Components | `apps/web/src/components/Upload/` | File upload UI |
| Result Screen | `apps/mobile/app/result.tsx` | Post-upload result display |

### Architecture Constraints

1. **C2PA Specification Compliance**: Manifests must conform to C2PA 2.0 specification
2. **Ed25519 Signing**: Use Ed25519 for manifest signatures (per ADR-005, architecture.md)
3. **Presigned URLs**: All media URLs expire in 1 hour (per architecture.md)
4. **JSONB Evidence**: Evidence structure matches Epic 4 EvidencePackage schema

---

## Detailed Design

### Services and Modules

#### Backend Modules

| Module | Responsibility | Inputs | Outputs |
|--------|---------------|--------|---------|
| `services/c2pa.rs` | C2PA manifest generation, signing, embedding | EvidencePackage, photo bytes | Manifest, embedded JPEG |
| `routes/verify.rs` | File verification endpoint | Uploaded file | Verification result |
| `routes/captures.rs` (extended) | Add C2PA URLs to capture response | Capture ID | Capture with C2PA data |
| `services/storage.rs` (extended) | Store C2PA files to S3 | Binary data | S3 keys |

#### Web Modules

| Module | Responsibility | Inputs | Outputs |
|--------|---------------|--------|---------|
| `app/verify/[id]/page.tsx` | Main verification page | Capture ID from URL | Rendered verification UI |
| `components/Evidence/EvidencePanel.tsx` | Collapsible evidence display | Evidence package | UI panel |
| `components/Evidence/DepthVisualization.tsx` | Depth map overlay | Depth preview URL | Interactive overlay |
| `components/Evidence/ConfidenceSummary.tsx` | Confidence badge and summary | Confidence level | Hero section |
| `components/Upload/FileDropzone.tsx` | Drag-drop file upload | File | Upload to verify endpoint |
| `components/Verification/VerificationResult.tsx` | Display verification result | API response | Result UI |

#### Mobile Modules

| Module | Responsibility | Inputs | Outputs |
|--------|---------------|--------|---------|
| `app/result.tsx` | Post-upload result screen | Capture response | UI with share functionality |
| `components/Evidence/EvidenceSummary.tsx` | Brief evidence summary | Evidence package | Summary cards |

### Data Models and Contracts

#### C2PA Manifest Structure

```rust
// backend/src/services/c2pa.rs

use c2pa::{Manifest, ManifestStore, assertions::Action};

pub struct C2paManifest {
    /// Claim generator identifier
    pub claim_generator: String,      // "RealityCam/0.1.0"

    /// Actions (always "c2pa.created")
    pub actions: Vec<C2paAction>,

    /// Custom assertions for RealityCam evidence
    pub assertions: RealityCamAssertions,

    /// Certificate chain for signature verification
    pub certificate_chain: Vec<u8>,
}

pub struct C2paAction {
    pub action: String,               // "c2pa.created"
    pub when: String,                 // ISO 8601 timestamp
    pub software_agent: String,       // "RealityCam iOS/1.0.0"
}

pub struct RealityCamAssertions {
    /// Hardware attestation summary
    pub hardware_attestation: HardwareAssertionSummary,

    /// Depth analysis summary
    pub depth_analysis: DepthAssertionSummary,

    /// Overall confidence level
    pub confidence_level: String,     // "high", "medium", "low", "suspicious"

    /// Device information
    pub device_model: String,
}

pub struct HardwareAssertionSummary {
    pub status: String,               // "pass", "fail", "unavailable"
    pub level: String,                // "secure_enclave", "unverified"
}

pub struct DepthAssertionSummary {
    pub status: String,
    pub is_real_scene: bool,
    pub depth_layers: u32,
}
```

#### File Verification Response

```typescript
// apps/web/src/lib/api.ts

export type VerificationStatus = 'verified' | 'c2pa_only' | 'no_record';

export interface FileVerificationResponse {
  data: {
    status: VerificationStatus;
    capture_id?: string;
    confidence_level?: string;
    verification_url?: string;
    manifest_info?: C2paManifestInfo;
    note?: string;
  };
  meta: {
    request_id: string;
    timestamp: string;
  };
}

export interface C2paManifestInfo {
  claim_generator: string;
  created_at: string;
  assertions: {
    hardware_attestation?: {
      status: string;
      level?: string;
    };
    depth_analysis?: {
      status: string;
      is_real_scene?: boolean;
    };
    confidence_level?: string;
  };
}
```

#### Extended Capture Response (with C2PA)

```typescript
// packages/shared/src/types/capture.ts

export interface CaptureResponse {
  data: {
    id: string;
    confidence_level: 'high' | 'medium' | 'low' | 'suspicious';
    status: 'pending' | 'processing' | 'complete' | 'failed';
    captured_at: string;
    uploaded_at: string;

    // Media URLs (presigned, 1-hour expiry)
    media_url: string;
    thumbnail_url?: string;
    depth_preview_url?: string;

    // C2PA URLs (new for Epic 5)
    c2pa_media_url?: string;        // Photo with embedded manifest
    c2pa_manifest_url?: string;     // Standalone .c2pa file

    // Evidence package
    evidence: EvidencePackage;

    // Location (coarse)
    location_coarse?: string;
  };
}
```

### APIs and Interfaces

#### POST /api/v1/verify-file

**Purpose:** Verify uploaded file against capture database and extract C2PA manifest.

**Request:**
```http
POST /api/v1/verify-file
Content-Type: multipart/form-data

--boundary
Content-Disposition: form-data; name="file"; filename="photo.jpg"
Content-Type: image/jpeg

{JPEG binary data}
--boundary--
```

**Response - Match Found (200):**
```json
{
  "data": {
    "status": "verified",
    "capture_id": "550e8400-e29b-41d4-a716-446655440000",
    "confidence_level": "high",
    "verification_url": "https://realitycam.app/verify/550e8400-e29b-41d4-a716-446655440000"
  },
  "meta": {
    "request_id": "req-xyz789",
    "timestamp": "2025-11-23T12:00:00Z"
  }
}
```

**Response - C2PA Only (200):**
```json
{
  "data": {
    "status": "c2pa_only",
    "manifest_info": {
      "claim_generator": "RealityCam/0.1.0",
      "created_at": "2025-11-23T10:30:00Z",
      "assertions": {
        "hardware_attestation": { "status": "pass", "level": "secure_enclave" },
        "depth_analysis": { "status": "pass", "is_real_scene": true },
        "confidence_level": "high"
      }
    },
    "note": "This file has Content Credentials but was not captured with RealityCam or has been modified"
  }
}
```

**Response - No Record (200):**
```json
{
  "data": {
    "status": "no_record",
    "note": "No provenance record found for this file"
  }
}
```

**Error Responses:**

| HTTP Status | Error Code | Condition |
|-------------|------------|-----------|
| 400 | `VALIDATION_ERROR` | No file uploaded or invalid format |
| 413 | `PAYLOAD_TOO_LARGE` | File > 20MB |
| 429 | `RATE_LIMITED` | Exceeded 100 verifications/hour/IP |
| 500 | `PROCESSING_FAILED` | Hash computation or C2PA parsing failed |

### Workflows and Sequencing

#### C2PA Generation Flow (Backend)

```
Evidence Processing Complete (Epic 4)
        |
        v
+-------------------+
| Load Evidence     |
| Package from DB   |
+-------------------+
        |
        v
+-------------------+
| Create C2PA       |
| Manifest Object   |
+-------------------+
        |
        +---> Add "c2pa.created" action with timestamp
        +---> Add hardware attestation assertion
        +---> Add depth analysis assertion
        +---> Add confidence level assertion
        +---> Add device model assertion
        |
        v
+-------------------+
| Load Signing Key  |
| (Ed25519)         |
+-------------------+
        |
        v
+-------------------+
| Sign Manifest     |
| (Ed25519 signature)|
+-------------------+
        |
        v
+-------------------+
| Embed in JPEG     |
| (JUMBF box)       |
+-------------------+
        |
        v
+-------------------+
| Upload to S3      |
| - c2pa.jpg        |
| - manifest.c2pa   |
+-------------------+
        |
        v
+-------------------+
| Update Capture    |
| Record with URLs  |
+-------------------+
```

#### File Verification Flow

```
User Uploads File
        |
        v
+-------------------+
| Compute SHA-256   |
| Hash of File      |
+-------------------+
        |
        v
+-------------------+
| Query captures    |
| by target_media_  |
| hash              |
+-------------------+
        |
        |---> [Match Found]
        |         |
        |         v
        |     Return "verified" with capture details
        |
        |---> [No Match]
                  |
                  v
        +-------------------+
        | Try to Extract    |
        | C2PA Manifest     |
        +-------------------+
                  |
                  |---> [Has C2PA]
                  |         |
                  |         v
                  |     Return "c2pa_only" with manifest info
                  |
                  |---> [No C2PA]
                            |
                            v
                        Return "no_record"
```

#### Verification Page Load Flow

```
User Opens /verify/{id}
        |
        v
+-------------------+
| Server Component  |
| Fetch Capture API |
+-------------------+
        |
        |---> [Not Found]
        |         |
        |         v
        |     Render 404 page
        |
        |---> [Found]
                  |
                  v
+-------------------+
| Render Page with  |
| - Confidence Hero |
| - Photo + Depth   |
| - Evidence Panel  |
| - C2PA Downloads  |
+-------------------+
        |
        v (Client)
+-------------------+
| Interactive       |
| Elements          |
| - Depth overlay   |
| - Panel expand    |
| - File upload     |
+-------------------+
```

---

## Non-Functional Requirements

### Performance

| Metric | Target | Source |
|--------|--------|--------|
| C2PA manifest generation | < 2s | Part of 5s evidence budget |
| C2PA embedding | < 1s | JUMBF insertion |
| Verification page FCP | < 1.5s | PRD: Performance targets |
| File verification hash | < 500ms | SHA-256 computation |
| File upload verification | < 3s total | Hash + DB lookup + C2PA parse |

**Implementation Requirements:**
- Pre-generate depth preview PNG during evidence processing (not on page load)
- Cache capture data at CDN edge for verification pages
- Stream file uploads, compute hash incrementally
- Use c2pa-rs async operations where available

### Security

**Key Management:**
- MVP: Ed25519 signing key stored in environment variable (base64 encoded)
- Production: AWS KMS or HashiCorp Vault for HSM-backed storage
- Key rotation: Annual (manual for MVP)
- Certificate: Self-signed for MVP, CA-issued for production

**C2PA Security:**
- Manifest signature binds evidence to photo
- Embedded manifest cannot be removed without invalidating signature
- Certificate chain embedded for offline verification

**Rate Limiting:**
- 100 file verifications/hour/IP (PRD: API Authentication Flow)
- No authentication required for verification (public)

### Reliability/Availability

**C2PA Generation:**
- If C2PA generation fails, capture remains complete (degraded functionality)
- Retry mechanism for transient S3 failures
- Log C2PA failures for investigation

**Verification Page:**
- Static generation for landing page
- Server-side rendering for capture-specific pages
- Graceful degradation if API unavailable (show cached data)

### Observability

**Logging Requirements:**

| Log Event | Level | Fields |
|-----------|-------|--------|
| C2PA manifest created | INFO | capture_id, manifest_size_bytes |
| C2PA signing complete | INFO | capture_id, key_id, signature_algorithm |
| C2PA embedding complete | INFO | capture_id, original_size, embedded_size |
| C2PA generation failed | ERROR | capture_id, error, stage |
| File verification request | INFO | file_hash, file_size, request_id |
| Verification match found | INFO | file_hash, capture_id |
| Verification no match | INFO | file_hash, has_c2pa |

**Metrics:**
- `realitycam_c2pa_generation_total` (counter): status
- `realitycam_c2pa_generation_duration_ms` (histogram)
- `realitycam_file_verifications_total` (counter): status
- `realitycam_verification_page_views` (counter): capture_id

---

## Dependencies and Integrations

### External Libraries

**Backend (Cargo.toml additions for Epic 5):**

| Crate | Version | Purpose |
|-------|---------|---------|
| `c2pa` | 0.51 | C2PA manifest generation, signing, embedding (already in Cargo.toml) |
| `image` | 0.25 | JPEG manipulation for thumbnail generation |
| `palette` | 0.7 | Color mapping for depth visualization |

**Web (package.json additions for Epic 5):**

| Package | Version | Purpose |
|---------|---------|---------|
| `react-dropzone` | ^14.0 | Drag-drop file upload |
| `@vercel/og` | ^0.6 | Dynamic OG image generation |

### Internal Dependencies

| Module | Depends On | Status |
|--------|------------|--------|
| C2PA service | Evidence package (Epic 4) | Complete |
| C2PA service | Storage service (Epic 1) | Complete |
| Verify endpoint | Captures table (Epic 1) | Complete |
| Verification page | API client (Epic 1) | Complete |
| Result screen | Capture response type (Epic 4) | Complete |

---

## Acceptance Criteria (Authoritative)

### AC-5.1: C2PA Manifest Generation
1. Backend generates C2PA manifest containing claim generator "RealityCam/0.1.0"
2. Manifest includes "c2pa.created" action with capture timestamp
3. Custom assertions include: hardware_attestation, depth_analysis, confidence_level, device_model
4. Manifest is valid per C2PA 2.0 specification (parseable by c2pa-rs reader)
5. Generation completes in < 2 seconds

### AC-5.2: C2PA Signing with Ed25519
1. Manifest signed using Ed25519 key loaded from configuration
2. Certificate chain embedded in manifest (self-signed for MVP)
3. Signature is valid and verifiable by c2pa-rs reader
4. Signing key ID logged (not key material)
5. Graceful failure if signing key unavailable (capture remains complete without C2PA)

### AC-5.3: C2PA Embedding and Storage
1. Signed manifest embedded in JPEG using JUMBF format
2. Embedded photo stored at `captures/{id}/c2pa.jpg`
3. Standalone manifest stored at `captures/{id}/manifest.c2pa`
4. Original photo preserved at `captures/{id}/original.jpg`
5. All three files accessible via presigned URLs (1-hour expiry)
6. Embedded photo remains valid JPEG viewable in any image viewer

### AC-5.4: Verification Page Summary View
1. Page at `/verify/{id}` displays confidence badge (GREEN/YELLOW/ORANGE/RED)
2. Hero section shows photo thumbnail with confidence overlay
3. Capture timestamp displayed as "Captured {date} at {time}"
4. Location shown as city-level (or "Location not provided")
5. Page loads in < 1.5s FCP
6. OG meta tags for social sharing (title, description, image)
7. 404 page for invalid capture IDs

### AC-5.5: Evidence Panel Component
1. Collapsible panel shows all evidence checks
2. Each check displays status icon: checkmark (green pass), X (red fail), dash (gray unavailable)
3. Hardware attestation shows: level, device model, verification status
4. Depth analysis shows: variance, layers, coherence, is_real_scene verdict
5. Metadata shows: timestamp validity, model verified, location status
6. "Unavailable" status explained: "This check could not be performed but is not suspicious"

### AC-5.6: File Upload Verification
1. Drag-drop zone accepts JPEG, PNG, HEIC files up to 20MB
2. Upload shows progress indicator
3. "Verified" result shows confidence badge and link to verification page
4. "C2PA only" result shows extracted manifest info
5. "No record" result explains: "No provenance record found - doesn't mean fake, just not in our system"
6. Rate limited to 100 verifications/hour/IP

### AC-5.7: File Verification Results Display
1. Verified result shows full confidence badge and "View Full Evidence" link
2. C2PA only result shows claim generator, creation date, and extracted assertions
3. No record result shows clear explanation without implying photo is fake
4. All results show computed file hash for transparency
5. Loading state shows "Checking..." with spinner

### AC-5.8: Capture Result Screen (Mobile)
1. Result screen shows capture thumbnail with confidence badge
2. Verification URL displayed prominently with "Copy" button
3. "Share" button opens native share sheet with verification URL
4. Evidence summary shows: hardware attestation status, depth analysis status
5. "View Details" navigates to web verification page
6. Screen accessible from History tab for past captures

---

## Traceability Mapping

| AC | FR(s) | Spec Section | Component(s) | Test Approach |
|----|-------|--------------|--------------|---------------|
| AC-5.1 | FR27 | Services: c2pa.rs | `services/c2pa.rs` | Unit test manifest structure |
| AC-5.2 | FR28 | Services: c2pa.rs | `services/c2pa.rs` | Unit test signing, verification |
| AC-5.3 | FR29, FR30 | Services: c2pa.rs, storage.rs | `services/c2pa.rs`, `storage.rs` | Integration test embedding, S3 |
| AC-5.4 | FR31, FR32 | Web: verify page | `app/verify/[id]/page.tsx` | E2E test page render |
| AC-5.5 | FR33, FR34, FR35 | Web: evidence panel | `components/Evidence/` | Component tests |
| AC-5.6 | FR36, FR37 | Web: file upload | `components/Upload/`, `routes/verify.rs` | Integration test upload flow |
| AC-5.7 | FR38, FR39, FR40 | Web: verification results | `components/Verification/` | Component tests |
| AC-5.8 | FR31 (mobile) | Mobile: result screen | `app/result.tsx` | E2E test on device |

---

## Risks, Assumptions, Open Questions

### Risks

| ID | Risk | Impact | Mitigation |
|----|------|--------|------------|
| R1 | c2pa-rs API changes | Integration breaks | Pin to 0.51.x, test on upgrade |
| R2 | Ed25519 key exposure | Security breach | ENV var for MVP, KMS for production |
| R3 | Large embedded photos | Slow downloads | Generate thumbnail, lazy load full |
| R4 | C2PA spec evolution | Manifest incompatibility | Follow CAI updates, versioned assertions |
| R5 | File verification abuse | Resource exhaustion | Rate limiting, file size limits |

### Assumptions

| ID | Assumption | Validation |
|----|------------|------------|
| A1 | c2pa-rs 0.51 supports Ed25519 signing | Verify in implementation |
| A2 | JUMBF embedding doesn't corrupt JPEG | Test with various JPEG sources |
| A3 | 20MB file upload limit sufficient | Typical iPhone photo 3-5MB |
| A4 | Self-signed cert acceptable for MVP | Document limitation, plan CA |
| A5 | Hash lookup by target_media_hash is unique | Enforced by DB constraint |

### Open Questions

| ID | Question | Owner | Resolution Path |
|----|----------|-------|-----------------|
| Q1 | Should C2PA manifest include full evidence or summary? | PM | Recommend summary (less data exposure) |
| Q2 | Certificate chain format for self-signed MVP? | Dev | Use c2pa-rs self-signing utilities |
| Q3 | OG image generation approach? | Dev | Use @vercel/og or pre-generate |
| Q4 | Depth preview color scheme? | UX | Use viridis colormap (accessible) |

---

## Test Strategy Summary

### Unit Tests

**Backend (Rust):**
- `c2pa.rs`: Test manifest creation, signing, embedding with test key
- `routes/verify.rs`: Test hash lookup, C2PA extraction logic

**Web (TypeScript/Jest):**
- `EvidencePanel`: Test expand/collapse, status display
- `FileDropzone`: Test file validation, upload states
- `ConfidenceSummary`: Test badge colors for each level

### Integration Tests

**Backend (testcontainers):**
- Full C2PA generation flow with sample evidence
- File verification with matched and unmatched hashes
- C2PA extraction from embedded photo

**Web (Playwright):**
- Verification page load and interaction
- File upload flow end-to-end
- Mobile responsive layout

**Mobile (Maestro):**
- Result screen display after upload
- Share functionality
- Navigation to web verification

### Test Data Requirements

| Data | Source | Purpose |
|------|--------|---------|
| Test Ed25519 key pair | Generated | C2PA signing tests |
| Sample evidence package | Fixtures | Manifest generation |
| JPEG with embedded C2PA | Generated | Extraction tests |
| Various JPEG samples | Stock photos | Embedding compatibility |
| Large file (>20MB) | Generated | Size limit testing |

### Coverage Targets

- Unit test coverage: > 80% for C2PA service
- All acceptance criteria have at least one automated test
- E2E test for critical path: upload -> process -> verify page
- Visual regression tests for verification page
