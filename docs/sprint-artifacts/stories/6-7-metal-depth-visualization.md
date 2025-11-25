# Story 6.7: Metal Depth Visualization

**Story Key:** 6-7-metal-depth-visualization
**Epic:** 6 - Native Swift Implementation
**Status:** Done
**Created:** 2025-11-25

---

## User Story

As a **photographer using RealityCam**,
I want **real-time depth visualization overlaid on the camera preview**,
So that **I can see LiDAR depth data rendered as a color gradient at 60fps to confirm depth capture quality before taking a photo**.

## Story Context

This story implements GPU-accelerated depth visualization using Metal shaders to render LiDAR depth maps as real-time color gradients overlaid on the camera preview. The visualization provides immediate feedback on depth capture quality, helping users understand scene geometry and identify potential depth data issues before capturing.

MetalKit provides 60fps rendering with minimal CPU overhead by processing depth data entirely on the GPU. The custom shader pipeline converts depth values (in meters) to color gradients, with near objects rendered in warm colors (red) and far objects in cool colors (blue).

### Key Visualization Features

1. **GPU-Native Rendering**: Metal shader processes Float32 depth texture directly
2. **Color Gradient Mapping**: Near (red) → Mid (green/yellow) → Far (blue)
3. **Adjustable Opacity**: 0-100% overlay transparency for balancing depth view with RGB preview
4. **Toggle Control**: Instant on/off without restarting ARSession
5. **Real-Time Performance**: 60fps rendering with < 2ms per frame GPU time

### Performance Targets

| Operation | Target | Rationale |
|-----------|--------|-----------|
| Frame rate | 60fps sustained | Smooth visual feedback |
| GPU time per frame | < 2ms | Leave headroom for other rendering |
| Depth texture upload | < 1ms | CPU → GPU transfer |
| Shader execution | < 1ms | Fragment shader processing |
| UI responsiveness | No dropped frames | Toggle and opacity changes instant |

### Color Mapping Strategy

| Depth Range | Color | Visual Meaning |
|-------------|-------|---------------|
| 0.0 - 1.0m | Red (1.0, 0.0, 0.0) | Very close objects |
| 1.0 - 2.5m | Yellow/Green | Medium distance |
| 2.5 - 5.0m | Cyan | Far objects |
| 5.0m+ | Blue (0.0, 0.0, 1.0) | Maximum depth |
| No data | Transparent | Gaps in depth map |

---

## Acceptance Criteria

### AC1: Metal Shader Depth Fragment Implementation
**Given** a Metal shader file with depth colormap fragment function
**When** the shader receives depth texture and rendering parameters
**Then**:
- Fragment shader samples depth texture at current fragment position
- Depth value (Float32 meters) normalized to 0.0-1.0 range using near/far plane parameters
- Normalized depth mapped to color gradient: `mix(nearColor, farColor, normalizedDepth)`
- Near color constant: `float3(1.0, 0.0, 0.0)` (red)
- Far color constant: `float3(0.0, 0.0, 1.0)` (blue)
- Opacity parameter applied to alpha channel
- Missing depth data (NaN, Inf) renders as transparent

**And** shader performance:
- Fragment shader compiles without errors
- Shader execution < 1ms per frame
- No GPU memory leaks
- Compatible with Metal 2.0+ (iOS 15.0+)

**Implementation Reference:**
```metal
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

constant float3 nearColor = float3(1.0, 0.0, 0.0);   // Red
constant float3 farColor = float3(0.0, 0.0, 1.0);    // Blue

fragment float4 depthFragment(
    VertexOut in [[stage_in]],
    texture2d<float> depthTex [[texture(0)]],
    constant float &nearPlane [[buffer(0)]],
    constant float &farPlane [[buffer(1)]],
    constant float &opacity [[buffer(2)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float depth = depthTex.sample(s, in.texCoord).r;

    // Handle invalid depth
    if (isinf(depth) || isnan(depth)) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    // Normalize depth to 0-1 range
    float normalized = saturate((depth - nearPlane) / (farPlane - nearPlane));

    // Interpolate between near and far colors
    float3 color = mix(nearColor, farColor, normalized);

    return float4(color, opacity);
}
```

