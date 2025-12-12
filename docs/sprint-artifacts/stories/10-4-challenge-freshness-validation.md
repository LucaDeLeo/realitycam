# Story 10-4: Challenge Freshness Validation

Status: review

## Story

As a **backend service**,
I want **to ensure challenge validation in Android registration properly enforces freshness (5-minute window) and single-use consumption**,
So that **replay attacks are prevented, each challenge can only be used once, and the challenge-response flow provides cryptographic freshness guarantees for Android Key Attestation**.

## Context

This story is part of Epic 10: Cross-Platform Foundation, focusing on FR73: "Challenge nonce validated for freshness (5-minute window) and single-use."

**Prerequisites (already implemented):**
- **Story 10-1:** Android Key Attestation Service - includes `validate_challenge()` function that calls `ChallengeStore::verify_and_consume()`
- **Story 10-3:** Software Attestation Rejection - Android registration endpoint (`register_android_device`) that routes to `verify_android_attestation()`
- **ChallengeStore:** In `backend/src/services/challenge_store.rs` - provides challenge generation, verification, and consumption

**Current Implementation Analysis:**
The existing `ChallengeStore` already implements:
1. Challenge generation with 5-minute TTL (`CHALLENGE_TTL_MINUTES = 5`)
2. Single-use enforcement via `used: bool` flag
3. Rate limiting (10 challenges/minute/IP)
4. Background cleanup of expired challenges

The `validate_challenge()` function in `android_attestation.rs` calls `challenge_store.verify_and_consume()` which:
1. Looks up challenge in store
2. Returns `ChallengeError::NotFound` if not found
3. Returns `ChallengeError::AlreadyUsed` if already consumed
4. Returns `ChallengeError::Expired` if past expiry time
5. Marks challenge as `used = true` on success

**This Story's Focus:**
While the core mechanics exist, this story ensures:
1. Challenge validation is properly integrated in the Android registration flow
2. Error handling provides clear, actionable feedback
3. Challenge consumption is atomic (no race conditions)
4. Logging captures challenge lifecycle for security auditing
5. Test coverage validates all freshness and single-use scenarios
6. Documentation explains the challenge-response security model

## Acceptance Criteria

### AC 1: Challenge Generation Endpoint Provides Fresh Challenges
**Given** an Android client requests a challenge via `GET /api/v1/devices/challenge`
**When** the challenge is generated
**Then**:
1. A cryptographically secure 32-byte random challenge is generated (`OsRng`)
2. Challenge is stored in `ChallengeStore` with:
   - `expires_at` = current time + 5 minutes
   - `used` = false
3. Response includes:
   ```json
   {
     "data": {
       "challenge": "base64-encoded-32-bytes",
       "expires_at": "2025-12-11T15:30:00Z"
     },
     "request_id": "uuid"
   }
   ```
4. Rate limiting is enforced (10 challenges/minute/IP)

### AC 2: Challenge Validation Enforces 5-Minute Freshness Window
**Given** an Android device attempts registration with a challenge
**When** the challenge is validated in `verify_android_attestation()`
**Then**:
1. If challenge was issued less than 5 minutes ago -> validation passes
2. If challenge was issued more than 5 minutes ago -> `ChallengeError::Expired` is returned
3. The expiry check uses `Utc::now() > entry.expires_at` (UTC timestamps)
4. Clock skew tolerance is NOT applied (strict 5-minute window)

**Boundary Cases:**
- Challenge issued at T, used at T+4:59 -> PASS
- Challenge issued at T, used at T+5:00 -> PASS (code uses `>` not `>=`, so exactly at expiry passes)
- Challenge issued at T, used at T+5:01 -> FAIL (Expired)

### AC 3: Challenge Validation Enforces Single-Use
**Given** a valid challenge that has not been used
**When** Android registration uses the challenge
**Then**:
1. First use: Challenge is marked as `used = true`, registration proceeds
2. Second use (same challenge): `ChallengeError::AlreadyUsed` is returned
3. The `used` flag is set atomically within the write lock
4. No race condition allows double-use of the same challenge

### AC 4: Challenge Consumption is Atomic
**Given** two concurrent registration requests with the same challenge
**When** both attempt to validate the challenge simultaneously
**Then**:
1. Only ONE request succeeds (first to acquire write lock)
2. The other request receives `ChallengeError::AlreadyUsed`
3. No device is registered with a reused challenge
4. This is enforced by `RwLock<HashMap>` in `ChallengeStore`

### AC 5: Challenge Not Found Handling
**Given** an Android device attempts registration with a challenge not in the store
**When** challenge validation is attempted
**Then**:
1. `ChallengeError::NotFound` is returned
2. This can occur when:
   - Challenge was never issued
   - Challenge was already cleaned up (expired + cleanup ran)
   - Challenge value was fabricated by attacker
