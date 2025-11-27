//
//  VideoProcessingPipelineTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-27.
//
//  Unit tests for VideoProcessingPipeline.
//

import XCTest
@testable import Rial

final class VideoProcessingPipelineTests: XCTestCase {

    var sut: VideoProcessingPipeline!

    override func setUp() {
        super.setUp()
        sut = VideoProcessingPipeline()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Pipeline Initialization Tests

    func testPipelineInitialization() {
        // Given/When
        let pipeline = VideoProcessingPipeline()

        // Then
        XCTAssertNotNil(pipeline)
    }

    // MARK: - Hash Chain Serialization Tests

    func testSerializeHashChain_ProducesValidJSON() throws {
        // Given
        let hashChainData = createMockHashChainData()

        // When
        let jsonData = try sut.serializeHashChain(hashChainData)

        // Then
        XCTAssertGreaterThan(jsonData.count, 0)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["frame_hashes"])
        XCTAssertNotNil(json?["checkpoints"])
        XCTAssertNotNil(json?["final_hash"])
        XCTAssertNotNil(json?["frame_count"])
        XCTAssertNotNil(json?["checkpoint_count"])
    }

    func testSerializeHashChain_IncludesAllFrameHashes() throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 10)

        // When
        let jsonData = try sut.serializeHashChain(hashChainData)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        let frameHashes = json?["frame_hashes"] as? [String]
        XCTAssertEqual(frameHashes?.count, 10)
    }

    func testSerializeHashChain_IncludesCheckpoints() throws {
        // Given
        let hashChainData = createMockHashChainData(checkpointCount: 2)

        // When
        let jsonData = try sut.serializeHashChain(hashChainData)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        let checkpoints = json?["checkpoints"] as? [[String: Any]]
        XCTAssertEqual(checkpoints?.count, 2)
    }

    func testSerializeHashChain_UsesBase64ForHashes() throws {
        // Given
        let hashChainData = createMockHashChainData()

        // When
        let jsonData = try sut.serializeHashChain(hashChainData)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        let finalHash = json?["final_hash"] as? String
        XCTAssertNotNil(finalHash)
        // Base64 strings should be decodable
        XCTAssertNotNil(Data(base64Encoded: finalHash!))
    }

    func testSerializeHashChain_UsesSnakeCaseKeys() throws {
        // Given
        let hashChainData = createMockHashChainData()

        // When
        let jsonData = try sut.serializeHashChain(hashChainData)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Then
        XCTAssertTrue(jsonString.contains("frame_hashes"))
        XCTAssertTrue(jsonString.contains("final_hash"))
        XCTAssertTrue(jsonString.contains("frame_count"))
        XCTAssertTrue(jsonString.contains("checkpoint_count"))
        // Should not contain camelCase
        XCTAssertFalse(jsonString.contains("frameHashes"))
        XCTAssertFalse(jsonString.contains("finalHash"))
    }

    func testSerializeHashChain_CheckpointStructure() throws {
        // Given
        let hashChainData = createMockHashChainData(checkpointCount: 1)

        // When
        let jsonData = try sut.serializeHashChain(hashChainData)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        let checkpoints = json?["checkpoints"] as? [[String: Any]]
        XCTAssertNotNil(checkpoints)
        XCTAssertEqual(checkpoints?.count, 1)

        let checkpoint = checkpoints?.first
        XCTAssertNotNil(checkpoint?["index"])
        XCTAssertNotNil(checkpoint?["frame_number"])
        XCTAssertNotNil(checkpoint?["hash"])
        XCTAssertNotNil(checkpoint?["timestamp"])
    }

    // MARK: - Metadata Serialization Tests

    func testSerializeMetadata_ProducesValidJSON() throws {
        // Given
        let metadata = createMockVideoMetadata()

        // When
        let jsonData = try sut.serializeMetadata(metadata)

        // Then
        XCTAssertGreaterThan(jsonData.count, 0)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(json)
    }

    func testSerializeMetadata_ProducesSnakeCaseJSON() throws {
        // Given
        let metadata = createMockVideoMetadata()

        // When
        let jsonData = try sut.serializeMetadata(metadata)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Then
        XCTAssertTrue(jsonString.contains("started_at"))
        XCTAssertTrue(jsonString.contains("ended_at"))
        XCTAssertTrue(jsonString.contains("duration_ms"))
        XCTAssertTrue(jsonString.contains("frame_count"))
        XCTAssertTrue(jsonString.contains("depth_keyframe_count"))
        XCTAssertTrue(jsonString.contains("device_model"))
        XCTAssertTrue(jsonString.contains("ios_version"))
        XCTAssertTrue(jsonString.contains("attestation_level"))
        XCTAssertTrue(jsonString.contains("hash_chain_final"))
    }

    func testSerializeMetadata_IncludesAttestation() throws {
        // Given
        let metadata = createMockVideoMetadata()

        // When
        let jsonData = try sut.serializeMetadata(metadata)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        XCTAssertNotNil(json?["assertion"])
        XCTAssertNotNil(json?["hash_chain_final"])
    }

    func testSerializeMetadata_IncludesResolution() throws {
        // Given
        let metadata = createMockVideoMetadata()

        // When
        let jsonData = try sut.serializeMetadata(metadata)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        let resolution = json?["resolution"] as? [String: Any]
        XCTAssertNotNil(resolution)
        XCTAssertEqual(resolution?["width"] as? Int, 1920)
        XCTAssertEqual(resolution?["height"] as? Int, 1080)
    }

    func testSerializeMetadata_IncludesISO8601Dates() throws {
        // Given
        let metadata = createMockVideoMetadata()

        // When
        let jsonData = try sut.serializeMetadata(metadata)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        let startedAt = json?["started_at"] as? String
        XCTAssertNotNil(startedAt)
        // ISO8601 format contains "T" separator and "Z" suffix
        XCTAssertTrue(startedAt?.contains("T") ?? false)
    }

    // MARK: - ProcessedVideoCapture Model Tests

    func testProcessedVideoCapture_Initialization() {
        // Given/When
        let processed = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(repeating: 0, count: 1000),
            hashChainJSON: Data(repeating: 0, count: 500),
            metadataJSON: Data(repeating: 0, count: 200),
            thumbnailData: Data(repeating: 0, count: 300),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        // Then
        XCTAssertEqual(processed.frameCount, 450)
        XCTAssertEqual(processed.depthKeyframeCount, 150)
        XCTAssertEqual(processed.durationMs, 15000)
        XCTAssertFalse(processed.isPartial)
    }

    func testProcessedVideoCapture_StatusDefaults() {
        // Given/When
        let processed = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        // Then
        XCTAssertEqual(processed.status, .pendingUpload)
    }

    func testProcessedVideoCapture_TotalSizeCalculation() {
        // Given
        let processed = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/nonexistent.mov"),
            compressedDepthData: Data(repeating: 0, count: 1000),
            hashChainJSON: Data(repeating: 0, count: 500),
            metadataJSON: Data(repeating: 0, count: 200),
            thumbnailData: Data(repeating: 0, count: 300),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        // Then
        // Video file doesn't exist, so just data sizes
        XCTAssertEqual(processed.totalSizeBytes, 2000)
    }

    func testProcessedVideoCapture_DurationSeconds() {
        // Given
        let processed = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15333,
            isPartial: false
        )

        // Then
        XCTAssertEqual(processed.durationSeconds, 15.333, accuracy: 0.001)
    }

    func testProcessedVideoCapture_HasDepthData() {
        // Given
        let withDepth = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(repeating: 0, count: 100),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        let withoutDepth = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 450,
            depthKeyframeCount: 0,
            durationMs: 15000,
            isPartial: false
        )

        // Then
        XCTAssertTrue(withDepth.hasDepthData)
        XCTAssertFalse(withoutDepth.hasDepthData)
    }

    func testProcessedVideoCapture_HasThumbnail() {
        // Given
        let withThumbnail = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(repeating: 0, count: 100),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        let withoutThumbnail = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        // Then
        XCTAssertTrue(withThumbnail.hasThumbnail)
        XCTAssertFalse(withoutThumbnail.hasThumbnail)
    }

    func testProcessedVideoCapture_HasHashChain() {
        // Given
        let withHashChain = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(),
            hashChainJSON: Data(repeating: 0, count: 100),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        let withoutHashChain = ProcessedVideoCapture(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            compressedDepthData: Data(),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 450,
            depthKeyframeCount: 150,
            durationMs: 15000,
            isPartial: false
        )

        // Then
        XCTAssertTrue(withHashChain.hasHashChain)
        XCTAssertFalse(withoutHashChain.hasHashChain)
    }

    // MARK: - VideoCaptureStatus Tests

    func testVideoCaptureStatus_IsComplete() {
        XCTAssertTrue(VideoCaptureStatus.uploaded.isComplete)
        XCTAssertFalse(VideoCaptureStatus.pendingUpload.isComplete)
        XCTAssertFalse(VideoCaptureStatus.uploading.isComplete)
        XCTAssertFalse(VideoCaptureStatus.failed.isComplete)
        XCTAssertFalse(VideoCaptureStatus.processing.isComplete)
    }

    func testVideoCaptureStatus_IsInProgress() {
        XCTAssertTrue(VideoCaptureStatus.processing.isInProgress)
        XCTAssertTrue(VideoCaptureStatus.uploading.isInProgress)
        XCTAssertFalse(VideoCaptureStatus.pendingUpload.isInProgress)
        XCTAssertFalse(VideoCaptureStatus.uploaded.isInProgress)
        XCTAssertFalse(VideoCaptureStatus.failed.isInProgress)
    }

    func testVideoCaptureStatus_CanRetry() {
        XCTAssertTrue(VideoCaptureStatus.failed.canRetry)
        XCTAssertTrue(VideoCaptureStatus.paused.canRetry)
        XCTAssertFalse(VideoCaptureStatus.uploaded.canRetry)
        XCTAssertFalse(VideoCaptureStatus.pendingUpload.canRetry)
        XCTAssertFalse(VideoCaptureStatus.processing.canRetry)
    }

    func testVideoCaptureStatus_RawValues() {
        XCTAssertEqual(VideoCaptureStatus.pendingUpload.rawValue, "pending_upload")
        XCTAssertEqual(VideoCaptureStatus.processing.rawValue, "processing")
        XCTAssertEqual(VideoCaptureStatus.uploading.rawValue, "uploading")
        XCTAssertEqual(VideoCaptureStatus.paused.rawValue, "paused")
        XCTAssertEqual(VideoCaptureStatus.uploaded.rawValue, "uploaded")
        XCTAssertEqual(VideoCaptureStatus.failed.rawValue, "failed")
    }

    // MARK: - Error Tests

    func testVideoProcessingError_Descriptions() {
        XCTAssertEqual(
            VideoProcessingError.compressionFailed.errorDescription,
            "Failed to compress depth data"
        )
        XCTAssertEqual(
            VideoProcessingError.thumbnailGenerationFailed.errorDescription,
            "Failed to generate video thumbnail"
        )
        XCTAssertEqual(
            VideoProcessingError.invalidInput("test").errorDescription,
            "Invalid input: test"
        )

        let innerError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "inner error"])
        let serializationError = VideoProcessingError.serializationFailed(innerError)
        XCTAssertTrue(serializationError.errorDescription?.contains("inner error") ?? false)
    }

    // MARK: - Progress Callback Tests

    func testProgressCallback_EmptyHashChain() throws {
        // Given
        let emptyHashChain = HashChainData(
            frameHashes: [],
            checkpoints: [],
            finalHash: Data()
        )

        // When
        let jsonData = try sut.serializeHashChain(emptyHashChain)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Then
        let frameHashes = json?["frame_hashes"] as? [String]
        XCTAssertEqual(frameHashes?.count, 0)
        XCTAssertEqual(json?["frame_count"] as? Int, 0)
    }

    // MARK: - Helpers

    private func createMockHashChainData(frameCount: Int = 5, checkpointCount: Int = 1) -> HashChainData {
        var frameHashes: [Data] = []
        for _ in 0..<frameCount {
            frameHashes.append(Data(repeating: UInt8.random(in: 0...255), count: 32))
        }

        var checkpoints: [HashCheckpoint] = []
        for i in 0..<checkpointCount {
            checkpoints.append(HashCheckpoint(
                index: i,
                frameNumber: (i + 1) * 150,
                hash: Data(repeating: UInt8.random(in: 0...255), count: 32),
                timestamp: TimeInterval((i + 1) * 5)
            ))
        }

        return HashChainData(
            frameHashes: frameHashes,
            checkpoints: checkpoints,
            finalHash: frameHashes.last ?? Data(repeating: 0, count: 32)
        )
    }

    private func createMockVideoMetadata() -> VideoMetadata {
        return VideoMetadata(
            type: "video",
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(15),
            durationMs: 15000,
            frameCount: 450,
            depthKeyframeCount: 150,
            resolution: Resolution(width: 1920, height: 1080),
            codec: "hevc",
            deviceModel: "iPhone 15 Pro",
            iosVersion: "17.4",
            location: nil,
            attestationLevel: "secure_enclave",
            hashChainFinal: "dGVzdGhhc2g=",
            assertion: "dGVzdGFzc2VydGlvbg=="
        )
    }
}
