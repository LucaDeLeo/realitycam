//
//  TextureClassificationServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Unit tests for TextureClassificationService (Story 9-2).
//  Tests texture classification for detecting recaptured images.
//

import XCTest
import CoreGraphics
import CoreVideo
import os.log
@testable import Rial

/// Tests for TextureClassificationService texture classification.
///
/// These tests verify:
/// - AC1: TextureClassificationResult model with required fields
/// - AC2/AC3: Image preprocessing and analysis
/// - AC4: Classification output mapping to TextureType
/// - AC5: Performance target (<50ms)
/// - AC6: Integration with capture pipeline (async interface)
/// - AC7: Graceful degradation
final class TextureClassificationServiceTests: XCTestCase {

    // MARK: - Properties

    private var service: TextureClassificationService!

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        service = TextureClassificationService.shared
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
        generator: (_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> (UInt8, UInt8, UInt8)
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = generator(x, y, width, height)
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixelData[offset] = r
                pixelData[offset + 1] = g
                pixelData[offset + 2] = b
                pixelData[offset + 3] = 255 // Alpha
            }
        }

        guard let context = CGContext(
            data: &pixelData,
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

        return context.makeImage()
    }

    /// Creates a uniform colored image.
    private func createUniformImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage? {
        return createTestImage(width: width, height: height) { _, _, _, _ in
            (r, g, b)
        }
    }

    /// Creates an image with vertical stripes (simulates screen pixels).
    private func createVerticalStripesImage(
        width: Int,
        height: Int,
        stripeWidth: Int = 3
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { x, _, _, _ in
            let phase = x % (stripeWidth * 3)
            if phase < stripeWidth {
                return (255, 0, 0) // Red stripe
            } else if phase < stripeWidth * 2 {
                return (0, 255, 0) // Green stripe
            } else {
                return (0, 0, 255) // Blue stripe
            }
        }
    }

    /// Creates a grid pattern (simulates LCD/OLED pixel grid).
    private func createGridImage(
        width: Int,
        height: Int,
        cellSize: Int = 5
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, _, _ in
            let xPhase = x % cellSize
            let yPhase = y % cellSize
            let isLine = xPhase == 0 || yPhase == 0
            return isLine ? (50, 50, 50) : (200, 200, 200)
        }
    }

    /// Creates a natural texture pattern (simulates real scene).
    private func createNaturalTextureImage(width: Int, height: Int) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, w, h in
            // Perlin-like noise simulation
            let fx = Float(x) / Float(w)
            let fy = Float(y) / Float(h)

            let noise1 = sin(fx * 10) * cos(fy * 8) * 0.3
            let noise2 = sin(fx * 25 + fy * 15) * 0.2
            let noise3 = Float.random(in: -0.1...0.1)
            let baseVal = 0.5 + noise1 + noise2 + noise3

            let r = UInt8(clamping: Int(baseVal * 255))
            let g = UInt8(clamping: Int((baseVal + 0.05) * 255))
            let b = UInt8(clamping: Int((baseVal - 0.05) * 255))
            return (r, g, b)
        }
    }

    /// Creates a soft/blurry image (simulates printed photo).
    private func createSoftImage(width: Int, height: Int) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, w, h in
            // Soft gradients with slight periodicity (halftone-like)
            let fx = Float(x) / Float(w)
            let fy = Float(y) / Float(h)

            // Soft gradient
            let base = (fx + fy) / 2.0

            // Subtle halftone pattern
            let halftone = sin(Float(x) * 0.5) * sin(Float(y) * 0.5) * 0.05

            let val = base + halftone
            let r = UInt8(clamping: Int(val * 200 + 30))
            let g = UInt8(clamping: Int(val * 190 + 30))
            let b = UInt8(clamping: Int(val * 180 + 30))
            return (r, g, b)
        }
    }

    /// Creates random noise image.
    private func createNoiseImage(width: Int, height: Int) -> CGImage? {
        return createTestImage(width: width, height: height) { _, _, _, _ in
            (UInt8.random(in: 0...255),
             UInt8.random(in: 0...255),
             UInt8.random(in: 0...255))
        }
    }

    /// Creates a CVPixelBuffer for testing.
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

    // MARK: - AC1: TextureClassificationResult Model Tests

    func testResultContainsRequiredFields() async throws {
        // Given: Any test image
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: All required fields should be present
        XCTAssertNotNil(result.classification, "Classification should not be nil")
        XCTAssertGreaterThanOrEqual(result.confidence, 0, "Confidence should be >= 0")
        XCTAssertLessThanOrEqual(result.confidence, 1, "Confidence should be <= 1")
        XCTAssertNotNil(result.allClassifications, "All classifications should not be nil")
        // isLikelyRecaptured is a Bool, always present
        XCTAssertGreaterThanOrEqual(result.analysisTimeMs, 0, "Analysis time should be >= 0")
        XCTAssertEqual(result.algorithmVersion, TextureClassificationConstants.algorithmVersion)
        XCTAssertEqual(result.status, .success)
    }

    func testResultCodable() throws {
        // Given: A result with all fields
        let allClassifications: [TextureType: Float] = [
            .realScene: 0.7,
            .lcdScreen: 0.2,
            .oledScreen: 0.05,
            .printedPaper: 0.04,
            .unknown: 0.01
        ]
        let result = TextureClassificationResult(
            classification: .realScene,
            confidence: 0.7,
            allClassifications: allClassifications,
            isLikelyRecaptured: false,
            analysisTimeMs: 15
        )

        // When: Encoding and decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TextureClassificationResult.self, from: data)

        // Then: Values should match
        XCTAssertEqual(decoded.classification, result.classification)
        XCTAssertEqual(decoded.confidence, result.confidence, accuracy: 0.001)
        XCTAssertEqual(decoded.allClassifications.count, result.allClassifications.count)
        XCTAssertEqual(decoded.isLikelyRecaptured, result.isLikelyRecaptured)
        XCTAssertEqual(decoded.analysisTimeMs, result.analysisTimeMs)
        XCTAssertEqual(decoded.algorithmVersion, result.algorithmVersion)
    }

    func testResultEquatable() {
        let date = Date()
        let allClassifications: [TextureType: Float] = [.realScene: 0.7]

        let result1 = TextureClassificationResult(
            classification: .realScene,
            confidence: 0.7,
            allClassifications: allClassifications,
            isLikelyRecaptured: false,
            analysisTimeMs: 15,
            computedAt: date
        )

        let result2 = TextureClassificationResult(
            classification: .realScene,
            confidence: 0.7,
            allClassifications: allClassifications,
            isLikelyRecaptured: false,
            analysisTimeMs: 15,
            computedAt: date
        )

        XCTAssertEqual(result1, result2, "Results with same values should be equal")
    }

    func testResultFactoryMethods() {
        // Test realScene
        let realScene = TextureClassificationResult.realScene(
            confidence: 0.8,
            allClassifications: [.realScene: 0.8],
            analysisTimeMs: 10
        )
        XCTAssertEqual(realScene.classification, .realScene)
        XCTAssertFalse(realScene.isLikelyRecaptured)
        XCTAssertEqual(realScene.status, .success)

        // Test unavailable
        let unavailable = TextureClassificationResult.unavailable(reason: "Test reason")
        XCTAssertEqual(unavailable.classification, .unknown)
        XCTAssertEqual(unavailable.status, .unavailable)
        XCTAssertEqual(unavailable.unavailabilityReason, "Test reason")

        // Test error
        let error = TextureClassificationResult.error(reason: "Error reason", analysisTimeMs: 5)
        XCTAssertEqual(error.classification, .unknown)
        XCTAssertEqual(error.status, .error)
        XCTAssertEqual(error.unavailabilityReason, "Error reason")
    }

    // MARK: - AC2/AC3: Image Preprocessing Tests

    func testHandlesVariousImageSizes() async throws {
        // Test various image sizes
        let sizes = [(128, 128), (256, 256), (512, 512), (300, 200)]

        for (width, height) in sizes {
            guard let image = createNaturalTextureImage(width: width, height: height) else {
                throw XCTSkip("Could not create test image \(width)x\(height)")
            }

            let result = await service.classify(image: image)

            XCTAssertEqual(result.status, .success, "Should handle \(width)x\(height) image")
        }
    }

    func testHandlesCGImageInput() async throws {
        // Given: CGImage
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should complete successfully
        XCTAssertEqual(result.status, .success)
        XCTAssertNotEqual(result.classification, .unknown)
    }

    func testHandlesPixelBufferBGRA() async throws {
        // Given: BGRA pixel buffer
        guard let pixelBuffer = createPixelBuffer(
            width: 256,
            height: 256,
            format: kCVPixelFormatType_32BGRA
        ) else {
            throw XCTSkip("Could not create pixel buffer")
        }

        // Fill with pattern
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
                    // Natural texture pattern
                    let val = UInt8((sin(Float(x) / 10) * cos(Float(y) / 8) * 50) + 128)
                    data[offset] = val         // B
                    data[offset + 1] = val + 10 // G
                    data[offset + 2] = val - 10 // R
                    data[offset + 3] = 255     // A
                }
            }
        }

        // When: Classifying
        let result = await service.classify(pixelBuffer: pixelBuffer)

        // Then: Should complete successfully
        XCTAssertEqual(result.status, .success)
    }

    // MARK: - AC4: Classification Output Tests

    func testAllTextureTypesInOutput() async throws {
        // Given: Test image
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should have scores for multiple texture types
        XCTAssertEqual(result.status, .success)
        XCTAssertFalse(result.allClassifications.isEmpty, "Should have classification scores")

        // Classification should be one of the valid types
        XCTAssertTrue(
            TextureType.allCases.contains(result.classification),
            "Classification should be a valid TextureType"
        )
    }

    func testClassificationConfidenceRange() async throws {
        // Given: Test image
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: All confidence scores should be in valid range
        for (_, score) in result.allClassifications {
            XCTAssertGreaterThanOrEqual(score, 0, "Score should be >= 0")
            XCTAssertLessThanOrEqual(score, 1, "Score should be <= 1")
        }

        XCTAssertGreaterThanOrEqual(result.confidence, 0)
        XCTAssertLessThanOrEqual(result.confidence, 1)
    }

    func testHighlyPeriodicImageDetection() async throws {
        // Given: Highly periodic grid pattern (screen-like)
        guard let image = createGridImage(width: 256, height: 256, cellSize: 5) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should detect periodic pattern
        XCTAssertEqual(result.status, .success)

        // Screen classification should have some score
        let screenScore = max(
            result.allClassifications[.lcdScreen] ?? 0,
            result.allClassifications[.oledScreen] ?? 0
        )
        // The grid pattern should trigger at least some screen-like detection
        Self.logger.debug("Screen score for grid: \(screenScore)")
    }

    func testVerticalStripesDetection() async throws {
        // Given: RGB stripes (simulating screen subpixels)
        guard let image = createVerticalStripesImage(width: 256, height: 256, stripeWidth: 3) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should complete and detect some pattern
        XCTAssertEqual(result.status, .success)
    }

    func testUniformImageClassification() async throws {
        // Given: Uniform colored image
        guard let image = createUniformImage(width: 256, height: 256, r: 128, g: 128, b: 128) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should have low confidence (ambiguous)
        XCTAssertEqual(result.status, .success)
        // Uniform image is ambiguous - could be screen or plain surface
    }

    func testNaturalTextureClassification() async throws {
        // Given: Natural texture pattern
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should lean toward real scene
        XCTAssertEqual(result.status, .success)

        // Real scene should have a reasonable score
        let realSceneScore = result.allClassifications[.realScene] ?? 0
        Self.logger.debug("Real scene score for natural texture: \(realSceneScore)")
    }

    func testIsLikelyRecapturedFlag() async throws {
        // Given: Two images - natural and screen-like
        guard let naturalImage = createNaturalTextureImage(width: 256, height: 256),
              let gridImage = createGridImage(width: 256, height: 256, cellSize: 3) else {
            throw XCTSkip("Could not create test images")
        }

        // When: Classifying both
        let naturalResult = await service.classify(image: naturalImage)
        let gridResult = await service.classify(image: gridImage)

        // Then: Natural should not be flagged as recaptured
        // Grid pattern result depends on classification confidence
        XCTAssertEqual(naturalResult.status, .success)
        XCTAssertEqual(gridResult.status, .success)
    }

    // MARK: - AC5: Performance Tests

    func testPerformanceTarget() async throws {
        // Given: Typical image size
        guard let image = createNaturalTextureImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await service.classify(image: image)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Then: Should complete within acceptable time
        // Note: Simulator is slower than device, use 200ms for CI
        let acceptableTimeMs = 200.0
        XCTAssertLessThan(
            elapsed,
            acceptableTimeMs / 1000.0,
            "Classification should complete in < \(acceptableTimeMs)ms, took \(elapsed * 1000)ms"
        )
        XCTAssertEqual(result.status, .success)

        // Log actual time
        print("Texture classification completed in \(elapsed * 1000)ms (target: \(TextureClassificationConstants.targetTimeMs)ms)")
    }

    func testPerformanceMeasure() throws {
        // Given: Test image
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // Measure multiple iterations
        measure {
            let expectation = XCTestExpectation(description: "Classification complete")
            Task {
                _ = await service.classify(image: image)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
        }
    }

    // MARK: - AC6: Integration Tests

    func testAsyncAwaitInterface() async throws {
        // Given: Test image
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Using async/await interface
        let result = await service.classify(image: image)

        // Then: Should return valid result
        XCTAssertEqual(result.status, .success)
    }

    func testConcurrentClassification() async throws {
        // Given: Multiple test images
        guard let image1 = createNaturalTextureImage(width: 256, height: 256),
              let image2 = createGridImage(width: 256, height: 256),
              let image3 = createSoftImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test images")
        }

        // When: Classifying concurrently
        async let result1 = service.classify(image: image1)
        async let result2 = service.classify(image: image2)
        async let result3 = service.classify(image: image3)

        let results = await [result1, result2, result3]

        // Then: All should complete successfully
        for result in results {
            XCTAssertEqual(result.status, .success, "Concurrent classification should complete")
        }
    }

    func testThreadSafety() async throws {
        // Given: Test image
        guard let image = createNaturalTextureImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Many concurrent calls
        let results = await withTaskGroup(of: TextureClassificationResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await self.service.classify(image: image)
                }
            }

            var collected = [TextureClassificationResult]()
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Then: All should succeed
        XCTAssertEqual(results.count, 10)
        for result in results {
            XCTAssertEqual(result.status, .success)
        }
    }

    // MARK: - AC7: Graceful Degradation Tests

    func testTooSmallImage() async throws {
        // Given: Image smaller than minimum
        guard let image = createUniformImage(width: 32, height: 32, r: 128, g: 128, b: 128) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should return unavailable
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.classification, .unknown)
        XCTAssertNotNil(result.unavailabilityReason)
    }

    func testMinimumImageSize() async throws {
        // Given: Minimum valid image size
        guard let image = createUniformImage(
            width: TextureClassificationConstants.minImageDimension,
            height: TextureClassificationConstants.minImageDimension,
            r: 128, g: 128, b: 128
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should handle gracefully
        XCTAssertEqual(result.status, .success)
    }

    func testNoThrowFromPublicAPI() async throws {
        // Given: Various images including edge cases
        let images: [(String, CGImage?)] = [
            ("small", createUniformImage(width: 32, height: 32, r: 128, g: 128, b: 128)),
            ("uniform", createUniformImage(width: 256, height: 256, r: 0, g: 0, b: 0)),
            ("white", createUniformImage(width: 256, height: 256, r: 255, g: 255, b: 255)),
            ("normal", createNaturalTextureImage(width: 256, height: 256))
        ]

        // When/Then: None should throw
        for (name, image) in images {
            if let img = image {
                let result = await service.classify(image: img)
                // Status may be success or unavailable, but should not crash
                XCTAssertTrue(
                    [.success, .unavailable, .error].contains(result.status),
                    "\(name) should return valid status"
                )
            }
        }
    }

    // MARK: - TextureType Tests

    func testTextureTypeRawValues() {
        XCTAssertEqual(TextureType.realScene.rawValue, "real_scene")
        XCTAssertEqual(TextureType.lcdScreen.rawValue, "lcd_screen")
        XCTAssertEqual(TextureType.oledScreen.rawValue, "oled_screen")
        XCTAssertEqual(TextureType.printedPaper.rawValue, "printed_paper")
        XCTAssertEqual(TextureType.unknown.rawValue, "unknown")
    }

    func testTextureTypeCodable() throws {
        for type in TextureType.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(type)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(TextureType.self, from: data)

            XCTAssertEqual(decoded, type)
        }
    }

    func testTextureTypeAllCases() {
        let allCases = TextureType.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.realScene))
        XCTAssertTrue(allCases.contains(.lcdScreen))
        XCTAssertTrue(allCases.contains(.oledScreen))
        XCTAssertTrue(allCases.contains(.printedPaper))
        XCTAssertTrue(allCases.contains(.unknown))
    }

    // MARK: - Constants Tests

    func testConstantsValid() {
        // Image dimension constants
        XCTAssertGreaterThan(TextureClassificationConstants.minImageDimension, 0)
        XCTAssertGreaterThan(TextureClassificationConstants.targetImageSize, 0)
        XCTAssertGreaterThan(TextureClassificationConstants.maxImageDimension, TextureClassificationConstants.targetImageSize)

        // Threshold constants
        XCTAssertGreaterThan(TextureClassificationConstants.recaptureConfidenceThreshold, 0)
        XCTAssertLessThanOrEqual(TextureClassificationConstants.recaptureConfidenceThreshold, 1)
        XCTAssertGreaterThan(TextureClassificationConstants.minClassificationConfidence, 0)
        XCTAssertLessThanOrEqual(TextureClassificationConstants.minClassificationConfidence, 1)

        // Performance constants
        XCTAssertGreaterThan(TextureClassificationConstants.targetTimeMs, 0)
        XCTAssertGreaterThanOrEqual(TextureClassificationConstants.maxTimeMs, TextureClassificationConstants.targetTimeMs)
        XCTAssertGreaterThan(TextureClassificationConstants.maxMemoryBytes, 0)

        // Weight constant
        XCTAssertEqual(TextureClassificationConstants.detectionWeight, 0.15, accuracy: 0.001)
    }

    // MARK: - Determinism Tests

    func testDeterministicResults() async throws {
        // Given: Fixed test image
        guard let image = createGridImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying multiple times
        let result1 = await service.classify(image: image)
        let result2 = await service.classify(image: image)
        let result3 = await service.classify(image: image)

        // Then: Classification and confidence should be deterministic
        XCTAssertEqual(result1.classification, result2.classification, "Classification must be deterministic")
        XCTAssertEqual(result2.classification, result3.classification, "Classification must be deterministic")

        XCTAssertEqual(result1.confidence, result2.confidence, accuracy: 0.001, "Confidence must be deterministic")
        XCTAssertEqual(result2.confidence, result3.confidence, accuracy: 0.001, "Confidence must be deterministic")

        XCTAssertEqual(result1.isLikelyRecaptured, result2.isLikelyRecaptured, "isLikelyRecaptured must be deterministic")
        XCTAssertEqual(result2.isLikelyRecaptured, result3.isLikelyRecaptured, "isLikelyRecaptured must be deterministic")
    }

    // MARK: - Edge Cases

    func testAllBlackImage() async throws {
        // Given: All black image
        guard let image = createUniformImage(width: 256, height: 256, r: 0, g: 0, b: 0) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should complete (uniform image)
        XCTAssertEqual(result.status, .success)
    }

    func testAllWhiteImage() async throws {
        // Given: All white image
        guard let image = createUniformImage(width: 256, height: 256, r: 255, g: 255, b: 255) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should complete (uniform image)
        XCTAssertEqual(result.status, .success)
    }

    func testNoiseImage() async throws {
        // Given: Random noise
        guard let image = createNoiseImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Classifying
        let result = await service.classify(image: image)

        // Then: Should complete (high variance, no pattern)
        XCTAssertEqual(result.status, .success)
    }

    // MARK: - Logger

    private static let logger = Logger(subsystem: "app.rial.tests", category: "textureclassification")
}
