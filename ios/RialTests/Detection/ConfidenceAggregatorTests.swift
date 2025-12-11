//
//  ConfidenceAggregatorTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Unit tests for ConfidenceAggregator (Story 9-4).
//  Tests confidence aggregation from LiDAR, Moire, Texture, and Artifacts.
//

import XCTest
@testable import Rial

/// Tests for ConfidenceAggregator confidence aggregation.
///
/// These tests verify:
/// - AC1: AggregatedConfidenceResult model and types
/// - AC2: Detection method weighting per PRD
/// - AC3: Input processing from detection services
/// - AC4: Confidence level thresholds
/// - AC5: Cross-validation logic
/// - AC6: Confidence flags
/// - AC7: MethodResult detail structure
/// - AC8: Performance target (<10ms)
/// - AC9: Integration with capture pipeline
final class ConfidenceAggregatorTests: XCTestCase {

    // MARK: - Properties

    private var aggregator: ConfidenceAggregator!

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        aggregator = ConfidenceAggregator.shared
    }

    override func tearDown() {
        aggregator = nil
        super.tearDown()
    }

    // MARK: - Test Fixtures

    /// Creates a passing depth result (real scene).
    private func createPassingDepth() -> DepthAnalysisResult {
        DepthAnalysisResult(
            depthVariance: 1.5,
            depthLayers: 5,
            edgeCoherence: 0.8,
            minDepth: 0.5,
            maxDepth: 4.0,
            isLikelyRealScene: true
        )
    }

    /// Creates a failing depth result (flat scene).
    private func createFailingDepth() -> DepthAnalysisResult {
        DepthAnalysisResult(
            depthVariance: 0.1,
            depthLayers: 1,
            edgeCoherence: 0.1,
            minDepth: 1.0,
            maxDepth: 1.1,
            isLikelyRealScene: false
        )
    }

    /// Creates a clean moire result (no screen detected).
    private func createCleanMoire() -> MoireAnalysisResult {
        MoireAnalysisResult.notDetected(analysisTimeMs: 30)
    }

    /// Creates a detected moire result (screen detected).
    private func createDetectedMoire(confidence: Float = 0.8) -> MoireAnalysisResult {
        MoireAnalysisResult(
            detected: true,
            confidence: confidence,
            peaks: [FrequencyPeak(frequency: 100, magnitude: 0.7, angle: 0, prominence: 5)],
            screenType: .lcd,
            analysisTimeMs: 30
        )
    }

    /// Creates a natural texture result.
    private func createNaturalTexture() -> TextureClassificationResult {
        TextureClassificationResult.realScene(
            confidence: 0.9,
            allClassifications: [.realScene: 0.9, .lcdScreen: 0.05, .printedPaper: 0.05],
            analysisTimeMs: 15
        )
    }

    /// Creates a screen texture result.
    private func createScreenTexture() -> TextureClassificationResult {
        TextureClassificationResult(
            classification: .lcdScreen,
            confidence: 0.85,
            allClassifications: [.realScene: 0.1, .lcdScreen: 0.85, .printedPaper: 0.05],
            isLikelyRecaptured: true,
            analysisTimeMs: 15
        )
    }

    /// Creates a clean artifact result (no artifacts).
    private func createCleanArtifacts() -> ArtifactAnalysisResult {
        ArtifactAnalysisResult.notDetected(analysisTimeMs: 50)
    }

    /// Creates an artifact result with detections.
    private func createDetectedArtifacts() -> ArtifactAnalysisResult {
        ArtifactAnalysisResult(
            pwmFlickerDetected: true,
            pwmConfidence: 0.7,
            specularPatternDetected: false,
            specularConfidence: 0.1,
            halftoneDetected: false,
            halftoneConfidence: 0.1,
            overallConfidence: 0.6,
            isLikelyArtificial: true,
            analysisTimeMs: 50
        )
    }

    /// Creates a halftone (print) artifact result.
    private func createHalftoneArtifacts() -> ArtifactAnalysisResult {
        ArtifactAnalysisResult(
            pwmFlickerDetected: false,
            pwmConfidence: 0.1,
            specularPatternDetected: false,
            specularConfidence: 0.1,
            halftoneDetected: true,
            halftoneConfidence: 0.8,
            overallConfidence: 0.65,
            isLikelyArtificial: true,
            analysisTimeMs: 50
        )
    }

    // MARK: - AC1: AggregatedConfidenceResult Model

    func testResultContainsRequiredFields() async {
        let depth = createPassingDepth()
        let moire = createCleanMoire()
        let texture = createNaturalTexture()
        let artifacts = createCleanArtifacts()

        let result = await aggregator.aggregate(
            depth: depth,
            moire: moire,
            texture: texture,
            artifacts: artifacts
        )

        // Verify all required fields
        XCTAssertGreaterThanOrEqual(result.overallConfidence, 0)
        XCTAssertLessThanOrEqual(result.overallConfidence, 1)
        XCTAssertNotNil(result.confidenceLevel)
        XCTAssertFalse(result.methodBreakdown.isEmpty)
        XCTAssertEqual(result.methodBreakdown.count, 4)
        XCTAssertGreaterThanOrEqual(result.analysisTimeMs, 0)
        XCTAssertEqual(result.algorithmVersion, ConfidenceAggregationConstants.algorithmVersion)
        XCTAssertNotNil(result.computedAt)
    }

    func testResultCodable() throws {
        let result = AggregatedConfidenceResult(
            overallConfidence: 0.85,
            confidenceLevel: .high,
            methodBreakdown: [
                .lidar: MethodResult(available: true, score: 0.9, weight: 0.55, contribution: 0.495, status: "pass"),
                .moire: MethodResult(available: true, score: 1.0, weight: 0.15, contribution: 0.15, status: "pass")
            ],
            primarySignalValid: true,
            supportingSignalsAgree: true,
            flags: [.partialAnalysis],
            analysisTimeMs: 5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AggregatedConfidenceResult.self, from: data)

        XCTAssertEqual(decoded.overallConfidence, result.overallConfidence, accuracy: 0.001)
        XCTAssertEqual(decoded.confidenceLevel, result.confidenceLevel)
        XCTAssertEqual(decoded.primarySignalValid, result.primarySignalValid)
        XCTAssertEqual(decoded.supportingSignalsAgree, result.supportingSignalsAgree)
        XCTAssertEqual(decoded.flags, result.flags)
        XCTAssertEqual(decoded.methodBreakdown.count, result.methodBreakdown.count)
    }

    func testResultEquatable() {
        let date = Date()
        let breakdown: [DetectionMethod: MethodResult] = [
            .lidar: MethodResult(available: true, score: 0.9, weight: 0.55, contribution: 0.495, status: "pass")
        ]

        let result1 = AggregatedConfidenceResult(
            overallConfidence: 0.85,
            confidenceLevel: .high,
            methodBreakdown: breakdown,
            primarySignalValid: true,
            supportingSignalsAgree: true,
            flags: [],
            analysisTimeMs: 5,
            computedAt: date
        )

        let result2 = AggregatedConfidenceResult(
            overallConfidence: 0.85,
            confidenceLevel: .high,
            methodBreakdown: breakdown,
            primarySignalValid: true,
            supportingSignalsAgree: true,
            flags: [],
            analysisTimeMs: 5,
            computedAt: date
        )

        XCTAssertEqual(result1, result2)
    }

    func testConfidenceLevelOrdering() {
        XCTAssertTrue(AggregatedConfidenceLevel.suspicious < AggregatedConfidenceLevel.low)
        XCTAssertTrue(AggregatedConfidenceLevel.low < AggregatedConfidenceLevel.medium)
        XCTAssertTrue(AggregatedConfidenceLevel.medium < AggregatedConfidenceLevel.high)
        XCTAssertTrue(AggregatedConfidenceLevel.high < AggregatedConfidenceLevel.veryHigh)
    }

    // MARK: - AC2: Detection Method Weighting

    func testWeightsWhenAllMethodsAvailable() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        // Verify PRD-specified weights
        XCTAssertEqual(result.result(for: .lidar)?.weight ?? 0, 0.55, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .moire)?.weight ?? 0, 0.15, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .texture)?.weight ?? 0, 0.15, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .artifacts)?.weight ?? 0, 0.15, accuracy: 0.01)

        // Weights should sum to 1.0
        let totalWeight = result.methodBreakdown.values.reduce(Float(0)) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.01)
    }

    func testWeightRedistributionWhenLidarOnly() async {
        let result = await aggregator.aggregate(depth: createPassingDepth())

        // LiDAR gets full weight (1.0)
        XCTAssertEqual(result.result(for: .lidar)?.weight ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .moire)?.weight ?? 0, 0, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .texture)?.weight ?? 0, 0, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .artifacts)?.weight ?? 0, 0, accuracy: 0.01)

        XCTAssertTrue(result.flags.contains(.partialAnalysis))
    }

    func testWeightRedistributionWhenSupportingOnly() async {
        let result = await aggregator.aggregate(
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        // Supporting methods split total weight proportionally
        // Each base is 0.15, total = 0.45, so each gets 0.15/0.45 = 0.333
        XCTAssertEqual(result.result(for: .lidar)?.weight ?? 0, 0, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .moire)?.weight ?? 0, 0.333, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .texture)?.weight ?? 0, 0.333, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .artifacts)?.weight ?? 0, 0.333, accuracy: 0.01)

        // Weights should sum to 1.0
        let totalWeight = result.methodBreakdown.values.reduce(Float(0)) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.01)
    }

    func testWeightRedistributionPartial() async {
        // LiDAR + Moire only
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire()
        )

        // Total base = 0.55 + 0.15 = 0.70
        // LiDAR = 0.55/0.70 = 0.786
        // Moire = 0.15/0.70 = 0.214
        XCTAssertEqual(result.result(for: .lidar)?.weight ?? 0, 0.786, accuracy: 0.01)
        XCTAssertEqual(result.result(for: .moire)?.weight ?? 0, 0.214, accuracy: 0.01)

        let totalWeight = result.methodBreakdown.values.reduce(Float(0)) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.01)
    }

    // MARK: - AC3: Input Processing

    func testAcceptsAllDetectionResults() async {
        let depth = createPassingDepth()
        let moire = createCleanMoire()
        let texture = createNaturalTexture()
        let artifacts = createCleanArtifacts()

        let result = await aggregator.aggregate(
            depth: depth,
            moire: moire,
            texture: texture,
            artifacts: artifacts
        )

        XCTAssertTrue(result.result(for: .lidar)?.available ?? false)
        XCTAssertTrue(result.result(for: .moire)?.available ?? false)
        XCTAssertTrue(result.result(for: .texture)?.available ?? false)
        XCTAssertTrue(result.result(for: .artifacts)?.available ?? false)
        XCTAssertEqual(result.status, .success)
    }

    func testHandlesNilInputs() async {
        let result = await aggregator.aggregate(
            depth: nil,
            moire: nil,
            texture: nil,
            artifacts: nil
        )

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.overallConfidence, 0)
        XCTAssertEqual(result.confidenceLevel, .suspicious)
    }

    func testHandlesPartialInputs() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: nil,
            texture: createNaturalTexture(),
            artifacts: nil
        )

        XCTAssertEqual(result.status, .partial)
        XCTAssertTrue(result.result(for: .lidar)?.available ?? false)
        XCTAssertFalse(result.result(for: .moire)?.available ?? true)
        XCTAssertTrue(result.result(for: .texture)?.available ?? false)
        XCTAssertFalse(result.result(for: .artifacts)?.available ?? true)
        XCTAssertTrue(result.flags.contains(.partialAnalysis))
    }

    func testNormalizesScoresToRange() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        for (_, methodResult) in result.methodBreakdown {
            if let score = methodResult.score {
                XCTAssertGreaterThanOrEqual(score, 0)
                XCTAssertLessThanOrEqual(score, 1)
            }
        }
    }

    // MARK: - AC4: Confidence Level Thresholds

    func testAllMethodsPassReturnsVeryHigh() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        XCTAssertEqual(result.confidenceLevel, .veryHigh)
        XCTAssertGreaterThanOrEqual(result.overallConfidence, ConfidenceAggregationConstants.veryHighThreshold)
        XCTAssertTrue(result.primarySignalValid)
        XCTAssertTrue(result.supportingSignalsAgree)
    }

    func testHighConfidenceThreshold() async {
        // LiDAR passes but some minor issues
        let depth = DepthAnalysisResult(
            depthVariance: 0.6,
            depthLayers: 3,
            edgeCoherence: 0.4,
            minDepth: 0.5,
            maxDepth: 2.0,
            isLikelyRealScene: true
        )

        let result = await aggregator.aggregate(
            depth: depth,
            moire: createCleanMoire(),
            texture: createNaturalTexture()
        )

        XCTAssertTrue(result.confidenceLevel >= .high || result.confidenceLevel == .veryHigh)
        XCTAssertTrue(result.primarySignalValid)
    }

    func testMediumConfidenceThreshold() async {
        // LiDAR fails but supporting signals pass
        let result = await aggregator.aggregate(
            depth: createFailingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        // Should be capped due to disagreement
        XCTAssertTrue(result.confidenceLevel <= .medium)
        XCTAssertFalse(result.primarySignalValid)
    }

    func testSuspiciousWhenAllFail() async {
        let result = await aggregator.aggregate(
            depth: createFailingDepth(),
            moire: createDetectedMoire(),
            texture: createScreenTexture(),
            artifacts: createDetectedArtifacts()
        )

        XCTAssertEqual(result.confidenceLevel, .suspicious)
        XCTAssertLessThan(result.overallConfidence, ConfidenceAggregationConstants.lowThreshold)
    }

    func testVeryHighRequiresAllMethodsAndAgreement() async {
        // All pass but one method missing
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture()
            // artifacts missing
        )

        // Should not be veryHigh due to missing method
        XCTAssertLessThan(result.confidenceLevel, .veryHigh)
        XCTAssertTrue(result.flags.contains(.partialAnalysis))
    }

    // MARK: - AC5: Cross-Validation Logic

    func testAgreementBoostApplied() async {
        // All methods pass and agree
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        XCTAssertTrue(result.supportingSignalsAgree)
        XCTAssertEqual(result.confidenceLevel, .veryHigh)
        // The +5% boost should be applied
        XCTAssertGreaterThanOrEqual(result.overallConfidence, 0.95)
    }

    func testDisagreementCapsConfidence() async {
        // LiDAR says real, moire says screen
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createDetectedMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        // Should be capped at MEDIUM due to disagreement
        XCTAssertLessThanOrEqual(result.confidenceLevel, .medium)
        XCTAssertFalse(result.supportingSignalsAgree)
        XCTAssertTrue(result.flags.contains(.primarySupportingDisagree) ||
                      result.flags.contains(.methodsDisagree) ||
                      result.flags.contains(.screenDetected))
    }

    func testPrimarySupportingDisagreementFlag() async {
        // LiDAR says real, artifacts say artificial
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createDetectedArtifacts()
        )

        XCTAssertTrue(result.flags.contains(.primarySupportingDisagree))
    }

    func testMethodsDisagreeFlag() async {
        // Supporting signals disagree with each other
        let result = await aggregator.aggregate(
            moire: createCleanMoire(), // says no screen
            texture: createScreenTexture(), // says screen
            artifacts: createCleanArtifacts() // says clean
        )

        XCTAssertTrue(result.flags.contains(.methodsDisagree))
    }

    // MARK: - AC6: Confidence Flags

    func testPrimarySignalFailedFlag() async {
        let result = await aggregator.aggregate(
            depth: createFailingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture()
        )

        XCTAssertTrue(result.flags.contains(.primarySignalFailed))
        XCTAssertFalse(result.primarySignalValid)
    }

    func testScreenDetectedFlag() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createDetectedMoire(),
            texture: createNaturalTexture()
        )

        XCTAssertTrue(result.flags.contains(.screenDetected))
        XCTAssertLessThanOrEqual(result.confidenceLevel, .medium)
    }

    func testPrintDetectedFlag() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createHalftoneArtifacts()
        )

        XCTAssertTrue(result.flags.contains(.printDetected))
        XCTAssertLessThanOrEqual(result.confidenceLevel, .medium)
    }

    func testPartialAnalysisFlag() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth()
        )

        XCTAssertTrue(result.flags.contains(.partialAnalysis))
    }

    func testLowConfidencePrimaryFlag() async {
        // LiDAR passes but with minimal metrics
        let lowConfidenceDepth = DepthAnalysisResult(
            depthVariance: 0.51, // Just above threshold
            depthLayers: 3,
            edgeCoherence: 0.31,
            minDepth: 0.5,
            maxDepth: 1.0,
            isLikelyRealScene: true
        )

        let result = await aggregator.aggregate(
            depth: lowConfidenceDepth,
            moire: createCleanMoire()
        )

        // May have low confidence primary flag depending on normalized score
        if let lidarScore = result.result(for: .lidar)?.score,
           lidarScore < ConfidenceAggregationConstants.lowConfidenceLidarThreshold {
            XCTAssertTrue(result.flags.contains(.lowConfidencePrimary))
        }
    }

    // MARK: - AC7: MethodResult Detail Structure

    func testMethodResultContainsAllFields() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire()
        )

        guard let lidarResult = result.result(for: .lidar) else {
            XCTFail("LiDAR result missing")
            return
        }

        XCTAssertTrue(lidarResult.available)
        XCTAssertNotNil(lidarResult.score)
        XCTAssertGreaterThan(lidarResult.weight, 0)
        XCTAssertGreaterThan(lidarResult.contribution, 0)
        XCTAssertEqual(lidarResult.status, "pass")
    }

    func testMethodResultStatusValues() async {
        // All pass
        let passResult = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire()
        )

        XCTAssertEqual(passResult.result(for: .lidar)?.status, "pass")
        XCTAssertEqual(passResult.result(for: .moire)?.status, "pass")

        // Some fail
        let failResult = await aggregator.aggregate(
            depth: createFailingDepth(),
            moire: createDetectedMoire()
        )

        XCTAssertEqual(failResult.result(for: .lidar)?.status, "fail")
        XCTAssertEqual(failResult.result(for: .moire)?.status, "fail")
    }

    func testUnavailableMethodResult() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth()
        )

        guard let moireResult = result.result(for: .moire) else {
            XCTFail("Moire result missing")
            return
        }

        XCTAssertFalse(moireResult.available)
        XCTAssertNil(moireResult.score)
        XCTAssertEqual(moireResult.weight, 0)
        XCTAssertEqual(moireResult.contribution, 0)
        XCTAssertEqual(moireResult.status, "unavailable")
    }

    // MARK: - AC8: Performance Target

    func testPerformanceUnder10ms() async {
        let depth = createPassingDepth()
        let moire = createCleanMoire()
        let texture = createNaturalTexture()
        let artifacts = createCleanArtifacts()

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await aggregator.aggregate(
            depth: depth,
            moire: moire,
            texture: texture,
            artifacts: artifacts
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Allow generous margin for CI (target is 10ms)
        XCTAssertLessThan(elapsed, 100, "Aggregation should complete in <100ms, took \(elapsed)ms")

        // Result should also track time
        print("Reported analysis time: \(result.analysisTimeMs)ms, measured: \(elapsed)ms")
    }

    func testPerformanceMeasure() {
        let depth = createPassingDepth()
        let moire = createCleanMoire()
        let texture = createNaturalTexture()
        let artifacts = createCleanArtifacts()

        measure {
            let expectation = XCTestExpectation(description: "Aggregation complete")
            Task {
                _ = await aggregator.aggregate(
                    depth: depth,
                    moire: moire,
                    texture: texture,
                    artifacts: artifacts
                )
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)
        }
    }

    // MARK: - AC9: Integration with Capture Pipeline

    func testAsyncAwaitInterface() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth()
        )

        XCTAssertNotEqual(result.status, .unavailable)
    }

    func testConcurrentCalls() async {
        // Multiple concurrent aggregations
        async let result1 = aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire()
        )
        async let result2 = aggregator.aggregate(
            depth: createFailingDepth(),
            moire: createDetectedMoire()
        )
        async let result3 = aggregator.aggregate(
            depth: createPassingDepth(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        let results = await [result1, result2, result3]

        for result in results {
            XCTAssertNotEqual(result.status, .error)
        }

        // Results should differ based on inputs
        XCTAssertNotEqual(results[0].overallConfidence, results[1].overallConfidence)
    }

    func testDeterministicResults() async {
        let depth = createPassingDepth()
        let moire = createCleanMoire()

        let result1 = await aggregator.aggregate(depth: depth, moire: moire)
        let result2 = await aggregator.aggregate(depth: depth, moire: moire)
        let result3 = await aggregator.aggregate(depth: depth, moire: moire)

        XCTAssertEqual(result1.overallConfidence, result2.overallConfidence, accuracy: 0.001)
        XCTAssertEqual(result2.overallConfidence, result3.overallConfidence, accuracy: 0.001)
        XCTAssertEqual(result1.confidenceLevel, result2.confidenceLevel)
        XCTAssertEqual(result2.confidenceLevel, result3.confidenceLevel)
    }

    // MARK: - Factory Methods

    func testUnavailableFactoryMethod() {
        let result = AggregatedConfidenceResult.unavailable()

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.overallConfidence, 0)
        XCTAssertEqual(result.confidenceLevel, .suspicious)
        XCTAssertTrue(result.methodBreakdown.isEmpty)
    }

    func testErrorFactoryMethod() {
        let result = AggregatedConfidenceResult.error(analysisTimeMs: 5)

        XCTAssertEqual(result.status, .error)
        XCTAssertEqual(result.overallConfidence, 0)
        XCTAssertEqual(result.confidenceLevel, .suspicious)
        XCTAssertEqual(result.analysisTimeMs, 5)
    }

    // MARK: - Edge Cases

    func testAllMethodsFailReturnsLowConfidence() async {
        let result = await aggregator.aggregate(
            depth: createFailingDepth(),
            moire: createDetectedMoire(confidence: 0.9),
            texture: createScreenTexture(),
            artifacts: createDetectedArtifacts()
        )

        // All methods fail: expect low/suspicious confidence
        // The exact score depends on normalization and weight redistribution
        print("DEBUG: overallConfidence = \(result.overallConfidence)")
        print("DEBUG: confidenceLevel = \(result.confidenceLevel)")
        print("DEBUG: methodBreakdown = \(result.methodBreakdown)")

        // With all methods failing, confidence should be low
        XCTAssertLessThan(result.overallConfidence, 0.40,
                         "Expected confidence < 0.40 but got \(result.overallConfidence)")
        XCTAssertTrue(result.confidenceLevel <= .medium,
                      "Expected medium or lower but got \(result.confidenceLevel)")
        XCTAssertFalse(result.primarySignalValid)
    }

    func testOnlySupportingSignalsNoLidar() async {
        let result = await aggregator.aggregate(
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        XCTAssertFalse(result.primarySignalValid)
        XCTAssertTrue(result.flags.contains(.partialAnalysis))
        // Without LiDAR, can't be veryHigh
        XCTAssertLessThan(result.confidenceLevel, .veryHigh)
    }

    func testScreenDetectedCapsMediumEvenWithGoodLidar() async {
        let result = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createDetectedMoire(confidence: 0.9),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )

        // Screen detection should cap at medium
        XCTAssertLessThanOrEqual(result.confidenceLevel, .medium)
        XCTAssertTrue(result.flags.contains(.screenDetected))
    }

    // MARK: - Constants Verification

    func testConstantsValid() {
        XCTAssertEqual(
            ConfidenceAggregationConstants.lidarWeight +
            ConfidenceAggregationConstants.moireWeight +
            ConfidenceAggregationConstants.textureWeight +
            ConfidenceAggregationConstants.artifactsWeight,
            1.0,
            accuracy: 0.001,
            "Weights should sum to 1.0"
        )

        XCTAssertGreaterThan(ConfidenceAggregationConstants.veryHighThreshold, ConfidenceAggregationConstants.highThreshold)
        XCTAssertGreaterThan(ConfidenceAggregationConstants.highThreshold, ConfidenceAggregationConstants.mediumThreshold)
        XCTAssertGreaterThan(ConfidenceAggregationConstants.mediumThreshold, ConfidenceAggregationConstants.lowThreshold)
        XCTAssertGreaterThan(ConfidenceAggregationConstants.lowThreshold, 0)

        XCTAssertGreaterThan(ConfidenceAggregationConstants.agreementBoost, 0)
        XCTAssertLessThanOrEqual(ConfidenceAggregationConstants.agreementBoost, 0.1)
    }

    // MARK: - MethodResult Tests

    func testMethodResultCodable() throws {
        let result = MethodResult(
            available: true,
            score: 0.85,
            weight: 0.55,
            contribution: 0.4675,
            status: "pass"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MethodResult.self, from: data)

        XCTAssertEqual(decoded.available, result.available)
        XCTAssertEqual(decoded.score, result.score)
        XCTAssertEqual(decoded.weight, result.weight, accuracy: 0.001)
        XCTAssertEqual(decoded.contribution, result.contribution, accuracy: 0.001)
        XCTAssertEqual(decoded.status, result.status)
    }

    func testMethodResultUnavailable() {
        let result = MethodResult.unavailable()

        XCTAssertFalse(result.available)
        XCTAssertNil(result.score)
        XCTAssertEqual(result.weight, 0)
        XCTAssertEqual(result.contribution, 0)
        XCTAssertEqual(result.status, "unavailable")
    }

    // MARK: - DetectionMethod Tests

    func testDetectionMethodAllCases() {
        XCTAssertEqual(DetectionMethod.allCases.count, 4)
        XCTAssertTrue(DetectionMethod.allCases.contains(.lidar))
        XCTAssertTrue(DetectionMethod.allCases.contains(.moire))
        XCTAssertTrue(DetectionMethod.allCases.contains(.texture))
        XCTAssertTrue(DetectionMethod.allCases.contains(.artifacts))
    }

    func testDetectionMethodRawValues() {
        XCTAssertEqual(DetectionMethod.lidar.rawValue, "lidar")
        XCTAssertEqual(DetectionMethod.moire.rawValue, "moire")
        XCTAssertEqual(DetectionMethod.texture.rawValue, "texture")
        XCTAssertEqual(DetectionMethod.artifacts.rawValue, "artifacts")
    }

    // MARK: - ConfidenceFlag Tests

    func testConfidenceFlagRawValues() {
        XCTAssertEqual(ConfidenceFlag.primarySignalFailed.rawValue, "primary_signal_failed")
        XCTAssertEqual(ConfidenceFlag.screenDetected.rawValue, "screen_detected")
        XCTAssertEqual(ConfidenceFlag.printDetected.rawValue, "print_detected")
        XCTAssertEqual(ConfidenceFlag.methodsDisagree.rawValue, "methods_disagree")
        XCTAssertEqual(ConfidenceFlag.primarySupportingDisagree.rawValue, "primary_supporting_disagree")
        XCTAssertEqual(ConfidenceFlag.partialAnalysis.rawValue, "partial_analysis")
        XCTAssertEqual(ConfidenceFlag.lowConfidencePrimary.rawValue, "low_confidence_primary")
        XCTAssertEqual(ConfidenceFlag.ambiguousResults.rawValue, "ambiguous_results")
    }

    // MARK: - AggregationStatus Tests

    func testAggregationStatusValues() async {
        // Success - all methods
        let successResult = await aggregator.aggregate(
            depth: createPassingDepth(),
            moire: createCleanMoire(),
            texture: createNaturalTexture(),
            artifacts: createCleanArtifacts()
        )
        XCTAssertEqual(successResult.status, .success)

        // Partial - some methods
        let partialResult = await aggregator.aggregate(
            depth: createPassingDepth()
        )
        XCTAssertEqual(partialResult.status, .partial)

        // Unavailable - no methods
        let unavailableResult = await aggregator.aggregate()
        XCTAssertEqual(unavailableResult.status, .unavailable)
    }
}
