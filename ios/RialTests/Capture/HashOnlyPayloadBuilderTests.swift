//
//  HashOnlyPayloadBuilderTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-01.
//
//  Unit tests for HashOnlyPayloadBuilder (Story 8-3).
//

import XCTest
@testable import Rial

final class HashOnlyPayloadBuilderTests: XCTestCase {

    // MARK: - Test Data

    private var sampleCaptureData: CaptureData!
    private var sampleDepthAnalysis: DepthAnalysisResult!
    private var sampleSettings: PrivacySettings!

    override func setUp() {
        super.setUp()

        // Create sample JPEG data (small for testing)
        let jpegData = "test jpeg data for hashing".data(using: .utf8)!

        // Create sample depth data
        let depthData = Data(repeating: 0x42, count: 100)

        // Create sample metadata
        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: CryptoService.sha256(jpegData),
            location: LocationData(
                latitude: 37.7749,
                longitude: -122.4194,
                altitude: 10.0,
                accuracy: 5.0
            ),
            depthMapDimensions: DepthDimensions(width: 256, height: 192),
            iosVersion: "18.1",
            appVersion: "1.0.0"
        )

        sampleCaptureData = CaptureData(
            jpeg: jpegData,
            depth: depthData,
            metadata: metadata,
            timestamp: Date()
        )

        sampleDepthAnalysis = DepthAnalysisResult(
            depthVariance: 2.4,
            depthLayers: 5,
            edgeCoherence: 0.87,
            minDepth: 0.5,
            maxDepth: 8.0,
            isLikelyRealScene: true
        )

