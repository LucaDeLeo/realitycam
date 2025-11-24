# RealityCam Test Design Document

**Version:** 1.0
**Date:** 2025-11-24
**Author:** Murat (Master Test Architect)
**Status:** Draft
**Mode:** System-Level (Phase 3 Testability Review)

---

## 1. Executive Summary

This document defines the comprehensive test strategy for RealityCam, a photo verification platform using hardware attestation (DCAppAttest) and LiDAR depth analysis to prove photo authenticity. The test design follows risk-based testing principles, prioritizing security-critical and core differentiator components.

**Key Testing Challenges:**
- iOS-only with hardware dependencies (LiDAR, Secure Enclave)
- DCAppAttest cannot be mocked in simulator
- Cryptographic verification chains require real attestation data
- Depth analysis thresholds need validation against real-world captures

**Recommended Test Distribution:**
- Unit Tests: 80% (fast feedback, high coverage)
- Integration Tests: 15% (component boundaries, data flows)
- E2E Tests: 5% (critical user journeys, high-value scenarios)

---

## 2. System Under Test

### 2.1 Architecture Overview

| Component | Technology | Test Framework |
|-----------|------------|----------------|
| Mobile App | Expo SDK 54, React Native 0.81 | Jest, Maestro |
| Backend | Rust, Axum 0.8, SQLx 0.8 | cargo test, testcontainers |
| Web App | Next.js 16, React 19 | Jest, Playwright |
| Database | PostgreSQL 16 | testcontainers |
| Storage | S3 (LocalStack dev) | LocalStack |

### 2.2 Critical Business Flows

1. **Device Registration**: Device detection → Key generation → DCAppAttest → Backend verification
2. **Photo Capture**: Camera + LiDAR → Per-capture assertion → Local processing
3. **Upload & Processing**: Queue management → Evidence pipeline → Confidence scoring
4. **Verification**: C2PA manifest → Public verification page → File upload check

### 2.3 Functional Requirements Coverage

| Epic | FRs | Test Priority |
|------|-----|---------------|
| Epic 2: Device Registration | FR1-FR5, FR41-FR43 | Critical |
| Epic 3: Photo Capture | FR6-FR13 | High |
| Epic 4: Upload & Processing | FR14-FR26, FR44-FR46 | Critical |
| Epic 5: C2PA & Verification | FR27-FR40 | High |

---

## 3. Risk-Based Test Prioritization

### 3.1 Risk Matrix

| Risk ID | Area | Impact | Likelihood | Detection | Score | Priority |
|---------|------|--------|------------|-----------|-------|----------|
| R-001 | DCAppAttest Verification | 10 | 6 | 8 | 480 | Critical |
| R-002 | Per-Capture Assertion Binding | 10 | 5 | 9 | 450 | Critical |
| R-003 | Depth Analysis Accuracy | 9 | 7 | 7 | 441 | Critical |
| R-004 | Upload Queue Reliability | 7 | 6 | 6 | 252 | High |
| R-005 | C2PA Manifest Validity | 8 | 4 | 7 | 224 | High |
| R-006 | Confidence Calculation | 7 | 5 | 5 | 175 | High |
| R-007 | Timestamp Validation | 6 | 4 | 4 | 96 | Medium |
| R-008 | GPS Privacy Coarsening | 5 | 3 | 5 | 75 | Medium |
| R-009 | Rate Limiting | 4 | 4 | 3 | 48 | Low |

### 3.2 Testing Investment Allocation

```
Critical (Score >400): 50% of test effort
  - Device attestation verification chain
  - Per-capture assertion counter validation
  - Depth analysis algorithms (variance, layers, coherence)

High (Score 150-400): 30% of test effort
  - Upload queue retry logic and persistence
  - C2PA manifest generation and signing
  - Confidence level state machine

Medium (Score 50-150): 15% of test effort
  - Timestamp validation windows
  - Model whitelist verification
  - Location privacy controls

Low (Score <50): 5% of test effort
  - Rate limiting behavior
  - Edge cases and boundary conditions
```

---

## 4. Test Scenarios by Domain

### 4.1 Security & Attestation (Critical)

#### TS-SEC-001: DCAppAttest Verification Chain

