# Story 10-3: Software Attestation Rejection

Status: review

## Story

As a **backend service**,
I want **to create an Android device registration endpoint that integrates with the Android Key Attestation service and rejects software-only attestation**,
So that **only Android devices with hardware-backed attestation (TEE or StrongBox) can register, enforcing the security boundary defined in FR72 and enabling secure cross-platform capture support**.

## Context

This story builds on:
- **Story 10-1:** Android Key Attestation Service - implements `verify_android_attestation()`, `validate_security_level()`, and the full ASN.1 parsing pipeline
- **Story 10-2:** Attestation Security Level Extraction - adds `security_level` and `keymaster_security_level` columns to the devices table, exposes security levels in API responses

Story 10-3 focuses on **integrating** the Android attestation service into a device registration endpoint:
1. Create Android-specific device registration flow (platform="android")
2. Invoke `verify_android_attestation()` for certificate chain validation
3. Enforce software-only rejection (FR72) at the registration layer
4. Return clear error messages when devices lack hardware attestation
5. Successfully register TEE/StrongBox devices with security level stored

## Acceptance Criteria

### AC 1: Android Device Registration Request Format
**Given** an Android device sends a registration request
**When** the request is received by POST /api/v1/devices/register
**Then** the endpoint accepts:
```json
{
  "platform": "android",
  "model": "Pixel 8 Pro",
  "has_lidar": false,
  "attestation": {
    "key_id": "base64-encoded-key-identifier",
    "certificate_chain": ["base64-cert-1", "base64-cert-2", "base64-root"],
    "challenge": "base64-encoded-challenge"
  }
}
```

**Key Differences from iOS:**
| Field | iOS | Android |
|-------|-----|---------|
| attestation_object | CBOR-encoded DCAppAttest blob | N/A |
| certificate_chain | N/A | Array of base64 DER certificates |
| has_lidar | true (required for MVP) | false (no LiDAR on Android) |

### AC 2: Platform Routing in Registration Handler
**Given** a device registration request
**When** processing begins
**Then** the handler routes based on platform:
1. `platform = "ios"` -> Existing DCAppAttest verification flow
2. `platform = "android"` -> New Android Key Attestation flow (this story)
3. Other platforms -> Return 400 Bad Request with "unsupported platform"

### AC 3: Android Attestation Verification Integration
**Given** an Android device registration with valid attestation payload
**When** `verify_android_attestation()` is called
**Then**:
1. Certificate chain is parsed and validated to Google root
2. Key Attestation extension is parsed for security level
3. Challenge is validated against ChallengeStore
4. Security level validation occurs (validate_security_level)
5. Public key is extracted for future signature verification
6. On success, `AndroidAttestationResult` is returned with all extracted data

### AC 4: Software-Only Attestation Rejection (FR72)
**Given** an Android device with `attestationSecurityLevel = 0` (Software)
**When** registration is attempted
**Then**:
1. `validate_security_level()` returns `AndroidAttestationError::SoftwareOnlyAttestation`
2. Registration handler catches this specific error
3. Returns HTTP 403 Forbidden (not 401 - device authenticated but unauthorized)
4. Response body:
```json
{
  "error": {
    "code": "ANDROID_SOFTWARE_ONLY_ATTESTATION",
    "message": "Software-only attestation rejected. Device requires TEE or StrongBox hardware security.",
    "details": {
      "attestation_security_level": "software",
      "required_levels": ["trusted_environment", "strongbox"],
      "documentation_url": "https://developer.android.com/privacy-and-security/security-key-attestation"
    }
  },
  "request_id": "uuid"
}
```
5. Device record is NOT created
6. Structured logging captures rejection for monitoring

### AC 5: TEE Attestation Acceptance
**Given** an Android device with `attestationSecurityLevel = 1` (TrustedEnvironment)
**When** registration completes successfully
**Then**:
1. Device is created with:
   - `attestation_level` = "tee"
   - `security_level` = "tee"
   - `keymaster_security_level` = extracted from attestation
   - `platform` = "android"
   - `public_key` = extracted from leaf certificate
2. Response includes:
```json
{
  "data": {
    "device_id": "uuid",
    "attestation_level": "tee",
    "has_lidar": false,
    "security_level": {
      "attestation": "tee",
      "keymaster": "tee",
      "platform": "android"
    }
  },
  "request_id": "uuid"
}
```
3. Log entry indicates MEDIUM trust level accepted

