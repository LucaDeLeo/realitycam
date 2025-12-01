# Story 8-3: Hash-Only Capture Payload

Status: drafted

## Story

As a **privacy-conscious user**,
I want **my capture to upload only hash and evidence**,
So that **the server never receives my raw media**.

## Acceptance Criteria

### AC 1: Privacy Mode Branch in Capture Flow
**Given** the user has enabled Privacy Mode in settings
**When** they capture a photo
**Then**:
1. CaptureViewModel detects privacy mode via PrivacySettingsManager
2. Capture flow branches to hash-only processing path
3. Raw photo bytes are NOT included in upload payload
4. Flow still works when privacy mode is OFF (full upload)

### AC 2: Client-Side Depth Analysis Execution
**Given** Privacy Mode is enabled and capture occurs
**When** the depth map is available
**Then**:
1. DepthAnalysisService.shared.analyze() is called with depth buffer
2. Analysis completes within capture processing flow
3. DepthAnalysisResult is stored in HashOnlyCapturePayload
4. Analysis failure falls back gracefully (capture continues with unavailable status)

### AC 3: Metadata Filtering Based on Privacy Settings
**Given** Privacy Mode capture with specific metadata levels configured
**When** building the hash-only payload
**Then**:
1. Location is filtered per locationLevel setting:
   - none: null location
   - coarse: city/country only (no coordinates)
   - precise: full GPS coordinates
2. Timestamp is filtered per timestampLevel setting:
   - none: null timestamp
   - dayOnly: ISO8601 date only (YYYY-MM-DD)
   - exact: full ISO8601 timestamp
3. Device info is filtered per deviceInfoLevel setting:
   - none: null device info
   - modelOnly: device model string only
   - full: model + iOS version + app version

### AC 4: Hash-Only Payload Structure
**Given** a completed privacy mode capture
**When** the payload is constructed
**Then** HashOnlyCapturePayload contains:
1. `captureMode`: "hash_only"
2. `mediaHash`: SHA-256 hex string of JPEG bytes
3. `mediaType`: "photo"
4. `depthAnalysis`: DepthAnalysisResult from client analysis
5. `metadata`: FilteredMetadata with per-setting values
6. `metadataFlags`: MetadataFlags indicating what was included
7. `capturedAt`: Capture timestamp
8. `assertion`: Base64 DCAppAttest assertion

### AC 5: Assertion Covers Entire Payload
**Given** a hash-only capture ready for signing
**When** DCAppAttest assertion is generated
**Then**:
1. Assertion clientDataHash = SHA256(serialized payload)
2. Assertion covers: mediaHash + depthAnalysis + metadata + metadataFlags
3. Assertion is generated via existing CaptureAssertionService
4. Invalid/failed assertion results in pending retry status

### AC 6: Payload Size Target
**Given** a hash-only capture payload
**When** serialized for upload
**Then**:
1. Total payload size is < 10KB
2. No raw photo bytes included (vs ~2-4MB full capture)
3. No raw depth map bytes included (vs ~50-100KB compressed)
4. Payload is suitable for low-bandwidth upload

### AC 7: Local Media Retention
**Given** a completed privacy mode capture
**When** payload is ready for upload
**Then**:
1. Full JPEG photo remains in local encrypted storage
2. Full depth map remains in local storage
3. User can view local capture in History
4. Media is NOT deleted after hash-only upload

### AC 8: CaptureData Extension for Privacy Mode
**Given** the existing CaptureData model
**When** supporting privacy mode
**Then**:
1. New optional `depthAnalysisResult: DepthAnalysisResult?` field added
2. New optional `captureMode: CaptureMode?` field added (.full or .hashOnly)
3. New optional `privacySettings: PrivacySettings?` snapshot field added
4. Backward compatibility maintained for existing captures

## Tasks / Subtasks

