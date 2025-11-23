/**
 * LiDARDepthModule
 *
 * Expo Modules API native module for ARKit LiDAR depth capture.
 * Provides isLiDARAvailable, startDepthCapture, stopDepthCapture, and captureDepthFrame functions.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 * @see docs/architecture.md#ADR-002
 */

import ExpoModulesCore
import ARKit

/// Error types for LiDAR operations
enum LiDARError: String, Error {
    case notAvailable = "NOT_AVAILABLE"
    case noDepthData = "NO_DEPTH_DATA"
    case sessionFailed = "SESSION_FAILED"
    case permissionDenied = "PERMISSION_DENIED"

    var localizedDescription: String {
        switch self {
        case .notAvailable:
            return "LiDAR sensor not available on this device"
        case .noDepthData:
            return "No depth data available in current frame"
        case .sessionFailed:
            return "ARSession failed to start"
        case .permissionDenied:
            return "Camera permission denied"
        }
    }
}

public class LiDARDepthModule: Module {
    /// ARSession instance for depth capture
    private var session: ARSession?

    /// Delegate for handling ARSession updates
    private var depthDelegate: DepthCaptureDelegate?

    /// Whether capture is currently active
    private var isCapturing: Bool = false

    /// Latest captured depth frame for on-demand access
    private var latestDepthFrame: [String: Any]?

    public func definition() -> ModuleDefinition {
        // Module name exposed to JavaScript
        Name("LiDARDepth")

        // Events that can be sent to JavaScript
        Events("onDepthFrame")

        /// Check if LiDAR hardware is available
        /// Uses ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        AsyncFunction("isLiDARAvailable") { () -> Bool in
            // Check if device supports scene reconstruction (requires LiDAR)
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }

        /// Start ARKit depth capture session
        AsyncFunction("startDepthCapture") { () throws in
            // Guard: check LiDAR availability first
            guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
                throw LiDARError.notAvailable
            }

            // Guard: don't start if already capturing
            guard !self.isCapturing else {
                print("[LiDARDepth] Already capturing, ignoring start request")
                return
            }

            // Create ARSession configuration with scene depth
            let config = ARWorldTrackingConfiguration()
            config.frameSemantics = .sceneDepth

            // Create session and delegate
            let session = ARSession()
            let delegate = DepthCaptureDelegate { [weak self] depthFrame in
                self?.handleDepthFrame(depthFrame)
            }

            session.delegate = delegate

            // Store references
            self.session = session
            self.depthDelegate = delegate
            self.isCapturing = true

            // Run session on main thread (ARKit requirement)
            DispatchQueue.main.async {
                session.run(config)
                print("[LiDARDepth] ARSession started with sceneDepth")
            }
        }

        /// Stop ARKit depth capture session
        AsyncFunction("stopDepthCapture") { () in
            guard self.isCapturing else {
                print("[LiDARDepth] Not capturing, ignoring stop request")
                return
            }

            // Pause session on main thread
            DispatchQueue.main.async { [weak self] in
                self?.session?.pause()
                print("[LiDARDepth] ARSession paused")
            }

            // Clean up
            self.isCapturing = false
            self.depthDelegate = nil
            self.latestDepthFrame = nil
            // Note: Keep session reference for potential restart
        }

        /// Capture a single depth frame
        AsyncFunction("captureDepthFrame") { () throws -> [String: Any] in
            // Guard: must be capturing
            guard self.isCapturing else {
                throw LiDARError.notAvailable
            }

            // Guard: need valid depth frame
            guard let depthFrame = self.latestDepthFrame else {
                throw LiDARError.noDepthData
            }

            return depthFrame
        }
    }

    /// Handle incoming depth frame from delegate
    private func handleDepthFrame(_ depthFrame: [String: Any]) {
        // Store for on-demand access
        self.latestDepthFrame = depthFrame

        // Send lightweight event to JS (timestamp and hasDepth flag only)
        // Full depth data is fetched on-demand via captureDepthFrame
        if let timestamp = depthFrame["timestamp"] as? Double {
            sendEvent("onDepthFrame", [
                "timestamp": timestamp,
                "hasDepth": true
            ])
        }
    }
}
