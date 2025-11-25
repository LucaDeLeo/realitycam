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
    public var assertion: Data?

    /// Capture timestamp
    public let timestamp: Date

    /// Creates a new CaptureData instance.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - jpeg: JPEG photo data
    ///   - depth: Compressed depth map data
    ///   - metadata: Capture metadata
    ///   - assertion: Optional hardware attestation assertion
    ///   - timestamp: Capture timestamp (defaults to current time)
    public init(
        id: UUID = UUID(),
        jpeg: Data,
        depth: Data,
        metadata: CaptureMetadata,
        assertion: Data? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.jpeg = jpeg
        self.depth = depth
        self.metadata = metadata
        self.assertion = assertion
        self.timestamp = timestamp
    }

    /// Total size of capture data in bytes (approximate for upload estimation)
    public var totalSizeBytes: Int {
        jpeg.count + depth.count + (assertion?.count ?? 0)
    }

    /// Human-readable size string (e.g., "3.2 MB")
    public var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSizeBytes), countStyle: .file)
    }
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
public enum CaptureStatus: String, Codable, Sendable {
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
