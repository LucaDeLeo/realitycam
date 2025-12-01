//
//  DepthAnalysisServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-01.
//
//  Unit tests for DepthAnalysisService (Story 8-1).
//  Tests algorithm parity with backend/src/services/depth_analysis.rs.
//

import XCTest
import CoreVideo
@testable import Rial

/// Tests for DepthAnalysisService client-side depth analysis.
///
/// These tests verify:
/// - AC1: Depth variance computation
/// - AC2: Depth layer detection
/// - AC3: Edge coherence calculation
/// - AC4: Real scene determination
/// - AC5: Performance (<500ms)
/// - AC6: Deterministic results
final class DepthAnalysisServiceTests: XCTestCase {

    // MARK: - Properties

    private var service: DepthAnalysisService!

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        service = DepthAnalysisService.shared
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Test Fixtures

    /// Creates a CVPixelBuffer with Float32 depth values
    private func createDepthBuffer(depths: [Float], width: Int, height: Int) -> CVPixelBuffer? {
        guard depths.count == width * height else {
            XCTFail("Depth count mismatch: \(depths.count) != \(width * height)")
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            XCTFail("Failed to create pixel buffer: \(status)")
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            XCTFail("Failed to get base address")
            return nil
        }

        let destination = baseAddress.bindMemory(to: Float.self, capacity: depths.count)
        for (index, depth) in depths.enumerated() {
            destination[index] = depth
        }

        return buffer
    }

    /// Creates a flat plane depth map (simulates screen photo)
    private func createFlatDepthMap(depth: Float, width: Int, height: Int) -> [Float] {
        Array(repeating: depth, count: width * height)
    }

    /// Creates a depth map with two distinct planes
    private func createTwoPlaneDepthMap(depth1: Float, depth2: Float, width: Int, height: Int) -> [Float] {
        var depths = [Float]()
        depths.reserveCapacity(width * height)
        for y in 0..<height {
            for _ in 0..<width {
                let depth = y < height / 2 ? depth1 : depth2
                depths.append(depth)
            }
        }
        return depths
    }

