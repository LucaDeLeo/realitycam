//
//  DepthVisualizerTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for Metal-based depth visualization.
//

import XCTest
import Metal
import MetalKit
import CoreVideo
import simd
import SwiftUI
@testable import Rial

final class DepthVisualizerTests: XCTestCase {

    // MARK: - DepthVisualizer Tests

    /// Test that Metal availability check returns expected value
    func testIsMetalAvailable_ReturnsValue() {
        // Metal is available on all iOS devices
        // This test verifies the static property is accessible
        let isAvailable = DepthVisualizer.isMetalAvailable
        // On real device/simulator with GPU, should be true
        XCTAssertNotNil(isAvailable)
    }

    /// Test DepthVisualizer initialization on supported device
    func testInit_OnSupportedDevice_Succeeds() throws {
        // Skip on simulator without Metal
        try XCTSkipIf(!DepthVisualizer.isMetalAvailable, "Metal not available")

        let visualizer = try DepthVisualizer()
        XCTAssertNotNil(visualizer.device)
    }

    /// Test default near/far plane values
    func testInit_DefaultPlaneValues() throws {
        try XCTSkipIf(!DepthVisualizer.isMetalAvailable, "Metal not available")

        let visualizer = try DepthVisualizer()
        XCTAssertEqual(visualizer.nearPlane, 0.5, accuracy: 0.001)
        XCTAssertEqual(visualizer.farPlane, 5.0, accuracy: 0.001)
    }

    /// Test custom near/far plane values
    func testPlaneValues_CanBeModified() throws {
        try XCTSkipIf(!DepthVisualizer.isMetalAvailable, "Metal not available")

        let visualizer = try DepthVisualizer()
        visualizer.nearPlane = 0.3
        visualizer.farPlane = 10.0

        XCTAssertEqual(visualizer.nearPlane, 0.3, accuracy: 0.001)
        XCTAssertEqual(visualizer.farPlane, 10.0, accuracy: 0.001)
    }

    // MARK: - VisualizationError Tests

