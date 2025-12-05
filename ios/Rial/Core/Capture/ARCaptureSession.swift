//
//  ARCaptureSession.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Unified ARKit capture session providing synchronized RGB photo and LiDAR depth capture.
//  This replaces the React Native approach of separate camera + LiDAR modules.
//

import Foundation
import ARKit
import os.log

// MARK: - ARCaptureSession

/// Unified ARKit capture session providing synchronized RGB photo and LiDAR depth capture.
///
/// ARCaptureSession wraps ARKit's `ARSession` with `ARWorldTrackingConfiguration` to enable
/// `sceneDepth` frame semantics. This provides both the `capturedImage` (RGB) and `sceneDepth`
/// (LiDAR depth map) in the same `ARFrame` object, captured at the exact same instant with
/// perfect alignment.
///
/// ## Key Benefits Over React Native
/// - **Perfect Synchronization**: Single ARFrame captures RGB and depth simultaneously
/// - **No Bridge Overhead**: All data processed in native memory
/// - **Native Frame Rate**: 30-60fps sustained without JavaScript coordination
/// - **Zero-Copy Access**: Direct CVPixelBuffer references without data duplication
///
/// ## Usage
/// ```swift
/// let captureSession = ARCaptureSession()
///
/// // Set frame callback for preview rendering
/// captureSession.onFrameUpdate = { frame in
///     depthVisualizer.update(with: frame)
/// }
///
/// do {
///     try captureSession.start()
/// } catch CaptureError.lidarNotAvailable {
///     showError("iPhone Pro with LiDAR required")
/// }
///
/// // Capture current frame when user taps button
/// if let frame = captureSession.captureCurrentFrame() {
///     let data = try await frameProcessor.process(frame)
/// }
///
/// // Clean up
/// captureSession.stop()
/// ```
///
/// - Note: LiDAR is only available on iPhone Pro models (12 Pro and newer).
///         Simulator does not support LiDAR functionality.
public final class ARCaptureSession: NSObject {

    // MARK: - Properties

    /// Logger for capture session events
    private static let logger = Logger(subsystem: "app.rial", category: "capture")

    /// ARKit session for RGB+depth capture
    private let session = ARSession()

    /// Public access to underlying ARSession for ARView binding.
    public var arSession: ARSession { session }

    /// Serial queue for thread-safe frame access
    private let frameQueue = DispatchQueue(label: "app.rial.arcapturesession.frame")

    /// Most recent ARFrame (thread-safe access via frameQueue)
    private var _currentFrame: ARFrame?

    /// Whether the session is currently running
    private(set) var isRunning: Bool = false

    /// Callback invoked on each frame update.
    ///
    /// - Important: Called on ARSession delegate queue, not main queue.
    ///              Dispatch to main queue if updating UI.
    public var onFrameUpdate: ((ARFrame) -> Void)?

    /// Callback invoked when session is interrupted (phone call, backgrounding, etc.)
    public var onInterruption: (() -> Void)?

    /// Callback invoked when interruption ends and session resumes
    public var onInterruptionEnded: (() -> Void)?

    /// Callback invoked when camera tracking state changes
    public var onTrackingStateChanged: ((ARCamera.TrackingState) -> Void)?

    /// Callback invoked when session encounters an error
    public var onError: ((Error) -> Void)?

    // MARK: - Initialization

    public override init() {
        super.init()
        session.delegate = self
        Self.logger.debug("ARCaptureSession initialized")
    }

    deinit {
        if isRunning {
            stop()
        }
        Self.logger.debug("ARCaptureSession deinitialized")
    }

    // MARK: - Public Methods

    /// Check if LiDAR is available on this device.
    ///
    /// - Returns: `true` if device supports LiDAR depth capture, `false` otherwise.
    ///
    /// - Note: Returns `false` on simulator and non-Pro iPhone models.
    public static var isLiDARAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// Start AR capture session with LiDAR depth capture enabled.
    ///
    /// Configures and runs an `ARSession` with `ARWorldTrackingConfiguration` and
    /// `.sceneDepth` frame semantics. The session will begin delivering frames via
    /// the `onFrameUpdate` callback.
    ///
    /// - Throws: `CaptureError.lidarNotAvailable` if device doesn't support LiDAR.
    ///           `CaptureError.sessionFailed` if ARSession fails to start.
    ///
    /// - Note: First frame typically arrives within 500ms of starting.
    public func start() throws {
        guard !isRunning else {
            Self.logger.warning("ARCaptureSession already running, ignoring start()")
            return
        }

        // Verify LiDAR support
        guard Self.isLiDARAvailable else {
            Self.logger.error("LiDAR not available on this device")
            throw CaptureError.lidarNotAvailable
        }

        Self.logger.info("Starting ARCaptureSession with LiDAR depth")

        // Configure AR session
        let config = ARWorldTrackingConfiguration()

        // Enable scene depth for LiDAR data
        config.frameSemantics.insert(.sceneDepth)

        // Disable unnecessary features for better performance
        config.planeDetection = []
        config.environmentTexturing = .none
        config.isAutoFocusEnabled = true

        // Start session with clean state
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true

        Self.logger.info("ARCaptureSession started successfully")
    }

    /// Stop AR capture session and release resources.
    ///
    /// Pauses the ARSession, clears the current frame reference, and stops
    /// all frame callbacks. Safe to call multiple times.
    public func stop() {
        guard isRunning else {
            Self.logger.debug("ARCaptureSession not running, ignoring stop()")
            return
        }

        Self.logger.info("Stopping ARCaptureSession")

        session.pause()

        frameQueue.sync {
            _currentFrame = nil
        }

        isRunning = false

        Self.logger.info("ARCaptureSession stopped")
    }

