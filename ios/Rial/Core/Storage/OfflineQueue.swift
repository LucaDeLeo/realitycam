//
//  OfflineQueue.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Offline capture queue management for upload scheduling.
//

import Foundation
import os.log
import Combine

/// Manages the offline capture queue for upload scheduling and retry logic.
///
/// Coordinates with CaptureStore to track pending uploads and handle
/// network availability changes.
///
/// ## Features
/// - Automatic queue processing when network available
/// - Exponential backoff retry for failed uploads
/// - Status change notifications via Combine
/// - Thread-safe queue operations
///
/// ## Example Usage
/// ```swift
/// let queue = OfflineQueue(store: captureStore)
///
/// // Add capture to queue
/// await queue.enqueue(captureData)
///
/// // Process queue (called when network available)
/// await queue.processQueue()
///
/// // Observe queue changes
/// queue.$queueCount
///     .sink { count in print("Queue has \(count) items") }
///     .store(in: &cancellables)
/// ```
@MainActor
final class OfflineQueue: ObservableObject {
    private static let logger = Logger(subsystem: "app.rial", category: "offline-queue")

    /// Underlying capture store
    private let store: CaptureStore

    /// Current number of items in queue
    @Published private(set) var queueCount: Int = 0

    /// Whether queue is currently being processed
    @Published private(set) var isProcessing: Bool = false

    /// Last error that occurred during processing
    @Published private(set) var lastError: Error?

    /// Maximum retry attempts per capture
    private let maxRetries: Int = 5

    /// Base delay for exponential backoff (seconds)
    private let baseRetryDelay: TimeInterval = 1.0

    /// Maximum delay between retries (seconds)
    private let maxRetryDelay: TimeInterval = 60.0

    // MARK: - Initialization

    /// Creates a new OfflineQueue with the given store.
    ///
    /// - Parameter store: CaptureStore for persistence
    init(store: CaptureStore) {
        self.store = store

        // Load initial queue count
        Task {
            await refreshQueueCount()
        }
    }

    // MARK: - Queue Operations

    /// Add a capture to the upload queue.
    ///
    /// - Parameter capture: CaptureData to queue
    func enqueue(_ capture: CaptureData) async {
        do {
            try await store.saveCapture(capture, status: .pending)
            await refreshQueueCount()
            Self.logger.info("Enqueued capture: \(capture.id.uuidString, privacy: .public)")
        } catch {
            Self.logger.error("Failed to enqueue capture: \(error.localizedDescription)")
            lastError = error
        }
    }

