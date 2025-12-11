# Story 9-5: Cross-Validation Logic

Status: ready-for-dev

## Story

As a **rial. iOS app user**,
I want **my device to perform advanced cross-validation between detection methods including pairwise correlation, temporal consistency, and confidence intervals**,
So that **anomalous signal patterns are detected and confidence estimates are more robust against sophisticated spoofing attempts**.

## Acceptance Criteria

### AC 1: CrossValidationService Implementation
**Given** results from multiple detection methods (LiDAR, moire, texture, artifacts)
**When** the CrossValidationService analyzes them
**Then**:
1. Service is implemented as final class singleton (matching existing detection services)
2. Exposes async/await interface: `validate(depth:moire:texture:artifacts:) async -> CrossValidationResult`
3. Performs analysis on background queue (userInitiated QoS)
4. Completes in <5ms for single-frame analysis
5. Logs via os.log with "crossvalidation" category
6. Thread-safe for concurrent calls

### AC 2: Pairwise Consistency Analysis
**Given** normalized scores from all available detection methods
**When** computing pairwise consistency
**Then**:
1. Computes consistency agreement score between each pair of methods (NOTE: single-frame analysis computes expected-vs-actual agreement, not Pearson correlation which requires multiple samples):
   - LiDAR vs Moire (both detect screens differently)
   - LiDAR vs Texture (depth should correlate with material)
   - LiDAR vs Artifacts (physical depth vs visual artifacts)
   - Moire vs Texture (both analyze 2D image properties)
   - Moire vs Artifacts (frequency vs temporal/spatial patterns)
   - Texture vs Artifacts (material vs artifact presence)
2. Identifies "unexpected correlations" (e.g., high moire but LiDAR says real)
3. Returns PairwiseConsistency struct with method pair, agreement score, and expected range
4. Flags pairs outside expected consistency bounds (configurable thresholds)

### AC 3: Temporal Consistency Checks (Multi-Frame)
**Given** detection results from multiple frames (video capture or burst photos)
**When** analyzing temporal consistency
**Then**:
1. Tracks score variance across frames for each method
2. Computes temporal stability score (0.0-1.0) - stable results = higher
3. Detects sudden score jumps (>0.3 delta between consecutive frames)
4. Identifies "flickering" methods (high variance, oscillating scores)
5. Returns TemporalConsistency struct with:
   - `frameCount: Int`
   - `stabilityScores: [DetectionMethod: Float]`
   - `anomalies: [TemporalAnomaly]` (sudden jumps, oscillations)
6. Falls back gracefully for single-frame analysis (returns neutral stability)

### AC 4: Confidence Interval Estimation
**Given** point estimate confidence scores from each method
**When** computing confidence intervals
**Then**:
1. Generates confidence intervals instead of single point estimates
2. Uses bootstrap-style estimation from method variance and reliability
3. Returns ConfidenceInterval struct per method:
   - `lowerBound: Float` (95% confidence)
   - `pointEstimate: Float`
   - `upperBound: Float` (95% confidence)
   - `width: Float` (uncertainty measure)
4. Computes overall aggregated confidence interval
5. Flags high-uncertainty cases (interval width > 0.3)
6. Incorporates method reliability weights (LiDAR narrower interval than software methods)

### AC 5: Anomaly Pattern Detection
**Given** cross-validation analysis results
**When** checking for anomalous patterns
**Then** detects and flags:
1. **Contradictory signals:** LiDAR says flat but texture says real material
2. **Too-perfect agreement:** All methods exactly agree (possible adversarial input)
3. **Isolated disagreement:** One method strongly differs from all others
4. **Score clustering:** Scores suspiciously clustered at boundaries (0.0, 0.5, 1.0)
5. **Correlation anomalies:** Expected correlations absent or unexpected ones present
6. Returns AnomalyReport with:
   - `anomalyType: AnomalyType` enum
   - `severity: AnomalySeverity` (low, medium, high)
   - `affectedMethods: [DetectionMethod]`
   - `description: String`
   - `confidenceImpact: Float` (suggested penalty)

