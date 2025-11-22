# System-Level Test Design: RealityCam (Phase 3)

**Date:** 2025-11-22
**Author:** Murat (Test Architect)
**Status:** Draft (Ready for Team Review)

---

## Executive Summary

RealityCam's architecture is **fundamentally testable** but requires **hardware-specific testing strategies** for its security-critical components (DCAppAttest, Secure Enclave, LiDAR depth). The system has strong API/backend testability and clear evidence computation, but Phase 1 implementation must prioritize:

1. **Hardware attestation simulation** (development/staging) before real DCAppAttest in production
2. **LiDAR depth analysis baseline validation** with real device capture samples
3. **Test infrastructure for native iOS modules** (Expo Modules + Swift code)
4. **Contract testing for attestation service integration** (Apple DeviceCheck API)

**Testability Status**: ✅ **PASS with CONDITIONS**
- Backend API testable via integration tests
- Evidence computation pipeline fully testable
- C2PA manifest generation and embedding testable
- **Requires real device + native test setup for security-critical paths**

---

## Testability Assessment

### 1. Controllability: Can We Control System State?

#### ✅ **PASS: Backend API & Database State**

**Evidence:**
- Device registration stateless (post `/api/v1/devices/register` with mock attestation)
- Capture upload testable via multipart POST with mock photo/depth data
- Evidence computation deterministic given inputs
- Database seeded via migrations + test data factories

**Test Strategy:**
```
Unit/Integration: Mock DCAppAttest → seed devices → upload captures → inspect evidence JSONB
Mock objects: DeviceAttestationService, DepthAnalysisService (Rust services)
Test data: Sample depth maps, JPEG photos, metadata
```

**Effort:** Low (2-3 days backend test setup)

---

#### ⚠️ **CONCERNS: DCAppAttest Hardware Attestation**

**Challenge:**
- Real DCAppAttest requires iOS device + Apple servers
- Attestation object is CBOR-encoded, time-bound (certificate pinning)
- Cannot mock server-side verification without Apple's root CA

**Testability Gap:**
- Development: Needs **mock attestation flow** (pre-generated attestation objects for testing)
- Staging: Needs **real device attestation** (QA device registers, captures on real device)
- Production: Real attestation required

**Test Strategy:**
```
Level 1 (Unit): DCAppAttest parsing - test CBOR decoding, certificate validation logic
Level 2 (Integration): Mock attestation flow - seed pre-generated attestation objects
Level 3 (E2E): Real device attestation on staging (QA device with app installed)
```

**Mitigation:**
- Create **attestation fixtures**: Pre-generated valid/invalid CBOR objects for testing
- Mock Apple DeviceCheck API responses in development
- Real device integration testing on staging (1-2 QA iPhones Pro)

**Effort:** Medium (5-7 days for mock attestation + native module test harness)

---

#### ⚠️ **CONCERNS: Secure Enclave Key Generation & LiDAR Capture**

**Challenge:**
- Secure Enclave keys are hardware-bound, non-extractable
- Cannot replicate in simulator (simulator has no real Secure Enclave)
- LiDAR capture requires physical iPhone Pro device (13 Pro+ or later)

**Testability Gap:**
- Simulator testing: Cannot fully test key generation or LiDAR capture
- Real device testing: Requires actual iPhone Pro (12 Pro or later)

**Test Strategy:**
```
Level 1 (Unit): Key generation logic - test Swift code with mock SecureEnclave APIs
Level 2 (Integration): LiDAR depth capture - test ARKit API integration (simulator has mocked depth)
Level 3 (E2E): Real device - actual Secure Enclave + LiDAR on iPhone Pro
```

**Mitigation:**
- **Simulator testing**: Use ARKit's mock depth data (available in simulator)
- **Real device testing**: Set up CI device farm or QA device workflow
- **Native test framework**: Implement XCTest for Swift modules (Expo Module testing)

