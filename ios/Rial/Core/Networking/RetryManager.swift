//
//  RetryManager.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Exponential backoff retry logic for network operations.
//

import Foundation
import os.log

/// Manager for retry logic with exponential backoff.
///
/// Implements a robust retry strategy with exponential backoff and jitter
/// to handle transient network failures gracefully.
///
/// ## Retry Strategy
/// - Exponential backoff: delay doubles with each attempt
/// - Jitter: random variation to prevent thundering herd
/// - Maximum delay cap to prevent excessive waits
/// - Configurable max attempts before permanent failure
///
/// ## Usage
/// ```swift
/// let retry = RetryManager()
///
/// func uploadWithRetry() async throws {
///     var attemptCount = 0
///
///     while true {
///         do {
///             try await upload()
///             return // Success
///         } catch let error where retry.shouldRetry(error: error, attemptCount: attemptCount) {
///             let delay = retry.nextDelay(for: attemptCount)
///             try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
///             attemptCount += 1
///         }
///     }
/// }
/// ```
final class RetryManager {
    private static let logger = Logger(subsystem: "app.rial", category: "retry-manager")

    /// Configuration for retry behavior
    let config: RetryConfiguration

    // MARK: - Initialization

    /// Creates a new RetryManager with default configuration.
    init(config: RetryConfiguration = .default) {
        self.config = config
    }

    // MARK: - Retry Logic

    /// Calculate the next delay for a given attempt count.
    ///
    /// Uses exponential backoff with jitter:
    /// `delay = min(baseDelay * 2^attempt, maxDelay) + jitter`
    ///
    /// - Parameter attemptCount: The current attempt number (0-based)
    /// - Returns: Delay in seconds before next retry
    func nextDelay(for attemptCount: Int) -> TimeInterval {
        // Calculate exponential delay
        let exponentialDelay = config.baseDelay * pow(2.0, Double(attemptCount))

        // Cap at maximum delay
        let cappedDelay = min(exponentialDelay, config.maxDelay)

        // Add jitter (0-25% of delay)
        let jitter = cappedDelay * config.jitterFactor * Double.random(in: 0...1)

        let finalDelay = cappedDelay + jitter

        Self.logger.debug("Retry delay for attempt \(attemptCount): \(String(format: "%.2f", finalDelay))s")

        return finalDelay
    }

    /// Determine if another retry should be attempted.
    ///
    /// - Parameter attemptCount: The current attempt number (0-based)
    /// - Returns: `true` if retry should be attempted
    func shouldRetry(attemptCount: Int) -> Bool {
        attemptCount < config.maxAttempts
    }

    /// Determine if an error is retryable.
    ///
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - attemptCount: The current attempt number
    /// - Returns: `true` if the error is retryable and attempts remain
    func shouldRetry(error: Error, attemptCount: Int) -> Bool {
        guard shouldRetry(attemptCount: attemptCount) else {
            Self.logger.info("Max attempts (\(self.config.maxAttempts)) reached, not retrying")
            return false
        }

        let isRetryable = isRetryableError(error)
        Self.logger.debug("Error retryable: \(isRetryable) - \(error.localizedDescription)")
        return isRetryable
    }

    /// Check if an error is retryable.
    ///
    /// Retryable errors include:
    /// - Network connectivity issues
    /// - Timeout errors
    /// - Server errors (5xx)
    /// - Rate limiting (429)
    ///
    /// - Parameter error: The error to check
    /// - Returns: `true` if the error is retryable
    func isRetryableError(_ error: Error) -> Bool {
        // Check URL errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }

        // Check API errors
        if let apiError = error as? APIError {
            return apiError.isRetryable
        }

        // Check upload errors
        if let uploadError = error as? UploadError {
            return uploadError.isRetryable
        }

        // Check NSError domain
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    // MARK: - Convenience Methods

    /// Execute an operation with automatic retry.
    ///
    /// - Parameters:
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: The last error if all retries fail
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        var attemptCount = 0
        var lastError: Error?

        while attemptCount <= config.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                if shouldRetry(error: error, attemptCount: attemptCount) {
                    let delay = nextDelay(for: attemptCount)
                    Self.logger.info("Retry attempt \(attemptCount + 1)/\(self.config.maxAttempts) after \(String(format: "%.2f", delay))s")

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attemptCount += 1
                } else {
                    throw error
                }
            }
        }

        throw lastError ?? RetryError.maxAttemptsReached
    }
}

// MARK: - RetryConfiguration

/// Configuration for retry behavior.
struct RetryConfiguration {
    /// Base delay in seconds (first retry)
    let baseDelay: TimeInterval

    /// Maximum delay in seconds (cap)
    let maxDelay: TimeInterval

    /// Maximum number of retry attempts
    let maxAttempts: Int

    /// Jitter factor (0.0 - 1.0)
    let jitterFactor: Double

    /// Default retry configuration.
    static let `default` = RetryConfiguration(
        baseDelay: 1.0,
        maxDelay: 60.0,
        maxAttempts: 5,
        jitterFactor: 0.25
    )

    /// Aggressive retry configuration (more attempts, shorter delays).
    static let aggressive = RetryConfiguration(
        baseDelay: 0.5,
        maxDelay: 30.0,
        maxAttempts: 8,
        jitterFactor: 0.2
    )

    /// Conservative retry configuration (fewer attempts, longer delays).
    static let conservative = RetryConfiguration(
        baseDelay: 2.0,
        maxDelay: 120.0,
        maxAttempts: 3,
        jitterFactor: 0.3
    )
}

// MARK: - RetryError

/// Errors specific to retry operations.
enum RetryError: Error, LocalizedError {
    /// Maximum retry attempts reached
    case maxAttemptsReached

    /// Operation was cancelled
    case cancelled

    var errorDescription: String? {
        switch self {
        case .maxAttemptsReached:
            return "Maximum retry attempts reached"
        case .cancelled:
            return "Retry operation was cancelled"
        }
    }
}

// MARK: - RetryState

/// Tracks the state of a retryable operation.
final class RetryState {
    /// Current attempt count
    private(set) var attemptCount: Int = 0

    /// Last error encountered
    private(set) var lastError: Error?

    /// Time of last attempt
    private(set) var lastAttemptTime: Date?

    /// Whether the operation has been cancelled
    private(set) var isCancelled: Bool = false

    /// Increment attempt count.
    func incrementAttempt() {
        attemptCount += 1
        lastAttemptTime = Date()
    }

    /// Record an error.
    func recordError(_ error: Error) {
        lastError = error
    }

    /// Mark as cancelled.
    func cancel() {
        isCancelled = true
    }

    /// Reset state for a new operation.
    func reset() {
        attemptCount = 0
        lastError = nil
        lastAttemptTime = nil
        isCancelled = false
    }
}