### AC 6: CrossValidationResult Output
**Given** completed cross-validation analysis
**When** returning results
**Then** result struct contains:
1. `validationStatus: ValidationStatus` (.pass, .warn, .fail)
2. `pairwiseConsistencies: [PairwiseConsistency]`
3. `temporalConsistency: TemporalConsistency?` (nil for single-frame)
4. `confidenceIntervals: [DetectionMethod: ConfidenceInterval]`
5. `aggregatedInterval: ConfidenceInterval`
6. `anomalies: [AnomalyReport]`
7. `overallPenalty: Float` (0.0-0.5 reduction to apply)
8. `analysisTimeMs: Int64`
9. `algorithmVersion: String` ("1.0")

### AC 7: Integration with ConfidenceAggregator
**Given** the existing ConfidenceAggregator (Story 9-4) with basic checkCrossValidation() at lines 481-522
**When** enhanced cross-validation is performed
**Then**:
1. Refactor ConfidenceAggregator.checkCrossValidation() to call CrossValidationService internally (keeping existing API signature)
2. Enhanced cross-validation is opt-in via optional parameter `enableEnhancedCrossValidation: Bool = false` initially
3. CrossValidationResult is incorporated into final confidence calculation when enabled
4. Anomaly penalties reduce overall confidence appropriately
5. Confidence intervals flow through to final result
6. Flags from cross-validation appear in AggregatedConfidenceResult
7. Maintains backward compatibility: existing behavior when enableEnhancedCrossValidation=false (existing tests pass)
8. New optional field in AggregatedConfidenceResult: `crossValidation: CrossValidationResult?`

### AC 8: Performance and Memory Targets
**Given** cross-validation analysis on iPhone 12 Pro or newer
**When** processing detection results
**Then**:
1. Single-frame CrossValidationService analysis completes in <5ms (combined with ConfidenceAggregator 10ms target = 15ms total budget for full aggregation+validation)
2. Multi-frame analysis (30 frames) completes in <20ms
3. Memory footprint <5MB during analysis
4. No main thread blocking
5. Graceful handling of partial data (some methods unavailable)

## Tasks / Subtasks

