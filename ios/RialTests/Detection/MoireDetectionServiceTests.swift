//
//  MoireDetectionServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Unit tests for MoireDetectionService (Story 9-1).
//  Tests 2D FFT analysis for screen moire pattern detection.
//

import XCTest
import CoreGraphics
import CoreVideo
@testable import Rial

/// Tests for MoireDetectionService moire pattern detection.
///
/// These tests verify:
/// - AC1: 2D FFT via Accelerate framework
/// - AC2: Frequency peak detection
/// - AC3: Screen type classification
/// - AC4: MoireAnalysisResult output
/// - AC5: Performance target (<100ms)
/// - AC6: Integration readiness
/// - AC7: False positive mitigation
final class MoireDetectionServiceTests: XCTestCase {

    // MARK: - Properties

    private var service: MoireDetectionService!

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        service = MoireDetectionService.shared
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
        generator: (_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> UInt8
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            XCTFail("Failed to create context")
            return nil
        }

        guard let data = context.data else {
            XCTFail("Failed to get context data")
            return nil
        }

        let bytePointer = data.bindMemory(to: UInt8.self, capacity: width * height)

        for y in 0..<height {
            for x in 0..<width {
                bytePointer[y * width + x] = generator(x, y, width, height)
            }
        }

        return context.makeImage()
    }

    /// Creates a uniform gray image (no moire pattern).
    private func createUniformImage(width: Int, height: Int, brightness: UInt8 = 128) -> CGImage? {
        return createTestImage(width: width, height: height) { _, _, _, _ in
            brightness
        }
    }

    /// Creates an image with vertical stripes (simulates LCD moire).
    private func createVerticalStripesImage(
        width: Int,
        height: Int,
        frequency: Int
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { x, _, w, _ in
            // Create vertical stripes at specified frequency
            let period = w / frequency
            let phase = x % max(1, period)
            return phase < period / 2 ? UInt8(200) : UInt8(50)
        }
    }

    /// Creates an image with horizontal stripes.
    private func createHorizontalStripesImage(
        width: Int,
        height: Int,
        frequency: Int
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { _, y, _, h in
            let period = h / frequency
            let phase = y % max(1, period)
            return phase < period / 2 ? UInt8(200) : UInt8(50)
        }
    }

    /// Creates an image with grid pattern (horizontal + vertical stripes).
    private func createGridPatternImage(
        width: Int,
        height: Int,
        frequencyX: Int,
        frequencyY: Int
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, w, h in
            let periodX = w / frequencyX
            let periodY = h / frequencyY
            let phaseX = x % max(1, periodX)
            let phaseY = y % max(1, periodY)

            let valX: UInt8 = phaseX < periodX / 2 ? 200 : 50
            let valY: UInt8 = phaseY < periodY / 2 ? 200 : 50

            // Combine: grid pattern
            return UInt8((Int(valX) + Int(valY)) / 2)
        }
    }

    /// Creates a sinusoidal pattern (for FFT verification).
    private func createSineWaveImage(
        width: Int,
        height: Int,
        frequencyX: Float,
        frequencyY: Float = 0
    ) -> CGImage? {
        return createTestImage(width: width, height: height) { x, y, w, h in
            let fx = sin(2 * Float.pi * frequencyX * Float(x) / Float(w))
            let fy = frequencyY > 0 ? sin(2 * Float.pi * frequencyY * Float(y) / Float(h)) : 0
            let combined = (fx + fy + 2) / 4 // Normalize to 0-1
            return UInt8(combined * 255)
        }
    }

    /// Creates random noise image (no periodic pattern).
    private func createNoiseImage(width: Int, height: Int) -> CGImage? {
        return createTestImage(width: width, height: height) { _, _, _, _ in
            UInt8.random(in: 0...255)
        }
    }

    /// Creates a CVPixelBuffer from grayscale data.
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

    // MARK: - AC1: 2D FFT via Accelerate

    func testFFTOnSineWave() async throws {
        // Given: Sine wave at known frequency (100 cycles)
        guard let image = createSineWaveImage(
            width: 512,
            height: 512,
            frequencyX: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should detect peaks near 100 cycles
        XCTAssertEqual(result.status, .completed)
        XCTAssertFalse(result.peaks.isEmpty, "Should detect frequency peaks")

        // The strongest peak should be near our input frequency
        if let strongestPeak = result.peaks.first {
            // Allow some tolerance due to windowing and sampling
            XCTAssertGreaterThan(strongestPeak.frequency, 50, "Peak frequency should be detectable")
            XCTAssertLessThan(strongestPeak.frequency, 200, "Peak frequency should be in expected range")
        }
    }

    func testFFTHandlesPowerOf2() async throws {
        // Given: Image with non-power-of-2 dimensions
        guard let image = createVerticalStripesImage(
            width: 300,
            height: 200,
            frequency: 75
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should complete successfully (padding to power-of-2)
        XCTAssertEqual(result.status, .completed)
    }

    func testFFTHandlesLargeImage() async throws {
        // Given: Large image (full iPhone resolution)
        // Note: Using smaller size for unit tests to avoid memory issues
        guard let image = createVerticalStripesImage(
            width: 1024,
            height: 768,
            frequency: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should complete successfully (downsampling if needed)
        XCTAssertEqual(result.status, .completed)
    }

    // MARK: - AC2: Frequency Peak Detection

    func testPeakDetectionWithStripes() async throws {
        // Given: Clear vertical stripes (should produce frequency peaks)
        guard let image = createVerticalStripesImage(
            width: 512,
            height: 512,
            frequency: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should detect peaks
        XCTAssertEqual(result.status, .completed)
        XCTAssertGreaterThan(result.peaks.count, 0, "Should detect peaks in striped pattern")
    }

    func testPeakDetectionWithUniformImage() async throws {
        // Given: Uniform gray image (no peaks)
        guard let image = createUniformImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should detect no significant peaks
        XCTAssertEqual(result.status, .completed)
        XCTAssertFalse(result.detected, "Uniform image should not trigger detection")
    }

    func testPeakDetectionFrequencyRange() async throws {
        // Given: Stripes in moire frequency range
        guard let image = createVerticalStripesImage(
            width: 512,
            height: 512,
            frequency: 75 // Within 50-300 range
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Peaks should be in expected frequency range
        for peak in result.peaks {
            XCTAssertGreaterThanOrEqual(
                peak.frequency,
                MoireAnalysisConstants.minFrequency * 0.5, // Allow some tolerance
                "Peak frequency should be above minimum"
            )
            XCTAssertLessThanOrEqual(
                peak.frequency,
                MoireAnalysisConstants.maxFrequency * 1.5, // Allow some tolerance
                "Peak frequency should be below maximum"
            )
        }
    }

    func testPeakProminence() async throws {
        // Given: Strong periodic pattern
        guard let image = createGridPatternImage(
            width: 512,
            height: 512,
            frequencyX: 100,
            frequencyY: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Peaks should have prominence > threshold
        for peak in result.peaks {
            XCTAssertGreaterThan(
                peak.prominence,
                0,
                "Peaks should have positive prominence"
            )
        }
    }

    // MARK: - AC3: Screen Type Classification

    func testScreenTypeClassificationGrid() async throws {
        // Given: Grid pattern (simulating LCD screen)
        guard let image = createGridPatternImage(
            width: 512,
            height: 512,
            frequencyX: 100,
            frequencyY: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should classify as some screen type
        XCTAssertEqual(result.status, .completed)
        // Note: Actual classification depends on pattern characteristics
        // At minimum, should detect the pattern
        if result.detected {
            XCTAssertNotNil(result.screenType, "Detected pattern should have screen type")
        }
    }

    func testScreenTypeUnknownForAmbiguous() async throws {
        // Given: Pattern that doesn't match known screen types
        guard let image = createSineWaveImage(
            width: 512,
            height: 512,
            frequencyX: 50,
            frequencyY: 150 // Non-standard ratio
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: May classify as unknown if pattern detected
        XCTAssertEqual(result.status, .completed)
        if result.detected && result.screenType != nil {
            // unknown is acceptable for ambiguous patterns
            XCTAssertTrue([.lcd, .oled, .highRefresh, .unknown].contains(result.screenType!))
        }
    }

    // MARK: - AC4: MoireAnalysisResult Output

    func testResultContainsRequiredFields() async throws {
        // Given: Any test image
        guard let image = createVerticalStripesImage(
            width: 512,
            height: 512,
            frequency: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: All required fields should be present
        // detected is a Bool, always present
        XCTAssertGreaterThanOrEqual(result.confidence, 0, "Confidence should be >= 0")
        XCTAssertLessThanOrEqual(result.confidence, 1, "Confidence should be <= 1")
        XCTAssertNotNil(result.peaks, "Peaks array should not be nil")
        XCTAssertGreaterThan(result.analysisTimeMs, 0, "Analysis time should be > 0")
        XCTAssertEqual(result.algorithmVersion, MoireAnalysisConstants.algorithmVersion)
        XCTAssertEqual(result.status, .completed)
    }

    func testResultCodable() throws {
        // Given: A result with all fields
        let peaks = [
            FrequencyPeak(frequency: 100, magnitude: 0.8, angle: 0, prominence: 5),
            FrequencyPeak(frequency: 100, magnitude: 0.7, angle: Float.pi / 2, prominence: 4)
        ]
        let result = MoireAnalysisResult(
            detected: true,
            confidence: 0.75,
            peaks: peaks,
            screenType: .lcd,
            analysisTimeMs: 25
        )

        // When: Encoding and decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MoireAnalysisResult.self, from: data)

        // Then: Values should match
        XCTAssertEqual(decoded.detected, result.detected)
        XCTAssertEqual(decoded.confidence, result.confidence)
        XCTAssertEqual(decoded.peaks.count, result.peaks.count)
        XCTAssertEqual(decoded.screenType, result.screenType)
        XCTAssertEqual(decoded.analysisTimeMs, result.analysisTimeMs)
        XCTAssertEqual(decoded.algorithmVersion, result.algorithmVersion)
    }

    func testResultEquatable() {
        let date = Date()
        let peaks = [FrequencyPeak(frequency: 100, magnitude: 0.8, angle: 0, prominence: 5)]

        let result1 = MoireAnalysisResult(
            detected: true,
            confidence: 0.7,
            peaks: peaks,
            screenType: .lcd,
            analysisTimeMs: 25,
            computedAt: date
        )

        let result2 = MoireAnalysisResult(
            detected: true,
            confidence: 0.7,
            peaks: peaks,
            screenType: .lcd,
            analysisTimeMs: 25,
            computedAt: date
        )

        XCTAssertEqual(result1, result2, "Results with same values should be equal")
    }

    func testResultFactoryMethods() {
        // Test notDetected
        let notDetected = MoireAnalysisResult.notDetected(analysisTimeMs: 15)
        XCTAssertFalse(notDetected.detected)
        XCTAssertEqual(notDetected.confidence, 0)
        XCTAssertTrue(notDetected.peaks.isEmpty)
        XCTAssertNil(notDetected.screenType)
        XCTAssertEqual(notDetected.analysisTimeMs, 15)
        XCTAssertEqual(notDetected.status, .completed)

        // Test unavailable
        let unavailable = MoireAnalysisResult.unavailable()
        XCTAssertFalse(unavailable.detected)
        XCTAssertEqual(unavailable.status, .unavailable)

        // Test failed
        let failed = MoireAnalysisResult.failed(analysisTimeMs: 50)
        XCTAssertFalse(failed.detected)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.analysisTimeMs, 50)
    }

    // MARK: - AC5: Performance Target

    func testPerformanceTarget() async throws {
        // Given: Typical image size
        guard let image = createGridPatternImage(
            width: 512,
            height: 512,
            frequencyX: 100,
            frequencyY: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await service.analyze(image: image)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Then: Should complete within acceptable time
        // Note: Simulator is slower than device, use 500ms as acceptable target for CI
        // Device should meet 100ms target (30ms goal)
        let acceptableTimeMs = 500.0 // Relaxed for simulator testing
        XCTAssertLessThan(
            elapsed,
            acceptableTimeMs / 1000.0,
            "Analysis should complete in < \(acceptableTimeMs)ms, took \(elapsed * 1000)ms"
        )
        XCTAssertEqual(result.status, .completed)

        // Log actual time for reference
        print("Moire analysis completed in \(elapsed * 1000)ms (target: \(MoireAnalysisConstants.targetTimeMs)ms)")
    }

    func testPerformanceMeasure() throws {
        // Given: Test image
        guard let image = createGridPatternImage(
            width: 512,
            height: 512,
            frequencyX: 100,
            frequencyY: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // Measure multiple iterations
        measure {
            let expectation = XCTestExpectation(description: "Analysis complete")
            Task {
                _ = await service.analyze(image: image)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
        }
    }

    // MARK: - AC6: Integration Readiness

    func testAsyncAwaitInterface() async throws {
        // Given: Test image
        guard let image = createUniformImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Using async/await interface
        let result = await service.analyze(image: image)

        // Then: Should return valid result
        XCTAssertEqual(result.status, .completed)
    }

    func testConcurrentCalls() async throws {
        // Given: Multiple test images
        guard let image1 = createVerticalStripesImage(width: 256, height: 256, frequency: 50),
              let image2 = createHorizontalStripesImage(width: 256, height: 256, frequency: 75),
              let image3 = createUniformImage(width: 256, height: 256) else {
            throw XCTSkip("Could not create test images")
        }

        // When: Analyzing concurrently
        async let result1 = service.analyze(image: image1)
        async let result2 = service.analyze(image: image2)
        async let result3 = service.analyze(image: image3)

        let results = await [result1, result2, result3]

        // Then: All should complete successfully
        for result in results {
            XCTAssertEqual(result.status, .completed, "Concurrent analysis should complete")
        }
    }

    func testPixelBufferInput() async throws {
        // Given: CVPixelBuffer
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
                    let value = UInt8((x % 50 < 25) ? 200 : 50) // Stripe pattern
                    data[offset] = value     // B
                    data[offset + 1] = value // G
                    data[offset + 2] = value // R
                    data[offset + 3] = 255   // A
                }
            }
        }

        // When: Analyzing pixel buffer
        let result = await service.analyze(pixelBuffer: pixelBuffer)

        // Then: Should complete successfully
        XCTAssertEqual(result.status, .completed)
    }

    // MARK: - AC7: False Positive Mitigation

    func testNoFalsePositiveOnNoise() async throws {
        // Given: Random noise image
        guard let image = createNoiseImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should not detect moire (or very low confidence)
        XCTAssertEqual(result.status, .completed)
        if result.detected {
            XCTAssertLessThan(
                result.confidence,
                0.5,
                "Random noise should not have high detection confidence"
            )
        }
    }

    func testNoFalsePositiveOnUniform() async throws {
        // Given: Uniform image
        guard let image = createUniformImage(width: 512, height: 512) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should not detect moire
        XCTAssertEqual(result.status, .completed)
        XCTAssertFalse(result.detected, "Uniform image should not trigger detection")
    }

    func testDistinguishesScreenFromFabric() async throws {
        // Given: Pattern simulating fabric (broad frequency spread)
        // Fabric has less sharp peaks than screens
        guard let image = createTestImage(width: 512, height: 512, generator: { x, y, w, h in
            // Multi-frequency pattern (like fabric weave)
            let f1 = sin(Float(x) * 0.1) * 0.3
            let f2 = sin(Float(y) * 0.15) * 0.3
            let f3 = sin(Float(x + y) * 0.08) * 0.2
            let noise = Float.random(in: -0.1...0.1)
            let combined = (f1 + f2 + f3 + noise + 1) / 2
            return UInt8(max(0, min(255, combined * 255)))
        }) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should have lower confidence or no detection
        // (fabric has broader frequency response, screens have sharp peaks)
        XCTAssertEqual(result.status, .completed)
        // Allow detection but expect lower confidence than true screen patterns
        if result.detected {
            XCTAssertLessThanOrEqual(
                result.confidence,
                0.8,
                "Fabric-like pattern should not have very high confidence"
            )
        }
    }

    // MARK: - Edge Cases

    func testMinimumImageSize() async throws {
        // Given: Minimum valid image size
        guard let image = createUniformImage(
            width: MoireAnalysisConstants.minImageDimension,
            height: MoireAnalysisConstants.minImageDimension
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should handle gracefully
        XCTAssertEqual(result.status, .completed)
    }

    func testTooSmallImage() async throws {
        // Given: Image smaller than minimum
        guard let image = createUniformImage(width: 32, height: 32) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing
        let result = await service.analyze(image: image)

        // Then: Should return unavailable
        XCTAssertEqual(result.status, .unavailable)
    }

    func testDeterministicResults() async throws {
        // Given: Fixed test image
        guard let image = createGridPatternImage(
            width: 256,
            height: 256,
            frequencyX: 100,
            frequencyY: 100
        ) else {
            throw XCTSkip("Could not create test image")
        }

        // When: Analyzing multiple times
        let result1 = await service.analyze(image: image)
        let result2 = await service.analyze(image: image)
        let result3 = await service.analyze(image: image)

        // Then: Detection and confidence should be deterministic
        XCTAssertEqual(result1.detected, result2.detected, "Detection must be deterministic")
        XCTAssertEqual(result2.detected, result3.detected, "Detection must be deterministic")

        XCTAssertEqual(result1.confidence, result2.confidence, accuracy: 0.001,
                       "Confidence must be deterministic")
        XCTAssertEqual(result2.confidence, result3.confidence, accuracy: 0.001,
                       "Confidence must be deterministic")

        XCTAssertEqual(result1.peaks.count, result2.peaks.count, "Peak count must be deterministic")
        XCTAssertEqual(result2.peaks.count, result3.peaks.count, "Peak count must be deterministic")
    }

    // MARK: - Constants Verification

    func testConstantsValid() {
        // Verify constants are sensible
        XCTAssertGreaterThan(MoireAnalysisConstants.minFrequency, 0)
        XCTAssertGreaterThan(MoireAnalysisConstants.maxFrequency, MoireAnalysisConstants.minFrequency)
        XCTAssertGreaterThan(MoireAnalysisConstants.minPeakMagnitude, 0)
        XCTAssertLessThanOrEqual(MoireAnalysisConstants.minPeakMagnitude, 1)
        XCTAssertGreaterThan(MoireAnalysisConstants.noiseFloorMultiplier, 1)
        XCTAssertGreaterThan(MoireAnalysisConstants.minPeaksForDetection, 0)
        XCTAssertGreaterThan(MoireAnalysisConstants.targetFFTSize, 0)
        XCTAssertTrue(isPowerOf2(MoireAnalysisConstants.targetFFTSize), "FFT size should be power of 2")
        XCTAssertGreaterThan(MoireAnalysisConstants.targetTimeMs, 0)
        XCTAssertGreaterThanOrEqual(MoireAnalysisConstants.maxTimeMs, MoireAnalysisConstants.targetTimeMs)
    }

    private func isPowerOf2(_ n: Int) -> Bool {
        n > 0 && (n & (n - 1)) == 0
    }

    // MARK: - FrequencyPeak Tests

    func testFrequencyPeakCodable() throws {
        let peak = FrequencyPeak(
            frequency: 150.5,
            magnitude: 0.75,
            angle: Float.pi / 4,
            prominence: 4.2
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(peak)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FrequencyPeak.self, from: data)

        XCTAssertEqual(decoded.frequency, peak.frequency, accuracy: 0.001)
        XCTAssertEqual(decoded.magnitude, peak.magnitude, accuracy: 0.001)
        XCTAssertEqual(decoded.angle, peak.angle, accuracy: 0.001)
        XCTAssertEqual(decoded.prominence, peak.prominence, accuracy: 0.001)
    }

    func testFrequencyPeakMagnitudeClamped() {
        let peak = FrequencyPeak(frequency: 100, magnitude: 1.5, angle: 0, prominence: 5)
        XCTAssertEqual(peak.magnitude, 1.0, "Magnitude should be clamped to 1.0")

        let negPeak = FrequencyPeak(frequency: 100, magnitude: -0.5, angle: 0, prominence: 5)
        XCTAssertEqual(negPeak.magnitude, 0.0, "Negative magnitude should be clamped to 0.0")
    }

    // MARK: - ScreenType Tests

    func testScreenTypeRawValues() {
        XCTAssertEqual(ScreenType.lcd.rawValue, "lcd")
        XCTAssertEqual(ScreenType.oled.rawValue, "oled")
        XCTAssertEqual(ScreenType.highRefresh.rawValue, "highRefresh")
        XCTAssertEqual(ScreenType.unknown.rawValue, "unknown")
    }

    func testScreenTypeCodable() throws {
        for type in [ScreenType.lcd, .oled, .highRefresh, .unknown] {
            let encoder = JSONEncoder()
            let data = try encoder.encode(type)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ScreenType.self, from: data)

            XCTAssertEqual(decoded, type)
        }
    }
}