### AC2: DepthVisualizer Swift Wrapper
**Given** a DepthVisualizer class that manages Metal rendering pipeline
**When** ARFrame depth data is provided
**Then**:
- Metal device and command queue initialized once
- Render pipeline state compiled from shader library
- Vertex buffer created for full-screen quad
- Depth texture created from CVPixelBuffer (MTLPixelFormat.r32Float)
- Render pass descriptor configured for overlay blending
- Command buffer encodes rendering commands
- Parameter buffers set for nearPlane, farPlane, opacity
- Drawable rendered to MTKView

**And** rendering state management:
- Pipeline initialized lazily (not on main thread)
- Resources reused across frames (no per-frame allocation)
- Old depth textures released promptly
- Error handling for pipeline compilation failures
- Fallback behavior if Metal unavailable (graceful degradation)

**Implementation Reference:**
```swift
import Metal
import MetalKit
import ARKit

class DepthVisualizer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?

    private var nearPlane: Float = 0.5    // 0.5m minimum
    private var farPlane: Float = 5.0     // 5.0m maximum
    private var opacity: Float = 0.4      // 40% opacity

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw VisualizationError.metalNotAvailable
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw VisualizationError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        try setupPipeline()
    }

    func render(depthMap: CVPixelBuffer, to view: MTKView) throws {
        // Create texture, encode render pass, commit
    }
}
```

### AC3: Depth Rendering at 60fps
**Given** ARSession running with sceneDepth frames at 60fps
**When** DepthOverlayView receives frame updates
**Then**:
- Frame rate measured with Xcode FPS gauge
- Sustained 60fps (> 57fps) for 95% of frames
- No dropped frames during normal operation
- GPU time per frame < 2ms (measured with Metal debugger)
- CPU overhead < 5% (depth texture upload only)

**And** performance under stress:
- 60fps maintained while camera moving rapidly
- 60fps maintained during scene transitions
- 60fps maintained with complex geometry
- Frame rate recovers quickly after thermal throttling
- No cumulative performance degradation over time

### AC4: Opacity Adjustment (0-100%)
**Given** user wants to adjust depth overlay visibility
**When** opacity slider is adjusted
**Then**:
- Opacity value range: 0.0 (fully transparent) to 1.0 (fully opaque)
- Opacity changes reflected immediately (next frame)
- Smooth interpolation between opacity values
- No flicker or visual artifacts during adjustment
- Opacity value persisted across app restarts (UserDefaults)

**And** opacity presets:
- Default: 0.4 (40%) - balanced visibility
- Minimum: 0.0 (0%) - depth hidden
- Maximum: 1.0 (100%) - depth fully opaque
- Recommended range: 0.3-0.6 for usability

### AC5: Toggle On/Off Without ARSession Restart
**Given** depth overlay is currently visible
**When** user taps toggle button
**Then**:
- Depth overlay visibility changes instantly (same frame)
- ARSession continues running without interruption
- No performance impact when toggled off
- Toggle state persisted in UserDefaults
- SF Symbol icon reflects current state: `eye` (on) / `eye.slash` (off)

**And** toggle behavior:
- Toggle button always accessible in capture UI
- Keyboard shortcut support (Space bar) for accessibility
- VoiceOver announces toggle state changes
- Toggle works in portrait and landscape orientations

### AC6: SwiftUI DepthOverlayView Integration
**Given** SwiftUI CaptureView needs depth overlay
**When** DepthOverlayView is added to ZStack
**Then**:
- DepthOverlayView wraps MTKView as UIViewRepresentable
- ARFrame depth data passed via `@Binding` or publisher
- View renders depth when depthFrame is not nil
- View renders transparent when depthFrame is nil
- View size matches parent container (full screen)
- View handles orientation changes automatically

**And** SwiftUI integration:
- View updates triggered by ARFrame publisher
- No memory leaks in SwiftUI view lifecycle
- Proper cleanup in `dismantleUIView`
- Coordinator pattern for MTKViewDelegate
- Render loop synchronized with ARSession

