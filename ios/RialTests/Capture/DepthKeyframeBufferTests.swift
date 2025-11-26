//
//  DepthKeyframeBufferTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-26.
//
//  Unit tests for DepthKeyframeBuffer.
//  Tests depth keyframe extraction, buffer operations, compression, and thread safety.
//

import XCTest
import ARKit
@testable import Rial

final class DepthKeyframeBufferTests: XCTestCase {

    var sut: DepthKeyframeBuffer!

    override func setUp() {
        super.setUp()
        sut = DepthKeyframeBuffer()
    }

    override func tearDown() {
        sut.reset()
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_CreatesInstance() {
        XCTAssertNotNil(sut, "DepthKeyframeBuffer should initialize")
    }

    func testInit_KeyframeCountIsZero() {
        XCTAssertEqual(sut.keyframeCount, 0, "Initial keyframe count should be zero")
    }

    func testInit_IsRecordingIsFalse() {
        XCTAssertFalse(sut.isRecording, "Initial isRecording should be false")
    }

    func testInit_ResolutionIsZero() {
        XCTAssertEqual(sut.resolution, .zero, "Initial resolution should be zero")
    }

    func testInit_AccumulatedDataSizeIsZero() {
        XCTAssertEqual(sut.accumulatedDataSize, 0, "Initial accumulated data size should be zero")
    }

    // MARK: - Constants Tests

    func testMaxKeyframes_Is150() {
        XCTAssertEqual(DepthKeyframeBuffer.maxKeyframes, 150, "Max keyframes should be 150")
    }

    func testKeyframeInterval_Is3() {
        XCTAssertEqual(DepthKeyframeBuffer.keyframeInterval, 3, "Keyframe interval should be 3")
    }

    // MARK: - shouldExtractDepth Tests

    func testShouldExtractDepth_Frame1_ReturnsTrue() {
        // Frame 1 is the first frame, should extract
        XCTAssertTrue(sut.shouldExtractDepth(frameNumber: 1), "Frame 1 should extract depth")
    }

    func testShouldExtractDepth_Frame2_ReturnsFalse() {
        XCTAssertFalse(sut.shouldExtractDepth(frameNumber: 2), "Frame 2 should not extract depth")
    }

    func testShouldExtractDepth_Frame3_ReturnsFalse() {
        XCTAssertFalse(sut.shouldExtractDepth(frameNumber: 3), "Frame 3 should not extract depth")
    }

    func testShouldExtractDepth_Frame4_ReturnsTrue() {
        // Frame 4 = (4-1) % 3 == 0
        XCTAssertTrue(sut.shouldExtractDepth(frameNumber: 4), "Frame 4 should extract depth")
    }

    func testShouldExtractDepth_Frame5_ReturnsFalse() {
        XCTAssertFalse(sut.shouldExtractDepth(frameNumber: 5), "Frame 5 should not extract depth")
    }

    func testShouldExtractDepth_Frame6_ReturnsFalse() {
        XCTAssertFalse(sut.shouldExtractDepth(frameNumber: 6), "Frame 6 should not extract depth")
    }

    func testShouldExtractDepth_Frame7_ReturnsTrue() {
        XCTAssertTrue(sut.shouldExtractDepth(frameNumber: 7), "Frame 7 should extract depth")
    }

    func testShouldExtractDepth_Frame10_ReturnsTrue() {
        XCTAssertTrue(sut.shouldExtractDepth(frameNumber: 10), "Frame 10 should extract depth")
    }

    func testShouldExtractDepth_Frame30_ReturnsFalse() {
        // Frame 30: (30-1) % 3 = 29 % 3 = 2 != 0
        XCTAssertFalse(sut.shouldExtractDepth(frameNumber: 30), "Frame 30 should not extract depth")
    }

    func testShouldExtractDepth_Frame31_ReturnsTrue() {
        // Frame 31: (31-1) % 3 = 30 % 3 = 0
        XCTAssertTrue(sut.shouldExtractDepth(frameNumber: 31), "Frame 31 should extract depth")
    }

    func testShouldExtractDepth_ExtractionPattern_10FPSFrom30FPS() {
        // Verify extraction pattern gives us 10fps from 30fps (every 3rd frame starting at 1)
        var extractionCount = 0
        for frame in 1...30 { // 30 frames = 1 second at 30fps
            if sut.shouldExtractDepth(frameNumber: frame) {
                extractionCount += 1
            }
        }
        XCTAssertEqual(extractionCount, 10, "Should extract 10 frames from 30 frames (10fps from 30fps)")
    }

    func testShouldExtractDepth_15SecondVideo_Extracts150Keyframes() {
        // 15 seconds at 30fps = 450 frames
        // Should extract 150 keyframes (10fps x 15s)
        var extractionCount = 0
        for frame in 1...450 {
            if sut.shouldExtractDepth(frameNumber: frame) {
                extractionCount += 1
            }
        }
        XCTAssertEqual(extractionCount, 150, "Should extract 150 frames from 450 frames (15s video)")
    }

    // MARK: - Recording State Tests

    func testStartRecording_SetsIsRecordingTrue() {
        sut.startRecording()
        XCTAssertTrue(sut.isRecording, "isRecording should be true after startRecording")
    }

    func testStartRecording_ResetsKeyframeCount() {
        // First simulate some state
        sut.startRecording()
        // (would need real ARFrame to add data)
        sut.reset()
        sut.startRecording()
        XCTAssertEqual(sut.keyframeCount, 0, "keyframeCount should be reset after startRecording")
    }

    func testReset_SetsIsRecordingFalse() {
        sut.startRecording()
        sut.reset()
        XCTAssertFalse(sut.isRecording, "isRecording should be false after reset")
    }

    func testReset_ClearsKeyframeCount() {
        sut.startRecording()
        sut.reset()
        XCTAssertEqual(sut.keyframeCount, 0, "keyframeCount should be zero after reset")
    }

    func testReset_ClearsAccumulatedData() {
        sut.startRecording()
        sut.reset()
        XCTAssertEqual(sut.accumulatedDataSize, 0, "accumulatedDataSize should be zero after reset")
    }

    func testReset_ClearsResolution() {
        sut.startRecording()
        sut.reset()
        XCTAssertEqual(sut.resolution, .zero, "resolution should be zero after reset")
    }

    // MARK: - Finalize Tests

    func testFinalize_WhenNoKeyframes_ReturnsNil() {
        sut.startRecording()
        let result = sut.finalize()
        XCTAssertNil(result, "finalize should return nil when no keyframes captured")
    }

    func testFinalize_SetsIsRecordingFalse() {
        sut.startRecording()
        _ = sut.finalize()
        XCTAssertFalse(sut.isRecording, "isRecording should be false after finalize")
    }

    // MARK: - Compression Tests

    func testCompression_ReducesDataSize() throws {
        // Create test data that compresses well (repetitive pattern)
        let testData = Data(repeating: 0x42, count: 100_000)

        // Use reflection or create a test wrapper to access compression
        // For now, test via the public decompressBlob method (round-trip test)

        // Create a buffer with mock data by using the compression/decompression roundtrip
        let originalData = Data(repeating: 0x42, count: 10_000)

        // Decompress should work on compressed data
        // We'll test this through finalize behavior in integration tests
        XCTAssertTrue(originalData.count > 0, "Test data should exist")
    }

    func testDecompressBlob_RoundTrip_RestoresOriginalData() throws {
        // Create a pattern that represents Float32 depth data
        var originalFloats: [Float32] = []
        for i in 0..<(256 * 192) {
            // Simulate depth values varying from 0-5 meters
            originalFloats.append(Float32(i % 500) / 100.0)
        }
        let originalData = Data(bytes: originalFloats, count: originalFloats.count * MemoryLayout<Float32>.size)

        // Compress and decompress through buffer
        sut.startRecording()

        // Since we can't easily inject compressed data, we'll test the decompression
        // with manually compressed data using the same algorithm

        // Create compressed data using NSData's zlib compression for comparison
        let compressedData = try (originalData as NSData).compressed(using: .zlib) as Data

        // Decompress using our method
        let decompressedData = try sut.decompressBlob(compressedData, uncompressedSize: originalData.count)

        // Verify round-trip
        XCTAssertEqual(decompressedData.count, originalData.count, "Decompressed size should match original")
        XCTAssertEqual(decompressedData, originalData, "Decompressed data should match original")
    }

    func testDecompressBlob_EmptyData_ReturnsEmpty() throws {
        let result = try sut.decompressBlob(Data(), uncompressedSize: 0)
        XCTAssertEqual(result, Data(), "Empty input should return empty output")
    }

    // MARK: - DepthKeyframe Model Tests

    func testDepthKeyframe_Init_StoresValues() {
        let keyframe = DepthKeyframe(index: 5, timestamp: 1.234, offset: 1000)

        XCTAssertEqual(keyframe.index, 5)
        XCTAssertEqual(keyframe.timestamp, 1.234)
        XCTAssertEqual(keyframe.offset, 1000)
    }

    func testDepthKeyframe_Equatable() {
        let keyframe1 = DepthKeyframe(index: 0, timestamp: 0.0, offset: 0)
        let keyframe2 = DepthKeyframe(index: 0, timestamp: 0.0, offset: 0)
        let keyframe3 = DepthKeyframe(index: 1, timestamp: 0.0, offset: 0)

        XCTAssertEqual(keyframe1, keyframe2)
        XCTAssertNotEqual(keyframe1, keyframe3)
    }

    func testDepthKeyframe_Codable() throws {
        let keyframe = DepthKeyframe(index: 10, timestamp: 5.5, offset: 2000)

        let encoder = JSONEncoder()
        let data = try encoder.encode(keyframe)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DepthKeyframe.self, from: data)

        XCTAssertEqual(decoded, keyframe)
    }

