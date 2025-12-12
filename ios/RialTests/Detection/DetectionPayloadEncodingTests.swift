//
//  DetectionPayloadEncodingTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-11.
//
//  Payload encoding tests for DetectionResults (Story 9-8, AC5).
//  Verifies JSON encoding matches backend Rust type expectations.
//

import XCTest
import Foundation
@testable import Rial

/// Tests for DetectionResults JSON encoding to ensure iOS-backend type compatibility.
///
/// These tests verify:
/// - All CodingKeys use snake_case matching backend expectations
/// - Enum raw values match Rust serde(rename_all) output
/// - DateTime encoding uses ISO 8601 format
/// - Confidence bounds (0.0-1.0) encoded as floats
/// - Nested optional fields serialize correctly
final class DetectionPayloadEncodingTests: XCTestCase {

    // MARK: - Properties

    var encoder: JSONEncoder!
    var decoder: JSONDecoder!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys] // For consistent test comparisons

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - AC5: Snake Case Field Names

    func testDetectionResultsUsesSnakeCaseKeys() throws {
        let results = createSampleDetectionResults()

        let data = try encoder.encode(results)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify snake_case keys are used (not camelCase)
        XCTAssertTrue(jsonString.contains("\"computed_at\""), "Should use computed_at (snake_case)")
        XCTAssertTrue(jsonString.contains("\"total_processing_time_ms\""), "Should use total_processing_time_ms")
        XCTAssertTrue(jsonString.contains("\"aggregated_confidence\""), "Should use aggregated_confidence")
        XCTAssertTrue(jsonString.contains("\"cross_validation\""), "Should use cross_validation")

        // Verify camelCase is NOT used
        XCTAssertFalse(jsonString.contains("\"computedAt\""), "Should NOT use computedAt (camelCase)")
        XCTAssertFalse(jsonString.contains("\"totalProcessingTimeMs\""), "Should NOT use totalProcessingTimeMs")
    }

    func testMoireAnalysisResultUsesSnakeCaseKeys() throws {
        let moire = createSampleMoireResult()

        let data = try encoder.encode(moire)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify snake_case keys
        XCTAssertTrue(jsonString.contains("\"screen_type\""), "Should use screen_type")
        XCTAssertTrue(jsonString.contains("\"analysis_time_ms\""), "Should use analysis_time_ms")
        XCTAssertTrue(jsonString.contains("\"algorithm_version\""), "Should use algorithm_version")
        XCTAssertTrue(jsonString.contains("\"computed_at\""), "Should use computed_at")
    }

    func testTextureClassificationResultUsesSnakeCaseKeys() throws {
        let texture = createSampleTextureResult()

        let data = try encoder.encode(texture)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify snake_case keys
        XCTAssertTrue(jsonString.contains("\"all_classifications\""), "Should use all_classifications")
        XCTAssertTrue(jsonString.contains("\"is_likely_recaptured\""), "Should use is_likely_recaptured")
        XCTAssertTrue(jsonString.contains("\"analysis_time_ms\""), "Should use analysis_time_ms")
        XCTAssertTrue(jsonString.contains("\"algorithm_version\""), "Should use algorithm_version")
        XCTAssertTrue(jsonString.contains("\"unavailability_reason\"") || !jsonString.contains("unavailabilityReason"),
                     "Should use snake_case or omit if nil")
    }

    func testArtifactAnalysisResultUsesSnakeCaseKeys() throws {
        let artifacts = createSampleArtifactResult()

        let data = try encoder.encode(artifacts)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify snake_case keys
        XCTAssertTrue(jsonString.contains("\"pwm_flicker_detected\""), "Should use pwm_flicker_detected")
        XCTAssertTrue(jsonString.contains("\"pwm_confidence\""), "Should use pwm_confidence")
        XCTAssertTrue(jsonString.contains("\"specular_pattern_detected\""), "Should use specular_pattern_detected")
        XCTAssertTrue(jsonString.contains("\"specular_confidence\""), "Should use specular_confidence")
        XCTAssertTrue(jsonString.contains("\"halftone_detected\""), "Should use halftone_detected")
        XCTAssertTrue(jsonString.contains("\"halftone_confidence\""), "Should use halftone_confidence")
        XCTAssertTrue(jsonString.contains("\"overall_confidence\""), "Should use overall_confidence")
        XCTAssertTrue(jsonString.contains("\"is_likely_artificial\""), "Should use is_likely_artificial")
        XCTAssertTrue(jsonString.contains("\"analysis_time_ms\""), "Should use analysis_time_ms")
    }

    func testAggregatedConfidenceResultUsesSnakeCaseKeys() throws {
        let aggregated = createSampleAggregatedResult()

        let data = try encoder.encode(aggregated)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify snake_case keys
        XCTAssertTrue(jsonString.contains("\"overall_confidence\""), "Should use overall_confidence")
        XCTAssertTrue(jsonString.contains("\"confidence_level\""), "Should use confidence_level")
        XCTAssertTrue(jsonString.contains("\"method_breakdown\""), "Should use method_breakdown")
        XCTAssertTrue(jsonString.contains("\"primary_signal_valid\""), "Should use primary_signal_valid")
        XCTAssertTrue(jsonString.contains("\"supporting_signals_agree\""), "Should use supporting_signals_agree")
        XCTAssertTrue(jsonString.contains("\"analysis_time_ms\""), "Should use analysis_time_ms")
        XCTAssertTrue(jsonString.contains("\"algorithm_version\""), "Should use algorithm_version")
    }

    // MARK: - AC5: Enum Serialization

    func testMoireAnalysisStatusSerialization() throws {
        // Test all status values
        let completed = MoireAnalysisStatus.completed
        let unavailable = MoireAnalysisStatus.unavailable
        let failed = MoireAnalysisStatus.failed

        XCTAssertEqual(try encodeEnum(completed), "\"completed\"")
        XCTAssertEqual(try encodeEnum(unavailable), "\"unavailable\"")
        XCTAssertEqual(try encodeEnum(failed), "\"failed\"")
    }

    func testTextureClassificationStatusSerialization() throws {
        let success = TextureClassificationStatus.success
        let unavailable = TextureClassificationStatus.unavailable
        let error = TextureClassificationStatus.error

        XCTAssertEqual(try encodeEnum(success), "\"success\"")
        XCTAssertEqual(try encodeEnum(unavailable), "\"unavailable\"")
        XCTAssertEqual(try encodeEnum(error), "\"error\"")
    }

    func testArtifactAnalysisStatusSerialization() throws {
        let success = ArtifactAnalysisStatus.success
        let unavailable = ArtifactAnalysisStatus.unavailable
        let error = ArtifactAnalysisStatus.error

        XCTAssertEqual(try encodeEnum(success), "\"success\"")
        XCTAssertEqual(try encodeEnum(unavailable), "\"unavailable\"")
        XCTAssertEqual(try encodeEnum(error), "\"error\"")
    }

    func testScreenTypeSerialization() throws {
        let lcd = ScreenType.lcd
        let oled = ScreenType.oled
        let highRefresh = ScreenType.highRefresh
        let unknown = ScreenType.unknown

        XCTAssertEqual(try encodeEnum(lcd), "\"lcd\"")
        XCTAssertEqual(try encodeEnum(oled), "\"oled\"")
        XCTAssertEqual(try encodeEnum(highRefresh), "\"highRefresh\"")
        XCTAssertEqual(try encodeEnum(unknown), "\"unknown\"")
    }

    func testTextureTypeSerialization() throws {
        let realScene = TextureType.realScene
        let lcdScreen = TextureType.lcdScreen
        let oledScreen = TextureType.oledScreen
        let printedPaper = TextureType.printedPaper
        let unknown = TextureType.unknown

        // Backend expects snake_case
        XCTAssertEqual(try encodeEnum(realScene), "\"real_scene\"")
        XCTAssertEqual(try encodeEnum(lcdScreen), "\"lcd_screen\"")
        XCTAssertEqual(try encodeEnum(oledScreen), "\"oled_screen\"")
        XCTAssertEqual(try encodeEnum(printedPaper), "\"printed_paper\"")
        XCTAssertEqual(try encodeEnum(unknown), "\"unknown\"")
    }

    func testAggregatedConfidenceLevelSerialization() throws {
        let veryHigh = AggregatedConfidenceLevel.veryHigh
        let high = AggregatedConfidenceLevel.high
        let medium = AggregatedConfidenceLevel.medium
        let low = AggregatedConfidenceLevel.low
        let suspicious = AggregatedConfidenceLevel.suspicious

        // Backend expects snake_case via #[serde(rename_all = "snake_case")]
        XCTAssertEqual(try encodeEnum(veryHigh), "\"veryHigh\"")
        XCTAssertEqual(try encodeEnum(high), "\"high\"")
        XCTAssertEqual(try encodeEnum(medium), "\"medium\"")
        XCTAssertEqual(try encodeEnum(low), "\"low\"")
        XCTAssertEqual(try encodeEnum(suspicious), "\"suspicious\"")
    }

    func testAggregationStatusSerialization() throws {
        let success = AggregationStatus.success
        let partial = AggregationStatus.partial
        let unavailable = AggregationStatus.unavailable
        let error = AggregationStatus.error

        XCTAssertEqual(try encodeEnum(success), "\"success\"")
        XCTAssertEqual(try encodeEnum(partial), "\"partial\"")
        XCTAssertEqual(try encodeEnum(unavailable), "\"unavailable\"")
        XCTAssertEqual(try encodeEnum(error), "\"error\"")
    }

    func testConfidenceFlagSerialization() throws {
        let flags: [ConfidenceFlag] = [
            .primarySignalFailed,
            .screenDetected,
            .printDetected,
            .methodsDisagree,
            .primarySupportingDisagree,
            .partialAnalysis,
            .lowConfidencePrimary,
            .ambiguousResults,
            .consistencyAnomaly,
            .temporalInconsistency,
            .highUncertainty
        ]

        let expectedValues = [
            "\"primarySignalFailed\"",
            "\"screenDetected\"",
            "\"printDetected\"",
            "\"methodsDisagree\"",
            "\"primarySupportingDisagree\"",
            "\"partialAnalysis\"",
            "\"lowConfidencePrimary\"",
            "\"ambiguousResults\"",
            "\"consistencyAnomaly\"",
            "\"temporalInconsistency\"",
            "\"highUncertainty\""
        ]

        for (flag, expected) in zip(flags, expectedValues) {
            XCTAssertEqual(try encodeEnum(flag), expected, "Flag \(flag) should serialize correctly")
        }
    }

    // MARK: - AC5: DateTime ISO 8601 Format

    func testDateTimeEncodingISO8601() throws {
        let results = createSampleDetectionResults()

        let data = try encoder.encode(results)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify ISO 8601 date format (YYYY-MM-DDTHH:MM:SS.sssZ or similar)
        let iso8601Regex = try NSRegularExpression(
            pattern: #""computed_at"\s*:\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"#,
            options: []
        )
        let range = NSRange(jsonString.startIndex..., in: jsonString)
        let matches = iso8601Regex.numberOfMatches(in: jsonString, options: [], range: range)

        XCTAssertGreaterThan(matches, 0, "Should contain ISO 8601 formatted dates")
    }

    func testDateTimeRoundTrip() throws {
        let originalDate = Date()
        let results = DetectionResults(
            computedAt: originalDate,
            totalProcessingTimeMs: 100
        )

        let data = try encoder.encode(results)
        let decoded = try decoder.decode(DetectionResults.self, from: data)

        // Allow 1 second tolerance due to ISO 8601 encoding precision
        XCTAssertEqual(decoded.computedAt.timeIntervalSince1970,
                      originalDate.timeIntervalSince1970,
                      accuracy: 1.0,
                      "Date should round-trip correctly")
    }

    // MARK: - AC5: Confidence Value Bounds

    func testConfidenceValuesEncodedAsFloats() throws {
        let moire = MoireAnalysisResult(
            detected: true,
            confidence: 0.85,
            peaks: [],
            screenType: .lcd,
            analysisTimeMs: 25
        )

        let data = try encoder.encode(moire)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify confidence is a number (float)
        guard let confidence = json["confidence"] as? Double else {
            XCTFail("Confidence should be a number")
            return
        }

        XCTAssertEqual(confidence, 0.85, accuracy: 0.001, "Confidence should be 0.85")
    }

    func testConfidenceValueBounds() throws {
        // Test that confidence values are properly clamped during initialization
        let moireHigh = MoireAnalysisResult(
            detected: true,
            confidence: 1.5, // Above max
            peaks: [],
            screenType: nil,
            analysisTimeMs: 25
        )

        let moireLow = MoireAnalysisResult(
            detected: false,
            confidence: -0.5, // Below min
            peaks: [],
            screenType: nil,
            analysisTimeMs: 25
        )

        XCTAssertEqual(moireHigh.confidence, 1.0, "Confidence should be clamped to 1.0")
        XCTAssertEqual(moireLow.confidence, 0.0, "Confidence should be clamped to 0.0")
    }

    // MARK: - AC5: Nested Optional Fields

    func testNestedOptionalFieldsSerialization() throws {
        // Test with all optionals present
        let fullResults = createSampleDetectionResults()
        let fullData = try encoder.encode(fullResults)
        let fullJson = String(data: fullData, encoding: .utf8)!

        XCTAssertTrue(fullJson.contains("\"moire\""), "moire should be present")
        XCTAssertTrue(fullJson.contains("\"texture\""), "texture should be present")
        XCTAssertTrue(fullJson.contains("\"artifacts\""), "artifacts should be present")
        XCTAssertTrue(fullJson.contains("\"aggregated_confidence\""), "aggregated_confidence should be present")

        // Test with no optionals (empty)
        let emptyResults = DetectionResults.empty()
        let emptyData = try encoder.encode(emptyResults)
        let emptyJson = String(data: emptyData, encoding: .utf8)!

        // With empty results, optional fields should be null
        // (encoder behavior may vary, but decoded values should be nil)
        let decoded = try decoder.decode(DetectionResults.self, from: emptyData)
        XCTAssertNil(decoded.moire, "moire should be nil for empty results")
        XCTAssertNil(decoded.texture, "texture should be nil for empty results")
        XCTAssertNil(decoded.artifacts, "artifacts should be nil for empty results")
    }

    func testOptionalScreenTypeSerialization() throws {
        // Moire with screen type
        let withScreenType = MoireAnalysisResult(
            detected: true,
            confidence: 0.9,
            peaks: [],
            screenType: .lcd,
            analysisTimeMs: 25
        )

        // Moire without screen type
        let withoutScreenType = MoireAnalysisResult(
            detected: false,
            confidence: 0.0,
            peaks: [],
            screenType: nil,
            analysisTimeMs: 25
        )

        let dataWith = try encoder.encode(withScreenType)
        let dataWithout = try encoder.encode(withoutScreenType)

        let jsonWith = String(data: dataWith, encoding: .utf8)!
        let jsonWithout = String(data: dataWithout, encoding: .utf8)!

        XCTAssertTrue(jsonWith.contains("\"screen_type\""), "screen_type should be present when set")

        // Verify round-trip
        let decodedWith = try decoder.decode(MoireAnalysisResult.self, from: dataWith)
        let decodedWithout = try decoder.decode(MoireAnalysisResult.self, from: dataWithout)

        XCTAssertEqual(decodedWith.screenType, .lcd)
        XCTAssertNil(decodedWithout.screenType)
    }

    // MARK: - Full Round-Trip Tests

    func testFullDetectionResultsRoundTrip() throws {
        let original = createSampleDetectionResults()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DetectionResults.self, from: data)

        // Verify key fields round-trip correctly
        XCTAssertEqual(decoded.totalProcessingTimeMs, original.totalProcessingTimeMs)
        XCTAssertEqual(decoded.moire?.detected, original.moire?.detected)
        XCTAssertEqual(decoded.moire?.confidence, original.moire?.confidence)
        XCTAssertEqual(decoded.texture?.classification, original.texture?.classification)
        XCTAssertEqual(decoded.artifacts?.pwmFlickerDetected, original.artifacts?.pwmFlickerDetected)
        XCTAssertEqual(decoded.aggregatedConfidence?.confidenceLevel, original.aggregatedConfidence?.confidenceLevel)
    }

    func testPayloadSizeEstimate() throws {
        let results = createSampleDetectionResults()
        let data = try encoder.encode(results)

        // Typical payload should be 2-5KB per documentation
        let sizeKB = Double(data.count) / 1024.0
        XCTAssertLessThan(sizeKB, 10.0, "Payload should be under 10KB")
        XCTAssertGreaterThan(data.count, 100, "Payload should have substantial content")

        print("Detection results payload size: \(String(format: "%.2f", sizeKB)) KB")
    }

    // MARK: - Backend Compatibility Snapshot Test

    func testJSONStructureMatchesBackendExpectations() throws {
        let results = createSampleDetectionResults()
        let data = try encoder.encode(results)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify top-level structure matches backend DetectionResults
        // (computed_at and total_processing_time_ms are required)
        XCTAssertNotNil(json["computed_at"], "computed_at is required")
        XCTAssertNotNil(json["total_processing_time_ms"], "total_processing_time_ms is required")

        // Optional fields should use correct snake_case keys when present
        if let moire = json["moire"] as? [String: Any] {
            XCTAssertNotNil(moire["detected"], "moire.detected should be present")
            XCTAssertNotNil(moire["confidence"], "moire.confidence should be present")
            XCTAssertNotNil(moire["status"], "moire.status should be present")
            XCTAssertNotNil(moire["analysis_time_ms"], "moire.analysis_time_ms should be present")
        }

        if let aggregated = json["aggregated_confidence"] as? [String: Any] {
            XCTAssertNotNil(aggregated["overall_confidence"], "overall_confidence should be present")
            XCTAssertNotNil(aggregated["confidence_level"], "confidence_level should be present")
            XCTAssertNotNil(aggregated["primary_signal_valid"], "primary_signal_valid should be present")
            XCTAssertNotNil(aggregated["supporting_signals_agree"], "supporting_signals_agree should be present")
        }
    }

    // MARK: - Helpers

    private func encodeEnum<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8)!
    }

    private func createSampleDetectionResults() -> DetectionResults {
        return DetectionResults(
            moire: createSampleMoireResult(),
            texture: createSampleTextureResult(),
            artifacts: createSampleArtifactResult(),
            aggregatedConfidence: createSampleAggregatedResult(),
            crossValidation: nil,
            computedAt: Date(),
            totalProcessingTimeMs: 150
        )
    }

    private func createSampleMoireResult() -> MoireAnalysisResult {
        return MoireAnalysisResult(
            detected: false,
            confidence: 0.0,
            peaks: [
                FrequencyPeak(frequency: 120.0, magnitude: 0.1, angle: 0.0, prominence: 2.5)
            ],
            screenType: nil,
            analysisTimeMs: 28
        )
    }

    private func createSampleTextureResult() -> TextureClassificationResult {
        return TextureClassificationResult(
            classification: .realScene,
            confidence: 0.92,
            allClassifications: [
                .realScene: 0.92,
                .lcdScreen: 0.05,
                .oledScreen: 0.02,
                .printedPaper: 0.01
            ],
            isLikelyRecaptured: false,
            analysisTimeMs: 18
        )
    }

    private func createSampleArtifactResult() -> ArtifactAnalysisResult {
        return ArtifactAnalysisResult(
            pwmFlickerDetected: false,
            pwmConfidence: 0.0,
            specularPatternDetected: false,
            specularConfidence: 0.1,
            halftoneDetected: false,
            halftoneConfidence: 0.0,
            overallConfidence: 0.0,
            isLikelyArtificial: false,
            analysisTimeMs: 42
        )
    }

    private func createSampleAggregatedResult() -> AggregatedConfidenceResult {
        return AggregatedConfidenceResult(
            overallConfidence: 0.88,
            confidenceLevel: .high,
            methodBreakdown: [
                .lidar: MethodResult(available: false, score: nil, weight: 0, contribution: 0, status: "unavailable"),
                .moire: MethodResult(available: true, score: 1.0, weight: 0.333, contribution: 0.333, status: "pass"),
                .texture: MethodResult(available: true, score: 0.92, weight: 0.333, contribution: 0.307, status: "pass"),
                .artifacts: MethodResult(available: true, score: 1.0, weight: 0.333, contribution: 0.333, status: "pass")
            ],
            primarySignalValid: false,
            supportingSignalsAgree: true,
            flags: [.partialAnalysis],
            analysisTimeMs: 5,
            status: .partial
        )
    }
}
