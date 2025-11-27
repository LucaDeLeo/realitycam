//
//  VideoMetadataCollector.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Service for collecting metadata during video recording.
//

import Foundation
import CoreLocation
import UIKit
import os.log

// MARK: - VideoMetadataCollector

/// Collects metadata during video recording for evidence package.
///
/// VideoMetadataCollector captures temporal, device, and location metadata
/// at recording start and assembles complete VideoMetadata at recording end.
/// Thread-safe using NSLock for state protection.
///
/// ## Usage
/// ```swift
/// let collector = VideoMetadataCollector()
///
/// // At recording start
/// collector.recordingStarted()
///
/// // At recording end
/// let metadata = collector.recordingEnded(
///     frameCount: result.frameCount,
///     depthKeyframeCount: result.depthKeyframeCount,
///     resolution: Resolution(width: 1920, height: 1080),
///     codec: result.codec,
///     hashChainFinal: result.finalHash ?? Data(),
///     assertion: result.attestation?.assertion ?? Data(),
///     attestationLevel: "secure_enclave"
/// )
/// ```
///
/// ## Thread Safety
/// All mutable state is protected by NSLock to ensure safe access from
/// multiple threads during recording.
public final class VideoMetadataCollector {

    // MARK: - Properties

    /// Logger for metadata collection events
    private static let logger = Logger(subsystem: "app.rial", category: "videometadata")

    /// Location manager for GPS capture
    private let locationManager: CLLocationManager

    /// Recording start timestamp
    private var startedAt: Date?

    /// GPS location at recording start
    private var startLocation: CLLocation?

    /// Lock for thread-safe state access
    private let stateLock = NSLock()

    // MARK: - Initialization

    /// Creates a new VideoMetadataCollector.
    ///
    /// - Parameter locationManager: CLLocationManager instance (defaults to new instance)
    public init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        Self.logger.debug("VideoMetadataCollector initialized")
    }

    // MARK: - Recording Lifecycle

    /// Called when recording starts to capture initial metadata.
    ///
    /// Captures:
    /// - Recording start timestamp (UTC)
    /// - GPS location (if available)
    ///
    /// ## Thread Safety
    /// Safe to call from any thread.
    public func recordingStarted() {
        stateLock.lock()
        defer { stateLock.unlock() }

        // Capture start timestamp
        startedAt = Date()

        // Capture GPS location (may be nil if not authorized or unavailable)
        startLocation = locationManager.location

        // Log recording start
        let hasLocation = startLocation != nil
        let locationString = startLocation.map { "(\($0.coordinate.latitude), \($0.coordinate.longitude))" } ?? "nil"
        Self.logger.info("Recording started - timestamp: \(self.startedAt?.ISO8601Format() ?? "nil"), location: \(locationString), hasLocation: \(hasLocation)")
    }

    /// Called when recording ends to finalize and assemble metadata.
    ///
    /// Calculates duration, encodes binary data to base64, and creates
    /// the complete VideoMetadata struct for evidence package.
    ///
    /// - Parameters:
    ///   - frameCount: Total frames captured (from hash chain)
    ///   - depthKeyframeCount: Depth keyframes captured (from DepthKeyframeBuffer)
    ///   - resolution: Video resolution (width x height)
    ///   - codec: Video codec ("h264" or "hevc")
    ///   - hashChainFinal: Final hash from hash chain (32 bytes)
    ///   - assertion: DCAppAttest assertion data
    ///   - attestationLevel: Attestation level ("secure_enclave" or "unverified")
    /// - Returns: Complete VideoMetadata for evidence package
    ///
    /// ## Thread Safety
    /// Safe to call from any thread.
    public func recordingEnded(
        frameCount: Int,
        depthKeyframeCount: Int,
        resolution: Resolution,
        codec: String,
        hashChainFinal: Data,
        assertion: Data,
        attestationLevel: String
    ) -> VideoMetadata {
        stateLock.lock()
        let capturedStartedAt = startedAt
        let capturedLocation = startLocation
        stateLock.unlock()

        // Capture end timestamp
        let endedAt = Date()

        // Use captured start time or fall back to end time
        let startTime = capturedStartedAt ?? endedAt

        // Calculate duration in milliseconds
        let durationMs = Int64(endedAt.timeIntervalSince(startTime) * 1000)

        // Convert location to CaptureLocation if available
        let location: CaptureLocation? = capturedLocation.map { CaptureLocation(from: $0) }

        // Encode binary data to base64
        let hashChainFinalBase64 = hashChainFinal.base64EncodedString()
        let assertionBase64 = assertion.base64EncodedString()

        // Build metadata
        let metadata = VideoMetadata(
            type: "video",
            startedAt: startTime,
            endedAt: endedAt,
            durationMs: durationMs,
            frameCount: frameCount,
            depthKeyframeCount: depthKeyframeCount,
            resolution: resolution,
            codec: codec.lowercased(),  // Ensure lowercase for API
            deviceModel: getDeviceModel(),
            iosVersion: getIOSVersion(),
            location: location,
            attestationLevel: attestationLevel,
            hashChainFinal: hashChainFinalBase64,
            assertion: assertionBase64
        )

        // Log metadata finalization
        Self.logger.info("""
            Metadata finalized - \
            duration: \(durationMs)ms, \
            frames: \(frameCount), \
            depthKeyframes: \(depthKeyframeCount), \
            resolution: \(resolution.width)x\(resolution.height), \
            codec: \(codec), \
            hasLocation: \(location != nil), \
            attestation: \(attestationLevel)
            """)

        return metadata
    }

    /// Resets collector state for next recording.
    ///
    /// Clears start timestamp and location. Call before starting
    /// a new recording session.
    ///
    /// ## Thread Safety
    /// Safe to call from any thread.
    public func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }

        startedAt = nil
        startLocation = nil

        Self.logger.debug("VideoMetadataCollector reset")
    }

    // MARK: - Device Information

    /// Gets the current device model.
    ///
    /// Returns the device model string (e.g., "iPhone" on simulator,
    /// actual model name on device via sysctl).
    ///
    /// - Returns: Device model string
    public func getDeviceModel() -> String {
        // Use UIDevice model which returns "iPhone" for all iPhones
        // For more specific model (e.g., "iPhone 15 Pro"), would need sysctl
        // Following existing pattern from CaptureMetadata
        return UIDevice.current.model
    }

    /// Gets the iOS version string.
    ///
    /// Returns the full operating system version string
    /// (e.g., "Version 17.4 (Build 21E219)").
    ///
    /// - Returns: iOS version string
    public func getIOSVersion() -> String {
        // Following existing pattern from CaptureMetadata
        return ProcessInfo.processInfo.operatingSystemVersionString
    }

    // MARK: - Internal State Access (for testing)

    /// Whether the collector has a recorded start time.
    var hasStarted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startedAt != nil
    }

    /// The recorded start timestamp (for testing).
    var recordedStartTime: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startedAt
    }

    /// The recorded start location (for testing).
    var recordedStartLocation: CLLocation? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startLocation
    }
}
