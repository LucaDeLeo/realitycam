//
//  HashOnlyCapturePayload.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Hash-only capture payload for privacy mode (Story 8-3).
//  Contains hash of media instead of raw bytes, with depth analysis and filtered metadata.
//

import Foundation

// MARK: - HashOnlyCapturePayload

/// Payload for privacy mode captures that contains only hash, depth analysis, and filtered metadata.
///
/// When privacy mode is enabled, this payload is uploaded instead of raw media bytes.
/// The server receives cryptographic proof of content (via hash) and device attestation
/// without ever receiving the actual photo or video.
///
/// ## Payload Size
/// Target: < 10KB (typically 2-3KB)
/// - mediaHash: 64 bytes (SHA-256 hex)
/// - depthAnalysis: ~200 bytes JSON
/// - metadata: ~100-500 bytes (depends on privacy levels)
/// - metadataFlags: ~150 bytes
/// - assertion: ~1-2KB Base64
///
/// ## Usage
/// ```swift
/// let payload = HashOnlyPayloadBuilder.build(
///     from: captureData,
///     privacySettings: settings,
///     depthAnalysis: depthResult
/// )
/// // Sign the payload
/// let hash = CryptoService.sha256Data(payloadJSON)
/// let assertion = try await assertionService.generateAssertion(for: hash)
/// payload.assertion = assertion.base64EncodedString()
/// ```
public struct HashOnlyCapturePayload: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Capture mode identifier - always "hash_only" for privacy mode
    public let captureMode: String

    /// SHA-256 hash of the JPEG photo bytes (64-character hex string)
    public let mediaHash: String

    /// Type of media - "photo" or "video"
    public let mediaType: String

    /// Client-side depth analysis result (for photos)
    public let depthAnalysis: DepthAnalysisResult?

    /// Client-side temporal depth analysis result (for videos)
    public let temporalDepthAnalysis: TemporalDepthAnalysisResult?

    /// Privacy-filtered metadata
    public let metadata: FilteredMetadata

    /// Flags indicating what metadata was included/excluded
    public let metadataFlags: MetadataFlags

    /// Capture timestamp (ISO8601 format when encoded)
    public let capturedAt: Date

    /// DCAppAttest assertion covering the entire payload (Base64 encoded)
    /// Set after payload construction via signing
    public var assertion: String

    // MARK: - Video-specific Properties (Optional)

    /// Hash chain data for video integrity (nil for photos)
    public let hashChain: PrivacyHashChainData?

    /// Number of frames in video (nil for photos)
    public let frameCount: Int?

    /// Video duration in milliseconds (nil for photos)
    public let durationMs: Int?

    // MARK: - Initialization

    /// Creates a new HashOnlyCapturePayload for a photo.
    ///
    /// - Parameters:
    ///   - mediaHash: SHA-256 hash of JPEG bytes
    ///   - depthAnalysis: Client-side depth analysis result
    ///   - metadata: Filtered metadata
    ///   - metadataFlags: Metadata inclusion flags
    ///   - capturedAt: Capture timestamp
    ///   - assertion: DCAppAttest assertion (empty string, set later)
    public init(
        mediaHash: String,
        depthAnalysis: DepthAnalysisResult,
        metadata: FilteredMetadata,
        metadataFlags: MetadataFlags,
        capturedAt: Date,
        assertion: String = ""
    ) {
        self.captureMode = "hash_only"
        self.mediaHash = mediaHash
        self.mediaType = "photo"
        self.depthAnalysis = depthAnalysis
        self.temporalDepthAnalysis = nil
        self.metadata = metadata
        self.metadataFlags = metadataFlags
        self.capturedAt = capturedAt
        self.assertion = assertion
        self.hashChain = nil
        self.frameCount = nil
        self.durationMs = nil
    }

    /// Creates a new HashOnlyCapturePayload for a video.
    ///
    /// - Parameters:
    ///   - mediaHash: SHA-256 hash of video bytes
    ///   - temporalDepthAnalysis: Client-side temporal depth analysis result
    ///   - metadata: Filtered metadata
    ///   - metadataFlags: Metadata inclusion flags
    ///   - capturedAt: Capture timestamp
    ///   - assertion: DCAppAttest assertion (empty string, set later)
    ///   - hashChain: Video hash chain data
    ///   - frameCount: Number of frames
    ///   - durationMs: Duration in milliseconds
    public init(
        mediaHash: String,
        temporalDepthAnalysis: TemporalDepthAnalysisResult,
        metadata: FilteredMetadata,
        metadataFlags: MetadataFlags,
        capturedAt: Date,
        assertion: String = "",
        hashChain: PrivacyHashChainData,
        frameCount: Int,
        durationMs: Int
    ) {
        self.captureMode = "hash_only"
        self.mediaHash = mediaHash
        self.mediaType = "video"
        self.depthAnalysis = nil
        self.temporalDepthAnalysis = temporalDepthAnalysis
        self.metadata = metadata
        self.metadataFlags = metadataFlags
        self.capturedAt = capturedAt
        self.assertion = assertion
        self.hashChain = hashChain
        self.frameCount = frameCount
        self.durationMs = durationMs
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case captureMode = "capture_mode"
        case mediaHash = "media_hash"
        case mediaType = "media_type"
        case depthAnalysis = "depth_analysis"
        case temporalDepthAnalysis = "temporal_depth_analysis"
        case metadata
        case metadataFlags = "metadata_flags"
        case capturedAt = "captured_at"
        case assertion
        case hashChain = "hash_chain"
        case frameCount = "frame_count"
        case durationMs = "duration_ms"
    }
}

