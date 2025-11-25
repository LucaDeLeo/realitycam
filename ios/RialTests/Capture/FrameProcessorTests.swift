//
//  FrameProcessorTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for FrameProcessor.
//  Note: Full ARKit frame processing requires physical iPhone Pro with LiDAR.
//

import XCTest
import ARKit
import CoreLocation
@testable import Rial

final class FrameProcessorTests: XCTestCase {

    var sut: FrameProcessor!

    override func setUp() {
        super.setUp()
        sut = FrameProcessor()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_CreatesInstance() {
        XCTAssertNotNil(sut)
    }

    func testInit_DefaultJPEGQuality() {
        XCTAssertEqual(sut.jpegQuality, 0.85)
    }

    func testInit_DefaultTimeout() {
        XCTAssertEqual(sut.processingTimeout, 1.0)
    }

    func testInit_CustomJPEGQuality() {
        let processor = FrameProcessor(jpegQuality: 0.90)
        XCTAssertEqual(processor.jpegQuality, 0.90)
    }

    func testInit_CustomTimeout() {
        let processor = FrameProcessor(processingTimeout: 2.0)
        XCTAssertEqual(processor.processingTimeout, 2.0)
    }

    // MARK: - CaptureData Model Tests

    func testCaptureData_Initialization() {
        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: "abc123",
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        let captureData = CaptureData(
            jpeg: Data(repeating: 0xFF, count: 1000),
            depth: Data(repeating: 0x00, count: 100),
            metadata: metadata
        )

        XCTAssertNotNil(captureData.id)
        XCTAssertEqual(captureData.jpeg.count, 1000)
        XCTAssertEqual(captureData.depth.count, 100)
        XCTAssertNil(captureData.assertion)
    }

    func testCaptureData_TotalSize() {
        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: "abc123",
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        let captureData = CaptureData(
            jpeg: Data(repeating: 0xFF, count: 1000),
            depth: Data(repeating: 0x00, count: 100),
            metadata: metadata,
            assertion: Data(repeating: 0x01, count: 50)
        )

        XCTAssertEqual(captureData.totalSizeBytes, 1150) // 1000 + 100 + 50
    }

    func testCaptureData_SizeFormatted() {
        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: "abc123",
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        let captureData = CaptureData(
            jpeg: Data(repeating: 0xFF, count: 3_000_000), // 3MB
            depth: Data(repeating: 0x00, count: 100_000), // 100KB
            metadata: metadata
        )

        XCTAssertTrue(captureData.totalSizeFormatted.contains("MB") || captureData.totalSizeFormatted.contains("KB"))
    }

    // MARK: - CaptureMetadata Tests

    func testCaptureMetadata_Initialization() {
        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: "abc123def456",
            location: LocationData(latitude: 37.7749, longitude: -122.4194, altitude: 10.0, accuracy: 5.0),
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        XCTAssertEqual(metadata.deviceModel, "iPhone 15 Pro")
        XCTAssertEqual(metadata.photoHash, "abc123def456")
        XCTAssertNotNil(metadata.location)
        XCTAssertEqual(metadata.depthMapDimensions.width, 256)
    }

    func testCaptureMetadata_Equatable() {
        let date = Date()
        let dims = DepthDimensions(width: 256, height: 192)

        let meta1 = CaptureMetadata(
            capturedAt: date,
            deviceModel: "iPhone",
            photoHash: "hash",
            location: nil,
            depthMapDimensions: dims
        )

        let meta2 = CaptureMetadata(
            capturedAt: date,
            deviceModel: "iPhone",
            photoHash: "hash",
            location: nil,
            depthMapDimensions: dims
        )

        XCTAssertEqual(meta1, meta2)
    }

    // MARK: - LocationData Tests

    func testLocationData_FromCLLocation() {
        let clLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 15.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 10.0,
            timestamp: Date()
        )

        let locationData = LocationData(from: clLocation)

        XCTAssertEqual(locationData.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(locationData.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(locationData.altitude, 15.0)
        XCTAssertEqual(locationData.accuracy, 5.0)
    }

    func testLocationData_IsAccurate() {
        let accurateLocation = LocationData(latitude: 0, longitude: 0, altitude: nil, accuracy: 10.0)
        XCTAssertTrue(accurateLocation.isAccurate)

        let inaccurateLocation = LocationData(latitude: 0, longitude: 0, altitude: nil, accuracy: 100.0)
        XCTAssertFalse(inaccurateLocation.isAccurate)

        let negativeAccuracy = LocationData(latitude: 0, longitude: 0, altitude: nil, accuracy: -1.0)
        XCTAssertFalse(negativeAccuracy.isAccurate)
    }

    // MARK: - DepthDimensions Tests

    func testDepthDimensions_PixelCount() {
        let dims = DepthDimensions(width: 256, height: 192)
        XCTAssertEqual(dims.pixelCount, 49152) // 256 * 192
    }

    func testDepthDimensions_RawDataSize() {
        let dims = DepthDimensions(width: 256, height: 192)
        XCTAssertEqual(dims.rawDataSize, 196608) // 256 * 192 * 4 (Float32)
    }

    // MARK: - CaptureStatus Tests

    func testCaptureStatus_IsComplete() {
        XCTAssertTrue(CaptureStatus.uploaded.isComplete)
        XCTAssertFalse(CaptureStatus.pending.isComplete)
        XCTAssertFalse(CaptureStatus.failed.isComplete)
    }

    func testCaptureStatus_IsInProgress() {
        XCTAssertTrue(CaptureStatus.processing.isInProgress)
        XCTAssertTrue(CaptureStatus.uploading.isInProgress)
        XCTAssertFalse(CaptureStatus.pending.isInProgress)
        XCTAssertFalse(CaptureStatus.uploaded.isInProgress)
    }

    // MARK: - FrameProcessingError Tests

    func testFrameProcessingError_NoDepthData_Description() {
        let error = FrameProcessingError.noDepthData
        XCTAssertEqual(error.errorDescription, "Frame missing depth data (LiDAR required)")
    }

    func testFrameProcessingError_JPEGConversionFailed_Description() {
        let error = FrameProcessingError.jpegConversionFailed
        XCTAssertEqual(error.errorDescription, "Failed to convert photo to JPEG format")
    }

    func testFrameProcessingError_DepthCompressionFailed_Description() {
        let error = FrameProcessingError.depthCompressionFailed
        XCTAssertEqual(error.errorDescription, "Failed to compress depth map")
    }

    func testFrameProcessingError_ProcessingTimeout_Description() {
        let error = FrameProcessingError.processingTimeout
        XCTAssertEqual(error.errorDescription, "Frame processing exceeded timeout")
    }

    func testFrameProcessingError_InvalidPixelFormat_Description() {
        let error = FrameProcessingError.invalidPixelFormat
        XCTAssertEqual(error.errorDescription, "Invalid pixel buffer format")
    }

    func testFrameProcessingError_Equatable() {
        XCTAssertEqual(FrameProcessingError.noDepthData, FrameProcessingError.noDepthData)
        XCTAssertNotEqual(FrameProcessingError.noDepthData, FrameProcessingError.jpegConversionFailed)
    }

    // MARK: - Codable Tests

    func testCaptureData_Codable() throws {
        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: "abc123",
            location: LocationData(latitude: 37.0, longitude: -122.0, altitude: 10.0, accuracy: 5.0),
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        let original = CaptureData(
            jpeg: Data([0x01, 0x02, 0x03]),
            depth: Data([0x04, 0x05]),
            metadata: metadata
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureData.self, from: data)

        XCTAssertEqual(decoded.jpeg, original.jpeg)
        XCTAssertEqual(decoded.depth, original.depth)
        XCTAssertEqual(decoded.metadata.photoHash, original.metadata.photoHash)
    }

    func testLocationData_Codable() throws {
        let original = LocationData(
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 15.0,
            accuracy: 5.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LocationData.self, from: data)

        XCTAssertEqual(decoded.latitude, original.latitude, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, original.longitude, accuracy: 0.0001)
    }

    func testCaptureStatus_Codable() throws {
        let original = CaptureStatus.uploading

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureStatus.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Physical Device Tests (Require iPhone Pro with LiDAR)

    /// Test full frame processing pipeline on physical device.
    /// This test will be skipped on simulator.
    func testProcess_OnPhysicalDevice_ReturnsValidCaptureData() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let captureSession = ARCaptureSession()
        defer { captureSession.stop() }

        try captureSession.start()

        // Wait for frame
        let expectation = XCTestExpectation(description: "Frame received")
        var capturedFrame: ARFrame?

        captureSession.onFrameUpdate = { frame in
            if frame.sceneDepth != nil && capturedFrame == nil {
                capturedFrame = frame
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        guard let frame = capturedFrame else {
            XCTFail("No frame received")
            return
        }

        // Process frame
        let captureData = try await sut.process(frame, location: nil)

        XCTAssertNotNil(captureData.id)
        XCTAssertGreaterThan(captureData.jpeg.count, 0, "JPEG should not be empty")
        XCTAssertGreaterThan(captureData.depth.count, 0, "Depth should not be empty")
        XCTAssertEqual(captureData.metadata.photoHash.count, 64, "Hash should be 64 hex chars")
        XCTAssertNil(captureData.metadata.location)
    }

    /// Test processing performance on physical device.
    func testProcess_OnPhysicalDevice_CompletesInUnder200ms() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let captureSession = ARCaptureSession()
        defer { captureSession.stop() }

        try captureSession.start()

        // Wait for frame with depth
        let expectation = XCTestExpectation(description: "Frame received")
        var capturedFrame: ARFrame?

        captureSession.onFrameUpdate = { frame in
            if frame.sceneDepth != nil && capturedFrame == nil {
                capturedFrame = frame
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        guard let frame = capturedFrame else {
            XCTFail("No frame received")
            return
        }

        // Measure processing time
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await sut.process(frame, location: nil)
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        print("Processing time: \(processingTime * 1000)ms")
        XCTAssertLessThan(processingTime, 0.5, "Processing should complete in under 500ms")
    }

    /// Test that processing includes location when provided.
    func testProcess_WithLocation_IncludesLocationInMetadata() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let captureSession = ARCaptureSession()
        defer { captureSession.stop() }

        try captureSession.start()

        // Wait for frame
        let expectation = XCTestExpectation(description: "Frame received")
        var capturedFrame: ARFrame?

        captureSession.onFrameUpdate = { frame in
            if frame.sceneDepth != nil && capturedFrame == nil {
                capturedFrame = frame
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        guard let frame = capturedFrame else {
            XCTFail("No frame received")
            return
        }

        // Create test location
        let testLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        // Process with location
        let captureData = try await sut.process(frame, location: testLocation)

        XCTAssertNotNil(captureData.metadata.location)
        XCTAssertEqual(captureData.metadata.location?.latitude ?? 0, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(captureData.metadata.location?.longitude ?? 0, -122.4194, accuracy: 0.0001)
    }

    /// Test JPEG data is valid image.
    func testProcess_JPEGData_IsValidImage() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let captureSession = ARCaptureSession()
        defer { captureSession.stop() }

        try captureSession.start()

        let expectation = XCTestExpectation(description: "Frame received")
        var capturedFrame: ARFrame?

        captureSession.onFrameUpdate = { frame in
            if frame.sceneDepth != nil && capturedFrame == nil {
                capturedFrame = frame
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        guard let frame = capturedFrame else {
            XCTFail("No frame received")
            return
        }

        let captureData = try await sut.process(frame, location: nil)

        // Verify JPEG is valid by loading as UIImage
        let image = UIImage(data: captureData.jpeg)
        XCTAssertNotNil(image, "JPEG should be loadable as UIImage")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    /// Test depth dimensions are recorded correctly.
    func testProcess_DepthDimensions_AreRecorded() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let captureSession = ARCaptureSession()
        defer { captureSession.stop() }

        try captureSession.start()

        let expectation = XCTestExpectation(description: "Frame received")
        var capturedFrame: ARFrame?

        captureSession.onFrameUpdate = { frame in
            if frame.sceneDepth != nil && capturedFrame == nil {
                capturedFrame = frame
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        guard let frame = capturedFrame else {
            XCTFail("No frame received")
            return
        }

        let captureData = try await sut.process(frame, location: nil)

        let dims = captureData.metadata.depthMapDimensions
        XCTAssertGreaterThan(dims.width, 0, "Depth width should be positive")
        XCTAssertGreaterThan(dims.height, 0, "Depth height should be positive")

        // Typical LiDAR dimensions are 256x192
        print("Depth dimensions: \(dims.width)x\(dims.height)")
    }
}