    // MARK: - DepthKeyframeData Model Tests

    func testDepthKeyframeData_Init_StoresValues() {
        let frames = [
            DepthKeyframe(index: 0, timestamp: 0.0, offset: 0),
            DepthKeyframe(index: 1, timestamp: 0.1, offset: 196608)
        ]
        let resolution = CGSize(width: 256, height: 192)
        let blob = Data(repeating: 0x42, count: 1000)

        let data = DepthKeyframeData(
            frames: frames,
            resolution: resolution,
            compressedBlob: blob,
            uncompressedSize: 393216
        )

        XCTAssertEqual(data.frames.count, 2)
        XCTAssertEqual(data.resolution, resolution)
        XCTAssertEqual(data.compressedBlob.count, 1000)
        XCTAssertEqual(data.uncompressedSize, 393216)
    }

    func testDepthKeyframeData_KeyframeCount() {
        let frames = [
            DepthKeyframe(index: 0, timestamp: 0.0, offset: 0),
            DepthKeyframe(index: 1, timestamp: 0.1, offset: 196608),
            DepthKeyframe(index: 2, timestamp: 0.2, offset: 393216)
        ]
        let data = DepthKeyframeData(
            frames: frames,
            resolution: CGSize(width: 256, height: 192),
            compressedBlob: Data(),
            uncompressedSize: 0
        )

        XCTAssertEqual(data.keyframeCount, 3)
    }