### AC 6: StrongBox Attestation Acceptance
**Given** an Android device with `attestationSecurityLevel = 2` (StrongBox)
**When** registration completes successfully
**Then**:
1. Device is created with:
   - `attestation_level` = "strongbox"
   - `security_level` = "strongbox"
   - `keymaster_security_level` = extracted from attestation
2. Response includes security_level with "strongbox"
3. Log entry indicates HIGH trust level accepted

### AC 7: Certificate Chain Validation Errors
**Given** an Android attestation with invalid certificate chain
**When** any chain validation step fails
**Then** return appropriate error:

| Error | HTTP Status | Code | Message |
|-------|-------------|------|---------|
| InvalidBase64 | 400 | INVALID_ATTESTATION_FORMAT | Invalid base64 encoding in certificate chain |
| InvalidCertificate | 400 | INVALID_ATTESTATION_FORMAT | Invalid X.509 certificate at index N |
| IncompleteCertChain | 400 | INVALID_ATTESTATION_FORMAT | Certificate chain requires at least 2 certificates |
| CertificateExpired | 400 | CERTIFICATE_EXPIRED | Certificate chain contains expired certificate |
| RootCaMismatch | 403 | UNTRUSTED_ATTESTATION | Certificate chain does not root to Google Hardware Attestation CA |
| MissingAttestationExtension | 400 | INVALID_ATTESTATION_FORMAT | Leaf certificate missing Key Attestation extension |

### AC 8: Challenge Validation Errors
**Given** an Android attestation with challenge validation failure
**When** challenge validation fails
**Then** return appropriate error:

| Error | HTTP Status | Code | Message |
|-------|-------------|------|---------|
| ChallengeMismatch | 400 | CHALLENGE_INVALID | Challenge does not match server-issued value |
| ChallengeExpired | 400 | CHALLENGE_EXPIRED | Challenge has expired (5 minute validity) |
| ChallengeNotFound | 400 | CHALLENGE_NOT_FOUND | Challenge not found - request a new challenge |

### AC 9: Attestation Payload Validation
**Given** an Android registration request
**When** validating the attestation payload
**Then**:
1. Require `attestation.certificate_chain` field (array of strings)
2. Require `attestation.challenge` field (base64 string)
3. `attestation.key_id` is optional (extracted from leaf cert if not provided)
4. Validate certificate_chain has at least 2 entries
5. Return 400 Bad Request for missing required fields

### AC 10: Request/Response Type Extensions
**Given** the device registration route handler
**When** processing Android requests
**Then** use extended types:

```rust
/// Android-specific attestation payload
#[derive(Debug, Deserialize)]
pub struct AndroidAttestationPayload {
    /// Optional key identifier (can be derived from leaf cert)
    pub key_id: Option<String>,
    /// Base64-encoded DER certificate chain [leaf, intermediate(s)..., root]
    pub certificate_chain: Vec<String>,
    /// Base64-encoded challenge used for attestation
    pub challenge: String,
}

/// Extended device registration request supporting both platforms
#[derive(Debug, Deserialize)]
pub struct DeviceRegistrationRequest {
    pub platform: String,
    pub model: String,
    pub has_lidar: bool,

    // iOS attestation (existing)
    #[serde(default)]
    pub attestation: Option<AttestationPayload>,

    // Android attestation (new - Story 10-3)
    #[serde(default)]
    pub android_attestation: Option<AndroidAttestationPayload>,

    // Flattened format (backward compatibility)
    // ... existing fields ...
}
```