        sampleSettings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .coarse,
            timestampLevel: .exact,
            deviceInfoLevel: .modelOnly
        )
    }

    // MARK: - Payload Construction Tests (AC #4)

    /// Test that build creates valid payload
    func testBuild_CreatesValidPayload() async {
        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertEqual(payload.captureMode, "hash_only")
        XCTAssertEqual(payload.mediaType, "photo")
        XCTAssertFalse(payload.mediaHash.isEmpty, "Media hash should not be empty")
        XCTAssertEqual(payload.mediaHash.count, 64, "SHA-256 hex should be 64 chars")
    }

    /// Test that mediaHash is computed from JPEG data
    func testBuild_ComputesCorrectMediaHash() async {
        let expectedHash = CryptoService.sha256(sampleCaptureData.jpeg)

        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertEqual(payload.mediaHash, expectedHash)
    }

    /// Test that depth analysis is included
    func testBuild_IncludesDepthAnalysis() async {
        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertNotNil(payload.depthAnalysis)
        XCTAssertEqual(payload.depthAnalysis?.depthVariance, 2.4)
        XCTAssertEqual(payload.depthAnalysis?.depthLayers, 5)
        XCTAssertEqual(payload.depthAnalysis?.edgeCoherence, 0.87)
        XCTAssertTrue(payload.depthAnalysis?.isLikelyRealScene ?? false)
    }

    /// Test that assertion is initially empty
    func testBuild_AssertionInitiallyEmpty() async {
        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertEqual(payload.assertion, "", "Assertion should be empty before signing")
    }

    // MARK: - Metadata Filtering Tests (AC #3)

    /// Test that metadata is filtered according to settings
    func testBuild_FiltersMetadataAccordingToSettings() async {
        let settings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .none,
            timestampLevel: .dayOnly,
            deviceInfoLevel: .full
        )

        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: settings,
            depthAnalysis: sampleDepthAnalysis
        )

        // Location should be nil (level = none)
        XCTAssertNil(payload.metadata.location)

        // Timestamp should be day only
        XCTAssertNotNil(payload.metadata.timestamp)
        XCTAssertFalse(payload.metadata.timestamp!.contains("T"), "Day only should not have time")

        // Device info should be full
        XCTAssertNotNil(payload.metadata.deviceModel)
        XCTAssertTrue(payload.metadata.deviceModel!.contains("/"), "Full should have separator")
    }

    /// Test that metadata flags match filtering
    func testBuild_MetadataFlagsMatchFiltering() async {
        let settings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .precise,
            timestampLevel: .none,
            deviceInfoLevel: .modelOnly
        )

        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: settings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertTrue(payload.metadataFlags.locationIncluded)
        XCTAssertEqual(payload.metadataFlags.locationLevel, "precise")
        XCTAssertFalse(payload.metadataFlags.timestampIncluded)
        XCTAssertEqual(payload.metadataFlags.timestampLevel, "none")
        XCTAssertTrue(payload.metadataFlags.deviceInfoIncluded)
        XCTAssertEqual(payload.metadataFlags.deviceInfoLevel, "model_only")
    }

    // MARK: - Payload Size Tests (AC #6)

    /// Test that payload is under 10KB
    func testBuild_PayloadUnder10KB() async {
        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertTrue(payload.isWithinSizeLimit(), "Payload should be under 10KB")
    }

    /// Test that no raw photo bytes are in payload
    func testBuild_NoRawPhotoBytes() async throws {
        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        let jsonData = try payload.toJSONData()
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // The raw JPEG data should not appear in the JSON
        let jpegBase64 = sampleCaptureData.jpeg.base64EncodedString()
        XCTAssertFalse(jsonString.contains(jpegBase64), "JSON should not contain raw photo bytes")
    }

    // MARK: - Sync Build Tests

    /// Test sync build creates valid payload
    func testBuildSync_CreatesValidPayload() {
        let payload = HashOnlyPayloadBuilder.buildSync(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertEqual(payload.captureMode, "hash_only")
        XCTAssertEqual(payload.mediaType, "photo")
        XCTAssertFalse(payload.mediaHash.isEmpty)
    }

    /// Test sync and async build produce same mediaHash
    func testBuildSync_SameHashAsAsync() async {
        let syncPayload = HashOnlyPayloadBuilder.buildSync(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        let asyncPayload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertEqual(syncPayload.mediaHash, asyncPayload.mediaHash)
    }

    // MARK: - Video Payload Tests

    /// Test video payload construction
    func testBuildVideo_CreatesVideoPayload() async {
        let hashChain = PrivacyHashChainData(finalHash: "finalHash123", chainLength: 450)

        // Create temporal depth analysis for video
        let temporalAnalysis = TemporalDepthAnalysisResult(
            keyframeAnalyses: [sampleDepthAnalysis],
            meanVariance: 2.4,
            varianceStability: 0.92,
            temporalCoherence: 0.85,
            isLikelyRealScene: true,
            keyframeCount: 150
        )

        let payload = await HashOnlyPayloadBuilder.buildVideo(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            temporalDepthAnalysis: temporalAnalysis,
            hashChain: hashChain,
            frameCount: 450,
            durationMs: 15000
        )

        XCTAssertEqual(payload.captureMode, "hash_only")
        XCTAssertEqual(payload.mediaType, "video")
        XCTAssertEqual(payload.frameCount, 450)
        XCTAssertEqual(payload.durationMs, 15000)
        XCTAssertNotNil(payload.hashChain)
        XCTAssertEqual(payload.hashChain?.finalHash, "finalHash123")
        XCTAssertEqual(payload.hashChain?.chainLength, 450)
        XCTAssertNotNil(payload.temporalDepthAnalysis)
        XCTAssertEqual(payload.temporalDepthAnalysis?.keyframeCount, 150)
        XCTAssertTrue(payload.temporalDepthAnalysis?.isLikelyRealScene ?? false)
    }

    // MARK: - Unavailable Depth Analysis Tests

    /// Test that unavailable depth analysis is handled
    func testBuild_UnavailableDepthAnalysis_StillBuildsPayload() async {
        let unavailableAnalysis = DepthAnalysisResult.unavailable()

        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: sampleSettings,
            depthAnalysis: unavailableAnalysis
        )

        XCTAssertNotNil(payload.depthAnalysis)
        XCTAssertEqual(payload.depthAnalysis?.status, .unavailable)
        XCTAssertFalse(payload.depthAnalysis?.isLikelyRealScene ?? true)
        XCTAssertEqual(payload.captureMode, "hash_only")
    }

    // MARK: - Edge Cases

    /// Test with minimal privacy settings (all none)
    func testBuild_AllNoneSettings_MinimalPayload() async {
        let minimalSettings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .none,
            timestampLevel: .none,
            deviceInfoLevel: .none
        )

        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: minimalSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertNil(payload.metadata.location)
        XCTAssertNil(payload.metadata.timestamp)
        XCTAssertNil(payload.metadata.deviceModel)
        XCTAssertFalse(payload.metadataFlags.locationIncluded)
        XCTAssertFalse(payload.metadataFlags.timestampIncluded)
        XCTAssertFalse(payload.metadataFlags.deviceInfoIncluded)
    }

    /// Test with maximum privacy settings (all precise/full)
    func testBuild_AllPreciseSettings_MaximalPayload() async {
        let maximalSettings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .precise,
            timestampLevel: .exact,
            deviceInfoLevel: .full
        )

        let payload = await HashOnlyPayloadBuilder.build(
            from: sampleCaptureData,
            privacySettings: maximalSettings,
            depthAnalysis: sampleDepthAnalysis
        )

        XCTAssertNotNil(payload.metadata.location)
        XCTAssertNotNil(payload.metadata.timestamp)
        XCTAssertNotNil(payload.metadata.deviceModel)
        XCTAssertTrue(payload.metadataFlags.locationIncluded)
        XCTAssertTrue(payload.metadataFlags.timestampIncluded)
        XCTAssertTrue(payload.metadataFlags.deviceInfoIncluded)
    }
}
