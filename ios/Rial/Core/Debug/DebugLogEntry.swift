//
//  DebugLogEntry.swift
//  Rial
//
//  Created by RealityCam on 2025-12-05.
//
//  Debug log entry model with Codable conformance for JSON serialization.
//  All code is wrapped in #if DEBUG for zero production impact.
//

import Foundation

#if DEBUG

// MARK: - Log Entry Model

/// Log entry for debug observability system.
/// Matches backend DebugLog schema for cross-stack correlation.
public struct DebugLogEntry: Codable, Sendable {
    /// Unique identifier for this log entry
    let id: UUID

    /// Correlation ID for tracing requests across iOS/backend
    let correlationId: UUID

    /// Timestamp when the log was created
    let timestamp: Date

    /// Source of the log (always .ios for this client)
    let source: LogSource

    /// Log level (debug, info, warn, error)
    let level: LogLevel

    /// Event name (e.g., "API_REQUEST", "UPLOAD_START")
    let event: String

    /// Flexible JSON payload with additional context
    let payload: [String: AnyCodable]

    /// Device ID from KeychainService (nil if not registered)
    let deviceId: UUID?

    /// Session ID generated per app launch
    let sessionId: UUID

    // CodingKeys for snake_case JSON encoding (backend expects snake_case)
    enum CodingKeys: String, CodingKey {
        case id
        case correlationId = "correlation_id"
        case timestamp
        case source
        case level
        case event
        case payload
        case deviceId = "device_id"
        case sessionId = "session_id"
    }
}

// MARK: - Log Level

/// Log severity levels matching backend schema.
public enum LogLevel: String, Codable, Sendable {
    case debug
    case info
    case warn
    case error
}

// MARK: - Log Source

/// Log source identifiers for cross-stack correlation.
public enum LogSource: String, Codable, Sendable {
    case ios
    case backend
    case web
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for heterogeneous dictionary values.
/// Allows encoding [String: Any] payloads to JSON.
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type for AnyCodable"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            // Fallback: convert to string representation
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - AnyCodable Equatable

extension AnyCodable: Equatable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality check based on string representation
        // For more accurate comparison, would need type-specific checks
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

#endif
