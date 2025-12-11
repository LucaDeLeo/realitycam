//
//  DetectionResultsTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Unit tests for DetectionResults model (Story 9-6).
//

import XCTest
@testable import Rial

final class DetectionResultsTests: XCTestCase {

    // MARK: - Initialization Tests

    func testEmptyInitialization() {
        let results = DetectionResults()

        XCTAssertNil(results.moire)
        XCTAssertNil(results.texture)
        XCTAssertNil(results.artifacts)
        XCTAssertNil(results.aggregatedConfidence)
        XCTAssertNil(results.crossValidation)
        XCTAssertFalse(results.hasAnyResults)
        XCTAssertEqual(results.availableMethodCount, 0)
        XCTAssertNil(results.confidenceLevel)
        XCTAssertNil(results.overallConfidence)
    }

    func testFullInitialization() {
        let moire = MoireAnalysisResult(
            detected: true,
            confidence: 0.8,
            peaks: [],
            screenType: .lcd,
            analysisTimeMs: 25
        )

        let texture = TextureClassificationResult(
            classification: .realScene,
            confidence: 0.9,
            allClassifications: [.realScene: 0.9],
            isLikelyRecaptured: false,
            analysisTimeMs: 15
        )

        let artifacts = ArtifactAnalysisResult(
            pwmFlickerDetected: false,
            pwmConfidence: 0.1,
            specularPatternDetected: false,
            specularConfidence: 0.1,
            halftoneDetected: false,
            halftoneConfidence: 0.1,
            overallConfidence: 0.1,
            isLikelyArtificial: false,
            analysisTimeMs: 20
        )

        let aggregated = AggregatedConfidenceResult(
            overallConfidence: 0.85,
            confidenceLevel: .high,
            methodBreakdown: [:],
            primarySignalValid: true,
            supportingSignalsAgree: true,
            flags: [],
            analysisTimeMs: 10
        )

        let results = DetectionResults(
            moire: moire,
            texture: texture,
            artifacts: artifacts,
            aggregatedConfidence: aggregated,
            crossValidation: nil,
            totalProcessingTimeMs: 100
        )

        XCTAssertNotNil(results.moire)
        XCTAssertNotNil(results.texture)
        XCTAssertNotNil(results.artifacts)
        XCTAssertNotNil(results.aggregatedConfidence)
        XCTAssertTrue(results.hasAnyResults)
        XCTAssertEqual(results.availableMethodCount, 3)
        XCTAssertEqual(results.confidenceLevel, .high)
        XCTAssertEqual(results.overallConfidence, 0.85)
        XCTAssertEqual(results.primarySignalValid, true)
        XCTAssertEqual(results.signalsAgree, true)
    }

    // MARK: - Factory Method Tests

    func testEmptyFactory() {
        let results = DetectionResults.empty()

        XCTAssertNil(results.moire)
        XCTAssertNil(results.texture)
        XCTAssertNil(results.artifacts)
        XCTAssertFalse(results.hasAnyResults)
    }

    func testUnavailableFactory() {
        let results = DetectionResults.unavailable()

        XCTAssertNotNil(results.moire)
        XCTAssertNotNil(results.texture)
        XCTAssertNotNil(results.artifacts)
        XCTAssertNotNil(results.aggregatedConfidence)

        // All should be in unavailable status
        XCTAssertEqual(results.moire?.status, .unavailable)
        XCTAssertEqual(results.texture?.status, .unavailable)
        XCTAssertEqual(results.artifacts?.status, .unavailable)
        XCTAssertEqual(results.aggregatedConfidence?.status, .unavailable)
    }

    func testPartialFactory() {
        let moire = MoireAnalysisResult.notDetected(analysisTimeMs: 25)

        let results = DetectionResults.partial(
            moire: moire,
            processingTimeMs: 50
        )

        XCTAssertNotNil(results.moire)
        XCTAssertNil(results.texture)
        XCTAssertNil(results.artifacts)
        XCTAssertTrue(results.hasAnyResults)
        XCTAssertEqual(results.availableMethodCount, 1)
        XCTAssertEqual(results.totalProcessingTimeMs, 50)
    }

    // MARK: - Computed Properties Tests

    func testMethodsUsed() {
        let moire = MoireAnalysisResult.notDetected(analysisTimeMs: 25)
        let texture = TextureClassificationResult.realScene(
            confidence: 0.9,
            allClassifications: [.realScene: 0.9],
            analysisTimeMs: 15
        )

        let results = DetectionResults(
            moire: moire,
            texture: texture
        )

        XCTAssertEqual(results.methodsUsed.count, 2)
        XCTAssertTrue(results.methodsUsed.contains("moire"))
        XCTAssertTrue(results.methodsUsed.contains("texture"))
        XCTAssertFalse(results.methodsUsed.contains("artifacts"))
    }

