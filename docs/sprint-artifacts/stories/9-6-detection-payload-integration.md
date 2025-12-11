# Story 9-6: Detection Payload Integration

Status: ready-for-dev

## Story

As a **rial. iOS app user**,
I want **my captured photos to include the complete multi-signal detection results (moire, texture, artifacts, cross-validation) alongside the existing LiDAR depth data**,
So that **the backend receives comprehensive authenticity evidence for stronger verification and the detection methods can be transparently displayed to verifiers**.

## Acceptance Criteria

### AC 1: DetectionResults Model for CaptureData
**Given** the existing CaptureData model (ios/Rial/Models/CaptureData.swift)
**When** a capture includes multi-signal detection
**Then**:
1. New `DetectionResults` struct aggregates all detection outputs:
   - `moire: MoireAnalysisResult?`
   - `texture: TextureClassificationResult?`
   - `artifacts: ArtifactAnalysisResult?`
   - `aggregatedConfidence: AggregatedConfidenceResult?`
   - `crossValidation: CrossValidationResult?` (from enhanced mode)
2. CaptureData gains new optional field: `detectionResults: DetectionResults?`
3. Field is nil for backward compatibility with existing captures
4. Model is Codable, Sendable, Equatable
5. Total serialized size estimate: 2-5KB typical

### AC 2: FrameProcessor Integration
**Given** the existing FrameProcessor (ios/Rial/Core/Capture/FrameProcessor.swift)
**When** processing an ARFrame
**Then**:
1. New optional parameter: `runDetection: Bool = false`
2. When true, runs all detection services in parallel after JPEG/depth processing:
   - MoireDetectionService.shared.analyze(image:)
   - TextureClassificationService.shared.classify(image:)
   - ArtifactDetectionService.shared.analyze(image:)
3. Aggregates results via ConfidenceAggregator.shared.aggregate() with enableEnhancedCrossValidation=true
4. Attaches DetectionResults to CaptureData output
5. Detection adds <200ms to processing time (runs in parallel with existing steps)
6. Processing remains under 400ms total (existing 200ms + detection 200ms target)
7. Graceful fallback: if any detection fails, others continue and result is partial

### AC 3: DetectionPayload for Upload
**Given** the existing UploadService multipart payload structure
**When** detection results are present in CaptureData
**Then**:
1. New `DetectionPayload` struct encodes results for backend (JSON):
   ```json
   {
     "moire": { "detected": bool, "confidence": float, "screen_type": string?, ... },
     "texture": { "classification": string, "confidence": float, ... },
     "artifacts": { "is_likely_artificial": bool, "pwm_detected": bool, ... },
     "aggregated": { "overall_confidence": float, "confidence_level": string, ... },
     "cross_validation": { "validation_status": string, "anomalies": [...], ... }
   }
   ```
2. Uses snake_case keys to match backend Rust conventions
3. Includes algorithm versions for each detection method
4. Total payload size: 5-10KB typical (acceptable for multipart upload)

### AC 4: UploadService Multipart Extension
**Given** the existing UploadService.writeMultipartBody() method
**When** uploading a capture with detection results
**Then**:
1. Detection payload added as new multipart part:
   - Name: `detection`
   - Filename: `detection.json`
   - Content-Type: `application/json`
2. Only included when CaptureData.detectionResults is non-nil
3. Existing metadata payload unchanged (backward compatible)
4. Upload continues to work without detection results (old captures)
5. Logged: "Upload includes multi-signal detection data" when present

### AC 5: UploadMetadataPayload Extension
**Given** the existing UploadMetadataPayload struct
**When** detection results are available
**Then**:
1. Metadata includes summary fields for quick backend indexing:
   - `detection_available: Bool` - whether detection data is present
   - `detection_confidence_level: String?` - "very_high"/"high"/"medium"/"low"/"suspicious"
   - `detection_primary_valid: Bool?` - whether LiDAR passed
   - `detection_signals_agree: Bool?` - whether cross-validation passed
2. Full detection breakdown remains in separate `detection` multipart part
3. Summary enables backend to index/filter without parsing full detection JSON