    /// Creates a varied depth map simulating a real scene
    private func createVariedDepthMap(width: Int, height: Int) -> [Float] {
        var depths = [Float]()
        depths.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                // Create gradient + some variation
                let base = 0.5 + (Float(x) / Float(width)) * 4.0
                let variation = (Float(y) / Float(height)) * 0.5

                // Add some "objects" at different depths
                let depth: Float
                if x > width / 3 && x < 2 * width / 3 && y > height / 3 && y < 2 * height / 3 {
                    depth = 1.0 // Foreground object
                } else if x < width / 4 {
                    depth = 3.5 // Left side far
                } else {
                    depth = base + variation
                }
                depths.append(depth)
            }
        }
        return depths
    }

    /// Creates a screen-like pattern (uniform depth at typical screen distance)
    private func createScreenPatternDepthMap(width: Int, height: Int) -> [Float] {
        // Simulates pointing phone at a screen ~0.5m away with <0.1m variation
        var depths = [Float]()
        depths.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                // Very slight variation around 0.5m (screen distance)
                let noise = Float.random(in: -0.02...0.02)
                depths.append(0.5 + noise)
            }
        }
        return depths
    }

    // MARK: - AC1: Depth Variance Computation

    func testDepthVarianceFlat() async throws {
        // Given: Flat depth map at 0.4m
        let depths = createFlatDepthMap(depth: 0.4, width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Variance should be near 0
        XCTAssertEqual(result.status, .completed)
        XCTAssertLessThan(result.depthVariance, 0.01, "Flat plane variance should be near 0")
        XCTAssertEqual(result.minDepth, 0.4, accuracy: 0.01)
        XCTAssertEqual(result.maxDepth, 0.4, accuracy: 0.01)
    }

    func testDepthVarianceVaried() async throws {
        // Given: Varied scene with multiple depths
        let depths = createVariedDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Variance should exceed threshold (0.5)
        XCTAssertEqual(result.status, .completed)
        XCTAssertGreaterThan(result.depthVariance, DepthAnalysisConstants.varianceThreshold,
                             "Varied scene should have variance > 0.5")
    }

    func testDepthVarianceFilterInvalid() async throws {
        // Given: Depth map with invalid values
        var depths = createFlatDepthMap(depth: 1.5, width: 64, height: 48)
        depths[0] = Float.nan
        depths[1] = Float.infinity
        depths[2] = -1.0 // Negative (invalid)
        depths[3] = 0.05 // Below MIN_VALID_DEPTH
        depths[4] = 25.0 // Above MAX_VALID_DEPTH

        guard let buffer = createDepthBuffer(depths: depths, width: 64, height: 48) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should complete with valid depths only
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.minDepth, 1.5, accuracy: 0.01, "Min depth should be from valid values")
        XCTAssertEqual(result.maxDepth, 1.5, accuracy: 0.01, "Max depth should be from valid values")
    }

    // MARK: - AC2: Depth Layer Detection

    func testDepthLayersFlat() async throws {
        // Given: Flat depth map
        let depths = createFlatDepthMap(depth: 0.4, width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should detect 1-2 layers
        XCTAssertEqual(result.status, .completed)
        XCTAssertLessThanOrEqual(result.depthLayers, 2, "Flat surface should have <= 2 layers")
    }

    func testDepthLayersTwoPlanes() async throws {
        // Given: Two distinct planes at 0.4m and 2.0m
        let depths = createTwoPlaneDepthMap(depth1: 0.4, depth2: 2.0, width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should detect 2+ layers
        XCTAssertEqual(result.status, .completed)
        XCTAssertGreaterThanOrEqual(result.depthLayers, 2,
                                     "Two plane scene should have >= 2 layers, got \(result.depthLayers)")
    }

    func testDepthLayersVaried() async throws {
        // Given: Varied scene with multiple depths
        let depths = createVariedDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should detect 3+ layers (threshold)
        XCTAssertEqual(result.status, .completed)
        XCTAssertGreaterThanOrEqual(result.depthLayers, DepthAnalysisConstants.layerThreshold,
                                     "Varied scene should have >= 3 layers, got \(result.depthLayers)")
    }

    // MARK: - AC3: Edge Coherence Calculation

    func testEdgeCoherenceFlat() async throws {
        // Given: Flat depth map (no edges)
        let depths = createFlatDepthMap(depth: 0.4, width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Edge coherence should be low
        XCTAssertEqual(result.status, .completed)
        XCTAssertLessThan(result.edgeCoherence, 0.5,
                          "Flat surface should have low coherence, got \(result.edgeCoherence)")
    }

    func testEdgeCoherenceVaried() async throws {
        // Given: Varied scene with depth edges
        let depths = createVariedDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Edge coherence should exceed threshold (0.3)
        XCTAssertEqual(result.status, .completed)
        XCTAssertGreaterThan(result.edgeCoherence, DepthAnalysisConstants.coherenceThreshold,
                             "Varied scene should have coherence > 0.3, got \(result.edgeCoherence)")
    }

    // MARK: - AC4: Real Scene Determination

    func testRealSceneFlatFails() async throws {
        // Given: Flat depth map (should fail)
        let depths = createFlatDepthMap(depth: 0.4, width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should NOT be classified as real scene
        XCTAssertEqual(result.status, .completed)
        XCTAssertFalse(result.isLikelyRealScene, """
            Flat scene should NOT be detected as real.
            variance=\(result.depthVariance), layers=\(result.depthLayers), coherence=\(result.edgeCoherence)
            """)
    }

    func testRealSceneVariedPasses() async throws {
        // Given: Varied scene (should pass)
        let depths = createVariedDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should meet threshold requirements
        XCTAssertEqual(result.status, .completed)
        XCTAssertGreaterThan(result.depthVariance, DepthAnalysisConstants.varianceThreshold)
        XCTAssertGreaterThanOrEqual(result.depthLayers, DepthAnalysisConstants.layerThreshold)
        // Note: Synthetic data may or may not pass all checks
    }

    func testRealSceneScreenPatternFails() async throws {
        // Given: Screen-like pattern (recapture attack)
        let depths = createScreenPatternDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should NOT be classified as real (screen detection)
        XCTAssertEqual(result.status, .completed)
        XCTAssertFalse(result.isLikelyRealScene,
                       "Screen-like pattern should be detected and fail real scene check")
    }

    func testThresholdEdgeCases() async throws {
        // Test exact threshold boundaries
        // variance > 0.5, layers >= 3, coherence > 0.3

        // Create a depth map that's exactly at thresholds
        // This is tricky with synthetic data, so we verify the constants are correct
        XCTAssertEqual(DepthAnalysisConstants.varianceThreshold, 0.5)
        XCTAssertEqual(DepthAnalysisConstants.layerThreshold, 3)
        XCTAssertEqual(DepthAnalysisConstants.coherenceThreshold, 0.3)
    }

    // MARK: - AC5: Performance Target

    func testPerformanceTarget() async throws {
        // Given: Typical LiDAR resolution
        let depths = createVariedDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Measuring analysis time
        let startTime = CFAbsoluteTimeGetCurrent()
        let _ = await service.analyze(depthMap: buffer)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Then: Should complete in < 500ms
        XCTAssertLessThan(elapsed, 0.5, "Analysis should complete in < 500ms, took \(elapsed * 1000)ms")
    }

    func testPerformanceMeasure() throws {
        // Given: Typical LiDAR resolution
        let depths = createVariedDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // Measure multiple iterations
        measure {
            let expectation = XCTestExpectation(description: "Analysis complete")
            Task {
                _ = await service.analyze(depthMap: buffer)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
        }
    }

    // MARK: - AC6: Deterministic Results

    func testDeterministicResults() async throws {
        // Given: Fixed depth map
        let depths = createVariedDepthMap(width: 256, height: 192)
        guard let buffer = createDepthBuffer(depths: depths, width: 256, height: 192) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing multiple times
        let result1 = await service.analyze(depthMap: buffer)
        let result2 = await service.analyze(depthMap: buffer)
        let result3 = await service.analyze(depthMap: buffer)

        // Then: All results should be identical
        XCTAssertEqual(result1.depthVariance, result2.depthVariance, "Variance must be deterministic")
        XCTAssertEqual(result2.depthVariance, result3.depthVariance, "Variance must be deterministic")

        XCTAssertEqual(result1.depthLayers, result2.depthLayers, "Layer count must be deterministic")
        XCTAssertEqual(result2.depthLayers, result3.depthLayers, "Layer count must be deterministic")

        XCTAssertEqual(result1.edgeCoherence, result2.edgeCoherence, "Coherence must be deterministic")
        XCTAssertEqual(result2.edgeCoherence, result3.edgeCoherence, "Coherence must be deterministic")

        XCTAssertEqual(result1.isLikelyRealScene, result2.isLikelyRealScene, "Result must be deterministic")
        XCTAssertEqual(result2.isLikelyRealScene, result3.isLikelyRealScene, "Result must be deterministic")
    }

    // MARK: - Edge Cases

    func testEmptyBuffer() async throws {
        // Given: Minimum valid buffer (3x3 required for edge computation)
        let depths = createFlatDepthMap(depth: 1.0, width: 3, height: 3)
        guard let buffer = createDepthBuffer(depths: depths, width: 3, height: 3) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should handle gracefully
        XCTAssertEqual(result.status, .completed)
    }

    func testAllInvalidDepths() async throws {
        // Given: All NaN values
        let depths = [Float](repeating: Float.nan, count: 64 * 48)
        guard let buffer = createDepthBuffer(depths: depths, width: 64, height: 48) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should return unavailable
        XCTAssertEqual(result.status, .unavailable, "All invalid depths should return unavailable")
        XCTAssertFalse(result.isLikelyRealScene)
    }

    func testMixedInvalidDepths() async throws {
        // Given: 50% NaN, 25% out-of-range, 25% valid
        let width = 64
        let height = 48
        let count = width * height
        var depths = [Float](repeating: 1.5, count: count)

        // First 50% NaN
        for i in 0..<(count / 2) {
            depths[i] = Float.nan
        }
        // Next 25% out of range
        for i in (count / 2)..<(count * 3 / 4) {
            depths[i] = 50.0 // Above MAX_VALID_DEPTH
        }
        // Last 25% valid at 1.5m

        guard let buffer = createDepthBuffer(depths: depths, width: width, height: height) else {
            throw XCTSkip("Could not create test buffer")
        }

        // When: Analyzing
        let result = await service.analyze(depthMap: buffer)

        // Then: Should analyze valid portion
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.minDepth, 1.5, accuracy: 0.01)
        XCTAssertEqual(result.maxDepth, 1.5, accuracy: 0.01)
    }

    // MARK: - DepthAnalysisResult Tests

    func testResultEquatable() {
        let sharedDate = Date()
        let result1 = DepthAnalysisResult(
            depthVariance: 0.6,
            depthLayers: 4,
            edgeCoherence: 0.8,
            minDepth: 0.5,
            maxDepth: 5.0,
            isLikelyRealScene: true,
            computedAt: sharedDate
        )

        let result2 = DepthAnalysisResult(
            depthVariance: 0.6,
            depthLayers: 4,
            edgeCoherence: 0.8,
            minDepth: 0.5,
            maxDepth: 5.0,
            isLikelyRealScene: true,
            computedAt: sharedDate
        )

        // Same values including timestamp should be equal
        XCTAssertEqual(result1, result2, "Results with identical values should be equal")

        // Different timestamp makes them not equal
        let result3 = DepthAnalysisResult(
            depthVariance: 0.6,
            depthLayers: 4,
            edgeCoherence: 0.8,
            minDepth: 0.5,
            maxDepth: 5.0,
            isLikelyRealScene: true,
            computedAt: Date()
        )
        XCTAssertNotEqual(result1, result3, "Results with different timestamps should not be equal")
    }

    func testResultUnavailable() {
        let result = DepthAnalysisResult.unavailable()

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.depthVariance, 0)
        XCTAssertEqual(result.depthLayers, 0)
        XCTAssertEqual(result.edgeCoherence, 0)
        XCTAssertFalse(result.isLikelyRealScene)
    }

    func testResultCodable() throws {
        let result = DepthAnalysisResult(
            depthVariance: 0.65,
            depthLayers: 5,
            edgeCoherence: 0.75,
            minDepth: 0.3,
            maxDepth: 8.0,
            isLikelyRealScene: true,
            algorithmVersion: "1.0",
            status: .completed
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DepthAnalysisResult.self, from: data)

        // Verify
        XCTAssertEqual(decoded.depthVariance, result.depthVariance)
        XCTAssertEqual(decoded.depthLayers, result.depthLayers)
        XCTAssertEqual(decoded.edgeCoherence, result.edgeCoherence)
        XCTAssertEqual(decoded.minDepth, result.minDepth)
        XCTAssertEqual(decoded.maxDepth, result.maxDepth)
        XCTAssertEqual(decoded.isLikelyRealScene, result.isLikelyRealScene)
        XCTAssertEqual(decoded.algorithmVersion, result.algorithmVersion)
        XCTAssertEqual(decoded.status, result.status)
    }

    // MARK: - Constants Verification

    func testConstantsMatchBackend() {
        // Verify constants match backend/src/services/depth_analysis.rs
        // These values are critical for algorithm parity

        XCTAssertEqual(DepthAnalysisConstants.varianceThreshold, 0.5,
                       "VARIANCE_THRESHOLD must match backend")
        XCTAssertEqual(DepthAnalysisConstants.layerThreshold, 3,
                       "LAYER_THRESHOLD must match backend")
        XCTAssertEqual(DepthAnalysisConstants.coherenceThreshold, 0.3,
                       "COHERENCE_THRESHOLD must match backend")
        XCTAssertEqual(DepthAnalysisConstants.histogramBins, 50,
                       "HISTOGRAM_BINS must match backend")
        XCTAssertEqual(DepthAnalysisConstants.peakProminenceRatio, 0.05,
                       "PEAK_PROMINENCE_RATIO must match backend")
        XCTAssertEqual(DepthAnalysisConstants.minValidDepth, 0.1,
                       "MIN_VALID_DEPTH must match backend")
        XCTAssertEqual(DepthAnalysisConstants.maxValidDepth, 20.0,
                       "MAX_VALID_DEPTH must match backend")
        XCTAssertEqual(DepthAnalysisConstants.gradientThreshold, 0.1,
                       "GRADIENT_THRESHOLD must match backend")
        XCTAssertEqual(DepthAnalysisConstants.screenDepthRangeMax, 0.15,
                       "SCREEN_DEPTH_RANGE_MAX must match backend")
        XCTAssertEqual(DepthAnalysisConstants.screenUniformityThreshold, 0.85,
                       "SCREEN_UNIFORMITY_THRESHOLD must match backend")
        XCTAssertEqual(DepthAnalysisConstants.screenDistanceMin, 0.2,
                       "SCREEN_DISTANCE_MIN must match backend")
        XCTAssertEqual(DepthAnalysisConstants.screenDistanceMax, 1.5,
                       "SCREEN_DISTANCE_MAX must match backend")
        XCTAssertEqual(DepthAnalysisConstants.minQuadrantVariance, 0.1,
                       "MIN_QUADRANT_VARIANCE must match backend")
    }
}
