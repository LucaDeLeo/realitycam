# Story 10-5: Unified Evidence Schema

Status: ready-for-dev

## Story

As a **backend service**,
I want **the evidence schema to uniformly represent both iOS DCAppAttest and Android Key Attestation, with platform-agnostic API responses where appropriate**,
So that **verification pages can display consistent evidence information regardless of capture source platform, enabling cross-platform evidence comparison and unified frontend rendering**.

## Context

This story builds on:
- **Story 10-1:** Android Key Attestation Service - implements `verify_android_attestation()`, `SecurityLevel` enum, and certificate chain verification
- **Story 10-2:** Attestation Security Level Extraction - adds `SecurityLevelInfo` struct, `security_level`/`keymaster_security_level` columns, and extends `AttestationLevel` enum with `StrongBox`/`TrustedEnvironment` variants
- **Story 10-3:** Android Device Registration Endpoint - platform routing, Android device insertion with security levels
- **Story 10-4:** Challenge Freshness Validation - ensures replay attack prevention for Android

**FR74 Focus:** "Evidence schema supports both iOS DCAppAttest and Android Key Attestation"

The existing evidence model (`EvidencePackage`, `HardwareAttestation`, `DepthAnalysis`) was designed for iOS-only captures with LiDAR depth analysis. This story ensures:
1. Evidence packages work for both iOS and Android captures
2. `HardwareAttestation` properly reflects platform-specific attestation methods
3. API responses provide platform context without breaking existing iOS integrations
4. Frontend can render evidence uniformly while highlighting platform differences
5. Backward compatibility with existing MVP evidence (FR75)

## Acceptance Criteria

### AC 1: EvidencePackage Includes Platform Field
**Given** a capture is processed from either iOS or Android
**When** the evidence package is generated
**Then** the evidence package JSON includes:
```json
{
  "platform": "ios",  // or "android"
  "hardware_attestation": { ... },
  "depth_analysis": { ... },
  "metadata": { ... },
  "processing": { ... }
}
```

**Platform Values:**
| Platform | Value | Description |
|----------|-------|-------------|
| iOS | `"ios"` | iPhone with DCAppAttest |
| Android | `"android"` | Android with Key Attestation |

### AC 2: HardwareAttestation Works for Both Platforms
**Given** a capture from iOS or Android
**When** `HardwareAttestation` is populated
**Then** it contains platform-appropriate values:

**iOS Example:**
```json
{
  "status": "pass",
  "level": "secure_enclave",
  "device_model": "iPhone 15 Pro",
  "assertion_verified": true,
  "counter_valid": true,
  "security_level": {
    "attestation_level": "secure_enclave",
    "keymaster_level": null,
    "platform": "ios"
  }
}
```

**Android Example:**
```json
{
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
```

### AC 3: AttestationLevel Enum Covers All Platform Levels
**Given** the `AttestationLevel` enum in `models/evidence.rs`
**When** serializing/deserializing
**Then** supports all platform attestation levels:

| Variant | Serialized String | Platform | Trust Level |
|---------|-------------------|----------|-------------|
| `SecureEnclave` | `"secure_enclave"` | iOS | HIGH |
| `StrongBox` | `"strongbox"` | Android | HIGH |
| `TrustedEnvironment` | `"tee"` | Android | MEDIUM |
| `Unverified` | `"unverified"` | Any | NONE |

Note: Story 10-2 already added `StrongBox` and `TrustedEnvironment` variants.

### AC 4: DepthAnalysis Handles Platform Differences
**Given** depth analysis for iOS vs Android captures
**When** evidence is generated
**Then**:

**iOS (LiDAR):**
```json
{
  "status": "pass",
  "depth_variance": 2.4,
  "depth_layers": 5,
  "edge_coherence": 0.87,
  "min_depth": 0.8,
  "max_depth": 4.2,
  "is_likely_real_scene": true,
  "source": "server",
  "method": "lidar"
}
```

**Android (No LiDAR - Future Parallax):**
```json
{
  "status": "unavailable",
  "depth_variance": 0.0,
  "depth_layers": 0,
  "edge_coherence": 0.0,
  "min_depth": 0.0,
  "max_depth": 0.0,
  "is_likely_real_scene": false,
  "source": null,
  "method": null,
  "unavailable_reason": "android_no_lidar"
}
```