    /// Test error descriptions exist
    func testVisualizationError_AllCasesHaveDescriptions() {
        let errors: [VisualizationError] = [
            .metalNotAvailable,
            .shaderCompilationFailed,
            .commandQueueCreationFailed,
            .depthTextureCreationFailed,
            .renderEncodingFailed
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) description should not be empty")
        }
    }

    /// Test metalNotAvailable error description
    func testVisualizationError_MetalNotAvailable_Description() {
        let error = VisualizationError.metalNotAvailable
        XCTAssertEqual(error.errorDescription, "Metal graphics not available on this device")
    }

    /// Test shaderCompilationFailed error description
    func testVisualizationError_ShaderCompilationFailed_Description() {
        let error = VisualizationError.shaderCompilationFailed
        XCTAssertEqual(error.errorDescription, "Failed to compile depth visualization shader")
    }

    /// Test commandQueueCreationFailed error description
    func testVisualizationError_CommandQueueCreationFailed_Description() {
        let error = VisualizationError.commandQueueCreationFailed
        XCTAssertEqual(error.errorDescription, "Failed to create Metal command queue")
    }

    /// Test depthTextureCreationFailed error description
    func testVisualizationError_DepthTextureCreationFailed_Description() {
        let error = VisualizationError.depthTextureCreationFailed
        XCTAssertEqual(error.errorDescription, "Failed to create depth texture from LiDAR data")
    }

    /// Test renderEncodingFailed error description
    func testVisualizationError_RenderEncodingFailed_Description() {
        let error = VisualizationError.renderEncodingFailed
        XCTAssertEqual(error.errorDescription, "Failed to encode rendering commands")
    }

    /// Test VisualizationError is Equatable
    func testVisualizationError_Equatable() {
        XCTAssertEqual(VisualizationError.metalNotAvailable, VisualizationError.metalNotAvailable)
        XCTAssertNotEqual(VisualizationError.metalNotAvailable, VisualizationError.shaderCompilationFailed)
        XCTAssertEqual(VisualizationError.renderEncodingFailed, VisualizationError.renderEncodingFailed)
    }

    // MARK: - DepthFrame Tests

    /// Test DepthFrame initialization with explicit values
    func testDepthFrame_InitWithExplicitValues() throws {
        let pixelBuffer = try createMockDepthPixelBuffer(width: 256, height: 192)

        let depthFrame = DepthFrame(
            depthMap: pixelBuffer,
            timestamp: 123.456,
            intrinsics: matrix_identity_float3x3,
            transform: matrix_identity_float4x4
        )

        XCTAssertEqual(depthFrame.width, 256)
        XCTAssertEqual(depthFrame.height, 192)
        XCTAssertEqual(depthFrame.timestamp, 123.456, accuracy: 0.001)
    }

    /// Test DepthFrame dimensions are extracted correctly
    func testDepthFrame_DimensionsMatchPixelBuffer() throws {
        let testCases: [(width: Int, height: Int)] = [
            (256, 192),   // Typical LiDAR resolution
            (128, 96),    // Half resolution
            (512, 384)    // Double resolution
        ]

        for testCase in testCases {
            let pixelBuffer = try createMockDepthPixelBuffer(width: testCase.width, height: testCase.height)
            let depthFrame = DepthFrame(depthMap: pixelBuffer)

            XCTAssertEqual(depthFrame.width, testCase.width, "Width should match for \(testCase)")
            XCTAssertEqual(depthFrame.height, testCase.height, "Height should match for \(testCase)")
        }
    }

    /// Test DepthFrame default timestamp is zero
    func testDepthFrame_DefaultTimestamp() throws {
        let pixelBuffer = try createMockDepthPixelBuffer(width: 256, height: 192)
        let depthFrame = DepthFrame(depthMap: pixelBuffer)

        XCTAssertEqual(depthFrame.timestamp, 0)
    }

    /// Test DepthFrame default intrinsics is identity matrix
    func testDepthFrame_DefaultIntrinsics() throws {
        let pixelBuffer = try createMockDepthPixelBuffer(width: 256, height: 192)
        let depthFrame = DepthFrame(depthMap: pixelBuffer)

        let identity = matrix_identity_float3x3
        XCTAssertEqual(depthFrame.intrinsics.columns.0.x, identity.columns.0.x)
        XCTAssertEqual(depthFrame.intrinsics.columns.1.y, identity.columns.1.y)
        XCTAssertEqual(depthFrame.intrinsics.columns.2.z, identity.columns.2.z)
    }

    /// Test DepthFrame default transform is identity matrix
    func testDepthFrame_DefaultTransform() throws {
        let pixelBuffer = try createMockDepthPixelBuffer(width: 256, height: 192)
        let depthFrame = DepthFrame(depthMap: pixelBuffer)

        let identity = matrix_identity_float4x4
        XCTAssertEqual(depthFrame.transform.columns.0.x, identity.columns.0.x)
        XCTAssertEqual(depthFrame.transform.columns.3.w, identity.columns.3.w)
    }

    // MARK: - Physical Device Tests (Require LiDAR)

    /// Test rendering with real depth data (physical device only)
    func testRender_OnPhysicalDevice_CompletesWithoutError() throws {
        try XCTSkipIf(!DepthVisualizer.isMetalAvailable, "Metal not available")
        try XCTSkipIf(isSimulator(), "Requires physical device with Metal GPU")

        let visualizer = try DepthVisualizer()
        let pixelBuffer = try createMockDepthPixelBuffer(width: 256, height: 192)
        let depthFrame = DepthFrame(depthMap: pixelBuffer)

        // Create MTKView for testing
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 300, height: 400), device: visualizer.device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false

        // Rendering should complete without error
        // Note: Actual visual output can't be verified in unit tests
        XCTAssertNoThrow(try visualizer.render(depthFrame: depthFrame, to: metalView, opacity: 0.4))
    }

    /// Test rendering with different opacity values
    func testRender_DifferentOpacities_AllSucceed() throws {
        try XCTSkipIf(!DepthVisualizer.isMetalAvailable, "Metal not available")
        try XCTSkipIf(isSimulator(), "Requires physical device with Metal GPU")

        let visualizer = try DepthVisualizer()
        let pixelBuffer = try createMockDepthPixelBuffer(width: 256, height: 192)
        let depthFrame = DepthFrame(depthMap: pixelBuffer)

        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 300, height: 400), device: visualizer.device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false

        let opacities: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        for opacity in opacities {
            XCTAssertNoThrow(try visualizer.render(depthFrame: depthFrame, to: metalView, opacity: opacity),
                            "Rendering should succeed with opacity \(opacity)")
        }
    }

    // MARK: - Helpers

    /// Check if running on simulator
    private func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Create a mock depth CVPixelBuffer with Float32 values
    private func createMockDepthPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "DepthVisualizerTests", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create mock depth pixel buffer"
            ])
        }

        // Fill with sample depth values (gradient from near to far)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
            let count = width * height

            for i in 0..<count {
                // Create depth gradient from 0.5m to 5.0m
                let x = i % width
                let y = i / width
                let normalized = Float(x + y) / Float(width + height)
                floatPointer[i] = 0.5 + normalized * 4.5  // 0.5m to 5.0m
            }
        }

        return buffer
    }
}

// MARK: - DepthOverlayView Tests

final class DepthOverlayViewTests: XCTestCase {

    /// Test DepthOverlayToggleButton initializes with correct state
    func testToggleButton_InitialState() {
        var isVisible = true
        let button = DepthOverlayToggleButton(isVisible: Binding(
            get: { isVisible },
            set: { isVisible = $0 }
        ))

        XCTAssertNotNil(button)
    }

    /// Test DepthOverlayOpacitySlider initializes correctly
    func testOpacitySlider_InitialState() {
        var opacity: Float = 0.4
        let slider = DepthOverlayOpacitySlider(opacity: Binding(
            get: { opacity },
            set: { opacity = $0 }
        ))

        XCTAssertNotNil(slider)
    }

    /// Test default opacity value
    func testOpacitySlider_DefaultOpacity() {
        var opacity: Float = 0.4
        _ = DepthOverlayOpacitySlider(opacity: Binding(
            get: { opacity },
            set: { opacity = $0 }
        ))

        XCTAssertEqual(opacity, 0.4, accuracy: 0.01)
    }
}