// MARK: - FilteredMetadata

/// Privacy-filtered metadata for hash-only captures.
///
/// Contains metadata filtered according to privacy settings:
/// - Location: none/coarse/precise
/// - Timestamp: none/dayOnly/exact
/// - Device info: none/modelOnly/full
public struct FilteredMetadata: Codable, Sendable, Equatable {

    /// Filtered location (nil if locationLevel is .none)
    public let location: FilteredLocation?

    /// Filtered timestamp string (nil if timestampLevel is .none)
    /// Format: ISO8601 full ("2025-12-01T10:30:00Z") or date only ("2025-12-01")
    public let timestamp: String?

    /// Device model string (nil if deviceInfoLevel is .none)
    /// Format: "iPhone 15 Pro" or "iPhone 15 Pro / iOS 18.1 / 1.0.0"
    public let deviceModel: String?

    /// Creates filtered metadata.
    ///
    /// - Parameters:
    ///   - location: Filtered location or nil
    ///   - timestamp: Filtered timestamp string or nil
    ///   - deviceModel: Filtered device info string or nil
    public init(
        location: FilteredLocation?,
        timestamp: String?,
        deviceModel: String?
    ) {
        self.location = location
        self.timestamp = timestamp
        self.deviceModel = deviceModel
    }

    /// Creates empty metadata (all fields excluded).
    public static let empty = FilteredMetadata(location: nil, timestamp: nil, deviceModel: nil)
}

// MARK: - FilteredLocation

/// Location data filtered according to privacy settings.
///
/// Supports two modes:
/// - Coarse: city and country only (no coordinates)
/// - Precise: full latitude/longitude coordinates
public struct FilteredLocation: Codable, Sendable, Equatable {

    /// City name (for coarse location)
    public let city: String?

    /// Country code (for coarse location)
    public let country: String?

    /// Latitude in decimal degrees (for precise location)
    public let latitude: Double?

    /// Longitude in decimal degrees (for precise location)
    public let longitude: Double?

    // MARK: - Factory Methods

    /// Creates a coarse location with city and country only.
    ///
    /// - Parameters:
    ///   - city: City name
    ///   - country: Country code (ISO 3166-1 alpha-2)
    /// - Returns: FilteredLocation with city/country, no coordinates
    public static func coarse(city: String, country: String) -> FilteredLocation {
        FilteredLocation(city: city, country: country, latitude: nil, longitude: nil)
    }

    /// Creates a precise location with coordinates.
    ///
    /// - Parameters:
    ///   - latitude: Latitude in decimal degrees
    ///   - longitude: Longitude in decimal degrees
    /// - Returns: FilteredLocation with coordinates, no city/country
    public static func precise(latitude: Double, longitude: Double) -> FilteredLocation {
        FilteredLocation(city: nil, country: nil, latitude: latitude, longitude: longitude)
    }

    // MARK: - Initialization

