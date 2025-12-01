//
//  HashOnlyCapturePayloadTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-01.
//
//  Unit tests for HashOnlyCapturePayload model (Story 8-3).
//

import XCTest
@testable import Rial

final class HashOnlyCapturePayloadTests: XCTestCase {

    // MARK: - Test Data

    private var sampleDepthAnalysis: DepthAnalysisResult!
    private var sampleMetadata: FilteredMetadata!
    private var sampleFlags: MetadataFlags!

    override func setUp() {
        super.setUp()
        sampleDepthAnalysis = DepthAnalysisResult(
            depthVariance: 2.4,
            depthLayers: 5,
            edgeCoherence: 0.87,
            minDepth: 0.5,
            maxDepth: 8.0,
            isLikelyRealScene: true
        )
        sampleMetadata = FilteredMetadata(
            location: .coarse(city: "San Francisco", country: "US"),
            timestamp: "2025-12-01T10:30:00Z",
            deviceModel: "iPhone 15 Pro"
        )
        sampleFlags = MetadataFlags(
            locationIncluded: true,
            locationLevel: "coarse",
            timestampIncluded: true,
            timestampLevel: "exact",
            deviceInfoIncluded: true,
            deviceInfoLevel: "model_only"
        )
    }

    // MARK: - Payload Construction Tests (AC #4)

    /// Test that photo payload is constructed with correct captureMode
    func testPhotoPayload_HasCorrectCaptureMode() {
        let payload = HashOnlyCapturePayload(
            mediaHash: "abc123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date()
        )

        XCTAssertEqual(payload.captureMode, "hash_only")
        XCTAssertEqual(payload.mediaType, "photo")
    }

    /// Test that video payload is constructed correctly
    func testVideoPayload_HasCorrectMediaType() {
        let hashChain = PrivacyHashChainData(finalHash: "finalHash123", chainLength: 450)
        let temporalAnalysis = TemporalDepthAnalysisResult(
            keyframeAnalyses: [sampleDepthAnalysis],
            meanVariance: 2.4,
            varianceStability: 0.92,
            temporalCoherence: 0.85,
            isLikelyRealScene: true,
            keyframeCount: 150
        )
        let payload = HashOnlyCapturePayload(
            mediaHash: "abc123",
            temporalDepthAnalysis: temporalAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date(),
            assertion: "",
            hashChain: hashChain,
            frameCount: 450,
            durationMs: 15000
        )

        XCTAssertEqual(payload.captureMode, "hash_only")
        XCTAssertEqual(payload.mediaType, "video")
        XCTAssertEqual(payload.frameCount, 450)
        XCTAssertEqual(payload.durationMs, 15000)
        XCTAssertNotNil(payload.hashChain)
        XCTAssertNotNil(payload.temporalDepthAnalysis)
    }

    /// Test that all required fields are present
    func testPayload_ContainsAllRequiredFields() {
        let capturedAt = Date()
        let payload = HashOnlyCapturePayload(
            mediaHash: "abcdef123456",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: capturedAt,
            assertion: "base64assertion"
        )

        XCTAssertEqual(payload.captureMode, "hash_only")
        XCTAssertEqual(payload.mediaHash, "abcdef123456")
        XCTAssertEqual(payload.mediaType, "photo")
        XCTAssertNotNil(payload.depthAnalysis)
        XCTAssertEqual(payload.depthAnalysis?.depthVariance, 2.4)
        XCTAssertEqual(payload.metadata.deviceModel, "iPhone 15 Pro")
        XCTAssertTrue(payload.metadataFlags.locationIncluded)
        XCTAssertEqual(payload.capturedAt, capturedAt)
        XCTAssertEqual(payload.assertion, "base64assertion")
    }

    // MARK: - Payload Size Tests (AC #6)