**Effort:** High (10-15 days for native test infrastructure)

---

### 2. Observability: Can We Inspect System Behavior?

#### ✅ **PASS: Evidence Pipeline & API Responses**

**Observability Points:**
- Evidence package as JSONB (queryable, inspectable)
- API responses structured (metadata, timestamps, trace IDs)
- HTTP logs with request IDs (X-Request-Id header)
- C2PA manifest content parseable

**Validation Strategy:**
```typescript
// Integration test: Verify evidence structure
const response = await request.post('/api/v1/captures', { ... });
const evidence = response.body.data.evidence;

expect(evidence).toHaveProperty('hardware_attestation.status');
expect(evidence).toHaveProperty('depth_analysis.depth_variance');
expect(evidence).toHaveProperty('metadata.timestamp_valid');
```

**Effort:** Low (already built into API design)

---

#### ⚠️ **CONCERNS: LiDAR Depth Analysis Algorithm**

**Challenge:**
- Depth variance threshold (>0.5) - needs empirical validation
- Edge coherence calculation (>0.7) - needs real depth vs RGB edge alignment data
- Depth layer clustering (≥3 distinct planes) - needs real scene samples

**Observability Gap:**
- No ground truth for "real scene" vs "fake scene" classification
- Thresholds tuned on architecture doc assumptions, not validated against real data

**Validation Strategy:**
```
Phase 1: Collect real depth maps from actual iPhone Pro captures
Phase 2: Manual classification (real vs flat image vs screen)
Phase 3: Empirical threshold tuning (ROC curve analysis)
Phase 4: Integrate baseline validation into CI
```

**Mitigation:**
- Baseline dataset: 50-100 real LiDAR captures + manual ground truth labels
- Depth analysis unit tests with known depth maps
- Performance metrics: Precision, recall, F1-score for "real scene" detection

**Effort:** Medium (7-10 days for baseline dataset + metric validation)

---

#### ✅ **PASS: Performance Observability**

**Metrics:**
- Capture → processing complete: target <15s
- Verification page FCP: target <1.5s
- Depth analysis computation: target <5s
- Evidence computation: target <10s

**Observability:**
- Server timing headers (Server-Timing)
- Request duration in logs (Axum tracing)
- CloudFront/S3 CDN metrics for media serving
- Database query duration (SQLx instrumentation)

**Effort:** Low (requires k6 load testing setup)

---

### 3. Reliability: Can Tests Be Isolated & Reproduced?

#### ✅ **PASS: API & Database Tests**

**Isolation Strategy:**
- Database: Test container (testcontainers or Docker Compose) per test run
- API: Stateless endpoints, no session pollution
- Data cleanup: Fixtures with auto-cleanup (delete by capture ID)

**Reproducibility:**
- Deterministic input data (factories with faker seeding)
- No time-dependent logic (use fixed timestamps in tests)
- Parallel-safe: Tests don't share database rows

**Effort:** Low (standard integration testing patterns)

---

#### ⚠️ **CONCERNS: iOS App Tests (Expo Modules + Swift)**

**Challenge:**
- Expo Modules (TypeScript ↔ Swift bridge) require both iOS + JS testing
- Swift code (Secure Enclave, ARKit, DCAppAttest) needs XCTest
- Integration between JS and native not easily mockable

**Isolation Gap:**
- Real device tests cannot run in parallel
- Simulator tests limited to ARKit mock depth (not real LiDAR)
- State leakage from one test to next (Keychain, UserDefaults persist)

**Reliability Strategy:**
```
Isolation:
  - Keychain cleanup between test runs (remove keys by key ID)
  - UserDefaults reset (NSUserDefaults.resetStandardUserDefaults)
  - File system cleanup (remove cached captures)

Reproducibility:
  - Seed ARKit depth data (mock depth array for simulator tests)
  - Use deterministic file paths (test-specific directories)
  - Mock TimeZone and system time (if used)
```

