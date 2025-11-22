# RealityCam ATDD Roadmap

**Author:** Luca
**Date:** 2025-11-22
**Phase:** 3 (Implementation Ready)
**Approach:** Tests FIRST, Implementation FOLLOWS

---

## Executive Summary

This document maps Acceptance Criteria to ATDD tests, stories, and implementation effort for RealityCam's core P0 user journey:

```
Device registers -> User captures photo -> Upload to backend -> Evidence generated -> User verifies
```

**Total Tests Generated:** 65 acceptance tests across 6 test files
**Critical Path Coverage:** 100% of P0 stories covered
**Implementation Estimate:** 15-20 developer days for P0

---

## Test File Summary

| File | Stories Covered | Test Count | Priority |
|------|-----------------|------------|----------|
| `tests/integration/device-registration.spec.ts` | 2.4, 2.5, 2.6 | 10 | P0 |
| `tests/integration/capture-upload.spec.ts` | 4.1 | 12 | P0 |
| `tests/integration/evidence-generation.spec.ts` | 4.4, 4.5, 4.6, 4.7 | 18 | P0 |
| `apps/web/e2e/verification-page.spec.ts` | 5.4 | 15 | P0 |
| `apps/web/e2e/evidence-panel.spec.ts` | 5.5 | 10 | P0 |
| `tests/support/fixtures/atdd-test-data.ts` | All | (fixtures) | P0 |

---

## P0 Critical Path: Test -> Story -> Implementation Mapping

### 1. Device Registration & Attestation (Epic 2)

| Test Case ID | Test Description | Story | AC | Priority | Impl Effort |
|--------------|------------------|-------|-----|----------|-------------|
| `DEV-001` | Device registers with valid Secure Enclave attestation | 2.4 | AC-2.4.1 | P0 | 2d |
| `DEV-002` | Non-Pro device registers without LiDAR capability | 2.4 | AC-2.4.2 | P0 | 0.5d |
| `DEV-003` | Duplicate registration returns existing device | 2.4 | AC-2.4.3 | P0 | 0.5d |
| `DEV-004` | Invalid attestation certificate chain is rejected | 2.4 | AC-2.4.4 | P0 | 1d |
| `DEV-005` | Missing required fields return validation error | 2.4 | AC-2.4.5 | P0 | 0.5d |
| `DEV-006` | Expired attestation timestamp is rejected | 2.4 | AC-2.4.6 | P1 | 0.5d |
| `DEV-007` | Backend correctly parses attestation object structure | 2.5 | AC-2.5.1 | P0 | 1d |
| `DEV-008` | Request without device signature is rejected | 2.6 | AC-2.6.1 | P0 | 1d |
| `DEV-009` | Request with expired timestamp is rejected | 2.6 | AC-2.6.2 | P0 | 0.5d |

**Subtotal Epic 2:** 7.5 developer days

**Dependencies:**
- Database schema (Story 1.2) must be implemented first
- API skeleton (Story 1.3) must be running

**Risk Areas:**
- DCAppAttest mock vs. real attestation: Mock flow works, but real Apple verification needs staging device
- Certificate chain parsing: `x509-parser` crate complexity

---

### 2. Capture Upload (Epic 4.1)

| Test Case ID | Test Description | Story | AC | Priority | Impl Effort |
|--------------|------------------|-------|-----|----------|-------------|
| `UPL-001` | Device uploads capture with photo, depth map, and metadata | 4.1 | AC-4.1.1 | P0 | 2d |
| `UPL-002` | Capture without GPS is accepted with location_opted_out flag | 4.1 | AC-4.1.2 | P0 | 0.5d |
| `UPL-003` | Upload with real scene depth map is accepted | 4.1 | AC-4.1.3 | P0 | 0.5d |
| `UPL-004` | Upload with flat depth map is accepted for processing | 4.1 | AC-4.1.4 | P0 | 0.5d |
| `UPL-005` | Missing photo part is rejected with validation error | 4.1 | AC-4.1.5 | P0 | 0.5d |
| `UPL-006` | Missing depth map is rejected with validation error | 4.1 | AC-4.1.6 | P0 | 0.5d |
| `UPL-007` | Invalid device signature is rejected | 4.1 | AC-4.1.7 | P0 | 0.5d |
| `UPL-008` | Unknown device ID is rejected | 4.1 | AC-4.1.8 | P0 | 0.5d |
| `UPL-009` | Files are stored in S3 after successful upload | 4.1 | AC-4.1.9 | P0 | 1d |
| `UPL-010` | Database record created with processing status | 4.1 | AC-4.1.10 | P0 | 0.5d |
| `UPL-011` | Handles typical photo size upload (3MB) | 4.1 | Perf | P1 | 0.5d |

