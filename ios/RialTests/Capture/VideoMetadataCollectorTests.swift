//
//  VideoMetadataCollectorTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-27.
//
//  Unit tests for VideoMetadataCollector and VideoMetadata.
//

import XCTest
import CoreLocation
@testable import Rial

final class VideoMetadataCollectorTests: XCTestCase {

    // MARK: - Properties

    var sut: VideoMetadataCollector!
    var mockLocationManager: CLLocationManager!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        mockLocationManager = CLLocationManager()
        sut = VideoMetadataCollector(locationManager: mockLocationManager)
    }

    override func tearDown() {
        sut = nil
        mockLocationManager = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    /// Creates sample test data for recording ended.
    private func createSampleRecordingEndParams() -> (
        frameCount: Int,
        depthKeyframeCount: Int,
        resolution: Resolution,
        codec: String,
        hashChainFinal: Data,
        assertion: Data,
        attestationLevel: String
    ) {
        return (
            frameCount: 450,
            depthKeyframeCount: 150,
            resolution: Resolution(width: 1920, height: 1080),
            codec: "hevc",
            hashChainFinal: Data([0x01, 0x02, 0x03, 0x04] + Array(repeating: UInt8(0), count: 28)),
            assertion: Data([0x10, 0x20, 0x30, 0x40]),
            attestationLevel: "secure_enclave"
        )
    }

    // MARK: - Initialization Tests

    func testInit_CreatesInstance() {
        XCTAssertNotNil(sut, "VideoMetadataCollector should initialize")
    }

    func testInit_HasNotStarted() {
        XCTAssertFalse(sut.hasStarted, "Should not have started initially")
    }

    func testInit_RecordedStartTimeIsNil() {
        XCTAssertNil(sut.recordedStartTime, "Recorded start time should be nil initially")
    }

    func testInit_RecordedStartLocationIsNil() {
        XCTAssertNil(sut.recordedStartLocation, "Recorded start location should be nil initially")
    }

    // MARK: - Recording Started Tests

    func testRecordingStarted_CapturesStartTimestamp() {
        let beforeStart = Date()

        sut.recordingStarted()

        let afterStart = Date()
        XCTAssertTrue(sut.hasStarted, "Should have started after recordingStarted()")

        guard let recordedTime = sut.recordedStartTime else {
            XCTFail("Recorded start time should not be nil")
            return
        }

        XCTAssertGreaterThanOrEqual(recordedTime, beforeStart, "Start time should be >= before call")
        XCTAssertLessThanOrEqual(recordedTime, afterStart, "Start time should be <= after call")
    }

    func testRecordingStarted_LocationIsNilWhenNotAuthorized() {
        // Default CLLocationManager won't have location without authorization
        sut.recordingStarted()

        // Location may or may not be available depending on device state
        // This test verifies the collector doesn't crash without location
        XCTAssertTrue(sut.hasStarted, "Should start even without location")
    }

    // MARK: - Recording Ended Tests

    func testRecordingEnded_CreatesCompleteVideoMetadata() {
        sut.recordingStarted()
        let params = createSampleRecordingEndParams()

        let metadata = sut.recordingEnded(
            frameCount: params.frameCount,
            depthKeyframeCount: params.depthKeyframeCount,
            resolution: params.resolution,
            codec: params.codec,
            hashChainFinal: params.hashChainFinal,
            assertion: params.assertion,
            attestationLevel: params.attestationLevel
        )

        XCTAssertEqual(metadata.type, "video")
        XCTAssertEqual(metadata.frameCount, 450)
        XCTAssertEqual(metadata.depthKeyframeCount, 150)
        XCTAssertEqual(metadata.resolution.width, 1920)
        XCTAssertEqual(metadata.resolution.height, 1080)
        XCTAssertEqual(metadata.codec, "hevc")
        XCTAssertEqual(metadata.attestationLevel, "secure_enclave")
    }

    func testRecordingEnded_DurationMsCalculationIsAccurate() {
        sut.recordingStarted()

        // Wait a small amount of time
        let waitTime: UInt32 = 100_000  // 100ms in microseconds
        usleep(waitTime)

        let params = createSampleRecordingEndParams()
        let metadata = sut.recordingEnded(
            frameCount: params.frameCount,
            depthKeyframeCount: params.depthKeyframeCount,
            resolution: params.resolution,
            codec: params.codec,
            hashChainFinal: params.hashChainFinal,
            assertion: params.assertion,
            attestationLevel: params.attestationLevel
        )

        // Duration should be at least 100ms (with some tolerance)
        XCTAssertGreaterThanOrEqual(metadata.durationMs, 80, "Duration should be at least ~100ms")
        XCTAssertLessThan(metadata.durationMs, 500, "Duration should not be unreasonably long")
    }

    func testRecordingEnded_HashChainFinalIsBase64Encoded() {
        sut.recordingStarted()
        let params = createSampleRecordingEndParams()

        let metadata = sut.recordingEnded(
            frameCount: params.frameCount,
            depthKeyframeCount: params.depthKeyframeCount,
            resolution: params.resolution,
            codec: params.codec,
            hashChainFinal: params.hashChainFinal,
            assertion: params.assertion,
            attestationLevel: params.attestationLevel
        )

        // Verify base64 encoding
        let expectedBase64 = params.hashChainFinal.base64EncodedString()
        XCTAssertEqual(metadata.hashChainFinal, expectedBase64)

        // Verify we can decode back
        guard let decoded = Data(base64Encoded: metadata.hashChainFinal) else {
            XCTFail("Should be able to decode base64 hash chain final")
            return
        }
        XCTAssertEqual(decoded, params.hashChainFinal)
    }

    func testRecordingEnded_AssertionIsBase64Encoded() {
        sut.recordingStarted()
        let params = createSampleRecordingEndParams()

        let metadata = sut.recordingEnded(
            frameCount: params.frameCount,
            depthKeyframeCount: params.depthKeyframeCount,
            resolution: params.resolution,
            codec: params.codec,
            hashChainFinal: params.hashChainFinal,
            assertion: params.assertion,
            attestationLevel: params.attestationLevel
        )

        // Verify base64 encoding
        let expectedBase64 = params.assertion.base64EncodedString()
        XCTAssertEqual(metadata.assertion, expectedBase64)

        // Verify we can decode back
        guard let decoded = Data(base64Encoded: metadata.assertion) else {
            XCTFail("Should be able to decode base64 assertion")
            return
        }
        XCTAssertEqual(decoded, params.assertion)
    }

    func testRecordingEnded_CodecIsLowercase() {
        sut.recordingStarted()
        let params = createSampleRecordingEndParams()

        // Pass uppercase codec
        let metadata = sut.recordingEnded(
            frameCount: params.frameCount,
            depthKeyframeCount: params.depthKeyframeCount,
            resolution: params.resolution,
            codec: "HEVC",  // Uppercase
            hashChainFinal: params.hashChainFinal,
            assertion: params.assertion,
            attestationLevel: params.attestationLevel
        )

        XCTAssertEqual(metadata.codec, "hevc", "Codec should be lowercased")
    }

    // MARK: - Device Information Tests

    func testGetDeviceModel_ReturnsValidString() {
        let model = sut.getDeviceModel()

        XCTAssertFalse(model.isEmpty, "Device model should not be empty")
        // On simulator, this will be "iPhone" or similar
        XCTAssertTrue(model.contains("iPhone") || model.contains("iPad") || model.contains("Mac"),
                      "Device model should contain device type")
    }

    func testGetIOSVersion_ReturnsValidString() {
        let version = sut.getIOSVersion()

        XCTAssertFalse(version.isEmpty, "iOS version should not be empty")
        XCTAssertTrue(version.contains("Version") || version.contains("."),
                      "iOS version should contain version info")
    }

    func testRecordingEnded_IncludesDeviceModel() {
        sut.recordingStarted()
        let params = createSampleRecordingEndParams()

        let metadata = sut.recordingEnded(
            frameCount: params.frameCount,
            depthKeyframeCount: params.depthKeyframeCount,
            resolution: params.resolution,
            codec: params.codec,
            hashChainFinal: params.hashChainFinal,
            assertion: params.assertion,
            attestationLevel: params.attestationLevel
        )

        XCTAssertFalse(metadata.deviceModel.isEmpty, "Device model should be included")
        XCTAssertEqual(metadata.deviceModel, sut.getDeviceModel())
    }

    func testRecordingEnded_IncludesIOSVersion() {
        sut.recordingStarted()
        let params = createSampleRecordingEndParams()

        let metadata = sut.recordingEnded(
            frameCount: params.frameCount,
            depthKeyframeCount: params.depthKeyframeCount,
            resolution: params.resolution,
            codec: params.codec,
            hashChainFinal: params.hashChainFinal,
            assertion: params.assertion,
            attestationLevel: params.attestationLevel
        )

        XCTAssertFalse(metadata.iosVersion.isEmpty, "iOS version should be included")
        XCTAssertEqual(metadata.iosVersion, sut.getIOSVersion())
    }

    // MARK: - Reset Tests

    func testReset_ClearsInternalState() {
        sut.recordingStarted()
        XCTAssertTrue(sut.hasStarted, "Should have started")

        sut.reset()

        XCTAssertFalse(sut.hasStarted, "Should not have started after reset")
        XCTAssertNil(sut.recordedStartTime, "Start time should be nil after reset")
        XCTAssertNil(sut.recordedStartLocation, "Start location should be nil after reset")
    }

    func testReset_AllowsNewRecording() {
        // First recording
        sut.recordingStarted()
        let firstStartTime = sut.recordedStartTime

        // Reset
        sut.reset()

        // Wait a bit
        usleep(10_000)

        // Second recording
        sut.recordingStarted()
        let secondStartTime = sut.recordedStartTime

        XCTAssertNotNil(secondStartTime, "Second recording should have start time")
        XCTAssertNotEqual(firstStartTime, secondStartTime, "Second recording should have different start time")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAccess_ThreadSafe() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { iteration in
            if iteration % 3 == 0 {
                self.sut.recordingStarted()
            } else if iteration % 3 == 1 {
                _ = self.sut.hasStarted
            } else {
                self.sut.reset()
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - VideoMetadata Tests

final class VideoMetadataTests: XCTestCase {

    // MARK: - Test Helpers

    private func createSampleVideoMetadata() -> VideoMetadata {
        VideoMetadata(
            type: "video",
            startedAt: Date(timeIntervalSince1970: 1732700000),
            endedAt: Date(timeIntervalSince1970: 1732700015),
            durationMs: 15000,
            frameCount: 450,
            depthKeyframeCount: 150,
            resolution: Resolution(width: 1920, height: 1080),
            codec: "hevc",
            deviceModel: "iPhone 15 Pro",
            iosVersion: "Version 17.4 (Build 21E219)",
            location: CaptureLocation(lat: 37.7749, lng: -122.4194),
            attestationLevel: "secure_enclave",
            hashChainFinal: "dGVzdGhhc2g=",
            assertion: "dGVzdGFzc2VydGlvbg=="
        )
    }

    // MARK: - Codable Tests

    func testVideoMetadata_Codable_RoundTrip() throws {
        let original = createSampleVideoMetadata()

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VideoMetadata.self, from: data)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.durationMs, original.durationMs)
        XCTAssertEqual(decoded.frameCount, original.frameCount)
        XCTAssertEqual(decoded.depthKeyframeCount, original.depthKeyframeCount)
        XCTAssertEqual(decoded.resolution, original.resolution)
        XCTAssertEqual(decoded.codec, original.codec)
        XCTAssertEqual(decoded.deviceModel, original.deviceModel)
        XCTAssertEqual(decoded.iosVersion, original.iosVersion)
        XCTAssertEqual(decoded.location, original.location)
        XCTAssertEqual(decoded.attestationLevel, original.attestationLevel)
        XCTAssertEqual(decoded.hashChainFinal, original.hashChainFinal)
        XCTAssertEqual(decoded.assertion, original.assertion)
    }

    func testVideoMetadata_JSONSerializationProducesSnakeCaseKeys() throws {
        let metadata = createSampleVideoMetadata()

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to convert JSON data to string")
            return
        }

        // Verify snake_case keys are present
        XCTAssertTrue(jsonString.contains("\"started_at\""), "JSON should contain started_at key")
        XCTAssertTrue(jsonString.contains("\"ended_at\""), "JSON should contain ended_at key")
        XCTAssertTrue(jsonString.contains("\"duration_ms\""), "JSON should contain duration_ms key")
        XCTAssertTrue(jsonString.contains("\"frame_count\""), "JSON should contain frame_count key")
        XCTAssertTrue(jsonString.contains("\"depth_keyframe_count\""), "JSON should contain depth_keyframe_count key")
        XCTAssertTrue(jsonString.contains("\"device_model\""), "JSON should contain device_model key")
        XCTAssertTrue(jsonString.contains("\"ios_version\""), "JSON should contain ios_version key")
        XCTAssertTrue(jsonString.contains("\"attestation_level\""), "JSON should contain attestation_level key")
        XCTAssertTrue(jsonString.contains("\"hash_chain_final\""), "JSON should contain hash_chain_final key")

        // Verify camelCase keys are NOT present
        XCTAssertFalse(jsonString.contains("\"startedAt\""), "JSON should NOT contain startedAt key")
        XCTAssertFalse(jsonString.contains("\"endedAt\""), "JSON should NOT contain endedAt key")
        XCTAssertFalse(jsonString.contains("\"durationMs\""), "JSON should NOT contain durationMs key")
        XCTAssertFalse(jsonString.contains("\"frameCount\""), "JSON should NOT contain frameCount key")
        XCTAssertFalse(jsonString.contains("\"depthKeyframeCount\""), "JSON should NOT contain depthKeyframeCount key")
        XCTAssertFalse(jsonString.contains("\"deviceModel\""), "JSON should NOT contain deviceModel key")
        XCTAssertFalse(jsonString.contains("\"iosVersion\""), "JSON should NOT contain iosVersion key")
        XCTAssertFalse(jsonString.contains("\"attestationLevel\""), "JSON should NOT contain attestationLevel key")
        XCTAssertFalse(jsonString.contains("\"hashChainFinal\""), "JSON should NOT contain hashChainFinal key")
    }

    func testVideoMetadata_DatesAreISO8601Formatted() throws {
        let metadata = createSampleVideoMetadata()

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to convert JSON data to string")
            return
        }

        // ISO 8601 format should contain "T" and "Z" or timezone offset
        XCTAssertTrue(jsonString.contains("T"), "Date should be ISO 8601 format with T separator")
        XCTAssertTrue(jsonString.contains("Z") || jsonString.contains("+") || jsonString.contains("-"),
                      "Date should have timezone indicator")
    }

    func testVideoMetadata_LocationIsOptional() throws {
        let metadataWithoutLocation = VideoMetadata(
            type: "video",
            startedAt: Date(),
            endedAt: Date(),
            durationMs: 15000,
            frameCount: 450,
            depthKeyframeCount: 150,
            resolution: Resolution(width: 1920, height: 1080),
            codec: "hevc",
            deviceModel: "iPhone 15 Pro",
            iosVersion: "17.4",
            location: nil,  // No location
            attestationLevel: "secure_enclave",
            hashChainFinal: "dGVzdA==",
            assertion: "dGVzdA=="
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadataWithoutLocation)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VideoMetadata.self, from: data)

        XCTAssertNil(decoded.location, "Location should be nil when not provided")
    }

    // MARK: - Equatable Tests

    func testVideoMetadata_Equatable_SameValues() {
        let metadata1 = createSampleVideoMetadata()
        let metadata2 = createSampleVideoMetadata()

        XCTAssertEqual(metadata1, metadata2, "Identical metadata should be equal")
    }

    func testVideoMetadata_Equatable_DifferentValues() {
        let metadata1 = createSampleVideoMetadata()
        let metadata2 = VideoMetadata(
            type: "video",
            startedAt: Date(),
            endedAt: Date(),
            durationMs: 10000,  // Different
            frameCount: 300,    // Different
            depthKeyframeCount: 100,
            resolution: Resolution(width: 1920, height: 1080),
            codec: "hevc",
            deviceModel: "iPhone 15 Pro",
            iosVersion: "17.4",
            location: nil,
            attestationLevel: "secure_enclave",
            hashChainFinal: "dGVzdA==",
            assertion: "dGVzdA=="
        )

        XCTAssertNotEqual(metadata1, metadata2, "Different metadata should not be equal")
    }
}

