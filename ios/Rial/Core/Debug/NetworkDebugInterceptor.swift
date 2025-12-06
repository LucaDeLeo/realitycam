//
//  NetworkDebugInterceptor.swift
//  Rial
//
//  Created by RealityCam on 2025-12-06.
//
//  Intercepts URLSession requests for debug logging.
//  Captures request/response details with correlation IDs for cross-stack tracing.
//  All code is wrapped in #if DEBUG for zero production impact.
//

import Foundation

#if DEBUG

/// Intercepts URLSession requests for debug logging.
///
/// Captures request/response details with correlation IDs for cross-stack tracing.
/// Use this interceptor in APIClient to log all API interactions for debugging
/// without requiring Xcode.
///
/// ## Usage
/// ```swift
/// #if DEBUG
/// let correlationId = UUID()
/// let startTime = Date()
/// await NetworkDebugInterceptor.logRequest(request, correlationId: correlationId)
/// // ... perform request ...
/// await NetworkDebugInterceptor.logResponse(response, data: data, startTime: startTime, correlationId: correlationId)
/// #endif
/// ```
///
/// ## Header Sanitization
/// Sensitive headers are automatically redacted to avoid logging secrets:
/// - `Authorization` -> `[REDACTED]`
/// - `X-Device-Signature` -> `[REDACTED]`
/// - `X-Signature-Timestamp` -> `[REDACTED]`
public struct NetworkDebugInterceptor {

    /// Headers that should be redacted in logs.
    private static let sensitiveHeaders = [
        "Authorization",
        "X-Device-Signature",
        "X-Signature-Timestamp"
    ]

    // MARK: - Public Methods

    /// Log an outgoing API request.
    ///
    /// Call this BEFORE `session.data(for: request)`.
    ///
    /// - Parameters:
    ///   - request: The URLRequest being sent
    ///   - correlationId: UUID linking request/response logs
    public static func logRequest(
        _ request: URLRequest,
        correlationId: UUID
    ) async {
        await DebugLogger.shared.log(
            event: "API_REQUEST",
            level: .info,
            payload: [
                "method": request.httpMethod ?? "?",
                "url": request.url?.absoluteString ?? "?",
                "path": request.url?.path ?? "?",
                "headers": sanitizedHeaders(request.allHTTPHeaderFields),
                "body_size": request.httpBody?.count ?? 0
            ],
            correlationId: correlationId
        )
    }

    /// Log an API response.
    ///
    /// Call this AFTER `session.data(for: request)` completes successfully.
    ///
    /// - Parameters:
    ///   - response: The HTTPURLResponse received
    ///   - data: Response body data
    ///   - startTime: When the request was initiated (for duration calculation)
    ///   - correlationId: UUID linking request/response logs
    public static func logResponse(
        _ response: HTTPURLResponse,
        data: Data,
        startTime: Date,
        correlationId: UUID
    ) async {
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        await DebugLogger.shared.log(
            event: "API_RESPONSE",
            level: .info,
            payload: [
                "status": response.statusCode,
                "duration_ms": durationMs,
                "body_size": data.count,
                "url": response.url?.absoluteString ?? "?"
            ],
            correlationId: correlationId
        )
    }

    /// Log an API error response.
    ///
    /// Call this when `session.data(for: request)` throws an error.
    ///
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - request: The original request (for URL context)
    ///   - startTime: When the request was initiated (for duration calculation)
    ///   - correlationId: UUID linking request/response logs
    public static func logError(
        _ error: Error,
        request: URLRequest,
        startTime: Date,
        correlationId: UUID
    ) async {
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        await DebugLogger.shared.log(
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
    }

    // MARK: - Private Methods

    /// Sanitize headers to avoid logging sensitive values.
    ///
    /// - Parameter headers: Original request headers
    /// - Returns: Headers with sensitive values redacted
    private static func sanitizedHeaders(_ headers: [String: String]?) -> [String: String] {
        guard let headers = headers else { return [:] }

        var sanitized = headers
        for key in sensitiveHeaders {
            if sanitized[key] != nil {
                sanitized[key] = "[REDACTED]"
            }
        }
        return sanitized
    }

    // MARK: - Testing Helpers

    /// Expose sanitizedHeaders for testing (internal access only).
    internal static func testSanitizedHeaders(_ headers: [String: String]?) -> [String: String] {
        return sanitizedHeaders(headers)
    }
}

#endif
