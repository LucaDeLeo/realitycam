//
//  EdgeDepthOverlayView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  SwiftUI wrapper for Metal-based Sobel edge detection depth overlay.
//  Used during video recording to show depth discontinuities without
//  obscuring the camera preview.
//

import SwiftUI
import MetalKit
import os.log

// MARK: - EdgeDepthOverlayView

/// SwiftUI view that renders real-time Sobel edge detection on LiDAR depth data.
///
/// Wraps a Metal-based MTKView to display depth edges during video recording.
/// Near edges appear cyan, far edges appear magenta. The sparse edge visualization
/// provides depth feedback without obscuring the camera preview.
///
/// ## Key Differences from DepthOverlayView
/// - Uses Sobel edge detection instead of full colormap
/// - Runs at 30fps (matching video recording) instead of 60fps
/// - Edge-only output is ~3x faster than full colormap
/// - Designed for video recording preview (not photo mode)
///
/// ## Important
/// This overlay renders to the preview ONLY and does NOT appear in the recorded video.
/// The AVAssetWriter receives raw RGB frames without any overlay compositing.
///
/// ## Usage
/// ```swift
/// ZStack {
///     // Camera preview
///     ARViewContainer()
///
///     // Edge overlay (video mode only)
///     if isRecordingVideo {
///         EdgeDepthOverlayView(
///             depthFrame: viewModel.currentDepthFrame,
///             edgeThreshold: 0.1,
///             isVisible: $showEdgeOverlay
///         )
///     }
/// }
/// ```
public struct EdgeDepthOverlayView: UIViewRepresentable {

    /// Current depth frame to render (nil = transparent)
    public let depthFrame: DepthFrame?

    /// Edge detection threshold (default: 0.1)
    /// Higher values show fewer, more prominent edges
    public let edgeThreshold: Float

    /// Whether the overlay is visible
    @Binding public var isVisible: Bool

    /// Creates a new edge depth overlay view.
    ///
    /// - Parameters:
    ///   - depthFrame: Current depth frame to render
    ///   - edgeThreshold: Minimum edge magnitude to render (default: 0.1)
    ///   - isVisible: Binding to visibility state
    public init(
        depthFrame: DepthFrame?,
        edgeThreshold: Float = EdgeDepthVisualizer.defaultEdgeThreshold,
        isVisible: Binding<Bool>
    ) {
        self.depthFrame = depthFrame
        self.edgeThreshold = edgeThreshold
        self._isVisible = isVisible
    }

    public func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()

        // Try to initialize Metal device
        if let device = context.coordinator.visualizer?.device {
            metalView.device = device
        } else if let device = MTLCreateSystemDefaultDevice() {
            metalView.device = device
        }

        metalView.delegate = context.coordinator
        metalView.framebufferOnly = false
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false

        // Use 30fps to match video recording rate
        // This reduces GPU load during concurrent video encoding
        metalView.preferredFramesPerSecond = 30

        // Transparent background for overlay
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.isOpaque = false
        metalView.backgroundColor = .clear

        return metalView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.depthFrame = depthFrame
        context.coordinator.edgeThreshold = edgeThreshold
        context.coordinator.isVisible = isVisible
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        uiView.delegate = nil
        uiView.isPaused = true
        coordinator.visualizer = nil
    }

    // MARK: - Coordinator

    /// Coordinator class that manages Metal edge rendering.
    public class Coordinator: NSObject, MTKViewDelegate {
        private static let logger = Logger(subsystem: "app.rial", category: "edgedepthoverlay")

        var parent: EdgeDepthOverlayView
        var visualizer: EdgeDepthVisualizer?
        var depthFrame: DepthFrame?
        var edgeThreshold: Float = EdgeDepthVisualizer.defaultEdgeThreshold
        var isVisible: Bool = true

        init(_ parent: EdgeDepthOverlayView) {
            self.parent = parent
            super.init()

            // Initialize visualizer
            do {
                visualizer = try EdgeDepthVisualizer()
            } catch {
                Self.logger.error("Failed to initialize EdgeDepthVisualizer: \(error.localizedDescription)")
            }
        }

        // MARK: - MTKViewDelegate

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle size changes if needed
        }

        public func draw(in view: MTKView) {
            // Skip rendering if not visible or no depth data
            guard isVisible, let depthFrame = depthFrame else {
                // Clear the view when not visible
                clearView(view)
                return
            }

            guard let visualizer = visualizer else {
                Self.logger.debug("EdgeVisualizer not available, skipping render")
                return
            }

            do {
                try visualizer.render(depthFrame: depthFrame, to: view, edgeThreshold: edgeThreshold)
            } catch {
                Self.logger.error("Edge render failed: \(error.localizedDescription)")
                clearView(view)
            }
        }

        /// Clear the Metal view with transparent pixels.
        private func clearView(_ view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandQueue = visualizer?.device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// MARK: - EdgeOverlayToggleButton

/// Toggle button for showing/hiding edge depth overlay during video recording.
///
/// Displays an eye icon that toggles between visible and hidden states.
/// Uses the same SF Symbols as `DepthOverlayToggleButton` for consistency.
public struct EdgeOverlayToggleButton: View {
    @Binding var isVisible: Bool

    /// Action to perform when toggle state changes
    var onToggle: ((Bool) -> Void)?

    public init(isVisible: Binding<Bool>, onToggle: ((Bool) -> Void)? = nil) {
        self._isVisible = isVisible
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: {
            isVisible.toggle()
            onToggle?(isVisible)
        }) {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .font(.title2)
                .foregroundColor(.white)
                .padding(12)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityLabel(isVisible ? "Hide edge overlay" : "Show edge overlay")
        .accessibilityHint("Double tap to toggle depth edge visualization during recording")
    }
}

// MARK: - Preview Provider

#if DEBUG
struct EdgeDepthOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black

            EdgeDepthOverlayView(
                depthFrame: nil,
                edgeThreshold: 0.1,
                isVisible: .constant(true)
            )

            VStack {
                Spacer()
                EdgeOverlayToggleButton(isVisible: .constant(true))
                    .padding()
            }
        }
    }
}
#endif