    func testEstimatedSize() {
        let emptyResults = DetectionResults.empty()
        XCTAssertEqual(emptyResults.estimatedSize, 100)

        let moire = MoireAnalysisResult.notDetected(analysisTimeMs: 25)
        let resultsWithMoire = DetectionResults(moire: moire)
        XCTAssertEqual(resultsWithMoire.estimatedSize, 100 + 500)

        // Full results should have largest estimated size
        let fullResults = DetectionResults.unavailable()
        XCTAssertGreaterThan(fullResults.estimatedSize, 3000)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let moire = MoireAnalysisResult(
            detected: true,
            confidence: 0.75,
            peaks: [FrequencyPeak(frequency: 100, magnitude: 0.5, angle: 0, prominence: 5.0)],
            screenType: .lcd,
            analysisTimeMs: 25
        )

        let texture = TextureClassificationResult(
            classification: .realScene,
            confidence: 0.9,
            allClassifications: [.realScene: 0.9, .lcdScreen: 0.05],
            isLikelyRecaptured: false,
            analysisTimeMs: 15
        )

        let original = DetectionResults(
            moire: moire,
            texture: texture,
            totalProcessingTimeMs: 100
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DetectionResults.self, from: data)

        XCTAssertEqual(original.moire?.detected, decoded.moire?.detected)
        XCTAssertEqual(original.moire?.confidence, decoded.moire?.confidence)
        XCTAssertEqual(original.texture?.classification, decoded.texture?.classification)
        XCTAssertEqual(original.totalProcessingTimeMs, decoded.totalProcessingTimeMs)
    }

    func testJSONSnakeCaseKeys() throws {
        let results = DetectionResults(totalProcessingTimeMs: 150)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(results)
        let json = String(data: data, encoding: .utf8)!

        // Verify snake_case keys are used
        XCTAssertTrue(json.contains("total_processing_time_ms"))
        XCTAssertTrue(json.contains("computed_at"))
        XCTAssertFalse(json.contains("totalProcessingTimeMs"))
        XCTAssertFalse(json.contains("computedAt"))
    }

    func testBackwardCompatibilityWithNilFields() throws {
        // Simulate JSON from backend or old captures without all fields
        let jsonString = """
        {
            "computed_at": "2025-12-11T12:00:00Z",
            "total_processing_time_ms": 0
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let results = try decoder.decode(DetectionResults.self, from: jsonString.data(using: .utf8)!)

        XCTAssertNil(results.moire)
        XCTAssertNil(results.texture)
        XCTAssertNil(results.artifacts)
        XCTAssertNil(results.aggregatedConfidence)
        XCTAssertFalse(results.hasAnyResults)
    }

    // MARK: - Equatable Tests

    func testEquatable() {
        let results1 = DetectionResults(totalProcessingTimeMs: 100)
        let results2 = DetectionResults(totalProcessingTimeMs: 100)
        let results3 = DetectionResults(totalProcessingTimeMs: 200)

        // Note: computedAt will differ, so these won't be equal
        // Testing with same computedAt
        let fixedDate = Date()
        let resultsA = DetectionResults(computedAt: fixedDate, totalProcessingTimeMs: 100)
        let resultsB = DetectionResults(computedAt: fixedDate, totalProcessingTimeMs: 100)

        XCTAssertEqual(resultsA, resultsB)
    }

    // MARK: - Integration Tests

    func testWithAggregatedConfidenceResult() {
        let aggregated = AggregatedConfidenceResult(
            overallConfidence: 0.92,
            confidenceLevel: .veryHigh,
            methodBreakdown: [
                .lidar: MethodResult(available: true, score: 0.95, weight: 0.55, contribution: 0.5225, status: "pass"),
                .moire: MethodResult(available: true, score: 0.9, weight: 0.15, contribution: 0.135, status: "pass"),
                .texture: MethodResult(available: true, score: 0.9, weight: 0.15, contribution: 0.135, status: "pass"),
                .artifacts: MethodResult(available: true, score: 0.9, weight: 0.15, contribution: 0.135, status: "pass")
            ],
            primarySignalValid: true,
            supportingSignalsAgree: true,
            flags: [],
            analysisTimeMs: 8
        )

        let results = DetectionResults(aggregatedConfidence: aggregated)

        XCTAssertEqual(results.confidenceLevel, .veryHigh)
        XCTAssertEqual(results.overallConfidence, 0.92)
        XCTAssertEqual(results.primarySignalValid, true)
        XCTAssertEqual(results.signalsAgree, true)
    }

    func testWithCrossValidationResult() {
        let crossValidation = CrossValidationResult.defaultPass(analysisTimeMs: 5)

        let results = DetectionResults(crossValidation: crossValidation)

        XCTAssertNotNil(results.crossValidation)
        XCTAssertEqual(results.crossValidation?.validationStatus, .pass)
    }

    // MARK: - Description Test

    func testDescription() {
        let results = DetectionResults.empty()
        let description = results.description

        XCTAssertTrue(description.contains("DetectionResults"))
        XCTAssertTrue(description.contains("hasResults: false"))
    }
}
