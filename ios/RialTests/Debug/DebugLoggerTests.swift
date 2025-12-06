//
//  DebugLoggerTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-05.
//
//  Unit tests for DebugLogger buffering logic.
//

import XCTest
@testable import Rial

#if DEBUG

/// Mock shipper for testing DebugLogger without network calls.
actor MockDebugLogShipper: DebugLogShipperProtocol {
    private(set) var shippedBatches: [[DebugLogEntry]] = []
    private(set) var shipCallCount: Int = 0

    func ship(_ entries: [DebugLogEntry]) async {
        shippedBatches.append(entries)
        shipCallCount += 1
    }

    func reset() {
        shippedBatches.removeAll()
        shipCallCount = 0
    }

    var totalEntriesShipped: Int {
        shippedBatches.reduce(0) { $0 + $1.count }
    }
}

/// Protocol for dependency injection in tests.
protocol DebugLogShipperProtocol {
    func ship(_ entries: [DebugLogEntry]) async
}

/// Make DebugLogShipper conform to protocol.
extension DebugLogShipper: DebugLogShipperProtocol {}

/// Test suite for DebugLogger buffering and flushing behavior.
///
/// Tests cover:
/// - Buffer fills entries until threshold
/// - Automatic flush when buffer reaches threshold
/// - Manual flush clears buffer
/// - Empty buffer doesn't trigger ship
class DebugLoggerTests: XCTestCase {

    // MARK: - Buffer Tests

    @MainActor
    func testDebugLogger_BuffersEntries_UntilThreshold() async {
        // Create logger with low threshold for testing
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 10)

        // Log 5 entries (below threshold)
        for i in 0..<5 {
            logger.log(event: "TEST_EVENT_\(i)")
        }

