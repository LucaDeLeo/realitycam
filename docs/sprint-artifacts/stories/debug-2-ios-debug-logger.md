# iOS Debug Logger

**Story Key:** debug-2-ios-debug-logger
**Epic:** Debug Observability System (Quick-Flow)
**Status:** drafted

## Description

Implement the iOS DebugLogger service that captures structured debug events and ships them to the backend in batches. This enables cross-stack request tracing by correlating iOS logs with backend logs via shared correlation IDs. The logger is DEBUG-only and completely compiled out in Release builds.

## Acceptance Criteria

- [ ] AC1: `DebugLogEntry` model correctly serializes to JSON matching the backend schema (id, correlation_id, timestamp, source, level, event, payload, device_id, session_id)
- [ ] AC2: `DebugLogger` actor buffers log entries and ships when buffer reaches 50 entries
- [ ] AC3: `DebugLogger.flush()` immediately ships all buffered entries (used on app background)
- [ ] AC4: `DebugLogShipper` successfully POSTs batch entries to `/debug/logs` endpoint
- [ ] AC5: All debug logging code is wrapped in `#if DEBUG` and excluded from Release builds
- [ ] AC6: Log levels (debug, info, warn, error) are properly supported and serialized
- [ ] AC7: Unit tests pass for buffer management, entry serialization, and shipper logic

## Tasks

- [ ] Task 1: Create `/ios/Rial/Core/Debug/` directory structure and add to Xcode project
- [ ] Task 2: Implement `DebugLogEntry.swift` - Codable model matching backend schema with LogLevel and LogSource enums
- [ ] Task 3: Implement `DebugLogger.swift` - Actor-based singleton with buffer management, log() method, and flush() method
- [ ] Task 4: Implement `DebugLogShipper.swift` - Batch upload service using APIClient pattern (POST to `/debug/logs`)
- [ ] Task 5: Add timer-based auto-ship (every 30 seconds) in DebugLogger
- [ ] Task 6: Create `/ios/RialTests/Debug/` test directory
- [ ] Task 7: Write `DebugLogEntryTests.swift` - Test JSON encoding matches expected schema
- [ ] Task 8: Write `DebugLoggerTests.swift` - Test buffer threshold triggers ship, flush clears buffer
- [ ] Task 9: Write `DebugLogShipperTests.swift` - Test batch request formatting

## Technical Details

### DebugLogEntry Model

```swift
struct DebugLogEntry: Codable {
    let id: UUID
    let correlationId: UUID
    let timestamp: Date
    let source: LogSource
    let level: LogLevel
    let event: String
    let payload: [String: AnyCodable]
    let deviceId: UUID?
    let sessionId: UUID?
}

enum LogLevel: String, Codable {
    case debug, info, warn, error
}

enum LogSource: String, Codable {
    case ios, backend, web
}
```

### DebugLogger Architecture

```swift
#if DEBUG
@MainActor
public final class DebugLogger {
    public static let shared = DebugLogger()

    private var buffer: [DebugLogEntry] = []
    private let shipper: DebugLogShipper
    private var currentSessionId = UUID()
    private var shipTimer: Timer?

    // Buffer threshold
    private let bufferThreshold = 50
    // Ship interval (30 seconds)
    private let shipInterval: TimeInterval = 30

    public func log(event:level:payload:correlationId:)
    public func flush() async
}
#endif
```

### Integration Points

- **APIClient.swift**: Already has X-Correlation-ID header and DebugLogger.log() calls (implemented)
- **RialApp.swift**: Already has background flush hook (implemented)
- **DeviceRegistrationService**: Use for device_id in log entries

### File Locations

**Create:**
- `/ios/Rial/Core/Debug/DebugLogEntry.swift`
- `/ios/Rial/Core/Debug/DebugLogger.swift`
- `/ios/Rial/Core/Debug/DebugLogShipper.swift`
- `/ios/RialTests/Debug/DebugLogEntryTests.swift`
- `/ios/RialTests/Debug/DebugLoggerTests.swift`
- `/ios/RialTests/Debug/DebugLogShipperTests.swift`

**Already Modified (no changes needed):**
- `/ios/Rial/Core/Networking/APIClient.swift` - correlation ID and log calls present
- `/ios/Rial/App/RialApp.swift` - background flush hook present

## Dev Agent Record

### Context Reference
`docs/sprint-artifacts/story-contexts/debug-2-ios-debug-logger-context.xml`

### File List
(populated during implementation)

### Completion Notes
(populated during implementation)

## Source References

- Tech Spec: Section "Story 2: iOS Debug Logger" (lines 563-570)
- Tech Spec: iOS DebugLogger Architecture (lines 428-475)
- Tech Spec: Log Entry Schema (lines 179-193)
- Tech Spec: Source Tree Changes - iOS section (lines 146-154)