**Implementation Reference:**
```swift
struct DepthOverlayView: UIViewRepresentable {
    let depthFrame: DepthFrame?
    @Binding var opacity: Float
    @Binding var isVisible: Bool

    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = context.coordinator.visualizer.device
        metalView.delegate = context.coordinator
        metalView.framebufferOnly = false
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        return metalView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.depthFrame = depthFrame
        context.coordinator.opacity = opacity
        context.coordinator.isVisible = isVisible
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: DepthOverlayView
        var visualizer: DepthVisualizer
        var depthFrame: DepthFrame?
        var opacity: Float = 0.4
        var isVisible: Bool = true

        func draw(in view: MTKView) {
            guard isVisible, let depthFrame = depthFrame else { return }
            try? visualizer.render(depthFrame: depthFrame, to: view, opacity: opacity)
        }
    }
}
```

### AC7: Portrait and Landscape Support
**Given** device can rotate between portrait and landscape
**When** orientation changes occur
**Then**:
- Depth overlay resizes to match new dimensions
- Aspect ratio preserved (no stretching)
- Depth texture coordinates adjusted for orientation
- No visual glitches during rotation transition
- Rendering continues at 60fps during rotation

**And** orientation handling:
- All device orientations supported
- Rotation animations smooth
- Metal view coordinate system updated
- ARSession camera transform considered
- Testing on iPhone Pro in all orientations

### AC8: Error Handling and Graceful Degradation
**Given** Metal or depth data may be unavailable
**When** errors occur
**Then** appropriate error handling:
- `.metalNotAvailable` - Device doesn't support Metal (unlikely on iPhone Pro)
- `.shaderCompilationFailed` - Shader syntax error or incompatibility
- `.depthTextureCreationFailed` - CVPixelBuffer to MTLTexture conversion failed
- `.renderEncodingFailed` - Command buffer encoding error

**And** graceful degradation:
- If Metal unavailable: Hide depth overlay UI, show warning message
- If shader fails: Log error, disable depth overlay, allow capture to continue
- If texture creation fails: Skip frame, retry on next frame
- Errors logged with Logger for diagnostics
- User notified with non-intrusive alert

---

## Tasks

### Task 1: Create Metal Shader File (AC1)
- [ ] Create `ios/Rial/Shaders/DepthVisualization.metal`
- [ ] Define VertexOut struct with position and texCoord
- [ ] Define nearColor and farColor constants
- [ ] Implement vertex shader for full-screen quad
- [ ] Implement depthFragment shader with color mapping
- [ ] Handle invalid depth values (NaN, Inf)
- [ ] Add shader comments documenting parameters
- [ ] Verify shader compiles in Xcode

**Vertex Shader Implementation:**
```metal
vertex VertexOut depthVertex(
    uint vertexID [[vertex_id]],
    constant float2 *positions [[buffer(0)]]
) {
    VertexOut out;
    float2 pos = positions[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = (pos + 1.0) * 0.5;  // Convert -1...1 to 0...1
    out.texCoord.y = 1.0 - out.texCoord.y;  // Flip Y for texture coordinates
    return out;
}
```

### Task 2: Create DepthVisualizer Core Class (AC2)
- [ ] Create `ios/Rial/Core/Capture/DepthVisualizer.swift`
- [ ] Import Metal, MetalKit, ARKit frameworks
- [ ] Initialize MTLDevice and MTLCommandQueue
- [ ] Load shader library and create render pipeline state
- [ ] Create vertex buffer for full-screen quad vertices
- [ ] Implement `setupPipeline()` for pipeline initialization
- [ ] Implement `createDepthTexture(from: CVPixelBuffer)` for texture creation
- [ ] Implement `render(depthFrame:, to:, opacity:)` method
- [ ] Add error handling and logging
- [ ] Document with DocC comments

**Pipeline Setup Implementation:**
```swift
private func setupPipeline() throws {
    guard let library = device.makeDefaultLibrary() else {
        throw VisualizationError.shaderCompilationFailed
    }

    guard let vertexFunction = library.makeFunction(name: "depthVertex"),
          let fragmentFunction = library.makeFunction(name: "depthFragment") else {
        throw VisualizationError.shaderCompilationFailed
    }

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

    pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
}
```