**Effort:** Medium-High (8-12 days for native test harness)

---

## Architecturally Significant Requirements (ASRs)

| ASR | Category | Testability | Complexity | Risk |
|-----|----------|-------------|-----------|------|
| DCAppAttest hardware attestation (Secure Enclave-backed) | SEC | ⚠️ Requires real device | Medium | High |
| LiDAR depth analysis for "real scene" detection | PERF/TECH | ⚠️ Empirical tuning needed | Medium | Medium |
| Evidence computation pipeline (20+ checks) | TECH | ✅ Fully testable | Low | Medium |
| C2PA manifest generation & signing | SEC/TECH | ✅ Fully testable | Low | Low |
| Offline capture storage (Secure Enclave-backed encryption) | DATA/REL | ⚠️ Requires native test setup | Medium | Medium |
| Upload retry with exponential backoff | REL | ✅ Fully testable | Low | Low |
| Device-based authentication (Ed25519 signatures) | SEC | ✅ Fully testable | Low | Low |
| S3 media storage + CloudFront CDN | PERF | ✅ Testable with LocalStack | Low | Low |

---

## Test Levels Strategy

### Architecture-Based Test Distribution

RealityCam has three distinct layers requiring different test levels:

#### **iOS App (Expo + React Native + Expo Modules)**

```
Unit Tests (45%):
  - Redux/Zustand store reducers
  - API client (request signing, retry logic)
  - Data factories and validators
  - Camera view component logic (not UI)

Component Tests (25%):
  - Camera view with depth overlay rendering
  - Preview screen with photo display
  - Result screen with share button
  - History list UI

E2E Tests (30%):
  - Complete capture flow (open app → capture → upload → result)
  - Offline capture → upload on reconnect
  - Deep linking to verification URL
  - Permission requests (camera, location)

Real Device Required:
  - LiDAR depth overlay rendering (must see actual depth visualization)
  - Secure Enclave key generation + signing
  - DCAppAttest attestation request
```

#### **Rust Backend (Axum + Evidence Computation)**

```
Unit Tests (40%):
  - Depth analysis algorithm (variance, layers, coherence)
  - Evidence scoring and confidence calculation
  - EXIF parsing and timestamp validation
  - Ed25519 signature verification
  - Error handling and logging

Integration Tests (50%):
  - Device registration endpoint with mock attestation
  - Capture upload endpoint with multipart parsing
  - Evidence generation pipeline (all checks together)
  - Database transactions and cleanup
  - S3 operations with LocalStack

E2E Tests (10%):
  - Full capture flow: register device → upload → verify → evidence shown
  - File verification via hash lookup
  - C2PA manifest embedding and storage
```

#### **Next.js Web (Verification UI)**

```
Component Tests (50%):
  - Evidence panel component (pass/fail rendering)
  - Confidence badge styling (HIGH/MEDIUM/LOW/SUSPICIOUS)
  - Depth visualization (heatmap rendering)
  - File upload dropzone

E2E Tests (50%):
  - Verification page loads for valid capture
  - Evidence panel expands/collapses
  - File upload flow (hash lookup, results)
  - Error states (invalid capture ID, no match)
```

### Test Level Selection Rationale

| Scenario | Level | Rationale |
|----------|-------|-----------|
| Depth variance calculation (20+ algorithms) | Unit | Pure math, fast, edge cases |
| Device registration (API contract) | Integration | Service boundary, database involved |
| Complete capture flow (UI → API → evidence) | E2E | User-facing critical path, real device |
| Confidence level calculation | Unit | Pure function, deterministic |
| Evidence JSONB structure | Integration | Database schema, API contract |
| LiDAR depth overlay | E2E | Real device only, visual feedback |
| Ed25519 signature verification | Unit | Cryptographic algorithm, fast |
| Upload retry logic | Integration | Service behavior, network simulation |

---

## Non-Functional Requirements (NFR) Testing Approach

