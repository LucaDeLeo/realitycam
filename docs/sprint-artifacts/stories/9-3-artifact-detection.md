# Story 9-3: Artifact Detection (PWM, Specular, Halftone)

Status: drafted

## Story

As a **rial. iOS app user**,
I want **my device to detect visual artifacts like PWM flicker, specular reflections, and halftone patterns**,
So that **screen recaptures and printed photos can be identified as supporting signals alongside LiDAR depth verification**.

## Acceptance Criteria

### AC 1: ArtifactAnalysisResult Model
**Given** the need to store artifact detection results
**When** artifact analysis is performed
**Then** the result struct contains:
1. `pwmFlickerDetected: Bool` - true if PWM/flicker patterns found
2. `pwmConfidence: Float` (0.0-1.0) - strength of PWM detection
3. `specularPatternDetected: Bool` - true if unnatural specular patterns found
4. `specularConfidence: Float` (0.0-1.0) - strength of specular detection
5. `halftoneDetected: Bool` - true if halftone dot patterns found
6. `halftoneConfidence: Float` (0.0-1.0) - strength of halftone detection
7. `overallConfidence: Float` (0.0-1.0) - combined artifact confidence
8. `isLikelyArtificial: Bool` - true if any artifact detected with high confidence
9. `analysisTimeMs: Int64` - processing duration
10. `status: ArtifactAnalysisStatus` - success, unavailable, or error
11. `algorithmVersion: String` - "1.0" for tracking
12. Struct is Codable, Sendable, and Equatable

### AC 2: PWM Flicker Detection
**Given** a captured image (CGImage or CVPixelBuffer)
**When** analyzing for PWM flicker patterns
**Then**:
1. Extracts luminance channel from image
2. Analyzes for periodic banding patterns (horizontal scan lines)
3. Detects characteristic frequencies: 60Hz, 90Hz, 120Hz, 144Hz refresh artifacts
4. Uses FFT on horizontal scan lines to detect periodic patterns
5. Reports pwmFlickerDetected = true if pattern matches known refresh rates
6. Sets pwmConfidence based on pattern strength and frequency match

### AC 3: Specular Reflection Pattern Detection
**Given** a captured image
**When** analyzing for specular reflection patterns
**Then**:
1. Detects highlight regions (high luminance, low saturation)
2. Analyzes highlight distribution for unnatural uniformity
3. Identifies characteristic screen glass reflections (rectangular, uniform)
4. Distinguishes from natural specular highlights (irregular, varied)
5. Reports specularPatternDetected = true if unnatural patterns found
6. Sets specularConfidence based on uniformity and shape analysis

### AC 4: Halftone Dot Detection
**Given** a captured image
**When** analyzing for halftone printing patterns
**Then**:
1. Performs frequency analysis on image regions
2. Detects regular dot patterns characteristic of CMYK printing (rosette pattern)
3. Uses FFT to find periodic structures at printing frequencies
4. Distinguishes from screen pixel patterns (circular dots vs square pixels)
5. Reports halftoneDetected = true if printing pattern found
6. Sets halftoneConfidence based on pattern regularity and coverage

### AC 5: Combined Confidence Calculation
**Given** individual artifact detection results
**When** computing overall confidence
**Then**:
1. Weights each artifact type appropriately:
   - PWM: 0.35 (strong indicator of screen)
   - Specular: 0.30 (screens have characteristic reflections)
   - Halftone: 0.35 (strong indicator of print)
2. Sets isLikelyArtificial = true if any confidence > 0.7 or combined > 0.6
3. Normalizes overallConfidence to 0.0-1.0 range
4. Logs detection breakdown for debugging

### AC 6: Performance Target
**Given** iPhone 12 Pro or newer device
**When** analyzing a full-resolution photo (4032x3024)
**Then**:
1. Analysis completes in < 100ms (target: 50ms per PRD)
2. Does not block main thread (async execution)
3. Memory footprint < 75MB during analysis
4. Gracefully handles memory pressure (reduces resolution if needed)

### AC 7: Integration with Capture Pipeline
**Given** the existing ARCaptureSession capture flow
**When** a photo is captured
**Then**:
1. ArtifactDetectionService can be invoked independently
2. Result can be included in detection payload (Story 9-6)
3. Service exposes async/await interface matching MoireDetectionService pattern
4. Logging via os.log with "artifactdetection" category
5. Service is thread-safe for concurrent calls

### AC 8: False Positive Mitigation
**Given** real-world scenes with natural patterns
**When** analyzing such images
**Then**:
1. Does NOT flag natural lighting variations as PWM
2. Does NOT flag natural highlights (sun glare, water) as screen specular
3. Does NOT flag fine textures (fabric, paper grain) as halftone
4. Requires multiple consistent indicators before flagging
5. Reduces confidence for ambiguous edge cases

