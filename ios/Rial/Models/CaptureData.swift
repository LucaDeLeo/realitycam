//
//  CaptureData.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Data models for capture processing and storage.
//

import Foundation
import CoreLocation

// MARK: - UploadMode

/// Mode of upload determining what data is sent to server.
///
/// Controls whether raw media is uploaded or only a hash.
/// Named UploadMode to avoid conflict with CaptureMode (photo/video).
public enum UploadMode: String, Codable, Sendable {
    /// Full upload mode - raw photo/video bytes uploaded
    case full = "full"

    /// Hash-only mode - only hash and metadata uploaded (privacy mode)
    case hashOnly = "hash_only"
}

// MARK: - CaptureData

/// Complete capture data ready for storage and upload.
///
/// Represents a processed capture containing the JPEG photo, compressed depth map,
/// metadata, and optional assertion from hardware attestation.
///
/// ## Usage
/// ```swift
/// let captureData = try await frameProcessor.process(frame, location: location)
/// // captureData.jpeg contains the JPEG photo (2-4MB)
/// // captureData.depth contains compressed depth map (~50-100KB)
/// // captureData.metadata contains all metadata including SHA-256 hash
/// ```
public struct CaptureData: Codable, Identifiable, Sendable {
    /// Unique identifier for this capture
    public let id: UUID

    /// JPEG-compressed photo data (2-4MB typical)
    public let jpeg: Data

    /// Zlib-compressed depth map data (~50-100KB typical)
    public let depth: Data

    /// Capture metadata including hash, location, and dimensions
    public let metadata: CaptureMetadata

    /// Hardware attestation assertion data (added by Story 6.8)
    /// Contains CBOR-encoded signature from Secure Enclave (1-2KB typical)
    public var assertion: Data?

    /// Status of assertion generation for this capture
    public var assertionStatus: AssertionStatus

    /// Number of assertion generation attempts (for retry logic)
    public var assertionAttemptCount: Int

    /// Capture timestamp
    public let timestamp: Date

    // MARK: - Privacy Mode Fields (Story 8-3)

    /// Upload mode (.full or .hashOnly) - nil for backward compatibility
    public var uploadMode: UploadMode?

    /// Client-side depth analysis result for privacy mode - nil when not applicable
    public var depthAnalysisResult: DepthAnalysisResult?

    /// Snapshot of privacy settings at capture time - nil for non-privacy captures
    public var privacySettings: PrivacySettings?

    // MARK: - Multi-Signal Detection Fields (Story 9-6)

    /// Multi-signal detection results (moire, texture, artifacts, aggregated confidence).
    /// Nil for backward compatibility with existing captures without detection.
    public var detectionResults: DetectionResults?

    /// Creates a new CaptureData instance.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - jpeg: JPEG photo data
    ///   - depth: Compressed depth map data
    ///   - metadata: Capture metadata
    ///   - assertion: Optional hardware attestation assertion
    ///   - assertionStatus: Status of assertion generation (defaults to .none)
    ///   - assertionAttemptCount: Number of assertion attempts (defaults to 0)
    ///   - timestamp: Capture timestamp (defaults to current time)
    ///   - uploadMode: Upload mode (.full or .hashOnly, defaults to nil for backward compat)
    ///   - depthAnalysisResult: Client-side depth analysis result (defaults to nil)
    ///   - privacySettings: Privacy settings snapshot (defaults to nil)
    ///   - detectionResults: Multi-signal detection results (defaults to nil)
    public init(
        id: UUID = UUID(),
        jpeg: Data,
        depth: Data,
        metadata: CaptureMetadata,
        assertion: Data? = nil,
        assertionStatus: AssertionStatus = .none,
        assertionAttemptCount: Int = 0,
        timestamp: Date = Date(),
        uploadMode: UploadMode? = nil,
        depthAnalysisResult: DepthAnalysisResult? = nil,
        privacySettings: PrivacySettings? = nil,
        detectionResults: DetectionResults? = nil
    ) {
        self.id = id
        self.jpeg = jpeg
        self.depth = depth
        self.metadata = metadata
        self.assertion = assertion
        self.assertionStatus = assertionStatus
        self.assertionAttemptCount = assertionAttemptCount
        self.timestamp = timestamp
        self.uploadMode = uploadMode
        self.depthAnalysisResult = depthAnalysisResult
        self.privacySettings = privacySettings
        self.detectionResults = detectionResults
    }

    /// Total size of capture data in bytes (approximate for upload estimation)
    public var totalSizeBytes: Int {
        jpeg.count + depth.count + (assertion?.count ?? 0) + (detectionResults?.estimatedSize ?? 0)
    }

    /// Human-readable size string (e.g., "3.2 MB")
    public var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSizeBytes), countStyle: .file)
    }

    /// Base64-encoded assertion for JSON serialization in upload metadata.
    /// Returns `nil` if no assertion is available.
    public var base64EncodedAssertion: String? {
        assertion?.base64EncodedString()
    }

    /// Whether this capture has a valid assertion attached
    public var hasAssertion: Bool {
        assertion != nil && assertionStatus == .generated
    }

    /// Whether this capture needs assertion retry
    public var needsAssertionRetry: Bool {
        assertionStatus == .pending && assertionAttemptCount < 3
    }
}