### Security (Crypto, Auth, Data Protection)

**What to test (automated):**

| Test | Tool | Coverage | Acceptance |
|------|------|----------|-----------|
| DCAppAttest attestation chain validation | Rust unit test | Certificate parsing, root CA verification | ✅ PASS: Cert chain validates to Apple root |
| Ed25519 device signature verification | Unit test (ed25519-dalek) | Signature generation + validation | ✅ PASS: Valid sigs accept, invalid reject |
| EXIF timestamp validation (±5 min) | Unit test | Time comparison logic | ✅ PASS: Within ±5min allowed, outside rejected |
| SQL injection prevention | Integration test (Playwright) | SQLx parameterized queries | ✅ PASS: Injection attempts blocked, no error exposure |
| Secrets never logged | Integration test | Mock Sentry/logging, verify password not in logs | ✅ PASS: Sensitive data excluded from logs |
| TLS 1.3 enforcement | Integration test (API request headers) | Verify HTTPS, reject HTTP | ✅ PASS: All endpoints require TLS 1.3 |
| Device key isolation (Keychain) | Native unit test (Swift) | Key generation in Secure Enclave, non-extractable | ✅ PASS: Key sealed to device, not exportable |

**Effort:** 8 days backend + 5 days iOS native

---

### Performance (LiDAR Analysis, Response Times, CDN)

**What to test (automated via k6):**

| Metric | Tool | Target | Acceptance |
|--------|------|--------|-----------|
| Depth analysis computation | k6 load test | <5s | ✅ PASS: p95 <5s under load |
| Capture processing (all checks) | k6 load test | <15s | ✅ PASS: p95 <15s under 100 concurrent |
| Verification page FCP | Playwright + Lighthouse | <1.5s | ✅ PASS: FCP <1.5s via CDN |
| Upload throughput | k6 with file streaming | 10 MB/s minimum | ✅ PASS: Sustained 10 MB/s with 50 concurrent |
| Evidence JSONB query speed | Integration test | <100ms | ✅ PASS: Indexed hash lookups <100ms |

**Execution:**
- **Load testing**: k6 with staged load (ramp 50 users → 100 users → spike to 200)
- **Stress testing**: Find breaking point (at what user count does p95 exceed threshold?)
- **Endurance testing**: Sustained 100 users for 10 minutes (detect memory leaks)

**Effort:** 5 days k6 setup + baseline runs

---

### Reliability (Offline, Retries, Error Handling)

**What to test (automated via Playwright):**

| Test | Tool | Coverage | Acceptance |
|------|------|----------|-----------|
| Offline capture storage | Playwright | Network disconnect → capture saved → reconnect → upload | ✅ PASS: Captures persist, auto-upload on reconnect |
| Retry with exponential backoff | Playwright + mock 503 | Fail 2x → succeed 3rd attempt | ✅ PASS: Retries capped at 5, backoff works |
| Circuit breaker (if attestation service fails) | Integration test | 5 consecutive failures → fallback | ✅ PASS: Opens after threshold, stops hammering |
| Health check endpoint | Integration test | `/api/health` returns service status | ✅ PASS: All dependencies reported (DB, S3) |
| JPEG data durability | Integration test | Upload → store → retrieve → verify hash | ✅ PASS: No corruption, hash stable |
| Graceful degradation on API errors | Playwright | 500 error → user-friendly message | ✅ PASS: No crashes, retry offered |

**Effort:** 6 days Playwright E2E setup

---

### Maintainability (Code Quality, Observability, Test Coverage)

**What to test (CI gates):**

| Check | Tool | Acceptance |
|-------|------|-----------|
| Test coverage | Cargo tarpaulin (Rust) | ≥80% for evidence module |
| Code duplication | jscpd | <5% allowed |
| Vulnerabilities | cargo audit (Rust) + npm audit | No critical/high, zero unsafe code |
| Type safety | Rust compiler + TypeScript strict mode | No `@ts-ignore`, all types explicit |
| Logging completeness | Grep for log statements | Every error path logged |
| Error telemetry | Verify Sentry SDK integrated | Critical errors captured, not swallowed |

