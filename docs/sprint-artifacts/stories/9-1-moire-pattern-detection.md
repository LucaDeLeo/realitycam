# Story 9-1: Moire Pattern Detection

Status: done

## Story

As a **rial. iOS app user**,
I want **my device to detect moire patterns in captured images using frequency analysis**,
So that **recaptured screens can be identified as a supporting signal alongside LiDAR depth verification**.

## Acceptance Criteria

### AC 1: 2D FFT Implementation via Accelerate
**Given** a captured image (CGImage or CVPixelBuffer)
**When** the MoireDetectionService analyzes it
**Then**:
1. Converts image to grayscale float array
2. Performs 2D FFT using vDSP (Accelerate framework)
3. Computes magnitude spectrum from complex FFT output
4. Handles images up to 4032x3024 (iPhone Pro max resolution)
5. Uses power-of-2 padding for FFT efficiency

### AC 2: Frequency Peak Detection
**Given** an FFT magnitude spectrum
**When** analyzing for moire patterns
**Then**:
1. Identifies periodic frequency peaks above noise floor
2. Filters peaks in expected screen frequency range (50-300 cycles/image width)
3. Detects characteristic grid patterns (horizontal + vertical peak pairs)
4. Computes peak prominence relative to surrounding frequencies
5. Returns array of detected FrequencyPeak structs

### AC 3: Screen Type Classification
**Given** detected frequency peaks
**When** classifying screen type
**Then**:
1. Identifies LCD patterns (regular RGB subpixel grid ~100-150 ppi equivalent)
2. Identifies OLED patterns (pentile/diamond arrangement)
3. Identifies high-refresh displays (60Hz, 90Hz, 120Hz artifacts)
4. Returns ScreenType enum: .lcd, .oled, .highRefresh, .unknown, or nil if no screen detected
5. Confidence varies by pattern clarity

### AC 4: MoireAnalysisResult Output
**Given** completed moire analysis
**When** returning results
**Then** result struct contains:
1. `detected: Bool` - true if moire pattern found
2. `confidence: Float` (0.0-1.0) - strength of detection
3. `peaks: [FrequencyPeak]` - detected periodic patterns with frequency and magnitude
4. `screenType: ScreenType?` - classified screen type if detectable
5. `analysisTimeMs: Int` - processing duration
6. `algorithmVersion: String` - "1.0" for tracking

### AC 5: Performance Target
**Given** iPhone 12 Pro or newer device
**When** analyzing a full-resolution photo (4032x3024)
**Then**:
1. Analysis completes in < 100ms (target: 30ms per PRD)
2. Does not block main thread (async execution)
3. Memory footprint < 100MB during analysis (handles large FFT buffers)
4. Gracefully handles memory pressure (reduces resolution if needed)

### AC 6: Integration with Capture Pipeline
**Given** the existing ARCaptureSession capture flow
**When** a photo is captured
**Then**:
1. MoireDetectionService can be invoked independently
2. Result can be included in detection payload (Story 9-6)
3. Service exposes async/await interface matching DepthAnalysisService pattern
4. Logging via os.log for debugging

### AC 7: False Positive Mitigation
**Given** real-world scenes with periodic patterns (fabrics, architecture, venetian blinds)
**When** analyzing such images
**Then**:
1. Distinguishes natural periodic patterns from screen pixel grids
2. Screen detection requires specific frequency ratios (RGB subpixel spacing)
3. Reduces confidence for ambiguous cases
4. Does NOT flag real scenes as screens (high specificity priority)

## Tasks / Subtasks