// MARK: - Resolution Tests

final class ResolutionTests: XCTestCase {

    func testResolution_Init() {
        let resolution = Resolution(width: 1920, height: 1080)

        XCTAssertEqual(resolution.width, 1920)
        XCTAssertEqual(resolution.height, 1080)
    }

    func testResolution_PixelCount() {
        let resolution = Resolution(width: 1920, height: 1080)

        XCTAssertEqual(resolution.pixelCount, 1920 * 1080)
    }

    func testResolution_AspectRatio() {
        let resolution = Resolution(width: 1920, height: 1080)

        XCTAssertEqual(resolution.aspectRatio, 1920.0 / 1080.0, accuracy: 0.001)
    }

    func testResolution_AspectRatio_ZeroHeight() {
        let resolution = Resolution(width: 1920, height: 0)

        XCTAssertEqual(resolution.aspectRatio, 0, "Aspect ratio should be 0 for zero height")
    }

    func testResolution_Description() {
        let resolution = Resolution(width: 1920, height: 1080)

        XCTAssertEqual(resolution.description, "1920x1080")
    }

    func testResolution_Codable() throws {
        let resolution = Resolution(width: 1920, height: 1080)

        let encoder = JSONEncoder()
        let data = try encoder.encode(resolution)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Resolution.self, from: data)