**Objective:** Verify backend correctly validates Apple DCAppAttest attestation objects

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Submit valid attestation object | CBOR decoded successfully |
| 2 | Verify certificate chain | Chain roots to Apple App Attest CA |
| 3 | Verify App ID hash | Matches Team ID + Bundle ID |
| 4 | Verify challenge nonce | Matches server-issued challenge |
| 5 | Extract public key | Key stored for future signature verification |
| 6 | Set attestation level | attestation_level = "secure_enclave" |

**Negative Tests:**
- Malformed CBOR → 401 ATTESTATION_FAILED
- Wrong App ID hash → 401 ATTESTATION_FAILED
- Expired challenge → 401 ATTESTATION_FAILED
- Invalid certificate chain → attestation_level = "unverified"

**Test Data:** Valid attestation object (captured from real device, key material redacted)

---

#### TS-SEC-002: Device Signature Authentication

**Objective:** Verify middleware correctly validates Ed25519 signatures on every request

| Test Case | Input | Expected |
|-----------|-------|----------|
| Valid signature | Correct timestamp, body hash, signature | 200 OK, request proceeds |
| Missing X-Device-Id | No header | 401 DEVICE_NOT_FOUND |
| Unknown device ID | Non-existent UUID | 401 DEVICE_NOT_FOUND |
| Expired timestamp | >5 minutes old | 401 TIMESTAMP_EXPIRED |
| Future timestamp | >5 minutes ahead | 401 TIMESTAMP_EXPIRED |
| Invalid signature | Wrong key or tampered body | 401 SIGNATURE_INVALID |
| Empty body | GET request | Signature over timestamp only |

**Edge Cases:**
- Clock drift at boundary (4:59 vs 5:01)
- Malformed base64 signature
- Body hash mismatch

---

#### TS-SEC-003: Per-Capture Assertion Counter

**Objective:** Prevent replay attacks by enforcing monotonic assertion counter

| Test Case | Counter State | Expected |
|-----------|---------------|----------|
| First assertion | device.counter=0, assertion.counter=1 | Accept, update to 1 |
| Sequential | device.counter=5, assertion.counter=6 | Accept, update to 6 |
| Skip allowed | device.counter=5, assertion.counter=10 | Accept, update to 10 |
| Replay attack | device.counter=5, assertion.counter=5 | Reject (same) |
| Rollback attack | device.counter=5, assertion.counter=3 | Reject (lower) |

**Security Note:** Counter update must be atomic with capture creation to prevent race conditions.

---

#### TS-SEC-004: Encrypted Offline Storage

**Objective:** Verify captures are encrypted at rest when device is offline

| Test Case | Condition | Expected |
|-----------|-----------|----------|
| Encrypt capture | Device offline, capture taken | Data encrypted with SE-backed key |
| Persist across restart | App killed and reopened | Encrypted data still present |
| Decrypt on upload | Connectivity restored | Decryption succeeds, upload proceeds |
| Key non-extractable | Attempt to read key | Key remains in Secure Enclave |

**Platform Limitation:** Can only be tested on physical device with Secure Enclave.

---

### 4.2 Depth Analysis (Core Differentiator)

#### TS-DEPTH-001: Real Scene Detection (True Positive)

**Objective:** Verify genuine 3D scenes pass depth analysis

| Metric | Threshold | Expected for Real Scene |
|--------|-----------|------------------------|
| depth_variance | > 0.5 | 1.5 - 4.0 typical |
| depth_layers | >= 3 | 4-8 typical |
| edge_coherence | > 0.7 | 0.75 - 0.95 typical |
| is_likely_real_scene | - | true |

**Test Data Sets:**
- Indoor office (desk, chair, monitor, person)
- Outdoor street (buildings, cars, pedestrians)
- Portrait (person at 1m, background at 3m)
- Nature scene (trees, varying depths)

---

#### TS-DEPTH-002: Flat Image Detection (True Negative)

**Objective:** Verify flat surfaces (screens, prints) fail depth analysis

| Scenario | Expected Variance | Expected Layers | Expected Coherence |
|----------|-------------------|-----------------|-------------------|
| Phone screen | < 0.3 | 1-2 | < 0.5 |
| Monitor display | < 0.3 | 1-2 | < 0.5 |
| Printed photo | < 0.2 | 1 | < 0.4 |
| Flat wall | < 0.1 | 1 | N/A |

