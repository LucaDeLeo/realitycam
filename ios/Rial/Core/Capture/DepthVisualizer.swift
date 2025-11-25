//
//  DepthVisualizer.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Metal-based depth visualization pipeline for real-time LiDAR rendering.
//

import Foundation
import Metal
import MetalKit
import ARKit
import os.log

// MARK: - DepthVisualizer

/// GPU-accelerated depth visualization using Metal shaders.
///
/// DepthVisualizer renders LiDAR depth data as a real-time color gradient overlay
/// at 60fps with < 2ms GPU time per frame. Near objects appear red, far objects
/// appear blue, providing immediate visual feedback on depth capture quality.
///
/// ## Performance Targets
/// - Frame rate: 60fps sustained
/// - GPU time: < 2ms per frame
/// - Texture upload: < 1ms
///
/// ## Usage
/// ```swift
/// let visualizer = try DepthVisualizer()
///
/// // In render loop (MTKViewDelegate.draw(in:))
/// if let depthFrame = currentDepthFrame {
///     try visualizer.render(depthFrame: depthFrame, to: metalView, opacity: 0.4)
/// }
/// ```
///
/// - Important: Full rendering requires physical device with Metal GPU.
public final class DepthVisualizer {

    // MARK: - Properties

    /// Logger for depth visualization events
    private static let logger = Logger(subsystem: "app.rial", category: "depthvisualizer")

    /// Metal device for GPU operations
    public let device: MTLDevice

    /// Command queue for submitting render commands
    private let commandQueue: MTLCommandQueue

    /// Compiled render pipeline state
    private var pipelineState: MTLRenderPipelineState?

    /// Vertex buffer for full-screen quad
    private var vertexBuffer: MTLBuffer?

    /// Minimum depth for normalization (meters)
    public var nearPlane: Float = 0.5

    /// Maximum depth for normalization (meters)
    public var farPlane: Float = 5.0

    /// Whether Metal is available on this device
    public static var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    // MARK: - Initialization

    /// Creates a new DepthVisualizer with Metal pipeline.
    ///
    /// - Throws: `VisualizationError.metalNotAvailable` if Metal not supported,
    ///           `VisualizationError.commandQueueCreationFailed` if queue creation fails,
    ///           `VisualizationError.shaderCompilationFailed` if shader compilation fails
    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.logger.error("Metal not available on this device")
            throw VisualizationError.metalNotAvailable
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            Self.logger.error("Failed to create Metal command queue")
            throw VisualizationError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        try setupPipeline()
        setupVertexBuffer()

        Self.logger.debug("DepthVisualizer initialized with device: \(device.name)")
    }

    // MARK: - Pipeline Setup

    /// Set up the Metal render pipeline.
    private func setupPipeline() throws {
        guard let library = device.makeDefaultLibrary() else {
            Self.logger.error("Failed to load Metal shader library")
            throw VisualizationError.shaderCompilationFailed
        }

        guard let vertexFunction = library.makeFunction(name: "depthVertex"),
              let fragmentFunction = library.makeFunction(name: "depthFragment") else {
            Self.logger.error("Failed to find shader functions in library")
            throw VisualizationError.shaderCompilationFailed
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
            Self.logger.debug("Render pipeline state created successfully")
        } catch {
            Self.logger.error("Failed to create render pipeline state: \(error.localizedDescription)")
            throw VisualizationError.shaderCompilationFailed
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

    /// Render depth data to the Metal view.
    ///
    /// - Parameters:
    ///   - depthFrame: Depth frame containing CVPixelBuffer depth map
    ///   - view: MTKView to render to
    ///   - opacity: Overlay opacity (0.0 = transparent, 1.0 = opaque)
    /// - Throws: `VisualizationError` if rendering fails
    public func render(depthFrame: DepthFrame, to view: MTKView, opacity: Float) throws {
        guard let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer else {
            throw VisualizationError.renderEncodingFailed
        }

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            // View not ready - skip frame
            return
        }

        // Create depth texture from pixel buffer
        guard let depthTexture = createDepthTexture(from: depthFrame.depthMap) else {
            throw VisualizationError.depthTextureCreationFailed
        }

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw VisualizationError.renderEncodingFailed
        }

        // Configure render pass for transparent background
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // Create render encoder
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw VisualizationError.renderEncodingFailed
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(depthTexture, index: 0)

        // Set shader parameters
        var nearPlaneValue = nearPlane
        var farPlaneValue = farPlane
        var opacityValue = opacity
        encoder.setFragmentBytes(&nearPlaneValue, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentBytes(&farPlaneValue, length: MemoryLayout<Float>.size, index: 1)
        encoder.setFragmentBytes(&opacityValue, length: MemoryLayout<Float>.size, index: 2)

        // Draw full-screen quad
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        // Present and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
}

// MARK: - DepthFrame

/// Depth frame data for visualization.
///
/// Contains the raw depth pixel buffer and associated metadata from an ARFrame.
public struct DepthFrame: Sendable {
    /// Raw Float32 depth values (meters)
    public let depthMap: CVPixelBuffer

    /// Depth map width in pixels
    public let width: Int

    /// Depth map height in pixels
    public let height: Int

    /// Frame capture timestamp
    public let timestamp: TimeInterval

    /// Camera intrinsics matrix
    public let intrinsics: simd_float3x3

    /// Camera transform matrix
    public let transform: simd_float4x4

    /// Creates a DepthFrame from an ARFrame.
    ///
    /// - Parameter arFrame: ARFrame with sceneDepth data
    /// - Returns: DepthFrame, or nil if sceneDepth is unavailable
    public init?(from arFrame: ARFrame) {
        guard let sceneDepth = arFrame.sceneDepth else {
            return nil
        }

        self.depthMap = sceneDepth.depthMap
        self.width = CVPixelBufferGetWidth(sceneDepth.depthMap)
        self.height = CVPixelBufferGetHeight(sceneDepth.depthMap)
        self.timestamp = arFrame.timestamp
        self.intrinsics = arFrame.camera.intrinsics
        self.transform = arFrame.camera.transform
    }

    /// Creates a DepthFrame with explicit values (for testing).
    ///
    /// - Parameters:
    ///   - depthMap: CVPixelBuffer with Float32 depth data
    ///   - timestamp: Frame timestamp
    ///   - intrinsics: Camera intrinsics
    ///   - transform: Camera transform
    public init(
        depthMap: CVPixelBuffer,
        timestamp: TimeInterval = 0,
        intrinsics: simd_float3x3 = matrix_identity_float3x3,
        transform: simd_float4x4 = matrix_identity_float4x4
    ) {
        self.depthMap = depthMap
        self.width = CVPixelBufferGetWidth(depthMap)
        self.height = CVPixelBufferGetHeight(depthMap)
        self.timestamp = timestamp
        self.intrinsics = intrinsics
        self.transform = transform
    }
}

// MARK: - VisualizationError

/// Errors that can occur during depth visualization.
public enum VisualizationError: Error, LocalizedError, Equatable {
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
            return "Failed to compile depth visualization shader"
        case .commandQueueCreationFailed:
            return "Failed to create Metal command queue"
        case .depthTextureCreationFailed:
            return "Failed to create depth texture from LiDAR data"
        case .renderEncodingFailed:
            return "Failed to encode rendering commands"
        }
    }
}