        XCTAssertEqual(decoded, resolution)
    }

    func testResolution_Equatable() {
        let resolution1 = Resolution(width: 1920, height: 1080)
        let resolution2 = Resolution(width: 1920, height: 1080)
        let resolution3 = Resolution(width: 1280, height: 720)

        XCTAssertEqual(resolution1, resolution2)
        XCTAssertNotEqual(resolution1, resolution3)
    }
}

// MARK: - CaptureLocation Tests

final class CaptureLocationTests: XCTestCase {

    func testCaptureLocation_Init() {
        let location = CaptureLocation(lat: 37.7749, lng: -122.4194)

        XCTAssertEqual(location.lat, 37.7749)
        XCTAssertEqual(location.lng, -122.4194)
    }

    func testCaptureLocation_InitFromCLLocation() {
        let clLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let location = CaptureLocation(from: clLocation)

        XCTAssertEqual(location.lat, 37.7749)
        XCTAssertEqual(location.lng, -122.4194)
    }

    func testCaptureLocation_IsValid_ValidCoordinates() {
        let location = CaptureLocation(lat: 37.7749, lng: -122.4194)

        XCTAssertTrue(location.isValid, "Valid coordinates should be valid")
    }

    func testCaptureLocation_IsValid_InvalidLatitude() {
        let location = CaptureLocation(lat: 91.0, lng: -122.4194)

        XCTAssertFalse(location.isValid, "Latitude > 90 should be invalid")
    }

