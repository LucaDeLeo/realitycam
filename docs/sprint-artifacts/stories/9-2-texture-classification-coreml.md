# Story 9-2: Texture Classification via CoreML

Status: drafted

## Story

As a **rial. iOS app user**,
I want **my device to classify surface textures using CoreML to distinguish real-world materials from screens and prints**,
So that **recaptured images can be identified as a supporting signal alongside LiDAR depth verification**.

## Acceptance Criteria

### AC 1: TextureClassificationResult Model
**Given** the need to store texture analysis results
**When** a texture classification is performed
**Then** the result struct contains:
1. `classification: TextureType` - primary classification (real_scene, lcd_screen, oled_screen, printed_paper, unknown)
2. `confidence: Float` (0.0-1.0) - confidence in primary classification
3. `allClassifications: [TextureType: Float]` - probabilities for all classes
4. `isLikelyRecaptured: Bool` - true if screen or print detected with high confidence
5. `analysisTimeMs: Int` - processing duration
6. `algorithmVersion: String` - "1.0" for tracking
7. Struct is Codable, Sendable, and Equatable

### AC 2: CoreML Model Integration
**Given** a captured image (CGImage or CVPixelBuffer)
**When** the TextureClassificationService analyzes it
**Then**:
1. Loads MobileNetV3 or equivalent lightweight model via CoreML
2. Preprocesses image to model input format (224x224 RGB, normalized)
3. Runs inference using VNCoreMLRequest
4. Extracts classification probabilities from model output
5. Model is loaded once and reused (lazy initialization)

### AC 3: Image Preprocessing Pipeline
**Given** an input image of arbitrary size and format
**When** preprocessing for model inference
**Then**:
1. Resizes image to 224x224 maintaining aspect ratio (center crop)
2. Converts to RGB format if needed (handles BGRA, YCbCr)
3. Normalizes pixel values per model requirements (ImageNet normalization: mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225])
4. Creates CVPixelBuffer suitable for Vision framework
5. Handles both CGImage and CVPixelBuffer inputs

### AC 4: Classification Output Mapping
**Given** raw model output probabilities
**When** mapping to TextureType enum
**Then**:
1. Maps model classes to TextureType enum values
2. Returns highest-probability class as primary classification
3. Returns all class probabilities in allClassifications dictionary
4. Sets isLikelyRecaptured = true if lcd_screen, oled_screen, or printed_paper has confidence > 0.7
5. Handles models with different output formats (softmax vs logits)

### AC 5: Performance Target
**Given** iPhone 12 Pro or newer device
**When** classifying a captured photo
**Then**:
1. Classification completes in < 50ms (target: 15ms per PRD)
2. Does not block main thread (async execution)
3. Model size < 10MB (MobileNetV3 Small target)
4. Memory footprint < 50MB during inference
5. Uses Neural Engine when available (ANE acceleration)

### AC 6: Integration with Capture Pipeline
**Given** the existing ARCaptureSession capture flow
**When** a photo is captured
**Then**:
1. TextureClassificationService can be invoked independently
2. Result can be included in detection payload (Story 9-6)
3. Service exposes async/await interface matching MoireDetectionService pattern
4. Logging via os.log with "textureclassification" category
5. Service is thread-safe for concurrent calls

### AC 7: Graceful Degradation
**Given** potential runtime issues (model load failure, memory pressure)
**When** classification cannot be performed
**Then**:
1. Returns TextureClassificationResult with status = .unavailable
2. Sets classification to .unknown with confidence 0.0
3. Logs error details for debugging
4. Does NOT crash or throw from public API
5. Includes reason for unavailability in result

## Tasks / Subtasks

