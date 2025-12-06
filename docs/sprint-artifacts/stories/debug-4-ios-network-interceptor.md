# iOS Network Interceptor

**Story Key:** debug-4-ios-network-interceptor
**Epic:** Debug Observability System (Quick-Flow)
**Status:** done

## Description

Implement a NetworkDebugInterceptor that captures detailed request/response information from all URLSession calls made through APIClient. The interceptor logs both outgoing requests (URL, method, headers, body size) and incoming responses (status code, duration, body size) with the same correlation ID for end-to-end tracing. This enables debugging API interactions without Xcode by querying the backend debug logs via CLI.

## Acceptance Criteria

- [x] AC1: `NetworkDebugInterceptor` captures request details (URL, method, headers, body size) and logs `API_REQUEST` event before each request
- [x] AC2: `NetworkDebugInterceptor` captures response details (status code, duration_ms, body size) and logs `API_RESPONSE` event after each response
- [x] AC3: Both request and response logs share the same correlation ID for tracing
- [x] AC4: Response duration is accurately measured in milliseconds from request start to response completion
- [x] AC5: All interceptor code is wrapped in `#if DEBUG` for zero production impact
- [x] AC6: Unit tests verify request/response capture and correlation ID linking
- [ ] AC7: Integration test demonstrates end-to-end tracing: make API call, query debug logs, see correlated request/response pair (manual test - requires running app)

## Tasks

- [x] Task 1: Create `NetworkDebugInterceptor.swift` in `/ios/Rial/Core/Debug/` with request/response capture methods
- [x] Task 2: Implement `logRequest(_:correlationId:)` method that logs `API_REQUEST` event with method, URL, headers, body_size
- [x] Task 3: Implement `logResponse(_:data:startTime:correlationId:)` method that logs `API_RESPONSE` event with status, duration_ms, body_size
- [x] Task 4: Refactor `APIClient.perform<T>(_:)` to use interceptor for request logging and response timing
- [x] Task 5: Refactor `APIClient.performNoContent(_:)` to use interceptor (DRY up the duplicate logic)
- [x] Task 6: Write `NetworkDebugInterceptorTests.swift` - verify event payloads and correlation ID consistency
- [ ] Task 7: Manual integration test: trigger API request from app, use `bun debug:search --correlation-id <id>` to verify both events appear

## Technical Details

### NetworkDebugInterceptor Design

```swift
#if DEBUG
import Foundation

/// Intercepts URLSession requests for debug logging.
/// Captures request/response details with correlation IDs for cross-stack tracing.
public struct NetworkDebugInterceptor {

    /// Log an outgoing API request.
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
    /// Call this AFTER `session.data(for: request)` completes.
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
            payload: [
                "status": response.statusCode,
                "duration_ms": durationMs,
                "body_size": data.count,
                "url": response.url?.absoluteString ?? "?"
            ],
            correlationId: correlationId
        )
    }

    /// Sanitize headers to avoid logging sensitive values.
    private static func sanitizedHeaders(_ headers: [String: String]?) -> [String: String] {
        guard let headers = headers else { return [:] }

        var sanitized = headers
        // Remove potentially sensitive headers
        let sensitiveKeys = ["Authorization", "X-Device-Signature", "X-Signature-Timestamp"]
        for key in sensitiveKeys {
            if sanitized[key] != nil {
                sanitized[key] = "[REDACTED]"
            }
        }
        return sanitized
    }
}
#endif
```

### APIClient Integration

The current `APIClient.perform<T>(_:)` and `performNoContent(_:)` methods already have inline debug logging. Refactor to use `NetworkDebugInterceptor` for cleaner separation:

**Before (current inline approach):**
```swift
func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
    var request = request

    #if DEBUG
    let correlationId = UUID()
    request.setValue(correlationId.uuidString, forHTTPHeaderField: "X-Correlation-ID")
    await DebugLogger.shared.log(event: "API_REQUEST", payload: [...], correlationId: correlationId)
    #endif

    let (data, response) = try await session.data(for: request)
    // ... validation ...
}
```