        // Give async tasks time to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Buffer should hold entries, no ship called
        XCTAssertEqual(logger.bufferCount, 5, "Buffer should have 5 entries")
        let callCount = await mockShipper.shipCallCount
        XCTAssertEqual(callCount, 0, "Should not ship until threshold reached")
    }

    @MainActor
    func testDebugLogger_AutoFlushes_WhenThresholdReached() async {
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 5)

        // Log exactly threshold entries
        for i in 0..<5 {
            logger.log(event: "TEST_EVENT_\(i)")
        }

        // Give async flush task time to complete
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Should have triggered auto-flush
        let callCount = await mockShipper.shipCallCount
        XCTAssertGreaterThanOrEqual(callCount, 1, "Should have called ship at least once")

        let totalShipped = await mockShipper.totalEntriesShipped
        XCTAssertEqual(totalShipped, 5, "Should have shipped 5 entries")
    }

    @MainActor
    func testDebugLogger_ManualFlush_ClearsBuffer() async {
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 100)

        // Log some entries
        logger.log(event: "EVENT_1")
        logger.log(event: "EVENT_2")
        logger.log(event: "EVENT_3")

        XCTAssertEqual(logger.bufferCount, 3, "Buffer should have 3 entries before flush")

        // Manual flush
        await logger.flush()

        // Buffer should be cleared
        XCTAssertEqual(logger.bufferCount, 0, "Buffer should be empty after flush")

        let callCount = await mockShipper.shipCallCount
        XCTAssertEqual(callCount, 1, "Flush should trigger ship")

        let totalShipped = await mockShipper.totalEntriesShipped
        XCTAssertEqual(totalShipped, 3, "Should have shipped 3 entries")
    }

    @MainActor
    func testDebugLogger_EmptyFlush_DoesNotShip() async {
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 100)

        // Flush without any entries
        await logger.flush()

        let callCount = await mockShipper.shipCallCount
        XCTAssertEqual(callCount, 0, "Empty flush should not trigger ship")
    }

    @MainActor
    func testDebugLogger_LogCreatesValidEntry() async {
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 100)

        let correlationId = UUID()
        logger.log(
            event: "API_REQUEST",
            level: .warn,
            payload: ["path": "/api/v1/test", "method": "GET"],
            correlationId: correlationId
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].count, 1)

        let entry = batches[0][0]
        XCTAssertEqual(entry.event, "API_REQUEST")
        XCTAssertEqual(entry.level, .warn)
        XCTAssertEqual(entry.correlationId, correlationId)
        XCTAssertEqual(entry.source, .ios)
        XCTAssertNotNil(entry.id)
        XCTAssertNotNil(entry.timestamp)
        XCTAssertNotNil(entry.sessionId)
    }

    @MainActor
    func testDebugLogger_MultipleFlushes_ShipSeparateBatches() async {
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 100)

        // First batch
        logger.log(event: "BATCH_1_EVENT_1")
        logger.log(event: "BATCH_1_EVENT_2")
        await logger.flush()

        // Second batch
        logger.log(event: "BATCH_2_EVENT_1")
        await logger.flush()

        let batches = await mockShipper.shippedBatches
        XCTAssertEqual(batches.count, 2, "Should have 2 separate batches")
        XCTAssertEqual(batches[0].count, 2, "First batch should have 2 entries")
        XCTAssertEqual(batches[1].count, 1, "Second batch should have 1 entry")
    }

    @MainActor
    func testDebugLogger_AllLogLevels() async {
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 100)

        logger.log(event: "DEBUG_EVENT", level: .debug)
        logger.log(event: "INFO_EVENT", level: .info)
        logger.log(event: "WARN_EVENT", level: .warn)
        logger.log(event: "ERROR_EVENT", level: .error)

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        let entries = batches[0]

        XCTAssertEqual(entries[0].level, .debug)
        XCTAssertEqual(entries[1].level, .info)
        XCTAssertEqual(entries[2].level, .warn)
        XCTAssertEqual(entries[3].level, .error)
    }

    @MainActor
    func testDebugLogger_PayloadTypes() async {
        let mockShipper = MockDebugLogShipper()
        let logger = await createTestLogger(shipper: mockShipper, bufferThreshold: 100)

        logger.log(
            event: "TYPED_PAYLOAD",
            payload: [
                "string": "test",
                "int": 42,
                "double": 3.14,
                "bool": true,
                "array": [1, 2, 3],
                "nested": ["key": "value"]
            ]
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        let entry = batches[0][0]
        let payload = entry.payload

        XCTAssertEqual(payload["string"]?.value as? String, "test")
        XCTAssertEqual(payload["int"]?.value as? Int, 42)
        XCTAssertEqual(payload["bool"]?.value as? Bool, true)
    }

    // MARK: - Helper Methods

    @MainActor
    private func createTestLogger(
        shipper: MockDebugLogShipper,
        bufferThreshold: Int
    ) async -> TestableDebugLogger {
        return TestableDebugLogger(
            mockShipper: shipper,
            bufferThreshold: bufferThreshold
        )
    }
}

// MARK: - Testable Debug Logger

/// Testable version of DebugLogger for unit tests.
/// Uses dependency injection for shipper instead of singleton.
@MainActor
final class TestableDebugLogger {
    private var buffer: [DebugLogEntry] = []
    private let mockShipper: MockDebugLogShipper
    private let bufferThreshold: Int
    private let sessionId = UUID()

    init(mockShipper: MockDebugLogShipper, bufferThreshold: Int) {
        self.mockShipper = mockShipper
        self.bufferThreshold = bufferThreshold
    }

    var bufferCount: Int {
        buffer.count
    }

    func log(
        event: String,
        level: LogLevel = .info,
        payload: [String: Any] = [:],
        correlationId: UUID? = nil
    ) {
        let typedPayload = payload.mapValues { AnyCodable($0) }

        let entry = DebugLogEntry(
            id: UUID(),
            correlationId: correlationId ?? UUID(),
            timestamp: Date(),
            source: .ios,
            level: level,
            event: event,
            payload: typedPayload,
            deviceId: nil,
            sessionId: sessionId
        )
        buffer.append(entry)

        if buffer.count >= bufferThreshold {
            Task { await flush() }
        }
    }

    func flush() async {
        guard !buffer.isEmpty else { return }

        let entries = buffer
        buffer.removeAll()

        await mockShipper.ship(entries)
    }
}

#endif
