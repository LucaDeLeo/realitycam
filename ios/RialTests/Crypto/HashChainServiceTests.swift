//
//  HashChainServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-26.
//
//  Unit tests for HashChainService frame hash chain computation.
//

import XCTest
import CryptoKit
@testable import Rial

final class HashChainServiceTests: XCTestCase {

    // MARK: - Properties

    var sut: HashChainService!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = HashChainService()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Test Helpers

    /// Creates a mock CVPixelBuffer for testing.
    ///
    /// - Parameters:
    ///   - width: Buffer width in pixels
    ///   - height: Buffer height in pixels
    ///   - fillValue: Value to fill pixels with (0-255)
    /// - Returns: A CVPixelBuffer suitable for testing
    private func createMockPixelBuffer(width: Int = 256, height: Int = 256, fillValue: UInt8 = 128) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        // Fill with test data
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let totalBytes = height * bytesPerRow
            memset(baseAddress, Int32(fillValue), totalBytes)
        }

        return buffer
    }

    /// Creates a mock depth pixel buffer for testing.
    private func createMockDepthBuffer(width: Int = 256, height: Int = 192, fillValue: Float = 1.5) -> CVPixelBuffer? {
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
            return nil
        }

        // Fill with depth values
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let floatPointer = baseAddress.bindMemory(to: Float.self, capacity: width * height)
            for i in 0..<(width * height) {
                floatPointer[i] = fillValue
            }
        }

        return buffer
    }

    // MARK: - Initial State Tests

    func testInitialState_FrameCountIsZero() async {
        let count = await sut.frameCount
        XCTAssertEqual(count, 0, "Initial frame count should be 0")
    }

    func testInitialState_HasNoFrames() async {
        let hasFrames = await sut.hasFrames
        XCTAssertFalse(hasFrames, "Should have no frames initially")
    }

    func testInitialState_LastCheckpointIsNil() async {
        let checkpoint = await sut.lastCheckpoint
        XCTAssertNil(checkpoint, "Last checkpoint should be nil initially")
    }

    func testGetChainData_EmptyState() async {
        let chainData = await sut.getChainData()

        XCTAssertTrue(chainData.frameHashes.isEmpty, "Frame hashes should be empty")
        XCTAssertTrue(chainData.checkpoints.isEmpty, "Checkpoints should be empty")
        XCTAssertTrue(chainData.finalHash.isEmpty, "Final hash should be empty")
        XCTAssertEqual(chainData.frameCount, 0, "Frame count should be 0")
    }

    // MARK: - First Frame Hash Tests

    func testProcessFrame_FirstFrame_ReturnsValidHash() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        let hash = await sut.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        XCTAssertEqual(hash.count, 32, "SHA256 hash should be 32 bytes")
        XCTAssertFalse(hash.allSatisfy { $0 == 0 }, "Hash should not be all zeros")
    }

    func testProcessFrame_FirstFrame_FrameCountIncreases() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        _ = await sut.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        let count = await sut.frameCount
        XCTAssertEqual(count, 1, "Frame count should be 1 after first frame")
    }

    // MARK: - Hash Chain Tests

    func testProcessFrame_SecondFrame_IncludesPreviousHash() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        let hash1 = await sut.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        let hash2 = await sut.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.033,
            frameNumber: 2
        )

        // Hash 2 should be different from hash 1 (includes previous hash)
        XCTAssertNotEqual(hash1, hash2, "Second frame hash should differ from first")
    }

    func testProcessFrame_SameInputDifferentPosition_DifferentHash() async {
        // Two separate service instances to test hash chain effect
        let service1 = HashChainService()
        let service2 = HashChainService()

        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // First service: single frame
        let hash1 = await service1.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        // Second service: process two frames with same data
        _ = await service2.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        let hash2 = await service2.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,  // Same timestamp
            frameNumber: 2
        )

        // hash2 includes previous hash, so should be different
        XCTAssertNotEqual(hash1, hash2, "Same data at different positions should produce different hashes")
    }

    // MARK: - Determinism Tests

    func testProcessFrame_Determinism_SameInputSameOutput() async {
        let service1 = HashChainService()
        let service2 = HashChainService()

        guard let rgbBuffer1 = createMockPixelBuffer(fillValue: 100) else {
            XCTFail("Failed to create mock pixel buffer 1")
            return
        }
        guard let rgbBuffer2 = createMockPixelBuffer(fillValue: 100) else {
            XCTFail("Failed to create mock pixel buffer 2")
            return
        }

        let hash1 = await service1.processFrame(
            rgbBuffer: rgbBuffer1,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        let hash2 = await service2.processFrame(
            rgbBuffer: rgbBuffer2,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        XCTAssertEqual(hash1, hash2, "Same input should produce same hash")
    }

    // MARK: - Depth Data Tests

    func testProcessFrame_WithDepth_AffectsHash() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }
        guard let depthBuffer = createMockDepthBuffer() else {
            XCTFail("Failed to create mock depth buffer")
            return
        }

        let service1 = HashChainService()
        let service2 = HashChainService()

        let hashWithoutDepth = await service1.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        let hashWithDepth = await service2.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: depthBuffer,
            timestamp: 0.0,
            frameNumber: 1
        )

        XCTAssertNotEqual(hashWithoutDepth, hashWithDepth, "Depth data should affect hash")
    }

    // MARK: - Timestamp Tests

    func testProcessFrame_DifferentTimestamp_DifferentHash() async {
        let service1 = HashChainService()
        let service2 = HashChainService()

        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        let hash1 = await service1.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 1
        )

        let hash2 = await service2.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 1.0,  // Different timestamp
            frameNumber: 1
        )

        XCTAssertNotEqual(hash1, hash2, "Different timestamps should produce different hashes")
    }

    // MARK: - Checkpoint Tests

    func testCheckpoint_CreatedAtFrame150() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // Process 150 frames
        for i in 1...150 {
            _ = await sut.processFrame(
                rgbBuffer: rgbBuffer,
                depthBuffer: nil,
                timestamp: Double(i) / 30.0,
                frameNumber: i
            )
        }

        let chainData = await sut.getChainData()
        XCTAssertEqual(chainData.checkpoints.count, 1, "Should have 1 checkpoint at frame 150")

        let checkpoint = chainData.checkpoints.first
        XCTAssertEqual(checkpoint?.index, 0, "Checkpoint index should be 0")
        XCTAssertEqual(checkpoint?.frameNumber, 150, "Checkpoint should be at frame 150")
    }

    func testCheckpoint_CreatedAtFrames150_300_450() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // Process 450 frames (15 seconds at 30fps)
        for i in 1...450 {
            _ = await sut.processFrame(
                rgbBuffer: rgbBuffer,
                depthBuffer: nil,
                timestamp: Double(i) / 30.0,
                frameNumber: i
            )
        }

        let chainData = await sut.getChainData()
        XCTAssertEqual(chainData.checkpoints.count, 3, "Should have 3 checkpoints")

        // Verify each checkpoint
        XCTAssertEqual(chainData.checkpoints[0].index, 0)
        XCTAssertEqual(chainData.checkpoints[0].frameNumber, 150)

        XCTAssertEqual(chainData.checkpoints[1].index, 1)
        XCTAssertEqual(chainData.checkpoints[1].frameNumber, 300)

        XCTAssertEqual(chainData.checkpoints[2].index, 2)
        XCTAssertEqual(chainData.checkpoints[2].frameNumber, 450)
    }

    func testCheckpoint_HashMatchesFrameHash() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // Process 150 frames
        var frame150Hash: Data?
        for i in 1...150 {
            let hash = await sut.processFrame(
                rgbBuffer: rgbBuffer,
                depthBuffer: nil,
                timestamp: Double(i) / 30.0,
                frameNumber: i
            )
            if i == 150 {
                frame150Hash = hash
            }
        }

        let chainData = await sut.getChainData()
        let checkpoint = chainData.checkpoints.first

        XCTAssertEqual(checkpoint?.hash, frame150Hash, "Checkpoint hash should match frame 150 hash")
        XCTAssertEqual(checkpoint?.hash, chainData.frameHashes[149], "Checkpoint hash should match stored frame hash")
    }

    // MARK: - Reset Tests

    func testReset_ClearsAllState() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // Process some frames
        for i in 1...200 {
            _ = await sut.processFrame(
                rgbBuffer: rgbBuffer,
                depthBuffer: nil,
                timestamp: Double(i) / 30.0,
                frameNumber: i
            )
        }

        // Verify state before reset
        var count = await sut.frameCount
        XCTAssertEqual(count, 200, "Should have 200 frames before reset")

        // Reset
        await sut.reset()

        // Verify state after reset
        count = await sut.frameCount
        XCTAssertEqual(count, 0, "Frame count should be 0 after reset")

        let hasFrames = await sut.hasFrames
        XCTAssertFalse(hasFrames, "Should have no frames after reset")

        let checkpoint = await sut.lastCheckpoint
        XCTAssertNil(checkpoint, "Last checkpoint should be nil after reset")

        let chainData = await sut.getChainData()
        XCTAssertTrue(chainData.frameHashes.isEmpty, "Frame hashes should be empty after reset")
        XCTAssertTrue(chainData.checkpoints.isEmpty, "Checkpoints should be empty after reset")
    }

    // MARK: - GetChainData Tests

    func testGetChainData_ReturnsCorrectStructure() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // Process 10 frames
        for i in 1...10 {
            _ = await sut.processFrame(
                rgbBuffer: rgbBuffer,
                depthBuffer: nil,
                timestamp: Double(i) / 30.0,
                frameNumber: i
            )
        }

        let chainData = await sut.getChainData()

        XCTAssertEqual(chainData.frameHashes.count, 10, "Should have 10 frame hashes")
        XCTAssertEqual(chainData.frameCount, 10, "Frame count should be 10")
        XCTAssertEqual(chainData.finalHash.count, 32, "Final hash should be 32 bytes")
        XCTAssertEqual(chainData.finalHash, chainData.frameHashes.last, "Final hash should equal last frame hash")
    }

    // MARK: - Frame Count Tracking Tests

    func testFrameCount_AccurateTracking() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        for expected in 1...100 {
            _ = await sut.processFrame(
                rgbBuffer: rgbBuffer,
                depthBuffer: nil,
                timestamp: Double(expected) / 30.0,
                frameNumber: expected
            )

            let count = await sut.frameCount
            XCTAssertEqual(count, expected, "Frame count should be \(expected) after processing \(expected) frames")
        }
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentAccess_ActorSafety() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // Process frames concurrently from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 1...50 {
                group.addTask {
                    _ = await self.sut.processFrame(
                        rgbBuffer: rgbBuffer,
                        depthBuffer: nil,
                        timestamp: Double(i) / 30.0,
                        frameNumber: i
                    )
                }
            }
        }

        // Verify all frames were processed
        let count = await sut.frameCount
        XCTAssertEqual(count, 50, "All 50 frames should be processed")

        let chainData = await sut.getChainData()
        XCTAssertEqual(chainData.frameHashes.count, 50, "Should have 50 frame hashes")
    }

    // MARK: - Performance Tests

    func testPerformance_HashComputation() async {
        guard let rgbBuffer = createMockPixelBuffer() else {
            XCTFail("Failed to create mock pixel buffer")
            return
        }

        // Warm up
        _ = await sut.processFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            timestamp: 0.0,
            frameNumber: 0
        )

        await sut.reset()

        // Measure average time for 30 frames
        let frameCount = 30
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 1...frameCount {
            _ = await sut.processFrame(
                rgbBuffer: rgbBuffer,
                depthBuffer: nil,
                timestamp: Double(i) / 30.0,
                frameNumber: i
            )
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTimeMs = (totalTime * 1000) / Double(frameCount)

        // Target: < 5ms per frame
        XCTAssertLessThan(averageTimeMs, 5.0, "Average hash computation should be < 5ms, was \(String(format: "%.2f", averageTimeMs))ms")
    }

    // MARK: - HashCheckpoint Tests

    func testHashCheckpoint_Codable() throws {
        let checkpoint = HashCheckpoint(
            index: 0,
            frameNumber: 150,
            hash: Data([0x01, 0x02, 0x03]),
            timestamp: 5.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(checkpoint)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HashCheckpoint.self, from: data)

        XCTAssertEqual(decoded.index, checkpoint.index)
        XCTAssertEqual(decoded.frameNumber, checkpoint.frameNumber)
        XCTAssertEqual(decoded.hash, checkpoint.hash)
        XCTAssertEqual(decoded.timestamp, checkpoint.timestamp)
    }

    func testHashCheckpoint_Equatable() {
        let checkpoint1 = HashCheckpoint(index: 0, frameNumber: 150, hash: Data([0x01]), timestamp: 5.0)
        let checkpoint2 = HashCheckpoint(index: 0, frameNumber: 150, hash: Data([0x01]), timestamp: 5.0)
        let checkpoint3 = HashCheckpoint(index: 1, frameNumber: 300, hash: Data([0x02]), timestamp: 10.0)

        XCTAssertEqual(checkpoint1, checkpoint2)
        XCTAssertNotEqual(checkpoint1, checkpoint3)
    }

    // MARK: - HashChainData Tests

    func testHashChainData_Codable() throws {
        let chainData = HashChainData(
            frameHashes: [Data([0x01]), Data([0x02])],
            checkpoints: [
                HashCheckpoint(index: 0, frameNumber: 150, hash: Data([0x01]), timestamp: 5.0)
            ],
            finalHash: Data([0x02])
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(chainData)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HashChainData.self, from: data)

        XCTAssertEqual(decoded.frameHashes.count, chainData.frameHashes.count)
        XCTAssertEqual(decoded.checkpoints.count, chainData.checkpoints.count)
        XCTAssertEqual(decoded.finalHash, chainData.finalHash)
        XCTAssertEqual(decoded.frameCount, chainData.frameCount)
    }

    func testHashChainData_ConvenienceProperties() {
        let chainData = HashChainData(
            frameHashes: [Data([0x01]), Data([0x02]), Data([0x03])],
            checkpoints: [
                HashCheckpoint(index: 0, frameNumber: 150, hash: Data([0x01]), timestamp: 5.0)
            ],
            finalHash: Data([0x03])
        )

        XCTAssertEqual(chainData.frameCount, 3)
        XCTAssertEqual(chainData.checkpointCount, 1)
    }
}