**Subtotal Story 4.1:** 7.5 developer days

**Dependencies:**
- Device registration (Story 2.4) must pass first
- S3 / LocalStack must be configured
- Device auth middleware (Story 2.6) must be implemented

**Risk Areas:**
- Multipart parsing in Axum: `axum::extract::Multipart` edge cases
- S3 presigned URL generation: AWS SDK configuration

---

### 3. Evidence Generation Pipeline (Epic 4.4-4.7)

| Test Case ID | Test Description | Story | AC | Priority | Impl Effort |
|--------------|------------------|-------|-----|----------|-------------|
| `EVD-001` | Hardware attestation recorded for Secure Enclave device | 4.4 | AC-4.4.1 | P0 | 1d |
| `EVD-002` | Invalid attestation flagged in evidence | 4.4 | AC-4.4.2 | P0 | 0.5d |
| `EVD-003` | Real 3D indoor scene detected with high variance | 4.5 | AC-4.5.1 | P0 | 2d |
| `EVD-004` | Real outdoor scene detected with higher variance | 4.5 | AC-4.5.2 | P0 | 0.5d |
| `EVD-005` | Flat screen detected with low variance | 4.5 | AC-4.5.3 | P0 | 0.5d |
| `EVD-006` | Printed photo detected as flat | 4.5 | AC-4.5.4 | P0 | 0.5d |
| `EVD-007` | Borderline two-layer scene fails layer count | 4.5 | AC-4.5.5 | P1 | 0.5d |
| `EVD-008` | Timestamp within tolerance is valid | 4.6 | AC-4.6.1 | P0 | 0.5d |
| `EVD-009` | Stale timestamp is flagged invalid | 4.6 | AC-4.6.2 | P0 | 0.5d |
| `EVD-010` | iPhone Pro model validated as having LiDAR | 4.6 | AC-4.6.3 | P0 | 0.5d |
| `EVD-011` | Non-Pro device flagged without LiDAR | 4.6 | AC-4.6.4 | P0 | 0.5d |
| `EVD-012` | HIGH confidence for hardware pass AND depth pass | 4.7 | AC-4.7.1 | P0 | 1d |
| `EVD-013` | MEDIUM confidence for hardware pass only | 4.7 | AC-4.7.2 | P0 | 0.5d |
| `EVD-014` | SUSPICIOUS confidence for timestamp manipulation | 4.7 | AC-4.7.3 | P0 | 0.5d |
| `EVD-015` | Evidence package contains all required fields | 4.7 | AC-4.7.4 | P0 | 0.5d |
| `EVD-016` | Capture status transitions to complete | 4.7 | AC-4.7.5 | P0 | 0.5d |
| `EVD-017` | Evidence computation completes within 15s target | 4.7 | Perf | P1 | 0.5d |

**Subtotal Stories 4.4-4.7:** 11 developer days

**Dependencies:**
- Upload endpoint (Story 4.1) must work
- All evidence services must be orchestrated

**Risk Areas:**
- **LiDAR depth thresholds:** Variance > 0.5, layers >= 3, coherence > 0.7 are UNVALIDATED
  - Need real iPhone Pro depth samples for empirical tuning
  - False positive/negative rates unknown until tested with real data
- EXIF parsing: Different JPEG encoders have varying EXIF structures
- Async processing: May need background job queue for production scale

---

### 4. Verification Page (Epic 5.4)

| Test Case ID | Test Description | Story | AC | Priority | Impl Effort |
|--------------|------------------|-------|-----|----------|-------------|
| `VER-001` | Verification page loads for valid capture ID | 5.4 | AC-5.4.1 | P0 | 1d |
| `VER-002` | HIGH confidence displays green badge | 5.4 | AC-5.4.2 | P0 | 0.5d |
| `VER-003` | MEDIUM confidence displays yellow badge | 5.4 | AC-5.4.3 | P0 | 0.5d |
| `VER-004` | LOW confidence displays orange badge | 5.4 | AC-5.4.4 | P0 | 0.5d |
| `VER-005` | SUSPICIOUS confidence displays red badge with warning | 5.4 | AC-5.4.5 | P0 | 0.5d |
| `VER-006` | Captured photo is displayed prominently | 5.4 | AC-5.4.6 | P0 | 0.5d |
| `VER-007` | Capture timestamp is displayed | 5.4 | AC-5.4.7 | P0 | 0.5d |
| `VER-008` | Coarse location displayed when available | 5.4 | AC-5.4.8 | P0 | 0.5d |
| `VER-009` | Depth analysis visualization is displayed | 5.4 | AC-5.4.9 | P0 | 1d |
| `VER-010` | Device model is displayed | 5.4 | AC-5.4.10 | P0 | 0.5d |
| `VER-011` | Invalid capture ID shows not found message | 5.4 | AC-5.4.11 | P0 | 0.5d |
| `VER-012` | Page meets FCP performance target (<1.5s) | 5.4 | AC-5.4.12 | P1 | 0.5d |
| `VER-013` | Media served via CDN with presigned URLs | 5.4 | AC-5.4.13 | P0 | 1d |
| `VER-014` | Page is usable on mobile viewport | 5.4 | Responsive | P1 | 0.5d |
| `VER-015` | Images have descriptive alt text | 5.4 | A11y | P1 | 0.5d |

