# Story 3.4: Capture Attestation Signature

Status: review

## Story

As a **mobile app user with an iPhone Pro device**,
I want **each photo capture to be signed with a device attestation assertion**,
so that **the capture is cryptographically bound to my attested device, creating an unbroken chain of trust from hardware to evidence**.

## Acceptance Criteria

1. **AC-1: CaptureAssertion Type Definition**
   - Given the shared types package
   - When capture attestation types are defined
   - Then a `CaptureAssertion` interface exists with:
     - `assertion: string` - Base64-encoded assertion from @expo/app-integrity
     - `clientDataHash: string` - Base64-encoded SHA-256 hash of metadata
     - `timestamp: string` - ISO timestamp when assertion was generated
   - And `CaptureAssertionError` type with error codes

2. **AC-2: useCaptureAttestation Hook API**
   - Given the capture screen uses the hook
   - When the `useCaptureAttestation` hook is used
   - Then it provides:
     - `generateAssertion(metadata: AssertionMetadata): Promise<CaptureAssertion>` - Generate assertion for capture
     - `isReady: boolean` - True when device is attested and can generate assertions
     - `isGenerating: boolean` - True during assertion generation
     - `error: CaptureAssertionError | null` - Error from last operation
   - And the hook uses `keyId` from `useDeviceStore`

3. **AC-3: AssertionMetadata Structure**
   - Given a capture is complete with photo, depth, timestamp, and optional location
   - When metadata is prepared for assertion
   - Then `AssertionMetadata` includes:
     - `photoHash: string` - SHA-256 hash of photo bytes (base64)
     - `depthHash: string` - SHA-256 hash of depth map bytes (base64)
     - `timestamp: string` - ISO timestamp of capture
     - `locationHash?: string` - SHA-256 hash of location string (if available)

4. **AC-4: Per-Capture Assertion Generation**
   - Given a photo + depth capture is complete
   - When assertion generation is triggered
   - Then `generateAssertionAsync(keyId, clientDataHash)` from @expo/app-integrity is called
   - And `clientDataHash` is SHA-256 of JSON.stringify(AssertionMetadata)
   - And the assertion is a base64-encoded string

5. **AC-5: RawCapture Type Extension**
   - Given the RawCapture interface from Story 3-2
   - When extended for attestation support
   - Then RawCapture includes:
     - `assertion?: CaptureAssertion` - Optional attestation data
   - And CaptureAssertion type is exported from shared package

6. **AC-6: useCapture Integration**
   - Given the useCapture hook from Story 3-2/3-3
   - When attestation is integrated
   - Then useCapture:
     - Calls useCaptureAttestation hook
     - Generates assertion after photo/depth/location captured
     - Computes photoHash and depthHash using expo-crypto
     - Includes CaptureAssertion in RawCapture when successful
   - And assertion failure is logged but does not block capture (graceful degradation)

7. **AC-7: Attestation-Ready Check**
   - Given the device may not be attested (failed attestation)
   - When capture is initiated
   - Then `useCaptureAttestation.isReady` returns false if:
     - Device is not attested (`isAttested === false`)
     - No keyId is available
   - And capture proceeds without assertion (unverified mode)
   - And RawCapture.assertion is `undefined`

8. **AC-8: Error Handling**
   - Given assertion generation may fail
   - When `generateAssertionAsync` throws
   - Then error is caught and logged
   - And `CaptureAssertionError` is set with appropriate code
   - And capture proceeds without assertion (graceful degradation)
   - And RawCapture.assertion is `undefined`

## Tasks / Subtasks

- [x] Task 1: Create CaptureAssertion Type Definition (AC: 1, 3, 5)
  - [x] 1.1: Add `CaptureAssertion` interface to `packages/shared/src/types/capture.ts`
  - [x] 1.2: Add `AssertionMetadata` interface for metadata hash computation
  - [x] 1.3: Add `CaptureAssertionError` type with error codes
  - [x] 1.4: Add optional `assertion?: CaptureAssertion` to RawCapture interface
  - [x] 1.5: Export new types from `packages/shared/src/index.ts`

