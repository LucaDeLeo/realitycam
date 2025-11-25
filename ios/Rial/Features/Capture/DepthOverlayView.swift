//
//  DepthOverlayView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  SwiftUI wrapper for Metal-based depth visualization overlay.
//

import SwiftUI
import MetalKit
import os.log

// MARK: - DepthOverlayView

/// SwiftUI view that renders real-time LiDAR depth visualization.
///
/// Wraps a Metal-based MTKView to display depth data as a color gradient overlay.
/// Near objects appear red, far objects appear blue.
///
/// ## Usage
/// ```swift
/// ZStack {
///     // Camera preview
///     ARViewContainer()
///
///     // Depth overlay
///     DepthOverlayView(
///         depthFrame: viewModel.currentDepthFrame,
///         opacity: $depthOpacity,
///         isVisible: $showDepthOverlay
///     )
/// }
/// ```
public struct DepthOverlayView: UIViewRepresentable {

    /// Current depth frame to render (nil = transparent)
    public let depthFrame: DepthFrame?

    /// Overlay opacity (0.0 = transparent, 1.0 = opaque)
    @Binding public var opacity: Float

    /// Whether the overlay is visible
    @Binding public var isVisible: Bool

    /// Creates a new depth overlay view.
    ///
    /// - Parameters:
    ///   - depthFrame: Current depth frame to render
    ///   - opacity: Binding to opacity value
    ///   - isVisible: Binding to visibility state
    public init(
        depthFrame: DepthFrame?,
        opacity: Binding<Float>,
        isVisible: Binding<Bool>
    ) {
        self.depthFrame = depthFrame
        self._opacity = opacity
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
        metalView.preferredFramesPerSecond = 60

        // Transparent background for overlay
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.isOpaque = false
        metalView.backgroundColor = .clear

        return metalView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.depthFrame = depthFrame
        context.coordinator.opacity = opacity
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

    /// Coordinator class that manages Metal rendering.
    public class Coordinator: NSObject, MTKViewDelegate {
        private static let logger = Logger(subsystem: "app.rial", category: "depthoverlay")

        var parent: DepthOverlayView
        var visualizer: DepthVisualizer?
        var depthFrame: DepthFrame?
        var opacity: Float = 0.4
        var isVisible: Bool = true

        init(_ parent: DepthOverlayView) {
            self.parent = parent
            super.init()

            // Initialize visualizer
            do {
                visualizer = try DepthVisualizer()
            } catch {
                Self.logger.error("Failed to initialize DepthVisualizer: \(error.localizedDescription)")
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
                Self.logger.debug("Visualizer not available, skipping render")
                return
            }

            do {
                try visualizer.render(depthFrame: depthFrame, to: view, opacity: opacity)
            } catch {
                Self.logger.error("Render failed: \(error.localizedDescription)")
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

// MARK: - DepthOverlayToggleButton

/// Toggle button for showing/hiding depth overlay.
///
/// Displays an eye icon that toggles between visible and hidden states.
public struct DepthOverlayToggleButton: View {
    @Binding var isVisible: Bool

    public init(isVisible: Binding<Bool>) {
        self._isVisible = isVisible
    }

    public var body: some View {
        Button(action: { isVisible.toggle() }) {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .font(.title2)
                .foregroundColor(.white)
                .padding(12)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityLabel(isVisible ? "Hide depth overlay" : "Show depth overlay")
        .accessibilityHint("Double tap to toggle depth visualization")
    }
}

// MARK: - DepthOverlayOpacitySlider

/// Slider for adjusting depth overlay opacity.
public struct DepthOverlayOpacitySlider: View {
    @Binding var opacity: Float

    public init(opacity: Binding<Float>) {
        self._opacity = opacity
    }

    public var body: some View {
        HStack {
            Image(systemName: "circle.dotted")
                .foregroundColor(.white)

            Slider(
                value: $opacity,
                in: 0...1,
                step: 0.1
            )
            .tint(.white)

            Image(systemName: "circle.fill")
                .foregroundColor(.white)
        }
        .padding(.horizontal)
        .accessibilityLabel("Depth overlay opacity: \(Int(opacity * 100))%")
    }
}

// MARK: - Preview Provider

#if DEBUG
struct DepthOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            DepthOverlayView(
                depthFrame: nil,
                opacity: .constant(0.4),
                isVisible: .constant(true)
            )
        }
    }
}
#endif