**is_likely_real_scene = false** for all flat scenarios.

---

#### TS-DEPTH-003: Edge Coherence Algorithm

**Objective:** Verify depth edges correlate with RGB edges in real scenes

| Test Case | RGB Edges | Depth Edges | Expected Coherence |
|-----------|-----------|-------------|-------------------|
| Real scene | Object boundaries | Depth discontinuities | > 0.7 |
| Flat screen | Content edges | No depth variation | < 0.5 |
| Fabricated depth | Photo edges | Random depth | < 0.4 |

**Algorithm:** Sobel edge detection on both RGB and depth, compute correlation coefficient.

---

#### TS-DEPTH-004: Threshold Boundary Testing

**Objective:** Verify exact threshold behavior

| Test | Variance | Layers | Coherence | Expected Result |
|------|----------|--------|-----------|-----------------|
| All pass | 0.51 | 3 | 0.71 | is_likely_real_scene=true |
| Variance fail | 0.49 | 3 | 0.71 | is_likely_real_scene=false |
| Layers fail | 0.51 | 2 | 0.71 | is_likely_real_scene=false |
| Coherence fail | 0.51 | 3 | 0.69 | is_likely_real_scene=false |
| Multiple fail | 0.49 | 2 | 0.69 | is_likely_real_scene=false |

**Note:** All three criteria must pass for is_likely_real_scene=true.

---

#### TS-DEPTH-005: Depth Map Format Validation

**Objective:** Verify robust handling of depth map input

| Test Case | Input | Expected |
|-----------|-------|----------|
| Valid gzip | Compressed Float32[256×192] | Decompression succeeds |
| Corrupted gzip | Invalid bytes | Error: DEPTH_DECODE_FAILED |
| Wrong dimensions | Float32[128×96] | Error: DIMENSION_MISMATCH |
| NaN values | Array with NaN | Error: INVALID_DEPTH_VALUES |
| Inf values | Array with Infinity | Error: INVALID_DEPTH_VALUES |
| Out of range | Values > 10m or < 0m | Warning logged, processed anyway |

---

### 4.3 Upload Pipeline & Evidence Processing

#### TS-UPLOAD-001: Multipart Upload Happy Path

**Objective:** Verify complete upload flow works correctly

```
Request:
  POST /api/v1/captures
  Content-Type: multipart/form-data
  X-Device-Id: {uuid}
  X-Device-Timestamp: {unix_ms}
  X-Device-Signature: {base64}

  Parts:
    - photo: image/jpeg (~3MB)
    - depth_map: application/gzip (~1MB)
    - metadata: application/json

Expected Response (202 Accepted):
  {
    "data": {
      "capture_id": "{uuid}",
      "status": "processing",
      "verification_url": "https://realitycam.app/verify/{uuid}"
    }
  }

Response Time: < 2 seconds
```

**Verification Points:**
- [ ] Photo streamed to S3 (not buffered)
- [ ] Depth map streamed to S3
- [ ] Capture record created in database
- [ ] Background task spawned for processing

---

#### TS-UPLOAD-002: Upload Queue Retry Logic

**Objective:** Verify exponential backoff and persistence

| Attempt | Delay | Expected Behavior |
|---------|-------|-------------------|
| 1 | 0ms | Immediate attempt |
| 2 | 1000ms | Wait 1 second |
| 3 | 2000ms | Wait 2 seconds |
| 4 | 4000ms | Wait 4 seconds |
| 5 | 8000ms | Wait 8 seconds |
| 6-10 | 300000ms | Wait 5 minutes (max) |
| 11+ | - | Mark permanently_failed |

**Persistence Test:**
1. Start upload, kill app mid-transfer
2. Reopen app
3. Verify upload resumes from queue

---

#### TS-UPLOAD-003: Offline→Online Transition

**Objective:** Verify automatic upload when connectivity returns

| Step | State | Expected |
|------|-------|----------|
| 1 | Enable airplane mode | Device offline |
| 2 | Take 3 captures | All stored locally encrypted |
| 3 | Disable airplane mode | Connectivity restored |
| 4 | Wait | Captures upload in chronological order |
| 5 | Verify | All 3 reach "complete" status |

---