### Task 3: Implement Depth Texture Creation (AC2)
- [ ] Create `createDepthTexture(from: CVPixelBuffer) -> MTLTexture?`
- [ ] Extract CVPixelBuffer properties (width, height, format)
- [ ] Verify pixel format is kCVPixelFormatType_DepthFloat32
- [ ] Create MTLTextureDescriptor with r32Float format
- [ ] Create MTLTexture from descriptor
- [ ] Copy CVPixelBuffer data to MTLTexture
- [ ] Handle texture cache for performance
- [ ] Log texture creation failures
- [ ] Test with real LiDAR depth data

**Texture Creation Implementation:**
```swift
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

    guard let texture = device.makeTexture(descriptor: descriptor) else {
        return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
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
```

### Task 4: Implement Render Method (AC2, AC3)
- [ ] Create `render(depthFrame:, to:, opacity:) throws`
- [ ] Create MTLCommandBuffer from command queue
- [ ] Create depth texture from CVPixelBuffer
- [ ] Get MTKView currentDrawable and renderPassDescriptor
- [ ] Create render command encoder
- [ ] Set pipeline state and vertex buffer
- [ ] Set depth texture at index 0
- [ ] Set parameter buffers (nearPlane, farPlane, opacity)
- [ ] Draw full-screen quad (6 vertices for 2 triangles)
- [ ] End encoding and present drawable
- [ ] Commit command buffer
- [ ] Measure and log frame time

**Render Implementation:**
```swift
func render(depthFrame: DepthFrame, to view: MTKView, opacity: Float) throws {
    guard let pipelineState = pipelineState,
          let drawable = view.currentDrawable,
          let renderPassDescriptor = view.currentRenderPassDescriptor else {
        throw VisualizationError.renderEncodingFailed
    }

    guard let depthTexture = createDepthTexture(from: depthFrame.depthMap) else {
        throw VisualizationError.depthTextureCreationFailed
    }

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
        throw VisualizationError.renderEncodingFailed
    }

    encoder.setRenderPipelineState(pipelineState)
    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    encoder.setFragmentTexture(depthTexture, index: 0)

    var nearPlane = self.nearPlane
    var farPlane = self.farPlane
    var opacityValue = opacity
    encoder.setFragmentBytes(&nearPlane, length: MemoryLayout<Float>.size, index: 0)
    encoder.setFragmentBytes(&farPlane, length: MemoryLayout<Float>.size, index: 1)
    encoder.setFragmentBytes(&opacityValue, length: MemoryLayout<Float>.size, index: 2)

    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()

    commandBuffer.present(drawable)
    commandBuffer.commit()
}
```

### Task 5: Create DepthFrame Model (AC2)
- [ ] Add DepthFrame struct to `ios/Rial/Models/CaptureData.swift`
- [ ] Define properties: depthMap (CVPixelBuffer), width, height, timestamp
- [ ] Add optional confidenceMap for future use
- [ ] Add intrinsics and transform from ARFrame
- [ ] Document with DocC comments

**DepthFrame Model:**
```swift
struct DepthFrame {
    let depthMap: CVPixelBuffer        // Float32 depth values (meters)
    let width: Int
    let height: Int
    let timestamp: TimeInterval
    let confidenceMap: [UInt8]?        // Per-pixel confidence (optional)
    let intrinsics: simd_float3x3      // Camera intrinsics
    let transform: simd_float4x4       // Camera transform

    init(from arFrame: ARFrame) {
        guard let sceneDepth = arFrame.sceneDepth else {
            fatalError("ARFrame missing sceneDepth")
        }

        self.depthMap = sceneDepth.depthMap
        self.width = CVPixelBufferGetWidth(sceneDepth.depthMap)
        self.height = CVPixelBufferGetHeight(sceneDepth.depthMap)
        self.timestamp = arFrame.timestamp
        self.confidenceMap = nil  // Future: extract from sceneDepth.confidenceMap
        self.intrinsics = arFrame.camera.intrinsics
        self.transform = arFrame.camera.transform
    }
}
```

