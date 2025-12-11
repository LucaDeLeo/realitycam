# Story 9-4: Confidence Aggregation

Status: drafted

## Story

As a **rial. iOS app user**,
I want **my device to combine all detection signals (LiDAR, Moire, Texture, Artifacts) into a single weighted confidence score**,
So that **I receive an overall confidence level that reflects the strength of evidence from multiple independent verification methods**.

## Acceptance Criteria

### AC 1: AggregatedConfidenceResult Model
**Given** the need to aggregate multiple detection method results
**When** confidence aggregation is performed
**Then** the result struct contains:
1. `overallConfidence: Float` (0.0-1.0) - weighted combination of all methods
2. `confidenceLevel: ConfidenceLevel` - enum: veryHigh, high, medium, low, suspicious
3. `methodBreakdown: [DetectionMethod: MethodResult]` - individual method scores and status
4. `primarySignalValid: Bool` - true if LiDAR depth passed (55% weight)
5. `supportingSignalsAgree: Bool` - true if all supporting signals agree with primary
6. `flags: [ConfidenceFlag]` - any concerns or disagreements detected
7. `analysisTimeMs: Int64` - total aggregation processing time
8. `computedAt: Date` - timestamp of aggregation
9. `algorithmVersion: String` - "1.0" for tracking
10. `status: AggregationStatus` - success, partial, unavailable, error
11. Struct is Codable, Sendable, and Equatable

### AC 2: Detection Method Weighting per PRD
**Given** the PRD confidence weighting specification
**When** aggregating detection method scores
**Then**:
1. LiDAR depth analysis receives 55% weight (PRIMARY signal)
2. Moire pattern detection receives 15% weight (SUPPORTING signal)
3. Texture classification receives 15% weight (SUPPORTING signal)
4. Artifact detection receives 15% weight (SUPPORTING signal)
5. Weights are applied only to available methods
6. Missing methods have their weight redistributed proportionally
7. Total weights always sum to 1.0 after normalization

### AC 3: Input Processing from Detection Services
**Given** results from all detection services
**When** aggregating confidence
**Then**:
1. Accepts DepthAnalysisResult from DepthAnalysisService
2. Accepts MoireAnalysisResult from MoireDetectionService
3. Accepts TextureClassificationResult from TextureClassificationService
4. Accepts ArtifactAnalysisResult from ArtifactDetectionService
5. Handles any subset of inputs (graceful degradation)
6. Normalizes each method's score to 0.0-1.0 range
7. Converts method-specific "detected" flags to confidence impact

### AC 4: Confidence Level Thresholds
**Given** an aggregated confidence score
**When** determining confidence level
**Then**:
1. VERY_HIGH (>= 0.90): All methods available AND all agree AND primary passes
2. HIGH (>= 0.75): Primary passes AND most supporting signals agree
3. MEDIUM (>= 0.50): Primary passes OR strong supporting consensus
4. LOW (>= 0.25): Weak signals OR significant disagreement
5. SUSPICIOUS (< 0.25): Failed primary OR methods disagree significantly OR screen detected
6. Level is capped at MEDIUM if any detection method detects screen/print
7. Level requires VERY_HIGH threshold AND full agreement for VERY_HIGH

### AC 5: Cross-Validation Logic
**Given** multiple detection method results
**When** checking for cross-validation agreement
**Then**:
1. Computes agreement score between primary (LiDAR) and each supporting signal
2. LiDAR "real scene" should correlate with Moire "no screen detected"
3. LiDAR "real scene" should correlate with Texture "natural material"
4. LiDAR "real scene" should correlate with Artifacts "no artificial patterns"
5. Disagreement triggers flags array entry with specific concern
6. Agreement across all methods provides +5% confidence boost
7. Significant disagreement caps confidence at MEDIUM level

### AC 6: Confidence Flags
**Given** aggregation analysis
**When** concerns are detected
**Then** appropriate flags are added:
1. `.primarySignalFailed` - LiDAR depth analysis did not pass
2. `.screenDetected` - Moire or texture detected screen recapture
3. `.printDetected` - Artifact halftone detection triggered
4. `.methodsDisagree` - Supporting signals contradict each other
5. `.primarySupportingDisagree` - LiDAR contradicts supporting signals
6. `.partialAnalysis` - Some detection methods unavailable
7. `.lowConfidencePrimary` - LiDAR passed but with low confidence
8. `.ambiguousResults` - Multiple methods returned borderline scores

