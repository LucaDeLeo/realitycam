//
//  VideoMetadata.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Metadata collected during video recording for evidence package.
//

import Foundation
import CoreLocation

// MARK: - VideoMetadata

/// Metadata collected during video recording for evidence package.
///
/// Contains temporal, device, location, and attestation information
/// needed for video evidence verification. Designed for JSON serialization
/// with snake_case keys to match backend API expectations.
///
/// ## Usage
/// ```swift
/// let metadata = VideoMetadata(
///     startedAt: recordingStart,
///     endedAt: recordingEnd,
///     durationMs: 15000,
///     frameCount: 450,
///     depthKeyframeCount: 150,
///     resolution: Resolution(width: 1920, height: 1080),
///     codec: "hevc",
///     deviceModel: "iPhone 15 Pro",
///     iosVersion: "17.4",
///     location: CaptureLocation(lat: 37.7749, lng: -122.4194),
///     attestationLevel: "secure_enclave",
///     hashChainFinal: "base64...",
///     assertion: "base64..."
/// )
/// ```
///
/// ## JSON Output
/// Serializes with snake_case keys:
/// ```json
/// {
///   "type": "video",
///   "started_at": "2025-11-27T10:30:00.123Z",
///   "ended_at": "2025-11-27T10:30:15.456Z",
///   "duration_ms": 15333,
///   "frame_count": 460,
///   "depth_keyframe_count": 153,
///   "resolution": { "width": 1920, "height": 1080 },
///   "codec": "hevc",
///   "device_model": "iPhone 15 Pro",
///   "ios_version": "Version 17.4 (Build 21E219)",
///   "location": { "lat": 37.7749, "lng": -122.4194 },
///   "attestation_level": "secure_enclave",
///   "hash_chain_final": "base64encodedstring...",
///   "assertion": "base64encodedstring..."
/// }
/// ```
public struct VideoMetadata: Codable, Equatable, Sendable {
    /// Media type identifier (always "video")
    public let type: String

    /// Recording start timestamp (UTC)
    public let startedAt: Date

    /// Recording end timestamp (UTC)
    public let endedAt: Date

    /// Total recording duration in milliseconds
    public let durationMs: Int64

    /// Total frame count (30fps * duration)
    public let frameCount: Int

    /// Depth keyframe count (10fps * duration)
    public let depthKeyframeCount: Int

    /// Video resolution
    public let resolution: Resolution

    /// Video codec ("h264" or "hevc")
    public let codec: String

    /// Device model (e.g., "iPhone 15 Pro")
    public let deviceModel: String

    /// iOS version string
    public let iosVersion: String

    /// GPS location at recording start (optional)
    public let location: CaptureLocation?

    /// Attestation level from DCAppAttest ("secure_enclave" or "unverified")
    public let attestationLevel: String

    /// Base64-encoded final hash from hash chain
    public let hashChainFinal: String

    /// Base64-encoded DCAppAttest assertion
    public let assertion: String

    /// Creates a new VideoMetadata instance.
    ///
    /// - Parameters:
    ///   - type: Media type (defaults to "video")
    ///   - startedAt: Recording start timestamp (UTC)
    ///   - endedAt: Recording end timestamp (UTC)
    ///   - durationMs: Duration in milliseconds
    ///   - frameCount: Total frames captured
    ///   - depthKeyframeCount: Depth keyframes captured
    ///   - resolution: Video resolution
    ///   - codec: Video codec ("h264" or "hevc")
    ///   - deviceModel: Device model string
    ///   - iosVersion: iOS version string
    ///   - location: GPS location (optional)
    ///   - attestationLevel: Attestation level
    ///   - hashChainFinal: Base64-encoded hash chain final hash
    ///   - assertion: Base64-encoded DCAppAttest assertion
    public init(
        type: String = "video",
        startedAt: Date,
        endedAt: Date,
        durationMs: Int64,
        frameCount: Int,
        depthKeyframeCount: Int,
        resolution: Resolution,
        codec: String,
        deviceModel: String,
        iosVersion: String,
        location: CaptureLocation?,
        attestationLevel: String,
        hashChainFinal: String,
        assertion: String
    ) {
        self.type = type
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.frameCount = frameCount
        self.depthKeyframeCount = depthKeyframeCount
        self.resolution = resolution
        self.codec = codec
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
        self.location = location
        self.attestationLevel = attestationLevel
        self.hashChainFinal = hashChainFinal
        self.assertion = assertion
    }

    // MARK: - CodingKeys