    /// Test that payload size is under 10KB
    func testPayload_SizeUnder10KB() {
        // Create a realistic payload
        let mediaHash = String(repeating: "a", count: 64) // SHA-256 hex
        let payload = HashOnlyCapturePayload(
            mediaHash: mediaHash,
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date(),
            assertion: String(repeating: "x", count: 2000) // ~2KB assertion
        )

        let size = payload.serializedSize()
        XCTAssertNotNil(size)
        XCTAssertLessThan(size!, 10 * 1024, "Payload should be under 10KB, got \(size!) bytes")
    }

    /// Test isWithinSizeLimit returns true for valid payload
    func testIsWithinSizeLimit_ValidPayload_ReturnsTrue() {
        let payload = HashOnlyCapturePayload(
            mediaHash: "abc123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date()
        )

        XCTAssertTrue(payload.isWithinSizeLimit())
    }

    /// Test that empty metadata produces smaller payload
    func testPayload_WithEmptyMetadata_IsSmallerSize() {
        let fullPayload = HashOnlyCapturePayload(
            mediaHash: "abc123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date()
        )

        let emptyPayload = HashOnlyCapturePayload(
            mediaHash: "abc123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: .empty,
            metadataFlags: MetadataFlags(
                locationIncluded: false,
                locationLevel: "none",
                timestampIncluded: false,
                timestampLevel: "none",
                deviceInfoIncluded: false,
                deviceInfoLevel: "none"
            ),
            capturedAt: Date()
        )

        let fullSize = fullPayload.serializedSize()!
        let emptySize = emptyPayload.serializedSize()!

        XCTAssertLessThan(emptySize, fullSize, "Empty metadata payload should be smaller")
    }

    // MARK: - JSON Encoding/Decoding Tests

    /// Test JSON round-trip preserves all values
    func testJSON_RoundTrip_PreservesValues() throws {
        let capturedAt = Date()
        let original = HashOnlyCapturePayload(
            mediaHash: "hash123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: capturedAt,
            assertion: "assertion123"
        )

        let jsonData = try original.toJSONData()
        let decoded = try HashOnlyCapturePayload.fromJSONData(jsonData)

        XCTAssertEqual(decoded.captureMode, original.captureMode)
        XCTAssertEqual(decoded.mediaHash, original.mediaHash)
        XCTAssertEqual(decoded.mediaType, original.mediaType)
        XCTAssertNotNil(decoded.depthAnalysis)
        XCTAssertEqual(decoded.depthAnalysis?.depthVariance, original.depthAnalysis?.depthVariance)
        XCTAssertEqual(decoded.metadata.deviceModel, original.metadata.deviceModel)
        XCTAssertEqual(decoded.metadataFlags.locationLevel, original.metadataFlags.locationLevel)
        XCTAssertEqual(decoded.assertion, original.assertion)
    }

    /// Test JSON uses snake_case field names
    func testJSON_UsesSnakeCaseFieldNames() throws {
        let payload = HashOnlyCapturePayload(
            mediaHash: "hash123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date()
        )

        let jsonData = try payload.toJSONData()
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("capture_mode"))
        XCTAssertTrue(jsonString.contains("media_hash"))
        XCTAssertTrue(jsonString.contains("media_type"))
        XCTAssertTrue(jsonString.contains("depth_analysis"))
        XCTAssertTrue(jsonString.contains("metadata_flags"))
        XCTAssertTrue(jsonString.contains("captured_at"))