**Subtotal Story 5.4:** 8.5 developer days

**Dependencies:**
- API endpoint GET /api/v1/captures/{id} must return evidence
- S3 presigned URLs must work
- CDN (CloudFront) should be configured for performance

---

### 5. Evidence Panel (Epic 5.5)

| Test Case ID | Test Description | Story | AC | Priority | Impl Effort |
|--------------|------------------|-------|-----|----------|-------------|
| `PAN-001` | Evidence panel expands on click | 5.5 | AC-5.5.1 | P0 | 0.5d |
| `PAN-002` | Evidence panel collapses on second click | 5.5 | AC-5.5.2 | P0 | 0.25d |
| `PAN-003` | Hardware attestation PASS displayed with green indicator | 5.5 | AC-5.5.3 | P0 | 0.5d |
| `PAN-004` | Hardware attestation level displayed | 5.5 | AC-5.5.4 | P0 | 0.25d |
| `PAN-005` | Device model displayed in hardware attestation | 5.5 | AC-5.5.5 | P0 | 0.25d |
| `PAN-006` | Depth analysis metrics displayed | 5.5 | AC-5.5.6 | P0 | 0.5d |
| `PAN-007` | Depth analysis shows threshold context | 5.5 | AC-5.5.7 | P0 | 0.5d |
| `PAN-008` | is_likely_real_scene result displayed | 5.5 | AC-5.5.8 | P0 | 0.25d |
| `PAN-009` | Depth analysis FAIL displayed with red indicator | 5.5 | AC-5.5.9 | P0 | 0.25d |
| `PAN-010` | Timestamp validation displayed | 5.5 | AC-5.5.10 | P0 | 0.25d |
| `PAN-011` | Timestamp delta displayed | 5.5 | AC-5.5.11 | P0 | 0.25d |
| `PAN-012` | Device model LiDAR validation displayed | 5.5 | AC-5.5.12 | P0 | 0.25d |
| `PAN-013` | Failed checks highlighted with warning styling | 5.5 | AC-5.5.13 | P0 | 0.5d |
| `PAN-014` | Failed checks are emphasized in the panel | 5.5 | AC-5.5.14 | P1 | 0.25d |
| `PAN-015` | Metrics show pass/fail context with thresholds | 5.5 | AC-5.5.15 | P0 | 0.5d |
| `PAN-016` | Each check has visual pass/fail indicator | 5.5 | AC-5.5.16 | P0 | 0.5d |

**Subtotal Story 5.5:** 5.75 developer days

**Dependencies:**
- Verification page (Story 5.4) must be implemented
- Evidence JSONB structure must match API response

---

## Test Fixture Summary

The `tests/support/fixtures/atdd-test-data.ts` provides:

| Fixture Category | Items | Purpose |
|------------------|-------|---------|
| Mock Attestations | 4 | Device registration testing |
| Sample Photos | 4 | Upload + metadata validation testing |
| Sample Depth Maps | 5 | Depth analysis algorithm testing |
| Expected Evidence | 4 | Confidence calculation verification |
| Upload Payloads | 2 | Complete capture upload testing |

**Key Fixtures:**
- `MockAttestations.validSecureEnclave()` - Happy path device registration
- `MockAttestations.invalidCertChain()` - Negative testing
- `SampleDepthMaps.realIndoorScene()` - Should pass depth analysis
- `SampleDepthMaps.flatScreen()` - Should fail depth analysis
- `ExpectedEvidenceFixtures.highConfidence()` - Expected output structure

---

## Implementation Order (Test-First)

### Sprint 1: Foundation + Device Registration (Week 1-2)

```
1. Set up test infrastructure (Docker, Playwright, Jest)
   Tests: N/A (infrastructure)
   Effort: 2d

2. Implement database schema (Story 1.2)
   Tests: Unit tests for migrations
   Effort: 1d

3. Implement API skeleton (Story 1.3)
   Tests: Health check integration test
   Effort: 1d

4. Implement device registration endpoint (Story 2.4)
   Run: device-registration.spec.ts DEV-001 through DEV-005
   Effort: 4d

5. Implement DCAppAttest verification (Story 2.5)
   Run: device-registration.spec.ts DEV-007
   Effort: 2d

6. Implement device auth middleware (Story 2.6)
   Run: device-registration.spec.ts DEV-008, DEV-009
   Effort: 2d
```