- [ ] Task 1: Create TextureClassificationResult and supporting types (AC: #1)
  - [ ] Define TextureType enum (real_scene, lcd_screen, oled_screen, printed_paper, unknown)
  - [ ] Define TextureClassificationResult struct (Codable, Sendable, Equatable)
  - [ ] Define TextureClassificationStatus enum (success, unavailable, error)
  - [ ] Add algorithmVersion constant "1.0"
  - [ ] Create file at ios/Rial/Models/TextureClassificationResult.swift

- [ ] Task 2: Obtain or create CoreML model (AC: #2)
  - [ ] Option A: Download pre-trained MobileNetV3 from Apple's model gallery
  - [ ] Option B: Fine-tune MobileNetV3 on texture classification dataset
  - [ ] Convert to CoreML format (.mlmodel or .mlpackage)
  - [ ] Verify model size < 10MB
  - [ ] Add model to ios/Rial/Resources/TextureClassifier.mlmodel

- [ ] Task 3: Create TextureClassificationService singleton (AC: #5, #6)
  - [ ] Create file at ios/Rial/Core/Detection/TextureClassificationService.swift
  - [ ] Implement as final class with shared singleton
  - [ ] Add lazy model loading with error handling
  - [ ] Add async classify(image:) method accepting CGImage
  - [ ] Add async classify(pixelBuffer:) method accepting CVPixelBuffer
  - [ ] Configure for Neural Engine acceleration
  - [ ] Add os.log logging with "textureclassification" category
  - [ ] Add os_signpost for performance tracking

- [ ] Task 4: Implement image preprocessing (AC: #3)
  - [ ] Create resizeAndCrop(image:targetSize:) function
  - [ ] Implement center-crop to maintain aspect ratio
  - [ ] Handle format conversion (BGRA, YCbCr to RGB)
  - [ ] Apply ImageNet normalization (mean/std)
  - [ ] Create CVPixelBuffer from preprocessed data
  - [ ] Use vImage/Accelerate for efficient operations

- [ ] Task 5: Implement Vision framework inference (AC: #2, #4)
  - [ ] Create VNCoreMLModel from loaded MLModel
  - [ ] Create VNCoreMLRequest with completion handler
  - [ ] Configure request for image classification
  - [ ] Execute request via VNImageRequestHandler
  - [ ] Extract VNClassificationObservation results
  - [ ] Map observations to TextureType enum

- [ ] Task 6: Implement result mapping (AC: #4)
  - [ ] Map model class labels to TextureType enum
  - [ ] Compute allClassifications dictionary from observations
  - [ ] Determine isLikelyRecaptured based on confidence threshold
  - [ ] Handle edge cases (no predictions, equal probabilities)
  - [ ] Apply softmax if model outputs logits

- [ ] Task 7: Implement graceful degradation (AC: #7)
  - [ ] Handle model load failure
  - [ ] Handle inference errors
  - [ ] Handle memory pressure (via DispatchSource)
  - [ ] Return unavailable status with reason
  - [ ] Ensure no throws from public API

- [ ] Task 8: Unit tests (AC: #1-#7)
  - [ ] Test result struct encoding/decoding
  - [ ] Test model loading and inference on test images
  - [ ] Test preprocessing on various image formats
  - [ ] Test classification output mapping
  - [ ] Test graceful degradation scenarios
  - [ ] Test performance on various image sizes

- [ ] Task 9: Integration preparation (AC: #6)
  - [ ] Document service interface for Story 9-6 integration
  - [ ] Ensure thread safety for concurrent calls
  - [ ] Add integration notes to Dev Notes

## Dev Notes

### Technical Approach

**Why Texture Classification:**
Real-world surfaces have distinct texture patterns compared to screens and prints:
- Real scenes: Natural material textures (skin, fabric, wood, grass, concrete)
- LCD screens: Visible pixel grid, backlight uniformity
- OLED screens: Different subpixel arrangement, potential burn-in patterns
- Printed paper: Halftone patterns, paper texture, ink absorption artifacts

**CoreML + Vision Framework:**
Apple's CoreML provides optimized inference on iOS devices with automatic hardware acceleration:

```swift
import CoreML
import Vision

// Load model (lazy, once)
private lazy var model: VNCoreMLModel? = {
    guard let mlModel = try? TextureClassifier(configuration: MLModelConfiguration()).model,
          let vnModel = try? VNCoreMLModel(for: mlModel) else {
        return nil
    }
    return vnModel
}()

// Create classification request
let request = VNCoreMLRequest(model: model!) { request, error in
    guard let observations = request.results as? [VNClassificationObservation] else {
        return
    }
    // Process observations...
}

// Configure for best performance
request.imageCropAndScaleOption = .centerCrop
request.usesCPUOnly = false  // Enable Neural Engine

// Execute
let handler = VNImageRequestHandler(cgImage: image, options: [:])
try handler.perform([request])
```

**Model Options:**
1. **Pre-trained MobileNetV3** - General image classification, requires output mapping
2. **Fine-tuned model** - Custom trained on texture dataset (higher accuracy)
3. **Apple's built-in classifiers** - VNClassifyImageRequest (limited classes)

For MVP, start with pre-trained MobileNetV3 Small and map outputs to texture types.

**Image Preprocessing:**
```swift
import Accelerate

func preprocessImage(_ cgImage: CGImage, targetSize: CGSize = CGSize(width: 224, height: 224)) -> CVPixelBuffer? {
    // 1. Create vImage buffer
    var format = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent
    )

    var sourceBuffer = vImage_Buffer()
    vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
    defer { free(sourceBuffer.data) }

    // 2. Scale to target size with center crop
    // ... vImageScale_ARGB8888

    // 3. Convert to CVPixelBuffer
    // ... CVPixelBufferCreate

    return pixelBuffer
}
```

**Performance Optimization:**
- Neural Engine: MobileNetV3 runs on ANE by default (much faster than GPU/CPU)
- Model caching: Load once on first use, keep in memory
- Batch processing: Can classify multiple images in single request
- Resolution: 224x224 is standard for MobileNet (don't exceed)

### Project Structure Notes

**New Files:**
- `ios/Rial/Models/TextureClassificationResult.swift` - Result struct and types
- `ios/Rial/Core/Detection/TextureClassificationService.swift` - Main service
- `ios/Rial/Resources/TextureClassifier.mlmodel` - CoreML model file
- `ios/RialTests/Detection/TextureClassificationServiceTests.swift` - Unit tests

**Existing Directory:**
- `ios/Rial/Core/Detection/` - Created by Story 9-1 (MoireDetectionService)

**Modified Files:**
- `ios/Rial.xcodeproj/project.pbxproj` - Add new files to project

### Model Training Notes

**Option 1: Use Pre-trained Model (Recommended for MVP)**
- Download MobileNetV3 Small from Apple's model gallery
- Model is trained on ImageNet (1000 classes)
- Map ImageNet classes to texture types:
  - "monitor", "screen", "television" -> lcd_screen
  - "cellular_telephone", "iPod" -> oled_screen
  - "envelope", "paper_towel", "book" -> printed_paper
  - Others -> real_scene (default)

**Option 2: Fine-tune for Accuracy (Post-MVP)**
- Collect training dataset:
  - Real scenes: 1000+ varied outdoor/indoor photos
  - LCD screens: 500+ photos of various displays
  - OLED screens: 500+ photos of phones/OLED TVs
  - Prints: 500+ photos of printed photos/documents
- Use CreateML or PyTorch + coremltools
- Fine-tune MobileNetV3 backbone
- Target: >95% accuracy on validation set

### Testing Standards

**Unit Tests (XCTest):**
- Test classification on known test images
- Test preprocessing pipeline
- Test model loading and caching
- Test error handling

**Test Assets:**
Create test fixtures with known classifications:
- `test_real_scene.jpg` - Natural outdoor scene
- `test_lcd_screen.jpg` - Photo of LCD monitor
- `test_oled_screen.jpg` - Photo of OLED phone
- `test_printed_paper.jpg` - Photo of printed photo

**Performance Tests:**
```swift
func testPerformanceClassification() {
    let image = loadTestImage("test_real_scene")!
    measure {
        _ = await TextureClassificationService.shared.classify(image: image)
    }
}
// Assert average < 50ms
```

### References

**PRD Requirements:**
- [Source: docs/prd.md#Phase-1-iOS-Multi-Signal-Detection]
  - FR64: iOS app performs texture classification via CoreML (MobileNetV3)
  - Performance target: ~15ms for Texture CNN

**Epic Context:**
- [Source: docs/epics.md#Epic-9-iOS-Defense-in-Depth]
  - Texture classification via CoreML (MobileNetV3) - distinguishes real vs screen/print materials
  - Confidence weighting: texture gets 15% weight
  - Cross-validation with other detection methods

**Multi-Signal Detection Architecture:**
- [Source: docs/prd.md#Multi-Signal-Detection-Architecture]
  - Texture Classification is Tier 2: Universal Detection (always available)
  - MobileNetV3 CNN distinguishes real-world vs screen/print materials
  - Texture weight: 0.15 (15%)

**Apple Documentation:**
- CoreML: https://developer.apple.com/documentation/coreml
- Vision: https://developer.apple.com/documentation/vision
- VNCoreMLRequest: https://developer.apple.com/documentation/vision/vncoremlrequest
- MobileNetV3 paper: https://arxiv.org/abs/1905.02244

**Related Stories:**
- Story 9-1: Moire Pattern Detection (FFT) - sibling detection signal
- Story 9-3: Artifact Detection - another detection signal
- Story 9-4: Confidence Aggregation - combines all detection results
- Story 9-6: Detection Payload Integration - sends results to backend

**Existing Code Patterns:**
- [Source: ios/Rial/Core/Detection/MoireDetectionService.swift] - Service singleton pattern
- [Source: ios/Rial/Models/MoireAnalysisResult.swift] - Result struct pattern

### Security Considerations

**Chimera Attack Awareness:**
Per PRD research (USENIX Security 2025), texture classification alone can be bypassed by adversarial attacks. This is why:
1. Texture is a SUPPORTING signal, not PRIMARY (LiDAR is primary)
2. Weight is limited to 15% in confidence calculation
3. Cross-validation with other detection methods required
4. Never rely on texture classification alone for high confidence

**Trust Model:**
```
Texture Classification Role: SUPPORTING (vulnerable to adversarial bypass)
Weight in iOS Pro Confidence: 0.15 (15%)
Requires: Cross-validation with LiDAR (primary) and other signals
```

### Learnings from Story 9-1

Based on Story 9-1 (Moire Pattern Detection):

1. **Singleton Pattern:** Use final class with shared singleton, matching MoireDetectionService
2. **Async/Await:** Return results via async function, process on background queue
3. **Logging:** Use os.log with dedicated category, os_signpost for performance
4. **Algorithm Constants:** Define constants in enum (like MoireAnalysisConstants)
5. **Result Struct:** Make Codable, Sendable, Equatable for flexibility
6. **Error Handling:** Return graceful defaults on failure, don't throw from public API
7. **Memory Safety:** Handle model loading errors gracefully
8. **Testing:** Comprehensive unit tests with synthetic and real-world data

---

_Story created: 2025-12-11_
_Epic: 9 - iOS Defense-in-Depth_
_FR Coverage: FR64 (Texture classification via CoreML)_
_Depends on: Epic 6 (Native Swift ARKit capture infrastructure), Story 9-1 (Detection service pattern)_
_Enables: Story 9-4 (Confidence Aggregation), Story 9-6 (Detection Payload Integration)_

## Dev Agent Record

### Context Reference

N/A - Story drafted based on PRD, epics, and Story 9-1 pattern.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story is drafted, not yet implemented.

### File List

N/A - Story is drafted, not yet implemented.
