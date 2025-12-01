//
//  CaptureDataPrivacyModeTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-01.
//
//  Unit tests for CaptureData privacy mode extensions (Story 8-3).
//

import XCTest
@testable import Rial

final class CaptureDataPrivacyModeTests: XCTestCase {

    // MARK: - Test Data

    private var sampleMetadata: CaptureMetadata!
    private var sampleJpeg: Data!
    private var sampleDepth: Data!

    override func setUp() {
        super.setUp()
        sampleJpeg = "test jpeg data".data(using: .utf8)!
        sampleDepth = Data(repeating: 0x42, count: 100)
        sampleMetadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: CryptoService.sha256(sampleJpeg),
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192),
            iosVersion: "18.1",
            appVersion: "1.0.0"
        )
    }

    // MARK: - UploadMode Tests (AC #8)

    /// Test that UploadMode enum has correct raw values
    func testUploadMode_RawValues() {
        XCTAssertEqual(UploadMode.full.rawValue, "full")
        XCTAssertEqual(UploadMode.hashOnly.rawValue, "hash_only")
    }

    /// Test UploadMode Codable round-trip
    func testUploadMode_Codable_RoundTrip() throws {
        for mode in [UploadMode.full, UploadMode.hashOnly] {
            let encoder = JSONEncoder()
            let data = try encoder.encode(mode)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(UploadMode.self, from: data)

            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - CaptureData Privacy Mode Fields Tests (AC #8)

    /// Test that new fields default to nil for backward compatibility
    func testCaptureData_NewFieldsDefaultNil() {
        let captureData = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata
        )

        XCTAssertNil(captureData.uploadMode)
        XCTAssertNil(captureData.depthAnalysisResult)
        XCTAssertNil(captureData.privacySettings)
    }

    /// Test that CaptureData can be created with privacy mode fields
    func testCaptureData_WithPrivacyModeFields() {
        let depthAnalysis = DepthAnalysisResult(
            depthVariance: 2.4,
            depthLayers: 5,
            edgeCoherence: 0.87,
            minDepth: 0.5,
            maxDepth: 8.0,
            isLikelyRealScene: true
        )
        let privacySettings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .coarse,
            timestampLevel: .exact,
            deviceInfoLevel: .modelOnly
        )

        let captureData = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata,
            uploadMode: .hashOnly,
            depthAnalysisResult: depthAnalysis,
            privacySettings: privacySettings
        )

        XCTAssertEqual(captureData.uploadMode, .hashOnly)
        XCTAssertNotNil(captureData.depthAnalysisResult)
        XCTAssertEqual(captureData.depthAnalysisResult?.depthVariance, 2.4)
        XCTAssertNotNil(captureData.privacySettings)
        XCTAssertTrue(captureData.privacySettings?.privacyModeEnabled ?? false)
    }

    /// Test backward compatibility - old captures without privacy fields decode correctly
    func testCaptureData_BackwardCompatibility_OldCaptures() throws {
        // Create old-style capture data (without privacy fields)
        let oldCapture = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(oldCapture)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureData.self, from: data)

        // Verify old fields preserved
        XCTAssertEqual(decoded.jpeg, oldCapture.jpeg)
        XCTAssertEqual(decoded.depth, oldCapture.depth)
        XCTAssertEqual(decoded.metadata.photoHash, oldCapture.metadata.photoHash)

        // Verify new fields are nil
        XCTAssertNil(decoded.uploadMode)
        XCTAssertNil(decoded.depthAnalysisResult)
        XCTAssertNil(decoded.privacySettings)
    }

    /// Test Codable round-trip with privacy mode fields
    func testCaptureData_Codable_WithPrivacyFields() throws {
        let depthAnalysis = DepthAnalysisResult(
            depthVariance: 2.4,
            depthLayers: 5,
            edgeCoherence: 0.87,
            minDepth: 0.5,
            maxDepth: 8.0,
            isLikelyRealScene: true
        )
        let privacySettings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .precise,
            timestampLevel: .dayOnly,
            deviceInfoLevel: .full
        )

        let original = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata,
            uploadMode: .hashOnly,
            depthAnalysisResult: depthAnalysis,
            privacySettings: privacySettings
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureData.self, from: data)

        // Verify all fields
        XCTAssertEqual(decoded.jpeg, original.jpeg)
        XCTAssertEqual(decoded.uploadMode, original.uploadMode)
        XCTAssertEqual(decoded.depthAnalysisResult?.depthVariance, original.depthAnalysisResult?.depthVariance)
        XCTAssertEqual(decoded.privacySettings?.privacyModeEnabled, original.privacySettings?.privacyModeEnabled)
        XCTAssertEqual(decoded.privacySettings?.locationLevel, original.privacySettings?.locationLevel)
    }

    /// Test that uploadMode can be set to full
    func testCaptureData_FullUploadMode() {
        let captureData = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata,
            uploadMode: .full
        )

        XCTAssertEqual(captureData.uploadMode, .full)
    }

    /// Test that privacy fields can be modified after creation
    func testCaptureData_PrivacyFieldsMutable() {
        var captureData = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata
        )

        XCTAssertNil(captureData.uploadMode)

        captureData.uploadMode = .hashOnly
        captureData.depthAnalysisResult = .unavailable()
        captureData.privacySettings = .default

        XCTAssertEqual(captureData.uploadMode, .hashOnly)
        XCTAssertNotNil(captureData.depthAnalysisResult)
        XCTAssertNotNil(captureData.privacySettings)
    }

    // MARK: - Integration with Existing Fields

    /// Test that privacy mode doesn't affect existing assertion fields
    func testCaptureData_PrivacyModeDoesNotAffectAssertionFields() {
        let captureData = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata,
            assertion: "test_assertion".data(using: .utf8),
            assertionStatus: .generated,
            assertionAttemptCount: 1,
            uploadMode: .hashOnly
        )

        XCTAssertNotNil(captureData.assertion)
        XCTAssertEqual(captureData.assertionStatus, .generated)
        XCTAssertEqual(captureData.assertionAttemptCount, 1)
        XCTAssertEqual(captureData.uploadMode, .hashOnly)
    }

    /// Test hasAssertion works with privacy mode
    func testCaptureData_HasAssertion_WorksWithPrivacyMode() {
        let captureData = CaptureData(
            jpeg: sampleJpeg,
            depth: sampleDepth,
            metadata: sampleMetadata,
            assertion: "test_assertion".data(using: .utf8),
            assertionStatus: .generated,
            uploadMode: .hashOnly
        )

        XCTAssertTrue(captureData.hasAssertion)
    }
}
