//
//  EdgeDepthVisualizer.swift
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  Metal-based Sobel edge detection visualization for real-time depth overlay.
//  Renders depth discontinuities during video recording preview.
//

import Foundation
import Metal
import MetalKit
import ARKit
import os.log

// MARK: - EdgeDepthVisualizer

/// GPU-accelerated Sobel edge detection visualization for LiDAR depth data.
///
/// EdgeDepthVisualizer renders depth discontinuities as colored edges (cyan=near, magenta=far)
/// at 30fps with < 3ms GPU time per frame. Unlike the full colormap `DepthVisualizer`,
/// this edge-only approach provides depth feedback during video recording without
/// obscuring the camera preview.
///
/// ## Performance Targets
/// - Frame rate: 30fps (matching video recording)
/// - GPU time: < 3ms per frame
/// - Memory: < 20MB additional
///
/// ## Usage
/// ```swift
/// let visualizer = try EdgeDepthVisualizer()
///
/// // In render loop (MTKViewDelegate.draw(in:))
/// if let depthFrame = currentDepthFrame {
///     try visualizer.render(depthFrame: depthFrame, to: metalView, edgeThreshold: 0.1)
/// }
/// ```
///
/// - Important: Full rendering requires physical device with Metal GPU.
/// - Note: Overlay renders to preview only, NOT to recorded video.
public final class EdgeDepthVisualizer {

    // MARK: - Properties

    /// Logger for edge depth visualization events
    private static let logger = Logger(subsystem: "app.rial", category: "edgedepthvisualizer")

    /// Metal device for GPU operations
    public let device: MTLDevice

    /// Command queue for submitting render commands
    private let commandQueue: MTLCommandQueue

    /// Compiled render pipeline state for edge detection
    private var pipelineState: MTLRenderPipelineState?

    /// Vertex buffer for full-screen quad
    private var vertexBuffer: MTLBuffer?

    /// Minimum depth for color normalization (meters)
    public var nearPlane: Float = 0.5

    /// Maximum depth for color normalization (meters)
    public var farPlane: Float = 5.0

    /// Default edge detection threshold
    public static let defaultEdgeThreshold: Float = 0.1

    /// Whether Metal is available on this device
    public static var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    // MARK: - Performance Tracking

    /// Last recorded GPU time for render pass (milliseconds)
    private(set) var lastRenderTimeMs: Double = 0

    /// Moving average of render times (milliseconds)
    private var renderTimeAverage: Double = 0

    /// Number of frames used for moving average
    private var frameCount: Int = 0

    // MARK: - Initialization

    /// Creates a new EdgeDepthVisualizer with Metal pipeline.
    ///
    /// - Throws: `EdgeVisualizationError.metalNotAvailable` if Metal not supported,
    ///           `EdgeVisualizationError.commandQueueCreationFailed` if queue creation fails,
    ///           `EdgeVisualizationError.shaderCompilationFailed` if shader compilation fails
    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.logger.error("Metal not available on this device")
            throw EdgeVisualizationError.metalNotAvailable
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            Self.logger.error("Failed to create Metal command queue")
            throw EdgeVisualizationError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        try setupPipeline()
        setupVertexBuffer()