    func testCaptureLocation_IsValid_InvalidLongitude() {
        let location = CaptureLocation(lat: 37.7749, lng: -181.0)

        XCTAssertFalse(location.isValid, "Longitude < -180 should be invalid")
    }

    func testCaptureLocation_Codable() throws {
        let location = CaptureLocation(lat: 37.7749, lng: -122.4194)

        let encoder = JSONEncoder()
        let data = try encoder.encode(location)

        // Verify JSON uses lat/lng keys
        guard let jsonString = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to convert to string")
            return
        }
        XCTAssertTrue(jsonString.contains("\"lat\""), "Should use lat key")
        XCTAssertTrue(jsonString.contains("\"lng\""), "Should use lng key")

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureLocation.self, from: data)

        XCTAssertEqual(decoded, location)
    }

    func testCaptureLocation_Equatable() {
        let location1 = CaptureLocation(lat: 37.7749, lng: -122.4194)
        let location2 = CaptureLocation(lat: 37.7749, lng: -122.4194)
        let location3 = CaptureLocation(lat: 40.7128, lng: -74.0060)

        XCTAssertEqual(location1, location2)
        XCTAssertNotEqual(location1, location3)
    }
}

// MARK: - Integration Tests (Device Only)

final class VideoMetadataCollectorIntegrationTests: XCTestCase {