### Task 6: Create DepthOverlayView SwiftUI Wrapper (AC6)
- [ ] Create `ios/Rial/Features/Capture/DepthOverlayView.swift`
- [ ] Implement UIViewRepresentable protocol
- [ ] Create MTKView in makeUIView
- [ ] Implement Coordinator as MTKViewDelegate
- [ ] Pass depthFrame, opacity, isVisible via updateUIView
- [ ] Implement draw(in:) in Coordinator
- [ ] Add proper cleanup in dismantleUIView
- [ ] Test view lifecycle (appear, disappear, update)
- [ ] Document with DocC comments

### Task 7: Integrate with CaptureView (AC5, AC6)
- [ ] Update `ios/Rial/Features/Capture/CaptureView.swift`
- [ ] Add @State var showDepthOverlay: Bool = true
- [ ] Add @State var depthOpacity: Float = 0.4
- [ ] Add @StateObject or @ObservedObject for depthFrame publisher
- [ ] Add DepthOverlayView to ZStack above AR camera
- [ ] Add toggle button with SF Symbol `eye`/`eye.slash`
- [ ] Add opacity slider (optional, can be settings)
- [ ] Persist toggle state to UserDefaults
- [ ] Test integration with ARCaptureSession (Story 6.5)

**CaptureView Integration:**
```swift
struct CaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @State private var showDepthOverlay = UserDefaults.standard.bool(forKey: "showDepthOverlay")
    @State private var depthOpacity: Float = UserDefaults.standard.float(forKey: "depthOpacity")

    var body: some View {
        ZStack {
            // AR Camera Preview
            ARViewContainer(session: viewModel.captureSession)
                .ignoresSafeArea()

            // Depth Overlay
            if showDepthOverlay {
                DepthOverlayView(
                    depthFrame: viewModel.currentDepthFrame,
                    opacity: $depthOpacity,
                    isVisible: $showDepthOverlay
                )
                .opacity(Double(depthOpacity))
                .allowsHitTesting(false)
            }

            // Controls
            VStack {
                HStack {
                    // Depth toggle
                    Button(action: { toggleDepthOverlay() }) {
                        Image(systemName: showDepthOverlay ? "eye" : "eye.slash")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(showDepthOverlay ? "Hide depth" : "Show depth")

                    Spacer()
                }
                .padding()

                Spacer()

                // Capture button
                CaptureButton(action: viewModel.capture)
                    .padding(.bottom, 40)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private func toggleDepthOverlay() {
        showDepthOverlay.toggle()
        UserDefaults.standard.set(showDepthOverlay, forKey: "showDepthOverlay")
    }
}
```

### Task 8: Add Depth Frame Publisher to CaptureViewModel (AC6)
- [ ] Update `ios/Rial/Features/Capture/CaptureViewModel.swift`
- [ ] Add @Published var currentDepthFrame: DepthFrame?
- [ ] Subscribe to ARSession frame updates
- [ ] Convert ARFrame.sceneDepth to DepthFrame
- [ ] Publish on main thread for SwiftUI
- [ ] Throttle updates to 60fps max
- [ ] Handle nil sceneDepth gracefully
- [ ] Test frame update performance

**ViewModel Depth Frame Publishing:**
```swift
class CaptureViewModel: ObservableObject {
    @Published var currentDepthFrame: DepthFrame?

    private let captureSession = ARCaptureSession()

    func start() {
        captureSession.onFrameUpdate = { [weak self] arFrame in
            guard let sceneDepth = arFrame.sceneDepth else { return }

            let depthFrame = DepthFrame(from: arFrame)

            DispatchQueue.main.async {
                self?.currentDepthFrame = depthFrame
            }
        }

        try? captureSession.start()
    }
}
```

### Task 9: Performance Optimization (AC3)
- [ ] Profile with Xcode FPS gauge to verify 60fps
- [ ] Profile with Metal debugger for GPU time
- [ ] Implement texture cache for reusing Metal textures
- [ ] Minimize CPU-GPU synchronization points
- [ ] Use autoreleasepool for temporary Metal objects
- [ ] Test on iPhone 12 Pro (oldest target device)
- [ ] Verify thermal throttling recovery
- [ ] Document performance characteristics