## Tasks / Subtasks

- [ ] Task 1: Create ArtifactAnalysisResult and supporting types (AC: #1)
  - [ ] Define ArtifactAnalysisResult struct (Codable, Sendable, Equatable)
  - [ ] Define ArtifactAnalysisStatus enum (success, unavailable, error)
  - [ ] Define ArtifactAnalysisConstants enum with thresholds
  - [ ] Add algorithmVersion constant "1.0"
  - [ ] Create file at ios/Rial/Models/ArtifactAnalysisResult.swift

- [ ] Task 2: Create ArtifactDetectionService singleton (AC: #6, #7)
  - [ ] Create file at ios/Rial/Core/Detection/ArtifactDetectionService.swift
  - [ ] Implement as final class with shared singleton
  - [ ] Add async analyze(image:) method accepting CGImage
  - [ ] Add async analyze(pixelBuffer:) method accepting CVPixelBuffer
  - [ ] Use DispatchQueue.global(qos: .userInitiated) for background processing
  - [ ] Add os.log logging with "artifactdetection" category
  - [ ] Add os_signpost for performance tracking

- [ ] Task 3: Implement PWM flicker detection (AC: #2)
  - [ ] Extract luminance channel using vDSP
  - [ ] Compute horizontal line averages (reduce to 1D signal)
  - [ ] Perform 1D FFT on luminance profile using vDSP_fft_zip
  - [ ] Detect peaks at refresh rate frequencies (60, 90, 120, 144 Hz equivalent)
  - [ ] Calculate exposure time from EXIF (if available) for frequency calibration
  - [ ] Compute confidence based on peak strength and frequency match
  - [ ] Handle edge cases (very short/long exposures)

- [ ] Task 4: Implement specular reflection pattern detection (AC: #3)
  - [ ] Identify highlight regions (luminance > 0.9, saturation < 0.2)
  - [ ] Analyze highlight shape using connected component analysis
  - [ ] Compute shape metrics: aspect ratio, rectangularity, edge uniformity
  - [ ] Detect characteristic screen reflection patterns (rectangular, uniform edges)
  - [ ] Distinguish from natural highlights (irregular shapes, varied edges)
  - [ ] Use Core Image or vImage for efficient highlight detection
  - [ ] Compute confidence based on shape regularity and count

- [ ] Task 5: Implement halftone dot detection (AC: #4)
  - [ ] Downsample to analysis resolution (512x512 or 1024x1024)
  - [ ] Compute local FFT on image regions (tile-based analysis)
  - [ ] Detect periodic dot patterns at printing frequencies
  - [ ] Identify rosette pattern characteristic of CMYK printing
  - [ ] Distinguish circular halftone dots from square screen pixels
  - [ ] Aggregate regional detections for overall confidence
  - [ ] Use vDSP for efficient FFT operations

- [ ] Task 6: Implement combined confidence scoring (AC: #5)
  - [ ] Weight individual detections (PWM: 0.35, Specular: 0.30, Halftone: 0.35)
  - [ ] Compute weighted average for overallConfidence
  - [ ] Determine isLikelyArtificial based on thresholds
  - [ ] Handle cases where only some analyses succeed
  - [ ] Apply sigmoid normalization for smooth confidence curve

- [ ] Task 7: Implement false positive mitigation (AC: #8)
  - [ ] PWM: Require consistent pattern across multiple rows
  - [ ] Specular: Validate rectangular shape before flagging
  - [ ] Halftone: Require minimum coverage area
  - [ ] Add minimum detection thresholds to prevent noise-triggered flags
  - [ ] Reduce confidence for single-indicator detections
  - [ ] Test against dataset of natural scenes

- [ ] Task 8: Unit tests (AC: #1-#8)
  - [ ] Test result struct encoding/decoding
  - [ ] Test PWM detection on synthetic banded images
  - [ ] Test specular detection on synthetic highlight patterns
  - [ ] Test halftone detection on known printed patterns
  - [ ] Test with natural scenes (should NOT detect)
  - [ ] Test performance on various image sizes
  - [ ] Test combined confidence calculation

- [ ] Task 9: Integration preparation (AC: #7)
  - [ ] Document service interface for Story 9-4 integration
  - [ ] Ensure thread safety for concurrent calls
  - [ ] Create example usage in Dev Notes

## Dev Notes

### Technical Approach

**Why Artifact Detection:**
Different recapture methods leave characteristic visual artifacts:

1. **PWM Flicker (Screens):** Many displays use PWM (Pulse Width Modulation) for brightness control. When photographed, this creates subtle horizontal banding patterns at the refresh rate frequency. The camera's rolling shutter captures different phases of the PWM cycle across scan lines.

2. **Specular Reflections (Screens):** Screen glass creates characteristic rectangular, uniform reflections. Natural objects have irregular, varied specular highlights. Analyzing highlight shape can distinguish screen glass from natural surfaces.

3. **Halftone Patterns (Prints):** Printed photos use halftone screening (typically CMYK rosette pattern). These create periodic dot patterns detectable via frequency analysis. Different from screen pixel patterns (square vs circular, different frequencies).

**PWM Detection Algorithm:**

```swift
import Accelerate

func detectPWM(luminance: [Float], width: Int, height: Int) -> (detected: Bool, confidence: Float) {
    // Average each row to get luminance profile
    var rowAverages = [Float](repeating: 0, count: height)
    for y in 0..<height {
        var sum: Float = 0
        vDSP_sve(luminance.advanced(by: y * width), 1, &sum, vDSP_Length(width))
        rowAverages[y] = sum / Float(width)
    }

    // Perform 1D FFT on luminance profile
    let log2n = vDSP_Length(log2(Float(height)))
    guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
        return (false, 0)
    }
    defer { vDSP_destroy_fftsetup(fftSetup) }

    // ... FFT and peak detection at known refresh frequencies
    // 60Hz, 90Hz, 120Hz, 144Hz relative to exposure time

    return (hasPWMPeaks, confidence)
}
```

**Specular Pattern Detection:**

```swift
func detectSpecularPatterns(image: CGImage) -> (detected: Bool, confidence: Float) {
    // 1. Create highlight mask (luminance > 0.9, saturation < 0.2)
    // 2. Find connected components (highlight regions)
    // 3. For each region, compute shape metrics:
    //    - Aspect ratio (screens tend to be rectangular)
    //    - Rectangularity = area / bounding_box_area
    //    - Edge uniformity (straight edges vs irregular)
    // 4. Flag if multiple rectangular, uniform highlights found

    // Use Core Image filters for efficient highlight extraction
    let highlightFilter = CIFilter(name: "CIColorThreshold")
    // ...
}
```

**Halftone Detection Algorithm:**

```swift
func detectHalftone(image: GrayscaleImage, tileSize: Int = 128) -> (detected: Bool, confidence: Float) {
    var halftoneScores = [Float]()

    // Tile-based analysis
    for y in stride(from: 0, to: image.height, by: tileSize) {
        for x in stride(from: 0, to: image.width, by: tileSize) {
            // Extract tile
            let tile = extractTile(image, x: x, y: y, size: tileSize)

            // Perform 2D FFT on tile
            let spectrum = performFFT(tile)

            // Look for periodic peaks characteristic of halftone
            // CMYK rosette: peaks at 15, 45, 75, 90 degree angles
            // Typical halftone frequency: 100-200 LPI (lines per inch)

            if hasHalftonePattern(spectrum) {
                halftoneScores.append(computeScore(spectrum))
            }
        }
    }

    // Aggregate: need consistent detection across multiple tiles
    let detected = halftoneScores.count > minTileCount
    let confidence = detected ? halftoneScores.mean() : 0

    return (detected, confidence)
}
```

**Performance Optimization:**
- Use Accelerate framework for all DSP operations
- Downsample for halftone analysis (512x512 sufficient)
- Process all three analyses in parallel using DispatchGroup
- Reuse FFT setups across calls (cache like MoireDetectionService)
- Early exit if first analysis is conclusive

### Project Structure Notes

**New Files:**
- `ios/Rial/Models/ArtifactAnalysisResult.swift` - Result struct and types
- `ios/Rial/Core/Detection/ArtifactDetectionService.swift` - Main service
- `ios/RialTests/Detection/ArtifactDetectionServiceTests.swift` - Unit tests

**Existing Directory:**
- `ios/Rial/Core/Detection/` - Created by Story 9-1 (MoireDetectionService)

**Modified Files:**
- `ios/Rial.xcodeproj/project.pbxproj` - Add new files to project

### Code Patterns from Stories 9-1 and 9-2

Following established patterns:

```swift
// Service singleton pattern
public final class ArtifactDetectionService: @unchecked Sendable {
    public static let shared = ArtifactDetectionService()

    private static let logger = Logger(subsystem: "app.rial", category: "artifactdetection")
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    private init() {
        Self.logger.debug("ArtifactDetectionService initialized")
    }

    public func analyze(image: CGImage) async -> ArtifactAnalysisResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performAnalysis(image: image)
                continuation.resume(returning: result)
            }
        }
    }
}
```

### Testing Standards

**Unit Tests (XCTest):**
- Test each artifact type independently
- Use synthetic test images with known patterns
- Test false positive rate with natural scenes

**Test Fixtures:**
- `test_pwm_banded.png` - Synthetic horizontal banding
- `test_specular_rectangular.png` - Synthetic screen-like highlights
- `test_halftone_dots.png` - Synthetic halftone pattern
- `test_natural_scene.jpg` - Natural scene (should NOT detect)

**Performance Tests:**
```swift
func testPerformanceFullResolution() {
    let image = loadTestImage("test_natural_scene")!
    measure {
        _ = await ArtifactDetectionService.shared.analyze(image: image)
    }
}
// Assert average < 100ms
```

### References

**PRD Requirements:**
- [Source: docs/prd.md#Phase-1-iOS-Multi-Signal-Detection]
  - FR65: iOS app detects supporting artifacts (PWM, specular reflection, halftone)
  - Performance target: ~50ms combined artifact detection

**Epic Context:**
- [Source: docs/epics.md#Epic-9-iOS-Defense-in-Depth]
  - Supporting artifact detection (PWM flicker, specular reflection patterns, halftone dots)
  - Confidence weighting: artifacts get ~15% combined weight
  - Cross-validation with other detection methods

**Multi-Signal Detection Architecture:**
- [Source: docs/prd.md#Multi-Signal-Detection-Architecture]
  - Tier 3: Supporting Signals
  - PWM/refresh rate artifacts
  - Specular reflection patterns
  - Halftone detection (prints)
  - Combined weight: 0.15 (15%)

**Technical References:**
- PWM display dimming: https://www.displaymate.com/Display_Measurements.htm
- Halftone screening: https://en.wikipedia.org/wiki/Halftone
- CMYK rosette patterns: https://en.wikipedia.org/wiki/Moir%C3%A9_pattern#Printing

**Related Stories:**
- Story 9-1: Moire Pattern Detection (FFT) - sibling detection signal (Done)
- Story 9-2: Texture Classification (CoreML) - sibling detection signal
- Story 9-4: Confidence Aggregation - combines all detection results
- Story 9-6: Detection Payload Integration - sends results to backend

**Existing Code Patterns:**
- [Source: ios/Rial/Core/Detection/MoireDetectionService.swift] - Service singleton pattern, FFT usage
- [Source: ios/Rial/Models/MoireAnalysisResult.swift] - Result struct pattern

### Security Considerations

**Chimera Attack Awareness:**
Per PRD research (USENIX Security 2025), artifact detection alone can be bypassed by sophisticated adversarial attacks. This is why:
1. Artifacts are SUPPORTING signals, not PRIMARY (LiDAR is primary)
2. Combined weight is limited to 15% in confidence calculation
3. Cross-validation with other detection methods required
4. Never rely on artifact detection alone for high confidence

**Trust Model:**
```
Artifact Detection Role: SUPPORTING (vulnerable to adversarial bypass)
Combined Weight in iOS Pro Confidence: 0.15 (15%)
Requires: Cross-validation with LiDAR (primary) and other signals
Individual weights: PWM (0.35), Specular (0.30), Halftone (0.35) of artifact budget
```

### Learnings from Stories 9-1 and 9-2

Based on completed Story 9-1 (Moire Pattern Detection):

1. **Singleton Pattern:** Use final class with shared singleton, matching MoireDetectionService
2. **Async/Await:** Return results via async function, process on background queue
3. **Logging:** Use os.log with dedicated category, os_signpost for performance
4. **Algorithm Constants:** Define constants in enum (like MoireAnalysisConstants)
5. **Result Struct:** Make Codable, Sendable, Equatable for flexibility
6. **Error Handling:** Return graceful defaults on failure, don't throw from public API
7. **Memory Safety:** Handle large buffers carefully, use defer for cleanup
8. **FFT Caching:** Cache FFT setup across calls for performance (significant gain)
9. **Thread Safety:** Use serial queue for mutable state protection
10. **Minimum Magnitude Thresholds:** Add absolute minimums to prevent numerical artifacts

---

_Story created: 2025-12-11_
_Epic: 9 - iOS Defense-in-Depth_
_FR Coverage: FR65 (Artifact detection - PWM, specular, halftone)_
_Depends on: Story 9-1 (Detection service pattern), Story 9-2 (Detection infrastructure)_
_Enables: Story 9-4 (Confidence Aggregation), Story 9-6 (Detection Payload Integration)_

## Dev Agent Record

### Context Reference

N/A - Story drafted based on PRD, epics, and Stories 9-1/9-2 patterns.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story is drafted, not yet implemented.

### File List

N/A - Story is drafted, not yet implemented.