    func testFullRecordingFlow_OnPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Integration test requires physical device with location services")
        #else
        // This test requires physical device with location permissions
        let collector = VideoMetadataCollector()

        // Start recording
        collector.recordingStarted()

        // Simulate recording duration
        usleep(200_000)  // 200ms

        // End recording
        let metadata = collector.recordingEnded(
            frameCount: 6,
            depthKeyframeCount: 2,
            resolution: Resolution(width: 1920, height: 1080),
            codec: "hevc",
            hashChainFinal: Data(repeating: 0x42, count: 32),
            assertion: Data(repeating: 0x24, count: 64),
            attestationLevel: "secure_enclave"
        )

        // Verify all fields
        XCTAssertEqual(metadata.type, "video")
        XCTAssertGreaterThanOrEqual(metadata.durationMs, 150)
        XCTAssertEqual(metadata.frameCount, 6)
        XCTAssertEqual(metadata.depthKeyframeCount, 2)
        XCTAssertEqual(metadata.resolution.width, 1920)
        XCTAssertEqual(metadata.resolution.height, 1080)
        XCTAssertEqual(metadata.codec, "hevc")
        XCTAssertFalse(metadata.deviceModel.isEmpty)
        XCTAssertFalse(metadata.iosVersion.isEmpty)
        XCTAssertEqual(metadata.attestationLevel, "secure_enclave")
        XCTAssertFalse(metadata.hashChainFinal.isEmpty)
        XCTAssertFalse(metadata.assertion.isEmpty)