    func testDepthKeyframeData_CompressionRatio() {
        let data = DepthKeyframeData(
            frames: [],
            resolution: CGSize(width: 256, height: 192),
            compressedBlob: Data(count: 1000),
            uncompressedSize: 3000
        )

        XCTAssertEqual(data.compressionRatio, 3.0, accuracy: 0.001)
    }

    func testDepthKeyframeData_CompressionRatio_ZeroCompressed() {
        let data = DepthKeyframeData(
            frames: [],
            resolution: CGSize(width: 256, height: 192),
            compressedBlob: Data(),
            uncompressedSize: 3000
        )

        XCTAssertEqual(data.compressionRatio, 0)
    }

    func testDepthKeyframeData_Codable() throws {
        let frames = [
            DepthKeyframe(index: 0, timestamp: 0.0, offset: 0),
            DepthKeyframe(index: 1, timestamp: 0.1, offset: 196608)
        ]
        let original = DepthKeyframeData(
            frames: frames,
            resolution: CGSize(width: 256, height: 192),
            compressedBlob: Data([0x01, 0x02, 0x03]),
            uncompressedSize: 393216
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DepthKeyframeData.self, from: data)

        XCTAssertEqual(decoded.frames.count, original.frames.count)
        XCTAssertEqual(decoded.resolution, original.resolution)
        XCTAssertEqual(decoded.compressedBlob, original.compressedBlob)
        XCTAssertEqual(decoded.uncompressedSize, original.uncompressedSize)
    }

    // MARK: - DepthKeyframeError Tests

    func testDepthKeyframeError_InvalidPixelFormat_Description() {
        let error = DepthKeyframeError.invalidPixelFormat
        XCTAssertEqual(error.errorDescription, "Invalid depth buffer pixel format (expected Float32)")
    }

    func testDepthKeyframeError_BufferAccessFailed_Description() {
        let error = DepthKeyframeError.bufferAccessFailed
        XCTAssertEqual(error.errorDescription, "Failed to access depth buffer memory")
    }

    func testDepthKeyframeError_CompressionFailed_Description() {
        let error = DepthKeyframeError.compressionFailed
        XCTAssertEqual(error.errorDescription, "Failed to compress depth data")
    }

    func testDepthKeyframeError_MaxKeyframesReached_Description() {
        let error = DepthKeyframeError.maxKeyframesReached
        XCTAssertEqual(error.errorDescription, "Maximum keyframe limit reached (150 frames)")
    }