    /// Coding keys for snake_case JSON serialization.
    private enum CodingKeys: String, CodingKey {
        case type
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case frameCount = "frame_count"
        case depthKeyframeCount = "depth_keyframe_count"
        case resolution
        case codec
        case deviceModel = "device_model"
        case iosVersion = "ios_version"
        case location
        case attestationLevel = "attestation_level"
        case hashChainFinal = "hash_chain_final"
        case assertion
    }

    // MARK: - Custom Encoding/Decoding

    /// Custom encoder to ensure ISO 8601 date format with fractional seconds.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(type, forKey: .type)

        // Encode dates as ISO 8601 strings with fractional seconds
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try container.encode(formatter.string(from: startedAt), forKey: .startedAt)
        try container.encode(formatter.string(from: endedAt), forKey: .endedAt)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encode(frameCount, forKey: .frameCount)
        try container.encode(depthKeyframeCount, forKey: .depthKeyframeCount)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(codec, forKey: .codec)
        try container.encode(deviceModel, forKey: .deviceModel)
        try container.encode(iosVersion, forKey: .iosVersion)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(attestationLevel, forKey: .attestationLevel)
        try container.encode(hashChainFinal, forKey: .hashChainFinal)
        try container.encode(assertion, forKey: .assertion)
    }

    /// Custom decoder to handle ISO 8601 date strings.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decode(String.self, forKey: .type)

        // Decode dates from ISO 8601 strings
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startedAtString = try container.decode(String.self, forKey: .startedAt)
        let endedAtString = try container.decode(String.self, forKey: .endedAt)

        // Try fractional seconds first, fall back to standard format
        if let date = formatter.date(from: startedAtString) {
            startedAt = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: startedAtString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .startedAt,
                    in: container,
                    debugDescription: "Invalid ISO 8601 date string: \(startedAtString)"
                )
            }
            startedAt = date
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        if let date = formatter.date(from: endedAtString) {
            endedAt = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: endedAtString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .endedAt,
                    in: container,
                    debugDescription: "Invalid ISO 8601 date string: \(endedAtString)"
                )
            }
            endedAt = date
        }

        durationMs = try container.decode(Int64.self, forKey: .durationMs)
        frameCount = try container.decode(Int.self, forKey: .frameCount)
        depthKeyframeCount = try container.decode(Int.self, forKey: .depthKeyframeCount)
        resolution = try container.decode(Resolution.self, forKey: .resolution)
        codec = try container.decode(String.self, forKey: .codec)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        iosVersion = try container.decode(String.self, forKey: .iosVersion)
        location = try container.decodeIfPresent(CaptureLocation.self, forKey: .location)
        attestationLevel = try container.decode(String.self, forKey: .attestationLevel)
        hashChainFinal = try container.decode(String.self, forKey: .hashChainFinal)
        assertion = try container.decode(String.self, forKey: .assertion)
    }
}

// MARK: - Resolution

/// Video resolution dimensions.
///
/// Simple struct containing width and height in pixels.
/// Used for video metadata to describe capture resolution.
public struct Resolution: Codable, Equatable, Sendable {
    /// Width in pixels
    public let width: Int

    /// Height in pixels
    public let height: Int

    /// Creates a new Resolution.
    ///
    /// - Parameters:
    ///   - width: Width in pixels
    ///   - height: Height in pixels
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Total pixel count (width * height)
    public var pixelCount: Int {
        width * height
    }

    /// Aspect ratio (width / height)
    public var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    /// Human-readable string (e.g., "1920x1080")
    public var description: String {
        "\(width)x\(height)"
    }
}

// MARK: - CaptureLocation

/// GPS location with latitude and longitude for video capture.
///
/// Simplified location structure matching backend API expectations.
/// Uses `lat` and `lng` keys for JSON serialization.
///
/// For more detailed location data (altitude, accuracy), see `LocationData`.
///
/// ## Usage
/// ```swift
/// // From CLLocation
/// let location = CaptureLocation(from: clLocation)
///
/// // Direct values
/// let location = CaptureLocation(lat: 37.7749, lng: -122.4194)
/// ```
public struct CaptureLocation: Codable, Equatable, Sendable {
    /// Latitude in decimal degrees (-90 to 90)
    public let lat: Double

    /// Longitude in decimal degrees (-180 to 180)
    public let lng: Double

    /// Creates a CaptureLocation from explicit coordinates.
    ///
    /// - Parameters:
    ///   - lat: Latitude in decimal degrees
    ///   - lng: Longitude in decimal degrees
    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    /// Creates a CaptureLocation from a CLLocation.
    ///
    /// - Parameter location: Core Location object
    public init(from location: CLLocation) {
        self.lat = location.coordinate.latitude
        self.lng = location.coordinate.longitude
    }

    /// Whether the coordinates are within valid ranges.
    public var isValid: Bool {
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
    }
}
