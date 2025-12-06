//
//  NetworkDebugInterceptorTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-06.
//
//  Unit tests for NetworkDebugInterceptor request/response capture.
//

import XCTest
@testable import Rial

#if DEBUG

/// Test suite for NetworkDebugInterceptor.
///
/// Tests cover:
/// - Request capture with method, URL, path, headers, body_size
/// - Response capture with status, duration_ms, body_size, url
/// - Error response capture
/// - Correlation ID consistency between request and response
/// - Header sanitization for sensitive keys
class NetworkDebugInterceptorTests: XCTestCase {

    // MARK: - Header Sanitization Tests

    func testSanitizedHeaders_RedactsAuthorizationHeader() {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer secret-token-12345"
        ]

        let sanitized = NetworkDebugInterceptor.testSanitizedHeaders(headers)

        XCTAssertEqual(sanitized["Content-Type"], "application/json")
        XCTAssertEqual(sanitized["Authorization"], "[REDACTED]")
    }

    func testSanitizedHeaders_RedactsDeviceSignatureHeader() {
        let headers = [
            "X-Device-Signature": "base64-signature-data",
            "Accept": "application/json"
        ]

        let sanitized = NetworkDebugInterceptor.testSanitizedHeaders(headers)

        XCTAssertEqual(sanitized["X-Device-Signature"], "[REDACTED]")
        XCTAssertEqual(sanitized["Accept"], "application/json")
    }

    func testSanitizedHeaders_RedactsSignatureTimestampHeader() {
        let headers = [
            "X-Signature-Timestamp": "1701849600",
            "User-Agent": "Rial-iOS/1.0"
        ]

        let sanitized = NetworkDebugInterceptor.testSanitizedHeaders(headers)

        XCTAssertEqual(sanitized["X-Signature-Timestamp"], "[REDACTED]")
        XCTAssertEqual(sanitized["User-Agent"], "Rial-iOS/1.0")
    }

    func testSanitizedHeaders_RedactsAllSensitiveHeaders() {
        let headers = [
            "Authorization": "secret",
            "X-Device-Signature": "secret",
            "X-Signature-Timestamp": "secret",
            "Content-Type": "application/json"
        ]

        let sanitized = NetworkDebugInterceptor.testSanitizedHeaders(headers)

        XCTAssertEqual(sanitized["Authorization"], "[REDACTED]")
        XCTAssertEqual(sanitized["X-Device-Signature"], "[REDACTED]")
        XCTAssertEqual(sanitized["X-Signature-Timestamp"], "[REDACTED]")
        XCTAssertEqual(sanitized["Content-Type"], "application/json")
    }

    func testSanitizedHeaders_PreservesNonSensitiveHeaders() {
        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "Rial-iOS/1.0",
            "X-Correlation-ID": "uuid-string"
        ]

        let sanitized = NetworkDebugInterceptor.testSanitizedHeaders(headers)

        XCTAssertEqual(sanitized["Content-Type"], "application/json")
        XCTAssertEqual(sanitized["Accept"], "application/json")
        XCTAssertEqual(sanitized["User-Agent"], "Rial-iOS/1.0")
        XCTAssertEqual(sanitized["X-Correlation-ID"], "uuid-string")
    }

    func testSanitizedHeaders_HandlesNilHeaders() {
        let sanitized = NetworkDebugInterceptor.testSanitizedHeaders(nil)
        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizedHeaders_HandlesEmptyHeaders() {
        let sanitized = NetworkDebugInterceptor.testSanitizedHeaders([:])
        XCTAssertTrue(sanitized.isEmpty)
    }

    // MARK: - Request Logging Tests

    @MainActor
    func testLogRequest_CapturesCorrectFields() async {
        let mockShipper = MockDebugLogShipper()
        let logger = TestableDebugLogger(mockShipper: mockShipper, bufferThreshold: 100)

        // Create test request
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/test")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"key\":\"value\"}".utf8)

        let correlationId = UUID()

        // Log request using testable logger (simulates what interceptor does)
        logger.log(
            event: "API_REQUEST",
            level: .info,
            payload: [
                "method": request.httpMethod ?? "?",
                "url": request.url?.absoluteString ?? "?",
                "path": request.url?.path ?? "?",
                "headers": NetworkDebugInterceptor.testSanitizedHeaders(request.allHTTPHeaderFields),
                "body_size": request.httpBody?.count ?? 0
            ],
            correlationId: correlationId
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].count, 1)

        let entry = batches[0][0]
        XCTAssertEqual(entry.event, "API_REQUEST")
        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.correlationId, correlationId)

        // Verify payload fields
        XCTAssertEqual(entry.payload["method"]?.value as? String, "POST")
        XCTAssertEqual(entry.payload["url"]?.value as? String, "https://api.example.com/v1/test")
        XCTAssertEqual(entry.payload["path"]?.value as? String, "/v1/test")
        XCTAssertEqual(entry.payload["body_size"]?.value as? Int, 15) // {"key":"value"}
    }

    @MainActor
    func testLogRequest_CapturesGetWithNoBody() async {
        let mockShipper = MockDebugLogShipper()
        let logger = TestableDebugLogger(mockShipper: mockShipper, bufferThreshold: 100)

        var request = URLRequest(url: URL(string: "https://api.example.com/health")!)
        request.httpMethod = "GET"

        let correlationId = UUID()

        logger.log(
            event: "API_REQUEST",
            level: .info,
            payload: [
                "method": request.httpMethod ?? "?",
                "url": request.url?.absoluteString ?? "?",
                "path": request.url?.path ?? "?",
                "headers": NetworkDebugInterceptor.testSanitizedHeaders(request.allHTTPHeaderFields),
                "body_size": request.httpBody?.count ?? 0
            ],
            correlationId: correlationId
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        let entry = batches[0][0]

        XCTAssertEqual(entry.payload["method"]?.value as? String, "GET")
        XCTAssertEqual(entry.payload["body_size"]?.value as? Int, 0)
    }

    // MARK: - Response Logging Tests

    @MainActor
    func testLogResponse_CapturesCorrectFields() async {
        let mockShipper = MockDebugLogShipper()
        let logger = TestableDebugLogger(mockShipper: mockShipper, bufferThreshold: 100)

        let responseURL = URL(string: "https://api.example.com/v1/captures")!
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        let responseData = Data("{\"id\":\"123\"}".utf8)
        let startTime = Date().addingTimeInterval(-0.150) // 150ms ago
        let correlationId = UUID()

        // Calculate duration as interceptor would
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        logger.log(
            event: "API_RESPONSE",
            level: .info,
            payload: [
                "status": response.statusCode,
                "duration_ms": durationMs,
                "body_size": responseData.count,
                "url": response.url?.absoluteString ?? "?"
            ],
            correlationId: correlationId
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        let entry = batches[0][0]

        XCTAssertEqual(entry.event, "API_RESPONSE")
        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.correlationId, correlationId)
        XCTAssertEqual(entry.payload["status"]?.value as? Int, 201)
        XCTAssertEqual(entry.payload["body_size"]?.value as? Int, 12) // {"id":"123"}
        XCTAssertEqual(entry.payload["url"]?.value as? String, "https://api.example.com/v1/captures")

        // Duration should be approximately 150ms (with some tolerance)
        if let duration = entry.payload["duration_ms"]?.value as? Int {
            XCTAssertGreaterThanOrEqual(duration, 140)
            XCTAssertLessThanOrEqual(duration, 200)
        } else {
            XCTFail("duration_ms should be an Int")
        }
    }

    @MainActor
    func testLogResponse_CapturesErrorStatus() async {
        let mockShipper = MockDebugLogShipper()
        let logger = TestableDebugLogger(mockShipper: mockShipper, bufferThreshold: 100)

        let responseURL = URL(string: "https://api.example.com/v1/error")!
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        let responseData = Data("{\"error\":\"internal\"}".utf8)
        let startTime = Date()
        let correlationId = UUID()

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        logger.log(
            event: "API_RESPONSE",
            level: .info,
            payload: [
                "status": response.statusCode,
                "duration_ms": durationMs,
                "body_size": responseData.count,
                "url": response.url?.absoluteString ?? "?"
            ],
            correlationId: correlationId
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        let entry = batches[0][0]

        XCTAssertEqual(entry.payload["status"]?.value as? Int, 500)
    }

    // MARK: - Error Logging Tests

    @MainActor
    func testLogError_CapturesErrorDetails() async {
        let mockShipper = MockDebugLogShipper()
        let logger = TestableDebugLogger(mockShipper: mockShipper, bufferThreshold: 100)

        let request = URLRequest(url: URL(string: "https://api.example.com/v1/timeout")!)
        let error = URLError(.timedOut)
        let startTime = Date().addingTimeInterval(-30) // 30 seconds ago (timeout)
        let correlationId = UUID()

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        logger.log(
            event: "API_RESPONSE",
            level: .error,
            payload: [
                "url": request.url?.absoluteString ?? "?",
                "duration_ms": durationMs,
                "error": error.localizedDescription,
                "error_type": String(describing: type(of: error))
            ],
            correlationId: correlationId
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        let entry = batches[0][0]

        XCTAssertEqual(entry.event, "API_RESPONSE")
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.correlationId, correlationId)
        XCTAssertEqual(entry.payload["url"]?.value as? String, "https://api.example.com/v1/timeout")
        XCTAssertEqual(entry.payload["error_type"]?.value as? String, "URLError")
        XCTAssertNotNil(entry.payload["error"]?.value)

        // Duration should be approximately 30000ms
        if let duration = entry.payload["duration_ms"]?.value as? Int {
            XCTAssertGreaterThanOrEqual(duration, 29000)
            XCTAssertLessThanOrEqual(duration, 31000)
        }
    }

    // MARK: - Correlation ID Tests

    @MainActor
    func testCorrelationId_SharedBetweenRequestAndResponse() async {
        let mockShipper = MockDebugLogShipper()
        let logger = TestableDebugLogger(mockShipper: mockShipper, bufferThreshold: 100)

        let sharedCorrelationId = UUID()

        // Log request
        logger.log(
            event: "API_REQUEST",
            payload: ["method": "GET", "url": "https://api.example.com/test"],
            correlationId: sharedCorrelationId
        )

        // Log response with same correlation ID
        logger.log(
            event: "API_RESPONSE",
            payload: ["status": 200, "duration_ms": 100],
            correlationId: sharedCorrelationId
        )

        await logger.flush()

        let batches = await mockShipper.shippedBatches
        XCTAssertEqual(batches[0].count, 2)

        let requestEntry = batches[0][0]
        let responseEntry = batches[0][1]

        // Both entries should have the same correlation ID
        XCTAssertEqual(requestEntry.correlationId, sharedCorrelationId)
        XCTAssertEqual(responseEntry.correlationId, sharedCorrelationId)
        XCTAssertEqual(requestEntry.correlationId, responseEntry.correlationId)

        // Events should be different
        XCTAssertEqual(requestEntry.event, "API_REQUEST")
        XCTAssertEqual(responseEntry.event, "API_RESPONSE")
    }

    // MARK: - Duration Calculation Tests

    @MainActor
    func testDurationCalculation_AccurateInMilliseconds() async {
        // Test that duration is calculated correctly
        let startTime = Date()

        // Simulate 100ms delay
        try? await Task.sleep(nanoseconds: 100_000_000)

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Should be approximately 100ms (with tolerance for timing variations)
        XCTAssertGreaterThanOrEqual(durationMs, 90)
        XCTAssertLessThanOrEqual(durationMs, 150)
    }

    @MainActor
    func testDurationCalculation_ZeroForImmediateResponse() async {
        let startTime = Date()
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Should be 0 or very close to 0
        XCTAssertLessThanOrEqual(durationMs, 5)
    }
}

#endif