Note: Android parallax depth will be added in Epic 12. For now, Android captures have `status: unavailable` for depth analysis.

### AC 5: API Response GET /captures/{id} Platform-Agnostic
**Given** a capture exists (iOS or Android)
**When** fetching via `GET /api/v1/captures/{id}`
**Then** response includes platform in evidence:

```json
{
  "data": {
    "id": "uuid",
    "confidence_level": "high",
    "platform": "ios",
    "evidence": {
      "platform": "ios",
      "hardware_attestation": { ... },
      "depth_analysis": { ... },
      "metadata": { ... },
      "processing": { ... }
    },
    "verification_url": "https://..."
  },
  "request_id": "uuid"
}
```

### AC 6: Confidence Calculation Accounts for Platform
**Given** the confidence calculation in `EvidencePackage::calculate_confidence()`
**When** calculating confidence for Android captures
**Then**:
1. Android with StrongBox + no depth = MEDIUM (not HIGH, depth unavailable)
2. Android with TEE + no depth = MEDIUM
3. Android with StrongBox attestation fail = SUSPICIOUS
4. iOS with secure_enclave + depth pass = HIGH (unchanged)
5. iOS with secure_enclave + depth fail = SUSPICIOUS (unchanged)

**Updated Confidence Matrix:**
| Platform | HW Attestation | Depth Analysis | Confidence |
|----------|---------------|----------------|------------|
| iOS | pass (secure_enclave) | pass | HIGH |
| iOS | pass | unavailable | MEDIUM |
| iOS | fail | any | SUSPICIOUS |
| Android | pass (strongbox) | unavailable | MEDIUM |
| Android | pass (tee) | unavailable | MEDIUM |
| Android | fail | any | SUSPICIOUS |

Note: Android depth will be added via parallax in Epic 12. Current implementation correctly returns MEDIUM for Android (one evidence signal passes, one unavailable).

### AC 7: EvidencePackage Struct Extension
**Given** the `EvidencePackage` struct in `models/evidence.rs`
**When** updated for cross-platform support
**Then** includes:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidencePackage {
    /// Platform: "ios" or "android"
    pub platform: String,
    /// Hardware attestation evidence
    pub hardware_attestation: HardwareAttestation,
    /// Depth analysis evidence (may be unavailable for Android)
    pub depth_analysis: DepthAnalysis,
    /// Metadata validation evidence
    pub metadata: MetadataEvidence,
    /// Processing information (timing, version)
    pub processing: ProcessingInfo,
}
```

### AC 8: DepthAnalysis Method Field
**Given** the `DepthAnalysis` struct
**When** updated for cross-platform support
**Then** includes method indicator:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepthAnalysis {
    // ... existing fields ...

    /// Depth analysis method: "lidar", "parallax", or null if unavailable
    #[serde(skip_serializing_if = "Option::is_none")]
    pub method: Option<String>,

    /// Reason why depth is unavailable (e.g., "android_no_lidar")
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unavailable_reason: Option<String>,
}
```

### AC 9: Backward Compatibility for Existing Evidence (FR75)
**Given** existing iOS evidence packages in database (without `platform` field)
**When** deserializing legacy evidence
**Then**:
1. Missing `platform` field defaults to `"ios"` (all existing captures are iOS)
2. Missing `method` field in depth_analysis defaults to `"lidar"` if status=pass
3. Missing `unavailable_reason` field is ignored (not required)
4. Missing `security_level` in hardware_attestation is handled gracefully
5. Existing confidence calculations produce same results

### AC 10: Evidence Package Builder Helper
**Given** capture processing in `routes/captures.rs`
**When** building evidence packages
**Then** use builder pattern that enforces platform:

```rust
impl EvidencePackage {
    /// Creates evidence package for iOS capture
    pub fn for_ios(
        hardware_attestation: HardwareAttestation,
        depth_analysis: DepthAnalysis,
        metadata: MetadataEvidence,
        processing: ProcessingInfo,
    ) -> Self {
        Self {
            platform: "ios".to_string(),
            hardware_attestation,
            depth_analysis,
            metadata,
            processing,
        }
    }

    /// Creates evidence package for Android capture
    pub fn for_android(
        hardware_attestation: HardwareAttestation,
        depth_analysis: DepthAnalysis,
        metadata: MetadataEvidence,
        processing: ProcessingInfo,
    ) -> Self {
        Self {
            platform: "android".to_string(),
            hardware_attestation,
            depth_analysis,
            metadata,
            processing,
        }
    }
}
```

