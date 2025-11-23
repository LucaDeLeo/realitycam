/**
 * DepthCaptureSession
 *
 * ARSessionDelegate implementation for receiving and processing depth frames.
 * Extracts depth data from CVPixelBuffer and camera intrinsics for JS bridge.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 */

import ARKit
import Foundation

/// Callback type for depth frame updates
typealias DepthFrameCallback = ([String: Any]) -> Void

/// ARSessionDelegate for depth capture
class DepthCaptureDelegate: NSObject, ARSessionDelegate {
    /// Callback invoked when a new depth frame is available
    private let onDepthFrame: DepthFrameCallback

    /// Frame counter for throttling (30fps from 60fps ARKit)
    private var frameCount: Int = 0

    /// Target frame interval (2 = every other frame = 30fps)
    private let frameInterval: Int = 2

    init(onDepthFrame: @escaping DepthFrameCallback) {
        self.onDepthFrame = onDepthFrame
        super.init()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Throttle to 30fps (emit every 2nd frame)
        frameCount += 1
        guard frameCount % frameInterval == 0 else { return }

        // Extract depth data
        guard let sceneDepth = frame.sceneDepth else {
            return
        }

        let depthMap = sceneDepth.depthMap

        // Extract depth map as base64-encoded Float32 array
        let depthData = extractDepthMap(from: depthMap)
        let depthBase64 = depthData.base64EncodedString()

        // Get dimensions
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // Extract camera intrinsics
        let intrinsics = extractIntrinsics(from: frame.camera.intrinsics)

        // Create depth frame dictionary
        let depthFrame: [String: Any] = [
            "depthMap": depthBase64,
            "width": width,
            "height": height,
            "timestamp": frame.timestamp * 1000, // Convert to milliseconds
            "intrinsics": intrinsics
        ]

        // Invoke callback
        onDepthFrame(depthFrame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[DepthCaptureDelegate] ARSession failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("[DepthCaptureDelegate] ARSession interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("[DepthCaptureDelegate] ARSession interruption ended")
    }

    // MARK: - Private Methods

    /// Extract depth values from CVPixelBuffer as Data
    /// Depth values are Float32 representing meters
    private func extractDepthMap(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Data()
        }

        let floatPointer = baseAddress.assumingMemoryBound(to: Float32.self)
        let count = width * height
        let data = Data(bytes: floatPointer, count: count * MemoryLayout<Float32>.size)

        return data
    }

    /// Extract camera intrinsics from simd_float3x3 matrix
    /// Returns dictionary with fx, fy, cx, cy values
    private func extractIntrinsics(from matrix: simd_float3x3) -> [String: Double] {
        // Camera intrinsics matrix layout:
        // [fx,  0, cx]
        // [ 0, fy, cy]
        // [ 0,  0,  1]
        return [
            "fx": Double(matrix[0][0]),
            "fy": Double(matrix[1][1]),
            "cx": Double(matrix[2][0]),
            "cy": Double(matrix[2][1])
        ]
    }
}