### AC 7: MethodResult Detail Structure
**Given** individual detection method results
**When** storing in methodBreakdown dictionary
**Then** each MethodResult contains:
1. `available: Bool` - whether method was executed
2. `score: Float?` - normalized 0.0-1.0 score (nil if unavailable)
3. `weight: Float` - actual weight applied (after redistribution)
4. `contribution: Float` - score * weight (actual contribution)
5. `status: String` - pass/fail/unavailable/error
6. `rawResult: Any?` - original result for debugging (optional)

### AC 8: Performance Target
**Given** iPhone 12 Pro or newer device
**When** aggregating detection results
**Then**:
1. Aggregation completes in < 10ms (pure computation, no I/O)
2. Does not block main thread (async execution)
3. Memory footprint < 5MB during aggregation
4. Can be called immediately after all detections complete

### AC 9: Integration with Capture Pipeline
**Given** the existing detection services and capture flow
**When** a photo is captured and all analyses complete
**Then**:
1. ConfidenceAggregator can be invoked with all available results
2. Aggregator exposes async/await interface
3. Logging via os.log with "confidenceaggregation" category
4. Result can be included in capture payload (Story 9-6)
5. Service is thread-safe for concurrent calls

## Tasks / Subtasks

- [ ] Task 1: Create AggregatedConfidenceResult and supporting types (AC: #1)
  - [ ] Define AggregatedConfidenceResult struct (Codable, Sendable, Equatable)
  - [ ] Define ConfidenceLevel enum (veryHigh, high, medium, low, suspicious)
  - [ ] Define DetectionMethod enum (lidar, moire, texture, artifacts)
  - [ ] Define MethodResult struct with score, weight, contribution, status
  - [ ] Define ConfidenceFlag enum with all concern types
  - [ ] Define AggregationStatus enum (success, partial, unavailable, error)
  - [ ] Define ConfidenceAggregationConstants with weights and thresholds
  - [ ] Create file at ios/Rial/Models/AggregatedConfidenceResult.swift

- [ ] Task 2: Create ConfidenceAggregator service singleton (AC: #8, #9)
  - [ ] Create file at ios/Rial/Core/Detection/ConfidenceAggregator.swift
  - [ ] Implement as final class with shared singleton
  - [ ] Add async aggregate(...) method accepting all detection results
  - [ ] Support partial inputs (any subset of detection results)
  - [ ] Use DispatchQueue.global(qos: .userInitiated) for background processing
  - [ ] Add os.log logging with "confidenceaggregation" category
  - [ ] Add os_signpost for performance tracking

- [ ] Task 3: Implement score normalization (AC: #3)
  - [ ] Normalize DepthAnalysisResult to 0.0-1.0 (isLikelyRealScene -> 1.0 if true)
  - [ ] Normalize MoireAnalysisResult (invert: high confidence screen = low score)
  - [ ] Normalize TextureClassificationResult (natural material = high score)
  - [ ] Normalize ArtifactAnalysisResult (invert: artifact detected = low score)
  - [ ] Handle edge cases (unavailable results, invalid data)
  - [ ] Document normalization logic in comments

- [ ] Task 4: Implement weighted aggregation (AC: #2)
  - [ ] Define base weights: LiDAR 0.55, Moire 0.15, Texture 0.15, Artifacts 0.15
  - [ ] Calculate available method mask
  - [ ] Redistribute weights from unavailable methods proportionally
  - [ ] Compute weighted sum: sum(score_i * weight_i)
  - [ ] Verify weights sum to 1.0 after redistribution
  - [ ] Log weight distribution for debugging

- [ ] Task 5: Implement confidence level determination (AC: #4)
  - [ ] Define threshold constants (0.90, 0.75, 0.50, 0.25)
  - [ ] Check VERY_HIGH requirements (threshold + all available + all agree + primary pass)
  - [ ] Check HIGH requirements (threshold + primary pass + most agree)
  - [ ] Check MEDIUM requirements (threshold + some signals pass)
  - [ ] Check LOW requirements (threshold)
  - [ ] Default to SUSPICIOUS for remaining cases
  - [ ] Apply caps for detected screens/prints

- [ ] Task 6: Implement cross-validation logic (AC: #5)
  - [ ] Compare LiDAR result with Moire result (agreement check)
  - [ ] Compare LiDAR result with Texture result (agreement check)
  - [ ] Compare LiDAR result with Artifact result (agreement check)
  - [ ] Compute overall agreement score (0.0-1.0)
  - [ ] Determine if supporting signals agree with each other
  - [ ] Apply +5% boost for full agreement
  - [ ] Cap confidence at MEDIUM for significant disagreement

- [ ] Task 7: Implement flag generation (AC: #6)
  - [ ] Check for primarySignalFailed flag
  - [ ] Check for screenDetected flag (Moire or Texture)
  - [ ] Check for printDetected flag (Artifact halftone)
  - [ ] Check for methodsDisagree flag (supporting vs supporting)
  - [ ] Check for primarySupportingDisagree flag (LiDAR vs supporting)
  - [ ] Check for partialAnalysis flag (any method unavailable)
  - [ ] Check for lowConfidencePrimary flag
  - [ ] Check for ambiguousResults flag (borderline scores)

- [ ] Task 8: Build MethodResult breakdown (AC: #7)
  - [ ] Create MethodResult for LiDAR with score, weight, contribution
  - [ ] Create MethodResult for Moire with score, weight, contribution
  - [ ] Create MethodResult for Texture with score, weight, contribution
  - [ ] Create MethodResult for Artifacts with score, weight, contribution
  - [ ] Store in dictionary keyed by DetectionMethod
  - [ ] Include status string for each method

- [ ] Task 9: Unit tests (AC: #1-#8)
  - [ ] Test result struct encoding/decoding
  - [ ] Test weight normalization when all methods available
  - [ ] Test weight redistribution when some methods unavailable
  - [ ] Test confidence level thresholds
  - [ ] Test cross-validation agreement detection
  - [ ] Test flag generation for various scenarios
  - [ ] Test full aggregation with real-world-like inputs
  - [ ] Test performance (should be <10ms)
  - [ ] Test edge cases (all unavailable, all fail, all pass)

- [ ] Task 10: Integration preparation (AC: #9)
  - [ ] Document service interface for Story 9-6 integration
  - [ ] Ensure thread safety for concurrent calls
  - [ ] Create example usage in Dev Notes
  - [ ] Verify compatibility with existing DepthAnalysisService

## Dev Notes

### Technical Approach

**Why Confidence Aggregation:**
Multiple independent detection methods provide defense-in-depth against sophisticated attacks. The Chimera attack (USENIX Security 2025) demonstrated that single detection methods can be bypassed. By combining LiDAR (hardware-based physical signal) with software detection methods (Moire, Texture, Artifacts), we create a multi-layered verification system.

**Trust Hierarchy (from PRD):**
```
1. Hardware Attestation (LiDAR, TEE/StrongBox) -> PRIMARY
2. Physical Signals (Parallax, Depth) -> STRONG SUPPORTING
3. Detection Algorithms (Moire, Texture) -> SUPPORTING (vulnerable to adversarial attack)
```

**Weight Distribution:**
```swift
enum ConfidenceAggregationConstants {
    // PRD-specified weights
    static let lidarWeight: Float = 0.55      // PRIMARY - most reliable physical signal
    static let moireWeight: Float = 0.15      // SUPPORTING - Chimera vulnerability
    static let textureWeight: Float = 0.15    // SUPPORTING
    static let artifactsWeight: Float = 0.15  // SUPPORTING

    // Confidence thresholds
    static let veryHighThreshold: Float = 0.90
    static let highThreshold: Float = 0.75
    static let mediumThreshold: Float = 0.50
    static let lowThreshold: Float = 0.25

    // Cross-validation
    static let agreementBoost: Float = 0.05    // +5% for full agreement
    static let disagreementCap: ConfidenceLevel = .medium  // Cap if significant disagreement
}
```

**Score Normalization:**

Each detection method produces different result formats. Normalization converts to 0.0-1.0 where:
- 1.0 = Strong evidence of real scene
- 0.0 = Strong evidence of artificial/recaptured scene

```swift
// LiDAR: Real scene = high score
func normalizeLiDAR(_ result: DepthAnalysisResult) -> Float {
    guard result.status == .completed else { return 0 }
    // isLikelyRealScene is primary indicator
    // Boost based on depth metrics
    let baseScore: Float = result.isLikelyRealScene ? 0.8 : 0.2
    let varianceBonus = min(result.depthVariance / 2.0, 0.1)  // Up to +0.1 for variance
    let layerBonus = min(Float(result.depthLayers) / 10.0, 0.1)  // Up to +0.1 for layers
    return min(baseScore + varianceBonus + layerBonus, 1.0)
}

// Moire: Screen detected = LOW score (inverted)
func normalizeMoire(_ result: MoireAnalysisResult) -> Float {
    guard result.status == .completed else { return 0.5 }  // Neutral if unavailable
    // No screen = high score; screen detected = low score
    return result.detected ? (1.0 - result.confidence) : 1.0
}

// Texture: Natural material = high score
func normalizeTexture(_ result: TextureClassificationResult) -> Float {
    guard result.status == .completed else { return 0.5 }
    // naturalMaterial -> high, screen/print -> low
    return result.isNaturalMaterial ? result.confidence : (1.0 - result.confidence)
}

// Artifacts: Artifacts detected = LOW score (inverted)
func normalizeArtifacts(_ result: ArtifactAnalysisResult) -> Float {
    guard result.status == .success else { return 0.5 }
    // No artifacts = high score
    return result.isLikelyArtificial ? (1.0 - result.overallConfidence) : 1.0
}
```

**Weight Redistribution:**

When a method is unavailable, its weight is redistributed to available methods:

```swift
func redistributeWeights(available: Set<DetectionMethod>) -> [DetectionMethod: Float] {
    let baseWeights: [DetectionMethod: Float] = [
        .lidar: 0.55,
        .moire: 0.15,
        .texture: 0.15,
        .artifacts: 0.15
    ]

    let totalAvailable = available.reduce(Float(0)) { $0 + (baseWeights[$1] ?? 0) }
    guard totalAvailable > 0 else { return [:] }

    var redistributed: [DetectionMethod: Float] = [:]
    for method in available {
        if let base = baseWeights[method] {
            redistributed[method] = base / totalAvailable  // Normalize to sum = 1.0
        }
    }
    return redistributed
}
```

**Cross-Validation Agreement:**

```swift
func checkAgreement(lidar: DepthAnalysisResult?, moire: MoireAnalysisResult?,
                    texture: TextureClassificationResult?, artifacts: ArtifactAnalysisResult?)
    -> (agree: Bool, flags: [ConfidenceFlag])
{
    var flags: [ConfidenceFlag] = []

    let lidarSaysReal = lidar?.isLikelyRealScene ?? nil
    let moireSaysNoScreen = moire?.detected == false
    let textureSaysNatural = texture?.isNaturalMaterial ?? nil
    let artifactsSaysClean = artifacts?.isLikelyArtificial == false

    // Check primary vs supporting agreement
    if let real = lidarSaysReal {
        if moireSaysNoScreen != real { flags.append(.primarySupportingDisagree) }
        if let natural = textureSaysNatural, natural != real { flags.append(.primarySupportingDisagree) }
        if artifactsSaysClean != real { flags.append(.primarySupportingDisagree) }
    }

    // Check supporting vs supporting agreement
    let supportingSignals = [moireSaysNoScreen, textureSaysNatural, artifactsSaysClean].compactMap { $0 }
    let allAgree = supportingSignals.allSatisfy { $0 == supportingSignals.first }
    if !allAgree { flags.append(.methodsDisagree) }

    return (flags.isEmpty, flags)
}
```

### Project Structure Notes

**New Files:**
- `ios/Rial/Models/AggregatedConfidenceResult.swift` - Result struct and all supporting types
- `ios/Rial/Core/Detection/ConfidenceAggregator.swift` - Main aggregation service
- `ios/RialTests/Detection/ConfidenceAggregatorTests.swift` - Unit tests

**Existing Directory:**
- `ios/Rial/Core/Detection/` - Created by Story 9-1, contains sibling services

**Modified Files:**
- `ios/Rial.xcodeproj/project.pbxproj` - Add new files to project

### Code Patterns from Stories 9-1, 9-2, 9-3

Following established patterns:

```swift
// Service singleton pattern (matching MoireDetectionService, etc.)
public final class ConfidenceAggregator: @unchecked Sendable {
    public static let shared = ConfidenceAggregator()

    private static let logger = Logger(subsystem: "app.rial", category: "confidenceaggregation")
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    private init() {
        Self.logger.debug("ConfidenceAggregator initialized")
    }

    /// Aggregates all detection method results into unified confidence.
    ///
    /// - Parameters:
    ///   - depth: LiDAR depth analysis result (optional)
    ///   - moire: Moire pattern detection result (optional)
    ///   - texture: Texture classification result (optional)
    ///   - artifacts: Artifact detection result (optional)
    /// - Returns: Aggregated confidence result
    public func aggregate(
        depth: DepthAnalysisResult? = nil,
        moire: MoireAnalysisResult? = nil,
        texture: TextureClassificationResult? = nil,
        artifacts: ArtifactAnalysisResult? = nil
    ) async -> AggregatedConfidenceResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let startTime = CFAbsoluteTimeGetCurrent()
                let result = self.performAggregation(
                    depth: depth, moire: moire, texture: texture, artifacts: artifacts
                )
                let elapsed = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

                continuation.resume(returning: result.with(analysisTimeMs: elapsed))
            }
        }
    }
}
```

### Testing Standards

**Unit Tests (XCTest):**

```swift
// Test all methods pass -> VERY_HIGH
func testAllMethodsPassVeryHigh() async {
    let depth = DepthAnalysisResult(
        depthVariance: 1.5, depthLayers: 5, edgeCoherence: 0.8,
        minDepth: 0.5, maxDepth: 4.0, isLikelyRealScene: true
    )
    let moire = MoireAnalysisResult.notDetected(analysisTimeMs: 30)
    let texture = TextureClassificationResult.natural(confidence: 0.9, analysisTimeMs: 20)
    let artifacts = ArtifactAnalysisResult.clean(analysisTimeMs: 50)

    let result = await ConfidenceAggregator.shared.aggregate(
        depth: depth, moire: moire, texture: texture, artifacts: artifacts
    )

    XCTAssertEqual(result.confidenceLevel, .veryHigh)
    XCTAssertGreaterThanOrEqual(result.overallConfidence, 0.90)
    XCTAssertTrue(result.primarySignalValid)
    XCTAssertTrue(result.supportingSignalsAgree)
    XCTAssertTrue(result.flags.isEmpty)
}

// Test screen detected -> capped at MEDIUM
func testScreenDetectedCapsMedium() async {
    let depth = DepthAnalysisResult(..., isLikelyRealScene: true)  // LiDAR says real
    let moire = MoireAnalysisResult(detected: true, confidence: 0.85, ...)  // Screen detected!

    let result = await ConfidenceAggregator.shared.aggregate(depth: depth, moire: moire)

    XCTAssertLessThanOrEqual(result.confidenceLevel.rawValue, ConfidenceLevel.medium.rawValue)
    XCTAssertTrue(result.flags.contains(.screenDetected))
    XCTAssertFalse(result.supportingSignalsAgree)
}

// Test weight redistribution when methods unavailable
func testWeightRedistributionPartialInput() async {
    // Only LiDAR available
    let depth = DepthAnalysisResult(..., isLikelyRealScene: true)

    let result = await ConfidenceAggregator.shared.aggregate(depth: depth)

    XCTAssertEqual(result.methodBreakdown[.lidar]?.weight, 1.0)  // Gets full weight
    XCTAssertTrue(result.flags.contains(.partialAnalysis))
}

// Test performance
func testPerformanceUnder10ms() {
    measure {
        let depth = DepthAnalysisResult(...)
        let moire = MoireAnalysisResult(...)
        let texture = TextureClassificationResult(...)
        let artifacts = ArtifactAnalysisResult(...)

        _ = await ConfidenceAggregator.shared.aggregate(
            depth: depth, moire: moire, texture: texture, artifacts: artifacts
        )
    }
    // Assert average < 10ms
}
```

### References

**PRD Requirements:**
- [Source: docs/prd.md#Phase-1-iOS-Multi-Signal-Detection]
  - FR66: iOS app aggregates confidence scores from all available detection methods
  - Confidence weighting: LiDAR 55%, Moire 15%, Texture 15%, Artifacts 15%
  - Performance target: Total analysis <50ms (aggregation is <10ms of this)

**Epic Context:**
- [Source: docs/epics.md#Epic-9-iOS-Defense-in-Depth]
  - Multi-signal detection with attestation-first trust model
  - Confidence aggregation combines all signals with PRD-specified weights
  - Cross-validation when multiple methods available

**Multi-Signal Detection Architecture:**
- [Source: docs/prd.md#Multi-Signal-Detection-Architecture]
  - Trust hierarchy: Hardware attestation PRIMARY, detection algorithms SUPPORTING
  - Agreement -> +5% boost; Disagreement -> cap at MEDIUM
  - iOS Pro weights: lidar 0.55, moire 0.15, texture 0.15, supporting 0.15

**Related Stories:**
- Story 8-1: Client-Side Depth Analysis Service (DepthAnalysisResult input)
- Story 9-1: Moire Pattern Detection (MoireAnalysisResult input) - DONE
- Story 9-2: Texture Classification (TextureClassificationResult input)
- Story 9-3: Artifact Detection (ArtifactAnalysisResult input)
- Story 9-5: Cross-Validation Logic - extends this story's agreement checks
- Story 9-6: Detection Payload Integration - sends aggregated results to backend

**Existing Code Patterns:**
- [Source: ios/Rial/Core/Detection/MoireDetectionService.swift] - Service singleton pattern
- [Source: ios/Rial/Models/DepthAnalysisResult.swift] - Result struct pattern
- [Source: ios/Rial/Models/MoireAnalysisResult.swift] - Detection result pattern

### Security Considerations

**Chimera Attack Awareness:**
Per PRD research (USENIX Security 2025), single detection methods can be bypassed. This aggregator implements the attestation-first trust model:

1. LiDAR is PRIMARY (55%) - hardware-based, prohibitively expensive to spoof
2. Detection algorithms are SUPPORTING (45% combined) - can be bypassed with effort
3. Cross-validation catches inconsistencies between methods
4. Disagreement flags alert to potential manipulation attempts

**Trust Model:**
```
Confidence Aggregation Role: Combines all signals with PRD weights
LiDAR Weight: 0.55 (PRIMARY - physical hardware signal)
Supporting Weight: 0.45 (Moire + Texture + Artifacts, 15% each)
Cross-Validation: Agreement boost +5%, Disagreement cap at MEDIUM
Security: Never rely on supporting signals alone for HIGH/VERY_HIGH
```

### Learnings from Stories 9-1, 9-2, 9-3

1. **Singleton Pattern:** Use final class with shared singleton
2. **Async/Await:** Return results via async function, process on background queue
3. **Logging:** Use os.log with dedicated category, os_signpost for performance
4. **Algorithm Constants:** Define all thresholds in dedicated enum
5. **Result Struct:** Make Codable, Sendable, Equatable for flexibility
6. **Error Handling:** Return graceful defaults, don't throw from public API
7. **Status Enum:** Include status for success/unavailable/error states
8. **Factory Methods:** Provide convenient factory methods for common cases

---

_Story created: 2025-12-11_
_Epic: 9 - iOS Defense-in-Depth_
_FR Coverage: FR66 (Confidence aggregation from all detection methods)_
_Depends on: Stories 9-1, 9-2, 9-3 (detection services), Epic 6/8 (DepthAnalysisService)_
_Enables: Story 9-5 (Cross-Validation Logic), Story 9-6 (Detection Payload Integration)_

## Dev Agent Record

### Context Reference

N/A - Story drafted based on PRD, epics, and Stories 9-1/9-2/9-3 patterns.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story is drafted, not yet implemented.

### File List

N/A - Story is drafted, not yet implemented.