- [ ] Task 1: Create HashOnlyCapturePayload model (AC: #4, #6)
  - [ ] Create `ios/Rial/Models/HashOnlyCapturePayload.swift`
  - [ ] Define HashOnlyCapturePayload struct with all fields per tech spec
  - [ ] Create FilteredMetadata struct for privacy-filtered metadata
  - [ ] Create MetadataFlags struct indicating included fields
  - [ ] Make all structs Codable, Sendable, Equatable
  - [ ] Add unit tests for JSON encoding/decoding

- [ ] Task 2: Create FilteredLocation helper (AC: #3)
  - [ ] Create FilteredLocation struct with city/country fields
  - [ ] Add static factory from LocationData with level filtering
  - [ ] Implement coarse filtering (reverse geocode to city if needed)
  - [ ] Add unit tests for each filtering level

- [ ] Task 3: Create MetadataFilterService (AC: #3)
  - [ ] Create `ios/Rial/Core/Capture/MetadataFilterService.swift`
  - [ ] Implement filterLocation(data:level:) method
  - [ ] Implement filterTimestamp(date:level:) method
  - [ ] Implement filterDeviceInfo(metadata:level:) method
  - [ ] Add unit tests for all filtering combinations

- [ ] Task 4: Extend CaptureData for privacy mode (AC: #8)
  - [ ] Add `depthAnalysisResult: DepthAnalysisResult?` field
  - [ ] Add `captureMode: CaptureMode?` enum field (.full, .hashOnly)
  - [ ] Add `privacySettings: PrivacySettings?` snapshot field
  - [ ] Ensure backward compatibility with default nil values
  - [ ] Update CaptureData init and Codable conformance
  - [ ] Add unit tests for migration from old captures

- [ ] Task 5: Create CaptureMode enum (AC: #1, #4, #8)
  - [ ] Add CaptureMode enum to CaptureData.swift or separate file
  - [ ] Define .full and .hashOnly cases
  - [ ] Use snake_case raw values for API compatibility
  - [ ] Add Codable, Sendable conformance

- [ ] Task 6: Integrate DepthAnalysisService into capture flow (AC: #2)
  - [ ] Import DepthAnalysisService in CaptureViewModel
  - [ ] Add depth analysis call after frame capture when privacy mode ON
  - [ ] Store DepthAnalysisResult in processing state
  - [ ] Handle analysis failure gracefully (continue with unavailable)
  - [ ] Add performance logging for analysis duration

- [ ] Task 7: Create HashOnlyPayloadBuilder (AC: #3, #4, #5)
  - [ ] Create `ios/Rial/Core/Capture/HashOnlyPayloadBuilder.swift`
  - [ ] Implement build(from:privacySettings:depthAnalysis:) method
  - [ ] Apply metadata filtering based on settings
  - [ ] Compute mediaHash (SHA-256 of JPEG)
  - [ ] Construct MetadataFlags from settings
  - [ ] Return complete HashOnlyCapturePayload
  - [ ] Add unit tests for payload construction

- [ ] Task 8: Modify CaptureViewModel for privacy mode branch (AC: #1, #2, #7)
  - [ ] Inject PrivacySettingsManager into CaptureViewModel
  - [ ] Check isPrivacyModeEnabled at capture time
  - [ ] Branch capture flow: full vs hash-only
  - [ ] For hash-only: run depth analysis, build payload
  - [ ] For full: use existing capture path
  - [ ] Ensure local storage happens regardless of mode

- [ ] Task 9: Update assertion generation for hash-only (AC: #5)
  - [ ] Modify CaptureAssertionService to accept HashOnlyCapturePayload
  - [ ] Compute clientDataHash from serialized payload JSON
  - [ ] Sign with existing DCAppAttest flow
  - [ ] Return Base64-encoded assertion
  - [ ] Handle assertion failure with retry status

- [ ] Task 10: Create HashOnlyCaptureData wrapper (AC: #4, #6, #7)
  - [ ] Create wrapper that combines local CaptureData + HashOnlyCapturePayload
  - [ ] Store full CaptureData locally (encrypted)
  - [ ] Store HashOnlyCapturePayload for upload
  - [ ] Verify payload size < 10KB
  - [ ] Add logging for payload size tracking

- [ ] Task 11: Unit tests for payload construction (AC: #4, #6)
  - [ ] Test complete payload serialization
  - [ ] Test payload size is < 10KB
  - [ ] Test all metadata filtering combinations
  - [ ] Test assertion hash computation
  - [ ] Test JSON encoding matches API contract

- [ ] Task 12: Integration tests (AC: #1, #2, #7)
  - [ ] Test full capture flow with privacy mode ON
  - [ ] Test full capture flow with privacy mode OFF
  - [ ] Verify local storage of full media
  - [ ] Verify depth analysis execution
  - [ ] Test with various privacy settings combinations

## Dev Notes

### Technical Approach

**Payload Structure (from tech spec):**
```swift
struct HashOnlyCapturePayload: Codable {
    let captureMode: String // "hash_only"
    let mediaHash: String   // SHA-256 hex
    let mediaType: String   // "photo"
    let depthAnalysis: DepthAnalysisResult
    let metadata: FilteredMetadata
    let metadataFlags: MetadataFlags
    let capturedAt: Date
    let assertion: String   // Base64

    // Video-specific (future, optional)
    let hashChain: HashChainData?
    let frameCount: Int?
    let durationMs: Int?
}

struct FilteredMetadata: Codable {
    let location: FilteredLocation?
    let timestamp: String?       // ISO8601 or day-only
    let deviceModel: String?
}

struct MetadataFlags: Codable {
    let locationIncluded: Bool
    let locationLevel: String    // "none", "coarse", "precise"
    let timestampIncluded: Bool
    let timestampLevel: String   // "none", "day_only", "exact"
    let deviceInfoIncluded: Bool
    let deviceInfoLevel: String  // "none", "model_only", "full"
}
```

**Metadata Filtering Logic:**
```swift
// Location filtering
switch privacySettings.locationLevel {
case .none:
    return nil
case .coarse:
    return FilteredLocation(city: "San Francisco", country: "US")
case .precise:
    return FilteredLocation(
        latitude: location.latitude,
        longitude: location.longitude
    )
}

// Timestamp filtering
switch privacySettings.timestampLevel {
case .none:
    return nil
case .dayOnly:
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter.string(from: date) // "2025-12-01"
case .exact:
    return ISO8601DateFormatter().string(from: date)
}

// Device info filtering
switch privacySettings.deviceInfoLevel {
case .none:
    return nil
case .modelOnly:
    return metadata.deviceModel
case .full:
    return "\(metadata.deviceModel) / iOS \(metadata.iosVersion) / \(metadata.appVersion)"
}
```

**CaptureViewModel Flow:**
```swift
func performCapture() async {
    let frame = captureSession.captureCurrentFrame()
    let captureData = try await frameProcessor.process(frame)

    if privacySettings.isPrivacyModeEnabled {
        // Privacy mode: run client-side depth analysis
        let depthAnalysis = await DepthAnalysisService.shared.analyze(
            depthMap: frame.sceneDepth?.depthMap
        )

        // Build hash-only payload
        let payload = HashOnlyPayloadBuilder.build(
            from: captureData,
            privacySettings: privacySettings.settings,
            depthAnalysis: depthAnalysis
        )

        // Generate assertion over payload
        let assertion = try await assertionService.createAssertion(
            for: payload
        )
        payload.assertion = assertion.base64EncodedString()

        // Store full media locally, upload only payload
        await saveLocalCapture(captureData)
        await uploadHashOnlyPayload(payload)
    } else {
        // Full mode: existing flow
        await saveAndUpload(captureData)
    }
}
```

**Payload Size Estimation:**
- mediaHash: 64 bytes (SHA-256 hex)
- depthAnalysis: ~200 bytes JSON
- metadata: ~100-500 bytes (depends on levels)
- metadataFlags: ~150 bytes
- assertion: ~1-2KB Base64
- Total: ~2-3KB (well under 10KB target)

### Project Structure Notes

**New Files:**
- `ios/Rial/Models/HashOnlyCapturePayload.swift` - Payload model + FilteredMetadata + MetadataFlags
- `ios/Rial/Core/Capture/MetadataFilterService.swift` - Filtering logic
- `ios/Rial/Core/Capture/HashOnlyPayloadBuilder.swift` - Payload construction
- `ios/RialTests/Models/HashOnlyCapturePayloadTests.swift` - Unit tests
- `ios/RialTests/Capture/MetadataFilterServiceTests.swift` - Filter tests
- `ios/RialTests/Capture/HashOnlyPayloadBuilderTests.swift` - Builder tests

**Modified Files:**
- `ios/Rial/Models/CaptureData.swift` - Add privacy mode fields
- `ios/Rial/Features/Capture/CaptureViewModel.swift` - Add privacy mode branch
- `ios/Rial/Core/Attestation/CaptureAssertionService.swift` - Support hash-only payload signing
- `ios/Rial.xcodeproj/project.pbxproj` - Add new files

**Dependencies:**
- Story 8-1: DepthAnalysisService (provides client-side depth analysis)
- Story 8-2: PrivacySettingsManager (provides privacy settings access)
- Existing: CryptService (for SHA-256), CaptureAssertionService (for signing)

### Testing Standards

**Unit Tests (XCTest):**
- Test HashOnlyCapturePayload encoding/decoding
- Test FilteredMetadata construction for all levels
- Test MetadataFlags correctness
- Test payload size calculation
- Test metadata filtering for all combinations

**Integration Tests:**
- Test capture flow with privacy mode ON/OFF
- Test depth analysis integration
- Test assertion generation over payload
- Test local storage of full media
- Test payload size < 10KB

**Manual Testing:**
- Capture with privacy mode enabled
- Verify upload size in network inspector
- Verify local storage has full media
- Test all metadata level combinations

### References

- **Epic:** [Source: docs/epics.md - Epic 8: Privacy-First Capture Mode]
  - Story 8.3: Hash-Only Capture Payload (lines 2956-2985)
  - Payload contains: media_hash, depth_analysis, metadata, metadata_flags, assertion
  - Upload size < 10KB, full media retained locally
- **Tech Spec:** [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-8.md]
  - Section: iOS HashOnlyCapturePayload (New) - Lines 161-196
  - Section: FilteredMetadata and MetadataFlags - Lines 182-195
  - Section: Acceptance Criteria Story 8.3 - Lines 631-640
  - Section: Privacy Mode Capture Flow - Lines 443-509
- **Architecture:** [Source: docs/architecture.md]
  - ADR-009: Native Swift Implementation
  - ADR-011: Client-Side Depth Analysis for Privacy Mode
- **PRD:** [Source: docs/prd.md]
  - FR57: Client-side depth analysis in privacy mode
  - FR58: Hash-only upload with depth_analysis_result + attestation_signature
  - FR62: Per-capture metadata granularity configuration
- **Existing Code:**
  - [Source: ios/Rial/Models/CaptureData.swift] - Capture model to extend
  - [Source: ios/Rial/Features/Capture/CaptureViewModel.swift] - Capture flow to modify
  - [Source: ios/Rial/Core/Capture/DepthAnalysisService.swift] - Depth analysis (Story 8-1)
  - [Source: ios/Rial/Core/Configuration/PrivacySettingsManager.swift] - Settings access (Story 8-2)
  - [Source: ios/Rial/Models/PrivacySettings.swift] - Settings model (Story 8-2)
  - [Source: ios/Rial/Core/Attestation/CaptureAssertionService.swift] - Assertion signing

## Learnings from Previous Stories

Based on Story 8-1 (Client-Side Depth Analysis) and Story 8-2 (Privacy Mode Settings UI):

1. **DepthAnalysisService is Ready:** Story 8-1 provides complete client-side depth analysis. Use `DepthAnalysisService.shared.analyze(depthMap:)` directly. Results are deterministic and match server algorithm.

2. **PrivacySettingsManager Pattern:** Story 8-2 established @EnvironmentObject injection pattern. Access via `privacySettings.isPrivacyModeEnabled` and `privacySettings.settings`.

3. **Enum Raw Values:** Use snake_case raw values for API compatibility (e.g., `"hash_only"`, `"day_only"`, `"model_only"`). Match existing patterns from PrivacySettings.

4. **@MainActor for UI Integration:** CaptureViewModel is @MainActor. Depth analysis runs async on background queue. Use proper async/await patterns.

5. **Payload JSON Encoding:** Use JSONEncoder with consistent settings. Match backend expectations for field naming.

6. **Assertion Integration:** CaptureAssertionService already handles signing. Extend to accept different payload types by computing clientDataHash from serialized JSON.

7. **Local Storage Pattern:** CaptureStore already encrypts local captures. Continue using this for full media retention.

8. **Task 12 from 8-1:** Story 8-1 deferred "Integration with CaptureViewModel" - this story completes that integration.

9. **Testing Isolation:** Clear UserDefaults before tests. Use unique keys or mock PrivacySettingsManager for isolation.

10. **Error Handling:** Depth analysis returns `.unavailable()` on failure. Capture should continue with degraded evidence rather than failing entirely.

---

_Story created: 2025-12-01_
_Depends on: Story 8-1 (DepthAnalysisService), Story 8-2 (PrivacySettingsManager)_
_Enables: Story 8-4 (Backend Hash-Only Endpoint) - provides client payload for backend to receive_

## Source Document References

- **Epic:** [Source: docs/epics.md - Epic 8: Privacy-First Capture Mode]
  - Story 8.3: Hash-Only Capture Payload (lines 2956-2985)
  - Acceptance Criteria: Payload excludes media, size < 10KB, assertion covers payload
- **Tech Spec:** [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-8.md]
  - Section: iOS HashOnlyCapturePayload (New) - Lines 161-196
  - Section: Privacy Mode Capture Flow - Lines 443-509
  - Section: Acceptance Criteria Story 8.3 - Lines 631-640
  - Section: Traceability Mapping - Line 691
- **Architecture:** [Source: docs/architecture.md]
  - ADR-009: Native Swift Implementation
  - ADR-011: Client-Side Depth Analysis for Privacy Mode
- **PRD:** [Source: docs/prd.md]
  - FR57: Client-side depth analysis
  - FR58: Hash-only uploads
  - FR62: Metadata granularity configuration
- **Existing Code:**
  - [Source: ios/Rial/Models/CaptureData.swift] (capture model)
  - [Source: ios/Rial/Features/Capture/CaptureViewModel.swift] (capture flow)
  - [Source: ios/Rial/Core/Capture/DepthAnalysisService.swift] (Story 8-1)
  - [Source: ios/Rial/Core/Configuration/PrivacySettingsManager.swift] (Story 8-2)
  - [Source: ios/Rial/Models/PrivacySettings.swift] (Story 8-2)

---

## Dev Agent Record

### Context Reference

_To be filled by story-context workflow_

### Agent Model Used

_To be filled during implementation_

### Debug Log References

_To be filled during implementation_

### Completion Notes

_To be filled during implementation_

### File List

_To be filled during implementation_