**Sprint 1 Target:** All `device-registration.spec.ts` tests passing

---

### Sprint 2: Capture Upload + Evidence (Week 3-4)

```
1. Implement capture upload endpoint (Story 4.1)
   Run: capture-upload.spec.ts UPL-001 through UPL-010
   Effort: 4d

2. Implement attestation verification service (Story 4.4)
   Run: evidence-generation.spec.ts EVD-001, EVD-002
   Effort: 1.5d

3. Implement depth analysis service (Story 4.5)
   Run: evidence-generation.spec.ts EVD-003 through EVD-007
   Effort: 3d

4. Implement metadata validation (Story 4.6)
   Run: evidence-generation.spec.ts EVD-008 through EVD-011
   Effort: 1.5d

5. Implement evidence aggregation + confidence (Story 4.7)
   Run: evidence-generation.spec.ts EVD-012 through EVD-017
   Effort: 2d
```

**Sprint 2 Target:** All `capture-upload.spec.ts` and `evidence-generation.spec.ts` tests passing

---

### Sprint 3: Verification Web (Week 5)

```
1. Implement GET /api/v1/captures/{id} endpoint
   Tests: API contract tests
   Effort: 1d

2. Implement verification page (Story 5.4)
   Run: verification-page.spec.ts VER-001 through VER-015
   Effort: 4d

3. Implement evidence panel component (Story 5.5)
   Run: evidence-panel.spec.ts PAN-001 through PAN-016
   Effort: 3d
```

**Sprint 3 Target:** All web E2E tests passing

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| LiDAR thresholds inaccurate | HIGH | HIGH | Collect real depth samples before Sprint 2 |
| DCAppAttest mock diverges from real | MEDIUM | MEDIUM | Test with real device in staging |
| S3 presigned URL edge cases | LOW | MEDIUM | Test with LocalStack edge cases |
| EXIF parsing variations | MEDIUM | LOW | Test with multiple JPEG sources |
| Depth analysis performance | LOW | MEDIUM | Profile early, optimize if needed |

---

## Test Environment Requirements

### Local Development

```bash
# Start services
docker-compose up -d  # PostgreSQL + LocalStack

# Run backend tests
cd backend && cargo test

# Run integration tests
cd tests && npx playwright test integration/

# Run E2E tests
cd apps/web && npx playwright test e2e/
```

### CI Pipeline

```yaml
stages:
  - unit: cargo test, npm test
  - integration: docker-compose + playwright (backend)
  - e2e: full stack + playwright (web)
  - performance: k6 load tests (staging)
```

---

## Definition of Done

A story is complete when:

1. All ATDD tests for that story are passing
2. Code reviewed and merged
3. No regressions in previously passing tests
4. Performance targets met (where applicable)
5. Test coverage > 80% for new code

---

## Appendix: Test Data Seeding

For E2E tests, seed the following captures in test database:

```sql
-- HIGH confidence capture
INSERT INTO captures (id, device_id, confidence_level, status, evidence, ...)
VALUES ('test-capture-high', ..., 'HIGH', 'complete', ...);

-- MEDIUM confidence capture
INSERT INTO captures (id, device_id, confidence_level, status, evidence, ...)
VALUES ('test-capture-medium', ..., 'MEDIUM', 'complete', ...);

-- SUSPICIOUS capture
INSERT INTO captures (id, device_id, confidence_level, status, evidence, ...)
VALUES ('test-capture-suspicious', ..., 'SUSPICIOUS', 'complete', ...);
```

Or use test data factory in `tests/support/fixtures/atdd-test-data.ts`.

---

## Next Steps for Phase 1 Sprint 1

1. **Run ATDD test suite (expect failures):**
   ```bash
   cd tests && npx playwright test integration/device-registration.spec.ts
   ```

2. **Implement to make tests pass:**
   - Start with `POST /api/v1/devices/register` endpoint
   - Add mock attestation verification
   - Implement device storage

3. **Track progress:**
   - Use `docs/bmm-workflow-status.yaml` for story status
   - Green tests = story complete

4. **Collect LiDAR baseline data:**
   - Capture 20+ real scenes with iPhone Pro
   - Capture 10+ flat surfaces (screens, prints)
   - Store in `tests/support/fixtures/depth-samples/`

---

_Generated by BMAD ATDD Workflow_
_Date: 2025-11-22_
_Project: RealityCam_
_Author: Luca_