- [ ] Task 1: Create CrossValidationResult and supporting types (AC: #2, #3, #4, #5, #6)
  - [ ] Define CrossValidationResult struct (Codable, Sendable, Equatable)
  - [ ] Define PairwiseConsistency struct (methodA, methodB, agreementScore, expectedRange, isAnomaly)
  - [ ] Define TemporalConsistency struct (frameCount, stabilityScores, anomalies)
  - [ ] Define TemporalAnomaly struct (frameIndex, method, deltaScore, type)
  - [ ] Define ConfidenceInterval struct (lowerBound, pointEstimate, upperBound, width)
  - [ ] Define AnomalyReport struct (type, severity, affectedMethods, description, impact)
  - [ ] Define AnomalyType enum (contradictory, tooPerfect, isolated, clustering, correlation)
  - [ ] Define AnomalySeverity enum (low, medium, high)
  - [ ] Define ValidationStatus enum (pass, warn, fail)
  - [ ] Add CrossValidationConstants enum with thresholds
  - [ ] Create file at ios/Rial/Models/CrossValidationResult.swift

- [ ] Task 2: Create CrossValidationService singleton (AC: #1, #8)
  - [ ] Create file at ios/Rial/Core/Detection/CrossValidationService.swift
  - [ ] Implement as final class with shared singleton
  - [ ] Add async validate(depth:moire:texture:artifacts:) method - accepts raw detection results (not pre-normalized scores); service normalizes internally using same logic as ConfidenceAggregator
  - [ ] Add async validateMultiFrame(frames:) method accepting DetectionFrameSet struct (see Task 2b)
  - [ ] Use DispatchQueue.global(qos: .userInitiated) for background processing
  - [ ] Add os.log logging with "crossvalidation" category
  - [ ] Add os_signpost for performance tracking

- [ ] Task 2b: Define DetectionFrameSet input type for multi-frame analysis (AC: #3)
  - [ ] Create DetectionFrameSet struct containing array of frame results
  - [ ] Each frame contains: frameIndex, timestamp, and optional results for each detection method
  - [ ] Struct: `struct DetectionFrameSet: Sendable { let frames: [DetectionFrame] }`
  - [ ] Frame: `struct DetectionFrame: Sendable { let index: Int; let timestamp: TimeInterval; let depth: DepthAnalysisResult?; let moire: MoireAnalysisResult?; let texture: TextureClassificationResult?; let artifacts: ArtifactAnalysisResult? }`

- [ ] Task 3: Implement pairwise consistency analysis (AC: #2)
  - [ ] Normalize all detection scores to 0.0-1.0 scale (reuse ConfidenceAggregator normalization logic)
  - [ ] Compute expected-vs-actual agreement score for each method pair (single-frame consistency, not Pearson correlation)
  - [ ] Define expected consistency ranges per pair:
    - [ ] LiDAR-Moire: Expected inverse relationship (real depth = no screen moire)
    - [ ] LiDAR-Texture: Expected positive relationship (real depth = real texture)
    - [ ] Moire-Texture: Expected consistency (both 2D signals)
  - [ ] Flag pairs outside expected consistency bounds
  - [ ] Return array of PairwiseConsistency results

- [ ] Task 4: Implement temporal consistency checks (AC: #3)
  - [ ] Accept array of detection result sets (one per frame)
  - [ ] Compute per-method score variance across frames
  - [ ] Detect sudden jumps (>0.3 delta threshold)
  - [ ] Detect oscillations (alternating high/low pattern)
  - [ ] Compute stability score: 1.0 - normalized_variance
  - [ ] Return TemporalConsistency result with anomaly list
  - [ ] Handle single-frame gracefully (return neutral values)

- [ ] Task 5: Implement confidence interval estimation (AC: #4)
  - [ ] Compute interval width based on method reliability:
    - [ ] LiDAR: narrow interval (high reliability), base width 0.05
    - [ ] Moire: medium interval, base width 0.10
    - [ ] Texture: medium interval, base width 0.10
    - [ ] Artifacts: wider interval, base width 0.12
  - [ ] Adjust interval based on score certainty (mid-range = wider)
  - [ ] Compute aggregated interval from individual intervals
  - [ ] Apply bootstrap-style variance estimation when multiple frames available
  - [ ] Return ConfidenceInterval per method plus aggregated

- [ ] Task 6: Implement anomaly pattern detection (AC: #5)
  - [ ] Check for contradictory signals (depth vs detection disagreement)
  - [ ] Check for too-perfect agreement (all scores within 0.02)
  - [ ] Check for isolated disagreement (one method >0.4 from others)
  - [ ] Check for boundary clustering (scores at 0.0, 0.5, 1.0)
  - [ ] Check for missing expected correlations
  - [ ] Compute severity and confidence impact for each anomaly
  - [ ] Return array of AnomalyReport structs

- [ ] Task 7: Implement overall validation scoring (AC: #6)
  - [ ] Aggregate all anomaly impacts into overallPenalty (capped at 0.5)
  - [ ] Determine validationStatus from anomaly count/severity:
    - [ ] .pass: no anomalies or only low severity
    - [ ] .warn: 1-2 medium severity anomalies
    - [ ] .fail: any high severity or 3+ medium anomalies
  - [ ] Assemble complete CrossValidationResult

- [ ] Task 8: Integrate with ConfidenceAggregator (AC: #7)
  - [ ] Add optional `enableEnhancedCrossValidation: Bool = false` parameter to aggregate() method
  - [ ] Refactor checkCrossValidation() to delegate to CrossValidationService when enhanced mode enabled
  - [ ] When disabled: maintain existing binary agreement logic (backward compatibility)
  - [ ] When enabled: call CrossValidationService.validate() and incorporate full result
  - [ ] Apply overallPenalty to confidence score (only when enhanced enabled)
  - [ ] Add new flags for cross-validation issues:
    - [ ] .consistencyAnomaly (renamed from correlationAnomaly)
    - [ ] .temporalInconsistency
    - [ ] .highUncertainty
  - [ ] Add crossValidation field to AggregatedConfidenceResult
  - [ ] Update AggregatedConfidenceResult model
  - [ ] Ensure existing unit tests still pass with enableEnhancedCrossValidation=false

- [ ] Task 9: Unit tests for CrossValidationService (AC: #1-#8)
  - [ ] Test pairwise correlation with known score sets
  - [ ] Test temporal consistency with synthetic frame sequences
  - [ ] Test confidence interval computation
  - [ ] Test anomaly detection for each anomaly type
  - [ ] Test integration with ConfidenceAggregator
  - [ ] Test performance (<5ms single frame)
  - [ ] Test edge cases (missing methods, single frame)
  - [ ] Create file at ios/RialTests/Detection/CrossValidationServiceTests.swift

- [ ] Task 10: Integration tests (AC: #7)
  - [ ] Test full pipeline: detection services -> aggregator -> cross-validation
  - [ ] Test backward compatibility with existing capture flow
  - [ ] Verify flags propagate correctly to final result

## Dev Notes

### Technical Approach

**Why Enhanced Cross-Validation:**
Story 9-4 implemented basic cross-validation that checks binary agreement between methods. This story enhances it with:
1. **Pairwise correlations** - Detect subtle inconsistencies between specific method pairs
2. **Temporal consistency** - For video/burst, ensure signals are stable across frames
3. **Confidence intervals** - Communicate uncertainty, not just point estimates
4. **Anomaly detection** - Catch sophisticated attacks that game individual methods

**Pairwise Consistency Analysis:**
For single-frame analysis with 4 methods, we compute 6 pairwise consistency checks. Since Pearson correlation requires multiple samples (impossible in single-frame), we instead compute **expected-vs-actual agreement scores**: given the score from method A, does method B's score fall within the expected range?

The key insight is that certain pairs should have predictable relationships:
- LiDAR detects physical depth; Moire detects screen pixels. A real scene should have: high LiDAR confidence, low Moire detection. These should be inversely related.
- LiDAR and Texture should agree: real 3D scenes have real material textures.

**Expected Relationship Matrix (initial estimates - tune from real-world data):**
```
           LiDAR   Moire   Texture  Artifacts
LiDAR      1.0     -0.7    +0.6     -0.5
Moire      -0.7    1.0     +0.4     +0.6
Texture    +0.6    +0.4    1.0      -0.3
Artifacts  -0.5    +0.6    -0.3     1.0
```
NOTE: These values are initial heuristic estimates. Actual threshold tuning should be informed by real capture data analysis.

Deviations from expected relationships indicate potential manipulation.

**Temporal Consistency:**
For video captures (10fps depth), detection scores should be relatively stable across consecutive frames. Large jumps or oscillations suggest:
- Intermittent spoofing (attacker switching between real/fake)
- Detection method instability
- Edge cases the methods handle poorly

Stability score formula:
```swift
stabilityScore = 1.0 - (variance / maxExpectedVariance)
```

**Confidence Intervals:**
Instead of returning 0.87 confidence, return [0.82, 0.87, 0.92]. This communicates:
- The point estimate
- Uncertainty bounds
- Method reliability (LiDAR = narrow, software = wider)

Interval width calculation:
```swift
width = baseWidth * (1.0 + uncertaintyFactor)
// uncertaintyFactor is higher for mid-range scores (0.4-0.6)
```

**Anomaly Detection Types:**

1. **Contradictory:** LiDAR says flat (score 0.2) but Texture says real material (score 0.9). One of them is wrong.

2. **Too-Perfect:** All four methods return exactly 0.88. Natural variation should produce slight differences. This suggests adversarial input crafted to pass all checks equally.

3. **Isolated:** Three methods agree at 0.85, one returns 0.20. Investigate the outlier.

4. **Clustering:** Scores suspiciously at decision boundaries (0.5) or extremes (0.0, 1.0). Natural scenes rarely produce such clean numbers.

5. **Correlation:** Expected negative correlation absent, or unexpected positive correlation present.

### Project Structure Notes

**New Files:**
- `ios/Rial/Models/CrossValidationResult.swift` - Result structs and types
- `ios/Rial/Core/Detection/CrossValidationService.swift` - Main service
- `ios/RialTests/Detection/CrossValidationServiceTests.swift` - Unit tests

**Modified Files:**
- `ios/Rial/Core/Detection/ConfidenceAggregator.swift` - Add cross-validation call
- `ios/Rial/Models/AggregatedConfidenceResult.swift` - Add crossValidation field, new flags
- `ios/Rial.xcodeproj/project.pbxproj` - Add new files to project

### Testing Standards

**Unit Tests (XCTest):**
- Test each analysis component independently
- Use synthetic score sets with known expected outputs
- Test edge cases: missing methods, single frame, all same scores

**Test Scenarios:**
1. Normal real scene (all methods agree, expect .pass)
2. Obvious screen (LiDAR flat, moire high, expect flags but .pass validation)
3. Contradictory signals (LiDAR says real, moire says screen, expect .warn)
4. Temporal instability (jumping scores, expect .warn)
5. Too-perfect scores (all identical, expect .warn)
6. Sophisticated attack pattern (expect .fail with high severity anomaly)

**Performance Tests:**
```swift
func testPerformanceSingleFrame() {
    let results = createTestDetectionResults()
    measure {
        _ = await CrossValidationService.shared.validate(
            depth: results.depth,
            moire: results.moire,
            texture: results.texture,
            artifacts: results.artifacts
        )
    }
    // Assert average < 5ms
}
```

### References

**PRD Requirements:**
- [Source: docs/prd.md#Multi-Signal-Detection-Architecture]
  - Cross-Validation: Agreement boost (+5%), disagreement cap (MEDIUM)
  - Evidence model includes cross_validation.methods_agree and disagreement_score

- [Source: docs/prd.md#Phase-1-iOS-Multi-Signal-Detection]
  - FR67: iOS app performs cross-validation when multiple methods available

**Epic Context:**
- [Source: docs/epics.md#Epic-9-iOS-Defense-in-Depth]
  - Cross-validation: all methods agree -> confidence boost; disagreement -> flag for review
  - FR67 maps to Epic 9: Cross-validation logic

**Existing Code Patterns:**
- [Source: ios/Rial/Core/Detection/ConfidenceAggregator.swift] - Basic cross-validation in checkCrossValidation() (lines 481-522). Story 9-5 EXTENDS this by having checkCrossValidation() delegate to CrossValidationService when enhanced mode enabled. Existing binary agreement logic preserved for backward compatibility.
- [Source: ios/Rial/Models/AggregatedConfidenceResult.swift] - ConfidenceFlag enum, MethodResult struct
- [Integration pattern: ios/Rial/Core/Detection/ConfidenceAggregator.swift normalizeDepth/normalizeMoire/normalizeTexture/normalizeArtifacts] - CrossValidationService should reuse or call these normalization methods for consistency

**Related Stories:**
- Story 9-1: MoireDetectionService - provides MoireAnalysisResult
- Story 9-2: TextureClassificationService - provides TextureClassificationResult
- Story 9-3: ArtifactDetectionService - provides ArtifactAnalysisResult
- Story 9-4: ConfidenceAggregator - integrates all signals, calls cross-validation

### Security Considerations

**Defense Against Sophisticated Attacks:**
This story specifically targets attacks that:
1. Game individual detection methods to pass individually
2. Create artificial score patterns that look "natural"
3. Exploit temporal inconsistencies in video
4. Avoid correlation patterns expected in real scenes

**Chimera Attack Mitigation:**
Per PRD research, Chimera attacks can bypass individual detection methods. Enhanced cross-validation adds:
- Correlation analysis catches inputs crafted to pass multiple methods but with wrong correlations
- Temporal consistency catches frame-by-frame manipulation
- Anomaly detection catches suspiciously perfect or boundary-hugging scores

**Trust Model:**
```
Enhanced Cross-Validation Role: SUPPORTING VERIFICATION
Purpose: Catch inconsistencies between methods
Impact: Can reduce confidence by up to 50% if anomalies detected
```

### Learnings from Previous Stories

Based on Stories 9-1 through 9-4:

1. **Service Pattern:** Use final class singleton with shared property
2. **Async/Await:** Process on background queue, return via continuation
3. **Logging:** os.log with dedicated category, os_signpost for performance
4. **Constants:** Define thresholds in enum (CrossValidationConstants)
5. **Result Structs:** Make Codable, Sendable, Equatable
6. **Error Handling:** Return graceful defaults, don't throw from public API
7. **Integration:** Add optional parameters for backward compatibility

---

_Story created: 2025-12-11_
_Epic: 9 - iOS Defense-in-Depth_
_FR Coverage: FR67 (Cross-validation when multiple methods available)_
_Depends on: Stories 9-1, 9-2, 9-3, 9-4 (all detection services and aggregator)_
_Enables: Story 9-6 (Detection Payload Integration with enhanced validation data)_

## Dev Agent Record

### Context Reference

N/A - Implementation based on story requirements, existing detection service patterns, and PRD/Epic specifications.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

### Completion Notes List

### File List