### AC 11: Unit Tests for Unified Evidence Schema
**Given** the unified evidence schema code
**When** unit tests run
**Then** coverage includes:
1. EvidencePackage serialization with platform field (iOS)
2. EvidencePackage serialization with platform field (Android)
3. HardwareAttestation with all AttestationLevel variants
4. DepthAnalysis with method field
5. DepthAnalysis with unavailable_reason field
6. Backward compatibility deserialization (missing platform -> ios)
7. Confidence calculation for iOS captures
8. Confidence calculation for Android captures (depth unavailable)
9. Security level info population for both platforms
10. Legacy evidence deserialization: verify platform field defaults to "ios" when missing

## Tasks / Subtasks

- [ ] Task 1: Add platform field to EvidencePackage (AC: #1, #7)
  - [ ] Add `platform: String` field to `EvidencePackage` struct in `backend/src/models/evidence.rs`
  - [ ] Add `#[serde(default = "default_platform")]` for backward compatibility
  - [ ] Implement `fn default_platform() -> String { "ios".to_string() }`
  - [ ] Update struct documentation

- [ ] Task 2: Add method and unavailable_reason to DepthAnalysis (AC: #4, #8)
  - [ ] Add `method: Option<String>` field with `#[serde(skip_serializing_if = "Option::is_none")]`
  - [ ] Add `unavailable_reason: Option<String>` field with `#[serde(skip_serializing_if = "Option::is_none")]`
  - [ ] Update `Default` implementation to set both as `None`
  - [ ] Document valid method values: "lidar", "parallax" (future)
  - [ ] Document valid unavailable_reason values: "android_no_lidar", "depth_map_missing", etc.

- [ ] Task 3: Add builder methods to EvidencePackage (AC: #10)
  - [ ] Add `EvidencePackage::for_ios()` constructor
  - [ ] Add `EvidencePackage::for_android()` constructor
  - [ ] Add `EvidencePackage::with_platform()` generic constructor if needed
  - [ ] Document builder pattern usage

- [ ] Task 4: Update iOS capture evidence generation (AC: #1, #4)
  - [ ] Modify `backend/src/routes/captures.rs` to use `EvidencePackage::for_ios()`
  - [ ] Set `depth_analysis.method = Some("lidar".to_string())` for successful depth analysis
  - [ ] Set `depth_analysis.unavailable_reason` appropriately when depth fails/unavailable
  - [ ] Ensure existing iOS capture flow continues to work

- [ ] Task 5: Update hash-only capture evidence generation (AC: #1, #4)
  - [ ] Modify `backend/src/routes/captures_hash_only.rs` to use platform-aware builder
  - [ ] Set `depth_analysis.method = Some("lidar".to_string())` (device analysis uses LiDAR)
  - [ ] Pass platform from device record to evidence package

- [ ] Task 6: Create Android capture evidence placeholder (AC: #4, #6)
  - [ ] Create helper function `depth_analysis_unavailable_android()` returning DepthAnalysis with:
    - `status: CheckStatus::Unavailable` (valid status per DepthAnalysis Default impl)
    - `method: None`
    - `unavailable_reason: Some("android_no_lidar".to_string())`
    - All metrics set to 0
  - [ ] Document that this will be replaced when Epic 12 implements parallax

- [ ] Task 7: Update GET /captures/{id} response (AC: #5)
  - [ ] Ensure platform is included in capture response
  - [ ] Can either duplicate platform at top level OR let frontend extract from evidence.platform
  - [ ] Verify JSON response matches AC #5 format
  - [ ] Add platform to CaptureResponse struct if not present

- [ ] Task 8: Review confidence calculation (AC: #6)
  - [ ] Review `EvidencePackage::calculate_confidence()` logic
  - [ ] Verify Android captures (no depth) produce MEDIUM confidence (hw pass + depth unavailable)
  - [ ] Verify existing iOS logic unchanged
  - [ ] Add comments documenting platform confidence expectations

- [ ] Task 9: Backward compatibility testing (AC: #9)
  - [ ] Create test JSON for legacy evidence (no platform field)
  - [ ] Verify deserialization defaults platform to "ios"
  - [ ] Verify legacy evidence confidence calculation unchanged
  - [ ] Test serialization round-trip preserves data

- [ ] Task 10: Unit tests (AC: #11)
  - [ ] Test EvidencePackage::for_ios() builder
  - [ ] Test EvidencePackage::for_android() builder
  - [ ] Test platform serialization ("ios", "android")
  - [ ] Test DepthAnalysis method field serialization
  - [ ] Test DepthAnalysis unavailable_reason serialization
  - [ ] Test backward compatibility (missing platform defaults to "ios")
  - [ ] Test confidence for iOS: hw pass + depth pass = HIGH
  - [ ] Test confidence for iOS: hw pass + depth unavailable = MEDIUM
  - [ ] Test confidence for Android: hw pass + depth unavailable = MEDIUM
  - [ ] Test confidence for Android: hw fail = SUSPICIOUS

- [ ] Task 11: Update video evidence generation (AC: #1)
  - [ ] Update `backend/src/routes/captures_video.rs` to use platform-aware builder
  - [ ] Ensure video captures also include platform field
  - [ ] Video evidence uses same EvidencePackage structure

## Dev Notes

### Technical Approach

**Platform Field Strategy:**
The `platform` field in `EvidencePackage` provides clear context for frontend rendering. This is derived from the device record at capture time, not inferred from attestation type.

```rust
// In capture processing:
let platform = device.platform.to_lowercase();
let evidence = if platform == "android" {
    EvidencePackage::for_android(hw_attestation, depth, metadata, processing)
} else {
    EvidencePackage::for_ios(hw_attestation, depth, metadata, processing)
};
```

**DepthAnalysis Method Values:**
| Method | Platform | Description |
|--------|----------|-------------|
| `"lidar"` | iOS Pro | Direct LiDAR depth measurement |
| `"parallax"` | Android (future) | Multi-camera stereo depth estimation |
| `null` | Any | Depth analysis not performed/unavailable |

**Unavailable Reason Values:**
| Reason | Meaning |
|--------|---------|
| `"android_no_lidar"` | Android device lacks LiDAR sensor |
| `"depth_map_missing"` | No depth data uploaded |
| `"analysis_failed"` | Depth analysis computation failed |
| `"device_analysis"` | Client-side analysis (hash-only mode) |

**Backward Compatibility Design:**
- Use `#[serde(default)]` for new fields to handle legacy data
- `platform` defaults to `"ios"` (all existing data is iOS)
- `method` defaults to `None` but can be inferred as "lidar" for existing iOS depth passes
- Confidence calculation unchanged for existing iOS captures

**Confidence Calculation Review:**
The current `calculate_confidence()` logic:
```rust
pub fn calculate_confidence(&self) -> ConfidenceLevel {
    if hw_fail || depth_fail { return SUSPICIOUS; }
    if hw_pass && depth_pass { return HIGH; }
    if hw_pass || depth_pass { return MEDIUM; }
    return LOW;
}
```

This naturally handles Android:
- Android: hw_pass=true, depth_pass=false (unavailable) -> MEDIUM
- No code changes needed for confidence calculation

### File Changes Summary

**Modified Files:**
- `/Users/luca/dev/realitycam/backend/src/models/evidence.rs`
  - Add `platform` field to `EvidencePackage`
  - Add `method`, `unavailable_reason` fields to `DepthAnalysis`
  - Add builder methods `for_ios()`, `for_android()`
  - Add `default_platform()` helper
  - Update tests

- `/Users/luca/dev/realitycam/backend/src/routes/captures.rs`
  - Use `EvidencePackage::for_ios()` builder
  - Set `depth_analysis.method` field

- `/Users/luca/dev/realitycam/backend/src/routes/captures_hash_only.rs`
  - Use platform-aware evidence builder
  - Set depth analysis method field

- `/Users/luca/dev/realitycam/backend/src/routes/captures_video.rs` (if exists)
  - Same changes as captures.rs

**New Files:**
- None (all changes in existing files)

### Security Considerations

**Platform Validation:**
The `platform` field in evidence is derived from the device record, which is set during registration after attestation verification. This ensures:
- Platform cannot be spoofed by client
- Evidence platform matches registered device platform
- Trust model remains intact

**Evidence Integrity:**
Adding new fields does not compromise evidence integrity:
- Platform field is metadata, not part of cryptographic binding
- Depth analysis method clarifies data source
- Confidence calculation unchanged for existing captures

### Testing Strategy

**Unit Tests:**
1. Serialization/deserialization of all new fields
2. Builder method correctness
3. Default value behavior for backward compatibility
4. Confidence calculation matrix (all platform/attestation/depth combinations)

**Integration Tests:**
1. Full iOS capture flow -> verify evidence contains platform="ios"
2. Android capture (when ready) -> verify evidence contains platform="android"
3. GET /captures/{id} returns correct platform in response
4. Legacy evidence deserialization (simulate old database record)

**Manual Verification:**
1. Deploy to staging
2. Create iOS capture, verify evidence in verification page
3. Check database evidence JSON includes platform field
4. Verify frontend renders correctly with new fields

### References

- [Source: backend/src/models/evidence.rs] - Current evidence model structures
- [Source: backend/src/services/capture_attestation.rs] - Hardware attestation generation
- [Source: backend/src/routes/captures.rs] - iOS capture processing
- [Source: docs/prd.md#FR74] - "Evidence schema supports both iOS DCAppAttest and Android Key Attestation"
- [Source: docs/prd.md#FR75] - "Backend maintains backward compatibility with MVP evidence schema"
- [Source: docs/prd.md#Evidence-Model-Unified] - Target unified evidence JSON structure

### Related Stories

- Story 10-1: Android Key Attestation Service - COMPLETED (provides SecurityLevel enum)
- Story 10-2: Attestation Security Level Extraction - COMPLETED (SecurityLevelInfo, AttestationLevel variants)
- Story 10-3: Software Attestation Rejection - REVIEW (Android device registration)
- Story 10-4: Challenge Freshness Validation - REVIEW (challenge security)
- Story 10-6: Backward Compatibility Migration - BACKLOG (if needed for production data)
- Story 11-1: Platform Indicator Display - BACKLOG (frontend uses platform field)

---

_Story created: 2025-12-11_
_Epic: 10 - Cross-Platform Foundation_
_FR Coverage: FR74 (Evidence schema supports both iOS DCAppAttest and Android Key Attestation), FR75 (Backward compatibility)_
_Depends on: Story 10-2 (SecurityLevelInfo struct, AttestationLevel enum extensions)_
_Enables: Story 11-1 (Platform indicator in verification UI), Epic 12 (Android app evidence generation)_

## Dev Agent Record

### Context Reference

Created from:
- docs/epics.md - Epic 10 definition, FR74-FR75 mapping
- docs/prd.md - FR74 "Evidence schema supports both iOS DCAppAttest and Android Key Attestation", FR75 backward compatibility, unified evidence model JSON
- backend/src/models/evidence.rs - Current EvidencePackage, HardwareAttestation, DepthAnalysis, SecurityLevelInfo structs
- backend/src/services/capture_attestation.rs - How HardwareAttestation is built from device record
- backend/src/routes/captures.rs - Current iOS evidence generation flow
- docs/sprint-artifacts/stories/10-1-android-key-attestation-service.md - SecurityLevel enum
- docs/sprint-artifacts/stories/10-2-attestation-security-level-extraction.md - SecurityLevelInfo, AttestationLevel variants
- docs/sprint-artifacts/stories/10-3-software-attestation-rejection.md - Android registration endpoint

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story not yet implemented

### File List

**To Modify:**
- `/Users/luca/dev/realitycam/backend/src/models/evidence.rs` - Add platform field, depth method/reason fields, builders
- `/Users/luca/dev/realitycam/backend/src/routes/captures.rs` - Use evidence builder, set depth method
- `/Users/luca/dev/realitycam/backend/src/routes/captures_hash_only.rs` - Use platform-aware builder
- `/Users/luca/dev/realitycam/backend/src/routes/captures_video.rs` - If video capture exists, same changes