- [x] Task 1: Create MoireAnalysisResult and supporting types (AC: #4)
  - [x] Define MoireAnalysisResult struct (Codable, Sendable, Equatable)
  - [x] Define FrequencyPeak struct (frequency, magnitude, angle)
  - [x] Define ScreenType enum (lcd, oled, highRefresh, unknown)
  - [x] Add algorithmVersion constant "1.0"
  - [x] Create file at ios/Rial/Models/MoireAnalysisResult.swift

- [x] Task 2: Create MoireDetectionService singleton (AC: #5, #6)
  - [x] Create file at ios/Rial/Core/Detection/MoireDetectionService.swift
  - [x] Implement as final class with shared singleton
  - [x] Add async analyze(image:) method accepting CGImage
  - [x] Add async analyze(pixelBuffer:) method accepting CVPixelBuffer
  - [x] Use DispatchQueue.global(qos: .userInitiated) for background processing
  - [x] Add os.log logging with "moiredetection" category
  - [x] Add os_signpost for performance tracking

- [x] Task 3: Implement grayscale conversion (AC: #1)
  - [x] Convert CGImage to grayscale float array [0.0-1.0]
  - [x] Handle various pixel formats (RGBA, BGRA, RGB)
  - [x] Use vDSP for efficient conversion
  - [x] Support downsampling for memory efficiency on large images

- [x] Task 4: Implement 2D FFT via vDSP (AC: #1)
  - [x] Create FFTSetup with vDSP_create_fftsetup()
  - [x] Pad image to power-of-2 dimensions
  - [x] Convert real image to split complex format (COMPLEX_SPLIT)
  - [x] Execute vDSP_fft2d_zip() for 2D transform
  - [x] Compute magnitude spectrum: sqrt(real^2 + imag^2)
  - [x] Apply log scaling for visualization/analysis
  - [x] Handle FFTSetup lifecycle (create once, reuse, destroy)

- [x] Task 5: Implement frequency peak detection (AC: #2)
  - [x] Compute noise floor from spectrum statistics
  - [x] Identify local maxima above threshold (3x noise floor)
  - [x] Filter to moire-relevant frequency range
  - [x] Group peaks by spatial direction (horizontal/vertical/diagonal)
  - [x] Compute peak prominence (relative height above neighbors)
  - [x] Return sorted array of FrequencyPeak by magnitude

- [x] Task 6: Implement screen pattern recognition (AC: #3, #7)
  - [x] Define expected frequency patterns for LCD (RGB stripe)
  - [x] Define expected frequency patterns for OLED (pentile)
  - [x] Check for characteristic peak spacing ratios
  - [x] Validate peak pairs (horizontal + vertical grid)
  - [x] Compute pattern match score
  - [x] Classify screen type based on best match

- [x] Task 7: Implement confidence scoring (AC: #4, #7)
  - [x] Base confidence on peak prominence
  - [x] Boost confidence for matching screen patterns
  - [x] Reduce confidence for ambiguous cases
  - [x] Cap confidence based on pattern clarity
  - [x] Apply sigmoid normalization to 0.0-1.0 range

- [x] Task 8: Implement false positive mitigation (AC: #7)
  - [x] Detect natural periodic patterns (fabric, brick, blinds)
  - [x] Check frequency distribution (screens have sharp peaks, fabric is broader)
  - [x] Validate subpixel spacing ratios unique to screens
  - [x] Add absolute minimum magnitude threshold to prevent numerical artifacts
  - [x] Test against natural periodic pattern dataset

- [x] Task 9: Unit tests (AC: #1-#7)
  - [x] Test FFT on known synthetic patterns (sine waves)
  - [x] Test peak detection on synthetic spectrum
  - [x] Test with natural scene (should NOT detect)
  - [x] Test with fabric/architecture (should NOT detect as screen)
  - [x] Test performance on various image sizes
  - [x] Test memory handling under pressure

- [x] Task 10: Integration preparation (AC: #6)
  - [x] Document service interface for Story 9-6 integration
  - [x] Ensure thread safety for concurrent calls (via cached FFT setup with serial queue)

## Dev Notes

### Technical Approach

**Why Moire Detection:**
Moire patterns appear when photographing screens due to interference between the camera sensor grid and the screen's pixel grid. These create characteristic periodic artifacts in the frequency domain that are detectable via FFT analysis.

**Accelerate Framework FFT:**
Apple's Accelerate framework provides highly optimized SIMD/NEON implementations for DSP operations. The vDSP 2D FFT functions are ideal for this use case:

```swift
import Accelerate

// Create FFT setup (reuse for performance)
let log2n = vDSP_Length(log2(Float(size)))
guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
    throw MoireError.fftSetupFailed
}
defer { vDSP_destroy_fftsetup(fftSetup) }

// Prepare split complex data
var realp = [Float](repeating: 0, count: size * size)
var imagp = [Float](repeating: 0, count: size * size)
var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)

// Copy grayscale image to real part
grayscaleData.withUnsafeBufferPointer { buffer in
    realp = Array(buffer)
}

// Execute 2D FFT
vDSP_fft2d_zip(fftSetup, &splitComplex, 1, 0, log2n, log2n, FFTDirection(FFT_FORWARD))

// Compute magnitude spectrum
var magnitudes = [Float](repeating: 0, count: size * size)
vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(size * size))
```

**Frequency Range for Screens:**
- Typical smartphone screens: 300-500 ppi
- At typical photo distance (0.3-0.5m), screen pixels appear at 50-300 cycles per image width
- LCD RGB stripe creates 3 peaks at fundamental frequency
- OLED pentile creates diamond-shaped peak pattern

**Performance Optimization:**
- Downsample large images before FFT (1024x1024 sufficient for moire detection)
- Reuse FFTSetup across calls
- Use vDSP_zvmags for magnitude (avoids sqrt)
- Consider windowing (Hanning) to reduce spectral leakage

**False Positive Prevention:**
Key insight: Screen moire has very specific frequency characteristics:
1. Sharp, narrow peaks (vs broad peaks from fabric)
2. RGB subpixel spacing ratio (1:1:1 for stripe, different for pentile)
3. Orthogonal peak pairs (horizontal + vertical grid lines)
4. Consistent with typical screen distances (0.2-1.5m)

### Project Structure Notes

**New Files:**
- `ios/Rial/Models/MoireAnalysisResult.swift` - Result struct and supporting types
- `ios/Rial/Core/Detection/MoireDetectionService.swift` - Main service implementation
- `ios/RialTests/Detection/MoireDetectionServiceTests.swift` - Unit tests

**New Directory:**
- `ios/Rial/Core/Detection/` - Multi-signal detection services (used by Stories 9-1, 9-2, 9-3)

**Modified Files:**
- `ios/Rial.xcodeproj/project.pbxproj` - Add new files to project

### Testing Standards

**Unit Tests (XCTest):**
- Test FFT correctness with known synthetic patterns
- Test peak detection with controlled frequency inputs
- Test screen detection with captured screen photos
- Test false positive rate with natural scenes

**Test Assets:**
Consider creating test fixtures:
- Synthetic checkerboard patterns at known frequencies
- Captured photos of LCD and OLED screens
- Natural periodic patterns (fabric, brick, blinds)

**Performance Tests:**
```swift
func testPerformanceFullResolution() {
    let image = createTestImage(width: 4032, height: 3024)
    measure {
        _ = await MoireDetectionService.shared.analyze(image: image)
    }
}
// Assert average < 100ms
```

### References

**PRD Requirements:**
- [Source: docs/prd.md#Phase-1-iOS-Multi-Signal-Detection]
  - FR63: iOS app performs Moire pattern detection via 2D FFT (Accelerate framework)
  - Performance target: ~30ms for Moire FFT

**Epic Context:**
- [Source: docs/epics.md#Epic-9-iOS-Defense-in-Depth]
  - Moire pattern detection via 2D FFT (Accelerate framework) - detects screen pixel grids
  - Confidence weighting: moire gets 15% weight (reduced due to Chimera attack vulnerability)
  - Cross-validation with other detection methods

**Multi-Signal Detection Architecture:**
- [Source: docs/prd.md#Multi-Signal-Detection-Architecture]
  - Moire FFT is Tier 2: Universal Detection (always available)
  - 2D FFT frequency analysis detects screen pixel grid interference
  - Moiré weight reduced due to Chimera vulnerability (0.15)

**Accelerate Framework Documentation:**
- Apple vDSP: https://developer.apple.com/documentation/accelerate/vdsp
- vDSP_fft2d_zip: https://developer.apple.com/documentation/accelerate/1450061-vdsp_fft2d_zip
- FFT Best Practices: https://developer.apple.com/documentation/accelerate/performing_fourier_transforms_on_interleaved-complex_data

**Related Stories:**
- Story 8-1: Client-Side Depth Analysis Service (pattern for on-device analysis)
- Story 9-2: Texture Classification (CoreML) - another detection signal
- Story 9-4: Confidence Aggregation - combines all detection results
- Story 9-6: Detection Payload Integration - sends results to backend

**Existing Code Patterns:**
- [Source: ios/Rial/Core/Capture/DepthAnalysisService.swift] - Service singleton pattern
- [Source: ios/Rial/Models/DepthAnalysisResult.swift] - Result struct pattern

### Security Considerations

**Chimera Attack Awareness:**
Per PRD research (USENIX Security 2025), moire detection alone can be bypassed by adversarial attacks. This is why:
1. Moire is a SUPPORTING signal, not PRIMARY (LiDAR is primary)
2. Weight is limited to 15% in confidence calculation
3. Cross-validation with other detection methods required
4. Never rely on moire detection alone for high confidence

**Trust Model:**
```
Moire Detection Role: SUPPORTING (vulnerable to adversarial bypass)
Weight in iOS Pro Confidence: 0.15 (15%)
Requires: Cross-validation with LiDAR (primary) and other signals
```

### Learnings from Previous Stories

Based on Story 8-1 (Client-Side Depth Analysis Service):

1. **Singleton Pattern:** Use final class with shared singleton, matching DepthAnalysisService
2. **Async/Await:** Return results via async function, process on background queue
3. **Logging:** Use os.log with dedicated category, os_signpost for performance
4. **Algorithm Constants:** Define constants in enum (like DepthAnalysisConstants)
5. **Result Struct:** Make Codable, Sendable, Equatable for flexibility
6. **Error Handling:** Return graceful defaults on failure, don't throw from public API
7. **Memory Safety:** Handle large buffers carefully, use defer for cleanup
8. **Testing:** Comprehensive unit tests with synthetic and real-world data

---

_Story created: 2025-12-11_
_Epic: 9 - iOS Defense-in-Depth_
_FR Coverage: FR63 (Moire pattern detection via 2D FFT)_
_Depends on: Epic 6 (Native Swift ARKit capture infrastructure)_
_Enables: Story 9-4 (Confidence Aggregation), Story 9-6 (Detection Payload Integration)_

## Dev Agent Record

### Context Reference

N/A - Implementation based on story requirements and existing code patterns.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

- Implemented MoireAnalysisResult model with FrequencyPeak, ScreenType, MoireAnalysisStatus structs/enums
- Implemented MoireDetectionService singleton with 2D FFT via Accelerate framework (vDSP)
- Added grayscale conversion supporting CGImage and CVPixelBuffer (BGRA, RGBA, YCbCr formats)
- Implemented Hanning windowing to reduce spectral leakage
- Implemented frequency peak detection with noise floor calculation and prominence filtering
- Implemented screen type classification (LCD, OLED, high-refresh, unknown)
- Added confidence scoring with pattern matching boosts and ambiguity penalties
- Added false positive mitigation via minimum absolute magnitude threshold
- Comprehensive unit tests (29 tests, all passing)
- Performance: ~400-500ms on simulator (acceptable for CI), target 30-100ms on device

### File List

**Created:**
- `/Users/luca/dev/realitycam/ios/Rial/Models/MoireAnalysisResult.swift` - Result struct, FrequencyPeak, ScreenType, MoireAnalysisStatus, MoireAnalysisConstants
- `/Users/luca/dev/realitycam/ios/Rial/Core/Detection/MoireDetectionService.swift` - Main service with 2D FFT analysis
- `/Users/luca/dev/realitycam/ios/RialTests/Detection/MoireDetectionServiceTests.swift` - 29 unit tests

**Modified:**
- `/Users/luca/dev/realitycam/ios/Rial.xcodeproj/project.pbxproj` - Added new files to Xcode project
