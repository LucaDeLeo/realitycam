# Story 10-2: Attestation Security Level Extraction

Status: ready-for-dev

## Story

As a **backend service**,
I want **to expose attestation security level in API responses and the evidence model**,
So that **Android device registration responses include security level, evidence packages track attestation strength, and frontends can display platform-specific attestation information**.

## Context

Story 10-1 implemented the Android Key Attestation service including:
- `SecurityLevel` enum (Software/TrustedEnvironment/StrongBox)
- `parse_key_attestation_extension()` for ASN.1 parsing
- `KeyDescription` ASN.1 structure parsing
- `AndroidAttestationResult` with security level fields
- Challenge validation and public key extraction

This story (10-2) focuses on **exposing** these security levels in:
1. Device registration response (Android devices report TEE/StrongBox level)
2. Evidence model (captures store attestation security level)
3. API responses (verification pages show attestation strength)

## Acceptance Criteria

### AC 1: Device Registration Response Includes Security Level
**Given** an Android device registers with valid TEE or StrongBox attestation
**When** the registration succeeds
**Then** the response includes:
```json
{
  "data": {
    "device_id": "uuid",
    "attestation_level": "strongbox",  // or "tee" or "secure_enclave" (iOS)
    "has_lidar": false,
    "security_level": {
      "attestation": "strongbox",      // StrongBox/TrustedEnvironment
      "keymaster": "strongbox",        // KeyMaster security level
      "platform": "android"
    }
  }
}
```

**Security Level Values:**
| Platform | attestation_level | security_level.attestation | Trust |
|----------|------------------|---------------------------|-------|
| iOS | secure_enclave | secure_enclave | HIGH |
| Android | strongbox | strongbox | HIGH |
| Android | tee | trusted_environment | MEDIUM |
| Any | unverified | unverified | REJECTED |

### AC 2: Database Schema Extension for Security Level
**Given** the devices table schema
**When** Story 10-2 migration runs
**Then** the devices table has:
```sql
ALTER TABLE devices
ADD COLUMN IF NOT EXISTS security_level TEXT;  -- "strongbox", "tee", "secure_enclave"

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS keymaster_security_level TEXT;  -- Android-specific

COMMENT ON COLUMN devices.security_level IS 'Hardware security level: strongbox (Android HSM), tee (Android TEE), secure_enclave (iOS)';
COMMENT ON COLUMN devices.keymaster_security_level IS 'Android KeyMaster security level (may differ from attestation level)';
```