**Effort:** 3 days CI pipeline setup

---

## Test Environment Requirements

### Phase 0 (Hackathon - Development)

```
Infrastructure:
  - Docker Compose: PostgreSQL 16, LocalStack (S3 mock)
  - Node.js 22 + Rust 1.82 + Xcode 16
  - iOS Simulator (ARM or Intel)

Data:
  - Test database snapshots (fixtures)
  - Sample depth maps (real iPhone Pro captures)
  - Pre-generated attestation objects (for mock testing)

Device:
  - OPTIONAL: 1 physical iPhone Pro for manual testing

Testing Tools:
  - Jest + Vitest (unit tests)
  - Playwright (integration E2E)
  - Cargo test (Rust unit/integration)
  - XCTest (Expo Module native tests)
  - k6 (performance testing, Phase 1+)
```

### Phase 1 (Sprint 1-2 - Staging)

```
Added Infrastructure:
  - Real PostgreSQL instance (RDS equivalent)
  - Real S3 bucket + CloudFront CDN
  - Real iOS app on TestFlight or staging server
  - Real device (1-2 iPhone Pro for QA)

Real Device Usage:
  - Device registration with real DCAppAttest
  - Actual LiDAR depth capture (baseline validation)
  - E2E testing on physical device
  - Offline capture → reconnect scenarios
```

---

## Testability Concerns & Recommendations

### 🚨 **CRITICAL: LiDAR Depth Analysis Thresholds Unvalidated**

**Concern:** Architecture doc defines thresholds (variance >0.5, layers ≥3, coherence >0.7) but these are NOT empirically validated against real iPhone Pro LiDAR data.

**Risk:**
- False negatives: Real scenes classified as flat/fake
- False positives: Flat images/screens classified as real

**Mitigation (MUST DO before Phase 1):**
```
Week 1: Collect baseline dataset
  - 50 real 3D scene captures (diverse: outdoors, indoors, objects, people)
  - 20 flat images (screens, prints, artwork)
  - 20 synthetic depth maps (CGI, 3D models)

Week 2: Manual ground truth labeling
  - 2 reviewers independently label each (real vs fake)
  - Resolve disagreements

Week 3: Empirical threshold tuning
  - Run depth analysis on each sample
  - Plot distribution of (variance, layers, coherence)
  - Optimize thresholds using ROC curve analysis (maximize F1-score)

Week 4: Integrate baselines into CI
  - Unit tests with known depth maps
  - Performance metrics: Precision, recall, F1
  - Alert if metrics degrade
```

**Ownership:** Backend engineer (with iPhone Pro + Luca validation)
**Deadline:** Before Phase 1 implementation
**Effort:** 15-20 hours

---

### ⚠️ **HIGH: Native Module Testing Infrastructure Missing**

**Concern:** Expo Modules (Swift + TypeScript bridge) have no test infrastructure yet. Secure Enclave key generation and LiDAR capture untestable without it.

**Risk:**
- Integration bugs between JS and Swift not caught
- Keychain state leakage between test runs (flaky tests)
- Simulator depth mocking insufficient for real verification

**Mitigation:**
```
Phase 0 (Week 1):
  - Set up XCTest for Expo Module Swift code
  - Create MockARKit for simulator depth testing
  - Implement Keychain cleanup between tests

Phase 1 (Week 2):
  - Real device test farm (CI agent on iPhone Pro)
  - Or: Manual QA device testing protocol (daily validation)
```

**Ownership:** iOS engineer
**Deadline:** Before Phase 1 iOS stories
**Effort:** 30-40 hours

---

### ⚠️ **MEDIUM: DCAppAttest Attestation Service Integration Testing**