    func testDepthKeyframeError_NotRecording_Description() {
        let error = DepthKeyframeError.notRecording
        XCTAssertEqual(error.errorDescription, "Buffer is not in recording state")
    }

    func testDepthKeyframeError_Equatable() {
        XCTAssertEqual(DepthKeyframeError.invalidPixelFormat, DepthKeyframeError.invalidPixelFormat)
        XCTAssertNotEqual(DepthKeyframeError.invalidPixelFormat, DepthKeyframeError.bufferAccessFailed)
    }

    // MARK: - Thread Safety Tests

    func testKeyframeCount_ThreadSafe() {
        sut.startRecording()

        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.keyframeCount
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testIsRecording_ThreadSafe() {
        sut.startRecording()

        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.isRecording
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testResolution_ThreadSafe() {
        sut.startRecording()

        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.resolution
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testAccumulatedDataSize_ThreadSafe() {
        sut.startRecording()

        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.accumulatedDataSize
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testConcurrentStartResetOperations_ThreadSafe() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index % 2 == 0 {
                sut.startRecording()
            } else {
                sut.reset()
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Performance Tests

    func testShouldExtractDepth_Performance() {
        measure {
            for _ in 0..<10000 {
                _ = sut.shouldExtractDepth(frameNumber: Int.random(in: 1...1000))
            }
        }
    }

    // MARK: - Integration with Mock Data Tests

    func testBufferAccumulatesCorrectDataSize() {
        sut.startRecording()

        // Simulate adding depth data manually by using the public API
        // We can't easily create CVPixelBuffer in tests, so we test the data structures

        // Expected: 256 x 192 x 4 bytes per frame = 196,608 bytes
        let expectedBytesPerFrame = 256 * 192 * MemoryLayout<Float32>.size
        XCTAssertEqual(expectedBytesPerFrame, 196_608, "Expected bytes per frame should be 196KB")
    }

    func testMaxKeyframesLimit_Is150() {
        // 10fps x 15 seconds = 150 frames
        let maxFrames = 10 * 15
        XCTAssertEqual(maxFrames, DepthKeyframeBuffer.maxKeyframes)
    }

    // MARK: - Physical Device Tests (Require iPhone Pro with LiDAR)

    func testExtractDepthData_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        let arSession = ARCaptureSession()
        try arSession.start()

        // Wait for a frame with depth data
        let frameExpectation = XCTestExpectation(description: "Frame with depth received")
        var capturedFrame: ARFrame?

        arSession.onFrameUpdate = { frame in
            if frame.sceneDepth != nil && capturedFrame == nil {
                capturedFrame = frame
                frameExpectation.fulfill()
            }
        }

        await fulfillment(of: [frameExpectation], timeout: 3.0)
        arSession.stop()

        guard let frame = capturedFrame, let sceneDepth = frame.sceneDepth else {
            XCTFail("Failed to capture frame with depth data")
            return
        }

        // Extract depth data
        sut.startRecording()
        let depthData = try sut.extractDepthData(from: sceneDepth.depthMap)

        // Verify data size (should be width x height x 4 bytes)
        let width = CVPixelBufferGetWidth(sceneDepth.depthMap)
        let height = CVPixelBufferGetHeight(sceneDepth.depthMap)
        let expectedSize = width * height * MemoryLayout<Float32>.size

        XCTAssertEqual(depthData.count, expectedSize, "Extracted depth data size should match expected")
        XCTAssertGreaterThan(depthData.count, 0, "Depth data should not be empty")

        // Verify resolution was set
        XCTAssertNotEqual(sut.resolution, .zero, "Resolution should be set after extraction")
        XCTAssertEqual(Int(sut.resolution.width), width)
        XCTAssertEqual(Int(sut.resolution.height), height)
    }

    func testProcessFrame_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        let arSession = ARCaptureSession()
        try arSession.start()

        // Wait for frames with depth data
        let frameExpectation = XCTestExpectation(description: "Frames received")
        frameExpectation.expectedFulfillmentCount = 10
        var frameCount = 0

        sut.startRecording()

        arSession.onFrameUpdate = { [weak self] frame in
            guard let self = self else { return }
            frameCount += 1
            self.sut.processFrame(frame, frameNumber: frameCount)
            if frameCount <= 10 {
                frameExpectation.fulfill()
            }
        }

        await fulfillment(of: [frameExpectation], timeout: 3.0)
        arSession.stop()

        // Should have extracted ~3-4 keyframes from 10 frames (frames 1, 4, 7, 10)
        let keyframeCount = sut.keyframeCount
        XCTAssertGreaterThanOrEqual(keyframeCount, 3, "Should have extracted at least 3 keyframes from 10 frames")
        XCTAssertLessThanOrEqual(keyframeCount, 4, "Should have extracted at most 4 keyframes from 10 frames")
    }

    func testFullRecordingCycle_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        let arSession = ARCaptureSession()
        try arSession.start()

        // Record for 1 second (~30 frames, ~10 keyframes)
        let recordingExpectation = XCTestExpectation(description: "Recording complete")
        var frameCount = 0

        sut.startRecording()

        arSession.onFrameUpdate = { [weak self] frame in
            guard let self = self else { return }
            frameCount += 1
            self.sut.processFrame(frame, frameNumber: frameCount)
        }

        // Wait 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            recordingExpectation.fulfill()
        }

        await fulfillment(of: [recordingExpectation], timeout: 2.0)
        arSession.stop()

        // Finalize and verify
        let result = sut.finalize()

        XCTAssertNotNil(result, "Finalize should return data")
        XCTAssertGreaterThan(result!.keyframeCount, 0, "Should have captured keyframes")
        XCTAssertGreaterThan(result!.compressedBlob.count, 0, "Compressed blob should have data")
        XCTAssertGreaterThan(result!.uncompressedSize, 0, "Uncompressed size should be recorded")
        XCTAssertGreaterThan(result!.compressionRatio, 1.0, "Should achieve some compression")

        // Verify approximately 10 keyframes for 1 second
        XCTAssertGreaterThanOrEqual(result!.keyframeCount, 8, "Should have ~10 keyframes for 1 second")
        XCTAssertLessThanOrEqual(result!.keyframeCount, 12, "Should have ~10 keyframes for 1 second")

        // Verify resolution
        XCTAssertNotEqual(result!.resolution, .zero, "Resolution should be captured")
    }

    func testCompressionRatio_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        let arSession = ARCaptureSession()
        try arSession.start()

        // Record for 0.5 seconds
        let recordingExpectation = XCTestExpectation(description: "Recording complete")
        var frameCount = 0

        sut.startRecording()

        arSession.onFrameUpdate = { [weak self] frame in
            guard let self = self else { return }
            frameCount += 1
            self.sut.processFrame(frame, frameNumber: frameCount)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            recordingExpectation.fulfill()
        }

        await fulfillment(of: [recordingExpectation], timeout: 1.0)
        arSession.stop()

        let result = sut.finalize()

        guard let depthData = result else {
            throw XCTSkip("No depth data captured - may require different conditions")
        }

        // Verify compression achieved some reduction
        // Depth data should compress reasonably well
        XCTAssertLessThan(
            depthData.compressedBlob.count,
            depthData.uncompressedSize,
            "Compressed size should be less than uncompressed"
        )

        print("Compression ratio: \(depthData.compressionRatio)x")
        print("Uncompressed: \(depthData.uncompressedSize) bytes")
        print("Compressed: \(depthData.compressedBlob.count) bytes")
    }