**After (using interceptor):**
```swift
func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
    var request = request

    #if DEBUG
    let correlationId = UUID()
    let startTime = Date()
    request.setValue(correlationId.uuidString, forHTTPHeaderField: "X-Correlation-ID")
    await NetworkDebugInterceptor.logRequest(request, correlationId: correlationId)
    #endif

    let (data, response) = try await session.data(for: request)

    #if DEBUG
    if let httpResponse = response as? HTTPURLResponse {
        await NetworkDebugInterceptor.logResponse(httpResponse, data: data, startTime: startTime, correlationId: correlationId)
    }
    #endif

    // ... validation ...
}
```

### Events Logged

| Event | Payload Fields | Description |
|-------|----------------|-------------|
| `API_REQUEST` | method, url, path, headers, body_size | Logged before request sent |
| `API_RESPONSE` | status, duration_ms, body_size, url | Logged after response received |

### Header Sanitization

Sensitive headers are redacted to avoid logging secrets:
- `Authorization` -> `[REDACTED]`
- `X-Device-Signature` -> `[REDACTED]`
- `X-Signature-Timestamp` -> `[REDACTED]`

### File Locations

**Create:**
- `/ios/Rial/Core/Debug/NetworkDebugInterceptor.swift`
- `/ios/RialTests/Debug/NetworkDebugInterceptorTests.swift`

**Modify:**
- `/ios/Rial/Core/Networking/APIClient.swift` - refactor perform methods to use interceptor

### Integration with Existing Code

- **DebugLogger** (story 2): Use `DebugLogger.shared.log()` for event capture
- **APIClient**: Already generates correlation ID and sets `X-Correlation-ID` header - refactor to use interceptor
- **Backend**: Receives correlation ID via header, logs with same ID for cross-stack correlation

## Dev Agent Record

### Context Reference
`docs/sprint-artifacts/story-contexts/debug-4-ios-network-interceptor-context.xml`

### File List

**Created:**
- `/ios/Rial/Core/Debug/NetworkDebugInterceptor.swift` - Main interceptor with logRequest, logResponse, logError methods
- `/ios/RialTests/Debug/NetworkDebugInterceptorTests.swift` - 15 unit tests covering all functionality

**Modified:**
- `/ios/Rial/Core/Networking/APIClient.swift` - Integrated interceptor into perform<T>() and performNoContent()
- `/ios/Rial.xcodeproj/project.pbxproj` - Added new files to Xcode project

### Completion Notes

**Implementation Summary:**
- Created `NetworkDebugInterceptor` as a stateless struct with static methods for logging API requests and responses
- Added `logError()` method to handle network errors with duration tracking
- Integrated interceptor into both `APIClient.perform<T>()` and `performNoContent()` methods
- All code wrapped in `#if DEBUG` for zero production impact
- Header sanitization redacts Authorization, X-Device-Signature, and X-Signature-Timestamp

**Key Design Decisions:**
1. Used static methods on struct (not class/actor) since interceptor is stateless
2. Added `logError()` method in addition to `logResponse()` to capture network failures with error details
3. Exposed `testSanitizedHeaders()` internal method for comprehensive test coverage
4. Duration calculation happens in interceptor to ensure accuracy

**Test Coverage (15 tests, all passing):**
- Header sanitization: 7 tests (redaction, preservation, edge cases)
- Request logging: 2 tests (POST with body, GET without body)
- Response logging: 2 tests (success status, error status)
- Error logging: 1 test (timeout error capture)
- Correlation ID: 1 test (shared between request/response)
- Duration calculation: 2 tests (accuracy, immediate response)

**AC7 Note:** Integration test (Task 7) requires manual verification with running app and backend. All automated tests pass.

## Source References

- Tech Spec: Section "Story 4: iOS Network Interceptor" (lines 580-586)
- Tech Spec: Correlation ID Flow diagram (lines 195-212)
- Tech Spec: iOS DebugLogger Architecture (lines 428-475)
- Tech Spec: Source Tree Changes - iOS NetworkDebugInterceptor (line 152)
- Existing Code: `/ios/Rial/Core/Networking/APIClient.swift` - current inline debug logging (lines 155-172, 195-212)
- Existing Code: `/ios/Rial/Core/Debug/DebugLogger.swift` - DebugLogger.shared.log() API