#### TS-EVIDENCE-001: Confidence Level Calculation

**Objective:** Verify confidence matrix logic

| Hardware Status | Depth is_real | Expected Confidence |
|-----------------|---------------|---------------------|
| pass | true | HIGH (green) |
| pass | false | MEDIUM (yellow) |
| unavailable | true | MEDIUM (yellow) |
| unavailable | false | LOW (orange) |
| fail | true | SUSPICIOUS (red) |
| fail | false | SUSPICIOUS (red) |

**Implementation Note:** Hardware "fail" always results in SUSPICIOUS because it indicates active tampering or compromised device.

---

#### TS-EVIDENCE-002: Metadata Validation

**Timestamp Validation:**

| EXIF Time | Upload Time | Delta | Expected |
|-----------|-------------|-------|----------|
| 10:00:00 | 10:10:00 | 10min | timestamp_valid=true |
| 10:00:00 | 10:15:00 | 15min | timestamp_valid=true (boundary) |
| 10:00:00 | 10:16:00 | 16min | timestamp_valid=false |
| null | 10:00:00 | - | timestamp_valid=false |

**Model Whitelist:**

| Model String | Expected |
|--------------|----------|
| "iPhone 12 Pro" | model_verified=true |
| "iPhone 12 Pro Max" | model_verified=true |
| "iPhone 13 Pro" | model_verified=true |
| "iPhone 13 Pro Max" | model_verified=true |
| "iPhone 14 Pro" | model_verified=true |
| "iPhone 14 Pro Max" | model_verified=true |
| "iPhone 15 Pro" | model_verified=true |
| "iPhone 15 Pro Max" | model_verified=true |
| "iPhone 16 Pro" | model_verified=true |
| "iPhone 16 Pro Max" | model_verified=true |
| "iPhone 17 Pro" | model_verified=true |
| "iPhone 17 Pro Max" | model_verified=true |
| "iPhone 15" | model_verified=false |
| "iPad Pro" | model_verified=false |

---

#### TS-EVIDENCE-003: Rate Limiting

**Objective:** Verify 10 captures/hour/device limit

| Request | Expected |
|---------|----------|
| 1-10 | 202 Accepted |
| 11 | 429 Too Many Requests |
| After 1 hour | Counter reset, 202 Accepted |

**Response Headers for 429:**
```
Retry-After: {seconds_until_reset}
```

---

### 4.4 C2PA & Verification Interface

#### TS-C2PA-001: Manifest Generation

**Objective:** Verify C2PA manifest structure and content

| Field | Expected Value |
|-------|----------------|
| claim_generator | "RealityCam/0.1.0" |
| action | "c2pa.created" |
| action.when | Capture timestamp (ISO 8601) |
| action.software_agent | "RealityCam iOS/1.0.0" |
| assertions.hardware_attestation | {status, level} |
| assertions.depth_analysis | {status, is_real_scene, layers} |
| assertions.confidence_level | "high"/"medium"/"low"/"suspicious" |
| assertions.device_model | e.g., "iPhone 15 Pro" |

**Validation:** Manifest parseable by c2pa-rs ManifestStore::from_bytes()

---

#### TS-C2PA-002: Ed25519 Signing

**Objective:** Verify manifest signature is valid

| Test | Expected |
|------|----------|
| Sign with valid key | Signature created |
| Verify signature | c2pa-rs verification passes |
| Certificate chain | Embedded in manifest |
| Key unavailable | Graceful failure, capture remains complete |

---

#### TS-C2PA-003: JUMBF Embedding

**Objective:** Verify embedded photo is valid

| Test | Expected |
|------|----------|
| Embed manifest | JPEG with JUMBF box |
| View embedded photo | Opens in any image viewer |
| Extract manifest | c2pa-rs extracts successfully |
| Original preserved | Separate original.jpg in S3 |
| Size overhead | < 100KB increase |

---

#### TS-VERIFY-001: File Hash Lookup

**Objective:** Verify file verification endpoint

| Scenario | Expected Status | Response |
|----------|-----------------|----------|
| Hash matches capture | "verified" | capture_id, confidence, verification_url |
| No match, has C2PA | "c2pa_only" | manifest_info extracted |
| No match, no C2PA | "no_record" | Explanatory note |

---

#### TS-VERIFY-002: Verification Page Rendering