        // Verify dates are reasonable
        XCTAssertLessThanOrEqual(metadata.startedAt, metadata.endedAt)
        #endif
    }

    func testMetadataJSONStructure_MatchesBackendExpectations() throws {
        let collector = VideoMetadataCollector()
        collector.recordingStarted()

        let metadata = collector.recordingEnded(
            frameCount: 450,
            depthKeyframeCount: 150,
            resolution: Resolution(width: 1920, height: 1080),
            codec: "hevc",
            hashChainFinal: Data(repeating: 0x01, count: 32),
            assertion: Data(repeating: 0x02, count: 64),
            attestationLevel: "secure_enclave"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(metadata)

        // Parse as dictionary to verify structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse JSON")
            return
        }

        // Verify required keys exist
        XCTAssertNotNil(json["type"])
        XCTAssertNotNil(json["started_at"])
        XCTAssertNotNil(json["ended_at"])
        XCTAssertNotNil(json["duration_ms"])
        XCTAssertNotNil(json["frame_count"])
        XCTAssertNotNil(json["depth_keyframe_count"])
        XCTAssertNotNil(json["resolution"])
        XCTAssertNotNil(json["codec"])
        XCTAssertNotNil(json["device_model"])
        XCTAssertNotNil(json["ios_version"])
        XCTAssertNotNil(json["attestation_level"])
        XCTAssertNotNil(json["hash_chain_final"])
        XCTAssertNotNil(json["assertion"])

        // Verify types
        XCTAssertEqual(json["type"] as? String, "video")
        XCTAssertEqual(json["frame_count"] as? Int, 450)
        XCTAssertEqual(json["depth_keyframe_count"] as? Int, 150)
        XCTAssertEqual(json["codec"] as? String, "hevc")
        XCTAssertEqual(json["attestation_level"] as? String, "secure_enclave")

        // Verify resolution is nested object
        guard let resolution = json["resolution"] as? [String: Any] else {
            XCTFail("Resolution should be a dictionary")
            return
        }
        XCTAssertEqual(resolution["width"] as? Int, 1920)
        XCTAssertEqual(resolution["height"] as? Int, 1080)

        // Verify dates are strings (ISO 8601)
        XCTAssertTrue(json["started_at"] is String)
        XCTAssertTrue(json["ended_at"] is String)
    }
}