### AC 6: CaptureViewModel Integration
**Given** the existing CaptureViewModel capture flow
**When** the user captures a photo
**Then**:
1. Detection is enabled by default for new captures (configurable via settings later)
2. UI shows brief "Analyzing..." state during detection processing
3. Detection runs after photo capture, before assertion generation
4. Order: capture -> JPEG/depth -> detection -> assertion -> ready for upload
5. If detection fails, capture proceeds without detection data (graceful degradation)
6. Detection results available in capture preview for debugging (debug builds only)

### AC 7: Backward Compatibility
**Given** existing captures without detection results
**When** uploading or processing
**Then**:
1. Uploads work identically - detection multipart part simply absent
2. Backend continues to accept captures without detection data
3. No breaking changes to existing CaptureData serialization
4. Existing CoreData captures remain loadable
5. Privacy mode captures work unchanged (detection is separate from depth analysis)

### AC 8: Performance Requirements
**Given** detection integration in capture flow
**When** processing a typical 12MP photo on iPhone 12 Pro or newer
**Then**:
1. Total processing time (JPEG + depth + detection + aggregation) < 500ms
2. Detection-specific time budget:
   - Moire: <30ms (target from 9-1)
   - Texture: <50ms (target from 9-2)
   - Artifacts: <20ms (target from 9-3)
   - Aggregation + cross-validation: <15ms (target from 9-4/9-5)
3. Parallel execution keeps overall time close to slowest component
4. Memory footprint increase: <50MB during detection
5. No UI blocking - all detection on background queue

## Tasks / Subtasks

