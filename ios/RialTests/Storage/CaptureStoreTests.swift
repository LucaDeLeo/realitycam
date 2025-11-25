//
//  CaptureStoreTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for CaptureStore and OfflineQueue.
//

import XCTest
@testable import Rial

/// Unit tests for CaptureStore CoreData persistence
///
/// Tests capture storage, status tracking, queue operations,
/// and cleanup functionality.
///
/// ## Testing Strategy
/// - Uses in-memory CoreData store for isolation
/// - No file system persistence between tests
/// - Thread-safe async test methods
class CaptureStoreTests: XCTestCase {

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

    /// Test saving a capture persists all data
    func testSaveCaptureSuccess() async throws {
        let capture = createMockCapture()

        try await sut.saveCapture(capture)

        let fetched = try await sut.fetchCapture(byId: capture.id)
        XCTAssertNotNil(fetched, "Capture should be retrievable after save")
        XCTAssertEqual(fetched?.id, capture.id)
        XCTAssertEqual(fetched?.jpeg.count, capture.jpeg.count)
        XCTAssertEqual(fetched?.depth.count, capture.depth.count)
        XCTAssertEqual(fetched?.metadata.photoHash, capture.metadata.photoHash)
    }

    /// Test saving capture with assertion data
    func testSaveCaptureWithAssertion() async throws {
        var capture = createMockCapture()
        capture.assertion = Data(repeating: 0xAB, count: 1024)
        capture.assertionStatus = .generated

        try await sut.saveCapture(capture)

        let fetched = try await sut.fetchCapture(byId: capture.id)
        XCTAssertNotNil(fetched?.assertion)
        XCTAssertEqual(fetched?.assertion?.count, 1024)
        XCTAssertEqual(fetched?.assertionStatus, .generated)
    }