    /// Capture the most recent ARFrame.
    ///
    /// Returns the most recently received frame from the ARSession delegate.
    /// The frame contains synchronized RGB image and LiDAR depth data captured
    /// at the same instant.
    ///
    /// - Returns: Current `ARFrame` with `capturedImage` and `sceneDepth`,
    ///            or `nil` if no frames have been received yet.
    ///
    /// - Note: Thread-safe. Can be called from any queue.
    public func captureCurrentFrame() -> ARFrame? {
        return frameQueue.sync {
            guard let frame = _currentFrame else {
                Self.logger.debug("No current frame available")
                return nil
            }

            Self.logger.debug("Captured frame at timestamp \(frame.timestamp, format: .fixed(precision: 3))")
            return frame
        }
    }

    /// Run the session with custom configuration.
    ///
    /// For advanced use cases where custom ARWorldTrackingConfiguration is needed.
    ///
    /// - Parameter configuration: Custom AR configuration with sceneDepth enabled.
    ///
    /// - Note: The configuration must have `.sceneDepth` in frameSemantics for
    ///         LiDAR depth data to be available.
    public func run(with configuration: ARWorldTrackingConfiguration) {
        Self.logger.info("Running ARCaptureSession with custom configuration")
        session.run(configuration)
        isRunning = true
    }
}

// MARK: - ARSessionDelegate

extension ARCaptureSession: ARSessionDelegate {

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Store frame (thread-safe)
        frameQueue.sync {
            _currentFrame = frame
        }

        // Verify frame contains depth data
        if frame.sceneDepth == nil {
            // This can happen briefly at session start or on unsupported devices
            Self.logger.warning("ARFrame missing sceneDepth (LiDAR data unavailable)")
        }

        // Notify callback
        onFrameUpdate?(frame)
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        Self.logger.error("ARSession failed: \(error.localizedDescription)")
        isRunning = false
        onError?(error)
    }

    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = camera.trackingState

        switch state {
        case .normal:
            Self.logger.debug("Camera tracking: normal")
        case .notAvailable:
            Self.logger.warning("Camera tracking: not available")
        case .limited(let reason):
            Self.logger.warning("Camera tracking: limited (\(String(describing: reason)))")
        }

        onTrackingStateChanged?(state)
    }

    public func sessionWasInterrupted(_ session: ARSession) {
        Self.logger.warning("ARSession interrupted (phone call, backgrounding, etc.)")
        onInterruption?()
    }

    public func sessionInterruptionEnded(_ session: ARSession) {
        Self.logger.info("ARSession interruption ended, resuming")
        onInterruptionEnded?()
    }

    public func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        // Allow relocalization after interruption
        return true
    }
}

// MARK: - CaptureError

/// Errors that can occur during AR capture operations.
public enum CaptureError: Error, LocalizedError, Equatable {
    /// Device doesn't support LiDAR (non-Pro iPhone or simulator)
    case lidarNotAvailable

    /// AR capture session failed to start
    case sessionFailed(underlying: String?)

    /// AR capture session was interrupted
    case interrupted

    /// No frame available (session not started or no frames received yet)
    case noFrameAvailable

    /// Camera permission not granted
    case cameraPermissionDenied

    /// Camera tracking lost or insufficient visual features
    case trackingLost

    public var errorDescription: String? {
        switch self {
        case .lidarNotAvailable:
            return "LiDAR sensor required (iPhone Pro models only)"
        case .sessionFailed(let underlying):
            if let reason = underlying {
                return "AR capture session failed: \(reason)"
            }
            return "AR capture session failed to start"
        case .interrupted:
            return "AR capture session interrupted"
        case .noFrameAvailable:
            return "No frame available yet (session not started or no frames received)"
        case .cameraPermissionDenied:
            return "Camera access required. Please enable in Settings."
        case .trackingLost:
            return "Camera tracking lost. Move device slowly and ensure good lighting."
        }
    }

    public static func == (lhs: CaptureError, rhs: CaptureError) -> Bool {
        switch (lhs, rhs) {
        case (.lidarNotAvailable, .lidarNotAvailable),
             (.interrupted, .interrupted),
             (.noFrameAvailable, .noFrameAvailable),
             (.cameraPermissionDenied, .cameraPermissionDenied),
             (.trackingLost, .trackingLost):
            return true
        case (.sessionFailed(let lhsUnderlying), .sessionFailed(let rhsUnderlying)):
            return lhsUnderlying == rhsUnderlying
        default:
            return false
        }
    }
}

// MARK: - ARFrame Extensions

public extension ARFrame {

    /// Whether this frame contains valid LiDAR depth data.
    var hasDepthData: Bool {
        sceneDepth != nil
    }

    /// Depth map dimensions (width x height), or nil if no depth data.
    var depthMapSize: (width: Int, height: Int)? {
        guard let depthMap = sceneDepth?.depthMap else { return nil }
        return (
            width: CVPixelBufferGetWidth(depthMap),
            height: CVPixelBufferGetHeight(depthMap)
        )
    }

    /// RGB image dimensions (width x height).
    var imageSize: (width: Int, height: Int) {
        return (
            width: CVPixelBufferGetWidth(capturedImage),
            height: CVPixelBufferGetHeight(capturedImage)
        )
    }
}