    /// Creates a FilteredLocation with all fields.
    ///
    /// Typically use factory methods `.coarse()` or `.precise()` instead.
    public init(city: String?, country: String?, latitude: Double?, longitude: Double?) {
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - MetadataFlags

/// Flags indicating what metadata was included in the hash-only payload.
///
/// Used by the server to understand what verification is possible
/// and how to interpret the evidence.
public struct MetadataFlags: Codable, Sendable, Equatable {

    /// Whether any location data is included
    public let locationIncluded: Bool

    /// Location granularity level ("none", "coarse", "precise")
    public let locationLevel: String

    /// Whether any timestamp is included
    public let timestampIncluded: Bool

    /// Timestamp granularity level ("none", "day_only", "exact")
    public let timestampLevel: String

    /// Whether any device info is included
    public let deviceInfoIncluded: Bool

    /// Device info granularity level ("none", "model_only", "full")
    public let deviceInfoLevel: String

    // MARK: - Factory Methods

    /// Creates MetadataFlags from PrivacySettings.
    ///
    /// - Parameter settings: Privacy settings to derive flags from
    /// - Returns: MetadataFlags with appropriate values
    public static func from(settings: PrivacySettings) -> MetadataFlags {
        MetadataFlags(
            locationIncluded: settings.locationLevel != .none,
            locationLevel: settings.locationLevel.rawValue,
            timestampIncluded: settings.timestampLevel != .none,
            timestampLevel: settings.timestampLevel.rawValue,
            deviceInfoIncluded: settings.deviceInfoLevel != .none,
            deviceInfoLevel: settings.deviceInfoLevel.rawValue
        )
    }

    // MARK: - Initialization

    /// Creates MetadataFlags with explicit values.
    public init(
        locationIncluded: Bool,
        locationLevel: String,
        timestampIncluded: Bool,
        timestampLevel: String,
        deviceInfoIncluded: Bool,
        deviceInfoLevel: String
    ) {
        self.locationIncluded = locationIncluded
        self.locationLevel = locationLevel
        self.timestampIncluded = timestampIncluded
        self.timestampLevel = timestampLevel
        self.deviceInfoIncluded = deviceInfoIncluded
        self.deviceInfoLevel = deviceInfoLevel
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case locationIncluded = "location_included"
        case locationLevel = "location_level"
        case timestampIncluded = "timestamp_included"
        case timestampLevel = "timestamp_level"
        case deviceInfoIncluded = "device_info_included"
        case deviceInfoLevel = "device_info_level"
    }
}

// MARK: - PrivacyHashChainData

/// Hash chain data for video integrity verification in privacy mode.
///
/// Contains a summary of the chain of frame hashes for video verification.
/// Used when mediaType is "video".
///
/// Named PrivacyHashChainData to avoid conflict with the full HashChainData
/// from HashChainService which contains all frame hashes.
public struct PrivacyHashChainData: Codable, Sendable, Equatable {

    /// Final hash of the hash chain (SHA-256 hex)
    public let finalHash: String

    /// Number of hashes in the chain
    public let chainLength: Int

    /// Algorithm version for hash chain
    public let version: String

    /// Creates hash chain data.
    ///
    /// - Parameters:
    ///   - finalHash: Final combined hash
    ///   - chainLength: Number of frame hashes
    ///   - version: Algorithm version (defaults to "1.0")
    public init(finalHash: String, chainLength: Int, version: String = "1.0") {
        self.finalHash = finalHash
        self.chainLength = chainLength
        self.version = version
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case finalHash = "final_hash"
        case chainLength = "chain_length"
        case version
    }
}

// MARK: - Payload Size Verification

extension HashOnlyCapturePayload {

    /// Maximum allowed payload size in bytes (10KB)
    public static let maxPayloadSize = 10 * 1024

    /// Computes the serialized JSON size of this payload.
    ///
    /// - Returns: Size in bytes, or nil if serialization fails
    public func serializedSize() -> Int? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return data.count
    }

    /// Checks if payload size is within the 10KB limit.
    ///
    /// - Returns: True if payload is under 10KB
    public func isWithinSizeLimit() -> Bool {
        guard let size = serializedSize() else {
            return false
        }
        return size < Self.maxPayloadSize
    }
}

// MARK: - JSON Serialization

extension HashOnlyCapturePayload {

    /// Encodes the payload to JSON data for signing.
    ///
    /// Uses consistent settings for deterministic output:
    /// - ISO8601 date encoding
    /// - Sorted keys for reproducibility
    ///
    /// - Returns: JSON-encoded Data
    /// - Throws: Encoding error if serialization fails
    public func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes a payload from JSON data.
    ///
    /// - Parameter data: JSON-encoded payload data
    /// - Returns: Decoded HashOnlyCapturePayload
    /// - Throws: Decoding error if deserialization fails
    public static func fromJSONData(_ data: Data) throws -> HashOnlyCapturePayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HashOnlyCapturePayload.self, from: data)
    }
}

// MARK: - CustomStringConvertible

extension HashOnlyCapturePayload: CustomStringConvertible {
    public var description: String {
        let sizeStr = serializedSize().map { "\($0) bytes" } ?? "unknown"
        let analysisStr: String
        if let depth = depthAnalysis {
            analysisStr = depth.status.rawValue
        } else if let temporal = temporalDepthAnalysis {
            analysisStr = "temporal(\(temporal.keyframeAnalyses.count) keyframes)"
        } else {
            analysisStr = "none"
        }
        return """
        HashOnlyCapturePayload(
            captureMode: \(captureMode),
            mediaType: \(mediaType),
            mediaHash: \(mediaHash.prefix(16))...,
            depthAnalysis: \(analysisStr),
            hasAssertion: \(!assertion.isEmpty),
            size: \(sizeStr)
        )
        """
    }
}