### Task 10: Portrait/Landscape Handling (AC7)
- [ ] Update vertex shader for orientation transforms
- [ ] Handle device orientation changes in Coordinator
- [ ] Test rotation transitions for visual glitches
- [ ] Verify aspect ratio preservation
- [ ] Test all orientations: portrait, landscape left/right
- [ ] Ensure 60fps during rotation
- [ ] Document orientation behavior

### Task 11: Error Handling (AC8)
- [ ] Create VisualizationError enum with all cases
- [ ] Implement LocalizedError for user messages
- [ ] Add logging for all error scenarios
- [ ] Test Metal unavailable scenario (if possible)
- [ ] Test shader compilation failure (intentional error)
- [ ] Test texture creation failure (invalid buffer)
- [ ] Implement graceful degradation for each error type
- [ ] Document error recovery behavior

**Error Types:**
```swift
enum VisualizationError: Error, LocalizedError {
    case metalNotAvailable
    case shaderCompilationFailed
    case depthTextureCreationFailed
    case renderEncodingFailed
    case commandQueueCreationFailed

    var errorDescription: String? {
        switch self {
        case .metalNotAvailable:
            return "Metal graphics not available on this device"
        case .shaderCompilationFailed:
            return "Failed to compile depth visualization shader"
        case .depthTextureCreationFailed:
            return "Failed to create depth texture from LiDAR data"
        case .renderEncodingFailed:
            return "Failed to encode rendering commands"
        case .commandQueueCreationFailed:
            return "Failed to create Metal command queue"
        }
    }
}
```

### Task 12: Unit and Integration Tests (AC1-AC8)
- [ ] Create `ios/RialTests/Capture/DepthVisualizerTests.swift`
- [ ] Test Metal device initialization
- [ ] Test shader compilation and pipeline creation
- [ ] Test depth texture creation with mock CVPixelBuffer
- [ ] Test parameter buffer setup
- [ ] Test error handling paths
- [ ] Create `ios/RialUITests/DepthOverlayTests.swift` for UI testing
- [ ] Test toggle button functionality
- [ ] Test opacity adjustment (if exposed in UI)
- [ ] Test orientation changes
- [ ] Achieve 80%+ code coverage (where testable)

**Note**: Full Metal rendering tests require physical device. Unit tests can verify pipeline setup and error handling logic.

---

## Technical Implementation Details

### Metal Shader Pipeline Architecture

```
ARFrame.sceneDepth (CVPixelBuffer Float32)
    |
    v
CVPixelBuffer → MTLTexture (r32Float)
    |
    v
Vertex Shader (Full-Screen Quad)
    |
    v
Fragment Shader (Depth → Color Mapping)
    |
    v
Render Pass (Blend with Camera Preview)
    |
    v
MTKView Drawable (Display)
```

### Full-Screen Quad Vertices

```swift
// Vertex positions for full-screen quad (2 triangles)
let vertices: [SIMD2<Float>] = [
    SIMD2(-1.0, -1.0),  // Bottom-left
    SIMD2( 1.0, -1.0),  // Bottom-right
    SIMD2(-1.0,  1.0),  // Top-left
    SIMD2(-1.0,  1.0),  // Top-left
    SIMD2( 1.0, -1.0),  // Bottom-right
    SIMD2( 1.0,  1.0)   // Top-right
]
```

### Depth Normalization Formula

```swift
// Normalize depth from meters to 0-1 range
normalized = (depth - nearPlane) / (farPlane - nearPlane)
normalized = clamp(normalized, 0.0, 1.0)  // saturate in Metal
```

### Color Interpolation

```swift
// Linear interpolation between near (red) and far (blue) colors
color = nearColor * (1.0 - normalized) + farColor * normalized
// Metal: color = mix(nearColor, farColor, normalized)
```

### Performance Measurement Approach

**FPS Monitoring:**
- Use Xcode Debug Navigator → FPS gauge
- Look for sustained 60fps (green line)
- Monitor for dropped frames (red spikes)

**GPU Profiling:**
- Metal debugger: Capture GPU frame
- Check fragment shader time < 1ms
- Verify texture upload time < 1ms
- Total GPU time < 2ms per frame

**Memory Profiling:**
- Instruments → Allocations tool
- Monitor MTLTexture allocations
- Verify textures released after use
- Check for memory growth over time

---

## Dependencies