- [x] Task 2: Create useCaptureAttestation Hook (AC: 2, 4, 7, 8)
  - [x] 2.1: Create `apps/mobile/hooks/useCaptureAttestation.ts`
  - [x] 2.2: Import `@expo/app-integrity` and `expo-crypto`
  - [x] 2.3: Get `keyId` and `isAttested` from `useDeviceStore`
  - [x] 2.4: Implement `generateAssertion()` with:
    - [x] 2.4.1: Build clientDataHash from AssertionMetadata
    - [x] 2.4.2: Call `generateAssertionAsync(keyId, clientDataHash)`
    - [x] 2.4.3: Return CaptureAssertion object
  - [x] 2.5: Implement `isReady` check based on attestation status
  - [x] 2.6: Implement error handling with typed CaptureAssertionError
  - [x] 2.7: Return null/undefined on failure instead of throwing

- [x] Task 3: Integrate Assertion into useCapture (AC: 6)
  - [x] 3.1: Update `apps/mobile/hooks/useCapture.ts`
  - [x] 3.2: Import and use `useCaptureAttestation` hook
  - [x] 3.3: Compute photoHash from photo bytes using expo-crypto
  - [x] 3.4: Compute depthHash from depth map using expo-crypto
  - [x] 3.5: Compute optional locationHash if location exists
  - [x] 3.6: Call `generateAssertion()` with metadata after capture
  - [x] 3.7: Include assertion in RawCapture (undefined if not available)

- [x] Task 4: Export Hook from Hooks Index (AC: 2)
  - [x] 4.1: Add `useCaptureAttestation` export to `apps/mobile/hooks/index.ts`

- [ ] Task 5: Testing (AC: all)
  - [ ] 5.1: Unit test useCaptureAttestation hook with mocked @expo/app-integrity (deferred to testing sprint)
  - [ ] 5.2: Unit test assertion generation with mock keyId (deferred to testing sprint)
  - [ ] 5.3: Integration test useCapture with assertion (deferred to testing sprint)
  - [ ] 5.4: Manual test on iPhone: assertion generation (requires device testing)

## Dev Notes

### Architecture Alignment

This story implements AC-3.6 from Epic 3 Tech Spec. It builds upon:
- Story 2-3's `useDeviceAttestation` hook for initial device attestation
- Story 3-2's `useCapture` hook for photo + depth capture
- Story 3-3's location capture for optional location hash

**Key alignment points:**
- **@expo/app-integrity (ADR-007):** Per-capture assertions via `generateAssertionAsync()`
- **Device-Based Auth (ADR-005):** Assertions bound to attested device key
- **Hook Pattern**: Follows established pattern from existing hooks
- **Graceful Degradation**: Assertion failure never blocks capture

### Previous Story Learnings

1. **useDeviceAttestation**: Provides `keyId` via `useDeviceStore` - key for assertions
2. **deviceStore.isAttested**: Boolean indicating if device passed attestation
3. **@expo/app-integrity API**: `generateAssertionAsync(keyId, clientDataHash)` returns base64 string
4. **Promise.allSettled Pattern**: From Story 3-3 - use for graceful degradation
5. **expo-crypto**: Used for SHA-256 hashing in Story 3-2

### Assertion Generation Flow

Per Epic 3 Tech Spec section "Per-Capture Assertion":

```typescript
// In useCapture after photo/depth/location captured
const metadata: AssertionMetadata = {
  photoHash: await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    photoBase64,
    { encoding: Crypto.CryptoEncoding.BASE64 }
  ),
  depthHash: await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    depthMapBase64,
    { encoding: Crypto.CryptoEncoding.BASE64 }
  ),
  timestamp: capturedAt,
  locationHash: location ? await hashLocation(location) : undefined,
};

const clientDataHash = await Crypto.digestStringAsync(
  Crypto.CryptoDigestAlgorithm.SHA256,
  JSON.stringify(metadata),
  { encoding: Crypto.CryptoEncoding.BASE64 }
);

const assertion = await AppIntegrity.generateAssertionAsync(keyId, clientDataHash);
```

### @expo/app-integrity API Reference

