//
//  DetectionOrchestratorTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Unit tests for DetectionOrchestrator (Story 9-6).
//

import XCTest
import CoreGraphics
@testable import Rial

final class DetectionOrchestratorTests: XCTestCase {

    // MARK: - Properties

    var orchestrator: DetectionOrchestrator!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        orchestrator = DetectionOrchestrator.shared
    }

    // MARK: - Singleton Tests

    func testSharedInstance() {
        let instance1 = DetectionOrchestrator.shared
        let instance2 = DetectionOrchestrator.shared

        // Both should reference the same instance
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - CGImage Detection Tests

    func testRunAllDetectionsWithValidImage() async {
        // Create a simple test image
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Should return results (may or may not have detection data depending on image)
        XCTAssertTrue(results.totalProcessingTimeMs >= 0)
        XCTAssertNotNil(results.computedAt)
    }

    func testRunAllDetectionsWithSmallImage() async {
        // Create a small test image (may cause some detections to fail)
        guard let testImage = createTestImage(width: 64, height: 64) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Should handle gracefully even with small images
        XCTAssertTrue(results.totalProcessingTimeMs >= 0)
    }

    // MARK: - JPEG Data Detection Tests

    func testRunAllDetectionsWithValidJPEGData() async {
        // Create test JPEG data
        guard let jpegData = createTestJPEGData() else {
            XCTFail("Failed to create test JPEG data")
            return
        }

        let results = await orchestrator.runAllDetections(jpegData: jpegData)

        // Should return results
        XCTAssertTrue(results.totalProcessingTimeMs >= 0)
    }

    func testRunAllDetectionsWithInvalidJPEGData() async {
        // Create invalid data
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])

        let results = await orchestrator.runAllDetections(jpegData: invalidData)

        // Should return unavailable results
        XCTAssertNotNil(results.moire)
        XCTAssertEqual(results.moire?.status, .unavailable)
    }

    // MARK: - Parallel Execution Tests

    func testParallelExecutionPerformance() async {
        // Create a test image
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = await orchestrator.runAllDetections(image: testImage)
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime

        // Total time should be reasonably close to the longest individual detection
        // since they run in parallel (not sum of all three)
        // Allow generous margin for test environment variability
        XCTAssertLessThan(totalTime, 2.0) // Should complete in under 2 seconds

        // Processing time should be tracked
        XCTAssertGreaterThan(results.totalProcessingTimeMs, 0)
    }

    // MARK: - Aggregation Tests

    func testAggregationIncluded() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Aggregated confidence should be computed
        XCTAssertNotNil(results.aggregatedConfidence)

        // If we have results, confidence should be valid
        if results.hasAnyResults {
            XCTAssertNotNil(results.confidenceLevel)
            XCTAssertNotNil(results.overallConfidence)
            if let confidence = results.overallConfidence {
                XCTAssertGreaterThanOrEqual(confidence, 0.0)
                XCTAssertLessThanOrEqual(confidence, 1.0)
            }
        }
    }

    func testCrossValidationIncluded() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Cross-validation should be included (enableEnhancedCrossValidation=true)
        // Note: May be nil if no methods completed successfully
        if results.hasAnyResults {
            XCTAssertNotNil(results.crossValidation)
        }
    }

    // MARK: - Graceful Degradation Tests

    func testGracefulDegradationWithPartialFailures() async {
        // Use a very small image that may cause some detections to fail
        guard let testImage = createTestImage(width: 32, height: 32) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Should not crash, should return results (even if partial/unavailable)
        XCTAssertTrue(results.totalProcessingTimeMs >= 0)

        // If any results available, aggregation should still work
        if results.hasAnyResults {
            XCTAssertNotNil(results.aggregatedConfidence)
        }
    }

    // MARK: - Methods Used Tracking Tests

    func testMethodsUsedTracking() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Methods used should match available results
        let methodsUsed = results.methodsUsed

        if results.moire != nil {
            XCTAssertTrue(methodsUsed.contains("moire"))
        }
        if results.texture != nil {
            XCTAssertTrue(methodsUsed.contains("texture"))
        }
        if results.artifacts != nil {
            XCTAssertTrue(methodsUsed.contains("artifacts"))
        }

        XCTAssertEqual(methodsUsed.count, results.availableMethodCount)
    }

    // MARK: - Performance Tests

    func testDetectionPerformance() async {
        guard let testImage = createTestImage(width: 512, height: 512) else {
            XCTFail("Failed to create test image")
            return
        }

        // Warm up
        _ = await orchestrator.runAllDetections(image: testImage)

        // Measure
        var times: [TimeInterval] = []
        for _ in 0..<3 {
            let startTime = CFAbsoluteTimeGetCurrent()
            _ = await orchestrator.runAllDetections(image: testImage)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            times.append(elapsed)
        }

        let averageTime = times.reduce(0, +) / Double(times.count)

        // Should complete within reasonable time for CI/test environment
        // Target is 200ms but CI environments can be slower, allow 5x margin
        XCTAssertLessThan(averageTime, 3.0, "Average detection time \(averageTime)s exceeds 3s")
    }

    // MARK: - Helpers

    /// Creates a test CGImage with specified dimensions.
    private func createTestImage(width: Int, height: Int) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        // Fill with a gradient pattern for more realistic detection results
        for y in 0..<height {
            for x in 0..<width {
                let red = CGFloat(x) / CGFloat(width)
                let green = CGFloat(y) / CGFloat(height)
                let blue = CGFloat((x + y) % 256) / 255.0
                context.setFillColor(red: red, green: green, blue: blue, alpha: 1.0)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        return context.makeImage()
    }

    /// Creates test JPEG data.
    private func createTestJPEGData() -> Data? {
        guard let image = createTestImage(width: 256, height: 256) else {
            return nil
        }

        #if os(iOS)
        let uiImage = UIImage(cgImage: image)
        return uiImage.jpegData(compressionQuality: 0.8)
        #else
        return nil
        #endif
    }
}

// MARK: - Integration Tests

extension DetectionOrchestratorTests {

    func testIntegrationWithDetectionResults() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Results should be usable in CaptureData
        let captureData = CaptureData(
            jpeg: Data(),
            depth: Data(),
            metadata: CaptureMetadata(
                capturedAt: Date(),
                deviceModel: "Test",
                photoHash: "abc123",
                location: nil,
                depthMapDimensions: DepthDimensions(width: 256, height: 192)
            ),
            detectionResults: results
        )

        XCTAssertNotNil(captureData.detectionResults)
        XCTAssertEqual(captureData.detectionResults?.totalProcessingTimeMs, results.totalProcessingTimeMs)
    }

    func testResultsEncodableForUpload() async throws {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Results should be encodable to JSON for upload
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(results)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should contain expected keys
        XCTAssertTrue(jsonString.contains("total_processing_time_ms"))
        XCTAssertTrue(jsonString.contains("computed_at"))

        // Should be decodable
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DetectionResults.self, from: data)

        XCTAssertEqual(decoded.totalProcessingTimeMs, results.totalProcessingTimeMs)
    }
}