- [ ] Task 1: Create DetectionResults model (AC: #1)
  - [ ] Create ios/Rial/Models/DetectionResults.swift
  - [ ] Define DetectionResults struct with optional fields for each detection type
  - [ ] Make Codable, Sendable, Equatable
  - [ ] Add factory methods: .partial(), .unavailable()
  - [ ] Add CodingKeys with snake_case for JSON serialization
  - [ ] Add computed property: hasAnyResults (true if at least one detection available)

- [ ] Task 2: Update CaptureData model (AC: #1, #7)
  - [ ] Add optional `detectionResults: DetectionResults?` field
  - [ ] Update initializer with default nil value
  - [ ] Ensure backward compatibility with existing serialization
  - [ ] Update totalSizeBytes computed property to include detection estimate

- [ ] Task 3: Create detection orchestration (AC: #2, #8)
  - [ ] Create ios/Rial/Core/Detection/DetectionOrchestrator.swift
  - [ ] Implement as final class singleton
  - [ ] Method: `runAllDetections(image: CGImage) async -> DetectionResults`
  - [ ] Run all three detection services in parallel (async let)
  - [ ] Aggregate results via ConfidenceAggregator with enhanced cross-validation
  - [ ] Handle partial failures gracefully (continue with available results)
  - [ ] Add os.log logging with "detection-orchestrator" category
  - [ ] Add os_signpost for performance tracking

- [ ] Task 4: Extend FrameProcessor (AC: #2, #8)
  - [ ] Add optional `runDetection: Bool = false` parameter to process() method
  - [ ] When true, extract CGImage from JPEG data for detection
  - [ ] Call DetectionOrchestrator.shared.runAllDetections()
  - [ ] Attach DetectionResults to returned CaptureData
  - [ ] Log detection timing separately from base processing
  - [ ] Maintain existing performance when detection disabled

- [ ] Task 5: Create DetectionPayload for upload (AC: #3)
  - [ ] Create DetectionPayload struct in UploadService.swift (private)
  - [ ] Include all detection result types with snake_case CodingKeys
  - [ ] Add algorithm version fields from each detection service
  - [ ] Implement Encodable conformance
  - [ ] Test JSON output format matches expected backend schema

- [ ] Task 6: Extend UploadMetadataPayload (AC: #5)
  - [ ] Add detection summary fields:
    - `detectionAvailable: Bool`
    - `detectionConfidenceLevel: String?`
    - `detectionPrimaryValid: Bool?`
    - `detectionSignalsAgree: Bool?`
  - [ ] Update CodingKeys with snake_case versions
  - [ ] Populate from CaptureData.detectionResults when available

- [ ] Task 7: Update UploadService multipart body (AC: #4)
  - [ ] Check if CaptureData.detectionResults is non-nil
  - [ ] If present, create DetectionPayload from detection results
  - [ ] Encode to JSON and add as multipart part (name: "detection")
  - [ ] Log when detection data included in upload
  - [ ] Ensure backward compatibility when detection absent

- [ ] Task 8: Update CaptureViewModel (AC: #6)
  - [ ] Enable detection by default when calling FrameProcessor.process()
  - [ ] Add brief UI feedback during detection (optional enhancement)
  - [ ] Ensure detection results flow through to CaptureData for upload
  - [ ] Handle detection failures gracefully (don't block capture)

- [ ] Task 9: Unit tests for DetectionResults model (AC: #1, #7)
  - [ ] Test Codable encoding/decoding
  - [ ] Test with partial results (some detections nil)
  - [ ] Test backward compatibility with captures without detection
  - [ ] Test JSON output format
  - [ ] Create file at ios/RialTests/Models/DetectionResultsTests.swift

- [ ] Task 10: Unit tests for DetectionOrchestrator (AC: #2, #3, #8)
  - [ ] Test parallel execution of detection services
  - [ ] Test graceful degradation with partial failures
  - [ ] Test performance (<200ms typical)
  - [ ] Test aggregation produces valid AggregatedConfidenceResult
  - [ ] Create file at ios/RialTests/Detection/DetectionOrchestratorTests.swift

- [ ] Task 11: Integration tests for upload flow (AC: #4, #5, #7)
  - [ ] Test upload with detection results includes detection multipart
  - [ ] Test upload without detection results works unchanged
  - [ ] Test metadata summary fields populated correctly
  - [ ] Verify JSON format matches expected backend schema

- [ ] Task 12: Update Xcode project (AC: all)
  - [ ] Add DetectionResults.swift to project
  - [ ] Add DetectionOrchestrator.swift to project
  - [ ] Add test files to RialTests target
  - [ ] Verify build succeeds

## Dev Notes

### Technical Approach

**Why Separate Orchestrator:**
Rather than adding detection logic directly to FrameProcessor, a dedicated DetectionOrchestrator:
1. Keeps FrameProcessor focused on frame conversion (single responsibility)
2. Makes detection testable independently
3. Allows detection to be called from other contexts if needed
4. Matches existing service pattern (MoireDetectionService, etc.)

**Parallel Execution Strategy:**
```swift
func runAllDetections(image: CGImage) async -> DetectionResults {
    async let moireTask = MoireDetectionService.shared.analyze(image: image)
    async let textureTask = TextureClassificationService.shared.classify(image: image)
    async let artifactsTask = ArtifactDetectionService.shared.analyze(image: image)

    let moire = await moireTask
    let texture = await textureTask
    let artifacts = await artifactsTask

    let aggregated = await ConfidenceAggregator.shared.aggregate(
        depth: nil, // Depth comes from separate LiDAR analysis
        moire: moire,
        texture: texture,
        artifacts: artifacts,
        enableEnhancedCrossValidation: true
    )

    return DetectionResults(
        moire: moire,
        texture: texture,
        artifacts: artifacts,
        aggregatedConfidence: aggregated,
        crossValidation: aggregated.crossValidation
    )
}
```

**Depth Integration Note:**
The DepthAnalysisResult comes from separate LiDAR processing (already in FrameProcessor). The aggregator receives depth separately when available. For privacy mode captures, depth analysis is done client-side and doesn't flow through detection orchestration.

**Payload Size Considerations:**
Each detection result is roughly:
- MoireAnalysisResult: ~500 bytes (peaks array, metadata)
- TextureClassificationResult: ~300 bytes (classification, confidence)
- ArtifactAnalysisResult: ~400 bytes (detection flags, confidences)
- AggregatedConfidenceResult: ~1KB (method breakdown, flags)
- CrossValidationResult: ~2KB (pairwise, intervals, anomalies)

Total: ~4-5KB typical, acceptable for multipart upload.

### Project Structure Notes

**New Files:**
- `ios/Rial/Models/DetectionResults.swift` - Container for all detection outputs
- `ios/Rial/Core/Detection/DetectionOrchestrator.swift` - Parallel detection runner
- `ios/RialTests/Models/DetectionResultsTests.swift` - Model tests
- `ios/RialTests/Detection/DetectionOrchestratorTests.swift` - Orchestrator tests

**Modified Files:**
- `ios/Rial/Models/CaptureData.swift` - Add detectionResults field
- `ios/Rial/Core/Capture/FrameProcessor.swift` - Add runDetection parameter
- `ios/Rial/Core/Networking/UploadService.swift` - Add detection multipart, extend metadata
- `ios/Rial/Features/Capture/CaptureViewModel.swift` - Enable detection by default
- `ios/Rial.xcodeproj/project.pbxproj` - Add new files

### Testing Standards

**Unit Tests (XCTest):**
- Test DetectionResults Codable round-trip
- Test DetectionOrchestrator with mocked services
- Test partial results (some services return nil/unavailable)
- Test upload payload format

**Integration Tests:**
- Test full capture flow with detection enabled
- Test backward compatibility with detection disabled
- Verify JSON output parseable (simulate backend validation)

**Performance Tests:**
```swift
func testDetectionOrchestratorPerformance() {
    let image = createTestImage()
    measure {
        _ = await DetectionOrchestrator.shared.runAllDetections(image: image)
    }
    // Assert average < 200ms
}
```

### References

**PRD Requirements:**
- [Source: docs/prd.md#Phase-1-iOS-Multi-Signal-Detection]
  - FR68: iOS app includes detection breakdown in capture payload
  - FR69: Backend stores and validates multi-signal detection results

**Epic Context:**
- [Source: docs/epics.md#Epic-9-iOS-Defense-in-Depth]
  - Multi-signal detection: Moire + Texture + Artifacts layered on LiDAR
  - Integration with capture and upload flow

**Existing Code Patterns:**
- [Source: ios/Rial/Models/CaptureData.swift] - Existing capture model structure
- [Source: ios/Rial/Core/Capture/FrameProcessor.swift] - Frame processing pipeline
- [Source: ios/Rial/Core/Networking/UploadService.swift] - Multipart upload structure
- [Source: ios/Rial/Core/Detection/ConfidenceAggregator.swift] - Aggregation with cross-validation

**Related Stories:**
- Story 9-1: MoireDetectionService (DONE) - provides MoireAnalysisResult
- Story 9-2: TextureClassificationService (DONE) - provides TextureClassificationResult
- Story 9-3: ArtifactDetectionService (DONE) - provides ArtifactAnalysisResult
- Story 9-4: ConfidenceAggregator (DONE) - aggregates all signals
- Story 9-5: CrossValidationService (DONE) - enhanced cross-validation
- Story 9-7: Backend Multi-Signal Storage (next) - receives detection payload

### Security Considerations

**Defense-in-Depth:**
This story integrates the multi-signal detection from Stories 9-1 through 9-5 into the actual capture flow. The aggregated detection results provide multiple independent verification signals that make spoofing attacks significantly harder.

**Trust Model:**
Detection results are computed client-side on the attested device. The aggregated confidence and cross-validation status accompany the capture to the backend, where they can be stored and displayed to verifiers.

### Learnings from Previous Stories

Based on Stories 9-1 through 9-5:

1. **Service Pattern:** Use final class singleton with shared property
2. **Async/Await:** Process on background queue with userInitiated QoS
3. **Logging:** os.log with dedicated category, os_signpost for performance
4. **Result Structs:** Make Codable, Sendable, Equatable
5. **Error Handling:** Return graceful defaults, don't throw from public API
6. **Backward Compatibility:** Add optional fields with defaults
7. **JSON Format:** Use snake_case CodingKeys to match Rust backend

---

_Story created: 2025-12-11_
_Epic: 9 - iOS Defense-in-Depth_
_FR Coverage: FR68 (Detection breakdown in payload)_
_Depends on: Stories 9-1, 9-2, 9-3, 9-4, 9-5 (all detection services and aggregation)_
_Enables: Story 9-7 (Backend Multi-Signal Storage)_

## Dev Agent Record

### Context Reference

N/A - Implementation based on story requirements, existing detection service patterns, and PRD/Epic specifications.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

### Completion Notes List

### File List

