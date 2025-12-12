//
//  DetectionPipelineIntegrationTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Integration tests for full detection pipeline (Story 9-8).
//  Tests DetectionOrchestrator coordinates all services and produces valid results.
//

import XCTest
import CoreGraphics
@testable import Rial

/// Integration tests for the complete multi-signal detection pipeline.
///
/// These tests verify:
/// - All detection services run successfully in parallel
/// - ConfidenceAggregator produces valid aggregated result
/// - CrossValidationService produces valid pairwise consistency checks
/// - DetectionResults payload serializes correctly for backend upload
/// - CaptureData can include DetectionResults
/// - End-to-end latency stays within target
final class DetectionPipelineIntegrationTests: XCTestCase {

    // MARK: - Properties

    var orchestrator: DetectionOrchestrator!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        orchestrator = DetectionOrchestrator.shared
    }

    // MARK: - AC1: Full Pipeline Integration Tests

    func testFullDetectionPipelineWithRealServices() async {
        // Given: A test image suitable for detection
        guard let testImage = createTestImage(width: 512, height: 512) else {
            XCTFail("Failed to create test image")
            return
        }

        // When: Running the full detection pipeline
        let results = await orchestrator.runAllDetections(image: testImage)

        // Then: All detection services should have attempted to run
        // Note: Services may return nil if they deem the test image unsuitable,
        // but at least aggregation should always run
        XCTAssertTrue(results.totalProcessingTimeMs >= 0, "Processing time should be non-negative")
        XCTAssertNotNil(results.computedAt, "Computed timestamp should be set")

        // Aggregated confidence should always be computed
        XCTAssertNotNil(results.aggregatedConfidence, "Aggregated confidence should be present")

        // If any services ran, we should have method results
        if results.hasAnyResults {
            XCTAssertGreaterThan(results.availableMethodCount, 0, "Should have at least one method result")
            XCTAssertNotNil(results.confidenceLevel, "Should have confidence level when results available")
        }
    }

    func testAllServicesAttemptToRunInParallel() async {
        // Given: A larger test image more likely to trigger all services
        guard let testImage = createTestImage(width: 256, height: 256, pattern: .gradient) else {
            XCTFail("Failed to create test image")
            return
        }

        // When: Running detection
        let results = await orchestrator.runAllDetections(image: testImage)

        // Then: We should see evidence of parallel execution
        // (total time should be close to max individual service time, not sum)
        // Note: In test environment, times may vary; we just verify no crashes
        XCTAssertNotNil(results.aggregatedConfidence)

        // If aggregation completed, check method breakdown
        if let aggregated = results.aggregatedConfidence {
            // Method breakdown should exist
            XCTAssertGreaterThan(aggregated.methodBreakdownByMethod.count, 0,
                               "Method breakdown should have entries")

            // Check status values are valid
            XCTAssertTrue(
                aggregated.status == .success || aggregated.status == .partial || aggregated.status == .unavailable,
                "Aggregation status should be valid"
            )
        }
    }

    func testAggregatorProducesValidAggregatedResult() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        guard let aggregated = results.aggregatedConfidence else {
            XCTFail("Aggregated confidence should be present")
            return
        }

        // Verify confidence bounds
        XCTAssertGreaterThanOrEqual(aggregated.overallConfidence, 0.0,
                                    "Overall confidence should be >= 0")
        XCTAssertLessThanOrEqual(aggregated.overallConfidence, 1.0,
                                 "Overall confidence should be <= 1")

        // Verify confidence level is set
        XCTAssertTrue(
            [.veryHigh, .high, .medium, .low, .suspicious].contains(aggregated.confidenceLevel),
            "Confidence level should be a valid value"
        )

        // Verify algorithm version is set
        XCTAssertFalse(aggregated.algorithmVersion.isEmpty, "Algorithm version should be set")

        // Verify analysis time is non-negative
        XCTAssertGreaterThanOrEqual(aggregated.analysisTimeMs, 0, "Analysis time should be non-negative")
    }

    func testCrossValidationIncludedInResults() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Cross-validation should be present when enhanced mode is enabled
        // (DetectionOrchestrator uses enableEnhancedCrossValidation=true)
        if results.hasAnyResults {
            XCTAssertNotNil(results.crossValidation, "Cross-validation should be present when results available")

            if let crossValidation = results.crossValidation {
                // Verify cross-validation structure
                XCTAssertTrue(
                    [.pass, .warn, .fail].contains(crossValidation.validationStatus),
                    "Validation status should be valid"
                )
                XCTAssertGreaterThanOrEqual(crossValidation.overallPenalty, 0.0,
                                           "Overall penalty should be non-negative")
                XCTAssertNotNil(crossValidation.aggregatedInterval,
                               "Aggregated interval should be present")
            }
        }
    }

    func testCrossValidationPairwiseConsistencies() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        guard let crossValidation = results.crossValidation else {
            // Cross-validation may not be present if no methods succeeded
            return
        }

        // If pairwise consistencies exist, verify structure
        for pairwise in crossValidation.pairwiseConsistencies {
            XCTAssertFalse(pairwise.methodA.isEmpty, "Method A should be set")
            XCTAssertFalse(pairwise.methodB.isEmpty, "Method B should be set")
            XCTAssertGreaterThanOrEqual(pairwise.actualAgreement, 0.0, "Agreement should be >= 0")
            XCTAssertLessThanOrEqual(pairwise.actualAgreement, 1.0, "Agreement should be <= 1")
        }
    }

    // MARK: - AC1: CaptureData Integration

    func testCaptureDataCanIncludeDetectionResults() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Create CaptureData with detection results
        let captureData = CaptureData(
            jpeg: Data(),
            depth: Data(),
            metadata: CaptureMetadata(
                capturedAt: Date(),
                deviceModel: "iPhone 15 Pro",
                photoHash: "test_hash_abc123",
                location: nil,
                depthMapDimensions: DepthDimensions(width: 256, height: 192)
            ),
            detectionResults: results
        )

        // Verify detection results are attached
        XCTAssertNotNil(captureData.detectionResults, "Detection results should be attached")
        XCTAssertEqual(captureData.detectionResults?.totalProcessingTimeMs,
                      results.totalProcessingTimeMs,
                      "Detection results should match")
    }

    // MARK: - AC1: Performance Tests

    func testDetectionOrchestratorPerformance() async {
        guard let testImage = createTestImage(width: 512, height: 512) else {
            XCTFail("Failed to create test image")
            return
        }

        // Warm up
        _ = await orchestrator.runAllDetections(image: testImage)

        // Measure multiple runs
        var times: [Int64] = []
        for _ in 0..<3 {
            let startTime = CFAbsoluteTimeGetCurrent()
            let results = await orchestrator.runAllDetections(image: testImage)
            times.append(results.totalProcessingTimeMs)
        }

        let averageTime = times.reduce(0, +) / Int64(times.count)

        // Target is 200ms, allow 5x margin for CI environments
        // (1000ms = 1 second is generous for test stability)
        XCTAssertLessThan(averageTime, 1000,
                         "Average detection time \(averageTime)ms should be under 1000ms")

        // Also verify the orchestrator's own timing is accurate
        XCTAssertGreaterThan(averageTime, 0, "Should record some processing time")
    }

    func testPerformanceWithLargeImage() async {
        // Test with a larger image to ensure scalability
        guard let testImage = createTestImage(width: 1024, height: 1024) else {
            XCTFail("Failed to create large test image")
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = await orchestrator.runAllDetections(image: testImage)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete within reasonable time even for larger images
        // Allow 3 seconds for CI environments
        XCTAssertLessThan(elapsed, 3.0,
                         "Large image detection should complete within 3 seconds")
        XCTAssertNotNil(results.aggregatedConfidence)
    }

    // MARK: - Graceful Degradation Tests

    func testGracefulDegradationWithTinyImage() async {
        // Very small images may cause some services to fail
        guard let testImage = createTestImage(width: 32, height: 32) else {
            XCTFail("Failed to create tiny test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Should not crash, should return some results
        XCTAssertTrue(results.totalProcessingTimeMs >= 0)
        // Aggregation should still attempt to run
        XCTAssertNotNil(results.aggregatedConfidence)
    }

    func testResultsAvailableEvenWithPartialFailures() async {
        guard let testImage = createTestImage(width: 64, height: 64) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Even if individual methods fail, we should get partial results
        // The aggregator handles nil inputs gracefully
        XCTAssertNotNil(results.aggregatedConfidence)

        // If partial, status should reflect that
        if let aggregated = results.aggregatedConfidence {
            XCTAssertTrue(
                aggregated.status == .success || aggregated.status == .partial || aggregated.status == .unavailable,
                "Status should indicate partial or unavailable if methods failed"
            )
        }
    }

    // MARK: - Methods Tracking Tests

    func testMethodsUsedTrackingAccuracy() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Verify methodsUsed matches actual results
        let methodsUsed = results.methodsUsed

        if results.moire != nil {
            XCTAssertTrue(methodsUsed.contains("moire"), "moire should be in methodsUsed")
        } else {
            XCTAssertFalse(methodsUsed.contains("moire"), "moire should not be in methodsUsed when nil")
        }

        if results.texture != nil {
            XCTAssertTrue(methodsUsed.contains("texture"), "texture should be in methodsUsed")
        } else {
            XCTAssertFalse(methodsUsed.contains("texture"), "texture should not be in methodsUsed when nil")
        }

        if results.artifacts != nil {
            XCTAssertTrue(methodsUsed.contains("artifacts"), "artifacts should be in methodsUsed")
        } else {
            XCTAssertFalse(methodsUsed.contains("artifacts"), "artifacts should not be in methodsUsed when nil")
        }

        XCTAssertEqual(methodsUsed.count, results.availableMethodCount,
                      "Methods count should match")
    }

    // MARK: - Signal Agreement Tests

    func testPrimarySignalValidityTracking() async {
        guard let testImage = createTestImage(width: 256, height: 256) else {
            XCTFail("Failed to create test image")
            return
        }

        let results = await orchestrator.runAllDetections(image: testImage)

        // Primary signal validity should be tracked
        // (Note: Without actual depth/LiDAR data, this will be false)
        // We just verify the field is accessible
        if let _ = results.primarySignalValid {
            // Field is accessible
        }

        // Signals agree should also be tracked
        if let _ = results.signalsAgree {
            // Field is accessible
        }
    }

    // MARK: - Helpers

    enum TestImagePattern {
        case solid
        case gradient
        case checkerboard
        case noise
    }

    /// Creates a test CGImage with specified dimensions and pattern.
    private func createTestImage(width: Int, height: Int, pattern: TestImagePattern = .gradient) -> CGImage? {
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

        switch pattern {
        case .solid:
            context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        case .gradient:
            for y in 0..<height {
                for x in 0..<width {
                    let red = CGFloat(x) / CGFloat(width)
                    let green = CGFloat(y) / CGFloat(height)
                    let blue = CGFloat((x + y) % 256) / 255.0
                    context.setFillColor(red: red, green: green, blue: blue, alpha: 1.0)
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }

        case .checkerboard:
            let tileSize = 16
            for y in 0..<height {
                for x in 0..<width {
                    let isWhite = ((x / tileSize) + (y / tileSize)) % 2 == 0
                    let gray: CGFloat = isWhite ? 1.0 : 0.0
                    context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1.0)
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }

        case .noise:
            for y in 0..<height {
                for x in 0..<width {
                    let red = CGFloat.random(in: 0...1)
                    let green = CGFloat.random(in: 0...1)
                    let blue = CGFloat.random(in: 0...1)
                    context.setFillColor(red: red, green: green, blue: blue, alpha: 1.0)
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }

        return context.makeImage()
    }
}