        // Verify camelCase is NOT used
        XCTAssertFalse(jsonString.contains("\"captureMode\""))
        XCTAssertFalse(jsonString.contains("\"mediaHash\""))
    }

    /// Test JSON encoding is deterministic (sorted keys)
    func testJSON_IsDeterministic() throws {
        let payload = HashOnlyCapturePayload(
            mediaHash: "hash123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date()
        )

        let json1 = try payload.toJSONData()
        let json2 = try payload.toJSONData()

        XCTAssertEqual(json1, json2, "JSON encoding should be deterministic")
    }

    // MARK: - Equatable Tests

    /// Test that identical payloads are equal
    func testEquatable_IdenticalPayloads_AreEqual() {
        let date = Date()
        let payload1 = HashOnlyCapturePayload(
            mediaHash: "hash123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: date,
            assertion: "assertion"
        )
        let payload2 = HashOnlyCapturePayload(
            mediaHash: "hash123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: date,
            assertion: "assertion"
        )

        XCTAssertEqual(payload1, payload2)
    }

    /// Test that different payloads are not equal
    func testEquatable_DifferentPayloads_AreNotEqual() {
        let date = Date()
        let payload1 = HashOnlyCapturePayload(
            mediaHash: "hash123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: date
        )
        let payload2 = HashOnlyCapturePayload(
            mediaHash: "differentHash",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: date
        )

        XCTAssertNotEqual(payload1, payload2)
    }

    // MARK: - Description Tests

    /// Test that description contains key fields
    func testDescription_ContainsKeyFields() {
        let payload = HashOnlyCapturePayload(
            mediaHash: "hash123",
            depthAnalysis: sampleDepthAnalysis,
            metadata: sampleMetadata,
            metadataFlags: sampleFlags,
            capturedAt: Date()
        )

        let description = payload.description

        XCTAssertTrue(description.contains("hash_only"))
        XCTAssertTrue(description.contains("photo"))
        XCTAssertTrue(description.contains("hash123"))
    }
}

// MARK: - FilteredMetadata Tests

final class FilteredMetadataTests: XCTestCase {

    /// Test empty metadata has all nil fields
    func testEmpty_HasAllNilFields() {
        let empty = FilteredMetadata.empty

        XCTAssertNil(empty.location)
        XCTAssertNil(empty.timestamp)
        XCTAssertNil(empty.deviceModel)
    }

    /// Test creating metadata with all fields
    func testInit_WithAllFields() {
        let metadata = FilteredMetadata(
            location: .precise(latitude: 37.7749, longitude: -122.4194),
            timestamp: "2025-12-01T10:30:00Z",
            deviceModel: "iPhone 15 Pro"
        )

        XCTAssertNotNil(metadata.location)
        XCTAssertEqual(metadata.timestamp, "2025-12-01T10:30:00Z")
        XCTAssertEqual(metadata.deviceModel, "iPhone 15 Pro")
    }

    /// Test JSON encoding/decoding
    func testCodable_RoundTrip() throws {
        let original = FilteredMetadata(
            location: .coarse(city: "San Francisco", country: "US"),
            timestamp: "2025-12-01",
            deviceModel: "iPhone 15 Pro / iOS 18.1 / 1.0.0"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilteredMetadata.self, from: data)

        XCTAssertEqual(decoded.location?.city, original.location?.city)
        XCTAssertEqual(decoded.location?.country, original.location?.country)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.deviceModel, original.deviceModel)
    }
}

// MARK: - FilteredLocation Tests

final class FilteredLocationTests: XCTestCase {

    /// Test coarse location factory
    func testCoarse_CreatesCorrectLocation() {
        let location = FilteredLocation.coarse(city: "San Francisco", country: "US")

        XCTAssertEqual(location.city, "San Francisco")
        XCTAssertEqual(location.country, "US")
        XCTAssertNil(location.latitude)
        XCTAssertNil(location.longitude)
    }

    /// Test precise location factory
    func testPrecise_CreatesCorrectLocation() {
        let location = FilteredLocation.precise(latitude: 37.7749, longitude: -122.4194)

        XCTAssertNil(location.city)
        XCTAssertNil(location.country)
        XCTAssertEqual(location.latitude, 37.7749)
        XCTAssertEqual(location.longitude, -122.4194)
    }

    /// Test JSON encoding/decoding for coarse location
    func testCodable_CoarseLocation_RoundTrip() throws {
        let original = FilteredLocation.coarse(city: "London", country: "GB")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilteredLocation.self, from: data)