**Objective:** Verify page content and performance

| Element | Expected |
|---------|----------|
| Confidence badge | Color matches level (GREEN/YELLOW/ORANGE/RED) |
| Photo thumbnail | Displayed with optional depth overlay |
| Timestamp | Formatted: "Captured {date} at {time}" |
| Location | City-level or "Location not provided" |
| Evidence panel | Collapsible, shows all checks |
| C2PA downloads | Functional presigned URLs |
| OG meta tags | Title, description, image for sharing |
| 404 handling | Invalid capture ID shows 404 page |
| Performance | FCP < 1.5s |

---

#### TS-VERIFY-003: File Upload UX

**Objective:** Verify drag-drop verification flow

| Test | Input | Expected |
|------|-------|----------|
| Valid JPEG | 3MB photo | Upload succeeds, result displayed |
| Valid PNG | 2MB image | Upload succeeds |
| Valid HEIC | 4MB photo | Upload succeeds |
| Too large | 25MB file | Error: "File too large (max 20MB)" |
| Wrong type | PDF document | Error: "Invalid file type" |
| Rate limited | 101st request | 429 with friendly message |

---

### 4.5 Mobile-Specific Scenarios

#### TS-MOBILE-001: Capture Flow

**Objective:** Verify end-to-end capture on device

| Step | Action | Verification |
|------|--------|--------------|
| 1 | Open app | Registration screen or capture tab |
| 2 | Allow camera permission | Camera preview visible |
| 3 | Verify depth overlay | Heatmap displayed at ≥30 FPS |
| 4 | Tap capture button | Haptic feedback |
| 5 | Wait for processing | < 2 seconds |
| 6 | Preview screen | Photo + depth toggle + metadata |
| 7 | Tap upload | Progress indicator |
| 8 | Result screen | Confidence badge, verification URL |

---

#### TS-MOBILE-002: Result Screen

**Objective:** Verify post-upload UI

| Element | Expected |
|---------|----------|
| Thumbnail | Captured photo displayed |
| Confidence badge | Matches calculated level |
| Verification URL | Displayed prominently |
| Copy button | Copies URL to clipboard |
| Share button | Opens native share sheet |
| Evidence summary | Hardware + depth status |

---

## 5. Non-Functional Requirements Testing

### 5.1 Performance Requirements

| Metric | Target | Test Method |
|--------|--------|-------------|
| Upload time (10 MB/s) | < 10s | Measure with 5MB payload |
| Evidence processing | < 5s | Timer in integration test |
| Verification page FCP | < 1.5s | Lighthouse CI |
| Verification page LCP | < 2.5s | Lighthouse CI |
| Depth analysis | < 2s | Unit test timer |
| C2PA generation | < 2s | Unit test timer |
| Hash computation | < 500ms | Unit test timer |

### 5.2 Security Requirements

| Requirement | Test Method |
|-------------|-------------|
| TLS 1.3 only | Attempt TLS 1.2 connection, verify failure |
| Device signature required | Request without headers, verify 401 |
| Replay protection | Submit same assertion twice, verify rejection |
| Encrypted offline storage | Inspect storage without key, verify unreadable |
| Rate limiting | Exceed limit, verify 429 |
| GPS coarsening | Verify public API returns city-level only |

### 5.3 Reliability Requirements

| Scenario | Expected Behavior |
|----------|-------------------|
| S3 upload failure | Return 500, mobile retries |
| Evidence processing failure | Capture status="failed", logged |
| Offline captures | Encrypted, queued, auto-upload on reconnect |
| App restart with queue | Queue survives, uploads resume |
| 10 failed upload attempts | Mark permanently_failed |

---

## 6. Test Data Requirements

### 6.1 Fixtures