**Concern:** Real DCAppAttest requires Apple servers + real device. Cannot test in isolation.

**Mitigation:**
```
Development:
  - Mock attestation flow (pre-generated CBOR objects)
  - Test certificate parsing + validation logic in unit tests

Staging:
  - Real device runs real DCAppAttest
  - Capture on device, verify server-side validation

Production:
  - Real attestation required (no mocking)
```

**Test Strategy:**
1. Unit tests: CBOR parsing, cert chain validation (mock certificate data)
2. Integration tests: Mock DeviceCheck API (return canned responses)
3. E2E tests: Real device on staging (1-2 QA devices sufficient)

**Ownership:** Backend + iOS engineer
**Deadline:** Phase 1 Sprint 2
**Effort:** 20-25 hours

---

### ✅ **LOW: Backend API Fully Testable**

**Strengths:**
- Clear API contracts
- Stateless endpoints
- Evidence pipeline is deterministic
- C2PA manifest generation is verifiable

**Testing Strategy:**
- Integration tests with testcontainers (PostgreSQL + LocalStack)
- Mock DeviceAttestationService + DepthAnalysisService
- Full coverage of evidence computation pipeline

---

## Recommendations for Sprint 0 (Phase 0)

### Priority 1: Infrastructure (Baseline)

| Task | Effort | Owner | Deadline |
|------|--------|-------|----------|
| Set up Docker Compose (PostgreSQL + LocalStack) | 1 day | Backend | Week 1 |
| Create test data factories (users, captures, devices) | 1 day | Backend | Week 1 |
| Configure Cargo test + Jest for unit testing | 1 day | Backend/Frontend | Week 1 |
| Set up Playwright for integration E2E tests | 2 days | Frontend/Backend | Week 2 |

### Priority 2: Evidence Pipeline Testing (Core)

| Task | Effort | Owner | Deadline |
|------|--------|-------|----------|
| Depth analysis algorithm unit tests + mock data | 3 days | Backend | Week 2 |
| Evidence JSONB structure + confidence calculation tests | 2 days | Backend | Week 2 |
| C2PA manifest generation + embedding tests | 2 days | Backend | Week 2 |
| Device registration endpoint integration tests | 2 days | Backend | Week 3 |
| Capture upload endpoint integration tests | 2 days | Backend | Week 3 |

### Priority 3: Native Testing (Phase 1 Prep)

| Task | Effort | Owner | Deadline |
|------|--------|-------|----------|
| XCTest harness for Expo Module Swift code | 4 days | iOS | Week 3 |
| Keychain cleanup fixtures | 2 days | iOS | Week 3 |
| MockARKit for simulator depth testing | 3 days | iOS | Week 4 |

### Priority 4: Baseline Validation (Critical for Accuracy)

| Task | Effort | Owner | Deadline |
|------|--------|-------|----------|
| Collect LiDAR baseline dataset (50 real scenes + 20 flat) | 8 hours | Luca (device) | Week 2 |
| Manual ground truth labeling | 8 hours | Luca + 1 reviewer | Week 3 |
| Empirical threshold tuning (ROC curve analysis) | 16 hours | Backend | Week 4 |
| Integrate baseline validation into CI | 4 hours | Backend | Week 4 |

---

## Quality Gate Criteria for Solutioning Phase (Phase 2 → 3)

**PASS**: Project can proceed to implementation if:

- [ ] Backend API integration tests ≥85% coverage for evidence module
- [ ] LiDAR depth analysis thresholds empirically validated (precision >95%, recall >90%)
- [ ] C2PA manifest generation tested and verified
- [ ] Native test harness for Expo Modules implemented
- [ ] Device-based auth (Ed25519) fully tested
- [ ] Health check endpoint defined and tested
- [ ] No critical testability blockers identified

**CONCERNS**: Proceed with caution if:

- [ ] LiDAR thresholds not empirically validated (use baseline dataset, flag risk)
- [ ] Native test infrastructure incomplete (flag requirement for Phase 1)
- [ ] DCAppAttest mock attestation flow not finalized (defer to Phase 1 sprint 2)

**FAIL**: Stop and rework architecture if:

- [ ] Secure Enclave key generation untestable on real device (would require redesign)
- [ ] Evidence computation not verifiable (would require rearchitecture)
- [ ] C2PA signing key management problematic (would require KMS redesign)

---

## Integration Points with Other Workflows

This test design feeds into:

1. **`*framework` workflow** (Phase 1): Scaffold Jest/Cargo test structure based on this test levels strategy
2. **`*atdd` workflow** (Phase 1): Generate E2E tests for critical capture → verify flow (P0 scenarios)
3. **`*automate` workflow** (Phase 1): Expand test coverage per epic (all integration + component tests)
4. **`*ci` workflow** (Phase 1): Configure pipeline stages: unit → integration → E2E → performance
5. **`*nfr-assess` workflow** (Phase 1): Detailed security, performance, reliability validation strategies

---

## Assumptions & Dependencies

### Assumptions

1. **LiDAR baseline dataset achievable**: Able to collect 50+ real depth samples from iPhone Pro
2. **Real device available for QA**: At least 1 physical iPhone Pro for Phase 1 testing
3. **Expo Module testing possible**: Swift code testable via XCTest + native test harness
4. **DCAppAttest service mockable**: Can generate valid CBOR attestation objects for testing

### Dependencies

1. **Hardware**: iPhone Pro (12 Pro or later) for LiDAR testing
2. **Tools**: XCTest, k6, Playwright (all free/open-source except XCTest which is bundled)
3. **Data**: Apple's root CA certificate for attestation validation (public)
4. **Services**: Apple DeviceCheck API (production only, mocked in dev/staging)

---

## Success Metrics (End of Phase 0)

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Backend integration test coverage (evidence module) | ≥85% | 0% | ⏳ To do |
| LiDAR depth analysis empirically validated | ✅ PASS | ❌ Not validated | ⏳ Critical |
| Native test harness for Expo Modules | ✅ Functional | ❌ Not started | ⏳ To do |
| Testability blockers identified | 0 | TBD | ⏳ Assessment done |
| Test infrastructure (Docker, Jest, Playwright, k6) | ✅ Ready | ❌ Not started | ⏳ To do |

---

## Next Steps

1. **Team Review**: Present this assessment to backend + iOS + frontend leads
2. **LiDAR Baseline Kickoff**: Start collecting real depth samples immediately (Week 1)
3. **Test Infrastructure Sprint**: Allocate 1 engineer (5 days) for Docker/Jest/Playwright setup
4. **Native Test Setup**: iOS engineer dedicates Week 3-4 to XCTest harness
5. **Phase 1 Planning**: Use this assessment to estimate effort for `*framework` + `*atdd` workflows

---

## Appendix: Risk Scoring

| Risk | Probability | Impact | Score | Mitigation |
|------|-----------|--------|-------|-----------|
| LiDAR thresholds inaccurate | 3 (likely) | 3 (critical) | **9** | Empirical validation ASAP |
| Native module testing gaps | 2 (possible) | 2 (degraded) | **4** | XCTest harness in Week 3 |
| DCAppAttest simulation fails | 2 (possible) | 2 (degraded) | **4** | Mock CBOR objects ready |
| Depth analysis too slow (<5s) | 1 (unlikely) | 2 (degraded) | **2** | Profile + optimize in Phase 1 |
| C2PA manifest embedding breaks | 1 (unlikely) | 2 (degraded) | **2** | Unit tests during Phase 1 |

---

_Generated by BMAD Test Architecture Workflow (System-Level Mode)_
_RealityCam Project - Luca_
_Phase 2 (Solutioning) → Phase 3 (Implementation Ready)_