    /// Test default status is pending
    func testSaveCaptureDefaultStatusPending() async throws {
        let capture = createMockCapture()

        try await sut.saveCapture(capture)

        let pending = try await sut.fetchPendingCaptures()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, capture.id)
    }

    // MARK: - Fetch Tests

    /// Test fetching all captures returns in date order
    func testFetchAllCapturesOrderedByDate() async throws {
        // Create captures with different timestamps
        var capture1 = createMockCapture()
        var capture2 = createMockCapture()
        var capture3 = createMockCapture()

        // Simulate different creation times
        try await sut.saveCapture(capture1)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        try await sut.saveCapture(capture2)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await sut.saveCapture(capture3)

        let all = try await sut.fetchAllCaptures()

        XCTAssertEqual(all.count, 3)
        // Newest first
        XCTAssertEqual(all[0].id, capture3.id)
        XCTAssertEqual(all[2].id, capture1.id)
    }

    /// Test fetch by ID returns correct capture
    func testFetchCaptureById() async throws {
        let capture1 = createMockCapture()
        let capture2 = createMockCapture()

        try await sut.saveCapture(capture1)
        try await sut.saveCapture(capture2)

        let fetched = try await sut.fetchCapture(byId: capture1.id)
        XCTAssertEqual(fetched?.id, capture1.id)
    }

    /// Test fetch by non-existent ID returns nil
    func testFetchCaptureByIdNotFound() async throws {
        let randomId = UUID()

        let fetched = try await sut.fetchCapture(byId: randomId)
        XCTAssertNil(fetched)
    }

    // MARK: - Status Update Tests

    /// Test status update to uploading
    func testUpdateStatusToUploading() async throws {
        let capture = createMockCapture()
        try await sut.saveCapture(capture)

        try await sut.updateStatus(.uploading, for: capture.id)

        // Pending should be empty now
        let pending = try await sut.fetchPendingCaptures()
        XCTAssertEqual(pending.count, 0)
    }

    /// Test status update to uploaded
    func testUpdateStatusToUploaded() async throws {
        let capture = createMockCapture()
        try await sut.saveCapture(capture)

        let serverCaptureId = UUID()
        let verificationUrl = "https://rial.app/verify/\(serverCaptureId.uuidString)"

        try await sut.updateUploadResult(
            for: capture.id,
            serverCaptureId: serverCaptureId,
            verificationUrl: verificationUrl
        )

        let fetched = try await sut.fetchCapture(byId: capture.id)
        XCTAssertNotNil(fetched)
    }

    /// Test status update for non-existent capture throws
    func testUpdateStatusNotFoundThrows() async {
        let randomId = UUID()

        do {
            try await sut.updateStatus(.uploading, for: randomId)
            XCTFail("Expected notFound error")
        } catch CaptureStoreError.notFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Delete Tests

    /// Test delete removes capture
    func testDeleteCapture() async throws {
        let capture = createMockCapture()
        try await sut.saveCapture(capture)

        try await sut.deleteCapture(byId: capture.id)

        let fetched = try await sut.fetchCapture(byId: capture.id)
        XCTAssertNil(fetched)
    }

    /// Test delete non-existent capture doesn't throw
    func testDeleteNonExistentCaptureNoThrow() async throws {
        let randomId = UUID()

        // Should not throw
        try await sut.deleteCapture(byId: randomId)
    }

    // MARK: - Count Tests

    /// Test capture count
    func testCaptureCount() async throws {
        try await sut.saveCapture(createMockCapture())
        try await sut.saveCapture(createMockCapture())
        try await sut.saveCapture(createMockCapture())

        let count = try await sut.captureCount()
        XCTAssertEqual(count, 3)
    }

    /// Test capture count by status
    func testCaptureCountByStatus() async throws {
        let capture1 = createMockCapture()
        let capture2 = createMockCapture()
        let capture3 = createMockCapture()

        try await sut.saveCapture(capture1, status: .pending)
        try await sut.saveCapture(capture2, status: .pending)
        try await sut.saveCapture(capture3, status: .failed)

        let pendingCount = try await sut.captureCount(status: .pending)
        let failedCount = try await sut.captureCount(status: .failed)

        XCTAssertEqual(pendingCount, 2)
        XCTAssertEqual(failedCount, 1)
    }

    // MARK: - Storage Tests

    /// Test storage calculation
    func testStorageUsed() async throws {
        let jpegSize = 100_000
        let depthSize = 50_000

        let capture = createMockCapture(jpegSize: jpegSize, depthSize: depthSize)
        try await sut.saveCapture(capture)

        let used = try await sut.storageUsed()

        // Should be at least jpeg + depth size (plus metadata overhead)
        XCTAssertGreaterThanOrEqual(used, Int64(jpegSize + depthSize))
    }

    // MARK: - Cleanup Tests

    /// Test cleanup doesn't remove recent uploads
    func testCleanupKeepsRecentUploads() async throws {
        let capture = createMockCapture()
        try await sut.saveCapture(capture)

        // Mark as uploaded (just now)
        try await sut.updateUploadResult(
            for: capture.id,
            serverCaptureId: UUID(),
            verificationUrl: "https://example.com"
        )

        try await sut.cleanupOldCaptures()

        // Should still exist (uploaded less than 7 days ago)
        let fetched = try await sut.fetchCapture(byId: capture.id)
        XCTAssertNotNil(fetched)
    }

    // MARK: - Helpers

    /// Create mock CaptureData for testing
    private func createMockCapture(
        jpegSize: Int = 10_000,
        depthSize: Int = 5_000
    ) -> CaptureData {
        let jpeg = Data(repeating: 0x42, count: jpegSize)
        let depth = Data(repeating: 0x43, count: depthSize)

        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone Test",
            photoHash: "mock-hash-\(UUID().uuidString)",
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        return CaptureData(
            id: UUID(),
            jpeg: jpeg,
            depth: depth,
            metadata: metadata,
            assertion: nil,
            assertionStatus: .none,
            assertionAttemptCount: 0,
            timestamp: Date()
        )
    }
}

// MARK: - OfflineQueue Tests

/// Unit tests for OfflineQueue
class OfflineQueueTests: XCTestCase {

    var store: CaptureStore!
    var sut: OfflineQueue!

    @MainActor
    override func setUp() {
        super.setUp()
        store = CaptureStore(inMemory: true)
        sut = OfflineQueue(store: store)
    }