| Fixture | Format | Source | Purpose |
|---------|--------|--------|---------|
| real_scene_depth_office.gz | gzip(Float32[256×192]) | Capture from device | True positive |
| real_scene_depth_outdoor.gz | gzip(Float32[256×192]) | Capture from device | True positive |
| real_scene_depth_portrait.gz | gzip(Float32[256×192]) | Capture from device | True positive |
| flat_screen_depth.gz | gzip(Float32[256×192]) | Capture from device | True negative |
| flat_print_depth.gz | gzip(Float32[256×192]) | Capture from device | True negative |
| uniform_depth.gz | gzip(Float32[256×192]) | Synthetic | Edge case |
| valid_attestation.cbor | CBOR bytes | Real device (redacted) | Attestation tests |
| invalid_attestation.cbor | CBOR bytes | Synthetic | Error handling |
| photo_with_exif.jpg | JPEG | Stock photo | Metadata tests |
| photo_no_exif.jpg | JPEG | Stripped photo | Missing metadata |
| ed25519_test_key.pem | PEM | Generated | C2PA signing |
| apple_ca_root.der | DER | Apple | Chain verification |

### 6.2 Test Devices

| Device | iOS Version | Purpose |
|--------|-------------|---------|
| iPhone 17 Pro | iOS 18.x | Primary test device |
| iPhone 15 Pro | iOS 17.x | Secondary device |
| iPhone 12 Pro | iOS 17.x | Minimum supported |
| iPhone 15 (non-Pro) | iOS 17.x | LiDAR unavailable test |
| iPhone Simulator | - | UI tests only (no LiDAR) |

---

## 7. Test Environment

### 7.1 Local Development

```bash
# Start infrastructure
docker-compose -f infrastructure/docker-compose.yml up -d

# Verify services
# PostgreSQL: localhost:5432
# LocalStack S3: localhost:4566

# Backend
cd backend && cargo test

# Mobile (simulator - limited tests)
cd apps/mobile && pnpm test

# Web
cd apps/web && pnpm test
```

### 7.2 CI Pipeline

| Stage | Tests | Trigger |
|-------|-------|---------|
| Unit | All unit tests | Every commit |
| Integration | Backend + testcontainers | PR merge |
| E2E Web | Playwright | PR merge |
| E2E Mobile | Maestro (scheduled) | Nightly |
| Device | Real device tests | Manual/Release |

---

## 8. Coverage Targets