// MARK: - AssertionStatus

/// Status of assertion generation for a capture.
///
/// Tracks whether assertion was successfully generated, pending retry,
/// or permanently failed.
public enum AssertionStatus: String, Codable, Sendable {
    /// No assertion attempted yet
    case none

    /// Assertion successfully generated
    case generated

    /// Assertion generation failed, pending retry
    case pending

    /// Retry limit exceeded, assertion failed permanently
    case failed
}

// MARK: - CaptureMetadata

/// Metadata associated with a capture.
///
/// Contains all non-binary metadata for a capture including timestamp,
/// device information, photo hash, location, and depth dimensions.
public struct CaptureMetadata: Codable, Sendable, Equatable {
    /// Timestamp when the frame was captured
    public let capturedAt: Date

    /// Device model string (e.g., "iPhone 15 Pro")
    public let deviceModel: String

    /// SHA-256 hash of JPEG data (64-character hex string)
    public let photoHash: String

    /// GPS location data (optional - nil if denied or unavailable)
    public let location: LocationData?

    /// Depth map dimensions for reconstruction
    public let depthMapDimensions: DepthDimensions

    /// iOS version at capture time
    public let iosVersion: String

    /// App version at capture time
    public let appVersion: String

    /// Creates a new CaptureMetadata instance.
    ///
    /// - Parameters:
    ///   - capturedAt: Frame capture timestamp
    ///   - deviceModel: Device model string
    ///   - photoHash: SHA-256 hash of JPEG data
    ///   - location: GPS location (optional)
    ///   - depthMapDimensions: Depth map width and height
    ///   - iosVersion: iOS version (defaults to current)
    ///   - appVersion: App version (defaults to current bundle version)
    public init(
        capturedAt: Date,
        deviceModel: String,
        photoHash: String,
        location: LocationData?,
        depthMapDimensions: DepthDimensions,
        iosVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    ) {
        self.capturedAt = capturedAt
        self.deviceModel = deviceModel
        self.photoHash = photoHash
        self.location = location
        self.depthMapDimensions = depthMapDimensions
        self.iosVersion = iosVersion
        self.appVersion = appVersion
    }
}

// MARK: - LocationData

/// GPS location data for a capture.
///
/// Simplified representation of CLLocation for serialization.
public struct LocationData: Codable, Sendable, Equatable {
    /// Latitude in decimal degrees (-90 to 90)
    public let latitude: Double

    /// Longitude in decimal degrees (-180 to 180)
    public let longitude: Double

    /// Altitude in meters above sea level (optional)
    public let altitude: Double?

    /// Horizontal accuracy in meters
    public let accuracy: Double

    /// Timestamp of location measurement
    public let timestamp: Date

    /// Creates LocationData from a CLLocation.
    ///
    /// - Parameter location: Core Location object
    public init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude.isNaN ? nil : location.altitude
        self.accuracy = location.horizontalAccuracy
        self.timestamp = location.timestamp
    }

    /// Creates LocationData with explicit values.
    ///
    /// - Parameters:
    ///   - latitude: Latitude in decimal degrees
    ///   - longitude: Longitude in decimal degrees
    ///   - altitude: Altitude in meters (optional)
    ///   - accuracy: Horizontal accuracy in meters
    ///   - timestamp: Location measurement timestamp
    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        accuracy: Double,
        timestamp: Date = Date()
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    /// Whether this location is considered accurate (accuracy < 50m)
    public var isAccurate: Bool {
        accuracy > 0 && accuracy < 50
    }
}

// MARK: - DepthDimensions

/// Depth map dimensions for reconstruction.
///
/// Stores the width and height of the depth map buffer for decompression.
/// Typical LiDAR depth maps are 256x192 pixels.
public struct DepthDimensions: Codable, Sendable, Equatable {
    /// Width in pixels
    public let width: Int

    /// Height in pixels
    public let height: Int

    /// Creates new DepthDimensions.
    ///
    /// - Parameters:
    ///   - width: Width in pixels
    ///   - height: Height in pixels
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Total pixel count (width × height)
    public var pixelCount: Int {
        width * height
    }

    /// Raw data size in bytes (Float32 per pixel)
    public var rawDataSize: Int {
        pixelCount * MemoryLayout<Float>.size
    }
}

// MARK: - CaptureStatus

/// Status of a capture in the processing/upload queue.
public enum CaptureStatus: String, Codable, Sendable, CaseIterable {
    /// Capture is being processed (JPEG conversion, compression)
    case processing

    /// Capture is processed and ready for upload
    case pending

    /// Capture is currently being uploaded
    case uploading

    /// Upload is paused (network unavailable, app backgrounded)
    case paused

    /// Upload completed successfully
    case uploaded

    /// Upload failed (will retry)
    case failed

    /// Whether this status indicates the capture is complete
    public var isComplete: Bool {
        self == .uploaded
    }

    /// Whether this status indicates work is in progress
    public var isInProgress: Bool {
        self == .processing || self == .uploading
    }
}