    @MainActor
    override func tearDown() {
        sut = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Enqueue Tests

    /// Test enqueue adds capture to queue
    @MainActor
    func testEnqueueCapture() async throws {
        let capture = createMockCapture()

        await sut.enqueue(capture)

        // Wait for queue count to update
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertEqual(sut.queueCount, 1)
    }

    /// Test dequeue returns oldest capture first
    @MainActor
    func testDequeueReturnsOldestFirst() async throws {
        let capture1 = createMockCapture()
        let capture2 = createMockCapture()

        await sut.enqueue(capture1)
        await sut.enqueue(capture2)

        let dequeued = await sut.dequeue()
        XCTAssertEqual(dequeued?.id, capture1.id)
    }

    // MARK: - Retry Logic Tests

    /// Test retry delay calculation
    @MainActor
    func testRetryDelayExponential() {
        XCTAssertEqual(sut.retryDelay(for: 0), 1.0)  // 2^0 * 1 = 1
        XCTAssertEqual(sut.retryDelay(for: 1), 2.0)  // 2^1 * 1 = 2
        XCTAssertEqual(sut.retryDelay(for: 2), 4.0)  // 2^2 * 1 = 4
        XCTAssertEqual(sut.retryDelay(for: 3), 8.0)  // 2^3 * 1 = 8
        XCTAssertEqual(sut.retryDelay(for: 4), 16.0) // 2^4 * 1 = 16
    }

    /// Test retry delay caps at maximum
    @MainActor
    func testRetryDelayMaximum() {
        // At attempt 10, would be 1024s but should cap at 60s
        XCTAssertEqual(sut.retryDelay(for: 10), 60.0)
    }

    /// Test should retry within limit
    @MainActor
    func testShouldRetryWithinLimit() {
        XCTAssertTrue(sut.shouldRetry(attemptCount: 0))
        XCTAssertTrue(sut.shouldRetry(attemptCount: 4))
        XCTAssertFalse(sut.shouldRetry(attemptCount: 5))
    }

    // MARK: - Statistics Tests

    /// Test statistics returns correct counts
    @MainActor
    func testStatistics() async throws {
        let capture1 = createMockCapture()
        let capture2 = createMockCapture()

        await sut.enqueue(capture1)
        await sut.enqueue(capture2)

        let stats = await sut.statistics()
        XCTAssertEqual(stats.pending, 2)
        XCTAssertEqual(stats.uploading, 0)
        XCTAssertEqual(stats.uploaded, 0)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertGreaterThan(stats.totalBytes, 0)
    }

    // MARK: - Helpers

    private func createMockCapture() -> CaptureData {
        let jpeg = Data(repeating: 0x42, count: 10_000)
        let depth = Data(repeating: 0x43, count: 5_000)

        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone Test",
            photoHash: "mock-hash-\(UUID().uuidString)",
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        return CaptureData(
            id: UUID(),
            jpeg: jpeg,
            depth: depth,
            metadata: metadata,
            assertion: nil,
            assertionStatus: .none,
            assertionAttemptCount: 0,
            timestamp: Date()
        )
    }
}

// MARK: - QueueState Tests

/// Tests for QueueState enum
class QueueStateTests: XCTestCase {

    func testQueueStateDescriptions() {
        XCTAssertEqual(QueueState.empty.description, "No pending uploads")
        XCTAssertEqual(QueueState.waiting(count: 1).description, "1 capture waiting")
        XCTAssertEqual(QueueState.waiting(count: 3).description, "3 captures waiting")
        XCTAssertEqual(QueueState.uploading(current: 2, total: 5).description, "Uploading 2 of 5")
        XCTAssertEqual(QueueState.paused(count: 2).description, "2 captures paused")
        XCTAssertEqual(QueueState.error(message: "Network error").description, "Error: Network error")
    }

    func testQueueStateEquality() {
        XCTAssertEqual(QueueState.empty, QueueState.empty)
        XCTAssertEqual(QueueState.waiting(count: 5), QueueState.waiting(count: 5))
        XCTAssertNotEqual(QueueState.waiting(count: 5), QueueState.waiting(count: 3))
        XCTAssertNotEqual(QueueState.empty, QueueState.waiting(count: 0))
    }
}
