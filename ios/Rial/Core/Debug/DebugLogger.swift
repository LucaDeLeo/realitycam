//
//  DebugLogger.swift
//  Rial
//
//  Created by RealityCam on 2025-12-05.
//
//  Central debug logging service for iOS app.
//  Uses @MainActor for thread-safe singleton access.
//  All code is wrapped in #if DEBUG for zero production impact.
//

import Foundation
import os.log

#if DEBUG

/// Central debug logging service for iOS app.
///
/// Provides buffered logging with automatic batch uploads to the backend
/// for cross-stack observability. Log entries are shipped when the buffer
/// reaches 50 entries or every 30 seconds (whichever comes first).
///
/// ## Usage
/// ```swift
/// #if DEBUG
/// await DebugLogger.shared.log(
///     event: "CAPTURE_STARTED",
///     level: .info,
///     payload: ["mode": "photo"],
///     correlationId: requestCorrelationId
/// )
/// #endif
/// ```
///
/// ## Thread Safety
/// Uses @MainActor isolation for thread-safe buffer access.
/// The shipper uses actor isolation internally.
@MainActor
public final class DebugLogger {
    private static let logger = Logger(subsystem: "app.rial", category: "debug-logger")

    /// Shared singleton instance
    public static let shared = DebugLogger()

    /// Buffer for pending log entries
    private var buffer: [DebugLogEntry] = []

    /// Log shipper for batch uploads
    private let shipper: DebugLogShipper

    /// Session ID for grouping logs within app session
    private var currentSessionId = UUID()

    /// Timer task for periodic flush
    private var shipTimer: Task<Void, Never>?

    /// Buffer size threshold for automatic shipping (default: 50)
    public let bufferThreshold: Int

    /// Flush interval in seconds (default: 30)
    public let flushInterval: TimeInterval

    /// Keychain service for device ID access
    private let keychain = KeychainService()

    // MARK: - Initialization

    private init() {
        self.bufferThreshold = 50
        self.flushInterval = 30
        self.shipper = DebugLogShipper(baseURL: AppEnvironment.apiBaseURL)
        startFlushTimer()
        Self.logger.info("DebugLogger initialized with session \(self.currentSessionId.uuidString)")
    }

    /// Internal initializer for testing with custom shipper.
    ///
    /// - Parameters:
    ///   - shipper: Custom debug log shipper
    ///   - bufferThreshold: Buffer size before auto-flush (default: 50)
    ///   - flushInterval: Time interval for periodic flush (default: 30s)
    ///   - startTimer: Whether to start the flush timer (default: false for tests)
    internal init(
        shipper: DebugLogShipper,
        bufferThreshold: Int = 50,
        flushInterval: TimeInterval = 30,
        startTimer: Bool = false
    ) {
        self.shipper = shipper
        self.bufferThreshold = bufferThreshold
        self.flushInterval = flushInterval
        if startTimer {
            startFlushTimer()
        }
        // Don't start timer by default in test mode - tests control flushing manually
    }

    // MARK: - Public Methods

    /// Log a debug event.
    ///
    /// Adds the log entry to the buffer. If the buffer exceeds the threshold
    /// (50 entries), triggers an immediate flush.
    ///
    /// - Parameters:
    ///   - event: Event name (e.g., "API_REQUEST", "CAPTURE_STARTED")
    ///   - level: Log severity level (default: .info)
    ///   - payload: Additional context as key-value pairs (default: empty)
    ///   - correlationId: Optional correlation ID for request tracing
    public func log(
        event: String,
        level: LogLevel = .info,
        payload: [String: Any] = [:],
        correlationId: UUID? = nil
    ) {
        let deviceId = getDeviceId()
        let typedPayload = payload.mapValues { AnyCodable($0) }

        let entry = DebugLogEntry(
            id: UUID(),
            correlationId: correlationId ?? UUID(),
            timestamp: Date(),
            source: .ios,
            level: level,
            event: event,
            payload: typedPayload,
            deviceId: deviceId,
            sessionId: currentSessionId
        )
        buffer.append(entry)

        Self.logger.debug("Buffered log: \(event) (buffer size: \(self.buffer.count))")

        // Ship if buffer exceeds threshold
        if buffer.count >= bufferThreshold {
            Task { await flush() }
        }
    }

    /// Force immediate ship of buffered logs.
    ///
    /// Called automatically when:
    /// - Buffer reaches 50 entries
    /// - 30-second timer fires
    /// - App enters background
    public func flush() async {
        guard !buffer.isEmpty else { return }

        let entries = buffer
        buffer.removeAll()

        Self.logger.info("Flushing \(entries.count) log entries")
        await shipper.ship(entries)
    }

    /// Get current buffer count (for testing)
    public var bufferCount: Int {
        buffer.count
    }

    /// Clear buffer without shipping (for testing)
    internal func clearBuffer() {
        buffer.removeAll()
    }

    // MARK: - Private Methods

    /// Start periodic flush timer.
    private func startFlushTimer() {
        shipTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
                await flush()
            }
        }
    }

    /// Get device ID from keychain if available.
    private func getDeviceId() -> UUID? {
        guard let state = try? keychain.loadDeviceState(for: AppEnvironment.apiBaseURL) else {
            return nil
        }
        return UUID(uuidString: state.deviceId)
    }
}

#endif
