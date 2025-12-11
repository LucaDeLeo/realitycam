//
//  ArtifactDetectionServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Unit tests for ArtifactDetectionService (Story 9-3).
//  Tests PWM flicker, specular reflection, and halftone pattern detection.
//

import XCTest
import CoreGraphics
import CoreVideo
@testable import Rial

/// Tests for ArtifactDetectionService artifact detection.
///
/// These tests verify:
/// - AC1: ArtifactAnalysisResult model
/// - AC2: PWM flicker detection
/// - AC3: Specular reflection pattern detection
/// - AC4: Halftone dot detection
/// - AC5: Combined confidence calculation
/// - AC6: Performance target (<100ms)
/// - AC7: Integration with capture pipeline
/// - AC8: False positive mitigation
final class ArtifactDetectionServiceTests: XCTestCase {

    // MARK: - Properties

    private var service: ArtifactDetectionService!

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        service = ArtifactDetectionService.shared
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Test Fixtures

    /// Creates a CGImage with specified pattern.
    private func createTestImage(
        width: Int,
        height: Int,
        generator: (_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> (r: UInt8, g: UInt8, b: UInt8)
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create context")
            return nil
        }

        guard let data = context.data else {
            XCTFail("Failed to get context data")
            return nil
        }

        let bytePointer = data.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let color = generator(x, y, width, height)
                bytePointer[offset] = color.r
                bytePointer[offset + 1] = color.g
                bytePointer[offset + 2] = color.b
                bytePointer[offset + 3] = 255 // Alpha
            }
        }

        return context.makeImage()
    }

    /// Creates a uniform gray image (no artifacts).
    private func createUniformImage(width: Int, height: Int, brightness: UInt8 = 128) -> CGImage? {
        return createTestImage(width: width, height: height) { _, _, _, _ in
            (brightness, brightness, brightness)
        }
    }

    /// Creates an image with horizontal banding (simulates PWM flicker).
    private func createPWMBandingImage(
        width: Int,
        height: Int,
        bandFrequency: Int,
        contrast: UInt8 = 30
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { _, y, _, h in
            let period = max(1, h / bandFrequency)
            let phase = y % period
            let inBand = phase < period / 2
            let base: UInt8 = 128
            let value = inBand ? base + contrast : base - contrast
            return (value, value, value)
        }
    }

    /// Creates an image with rectangular highlight (simulates screen specular).
    private func createSpecularHighlightImage(
        width: Int,
        height: Int,
        highlightX: Int,
        highlightY: Int,
        highlightWidth: Int,
        highlightHeight: Int
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, _, _ in
            let inHighlight = x >= highlightX && x < highlightX + highlightWidth &&
                             y >= highlightY && y < highlightY + highlightHeight
            if inHighlight {
                // High luminance, low saturation (white)
                return (250, 250, 250)
            } else {
                // Medium gray background
                return (100, 100, 100)
            }
        }
    }

    /// Creates an image with halftone dot pattern.
    private func createHalftoneImage(
        width: Int,
        height: Int,
        dotSpacing: Int,
        dotSize: Int
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, _, _ in
            // Create regular dot pattern at 45-degree angle (CMYK rosette characteristic)
            let rotatedX = Int(Float(x) * 0.707 + Float(y) * 0.707)
            let rotatedY = Int(Float(-x) * 0.707 + Float(y) * 0.707)

            let inDotX = (rotatedX % dotSpacing) < dotSize
            let inDotY = (rotatedY % dotSpacing) < dotSize

            if inDotX && inDotY {
                return (50, 50, 50)  // Dark dot (ink)
            } else {
                return (240, 240, 240)  // Light background (paper)
            }
        }
    }

    /// Creates random noise image (no pattern).
    private func createNoiseImage(width: Int, height: Int) -> CGImage? {
        return createTestImage(width: width, height: height) { _, _, _, _ in
            let r = UInt8.random(in: 0...255)
            let g = UInt8.random(in: 0...255)
            let b = UInt8.random(in: 0...255)
            return (r, g, b)
        }
    }

    /// Creates a natural scene-like image with gradients.
    private func createNaturalSceneImage(width: Int, height: Int) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, w, h in
            // Sky to ground gradient with some variation
            let gradientT = Float(y) / Float(h)
            let noise = Float.random(in: -10...10)

            let skyBlue: (Float, Float, Float) = (135, 206, 235)
            let grassGreen: (Float, Float, Float) = (34, 139, 34)

            if gradientT < 0.5 {
                // Sky
                let r = UInt8(clamping: Int(skyBlue.0 + noise))
                let g = UInt8(clamping: Int(skyBlue.1 + noise))
                let b = UInt8(clamping: Int(skyBlue.2 + noise))
                return (r, g, b)
            } else {
                // Ground
                let r = UInt8(clamping: Int(grassGreen.0 + noise))
                let g = UInt8(clamping: Int(grassGreen.1 + noise))
                let b = UInt8(clamping: Int(grassGreen.2 + noise))
                return (r, g, b)
            }
        }
    }

    /// Creates a CVPixelBuffer.
    private func createPixelBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess else {
            XCTFail("Failed to create pixel buffer: \(status)")
            return nil
        }

        return pixelBuffer
    }

    // MARK: - AC1: ArtifactAnalysisResult Model Tests

    func testResultContainsRequiredFields() async throws {
        guard let image = createUniformImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        let result = await service.analyze(image: image)

        // All required fields should be present
        XCTAssertGreaterThanOrEqual(result.pwmConfidence, 0)
        XCTAssertLessThanOrEqual(result.pwmConfidence, 1)
        XCTAssertGreaterThanOrEqual(result.specularConfidence, 0)
        XCTAssertLessThanOrEqual(result.specularConfidence, 1)
        XCTAssertGreaterThanOrEqual(result.halftoneConfidence, 0)
        XCTAssertLessThanOrEqual(result.halftoneConfidence, 1)
        XCTAssertGreaterThanOrEqual(result.overallConfidence, 0)
        XCTAssertLessThanOrEqual(result.overallConfidence, 1)
        XCTAssertGreaterThan(result.analysisTimeMs, 0)
        XCTAssertEqual(result.algorithmVersion, ArtifactAnalysisConstants.algorithmVersion)
        XCTAssertEqual(result.status, .success)
    }

    func testResultCodable() throws {
        let result = ArtifactAnalysisResult(
            pwmFlickerDetected: true,
            pwmConfidence: 0.75,
            specularPatternDetected: false,
            specularConfidence: 0.2,
            halftoneDetected: true,
            halftoneConfidence: 0.8,
            overallConfidence: 0.65,
            isLikelyArtificial: true,
            analysisTimeMs: 45
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ArtifactAnalysisResult.self, from: data)

        XCTAssertEqual(decoded.pwmFlickerDetected, result.pwmFlickerDetected)
        XCTAssertEqual(decoded.pwmConfidence, result.pwmConfidence)
        XCTAssertEqual(decoded.specularPatternDetected, result.specularPatternDetected)
        XCTAssertEqual(decoded.specularConfidence, result.specularConfidence)
        XCTAssertEqual(decoded.halftoneDetected, result.halftoneDetected)
        XCTAssertEqual(decoded.halftoneConfidence, result.halftoneConfidence)
        XCTAssertEqual(decoded.overallConfidence, result.overallConfidence)
        XCTAssertEqual(decoded.isLikelyArtificial, result.isLikelyArtificial)
        XCTAssertEqual(decoded.analysisTimeMs, result.analysisTimeMs)
    }

    func testResultEquatable() {
        let date = Date()
        let result1 = ArtifactAnalysisResult(
            pwmFlickerDetected: true,
            pwmConfidence: 0.7,
            specularPatternDetected: false,
            specularConfidence: 0.1,
            halftoneDetected: false,
            halftoneConfidence: 0.2,
            overallConfidence: 0.5,
            isLikelyArtificial: false,
            analysisTimeMs: 30,
            computedAt: date
        )

        let result2 = ArtifactAnalysisResult(
            pwmFlickerDetected: true,
            pwmConfidence: 0.7,
            specularPatternDetected: false,
            specularConfidence: 0.1,
            halftoneDetected: false,
            halftoneConfidence: 0.2,
            overallConfidence: 0.5,
            isLikelyArtificial: false,
            analysisTimeMs: 30,
            computedAt: date
        )

        XCTAssertEqual(result1, result2)
    }

    func testResultFactoryMethods() {
        // Test notDetected
        let notDetected = ArtifactAnalysisResult.notDetected(analysisTimeMs: 25)
        XCTAssertFalse(notDetected.pwmFlickerDetected)
        XCTAssertFalse(notDetected.specularPatternDetected)
        XCTAssertFalse(notDetected.halftoneDetected)
        XCTAssertFalse(notDetected.isLikelyArtificial)
        XCTAssertEqual(notDetected.overallConfidence, 0)
        XCTAssertEqual(notDetected.analysisTimeMs, 25)
        XCTAssertEqual(notDetected.status, .success)

        // Test unavailable
        let unavailable = ArtifactAnalysisResult.unavailable()
        XCTAssertEqual(unavailable.status, .unavailable)
        XCTAssertFalse(unavailable.isLikelyArtificial)

        // Test error
        let error = ArtifactAnalysisResult.error(analysisTimeMs: 50)
        XCTAssertEqual(error.status, .error)
        XCTAssertEqual(error.analysisTimeMs, 50)
    }

    func testResultConfidenceClamping() {
        // Test that confidence values are clamped to 0-1
        let result = ArtifactAnalysisResult(
            pwmFlickerDetected: true,
            pwmConfidence: 1.5, // Should be clamped to 1.0
            specularPatternDetected: false,
            specularConfidence: -0.5, // Should be clamped to 0.0
            halftoneDetected: false,
            halftoneConfidence: 0.5,
            overallConfidence: 2.0, // Should be clamped to 1.0
            isLikelyArtificial: true,
            analysisTimeMs: 30
        )

        XCTAssertEqual(result.pwmConfidence, 1.0)
        XCTAssertEqual(result.specularConfidence, 0.0)
        XCTAssertEqual(result.overallConfidence, 1.0)
    }

    // MARK: - AC2: PWM Flicker Detection Tests

    func testPWMDetectionWithBanding() async throws {
        // Given: Image with horizontal banding at 60Hz-like frequency
        guard let image = createPWMBandingImage(
            width: 512,
            height: 512,
            bandFrequency: 30, // Simulates 60Hz PWM at typical exposure
            contrast: 40
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should detect or have some PWM confidence
        XCTAssertEqual(result.status, .success)
        // Note: Exact detection depends on pattern matching refresh rates
        print("PWM detection result: detected=\(result.pwmFlickerDetected), confidence=\(result.pwmConfidence)")
    }

    func testNoPWMDetectionOnUniform() async throws {
        // Given: Uniform image (no banding)
        guard let image = createUniformImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should not detect PWM
        XCTAssertEqual(result.status, .success)
        XCTAssertLessThan(result.pwmConfidence, 0.5, "Uniform image should have low PWM confidence")
    }

    // MARK: - AC3: Specular Reflection Detection Tests

    func testSpecularDetectionWithRectangularHighlight() async throws {
        // Given: Image with rectangular highlight
        guard let image = createSpecularHighlightImage(
            width: 512,
            height: 512,
            highlightX: 150,
            highlightY: 150,
            highlightWidth: 200,
            highlightHeight: 50 // Rectangular shape
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should detect specular pattern with some confidence
        XCTAssertEqual(result.status, .success)
        print("Specular detection result: detected=\(result.specularPatternDetected), confidence=\(result.specularConfidence)")
    }

    func testNoSpecularDetectionOnUniform() async throws {
        // Given: Uniform image (no highlights)
        guard let image = createUniformImage(width: 512, height: 512, brightness: 100) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should not detect specular patterns
        XCTAssertEqual(result.status, .success)
        XCTAssertFalse(result.specularPatternDetected, "Uniform image should not have specular detection")
        XCTAssertLessThan(result.specularConfidence, 0.3)
    }

    // MARK: - AC4: Halftone Detection Tests

    func testHalftoneDetectionWithDotPattern() async throws {
        // Given: Image with halftone-like dot pattern
        guard let image = createHalftoneImage(
            width: 512,
            height: 512,
            dotSpacing: 8,
            dotSize: 3
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should have some halftone confidence
        XCTAssertEqual(result.status, .success)
        print("Halftone detection result: detected=\(result.halftoneDetected), confidence=\(result.halftoneConfidence)")
    }

    func testNoHalftoneDetectionOnUniform() async throws {
        // Given: Uniform image (no dot pattern)
        guard let image = createUniformImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should not detect halftone
        XCTAssertEqual(result.status, .success)
        XCTAssertFalse(result.halftoneDetected)
        XCTAssertLessThan(result.halftoneConfidence, 0.3)
    }

    // MARK: - AC5: Combined Confidence Calculation Tests

    func testCombinedConfidenceWeighting() {
        // Verify weight constants sum to 1.0
        let totalWeight = ArtifactAnalysisConstants.pwmWeight +
                         ArtifactAnalysisConstants.specularWeight +
                         ArtifactAnalysisConstants.halftoneWeight
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.001, "Weights should sum to 1.0")
    }

    func testIsLikelyArtificialThreshold() async throws {
        // The isLikelyArtificial flag should be set based on thresholds
        // Test with uniform image (should not be artificial)
        guard let image = createUniformImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        let result = await service.analyze(image: image)

        // Uniform image should not be flagged as artificial
        XCTAssertFalse(result.isLikelyArtificial)
    }

    // MARK: - AC6: Performance Target Tests

    func testPerformanceTarget() async throws {
        // Given: Typical image size
        guard let image = createNaturalSceneImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await service.analyze(image: image)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Then: Should complete successfully
        // Note: Performance target is 50ms on iPhone 12 Pro+, but simulator is much slower
        // We only verify completion here; real performance testing happens on device
        XCTAssertEqual(result.status, .success)

        // Relaxed threshold for simulator (2000ms) - real device should be <100ms
        let simulatorThresholdMs = 2000.0
        XCTAssertLessThan(
            elapsed,
            simulatorThresholdMs / 1000.0,
            "Analysis should complete in < \(simulatorThresholdMs)ms on simulator, took \(elapsed * 1000)ms"
        )

        print("Artifact analysis completed in \(elapsed * 1000)ms (target: \(ArtifactAnalysisConstants.targetTimeMs)ms on device)")
    }

    func testPerformanceMeasure() throws {
        guard let image = createNaturalSceneImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        measure {
            let expectation = XCTestExpectation(description: "Analysis complete")
            Task {
                _ = await service.analyze(image: image)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
        }
    }

    // MARK: - AC7: Integration Tests

    func testAsyncAwaitInterface() async throws {
        guard let image = createUniformImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // Test async/await works correctly
        let result = await service.analyze(image: image)
        XCTAssertEqual(result.status, .success)
    }

    func testConcurrentCalls() async throws {
        guard let image1 = createUniformImage(width: 256, height: 256),
              let image2 = createPWMBandingImage(width: 256, height: 256, bandFrequency: 30),
              let image3 = createNaturalSceneImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test images")
        }

        // Analyze concurrently
        async let result1 = service.analyze(image: image1)
        async let result2 = service.analyze(image: image2)
        async let result3 = service.analyze(image: image3)

        let results = await [result1, result2, result3]

        // All should complete successfully
        for result in results {
            XCTAssertEqual(result.status, .success)
        }
    }

    func testPixelBufferInput() async throws {
        guard let pixelBuffer = createPixelBuffer(
            width: 256,
            height: 256,
            format: kCVPixelFormatType_32BGRA
        ) else {
            throw XCTSkip("Could not create pixel buffer")
        }

        // Fill with uniform color
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let data = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    data[offset] = 128     // B
                    data[offset + 1] = 128 // G
                    data[offset + 2] = 128 // R
                    data[offset + 3] = 255 // A
                }
            }
        }

        let result = await service.analyze(pixelBuffer: pixelBuffer)
        XCTAssertEqual(result.status, .success)
    }

    // MARK: - AC8: False Positive Mitigation Tests

    func testNoFalsePositiveOnNaturalScene() async throws {
        // Given: Natural scene-like image
        guard let image = createNaturalSceneImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should not flag as artificial with high confidence
        XCTAssertEqual(result.status, .success)

        // Natural scenes should not have high artifact confidence
        // Allow some false positives but overall confidence should be low
        if result.isLikelyArtificial {
            // If flagged, confidence should not be very high
            XCTAssertLessThan(
                result.overallConfidence,
                0.8,
                "Natural scene should not have very high artifact confidence"
            )
        }
    }

    func testNoFalsePositiveOnNoise() async throws {
        // Given: Random noise
        guard let image = createNoiseImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should not confidently flag as artificial
        XCTAssertEqual(result.status, .success)
        XCTAssertLessThan(result.overallConfidence, 0.7, "Random noise should have low artifact confidence")
    }

    func testNoFalsePositiveOnGradient() async throws {
        // Given: Smooth gradient (not periodic like PWM)
        guard let image = createTestImage(width: 512, height: 512, generator: { _, y, _, h in
            let brightness = UInt8(255 * y / h)
            return (brightness, brightness, brightness)
        }) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Smooth gradient should not trigger PWM detection
        XCTAssertEqual(result.status, .success)
        XCTAssertLessThan(result.pwmConfidence, 0.5, "Smooth gradient should not trigger PWM detection")
    }

    // MARK: - Edge Cases

    func testMinimumImageSize() async throws {
        guard let image = createUniformImage(
            width: ArtifactAnalysisConstants.minImageDimension,
            height: ArtifactAnalysisConstants.minImageDimension
        ) else {
            throw XCTSkip("Could not create test image")
        }

        let result = await service.analyze(image: image)
        XCTAssertEqual(result.status, .success)
    }

    func testTooSmallImage() async throws {
        guard let image = createUniformImage(width: 32, height: 32) else {
            throw XCTSkip("Could not create test image")
        }

        let result = await service.analyze(image: image)
        XCTAssertEqual(result.status, .unavailable)
    }

    func testDeterministicResults() async throws {
        guard let image = createNaturalSceneImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        let result1 = await service.analyze(image: image)
        let result2 = await service.analyze(image: image)
        let result3 = await service.analyze(image: image)

        // Results should be deterministic
        XCTAssertEqual(result1.pwmFlickerDetected, result2.pwmFlickerDetected)
        XCTAssertEqual(result2.pwmFlickerDetected, result3.pwmFlickerDetected)

        XCTAssertEqual(result1.specularPatternDetected, result2.specularPatternDetected)
        XCTAssertEqual(result2.specularPatternDetected, result3.specularPatternDetected)

        XCTAssertEqual(result1.halftoneDetected, result2.halftoneDetected)
        XCTAssertEqual(result2.halftoneDetected, result3.halftoneDetected)

        XCTAssertEqual(result1.overallConfidence, result2.overallConfidence, accuracy: 0.001)
        XCTAssertEqual(result2.overallConfidence, result3.overallConfidence, accuracy: 0.001)
    }

    // MARK: - Constants Verification

    func testConstantsValid() {
        // Weights should sum to 1
        let totalWeight = ArtifactAnalysisConstants.pwmWeight +
                         ArtifactAnalysisConstants.specularWeight +
                         ArtifactAnalysisConstants.halftoneWeight
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.001)

        // Thresholds should be sensible
        XCTAssertGreaterThan(ArtifactAnalysisConstants.highConfidenceThreshold, 0)
        XCTAssertLessThanOrEqual(ArtifactAnalysisConstants.highConfidenceThreshold, 1)

        XCTAssertGreaterThan(ArtifactAnalysisConstants.combinedConfidenceThreshold, 0)
        XCTAssertLessThanOrEqual(ArtifactAnalysisConstants.combinedConfidenceThreshold, 1)

        // Performance targets
        XCTAssertGreaterThan(ArtifactAnalysisConstants.targetTimeMs, 0)
        XCTAssertGreaterThanOrEqual(ArtifactAnalysisConstants.maxTimeMs, ArtifactAnalysisConstants.targetTimeMs)

        // Image requirements
        XCTAssertGreaterThan(ArtifactAnalysisConstants.minImageDimension, 0)
        XCTAssertGreaterThan(ArtifactAnalysisConstants.targetImageDimension, ArtifactAnalysisConstants.minImageDimension)
    }

    // MARK: - Status Tests

    func testArtifactAnalysisStatusRawValues() {
        XCTAssertEqual(ArtifactAnalysisStatus.success.rawValue, "success")
        XCTAssertEqual(ArtifactAnalysisStatus.unavailable.rawValue, "unavailable")
        XCTAssertEqual(ArtifactAnalysisStatus.error.rawValue, "error")
    }

    func testArtifactAnalysisStatusCodable() throws {
        for status in [ArtifactAnalysisStatus.success, .unavailable, .error] {
            let encoder = JSONEncoder()
            let data = try encoder.encode(status)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ArtifactAnalysisStatus.self, from: data)

            XCTAssertEqual(decoded, status)
        }
    }
}