### Prerequisites
- **Story 6.5**: ARKit Unified Capture Session (provides ARFrame with sceneDepth)
- **Story 6.1**: Initialize Native iOS Project (provides Xcode project structure)

### Blocks
- **Story 6.13**: SwiftUI Capture Screen (integrates DepthOverlayView in CaptureView)

### External Dependencies
- **Metal.framework**: GPU rendering pipeline
- **MetalKit.framework**: MTKView for display
- **ARKit.framework**: ARFrame and sceneDepth access
- **CoreVideo.framework**: CVPixelBuffer handling
- **SwiftUI.framework**: UIViewRepresentable integration

---

## Testing Strategy

### Unit Tests (Limited Simulator Support)
Depth visualization can be partially tested in simulator:
- DepthVisualizer initialization
- Error handling logic
- Parameter setup (nearPlane, farPlane, opacity)
- DepthFrame model creation

**Cannot test in simulator:**
- Actual Metal rendering (no GPU)
- Shader compilation (no Metal device)
- Performance measurements
- Real depth texture creation

### Physical Device Testing (Required)
Full testing requires iPhone Pro with LiDAR:
- End-to-end rendering with real depth data
- 60fps performance verification
- GPU time profiling with Metal debugger
- Texture creation from real CVPixelBuffer
- Toggle and opacity adjustment
- Orientation changes
- Visual quality validation

### Integration Testing
- Story 6.5: ARCaptureSession provides valid depth data
- Story 6.13: CaptureView displays overlay correctly
- Toggle persists across app restarts
- Overlay works alongside other UI elements

### Performance Testing
Measure with Instruments and Metal debugger on iPhone 12 Pro:
- Frame rate: 60fps sustained (> 57fps for 95% of frames)
- GPU time: < 2ms per frame
- CPU overhead: < 5%
- Memory usage: No leaks, stable over time
- Texture upload: < 1ms
- Shader execution: < 1ms

---

## Definition of Done

- [ ] All acceptance criteria verified and passing
- [ ] All tasks completed
- [ ] DepthVisualization.metal shader implemented and compiling
- [ ] DepthVisualizer.swift implemented and documented
- [ ] DepthOverlayView.swift SwiftUI wrapper implemented
- [ ] DepthFrame model defined in CaptureData.swift
- [ ] Integration with CaptureView completed
- [ ] Unit tests achieve 80%+ coverage (where testable)
- [ ] Physical device testing confirms:
  - [ ] 60fps rendering sustained
  - [ ] GPU time < 2ms per frame
  - [ ] Toggle works instantly
  - [ ] Opacity adjustment smooth
  - [ ] No visual glitches in all orientations
  - [ ] No memory leaks (Instruments)
- [ ] Integration with Story 6.5 (ARCaptureSession) tested
- [ ] Visual quality validated (clear color gradient, accurate depth)
- [ ] Error handling tested and graceful
- [ ] Performance benchmarks documented
- [ ] Code reviewed and approved
- [ ] Documentation updated
- [ ] Code committed to feature branch

---

## FR Coverage

| Functional Requirement | Implementation |
|----------------------|----------------|
| **FR6**: Camera view with depth overlay | Metal shader renders depth as color gradient overlay on ARKit camera preview |

---

## References

### Source Documents
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#Story-6.7-Metal-Depth-Visualization]
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#Data-Models]
- [User Request: Create story for 6-7-metal-depth-visualization]