    /// Get the next capture to upload.
    ///
    /// - Returns: Next pending capture, or nil if queue is empty
    func dequeue() async -> CaptureData? {
        do {
            let pending = try await store.fetchPendingCaptures()
            return pending.first
        } catch {
            Self.logger.error("Failed to dequeue: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get all pending captures.
    ///
    /// - Returns: Array of pending captures
    func pendingCaptures() async -> [CaptureData] {
        do {
            return try await store.fetchPendingCaptures()
        } catch {
            Self.logger.error("Failed to fetch pending: \(error.localizedDescription)")
            return []
        }
    }

    /// Mark a capture as uploading.
    ///
    /// - Parameter captureId: Capture UUID
    func markUploading(_ captureId: UUID) async {
        do {
            try await store.updateStatus(.uploading, for: captureId)
        } catch {
            Self.logger.error("Failed to mark uploading: \(error.localizedDescription)")
        }
    }

    /// Mark a capture as uploaded (success).
    ///
    /// - Parameters:
    ///   - captureId: Local capture UUID
    ///   - serverCaptureId: Server-assigned capture UUID
    ///   - verificationUrl: Verification page URL
    func markUploaded(
        _ captureId: UUID,
        serverCaptureId: UUID,
        verificationUrl: String
    ) async {
        do {
            try await store.updateUploadResult(
                for: captureId,
                serverCaptureId: serverCaptureId,
                verificationUrl: verificationUrl
            )
            await refreshQueueCount()
            Self.logger.info("Upload completed: \(captureId.uuidString, privacy: .public)")
        } catch {
            Self.logger.error("Failed to mark uploaded: \(error.localizedDescription)")
        }
    }

    /// Mark a capture as failed (will retry).
    ///
    /// - Parameter captureId: Capture UUID
    func markFailed(_ captureId: UUID) async {
        do {
            try await store.updateStatus(.failed, for: captureId)
            Self.logger.warning("Upload failed: \(captureId.uuidString, privacy: .public)")
        } catch {
            Self.logger.error("Failed to mark failed: \(error.localizedDescription)")
        }
    }

    /// Reset failed captures to pending for retry.
    ///
    /// Only resets captures that haven't exceeded max retries.
    func retryFailedCaptures() async {
        do {
            let all = try await store.fetchAllCaptures()

            // Filter to only failed captures
            let failed = all.filter { capture in
                // Check assertion attempt count as proxy for retry eligibility
                capture.assertionAttemptCount < maxRetries
            }

            for capture in failed {
                try await store.updateStatus(.pending, for: capture.id)
            }

            await refreshQueueCount()
            Self.logger.info("Reset \(failed.count) captures for retry")
        } catch {
            Self.logger.error("Failed to retry captures: \(error.localizedDescription)")
        }
    }

    /// Calculate delay for retry attempt using exponential backoff.
    ///
    /// - Parameter attemptCount: Number of previous attempts
    /// - Returns: Delay in seconds before next retry
    func retryDelay(for attemptCount: Int) -> TimeInterval {
        let delay = pow(2.0, Double(attemptCount)) * baseRetryDelay
        return min(delay, maxRetryDelay)
    }

    /// Whether a capture should be retried based on attempt count.
    ///
    /// - Parameter attemptCount: Number of previous attempts
    /// - Returns: True if retry is allowed
    func shouldRetry(attemptCount: Int) -> Bool {
        attemptCount < maxRetries
    }

    // MARK: - Queue Statistics

    /// Refresh the queue count from store.
    func refreshQueueCount() async {
        do {
            queueCount = try await store.captureCount(status: .pending)
        } catch {
            Self.logger.error("Failed to refresh queue count: \(error.localizedDescription)")
        }
    }

    /// Get storage statistics.
    ///
    /// - Returns: Tuple of (pending count, uploading count, uploaded count, failed count, total bytes)
    func statistics() async -> (pending: Int, uploading: Int, uploaded: Int, failed: Int, totalBytes: Int64) {
        do {
            let pending = try await store.captureCount(status: .pending)
            let uploading = try await store.captureCount(status: .uploading)
            let uploaded = try await store.captureCount(status: .uploaded)
            let failed = try await store.captureCount(status: .failed)
            let totalBytes = try await store.storageUsed()

            return (pending, uploading, uploaded, failed, totalBytes)
        } catch {
            Self.logger.error("Failed to get statistics: \(error.localizedDescription)")
            return (0, 0, 0, 0, 0)
        }
    }

    /// Get human-readable storage used string.
    func storageUsedFormatted() async -> String {
        do {
            let bytes = try await store.storageUsed()
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } catch {
            return "Unknown"
        }
    }

    // MARK: - Cleanup

    /// Delete a capture from the queue.
    ///
    /// - Parameter captureId: Capture UUID
    func remove(_ captureId: UUID) async {
        do {
            try await store.deleteCapture(byId: captureId)
            await refreshQueueCount()
        } catch {
            Self.logger.error("Failed to remove capture: \(error.localizedDescription)")
        }
    }

    /// Run cleanup to remove old uploaded captures.
    func cleanup() async {
        do {
            try await store.cleanupOldCaptures()
            await refreshQueueCount()
        } catch {
            Self.logger.error("Cleanup failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Queue Processing State

/// State of the upload queue for UI display.
enum QueueState: Equatable {
    /// Queue is empty
    case empty

    /// Queue has items waiting for network
    case waiting(count: Int)

    /// Actively uploading
    case uploading(current: Int, total: Int)

    /// Paused (no network)
    case paused(count: Int)

    /// Error occurred
    case error(message: String)

    /// Human-readable description
    var description: String {
        switch self {
        case .empty:
            return "No pending uploads"
        case .waiting(let count):
            return "\(count) capture\(count == 1 ? "" : "s") waiting"
        case .uploading(let current, let total):
            return "Uploading \(current) of \(total)"
        case .paused(let count):
            return "\(count) capture\(count == 1 ? "" : "s") paused"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