3. API returns 400 Bad Request with `CHALLENGE_NOT_FOUND` code

### AC 6: Challenge Error Mapping to API Responses
**Given** any challenge validation error
**When** error is propagated to the API response
**Then** errors map correctly:

| ChallengeError | HTTP Status | Error Code | Message |
|----------------|-------------|------------|---------|
| NotFound | 400 | CHALLENGE_NOT_FOUND | Challenge not found - request a new challenge |
| AlreadyUsed | 400 | CHALLENGE_INVALID | Challenge already used - request a new challenge |
| Expired | 400 | CHALLENGE_EXPIRED | Challenge has expired (5 minute validity) |
| RateLimitExceeded | 429 | TOO_MANY_REQUESTS | Rate limit exceeded - try again later |

### AC 7: Challenge Validation Logging
**Given** challenge validation occurs during Android registration
**When** validation succeeds or fails
**Then** structured logging captures:

**Success (guideline format - actual implementation may vary):**
```rust
tracing::info!(
    request_id = %request_id,
    status = "pass",
    "Challenge verified and consumed"
);
```

**Failure (guideline format - actual implementation may vary):**
```rust
tracing::warn!(
    request_id = %request_id,
    status = "fail",
    reason = "expired" | "already_used" | "not_found",
    "Challenge validation failed"
);
```

### AC 8: Background Cleanup of Expired Challenges
**Given** the challenge store contains expired challenges
**When** the background cleanup task runs (every 60 seconds)
**Then**:
1. All challenges with `expires_at < now` are removed
2. Used but not-yet-expired challenges are retained (audit trail)
3. Cleanup is logged: `tracing::debug!(removed = N, "Cleaned up expired challenges")`
4. Rate limit entries older than 5 minutes are also cleaned

### AC 9: Integration with Android Attestation Flow
**Given** `verify_android_attestation()` is called with a certificate chain
**When** challenge validation step executes
**Then**:
1. `attestationChallenge` is extracted from `KeyDescription` in the certificate
2. Challenge must be exactly 32 bytes
3. `validate_challenge()` is called with:
   - `key_description` containing the challenge bytes
   - `challenge_store` Arc reference
   - `request_id` for logging correlation
4. On success, verification continues to next step
5. On failure, `AndroidAttestationError` is returned immediately

### AC 10: Unit Test Coverage for Challenge Freshness
**Given** the challenge validation code
**When** unit tests run
**Then** the following scenarios are covered:
1. Valid challenge within 5-minute window -> success
2. Expired challenge (>5 minutes) -> `ChallengeError::Expired`
3. Already-used challenge -> `ChallengeError::AlreadyUsed`
4. Unknown challenge -> `ChallengeError::NotFound`
5. Invalid challenge length (!= 32 bytes) -> error
6. Concurrent access (race condition prevention)
7. Rate limiting enforcement
8. Cleanup removes expired challenges

## Tasks / Subtasks