        XCTAssertEqual(decoded.city, original.city)
        XCTAssertEqual(decoded.country, original.country)
    }

    /// Test JSON encoding/decoding for precise location
    func testCodable_PreciseLocation_RoundTrip() throws {
        let original = FilteredLocation.precise(latitude: 51.5074, longitude: -0.1278)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilteredLocation.self, from: data)

        XCTAssertEqual(decoded.latitude, original.latitude)
        XCTAssertEqual(decoded.longitude, original.longitude)
    }
}

// MARK: - MetadataFlags Tests

final class MetadataFlagsTests: XCTestCase {

    /// Test creating flags from PrivacySettings
    func testFrom_PrivacySettings_CreatesCorrectFlags() {
        let settings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .coarse,
            timestampLevel: .dayOnly,
            deviceInfoLevel: .modelOnly
        )

        let flags = MetadataFlags.from(settings: settings)

        XCTAssertTrue(flags.locationIncluded)
        XCTAssertEqual(flags.locationLevel, "coarse")
        XCTAssertTrue(flags.timestampIncluded)
        XCTAssertEqual(flags.timestampLevel, "day_only")
        XCTAssertTrue(flags.deviceInfoIncluded)
        XCTAssertEqual(flags.deviceInfoLevel, "model_only")
    }

    /// Test flags when all levels are none
    func testFrom_AllNoneLevels_FlagsShowNotIncluded() {
        let settings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .none,
            timestampLevel: .none,
            deviceInfoLevel: .none
        )

        let flags = MetadataFlags.from(settings: settings)

        XCTAssertFalse(flags.locationIncluded)
        XCTAssertEqual(flags.locationLevel, "none")
        XCTAssertFalse(flags.timestampIncluded)
        XCTAssertEqual(flags.timestampLevel, "none")
        XCTAssertFalse(flags.deviceInfoIncluded)
        XCTAssertEqual(flags.deviceInfoLevel, "none")
    }

    /// Test JSON uses snake_case keys
    func testJSON_UsesSnakeCaseKeys() throws {
        let flags = MetadataFlags(
            locationIncluded: true,
            locationLevel: "precise",
            timestampIncluded: true,
            timestampLevel: "exact",
            deviceInfoIncluded: true,
            deviceInfoLevel: "full"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(flags)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("location_included"))
        XCTAssertTrue(jsonString.contains("location_level"))
        XCTAssertTrue(jsonString.contains("timestamp_included"))
        XCTAssertTrue(jsonString.contains("timestamp_level"))
        XCTAssertTrue(jsonString.contains("device_info_included"))
        XCTAssertTrue(jsonString.contains("device_info_level"))
    }
}

// MARK: - PrivacyHashChainData Tests

final class PrivacyHashChainDataTests: XCTestCase {

    /// Test creating hash chain data
    func testInit_CreatesCorrectData() {
        let hashChain = PrivacyHashChainData(finalHash: "abc123", chainLength: 450, version: "1.0")

        XCTAssertEqual(hashChain.finalHash, "abc123")
        XCTAssertEqual(hashChain.chainLength, 450)
        XCTAssertEqual(hashChain.version, "1.0")
    }

    /// Test default version
    func testInit_DefaultVersion() {
        let hashChain = PrivacyHashChainData(finalHash: "abc123", chainLength: 100)

        XCTAssertEqual(hashChain.version, "1.0")
    }

    /// Test JSON uses snake_case keys
    func testJSON_UsesSnakeCaseKeys() throws {
        let hashChain = PrivacyHashChainData(finalHash: "abc123", chainLength: 450)

        let encoder = JSONEncoder()
        let data = try encoder.encode(hashChain)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("final_hash"))
        XCTAssertTrue(jsonString.contains("chain_length"))
    }
}