From architecture documentation:

```typescript
import * as AppIntegrity from '@expo/app-integrity';

// Generate assertion (per-capture)
// keyId: string - The key ID from attestKeyAsync
// clientDataHash: string - Base64 SHA-256 hash of client data
// Returns: Promise<string> - Base64-encoded assertion
const assertion = await AppIntegrity.generateAssertionAsync(keyId, clientDataHash);
```

### Error Handling Strategy

```typescript
type CaptureAssertionErrorCode =
  | 'NOT_ATTESTED'       // Device not attested (keyId missing)
  | 'ASSERTION_FAILED'   // generateAssertionAsync threw
  | 'HASH_FAILED'        // SHA-256 computation failed
  | 'UNKNOWN';           // Unknown error

interface CaptureAssertionError {
  code: CaptureAssertionErrorCode;
  message: string;
}
```

Assertion errors are **informational only** - they don't prevent capture. The capture is marked as "unverified" and proceeds.

### Security Considerations

Per Epic 3 Tech Spec "Capture Integrity":

| Aspect | Implementation |
|--------|----------------|
| Per-capture assertion | Binds capture to attested device |
| Photo hash binding | Hash included in assertion clientDataHash |
| Timestamp binding | Capture timestamp in assertion payload |
| Depth hash binding | Proves depth wasn't fabricated separately |

### File Structure After Implementation

```
apps/mobile/
├── hooks/
│   ├── useLiDAR.ts              # From Story 3-1
│   ├── useCapture.ts            # Updated - assertion integration
│   ├── useLocation.ts           # From Story 3-3
│   ├── useCaptureAttestation.ts # NEW - assertion hook
│   └── index.ts                 # Updated - export new hook
```

### References

- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-3.md#AC-3.6]
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-3.md#Per-Capture-Assertion]
- [Source: docs/architecture.md#ADR-007-App-Integrity]
- [Source: docs/sprint-artifacts/stories/2-3-dcappattest-integration.md]
- [Source: docs/sprint-artifacts/stories/3-2-photo-capture-depth-map.md]
- [Source: docs/sprint-artifacts/stories/3-3-gps-metadata-collection.md]
- [@expo/app-integrity Documentation](https://docs.expo.dev/versions/latest/sdk/app-integrity/)

## Dev Agent Record

### Context Reference

Story file dev notes used as context

### Agent Model Used

claude-sonnet-4-5-20250929

### Debug Log References

N/A

### Completion Notes List

#### Implementation Summary

Implemented per-capture device attestation signatures using @expo/app-integrity. Each capture is now cryptographically bound to the attested device via an assertion that includes hashes of the photo, depth map, timestamp, and optional location.

#### Key Implementation Decisions

1. **Graceful Degradation Pattern**: Assertion generation failure never blocks capture. If device is not attested or assertion fails, capture proceeds without assertion (unverified mode).

2. **Hash Chain Structure**: AssertionMetadata includes photoHash, depthHash, timestamp, and optional locationHash. This creates a complete evidence chain binding all capture data to the attestation.

3. **Location Hash Format**: Location is hashed as `${latitude},${longitude},${timestamp}` string to create deterministic hash.

4. **Sequential Assertion**: Assertion is generated after photo/depth/location capture completes (not in parallel) because it depends on computed hashes of the capture data.

5. **expo-file-system Encoding**: Used `encoding: 'base64'` string literal instead of `FileSystem.EncodingType.Base64` enum for compatibility with current expo-file-system version.

#### Acceptance Criteria Status

- AC-1 (CaptureAssertion Type Definition): SATISFIED - Interface at `capture.ts:187-194`
- AC-2 (useCaptureAttestation Hook API): SATISFIED - Hook at `useCaptureAttestation.ts:74-192`
- AC-3 (AssertionMetadata Structure): SATISFIED - Interface at `capture.ts:172-181`
- AC-4 (Per-Capture Assertion Generation): SATISFIED - `generateAssertion()` calls `generateAssertionAsync()`
- AC-5 (RawCapture Type Extension): SATISFIED - Optional `assertion` field at `capture.ts:101`
- AC-6 (useCapture Integration): SATISFIED - Integrated at `useCapture.ts:298-354`
- AC-7 (Attestation-Ready Check): SATISFIED - `isReady = isAttested && keyId !== null` at `useCaptureAttestation.ts:83`
- AC-8 (Error Handling): SATISFIED - Try-catch with graceful degradation at `useCaptureAttestation.ts:88-184`

#### Technical Debt / Follow-ups

- Testing tasks (5.1-5.4) deferred to testing sprint as noted in story
- Manual device testing required for full validation of assertion generation

### File List

#### Created

- `/Users/luca/dev/realitycam/apps/mobile/hooks/useCaptureAttestation.ts` - New hook for per-capture attestation generation
- `/Users/luca/dev/realitycam/docs/sprint-artifacts/stories/3-4-capture-attestation-signature.md` - Story file

#### Modified

- `/Users/luca/dev/realitycam/packages/shared/src/types/capture.ts` - Added AssertionMetadata, CaptureAssertion, CaptureAssertionErrorCode, CaptureAssertionError types; extended RawCapture with optional assertion field
- `/Users/luca/dev/realitycam/packages/shared/src/index.ts` - Exported new attestation types
- `/Users/luca/dev/realitycam/apps/mobile/hooks/useCapture.ts` - Integrated useCaptureAttestation hook, added hash computation and assertion generation
- `/Users/luca/dev/realitycam/apps/mobile/hooks/index.ts` - Exported useCaptureAttestation hook
- `/Users/luca/dev/realitycam/docs/sprint-artifacts/sprint-status.yaml` - Updated story status to review

---

## Senior Developer Review (AI)

### Review Metadata

- **Review Date:** 2025-11-23
- **Reviewer:** Claude (claude-sonnet-4-5-20250929)
- **Review Outcome:** APPROVED
- **Status Update:** review -> done

### Executive Summary

Story 3-4 implements per-capture device attestation signatures as specified. All 8 acceptance criteria are fully implemented with proper code evidence. The implementation correctly uses `@expo/app-integrity` for assertion generation, computes SHA-256 hashes for photo/depth/location binding, and implements graceful degradation when attestation is unavailable. TypeScript compilation passes with no errors. Testing tasks are appropriately deferred to the testing sprint as documented.

### Acceptance Criteria Validation

| AC | Title | Status | Evidence |
|----|-------|--------|----------|
| AC-1 | CaptureAssertion Type Definition | IMPLEMENTED | `capture.ts:189-196` - CaptureAssertion with assertion, clientDataHash, timestamp fields |
| AC-2 | useCaptureAttestation Hook API | IMPLEMENTED | `useCaptureAttestation.ts:32-43` - generateAssertion, isReady, isGenerating, error exposed |
| AC-3 | AssertionMetadata Structure | IMPLEMENTED | `capture.ts:174-183` - photoHash, depthHash, timestamp, locationHash fields |
| AC-4 | Per-Capture Assertion Generation | IMPLEMENTED | `useCaptureAttestation.ts:159-162` - calls generateAssertionAsync(keyId, clientDataHash) |
| AC-5 | RawCapture Type Extension | IMPLEMENTED | `capture.ts:101` - `assertion?: CaptureAssertion` field added |
| AC-6 | useCapture Integration | IMPLEMENTED | `useCapture.ts:298-354` - hash computation and generateAssertion call |
| AC-7 | Attestation-Ready Check | IMPLEMENTED | `useCaptureAttestation.ts:90` - `isReady = isAttested && keyId !== null` |
| AC-8 | Error Handling | IMPLEMENTED | `useCaptureAttestation.ts:175-196` - try-catch with graceful degradation |

### Task Completion Validation

| Task | Status | Evidence |
|------|--------|----------|
| 1.1: Add CaptureAssertion interface | VERIFIED | `capture.ts:189-196` |
| 1.2: Add AssertionMetadata interface | VERIFIED | `capture.ts:174-183` |
| 1.3: Add CaptureAssertionError type | VERIFIED | `capture.ts:201-215` |
| 1.4: Add assertion to RawCapture | VERIFIED | `capture.ts:101` |
| 1.5: Export types from shared index | VERIFIED | `index.ts:26-29` |
| 2.1: Create useCaptureAttestation.ts | VERIFIED | File exists at `apps/mobile/hooks/useCaptureAttestation.ts` |
| 2.2: Import @expo/app-integrity and expo-crypto | VERIFIED | `useCaptureAttestation.ts:19-20` |
| 2.3: Get keyId/isAttested from deviceStore | VERIFIED | `useCaptureAttestation.ts:83` |
| 2.4.1: Build clientDataHash | VERIFIED | `useCaptureAttestation.ts:129-137` |
| 2.4.2: Call generateAssertionAsync | VERIFIED | `useCaptureAttestation.ts:159-162` |
| 2.4.3: Return CaptureAssertion | VERIFIED | `useCaptureAttestation.ts:165-174` |
| 2.5: Implement isReady check | VERIFIED | `useCaptureAttestation.ts:90` |
| 2.6: Implement error handling | VERIFIED | `useCaptureAttestation.ts:138-151, 175-196` |
| 2.7: Return null on failure | VERIFIED | `useCaptureAttestation.ts:121, 150, 195` |
| 3.1: Update useCapture.ts | VERIFIED | File modified with attestation integration |
| 3.2: Import useCaptureAttestation | VERIFIED | `useCapture.ts:28` |
| 3.3: Compute photoHash | VERIFIED | `useCapture.ts:305-312` |
| 3.4: Compute depthHash | VERIFIED | `useCapture.ts:315-319` |
| 3.5: Compute locationHash | VERIFIED | `useCapture.ts:322-330` |
| 3.6: Call generateAssertion | VERIFIED | `useCapture.ts:341` |
| 3.7: Include assertion in RawCapture | VERIFIED | `useCapture.ts:366` |
| 4.1: Export hook from index | VERIFIED | `hooks/index.ts:16` |
| 5.x: Testing tasks | DEFERRED | Appropriately deferred to testing sprint per story |

### Code Quality Assessment

**Architecture Alignment:** GOOD
- Follows established hook pattern from Epic 2
- Uses deviceStore for keyId/isAttested as specified
- Integrates with useCapture via hook composition

**Code Organization:** GOOD
- Clear separation of concerns between useCaptureAttestation (assertion logic) and useCapture (orchestration)
- Proper TypeScript types in shared package
- Comprehensive JSDoc documentation

**Error Handling:** GOOD
- Graceful degradation pattern consistently applied
- Error codes properly typed and descriptive
- Assertion failure never blocks capture (as specified)

**Security:** GOOD
- SHA-256 hashing via expo-crypto (not custom implementation)
- Hash chain includes photo, depth, timestamp, location
- clientDataHash computed from JSON.stringify(metadata) - deterministic

### Test Coverage Assessment

**Current Status:** Tests deferred to testing sprint
- Task 5.1-5.4 explicitly marked as deferred in story
- This is acceptable per BMM workflow (testing stories often run in dedicated sprint)

**Verification Performed:**
- TypeScript compilation: PASS (no errors)
- Shared package typecheck: PASS
- Mobile package typecheck: PASS

### Issues Identified

**CRITICAL:** None

**HIGH:** None

**MEDIUM:** None

**LOW:**
- [ ] [LOW] Consider adding unit tests for hash computation edge cases (empty data, large files) [deferred to testing sprint]
- [ ] [LOW] Consider memoizing the generateAssertion callback dependencies more explicitly [useCapture.ts:408]

### Action Items

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 2 |

### Recommendation

**APPROVED** - All acceptance criteria are implemented with verified code evidence. The implementation correctly follows the technical specification from Epic 3 Tech Spec (AC-3.6). Graceful degradation is properly implemented. Testing tasks are appropriately deferred. LOW severity items are suggestions for future improvement and do not block approval.

---

_Story created by BMAD Create Story Workflow_
_Date: 2025-11-23_
_Epic: 3 - Photo Capture with LiDAR Depth_
_Implementation completed: 2025-11-23_
_Review completed: 2025-11-23_