- [x] Task 1: Verify existing ChallengeStore implementation (AC: #1, #2, #3, #4, #8)
  - [x] Review `backend/src/services/challenge_store.rs` for correctness
  - [x] Verify `CHALLENGE_TTL_MINUTES = 5` constant
  - [x] Verify `verify_and_consume()` marks challenge as used atomically
  - [x] Verify cleanup task removes expired challenges
  - [x] Document any gaps or issues found

- [x] Task 2: Verify validate_challenge() in Android attestation (AC: #9)
  - [x] Review `validate_challenge()` in `android_attestation.rs`
  - [x] Verify challenge bytes extraction from KeyDescription
  - [x] Verify 32-byte length validation
  - [x] Verify proper error mapping from ChallengeError to AndroidAttestationError
  - [x] Ensure logging includes request_id

- [x] Task 3: Verify challenge error mapping in devices.rs (AC: #6)
  - [x] Review `map_android_attestation_error()` function
  - [x] Verify ChallengeMismatch -> CHALLENGE_INVALID
  - [x] Verify ChallengeExpired -> CHALLENGE_EXPIRED
  - [x] Verify ChallengeNotFound -> CHALLENGE_NOT_FOUND
  - [x] Ensure HTTP status codes are correct (400 for all challenge errors)

- [x] Task 4: Add/enhance logging for challenge lifecycle (AC: #7)
  - [x] Add structured logging in `verify_and_consume()` for success path
  - [x] Add structured logging for each failure reason
  - [x] Ensure request_id propagation through challenge validation
  - [x] Add logging in cleanup task for removed challenges count

- [x] Task 5: Unit tests for challenge freshness scenarios (AC: #10)
  - [x] Test: Challenge used within 5 minutes -> success
  - [x] Test: Challenge used at exactly 5 minutes -> boundary check
  - [x] Test: Challenge used after 5 minutes -> Expired error
  - [x] Test: Challenge reuse attempt -> AlreadyUsed error
  - [x] Test: Unknown challenge -> NotFound error
  - [x] Test: Invalid challenge length -> error handling
  - [x] Test: Cleanup removes only expired challenges
  - [x] Test: Rate limiting blocks excessive requests

- [x] Task 6: Concurrent access test (AC: #4)
  - [x] Create test that spawns multiple tasks using same challenge
  - [x] Verify only one succeeds, others get AlreadyUsed
  - [x] Use `tokio::spawn` for concurrent execution
  - [x] Verify no race conditions with RwLock

- [x] Task 7: Integration test for challenge flow (AC: #1, #2, #3, #9)
  - [x] Test: Generate challenge -> use in registration within 5 min -> success
  - [x] Test: Generate challenge -> wait 5+ minutes -> use -> expired
  - [x] Test: Generate challenge -> use twice -> second fails
  - [x] Test: Fabricate challenge (not generated) -> not found
  - [x] Reference Story 10-1 test fixtures for mock certificate generation (see 10-1-android-key-attestation-service.md)

- [x] Task 8: Documentation update
  - [x] Document challenge-response security model in CLAUDE.md or architecture doc
  - [x] Document Android registration flow with challenge step
  - [x] Document error codes and recovery actions for clients

## Dev Notes

### Technical Analysis of Existing Implementation

**ChallengeStore (challenge_store.rs):**
The existing implementation is solid and meets FR73 requirements:

```rust
// Constants
const CHALLENGE_TTL_MINUTES: i64 = 5;  // 5-minute freshness window
const RATE_LIMIT_MAX: u32 = 10;        // 10 challenges/minute/IP
const RATE_LIMIT_WINDOW_MINUTES: i64 = 1;

// ChallengeEntry tracks used state
pub struct ChallengeEntry {
    pub challenge: [u8; 32],
    pub expires_at: DateTime<Utc>,
    pub used: bool,  // Single-use enforcement
}

// verify_and_consume() is atomic via RwLock
pub async fn verify_and_consume(&self, challenge: &[u8; 32]) -> Result<(), ChallengeError> {
    let mut challenges = self.challenges.write().await;  // Write lock
    let entry = challenges.get_mut(challenge).ok_or(ChallengeError::NotFound)?;
    if entry.used { return Err(ChallengeError::AlreadyUsed); }
    if Utc::now() > entry.expires_at { return Err(ChallengeError::Expired); }
    entry.used = true;  // Mark consumed
    Ok(())
}
```

**validate_challenge() (android_attestation.rs):**
Already implemented in Story 10-1:

```rust
pub async fn validate_challenge(
    key_description: &KeyDescription,
    challenge_store: Arc<ChallengeStore>,
    request_id: uuid::Uuid,
) -> Result<(), AndroidAttestationError> {
    let challenge_bytes = &key_description.attestation_challenge;

    // Challenge must be exactly 32 bytes
    if challenge_bytes.len() != 32 {
        return Err(AndroidAttestationError::ChallengeMismatch);
    }

    let challenge: [u8; 32] = challenge_bytes.as_slice().try_into()...;

    // Verify and consume the challenge
    match challenge_store.verify_and_consume(&challenge).await {
        Ok(()) => Ok(()),
        Err(ChallengeError::NotFound) => Err(AndroidAttestationError::ChallengeNotFound),
        Err(ChallengeError::AlreadyUsed) => Err(AndroidAttestationError::ChallengeMismatch),
        Err(ChallengeError::Expired) => Err(AndroidAttestationError::ChallengeExpired),
        // RateLimitExceeded maps to ChallengeMismatch because: rate limiting during verify_and_consume()
        // indicates an attack pattern (rapid replay attempts). ChallengeMismatch is a generic client-facing
        // error that doesn't reveal internal rate limiting details to potential attackers.
        Err(ChallengeError::RateLimitExceeded) => Err(AndroidAttestationError::ChallengeMismatch),
    }
}
```

### What This Story Validates/Enhances

1. **Verification:** Confirm existing code meets FR73 exactly
2. **Logging Enhancement:** Add structured logging for audit trail
3. **Test Coverage:** Comprehensive tests for all challenge scenarios
4. **Documentation:** Clear security model documentation

### Security Model: Challenge-Response for Android Key Attestation

The challenge-response flow prevents replay attacks:

```
Client                              Server
  |                                    |
  |-- GET /devices/challenge --------->|
  |                                    | Generate 32-byte random challenge
  |                                    | Store in ChallengeStore (TTL=5min)
  |<---- { challenge, expires_at } ----|
  |                                    |
  | Generate keypair with challenge    |
  | setAttestationChallenge(challenge) |
  | KeyPairGenerator.generateKeyPair() |
  |                                    |
  |-- POST /devices/register --------->|
  |    { certificate_chain... }        | Extract challenge from cert extension
  |                                    | Verify challenge in ChallengeStore
  |                                    | Mark challenge as USED (single-use)
  |                                    | Continue with attestation verification
  |<---- { device_id, ... } -----------|
```

**Why This Matters:**
- **Freshness:** Challenge ensures attestation was created recently (not replayed from past)
- **Single-Use:** Each challenge can only be used once (prevents replay of valid attestation)
- **Server-Bound:** Challenge is server-generated (attacker can't predict or forge)
- **Cryptographic Binding:** Challenge is embedded in attestation certificate by Android OS

### File Changes Summary

**Files to Review/Verify (minimal changes expected):**
- `/Users/luca/dev/realitycam/backend/src/services/challenge_store.rs` - Existing implementation
- `/Users/luca/dev/realitycam/backend/src/services/android_attestation.rs` - validate_challenge()
- `/Users/luca/dev/realitycam/backend/src/routes/devices.rs` - Error mapping

**Files to Enhance:**
- Add logging enhancements if gaps found
- Add test file: `/Users/luca/dev/realitycam/backend/src/services/challenge_store.rs` (existing tests)
- May add integration test: `/Users/luca/dev/realitycam/backend/tests/android_registration_challenge.rs`

### Testing Strategy

**Unit Tests (in challenge_store.rs):**
Existing tests cover basic scenarios. Additional tests needed:
1. Boundary test: 5-minute exactly
2. Concurrent access test (tokio::spawn multiple tasks)

**Integration Tests:**
1. Full flow: challenge -> mock attestation -> registration
2. Expired flow: challenge -> wait -> registration fails
3. Replay flow: challenge -> registration -> same challenge again fails

**Test Fixtures:**
Reference mock certificate generation from Story 10-1 tests.

### References

- [Story 10-1: Android Key Attestation Service](./10-1-android-key-attestation-service.md) - Foundation with validate_challenge()
- [Story 10-3: Software Attestation Rejection](./10-3-software-attestation-rejection.md) - Android registration endpoint
- [Source: backend/src/services/challenge_store.rs] - ChallengeStore implementation
- [Source: backend/src/services/android_attestation.rs] - validate_challenge() function
- [Source: docs/prd.md#FR73] - "Challenge nonce validated for freshness (5-minute window) and single-use"
- [Android Key Attestation Docs](https://developer.android.com/privacy-and-security/security-key-attestation)

### Related Stories

- Story 10-1: Android Key Attestation Service - COMPLETED (foundation)
- Story 10-2: Attestation Security Level Extraction - COMPLETED (database schema)
- Story 10-3: Software Attestation Rejection - REVIEW (Android registration endpoint)
- Story 10-5: Unified Evidence Model - BACKLOG (evidence schema expansion)
- Story 10-6: Backward Compatibility - BACKLOG (migration for existing captures)

---

_Story created: 2025-12-11_
_Epic: 10 - Cross-Platform Foundation_
_FR Coverage: FR73 (Challenge freshness validation - time-bound nonces, single-use)_
_Depends on: Story 10-1 (validate_challenge function), Story 10-3 (Android registration endpoint), ChallengeStore_
_Enables: Secure Android device registration with replay attack prevention_

## Dev Agent Record

### Context Reference

Created from:
- docs/epics.md - Epic 10 definition, FR73 mapping
- docs/prd.md - FR73 "Challenge nonce validated for freshness (5-minute window) and single-use"
- backend/src/services/challenge_store.rs - ChallengeStore implementation with TTL and single-use
- backend/src/services/android_attestation.rs - validate_challenge() function
- backend/src/routes/devices.rs - Challenge endpoint and error mapping
- docs/sprint-artifacts/stories/10-1-android-key-attestation-service.md - Foundation story
- docs/sprint-artifacts/stories/10-3-software-attestation-rejection.md - Android registration endpoint

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story not yet implemented

### File List

**To Review/Verify:**
- `/Users/luca/dev/realitycam/backend/src/services/challenge_store.rs`
- `/Users/luca/dev/realitycam/backend/src/services/android_attestation.rs`
- `/Users/luca/dev/realitycam/backend/src/routes/devices.rs`

**To Enhance (if gaps found):**
- Logging additions in above files

**To Create:**
- `/Users/luca/dev/realitycam/backend/tests/android_registration_challenge.rs` (integration test)
