//
//  DebugLogEntryTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-05.
//
//  Unit tests for DebugLogEntry Codable serialization.
//

import XCTest
@testable import Rial

#if DEBUG

/// Test suite for DebugLogEntry serialization and model behavior.
///
/// Tests cover:
/// - JSON encoding with correct snake_case keys
/// - JSON decoding roundtrip
/// - LogLevel and LogSource enum serialization
/// - AnyCodable handling of various types
class DebugLogEntryTests: XCTestCase {

    // MARK: - JSON Encoder Configuration

    /// Configured encoder matching DebugLogShipper
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys] // For predictable test output
        return encoder
    }()

    /// Configured decoder for roundtrip testing
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - DebugLogEntry Encoding Tests

    func testDebugLogEntry_EncodesToJSON_WithCorrectSnakeCaseKeys() throws {
        let entry = DebugLogEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            correlationId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            timestamp: ISO8601DateFormatter().date(from: "2025-12-05T10:00:00Z")!,
            source: .ios,
            level: .info,
            event: "TEST_EVENT",
            payload: ["key": AnyCodable("value")],
            deviceId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sessionId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )

        let data = try encoder.encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify snake_case keys
        XCTAssertNotNil(json["id"], "Should have 'id' key")
        XCTAssertNotNil(json["correlation_id"], "Should have 'correlation_id' key (snake_case)")
        XCTAssertNotNil(json["timestamp"], "Should have 'timestamp' key")
        XCTAssertNotNil(json["source"], "Should have 'source' key")
        XCTAssertNotNil(json["level"], "Should have 'level' key")
        XCTAssertNotNil(json["event"], "Should have 'event' key")
        XCTAssertNotNil(json["payload"], "Should have 'payload' key")
        XCTAssertNotNil(json["device_id"], "Should have 'device_id' key (snake_case)")
        XCTAssertNotNil(json["session_id"], "Should have 'session_id' key (snake_case)")

        // Verify no camelCase keys leaked
        XCTAssertNil(json["correlationId"], "Should NOT have camelCase 'correlationId'")
        XCTAssertNil(json["deviceId"], "Should NOT have camelCase 'deviceId'")
        XCTAssertNil(json["sessionId"], "Should NOT have camelCase 'sessionId'")
    }

    func testDebugLogEntry_EncodeDecode_Roundtrip() throws {
        let original = DebugLogEntry(
            id: UUID(),
            correlationId: UUID(),
            timestamp: Date(),
            source: .ios,
            level: .warn,
            event: "ROUNDTRIP_TEST",
            payload: [
                "string": AnyCodable("test"),
                "number": AnyCodable(42),
                "bool": AnyCodable(true)
            ],
            deviceId: UUID(),
            sessionId: UUID()
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DebugLogEntry.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.correlationId, decoded.correlationId)
        XCTAssertEqual(original.source, decoded.source)
        XCTAssertEqual(original.level, decoded.level)
        XCTAssertEqual(original.event, decoded.event)
        XCTAssertEqual(original.deviceId, decoded.deviceId)
        XCTAssertEqual(original.sessionId, decoded.sessionId)
    }

    func testDebugLogEntry_WithNilDeviceId_EncodesCorrectly() throws {
        let entry = DebugLogEntry(
            id: UUID(),
            correlationId: UUID(),
            timestamp: Date(),
            source: .ios,
            level: .info,
            event: "NO_DEVICE_ID",
            payload: [:],
            deviceId: nil,
            sessionId: UUID()
        )

        let data = try encoder.encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // device_id should be null (NSNull) not missing
        XCTAssertTrue(json.keys.contains("device_id"), "Should have device_id key even when nil")
    }

    // MARK: - LogLevel Tests

    func testLogLevel_SerializesAsExpectedStrings() throws {
        let levels: [LogLevel] = [.debug, .info, .warn, .error]
        let expected = ["debug", "info", "warn", "error"]

        for (level, expectedString) in zip(levels, expected) {
            let data = try encoder.encode(level)
            let string = try decoder.decode(String.self, from: data)
            XCTAssertEqual(string, expectedString, "\(level) should serialize as '\(expectedString)'")
        }
    }

    func testLogLevel_DecodesFromStrings() throws {
        let jsonStrings = ["\"debug\"", "\"info\"", "\"warn\"", "\"error\""]
        let expected: [LogLevel] = [.debug, .info, .warn, .error]

        for (jsonString, expectedLevel) in zip(jsonStrings, expected) {
            let data = jsonString.data(using: .utf8)!
            let level = try decoder.decode(LogLevel.self, from: data)
            XCTAssertEqual(level, expectedLevel)
        }
    }

    // MARK: - LogSource Tests

    func testLogSource_SerializesAsExpectedStrings() throws {
        let sources: [LogSource] = [.ios, .backend, .web]
        let expected = ["ios", "backend", "web"]

        for (source, expectedString) in zip(sources, expected) {
            let data = try encoder.encode(source)
            let string = try decoder.decode(String.self, from: data)
            XCTAssertEqual(string, expectedString, "\(source) should serialize as '\(expectedString)'")
        }
    }

    func testLogSource_DecodesFromStrings() throws {
        let jsonStrings = ["\"ios\"", "\"backend\"", "\"web\""]
        let expected: [LogSource] = [.ios, .backend, .web]

        for (jsonString, expectedSource) in zip(jsonStrings, expected) {
            let data = jsonString.data(using: .utf8)!
            let source = try decoder.decode(LogSource.self, from: data)
            XCTAssertEqual(source, expectedSource)
        }
    }

    // MARK: - AnyCodable Tests

    func testAnyCodable_EncodesBool() throws {
        let value = AnyCodable(true)
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(Bool.self, from: data)
        XCTAssertEqual(decoded, true)

        let falseValue = AnyCodable(false)
        let falseData = try encoder.encode(falseValue)
        let decodedFalse = try decoder.decode(Bool.self, from: falseData)
        XCTAssertEqual(decodedFalse, false)
    }

    func testAnyCodable_EncodesInt() throws {
        let value = AnyCodable(42)
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(Int.self, from: data)
        XCTAssertEqual(decoded, 42)

        let negativeValue = AnyCodable(-100)
        let negData = try encoder.encode(negativeValue)
        let decodedNeg = try decoder.decode(Int.self, from: negData)
        XCTAssertEqual(decodedNeg, -100)
    }

    func testAnyCodable_EncodesDouble() throws {
        let value = AnyCodable(3.14159)
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(Double.self, from: data)
        XCTAssertEqual(decoded, 3.14159, accuracy: 0.00001)
    }

    func testAnyCodable_EncodesString() throws {
        let value = AnyCodable("Hello, World!")
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(String.self, from: data)
        XCTAssertEqual(decoded, "Hello, World!")
    }

    func testAnyCodable_EncodesArray() throws {
        let value = AnyCodable([1, 2, 3])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode([Int].self, from: data)
        XCTAssertEqual(decoded, [1, 2, 3])
    }

    func testAnyCodable_EncodesDictionary() throws {
        let dict: [String: Any] = ["name": "test", "count": 42]
        let value = AnyCodable(dict)
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["name"] as? String, "test")
        XCTAssertEqual(json["count"] as? Int, 42)
    }

    func testAnyCodable_EncodesNestedStructures() throws {
        let nested: [String: Any] = [
            "user": [
                "name": "John",
                "age": 30
            ],
            "scores": [95, 87, 92]
        ]
        let value = AnyCodable(nested)
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let user = json["user"] as! [String: Any]
        XCTAssertEqual(user["name"] as? String, "John")
        XCTAssertEqual(user["age"] as? Int, 30)

        let scores = json["scores"] as! [Int]
        XCTAssertEqual(scores, [95, 87, 92])
    }

    func testAnyCodable_DecodesFromJSON() throws {
        let jsonString = """
        {"string": "hello", "number": 42, "bool": true, "null": null}
        """
        let data = jsonString.data(using: .utf8)!
        let decoded = try decoder.decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["string"]?.value as? String, "hello")
        XCTAssertEqual(decoded["number"]?.value as? Int, 42)
        XCTAssertEqual(decoded["bool"]?.value as? Bool, true)
        XCTAssertTrue(decoded["null"]?.value is NSNull)
    }

    func testAnyCodable_Equality() {
        let value1 = AnyCodable("test")
        let value2 = AnyCodable("test")
        let value3 = AnyCodable("different")

        XCTAssertEqual(value1, value2)
        XCTAssertNotEqual(value1, value3)
    }

    // MARK: - Batch Encoding Tests

    func testDebugLogEntry_BatchEncoding() throws {
        let entries = [
            DebugLogEntry(
                id: UUID(),
                correlationId: UUID(),
                timestamp: Date(),
                source: .ios,
                level: .info,
                event: "EVENT_1",
                payload: [:],
                deviceId: nil,
                sessionId: UUID()
            ),
            DebugLogEntry(
                id: UUID(),
                correlationId: UUID(),
                timestamp: Date(),
                source: .ios,
                level: .error,
                event: "EVENT_2",
                payload: ["error": AnyCodable("Something went wrong")],
                deviceId: UUID(),
                sessionId: UUID()
            )
        ]

        let data = try encoder.encode(entries)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json[0]["event"] as? String, "EVENT_1")
        XCTAssertEqual(json[1]["event"] as? String, "EVENT_2")
    }
}

#endif