### AC 11: Database Insertion with Android Fields
**Given** successful Android attestation verification
**When** creating device record
**Then** INSERT includes:
1. `attestation_key_id` = key identifier from leaf cert subject or provided key_id
2. `attestation_chain` = serialized certificate chain (JSON or concatenated DER)
3. `platform` = "android"
4. `public_key` = EC or RSA public key bytes from leaf certificate
5. `assertion_counter` = 0 (Android doesn't use counter like iOS)
6. `security_level` = "strongbox" or "tee"
7. `keymaster_security_level` = from AndroidAttestationResult

### AC 12: Structured Logging for Android Registration
**Given** any Android registration attempt
**When** processing occurs
**Then** log structured events:

```rust
// Success
tracing::info!(
    request_id = %request_id,
    platform = "android",
    security_level = %result.attestation_security_level,
    keymaster_level = %result.keymaster_security_level,
    device_brand = ?result.device_info.brand,
    device_model = ?result.device_info.model,
    os_patch_level = ?result.device_info.os_patch_level,
    "Android device registration successful"
);

// Software rejection
tracing::warn!(
    request_id = %request_id,
    platform = "android",
    device_brand = ?device_info.brand,
    device_model = ?device_info.model,
    reason = "software_only_attestation",
    "Android device registration REJECTED - software attestation"
);

// Chain verification failure
tracing::warn!(
    request_id = %request_id,
    platform = "android",
    error = %error,
    chain_length = cert_chain.len(),
    "Android attestation chain verification failed"
);
```

## Tasks / Subtasks

- [x] Task 1: Extend request types for Android (AC: #1, #10)
  - [x] Add `AndroidAttestationPayload` struct to `routes/devices.rs`
  - [x] Add `android_attestation: Option<AndroidAttestationPayload>` to `DeviceRegistrationRequest`
  - [x] Add `get_android_attestation_data()` method to extract and validate
  - [x] Update request validation to handle Android payloads

- [x] Task 2: Add Android error codes to ApiError (AC: #4, #7, #8)
  - [x] Add `AndroidSoftwareOnlyAttestation` variant to `ApiError` enum
  - [x] Add `AndroidAttestationFailed(String)` variant for general failures
  - [x] Add `AndroidChainVerificationFailed` variant
  - [x] Map to appropriate HTTP status codes (403 for software-only, 400 for format errors)
  - [x] Implement error response serialization with details
  - [x] Define complete error code constants:
    - `ANDROID_SOFTWARE_ONLY_ATTESTATION` - Software-only attestation rejected (403)
    - `ANDROID_ATTESTATION_FAILED` - General attestation failure (400)
    - `ANDROID_CHAIN_VERIFICATION_FAILED` - Certificate chain invalid (400)
    - `UNTRUSTED_ATTESTATION` - Root CA mismatch (403)
    - `CERTIFICATE_EXPIRED` - Certificate in chain expired (400)
    - `CHALLENGE_INVALID` - Challenge mismatch (400)
    - `CHALLENGE_EXPIRED` - Challenge timed out (400)
    - `CHALLENGE_NOT_FOUND` - Challenge not in store (400)

- [x] Task 2.5: Verify Story 10-2 migration is applied (PREREQUISITE)
  - [x] Confirm `security_level` column exists in devices table
  - [x] Confirm `keymaster_security_level` column exists in devices table
  - [x] Run `sqlx migrate info` to verify migration status
  - [x] If migration not applied, run `sqlx migrate run` before proceeding

- [x] Task 3: Implement platform routing in register_device (AC: #2)
  - [x] Add platform detection at start of handler
  - [x] Branch to `register_android_device()` for platform="android"
  - [x] Keep existing iOS flow for platform="ios"
  - [x] Return 400 for unsupported platforms

- [x] Task 4: Implement register_android_device handler (AC: #3, #5, #6, #11)
  - [x] Extract and validate Android attestation payload
  - [x] Decode challenge from base64
  - [x] Call `verify_android_attestation()` with certificate chain and challenge
  - [x] Map `AndroidAttestationResult` to database insert parameters
  - [x] Extract key_id from leaf certificate if not provided
  - [x] Store certificate chain appropriately (JSON array or binary blob)
  - [x] Insert device record with security_level fields
  - [x] Build and return success response

- [x] Task 5: Implement software-only rejection handling (AC: #4)
  - [x] Catch `AndroidAttestationError::SoftwareOnlyAttestation` specifically
  - [x] Return 403 Forbidden with `ANDROID_SOFTWARE_ONLY_ATTESTATION` code
  - [x] Include details: attestation_security_level, required_levels, documentation_url
  - [x] Log rejection with device info for monitoring dashboards
  - [x] Ensure device record is NOT created

- [x] Task 6: Implement error mapping for chain validation (AC: #7)
  - [x] Map `InvalidBase64` -> 400 INVALID_ATTESTATION_FORMAT
  - [x] Map `InvalidCertificate` -> 400 INVALID_ATTESTATION_FORMAT
  - [x] Map `IncompleteCertChain` -> 400 INVALID_ATTESTATION_FORMAT
  - [x] Map `CertificateExpired` -> 400 CERTIFICATE_EXPIRED
  - [x] Map `RootCaMismatch` -> 403 UNTRUSTED_ATTESTATION
  - [x] Map `MissingAttestationExtension` -> 400 INVALID_ATTESTATION_FORMAT

- [x] Task 7: Implement error mapping for challenge validation (AC: #8)
  - [x] Map `ChallengeMismatch` -> 400 CHALLENGE_INVALID
  - [x] Map `ChallengeExpired` -> 400 CHALLENGE_EXPIRED
  - [x] Map `ChallengeNotFound` -> 400 CHALLENGE_NOT_FOUND

- [x] Task 8: Update platform validation (AC: #9)
  - [x] Modify `validate_registration_request()` in devices.rs (currently ~line 200):
    - Current behavior rejects non-iOS platforms immediately
    - Change platform validation from iOS-only rejection to allow both "ios" and "android"
    - Add platform-specific validation AFTER platform routing (not before)
  - [x] In the iOS branch: keep existing has_lidar=true validation
  - [x] In the Android branch:
    - Validate certificate_chain is present and has at least 2 entries
    - Validate challenge is present
    - **Reject has_lidar=true** - Android devices do not have LiDAR; return 400 if Android registration includes has_lidar=true
  - [x] Return 400 Bad Request with "unsupported platform" for platforms other than "ios"/"android"

- [x] Task 9: Add structured logging (AC: #12)
  - [x] Add success logging with all Android-specific fields
  - [x] Add software rejection logging with device info
  - [x] Add chain validation failure logging
  - [x] Add challenge validation failure logging
  - [x] Ensure request_id is included in all logs

- [x] Task 10: Unit tests
  - [x] Test `AndroidAttestationPayload` deserialization
  - [x] Test platform routing (ios vs android vs invalid)
  - [x] Test software-only rejection error response format
  - [x] Test successful TEE registration
  - [x] Test successful StrongBox registration
  - [x] Test chain validation error mapping
  - [x] Test challenge error mapping
  - [x] Test missing required fields validation

- [ ] Task 11: Integration test preparation
  - [ ] Create mock Android attestation certificate chain (TEE level)
  - [ ] Create mock Android attestation certificate chain (StrongBox level)
  - [ ] Create mock software-level attestation (should be rejected)
  - [ ] Document test fixture generation process
  - [ ] Reference test patterns from Story 10-1 unit tests

## Dev Notes

### Technical Approach

**Platform Routing Pattern:**
The existing `register_device` handler processes iOS attestation. This story adds a branch:

```rust
async fn register_device(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Json(req): Json<DeviceRegistrationRequest>,
) -> Result<...> {
    match req.platform.to_lowercase().as_str() {
        "ios" => register_ios_device(state, request_id, req).await,
        "android" => register_android_device(state, request_id, req).await,
        _ => Err(ApiError::Validation("unsupported platform")),
    }
}
```

**Android Registration Flow:**
```
1. Validate request (platform, model, android_attestation present)
2. Decode challenge from base64
3. Call verify_android_attestation(certificate_chain, challenge_store, config, request_id)
   - This internally calls validate_security_level() which rejects Software
4. On success: extract key_id, public_key, security_level
5. Insert device record
6. Return success response with security_level
```

**Error Response Design:**
The software-only rejection error (FR72) should be clearly distinguishable:
- HTTP 403 (Forbidden) - device authenticated but policy violation
- Unique error code for monitoring/alerting
- Actionable message (user needs different device)
- Documentation link for developers

**Certificate Chain Storage:**
Store `certificate_chain` as a JSON-serialized array of base64 strings in the existing `attestation_chain` BYTEA column. Example format:
```json
["MIIBxjCCAW2gAwIB...", "MIICmTCCAj+gAwIB...", "MIIFHDCCAwSgAwIB..."]
```
This matches the input format from registration requests and enables easier debugging/auditing.

**Rate Limiting:**
Android registration uses the same rate limiting as iOS via ChallengeStore (10 challenges/minute/IP). No additional rate limiting configuration needed for this story.

**Rollback Note:**
If implementation fails midway, no database rollback is needed as Android devices are new entries. The existing iOS registration flow remains unchanged and unaffected by partial Android implementation.

### Integration with Story 10-1

Story 10-1 provides the core verification pipeline:
```rust
pub async fn verify_android_attestation(
    certificate_chain_b64: &[String],
    challenge_store: Arc<ChallengeStore>,
    config: &Config,
    request_id: Uuid,
) -> Result<AndroidAttestationResult, AndroidAttestationError>
```

Key functions used:
- `parse_certificate_chain()` - AC7 errors
- `verify_certificate_chain()` - AC7 errors
- `parse_key_attestation_extension()` - AC7 errors
- `validate_security_level()` - AC4 (software rejection)
- `validate_challenge()` - AC8 errors
- `extract_public_key()` - Key extraction

### Integration with Story 10-2

Story 10-2 adds database columns and response types:
- `devices.security_level` column
- `devices.keymaster_security_level` column
- `SecurityLevelResponse` struct for API responses
- `InsertDeviceParams` with security_level fields

This story uses those structures for Android device insertion.

### Security Considerations

**FR72 Enforcement is Critical:**
Software-only attestation can be trivially spoofed. This is a HARD security boundary:
- Log ALL software rejections for monitoring
- Consider alerting on high rejection rates (may indicate attack)
- Never degrade to "unverified" for Android - reject completely

**Why 403 vs 401 for Software Rejection:**
- 401 = authentication failed (identity unknown)
- 403 = authenticated but forbidden (identity known, policy violation)
- Software attestation successfully identifies the device, but policy prohibits registration

**Challenge Replay Prevention:**
Challenge validation in `verify_android_attestation()` marks challenge as consumed.
Even if an attacker captures a valid attestation, replay is prevented.

### File Changes Summary

**Modified Files:**
- `/Users/luca/dev/realitycam/backend/src/routes/devices.rs` - Main changes:
  - Add `AndroidAttestationPayload` struct
  - Update `DeviceRegistrationRequest` with android_attestation field
  - Add platform routing logic
  - Add `register_android_device()` handler function
  - Update validation to allow android platform
- `/Users/luca/dev/realitycam/backend/src/error.rs` - Add Android-specific error variants:
  - `AndroidSoftwareOnlyAttestation`
  - `AndroidAttestationFailed(String)`
  - Map to HTTP status codes

**New Files:**
- None (all changes in existing files)

### Testing Strategy

**Unit Tests:**
1. Request deserialization (both iOS and Android formats)
2. Platform routing logic
3. Error code mapping for all AndroidAttestationError variants
4. Response format validation
5. Security level string conversion

**Integration Tests:**
1. Full Android registration with mock TEE attestation
2. Full Android registration with mock StrongBox attestation
3. Software-only rejection (verify 403 response)
4. Invalid certificate chain (verify 400 response)
5. Challenge errors (verify 400 responses)
6. Ensure iOS registration still works (backward compatibility)

**Mock Attestation Chains:**
Generate test certificates using:
- openssl for certificate generation
- Manually constructed KeyDescription extension
- Self-signed test root (not Google root - acceptable in test mode with strict=false)

### References

- [Story 10-1: Android Key Attestation Service](./10-1-android-key-attestation-service.md) - Foundation service
- [Story 10-2: Attestation Security Level Extraction](./10-2-attestation-security-level-extraction.md) - Database schema and response types
- [Source: backend/src/services/android_attestation.rs] - verify_android_attestation(), validate_security_level()
- [Source: backend/src/routes/devices.rs] - Existing iOS registration flow
- [Source: docs/prd.md#FR72] - "Backend rejects software-only attestation"
- [Android Key Attestation Docs](https://developer.android.com/privacy-and-security/security-key-attestation)

### Related Stories

- Story 10-1: Android Key Attestation Service - PREREQUISITE (provides verification service)
- Story 10-2: Attestation Security Level Extraction - PREREQUISITE (provides database schema)
- Story 10-4: Unified Evidence Model - BACKLOG (evidence schema with platform awareness)
- Story 10-5: Database Migration for Android - BACKLOG (may be merged into this story if needed)
- Story 10-6: Backward Compatibility - BACKLOG (ensure existing iOS captures unaffected)

---

_Story created: 2025-12-11_
_Epic: 10 - Cross-Platform Foundation_
_FR Coverage: FR72 (Software-only attestation rejection), FR70 (Android Key Attestation verification - integration)_
_Depends on: Story 10-1 (Android Key Attestation Service), Story 10-2 (Attestation Security Level Extraction)_
_Enables: Epic 12 (Android Native App - device registration ready)_

## Dev Agent Record

### Context Reference

Created from:
- docs/epics.md - Epic 10 definition, FR70-FR75 mapping
- docs/prd.md - FR72 "Backend rejects software-only attestation", Android Platform Requirements
- docs/sprint-artifacts/stories/10-1-android-key-attestation-service.md - Foundation service details
- docs/sprint-artifacts/stories/10-2-attestation-security-level-extraction.md - Database schema and response types
- backend/src/services/android_attestation.rs - verify_android_attestation(), AndroidAttestationError, SecurityLevel
- backend/src/routes/devices.rs - Existing iOS registration flow, DeviceRegistrationRequest

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story not yet implemented

### File List

**To Modify:**
- `/Users/luca/dev/realitycam/backend/src/routes/devices.rs` - Add Android registration handler, request types
- `/Users/luca/dev/realitycam/backend/src/error.rs` - Add Android-specific error variants
