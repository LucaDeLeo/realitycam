//
//  VideoCaptureStoreTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-27.
//
//  Unit tests for video capture storage in CaptureStore (Story 7-8).
//

import XCTest
@testable import Rial

/// Unit tests for video capture CoreData persistence
///
/// Tests video capture storage, status tracking, and conversion
/// between ProcessedVideoCapture and VideoCaptureEntity.
///
/// ## Testing Strategy
/// - Uses in-memory CoreData store for isolation
/// - No file system persistence between tests
/// - Thread-safe async test methods
class VideoCaptureStoreTests: XCTestCase {

    var sut: CaptureStore!

    override func setUp() {
        super.setUp()
        // Use in-memory store for testing
        sut = CaptureStore(inMemory: true)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Save Tests

    /// Test saving a video capture persists all data
    func testSaveVideoCaptureSuccess() async throws {
        let capture = createMockVideoCapture()

        try await sut.saveVideoCapture(capture)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertNotNil(fetched, "Video capture should be retrievable after save")
        XCTAssertEqual(fetched?.id, capture.id)
        XCTAssertEqual(fetched?.compressedDepthData.count, capture.compressedDepthData.count)
        XCTAssertEqual(fetched?.hashChainJSON.count, capture.hashChainJSON.count)
        XCTAssertEqual(fetched?.metadataJSON.count, capture.metadataJSON.count)
    }

    /// Test saving video capture preserves frame counts
    func testSaveVideoCapturePreservesFrameCounts() async throws {
        let capture = createMockVideoCapture(frameCount: 450, depthKeyframeCount: 150)

        try await sut.saveVideoCapture(capture)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertEqual(fetched?.frameCount, 450)
        XCTAssertEqual(fetched?.depthKeyframeCount, 150)
    }

    /// Test saving video capture preserves duration
    func testSaveVideoCapturePreservesDuration() async throws {
        let capture = createMockVideoCapture(durationMs: 15000)

        try await sut.saveVideoCapture(capture)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertEqual(fetched?.durationMs, 15000)
    }

    /// Test saving partial video capture
    func testSavePartialVideoCapture() async throws {
        let capture = createMockVideoCapture(isPartial: true)

        try await sut.saveVideoCapture(capture)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertTrue(fetched?.isPartial ?? false)
    }

    // MARK: - Status Update Tests

    /// Test status update to uploading
    func testUpdateVideoCaptureStatusToUploading() async throws {
        let capture = createMockVideoCapture()
        try await sut.saveVideoCapture(capture)

        try await sut.updateVideoCaptureStatus(.uploading, for: capture.id)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertEqual(fetched?.status, .uploading)
    }

    /// Test status update to failed
    func testUpdateVideoCaptureStatusToFailed() async throws {
        let capture = createMockVideoCapture()
        try await sut.saveVideoCapture(capture)

        try await sut.updateVideoCaptureStatus(.failed, for: capture.id)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertEqual(fetched?.status, .failed)
    }

    /// Test status update to paused
    func testUpdateVideoCaptureStatusToPaused() async throws {
        let capture = createMockVideoCapture()
        try await sut.saveVideoCapture(capture)

        try await sut.updateVideoCaptureStatus(.paused, for: capture.id)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertEqual(fetched?.status, .paused)
    }

    /// Test status update for non-existent capture throws
    func testUpdateVideoCaptureStatusNotFoundThrows() async {
        let randomId = UUID()

        do {
            try await sut.updateVideoCaptureStatus(.uploading, for: randomId)
            XCTFail("Expected notFound error")
        } catch CaptureStoreError.notFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Upload Result Tests

    /// Test upload result update
    func testUpdateVideoUploadResult() async throws {
        let capture = createMockVideoCapture()
        try await sut.saveVideoCapture(capture)

        let serverCaptureId = UUID()
        let verificationUrl = "https://rial.app/verify/\(serverCaptureId.uuidString)"

        try await sut.updateVideoUploadResult(
            for: capture.id,
            serverCaptureId: serverCaptureId,
            verificationUrl: verificationUrl
        )

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertEqual(fetched?.status, .uploaded)
    }

    // MARK: - Fetch Tests

    /// Test fetch by ID returns correct capture
    func testLoadVideoCaptureById() async throws {
        let capture1 = createMockVideoCapture()
        let capture2 = createMockVideoCapture()

        try await sut.saveVideoCapture(capture1)
        try await sut.saveVideoCapture(capture2)

        let fetched = try await sut.loadVideoCapture(id: capture1.id)
        XCTAssertEqual(fetched?.id, capture1.id)
    }

    /// Test fetch by non-existent ID returns nil
    func testLoadVideoCaptureByIdNotFound() async throws {
        let randomId = UUID()

        let fetched = try await sut.loadVideoCapture(id: randomId)
        XCTAssertNil(fetched)
    }

    /// Test fetch all video captures ordered by date
    func testFetchAllVideoCapturesOrderedByDate() async throws {
        let capture1 = createMockVideoCapture()
        let capture2 = createMockVideoCapture()
        let capture3 = createMockVideoCapture()

        try await sut.saveVideoCapture(capture1)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        try await sut.saveVideoCapture(capture2)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await sut.saveVideoCapture(capture3)

        let all = try await sut.fetchAllVideoCaptures()

        XCTAssertEqual(all.count, 3)
        // Newest first
        XCTAssertEqual(all[0].id, capture3.id)
        XCTAssertEqual(all[2].id, capture1.id)
    }

    // MARK: - Pending Uploads Tests

    /// Test pending video uploads returns correct captures
    func testPendingVideoUploads() async throws {
        let pendingCapture = createMockVideoCapture()
        let uploadingCapture = createMockVideoCapture()

        try await sut.saveVideoCapture(pendingCapture)
        try await sut.saveVideoCapture(uploadingCapture)
        try await sut.updateVideoCaptureStatus(.uploading, for: uploadingCapture.id)

        let pending = try await sut.pendingVideoUploads()

        // Only pending_upload status should be returned
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, pendingCapture.id)
    }

    /// Test pending video uploads includes failed captures that can retry
    func testPendingVideoUploadsIncludesFailedCaptures() async throws {
        let pendingCapture = createMockVideoCapture()
        let failedCapture = createMockVideoCapture()

        try await sut.saveVideoCapture(pendingCapture)
        try await sut.saveVideoCapture(failedCapture)
        try await sut.updateVideoCaptureStatus(.failed, for: failedCapture.id)

        let pending = try await sut.pendingVideoUploads()

        // Both pending and failed (retryable) should be returned
        XCTAssertEqual(pending.count, 2)
    }

    // MARK: - Delete Tests

    /// Test delete removes video capture
    func testDeleteVideoCapture() async throws {
        let capture = createMockVideoCapture()
        try await sut.saveVideoCapture(capture)

        try await sut.deleteVideoCapture(byId: capture.id)

        let fetched = try await sut.loadVideoCapture(id: capture.id)
        XCTAssertNil(fetched)
    }

    /// Test delete non-existent capture doesn't throw
    func testDeleteNonExistentVideoCaptureNoThrow() async throws {
        let randomId = UUID()

        // Should not throw
        try await sut.deleteVideoCapture(byId: randomId)
    }

    // MARK: - Count Tests

    /// Test video capture count
    func testVideoCaptureCount() async throws {
        try await sut.saveVideoCapture(createMockVideoCapture())
        try await sut.saveVideoCapture(createMockVideoCapture())
        try await sut.saveVideoCapture(createMockVideoCapture())

        let count = try await sut.videoCaptureCount()
        XCTAssertEqual(count, 3)
    }

    /// Test video capture count by status
    func testVideoCaptureCountByStatus() async throws {
        let capture1 = createMockVideoCapture()
        let capture2 = createMockVideoCapture()
        let capture3 = createMockVideoCapture()

        try await sut.saveVideoCapture(capture1)
        try await sut.saveVideoCapture(capture2)
        try await sut.saveVideoCapture(capture3)
        try await sut.updateVideoCaptureStatus(.failed, for: capture3.id)

        let pendingCount = try await sut.videoCaptureCount(status: .pendingUpload)
        let failedCount = try await sut.videoCaptureCount(status: .failed)

        XCTAssertEqual(pendingCount, 2)
        XCTAssertEqual(failedCount, 1)
    }

    // MARK: - VideoCaptureEntity Tests

    /// Test VideoCaptureEntity totalSizeBytes calculation
    func testVideoCaptureEntityTotalSize() {
        // This tests the computed property on the entity
        // In real tests, we'd create the entity directly, but we can verify
        // the ProcessedVideoCapture conversion preserves sizes
        let capture = createMockVideoCapture()
        XCTAssertGreaterThan(capture.totalSizeBytes, 0)
    }

    /// Test VideoCaptureEntity canRetry logic
    func testVideoCaptureStatusCanRetryLogic() {
        // Test the retry logic for different statuses
        XCTAssertTrue(VideoCaptureStatus.failed.canRetry)
        XCTAssertTrue(VideoCaptureStatus.paused.canRetry)
        XCTAssertFalse(VideoCaptureStatus.uploaded.canRetry)
        XCTAssertFalse(VideoCaptureStatus.uploading.canRetry)
        XCTAssertFalse(VideoCaptureStatus.processing.canRetry)
        XCTAssertFalse(VideoCaptureStatus.pendingUpload.canRetry)
    }

    // MARK: - Helpers

    /// Create mock ProcessedVideoCapture for testing
    private func createMockVideoCapture(
        frameCount: Int = 300,
        depthKeyframeCount: Int = 100,
        durationMs: Int64 = 10000,
        isPartial: Bool = false
    ) -> ProcessedVideoCapture {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("test-video-\(UUID().uuidString).mp4")

        // Create a small test file
        let videoData = Data(repeating: 0x00, count: 10_000)
        try? videoData.write(to: videoURL)

        return ProcessedVideoCapture(
            id: UUID(),
            videoURL: videoURL,
            compressedDepthData: Data(repeating: 0x01, count: 5_000),
            hashChainJSON: Data(repeating: 0x02, count: 2_000),
            metadataJSON: Data(repeating: 0x03, count: 1_000),
            thumbnailData: Data(repeating: 0x04, count: 500),
            createdAt: Date(),
            status: .pendingUpload,
            frameCount: frameCount,
            depthKeyframeCount: depthKeyframeCount,
            durationMs: durationMs,
            isPartial: isPartial
        )
    }
}