### Apple Documentation
- [Metal Shading Language](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
- [MTKView](https://developer.apple.com/documentation/metalkit/mtkview)
- [MTLRenderPipelineState](https://developer.apple.com/documentation/metal/mtlrenderpipelinestate)
- [ARFrame.sceneDepth](https://developer.apple.com/documentation/arkit/arframe/3566299-scenedepth)
- [UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable)

### Metal Resources
- [Metal Best Practices Guide](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/index.html)
- [Metal Programming Guide](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Introduction/Introduction.html)

---

## Notes

### Important Implementation Considerations

1. **Metal vs Core Image**
   - Metal chosen for maximum performance (60fps guarantee)
   - Core Image CIFilter alternative would be simpler but slower
   - Metal provides < 2ms GPU time, Core Image typically 5-10ms
   - Direct shader control allows custom color mapping

2. **Depth Range Configuration**
   - nearPlane: 0.5m (LiDAR minimum range)
   - farPlane: 5.0m (typical indoor/outdoor maximum)
   - Values configurable for different use cases
   - Backend receives full Float32 depth (not normalized)

3. **Color Gradient Rationale**
   - Red (near) → Blue (far) intuitive for depth perception
   - Alternative: Rainbow gradient (more colorful but less intuitive)
   - Grayscale considered but less visually distinct
   - Color gradient helps identify depth issues quickly

4. **Performance Optimization**
   - Metal texture cache reuses textures across frames
   - Command buffer reuse reduces allocation overhead
   - Full-screen quad minimizes vertex processing
   - Fragment shader optimized for linear texture sampling

5. **Blending Configuration**
   - Source alpha blending allows adjustable opacity
   - RGB preview visible beneath depth overlay
   - Opacity 0.4 (40%) provides good balance
   - Users can disable overlay entirely for clear RGB view

### React Native Migration

This Metal implementation replaces:
- Custom React Native depth visualization module
- JavaScript-based color mapping
- Bridge crossings for depth data
- Less efficient rendering approaches

The native implementation provides:
- **Better performance**: 60fps guaranteed vs 30-45fps in RN
- **Better quality**: GPU-native rendering, no bridge overhead
- **Better control**: Direct shader programming
- **Simpler code**: No bridge layer, direct ARKit → Metal pipeline

### Common Visualization Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Low frame rate (< 60fps) | GPU overload or synchronization | Profile with Metal debugger, optimize shader |
| Depth appears inverted | Texture Y-coordinate not flipped | Fix texCoord in vertex shader |
| Flickering | Multiple render passes interfering | Ensure single render pass per frame |
| Stretched appearance | Aspect ratio mismatch | Match MTKView size to depth texture dimensions |
| Missing depth data | ARFrame.sceneDepth is nil | Verify LiDAR availability, handle nil gracefully |

### Visual Quality Validation

Test depth visualization with these scenarios:
- **Close objects (0.5-1m)**: Should appear red
- **Medium distance (2-3m)**: Should appear yellow/green
- **Far objects (4-5m)**: Should appear blue
- **Smooth surfaces**: Gradient should be continuous
- **Edges**: Depth discontinuities should be visible
- **Gaps**: Missing depth should be transparent

### Testing Notes

**Simulator Limitations:**
- Cannot run Metal shaders (no GPU device)
- Cannot test ARKit depth data
- Cannot measure performance
- Useful only for SwiftUI view structure testing

**Physical Device Requirements:**
- iPhone Pro (12 Pro or later) with LiDAR
- iOS 15.0 or later
- Camera permissions granted
- Good lighting for optimal LiDAR performance

---

## Dev Agent Record

### Context Reference

Story Context XML: `docs/sprint-artifacts/story-contexts/6-7-metal-depth-visualization-context.xml`

### Agent Model Used

Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Implementation Notes

_To be filled during implementation_

### Completion Notes

_To be filled when story is complete_

### File List

**Created:**
- `ios/Rial/Shaders/DepthVisualization.metal` - Metal shader with vertex and fragment functions for depth colormap
- `ios/Rial/Core/Capture/DepthVisualizer.swift` - Metal rendering pipeline manager for depth visualization
- `ios/Rial/Features/Capture/DepthOverlayView.swift` - SwiftUI UIViewRepresentable wrapper for MTKView
- `ios/RialTests/Capture/DepthVisualizerTests.swift` - Unit tests for DepthVisualizer
- `ios/RialUITests/DepthOverlayTests.swift` - UI tests for depth overlay integration

**Modified:**
- `ios/Rial/Models/CaptureData.swift` - Added DepthFrame struct for depth data representation
- `ios/Rial/Features/Capture/CaptureView.swift` - Integrated DepthOverlayView with toggle button
- `ios/Rial/Features/Capture/CaptureViewModel.swift` - Added currentDepthFrame publisher
- `ios/Rial.xcodeproj/project.pbxproj` - Added Metal shader file to build phases

### Code Review Result

_To be filled after code review_