        Self.logger.debug("EdgeDepthVisualizer initialized with device: \(device.name)")
    }

    // MARK: - Pipeline Setup

    /// Set up the Metal render pipeline for edge detection.
    private func setupPipeline() throws {
        guard let library = device.makeDefaultLibrary() else {
            Self.logger.error("Failed to load Metal shader library")
            throw EdgeVisualizationError.shaderCompilationFailed
        }

        guard let vertexFunction = library.makeFunction(name: "edgeDepthVertex"),
              let fragmentFunction = library.makeFunction(name: "edgeDepthFragment") else {
            Self.logger.error("Failed to find edge shader functions in library")
            throw EdgeVisualizationError.shaderCompilationFailed
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable alpha blending for overlay transparency
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            Self.logger.debug("Edge render pipeline state created successfully")
        } catch {
            Self.logger.error("Failed to create edge render pipeline state: \(error.localizedDescription)")
            throw EdgeVisualizationError.shaderCompilationFailed
        }
    }

    /// Set up vertex buffer for full-screen quad.
    private func setupVertexBuffer() {
        // Full-screen quad vertices (2 triangles, 6 vertices)
        // Clip space coordinates: -1 to 1
        let vertices: [SIMD2<Float>] = [
            SIMD2(-1.0, -1.0),  // Bottom-left
            SIMD2( 1.0, -1.0),  // Bottom-right
            SIMD2(-1.0,  1.0),  // Top-left
            SIMD2(-1.0,  1.0),  // Top-left
            SIMD2( 1.0, -1.0),  // Bottom-right
            SIMD2( 1.0,  1.0)   // Top-right
        ]

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - Rendering

    /// Render Sobel edge detection overlay to the Metal view.
    ///
    /// - Parameters:
    ///   - depthFrame: Depth frame containing CVPixelBuffer depth map
    ///   - view: MTKView to render to
    ///   - edgeThreshold: Minimum edge magnitude to render (default: 0.1)
    /// - Throws: `EdgeVisualizationError` if rendering fails
    public func render(depthFrame: DepthFrame, to view: MTKView, edgeThreshold: Float = defaultEdgeThreshold) throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer else {
            throw EdgeVisualizationError.renderEncodingFailed
        }

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            // View not ready - skip frame
            return
        }

        // Create depth texture from pixel buffer
        guard let depthTexture = createDepthTexture(from: depthFrame.depthMap) else {
            throw EdgeVisualizationError.depthTextureCreationFailed
        }

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw EdgeVisualizationError.renderEncodingFailed
        }

        // Configure render pass for transparent background
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // Create render encoder
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw EdgeVisualizationError.renderEncodingFailed
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(depthTexture, index: 0)

        // Set shader parameters
        var nearPlaneValue = nearPlane
        var farPlaneValue = farPlane
        var thresholdValue = edgeThreshold
        encoder.setFragmentBytes(&nearPlaneValue, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentBytes(&farPlaneValue, length: MemoryLayout<Float>.size, index: 1)
        encoder.setFragmentBytes(&thresholdValue, length: MemoryLayout<Float>.size, index: 2)

        // Draw full-screen quad
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        // Present and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Track render time
        let endTime = CFAbsoluteTimeGetCurrent()
        lastRenderTimeMs = (endTime - startTime) * 1000.0
        updateRenderTimeAverage()

        // Log warning if exceeding 3ms budget
        if lastRenderTimeMs > 3.0 {
            Self.logger.warning("Edge render exceeded 3ms budget: \(String(format: "%.2f", self.lastRenderTimeMs))ms")
        }
    }

    // MARK: - Texture Creation

    /// Create Metal texture from depth pixel buffer.
    ///
    /// - Parameter pixelBuffer: CVPixelBuffer containing Float32 depth values
    /// - Returns: MTLTexture with r32Float format, or nil if creation fails
    private func createDepthTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            Self.logger.error("Failed to create depth texture (\(width)x\(height))")
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            Self.logger.error("Failed to get pixel buffer base address")
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, width, height)

        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    // MARK: - Performance Tracking

    /// Update the moving average of render times.
    private func updateRenderTimeAverage() {
        frameCount += 1
        if frameCount == 1 {
            renderTimeAverage = lastRenderTimeMs
        } else {
            // Exponential moving average with alpha = 0.1
            renderTimeAverage = 0.9 * renderTimeAverage + 0.1 * lastRenderTimeMs
        }
    }

    /// Get the average render time over recent frames.
    ///
    /// - Returns: Average render time in milliseconds
    public func getAverageRenderTimeMs() -> Double {
        return renderTimeAverage
    }

    /// Reset performance tracking counters.
    public func resetPerformanceTracking() {
        lastRenderTimeMs = 0
        renderTimeAverage = 0
        frameCount = 0
    }
}

// MARK: - EdgeVisualizationError

/// Errors that can occur during edge depth visualization.
public enum EdgeVisualizationError: Error, LocalizedError, Equatable {
    /// Metal is not available on this device
    case metalNotAvailable

    /// Failed to compile Metal shaders
    case shaderCompilationFailed

    /// Failed to create Metal command queue
    case commandQueueCreationFailed

    /// Failed to create depth texture from pixel buffer
    case depthTextureCreationFailed

    /// Failed to encode render commands
    case renderEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .metalNotAvailable:
            return "Metal graphics not available on this device"
        case .shaderCompilationFailed:
            return "Failed to compile edge detection shader"
        case .commandQueueCreationFailed:
            return "Failed to create Metal command queue"
        case .depthTextureCreationFailed:
            return "Failed to create depth texture from LiDAR data"
        case .renderEncodingFailed:
            return "Failed to encode rendering commands"
        }
    }
}