| Component | Unit | Integration | E2E |
|-----------|------|-------------|-----|
| backend/src/services/attestation.rs | 95% | 2 tests | - |
| backend/src/services/evidence/depth.rs | 95% | 2 tests | - |
| backend/src/services/evidence/pipeline.rs | 90% | 3 tests | - |
| backend/src/services/c2pa.rs | 90% | 2 tests | - |
| backend/src/middleware/device_auth.rs | 95% | 2 tests | - |
| backend/src/routes/captures.rs | 85% | 3 tests | - |
| backend/src/routes/verify.rs | 85% | 2 tests | - |
| apps/mobile/hooks/useUploadQueue | 90% | 1 test | 2 flows |
| apps/mobile/services/OfflineStorage | 85% | 1 test | 1 flow |
| apps/mobile/store/captureStore | 85% | - | - |
| apps/web/components/Evidence/* | 80% | - | 2 flows |
| apps/web/components/Upload/* | 80% | - | 1 flow |
| apps/web/app/verify/[id] | 75% | - | 2 flows |

**Overall Target:** >80% backend, >75% frontend

---

## 9. Testability Gaps & Recommendations

### 9.1 Identified Gaps

| Gap | Impact | Recommendation |
|-----|--------|----------------|
| LiDAR module not unit-testable | Cannot test depth capture logic | Create mock interface, record fixtures |
| DCAppAttest device-only | No CI for attestation flow | Device test suite, manual verification |
| Secure Enclave device-only | No CI for encryption | Device test suite, separate from unit |
| ARKit depth requires device | Cannot generate test data in CI | Pre-capture fixtures from real device |
| Clock drift testing | Hard to simulate | Inject time source interface |

### 9.2 Recommended Actions

1. **Create LiDAR mock interface** (`useLiDARMock`) for unit tests
2. **Record depth map fixtures** from real captures for CI
3. **Separate device test suite** in Maestro for hardware-dependent tests
4. **Add time injection** to timestamp validation for boundary testing
5. **Document manual test procedures** for DCAppAttest verification

---

## 10. Traceability Matrix

| AC ID | FR(s) | Test Scenario(s) | Test Type |
|-------|-------|------------------|-----------|
| AC-2.1 | FR1 | TS-SEC-001 | Integration |
| AC-2.2 | FR2 | TS-SEC-004 | Device |
| AC-2.3 | FR3 | TS-SEC-001 | Integration |
| AC-2.4 | FR4 | TS-SEC-001 | Integration |
| AC-2.5 | FR5 | TS-SEC-001, TS-EVIDENCE-001 | Unit, Integration |
| AC-2.7 | FR41 | TS-SEC-002, TS-SEC-003 | Unit, Integration |
| AC-3.1-3.4 | FR6-FR8 | TS-MOBILE-001 | E2E |
| AC-3.5 | FR9 | TS-EVIDENCE-002 | Unit |
| AC-3.6 | FR10 | TS-SEC-003 | Unit, Integration |
| AC-3.7-3.9 | FR11-FR13 | TS-DEPTH-005 | Unit |
| AC-4.1 | FR14-FR15 | TS-UPLOAD-001 | Integration |
| AC-4.2 | FR16, FR19 | TS-UPLOAD-002 | Unit, E2E |
| AC-4.3 | FR17-FR18 | TS-UPLOAD-003 | E2E |
| AC-4.4 | FR20 | TS-SEC-003 | Unit, Integration |
| AC-4.5 | FR21-FR22 | TS-DEPTH-001-005 | Unit, Integration |
| AC-4.6 | FR23-FR24 | TS-EVIDENCE-002 | Unit |
| AC-4.7 | FR25-FR26 | TS-EVIDENCE-001 | Unit, Integration |
| AC-4.8 | FR44-FR46 | TS-EVIDENCE-002 | Unit |
| AC-5.1 | FR27 | TS-C2PA-001 | Unit |
| AC-5.2 | FR28 | TS-C2PA-002 | Unit |
| AC-5.3 | FR29-FR30 | TS-C2PA-003 | Integration |
| AC-5.4-5.5 | FR31-FR35 | TS-VERIFY-002, TS-VERIFY-003 | Component, E2E |
| AC-5.6-5.7 | FR36-FR40 | TS-VERIFY-001, TS-VERIFY-003 | Integration, E2E |
| AC-5.8 | FR31 | TS-MOBILE-002 | E2E |

---

## 11. Appendix

### A. Test Scenario Quick Reference

| ID | Domain | Priority | Type |
|----|--------|----------|------|
| TS-SEC-001 | Attestation | Critical | Integration |
| TS-SEC-002 | Auth | Critical | Unit |
| TS-SEC-003 | Counter | Critical | Unit |
| TS-SEC-004 | Encryption | Critical | Device |
| TS-DEPTH-001 | Depth | Critical | Unit |
| TS-DEPTH-002 | Depth | Critical | Unit |
| TS-DEPTH-003 | Depth | High | Unit |
| TS-DEPTH-004 | Depth | High | Unit |
| TS-DEPTH-005 | Depth | High | Unit |
| TS-UPLOAD-001 | Upload | High | Integration |
| TS-UPLOAD-002 | Upload | High | Unit |
| TS-UPLOAD-003 | Upload | High | E2E |
| TS-EVIDENCE-001 | Evidence | High | Unit |
| TS-EVIDENCE-002 | Evidence | Medium | Unit |
| TS-EVIDENCE-003 | Evidence | Medium | Integration |
| TS-C2PA-001 | C2PA | High | Unit |
| TS-C2PA-002 | C2PA | High | Unit |
| TS-C2PA-003 | C2PA | High | Integration |
| TS-VERIFY-001 | Verify | High | Integration |
| TS-VERIFY-002 | Verify | High | E2E |
| TS-VERIFY-003 | Verify | Medium | E2E |
| TS-MOBILE-001 | Mobile | High | E2E |
| TS-MOBILE-002 | Mobile | Medium | E2E |

### B. Commands Reference

```bash
# Run all backend tests
cd backend && cargo test

# Run backend tests with coverage
cd backend && cargo tarpaulin --out Html

# Run mobile unit tests
cd apps/mobile && pnpm test

# Run mobile E2E (requires device)
cd apps/mobile && maestro test .maestro/

# Run web unit tests
cd apps/web && pnpm test

# Run web E2E
cd apps/web && pnpm test:e2e

# Run web E2E with UI
cd apps/web && pnpm test:e2e --ui
```

---

*Document generated by BMAD Test Design Workflow*
*RealityCam MVP - System-Level Test Design*