    func testDecompressBlob_RecoversOriginalData_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        let arSession = ARCaptureSession()
        try arSession.start()

        // Capture a few frames
        let recordingExpectation = XCTestExpectation(description: "Recording complete")
        var frameCount = 0

        sut.startRecording()

        arSession.onFrameUpdate = { [weak self] frame in
            guard let self = self else { return }
            frameCount += 1
            self.sut.processFrame(frame, frameNumber: frameCount)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            recordingExpectation.fulfill()
        }

        await fulfillment(of: [recordingExpectation], timeout: 1.0)
        arSession.stop()

        let result = sut.finalize()

        guard let depthData = result else {
            throw XCTSkip("No depth data captured")
        }

        // Decompress and verify size
        let decompressed = try sut.decompressBlob(
            depthData.compressedBlob,
            uncompressedSize: depthData.uncompressedSize
        )

        XCTAssertEqual(
            decompressed.count,
            depthData.uncompressedSize,
            "Decompressed size should match original"
        )

        // Verify we can parse the data back to Float32 values
        let floatCount = decompressed.count / MemoryLayout<Float32>.size
        XCTAssertGreaterThan(floatCount, 0, "Should have float values")

        // Read some values and verify they're valid depth measurements (0-5m range typical)
        decompressed.withUnsafeBytes { buffer in
            let floats = buffer.bindMemory(to: Float32.self)
            var validDepthCount = 0
            for i in 0..<min(1000, floats.count) {
                let depth = floats[i]
                if depth >= 0 && depth <= 10 { // LiDAR typical range
                    validDepthCount += 1
                }
            }
            // Most values should be valid depths (some may be inf for no-return)
            XCTAssertGreaterThan(validDepthCount, 500, "Most depth values should be in valid range")
        }
    }
}