### AC 3: Evidence Model Extension for Attestation Security Level
**Given** the evidence package structure
**When** a capture is processed
**Then** the hardware_attestation section includes security level details:
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareAttestation {
    pub status: CheckStatus,
    pub level: AttestationLevel,
    pub device_model: String,
    pub assertion_verified: bool,
    pub counter_valid: bool,
    // New fields for Story 10-2:
    pub security_level: Option<SecurityLevelInfo>,  // Detailed security level
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityLevelInfo {
    pub attestation_level: String,      // "strongbox", "tee", "secure_enclave"
    pub keymaster_level: Option<String>, // Android-only
    pub platform: String,               // "ios" or "android"
}
```

### AC 4: Device Model Update to Include Security Level
**Given** the Device model in `backend/src/models/device.rs`
**When** reading/writing devices
**Then** the model includes:
```rust
pub struct Device {
    // ... existing fields ...

    /// Hardware security level: "strongbox", "tee", "secure_enclave"
    /// NULL for unverified devices
    pub security_level: Option<String>,

    /// Android KeyMaster security level (may differ from attestation level)
    /// NULL for iOS devices
    pub keymaster_security_level: Option<String>,
}
```

### AC 5: Android Device Registration Flow Integration
**Given** an Android device sends Key Attestation certificate chain
**When** `verify_android_attestation()` succeeds (Story 10-1)
**Then** the registration endpoint:
1. Extracts `attestation_security_level` from `AndroidAttestationResult`
2. Maps SecurityLevel enum to database string:
   - `SecurityLevel::StrongBox` -> "strongbox"
   - `SecurityLevel::TrustedEnvironment` -> "tee"
3. Stores both `security_level` and `keymaster_security_level`
4. Sets `attestation_level` = security level string for consistency
5. Returns security level in response

### AC 6: iOS Device Registration Backward Compatibility
**Given** an existing iOS device registers
**When** DCAppAttest verification succeeds
**Then**:
1. `security_level` = "secure_enclave"
2. `keymaster_security_level` = NULL (iOS-specific field not used)
3. `attestation_level` = "secure_enclave" (unchanged)
4. Response includes `security_level` in same format as Android

### AC 7: Evidence Package Security Level Population
**Given** a capture is uploaded from an Android or iOS device
**When** evidence is generated
**Then** `hardware_attestation.security_level` is populated from device record:
```json
{
  "hardware_attestation": {
    "status": "pass",
    "level": "strongbox",
    "device_model": "Pixel 8 Pro",
    "assertion_verified": true,
    "counter_valid": true,
    "security_level": {
      "attestation_level": "strongbox",
      "keymaster_level": "strongbox",
      "platform": "android"
    }
  }
}
```

### AC 8: GET /api/v1/captures/{id} Response Enhancement
**Given** a verified capture exists
**When** fetching capture details
**Then** response includes attestation security level:
```json
{
  "data": {
    "id": "uuid",
    "confidence_level": "high",
    "evidence": {
      "hardware_attestation": {
        "status": "pass",
        "level": "strongbox",
        "device_model": "Pixel 8 Pro",
        "security_level": {
          "attestation_level": "strongbox",
          "keymaster_level": "strongbox",
          "platform": "android"
        }
      }
    }
  }
}
```

### AC 9: Unit Tests for Security Level Integration
**Given** the security level integration code
**When** unit tests run
**Then**:
1. Test SecurityLevel -> string mapping
2. Test device insertion with security_level
3. Test evidence package serialization with security_level
4. Test backward compatibility (old devices without security_level)
5. Test iOS and Android security level handling

## Tasks / Subtasks

- [ ] Task 1: Database migration for security_level columns (AC: #2)
  - [ ] Create migration file (use actual timestamp, e.g., `YYYYMMDDHHMMSS_add_security_level_fields.sql`)
    - Note: Run `sqlx migrate add add_security_level_fields` to auto-generate filename with correct timestamp
  - [ ] Add `security_level` column (nullable TEXT)
  - [ ] Add `keymaster_security_level` column (nullable TEXT)
  - [ ] Add column comments
  - [ ] Run `cargo sqlx prepare` to update offline cache

- [ ] Task 2: Update Device model (AC: #4)
  - [ ] Add `security_level: Option<String>` to Device struct
  - [ ] Add `keymaster_security_level: Option<String>` to Device struct
  - [ ] Update all SQLx queries that SELECT from devices
  - [ ] Verify compile-time query checks pass

- [ ] Task 3: Add SecurityLevelInfo to evidence model (AC: #3)
  - [ ] Create `SecurityLevelInfo` struct in `backend/src/models/evidence.rs`
  - [ ] Add `security_level: Option<SecurityLevelInfo>` to `HardwareAttestation`
  - [ ] Extend `AttestationLevel` enum with `StrongBox` and `TrustedEnvironment` variants
    - Use `#[serde(rename = "strongbox")]` and `#[serde(rename = "tee")]` for correct JSON serialization
  - [ ] Implement Default for SecurityLevelInfo
  - [ ] Add serialization tests

- [ ] Task 4: Update device registration response (AC: #1, #5, #6)
  - [ ] Add `SecurityLevelResponse` struct to `backend/src/routes/devices.rs`
  - [ ] Update `DeviceRegistrationResponse` to include security_level
  - [ ] Map `SecurityLevel` enum to string in registration handler
  - [ ] Add `SecurityLevel::as_str()` helper method in `backend/src/services/android_attestation.rs`
  - [ ] Handle iOS devices (set security_level = "secure_enclave")
  - [ ] Handle Android devices (set from AndroidAttestationResult)

- [ ] Task 5: Update device insertion SQL (AC: #5, #6)
  - [ ] Modify `insert_device()` in `routes/devices.rs`
  - [ ] Add security_level and keymaster_security_level parameters
  - [ ] Update INSERT query to include new columns

- [ ] Task 6: Update evidence generation (AC: #7)
  - [ ] Modify `build_hardware_attestation()` in `backend/src/services/evidence.rs`
    - If function doesn't exist, locate where `HardwareAttestation` is constructed from `Device` record in `backend/src/routes/captures.rs`
  - [ ] Populate `SecurityLevelInfo` from device record
  - [ ] Handle devices without security_level (backward compatibility)

- [ ] Task 7: Update GET /captures/{id} response (AC: #8)
  - [ ] Ensure evidence serialization includes security_level
  - [ ] Verify JSON response format matches AC #8

- [ ] Task 8: Update existing iOS registration flow (AC: #6)
  - [ ] Modify iOS attestation success path
  - [ ] Set security_level = "secure_enclave" for verified iOS devices
  - [ ] Ensure backward compatibility with existing devices

- [ ] Task 9: Unit tests (AC: #9)
  - [ ] Test SecurityLevel string mapping
  - [ ] Test SecurityLevelInfo serialization
  - [ ] Test device model with security_level
  - [ ] Test evidence package with security_level
  - [ ] Test backward compatibility (NULL security_level)

- [ ] Task 10: Integration test preparation
  - [ ] Create test for Android registration with security level
  - [ ] Create test for iOS registration with security level
  - [ ] Create test for capture evidence with security level
  - [ ] Reference Android attestation test fixtures (mock certificate chains) from Story 10-1 tests in `backend/tests/` or `backend/src/services/android_attestation.rs` unit tests

## Dev Notes

### Technical Approach

**SecurityLevel Enum to String Mapping:**
The `SecurityLevel` enum from Story 10-1 needs consistent string representation:

```rust
impl SecurityLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            SecurityLevel::Software => "software",      // Should never be stored (rejected)
            SecurityLevel::TrustedEnvironment => "tee",
            SecurityLevel::StrongBox => "strongbox",
        }
    }
}
```

For iOS, we use "secure_enclave" as the security level string.

**Database Column Design:**
- `security_level`: Primary hardware security indicator (strongbox/tee/secure_enclave)
- `keymaster_security_level`: Android-specific KeyMaster level (may differ from attestation level)
- Both nullable for backward compatibility with existing devices

**Evidence Model Design:**
The `SecurityLevelInfo` struct provides detailed security information for verification pages:
- Frontend can show "Verified by StrongBox hardware security module"
- Platform indicator helps explain iOS vs Android attestation differences
- KeyMaster level provides additional Android-specific context

**Backward Compatibility:**
- Existing devices have NULL security_level
- Evidence generation handles NULL gracefully (omits security_level field)
- No migration of existing data needed (devices re-register rarely)

### File Changes Summary

**New Files:**
- `/Users/luca/dev/realitycam/backend/migrations/<timestamp>_add_security_level_fields.sql`

**Modified Files:**
- `/Users/luca/dev/realitycam/backend/src/models/device.rs` - Add security_level fields
- `/Users/luca/dev/realitycam/backend/src/models/evidence.rs` - Add SecurityLevelInfo struct, extend AttestationLevel enum
- `/Users/luca/dev/realitycam/backend/src/routes/devices.rs` - Update response and insertion
- `/Users/luca/dev/realitycam/backend/src/services/android_attestation.rs` - Add SecurityLevel::as_str() helper
- `/Users/luca/dev/realitycam/backend/src/services/evidence.rs` or `/Users/luca/dev/realitycam/backend/src/routes/captures.rs` - Update evidence generation

**Queries to Update:**
1. INSERT INTO devices (in register_device)
2. SELECT FROM devices (all queries returning Device)
3. Evidence generation (populate from device)

### Security Considerations

**Security Level Trust Hierarchy:**
```
StrongBox (Android HSM) = Secure Enclave (iOS) > TEE (Android) > Software (REJECTED)
```

- StrongBox and Secure Enclave provide equivalent HIGH trust
- TEE provides MEDIUM trust (acceptable but noted)
- Software is always REJECTED (Story 10-1 handles this)

**Information Disclosure:**
- Security level is public information (shown on verification page)
- Does not expose device-identifying information
- Helps users understand attestation strength

### Testing Strategy

**Unit Tests:**
1. SecurityLevel::as_str() mapping
2. SecurityLevelInfo serialization/deserialization
3. Device model with optional security_level
4. Evidence package calculate_confidence with security level
5. Backward compatibility (existing evidence without security_level)

**Integration Tests:**
1. Full Android registration flow with security level extraction
2. Full iOS registration flow with secure_enclave level
3. Capture upload and evidence generation with security level
4. GET /captures/{id} response format validation

### References

- [Story 10-1: Android Key Attestation Service](./10-1-android-key-attestation-service.md) - Foundation for this story
- [Source: backend/src/services/android_attestation.rs] - SecurityLevel enum, AndroidAttestationResult
- [Source: backend/src/models/evidence.rs] - Evidence model patterns
- [Source: backend/src/routes/devices.rs] - Device registration flow
- [Source: docs/prd.md#FR71] - "Backend extracts attestation security level (StrongBox/TEE/Software)"

### Related Stories

- Story 10-1: Android Key Attestation Service - COMPLETED (foundation)
- Story 10-3: Unified Device Registration Endpoint - BACKLOG (uses security level)
- Story 10-4: Evidence Model Expansion - BACKLOG (extends evidence schema)
- Story 11-1: Platform Indicator Display - BACKLOG (shows security level in UI)

---

_Story created: 2025-12-11_
_Epic: 10 - Cross-Platform Foundation_
_FR Coverage: FR71 (Attestation security level extraction), FR74 (Unified evidence model)_
_Depends on: Story 10-1 (Android Key Attestation Service)_
_Enables: Story 10-3 (Unified Device Registration), Story 11-1 (Platform Indicator Display)_

## Dev Agent Record

### Context Reference

Created from:
- docs/epics.md - Epic 10 definition, FR70-FR75 mapping
- docs/prd.md - FR71 "Backend extracts attestation security level (StrongBox/TEE/Software)"
- docs/architecture.md - Evidence architecture patterns
- backend/src/services/android_attestation.rs - SecurityLevel enum, AndroidAttestationResult
- backend/src/models/evidence.rs - HardwareAttestation, CheckStatus patterns
- backend/src/models/device.rs - Device model structure
- backend/src/routes/devices.rs - DeviceRegistrationResponse, insert_device()
- docs/sprint-artifacts/stories/10-1-android-key-attestation-service.md - Foundation story

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story not yet implemented

### File List

**To Create:**
- `/Users/luca/dev/realitycam/backend/migrations/<timestamp>_add_security_level_fields.sql` (use `sqlx migrate add` for correct timestamp)

**To Modify:**
- `/Users/luca/dev/realitycam/backend/src/models/device.rs`
- `/Users/luca/dev/realitycam/backend/src/models/evidence.rs`
- `/Users/luca/dev/realitycam/backend/src/routes/devices.rs`
- `/Users/luca/dev/realitycam/backend/src/services/android_attestation.rs`
- `/Users/luca/dev/realitycam/backend/src/services/evidence.rs` or `/Users/luca/dev/realitycam/backend/src/routes/captures.rs`
- `/Users/luca/dev/realitycam/.sqlx/` (regenerate with cargo sqlx prepare)
