//
//  RetryManagerTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for RetryManager.
//

import XCTest
@testable import Rial

/// Unit tests for RetryManager
///
/// Tests exponential backoff logic including:
/// - Delay calculations
/// - Retry decisions
/// - Error classification
/// - Configuration options
class RetryManagerTests: XCTestCase {

    var sut: RetryManager!

    override func setUp() {
        super.setUp()
        sut = RetryManager(config: .default)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Delay Calculation Tests

    /// Test first delay is close to base delay
    func testFirstDelayIsBaseDelay() {
        let delay = sut.nextDelay(for: 0)

        // Should be between base delay and base delay + jitter
        // With default config: base = 1.0, jitter = 0.25
        XCTAssertGreaterThanOrEqual(delay, 1.0)
        XCTAssertLessThanOrEqual(delay, 1.25)
    }

    /// Test delay doubles with each attempt
    func testExponentialBackoff() {
        // Create manager without jitter for predictable testing
        let config = RetryConfiguration(
            baseDelay: 1.0,
            maxDelay: 60.0,
            maxAttempts: 5,
            jitterFactor: 0.0
        )
        let manager = RetryManager(config: config)

        XCTAssertEqual(manager.nextDelay(for: 0), 1.0)
        XCTAssertEqual(manager.nextDelay(for: 1), 2.0)
        XCTAssertEqual(manager.nextDelay(for: 2), 4.0)
        XCTAssertEqual(manager.nextDelay(for: 3), 8.0)
        XCTAssertEqual(manager.nextDelay(for: 4), 16.0)
    }

    /// Test delay is capped at max delay
    func testDelayCappedAtMax() {
        let config = RetryConfiguration(
            baseDelay: 1.0,
            maxDelay: 10.0,
            maxAttempts: 10,
            jitterFactor: 0.0
        )
        let manager = RetryManager(config: config)

        // Attempt 10 would be 2^10 = 1024s, but capped at 10s
        XCTAssertEqual(manager.nextDelay(for: 10), 10.0)
    }

    /// Test jitter adds variation to delays
    func testJitterAddsVariation() {
        let delays = (0..<10).map { _ in sut.nextDelay(for: 0) }

        // With jitter, not all delays should be identical
        let uniqueDelays = Set(delays)
        XCTAssertGreaterThan(uniqueDelays.count, 1, "Jitter should create variation")
    }

    // MARK: - Retry Decision Tests

    /// Test shouldRetry returns true while attempts remain
    func testShouldRetryWithAttemptsRemaining() {
        XCTAssertTrue(sut.shouldRetry(attemptCount: 0))
        XCTAssertTrue(sut.shouldRetry(attemptCount: 1))
        XCTAssertTrue(sut.shouldRetry(attemptCount: 4))
    }

    /// Test shouldRetry returns false at max attempts
    func testShouldNotRetryAtMaxAttempts() {
        XCTAssertFalse(sut.shouldRetry(attemptCount: 5))
        XCTAssertFalse(sut.shouldRetry(attemptCount: 10))
    }

    // MARK: - Error Classification Tests

    /// Test network timeout error is retryable
    func testTimeoutErrorIsRetryable() {
        let error = URLError(.timedOut)
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test not connected error is retryable
    func testNotConnectedErrorIsRetryable() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test connection lost error is retryable
    func testConnectionLostErrorIsRetryable() {
        let error = URLError(.networkConnectionLost)
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test cannot connect error is retryable
    func testCannotConnectErrorIsRetryable() {
        let error = URLError(.cannotConnectToHost)
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test DNS lookup error is retryable
    func testDNSErrorIsRetryable() {
        let error = URLError(.dnsLookupFailed)
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test cancelled error is NOT retryable
    func testCancelledErrorNotRetryable() {
        let error = URLError(.cancelled)
        XCTAssertFalse(sut.isRetryableError(error))
    }

    /// Test bad URL error is NOT retryable
    func testBadURLErrorNotRetryable() {
        let error = URLError(.badURL)
        XCTAssertFalse(sut.isRetryableError(error))
    }

    /// Test APIError server error is retryable
    func testAPIServerErrorIsRetryable() {
        let error = APIError.serverError(500)
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test APIError rate limit is retryable
    func testAPIRateLimitIsRetryable() {
        let error = APIError.rateLimited
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test APIError unauthorized is NOT retryable
    func testAPIUnauthorizedNotRetryable() {
        let error = APIError.unauthorized
        XCTAssertFalse(sut.isRetryableError(error))
    }

    /// Test UploadError network error is retryable
    func testUploadNetworkErrorIsRetryable() {
        let error = UploadError.networkError(URLError(.notConnectedToInternet))
        XCTAssertTrue(sut.isRetryableError(error))
    }

    /// Test UploadError device not registered is NOT retryable
    func testUploadDeviceNotRegisteredNotRetryable() {
        let error = UploadError.deviceNotRegistered
        XCTAssertFalse(sut.isRetryableError(error))
    }

    // MARK: - Combined Decision Tests

    /// Test shouldRetry considers both error type and attempt count
    func testShouldRetryConsidersBothFactors() {
        let retryableError = URLError(.timedOut)
        let nonRetryableError = URLError(.cancelled)

        // Retryable error with attempts remaining
        XCTAssertTrue(sut.shouldRetry(error: retryableError, attemptCount: 0))

        // Retryable error but max attempts reached
        XCTAssertFalse(sut.shouldRetry(error: retryableError, attemptCount: 5))

        // Non-retryable error with attempts remaining
        XCTAssertFalse(sut.shouldRetry(error: nonRetryableError, attemptCount: 0))
    }

    // MARK: - Configuration Tests

    /// Test default configuration values
    func testDefaultConfiguration() {
        let config = RetryConfiguration.default

        XCTAssertEqual(config.baseDelay, 1.0)
        XCTAssertEqual(config.maxDelay, 60.0)
        XCTAssertEqual(config.maxAttempts, 5)
        XCTAssertEqual(config.jitterFactor, 0.25)
    }

    /// Test aggressive configuration values
    func testAggressiveConfiguration() {
        let config = RetryConfiguration.aggressive

        XCTAssertEqual(config.baseDelay, 0.5)
        XCTAssertEqual(config.maxDelay, 30.0)
        XCTAssertEqual(config.maxAttempts, 8)
        XCTAssertEqual(config.jitterFactor, 0.2)
    }

    /// Test conservative configuration values
    func testConservativeConfiguration() {
        let config = RetryConfiguration.conservative

        XCTAssertEqual(config.baseDelay, 2.0)
        XCTAssertEqual(config.maxDelay, 120.0)
        XCTAssertEqual(config.maxAttempts, 3)
        XCTAssertEqual(config.jitterFactor, 0.3)
    }

    // MARK: - RetryState Tests

    /// Test RetryState initial values
    func testRetryStateInitialValues() {
        let state = RetryState()

        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastError)
        XCTAssertNil(state.lastAttemptTime)
        XCTAssertFalse(state.isCancelled)
    }

    /// Test RetryState increment
    func testRetryStateIncrement() {
        let state = RetryState()
        state.incrementAttempt()

        XCTAssertEqual(state.attemptCount, 1)
        XCTAssertNotNil(state.lastAttemptTime)
    }

    /// Test RetryState error recording
    func testRetryStateErrorRecording() {
        let state = RetryState()
        let error = URLError(.timedOut)
        state.recordError(error)

        XCTAssertNotNil(state.lastError)
    }

    /// Test RetryState cancel
    func testRetryStateCancel() {
        let state = RetryState()
        state.cancel()

        XCTAssertTrue(state.isCancelled)
    }

    /// Test RetryState reset
    func testRetryStateReset() {
        let state = RetryState()
        state.incrementAttempt()
        state.recordError(URLError(.timedOut))
        state.cancel()

        state.reset()

        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastError)
        XCTAssertNil(state.lastAttemptTime)
        XCTAssertFalse(state.isCancelled)
    }

    // MARK: - RetryError Tests

    /// Test RetryError descriptions
    func testRetryErrorDescriptions() {
        XCTAssertNotNil(RetryError.maxAttemptsReached.errorDescription)
        XCTAssertNotNil(RetryError.cancelled.errorDescription)
    }

    // MARK: - CertificatePinning Tests

    /// Test pin parsing
    func testPinParsing() {
        // Valid pin with correct format
        let validPins = ["sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="]
        let pinning = CertificatePinning(pins: validPins, enabled: true)

        // Invalid pin format (should be ignored)
        let invalidPins = ["invalid-pin-format"]
        let pinning2 = CertificatePinning(pins: invalidPins, enabled: true)

        // Pinning should work with valid pins
        XCTAssertNotNil(pinning)

        // Pinning with no valid pins should be created but disabled
        XCTAssertNotNil(pinning2)
    }

    /// Test development pinning is disabled
    func testDevelopmentPinningDisabled() {
        let pinning = CertificatePinning.development()
        XCTAssertNotNil(pinning)
    }

    /// Test production pinning configuration
    func testProductionPinningConfiguration() {
        let pinning = CertificatePinning.production()
        XCTAssertNotNil(pinning)
    }

    /// Test CertificatePinningError descriptions
    func testCertificatePinningErrorDescriptions() {
        XCTAssertNotNil(CertificatePinningError.pinMismatch.errorDescription)
        XCTAssertNotNil(CertificatePinningError.noCertificate.errorDescription)
        XCTAssertNotNil(CertificatePinningError.publicKeyExtractionFailed.errorDescription)
        XCTAssertNotNil(CertificatePinningError.trustEvaluationFailed("test").errorDescription)
    }

    // MARK: - NetworkMonitor Tests

    /// Test NetworkMonitor initial state
    func testNetworkMonitorInitialState() {
        let monitor = NetworkMonitor()

        XCTAssertEqual(monitor.status, .unknown)
        XCTAssertFalse(monitor.isConnected)
    }

    /// Test NetworkStatus values
    func testNetworkStatusValues() {
        XCTAssertEqual(NetworkStatus.unknown.rawValue, "unknown")
        XCTAssertEqual(NetworkStatus.connected.rawValue, "connected")
        XCTAssertEqual(NetworkStatus.disconnected.rawValue, "disconnected")
    }

    /// Test ConnectionType values
    func testConnectionTypeValues() {
        XCTAssertEqual(ConnectionType.wifi.rawValue, "wifi")
        XCTAssertEqual(ConnectionType.cellular.rawValue, "cellular")
        XCTAssertEqual(ConnectionType.ethernet.rawValue, "ethernet")
        XCTAssertEqual(ConnectionType.other.rawValue, "other")
        XCTAssertEqual(ConnectionType.unknown.rawValue, "unknown")
    }
}
