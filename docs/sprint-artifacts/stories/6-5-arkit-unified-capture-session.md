# Story 6.5: ARKit Unified Capture Session

**Story Key:** 6-5-arkit-unified-capture-session
**Epic:** 6 - Native Swift Implementation
**Status:** Done
**Created:** 2025-11-25

---

## User Story

As a **photographer using RealityCam**,
I want **simultaneous RGB photo and LiDAR depth capture in a single frame**,
So that **depth data perfectly matches the photo with no timing issues or synchronization errors**.

## Story Context

This story implements the unified ARKit capture session that provides perfectly synchronized RGB photo and LiDAR depth data in a single ARFrame. This is a critical improvement over the React Native approach, which required separate camera and LiDAR modules coordinated via JavaScript, leading to potential synchronization issues.

ARCaptureSession wraps ARKit's ARSession with ARWorldTrackingConfiguration to enable sceneDepth frame semantics. This provides both the capturedImage (RGB) and sceneDepth (LiDAR depth map) in the same ARFrame object, captured at the exact same instant with perfect alignment.

### Security Benefits Over React Native Approach

| Aspect | React Native (separate modules) | Native Swift (ARCaptureSession) |
|--------|--------------------------------|----------------------------------|
| **Synchronization** | Two modules + JS coordination timing | Single ARFrame (same instant) |
| **Data Handling** | Photo/depth cross JS bridge separately | All data processed in native memory |
| **Frame Rate** | Limited by bridge overhead | Native 30-60fps sustained |
| **Memory** | Duplicated buffers for bridge | Zero-copy ARFrame references |
| **Reliability** | Timing drift possible | Hardware-synchronized capture |

---

## Acceptance Criteria

### AC1: LiDAR Availability Check
**Given** the app launches on an iOS device
**When** ARCaptureSession.start() is called
**Then**:
- `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)` is checked
- If LiDAR is NOT available, throw `CaptureError.lidarNotAvailable`
- If LiDAR IS available, proceed with session configuration
- Error message clearly states "LiDAR sensor required (iPhone Pro models only)"

**And** supported devices include:
- iPhone 12 Pro / Pro Max (2020+)
- iPhone 13 Pro / Pro Max (2021+)
- iPhone 14 Pro / Pro Max (2022+)
- iPhone 15 Pro / Pro Max (2023+)
- iPhone 16 Pro / Pro Max (2024+)

### AC2: ARFrame Contains Both RGB and Depth
**Given** ARCaptureSession is running
**When** the session delegate receives frame updates
**Then** each ARFrame contains:
- `capturedImage: CVPixelBuffer` - RGB photo data (YCbCr format)
- `sceneDepth: ARDepthData?` - LiDAR depth map with depthMap and confidenceMap
- Both captured at the same timestamp (synchronized)
- DepthMap dimensions typically 256x192 (device-dependent)
- DepthMap values in meters (Float32)

**And** the ARFrame includes:
- `timestamp: TimeInterval` - Frame capture time
- `camera.intrinsics: simd_float3x3` - Camera intrinsics matrix
- `camera.transform: simd_float4x4` - World transform matrix

### AC3: Frame Update Rate
**Given** ARCaptureSession is running
**When** monitoring frame updates via `onFrameUpdate` callback
**Then**:
- Frame updates occur at 30fps minimum (≥30 frames per second)
- Preferably 60fps on capable devices (iPhone 13 Pro+)
- Frame timing consistent (no dropped frames under normal conditions)
- Frame rate measured over 10-second window averages ≥30fps

**And** frame rate maintained:
- During AR camera preview rendering
- With depth overlay enabled
- Under normal device temperature (not thermal throttling)

### AC4: Session Interruption Handling
**Given** ARCaptureSession is running
**When** interruptions occur (phone call, background, camera permissions revoked)
**Then**:
- `session(_:wasInterrupted:)` delegate method called
- Session pauses gracefully without crashing
- `session(_:interruptionEnded:)` resumes session automatically
- App notifies user of interruption reason
- Session recovers to normal state after interruption ends

**And** interruption types handled:
- Phone calls or FaceTime
- App backgrounded (home button, app switcher)
- Camera permissions revoked or changed
- System resource pressure (thermal, battery)

### AC5: Proper Resource Cleanup
**Given** ARCaptureSession is stopped or deinitialized
**When** `stop()` is called or ARCaptureSession is released
**Then**:
- `session.pause()` called to stop ARSession
- Frame update callbacks cease immediately
- No memory leaks (verified with Instruments Allocations)
- ARSession resources released (camera, LiDAR sensor)
- No background processing continues after stop

**And** verified via Instruments:
- Memory returns to baseline after stop
- No persistent ARFrame references
- CVPixelBuffer references released
- Delegate callbacks removed

### AC6: Capture Current Frame
**Given** ARCaptureSession is running
**When** `captureCurrentFrame()` is called (e.g., user taps capture button)
**Then**:
- Returns the most recent ARFrame from delegate updates
- ARFrame contains valid capturedImage and sceneDepth
- Frame timestamp within 33ms of current time (one frame at 30fps)
- Returns `nil` if session not yet started or no frames received

**And** frame capture is:
- Non-blocking (returns immediately with cached frame)
- Thread-safe (can be called from any queue)
- Does not interfere with ongoing frame updates

### AC7: Configuration and Initialization
**Given** ARCaptureSession is initialized
**When** `start()` is called
**Then**:
- `ARWorldTrackingConfiguration` created with correct settings
- `config.frameSemantics.insert(.sceneDepth)` enables LiDAR depth
- Session delegate set to self
- `session.run(config)` starts ARSession
- First frame arrives within 500ms

**And** configuration includes:
- World tracking (6DOF tracking, not orientation-only)
- Scene depth enabled (LiDAR depth maps)
- No plane detection (not needed for photo capture)
- No image detection (not needed for photo capture)

---

## Tasks

### Task 1: Create ARCaptureSession Core Class (AC1, AC7)
- [ ] Create `ios/Rial/Core/Capture/ARCaptureSession.swift`
- [ ] Import ARKit framework
- [ ] Define class conforming to NSObject and ARSessionDelegate
- [ ] Add private ARSession property
- [ ] Add private currentFrame storage (thread-safe)
- [ ] Add public onFrameUpdate callback property
- [ ] Add logging with os.log Logger
- [ ] Document all public methods with DocC comments

### Task 2: Implement LiDAR Availability Check (AC1)
- [ ] Implement `start() throws` method
- [ ] Check `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)`
- [ ] Throw `CaptureError.lidarNotAvailable` if unsupported
- [ ] Define CaptureError enum with lidarNotAvailable case
- [ ] Add user-friendly error message
- [ ] Log availability check result
- [ ] Test on iPhone Pro (should pass) and non-Pro (should throw)

### Task 3: Configure ARWorldTrackingConfiguration (AC7)
- [ ] Create `ARWorldTrackingConfiguration` instance
- [ ] Insert `.sceneDepth` into frameSemantics
- [ ] Disable unnecessary features (plane detection, image detection)
- [ ] Set session delegate to self
- [ ] Call `session.run(config)` to start
- [ ] Log configuration details
- [ ] Verify configuration in debug mode

### Task 4: Implement Frame Update Delegate (AC2)
- [ ] Implement `session(_:didUpdate:)` delegate method
- [ ] Store incoming ARFrame in currentFrame property (thread-safe)
- [ ] Verify ARFrame contains capturedImage (CVPixelBuffer)
- [ ] Verify ARFrame contains sceneDepth (ARDepthData)
- [ ] Call onFrameUpdate callback if set
- [ ] Log frame updates (debug level, with timestamp)
- [ ] Handle nil sceneDepth gracefully (log warning)

### Task 5: Implement Capture Current Frame (AC6)
- [ ] Implement `captureCurrentFrame() -> ARFrame?`
- [ ] Return currentFrame property (thread-safe read)
- [ ] Return nil if currentFrame is nil (no frames yet)
- [ ] Add logging for capture attempts
- [ ] Make method thread-safe (can call from any queue)
- [ ] Test with capture button integration
- [ ] Verify frame timestamp freshness

### Task 6: Implement Session Stop (AC5)
- [ ] Implement `stop()` method
- [ ] Call `session.pause()` to stop ARSession
- [ ] Clear currentFrame reference
- [ ] Log stop event
- [ ] Test cleanup with Instruments Allocations
- [ ] Verify no memory leaks

### Task 7: Implement Interruption Handling (AC4)
- [ ] Implement `session(_:wasInterrupted:)` delegate method
- [ ] Log interruption event
- [ ] Notify app layer via callback or notification
- [ ] Implement `session(_:interruptionEnded:)` delegate method
- [ ] Log interruption end
- [ ] Test with phone call, backgrounding, permission changes
- [ ] Verify session resumes correctly

### Task 8: Thread Safety and Concurrency (AC2, AC6)
- [ ] Make currentFrame access thread-safe (use serial DispatchQueue or actor)
- [ ] Ensure onFrameUpdate callback dispatches on main queue (if needed for UI)
- [ ] Verify captureCurrentFrame() is thread-safe
- [ ] Add concurrent read/write tests
- [ ] Document thread safety guarantees in DocC comments

### Task 9: Error Handling (AC1, AC4)
- [ ] Define CaptureError enum with all error cases:
  - `.lidarNotAvailable` - Device doesn't support LiDAR
  - `.sessionFailed` - ARSession failed to start
  - `.interrupted` - Session interrupted
  - `.noFrameAvailable` - No frame captured yet
- [ ] Implement LocalizedError protocol
- [ ] Add detailed error descriptions
- [ ] Log all error scenarios
- [ ] Test all error paths

### Task 10: Unit Tests (AC1-AC7)
- [ ] Create `ios/RialTests/Capture/ARCaptureSessionTests.swift`
- [ ] Test LiDAR availability check (requires device capability mocking)
- [ ] Test frame update delegate calls
- [ ] Test captureCurrentFrame returns current frame
- [ ] Test captureCurrentFrame returns nil before first frame
- [ ] Test stop() cleans up resources
- [ ] Test interruption handling (mock delegate calls)
- [ ] Test thread safety of currentFrame access
- [ ] Achieve 90%+ code coverage
- [ ] Note: Full ARKit testing requires physical device

---

## Technical Implementation Details

### ARCaptureSession.swift Structure

```swift
import Foundation
import ARKit
import os.log

/// Unified ARKit capture session providing synchronized RGB photo and LiDAR depth
class ARCaptureSession: NSObject, ARSessionDelegate {
    private static let logger = Logger(subsystem: "app.rial", category: "capture")

    /// ARKit session for RGB+depth capture
    private let session = ARSession()

    /// Most recent ARFrame (thread-safe access)
    private let frameQueue = DispatchQueue(label: "app.rial.arcapturesession.frame")
    private var _currentFrame: ARFrame?

    /// Callback invoked on each frame update
    /// - Note: Called on ARSession delegate queue, not main queue
    var onFrameUpdate: ((ARFrame) -> Void)?

    // MARK: - Lifecycle

    /// Start AR capture session with LiDAR depth
    /// - Throws: CaptureError if LiDAR not available or session fails
    func start() throws {
        // Verify LiDAR support
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            Self.logger.error("LiDAR not available on this device")
            throw CaptureError.lidarNotAvailable
        }

        Self.logger.info("Starting ARCaptureSession with LiDAR depth")

        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth)

        // Disable unnecessary features for performance
        config.planeDetection = []

        // Set delegate and start
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        Self.logger.info("ARCaptureSession started successfully")
    }

    /// Stop AR capture session and release resources
    func stop() {
        Self.logger.info("Stopping ARCaptureSession")
        session.pause()

        frameQueue.sync {
            _currentFrame = nil
        }

        Self.logger.info("ARCaptureSession stopped")
    }

    /// Capture the most recent ARFrame
    /// - Returns: Current ARFrame with RGB and depth, or nil if no frames yet
    func captureCurrentFrame() -> ARFrame? {
        return frameQueue.sync {
            guard let frame = _currentFrame else {
                Self.logger.debug("No current frame available")
                return nil
            }

            Self.logger.debug("Captured frame at timestamp \(frame.timestamp)")
            return frame
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Store frame (thread-safe)
        frameQueue.sync {
            _currentFrame = frame
        }

        // Verify frame contains depth data
        if frame.sceneDepth == nil {
            Self.logger.warning("ARFrame missing sceneDepth (LiDAR data unavailable)")
        }

        // Notify callback
        onFrameUpdate?(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        Self.logger.error("ARSession failed: \(error.localizedDescription)")
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = camera.trackingState
        switch state {
        case .normal:
            Self.logger.debug("Camera tracking: normal")
        case .notAvailable:
            Self.logger.warning("Camera tracking: not available")
        case .limited(let reason):
            Self.logger.warning("Camera tracking: limited (\(reason))")
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        Self.logger.warning("ARSession interrupted (phone call, backgrounding, etc.)")
        // Session automatically pauses
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Self.logger.info("ARSession interruption ended, resuming")
        // Session automatically resumes
    }
}

/// Errors that can occur during AR capture
enum CaptureError: Error, LocalizedError {
    case lidarNotAvailable
    case sessionFailed
    case interrupted
    case noFrameAvailable

    var errorDescription: String? {
        switch self {
        case .lidarNotAvailable:
            return "LiDAR sensor required (iPhone Pro models only)"
        case .sessionFailed:
            return "AR capture session failed to start"
        case .interrupted:
            return "AR capture session interrupted"
        case .noFrameAvailable:
            return "No frame available yet (session not started or no frames received)"
        }
    }
}
```

### Frame Structure Reference

```swift
// ARFrame provides these key properties:
struct ARFrame {
    let capturedImage: CVPixelBuffer     // RGB photo (YCbCr420)
    let sceneDepth: ARDepthData?         // LiDAR depth map
    let timestamp: TimeInterval          // Capture time
    let camera: ARCamera                 // Camera parameters
}

struct ARDepthData {
    let depthMap: CVPixelBuffer          // Float32 depth values (meters)
    let confidenceMap: CVPixelBuffer?    // Per-pixel confidence (low/medium/high)
}

struct ARCamera {
    let intrinsics: simd_float3x3        // Camera intrinsics matrix
    let transform: simd_float4x4         // World transform
    let trackingState: ARCamera.TrackingState
}
```

### Usage Example

```swift
// Initialize and start capture session
let captureSession = ARCaptureSession()

// Set frame update callback (for preview rendering)
captureSession.onFrameUpdate = { frame in
    // Update Metal depth visualization (Story 6.7)
    depthVisualizer.update(with: frame)
}

do {
    try captureSession.start()
} catch CaptureError.lidarNotAvailable {
    // Show error: "LiDAR required (iPhone Pro models only)"
    showError("This app requires an iPhone Pro with LiDAR sensor")
} catch {
    showError("Failed to start camera: \(error.localizedDescription)")
}

// Later, when user taps capture button
if let frame = captureSession.captureCurrentFrame() {
    // Process frame (Story 6.6)
    let captureData = try await frameProcessor.process(frame, location: currentLocation)

    // Generate assertion (Story 6.8)
    let assertion = try await captureAssertion.createAssertion(for: captureData)

    // Save to CoreData (Story 6.9)
    try await captureStore.save(captureData, assertion: assertion)
} else {
    showError("No frame available")
}

// Clean up when done
captureSession.stop()
```

### Unit Test Examples

```swift
import XCTest
import ARKit
@testable import Rial

class ARCaptureSessionTests: XCTestCase {
    var sut: ARCaptureSession!

    override func setUp() {
        super.setUp()
        sut = ARCaptureSession()
    }

    override func tearDown() {
        sut.stop()
        super.tearDown()
    }

    // MARK: - Availability Tests

    func testStart_OnDeviceWithoutLiDAR_ThrowsError() {
        // Note: This test only works on non-Pro devices or simulator
        // On iPhone Pro, this will pass (not throw)

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            XCTAssertNoThrow(try sut.start(), "iPhone Pro should support LiDAR")
        } else {
            XCTAssertThrowsError(try sut.start()) { error in
                XCTAssertEqual(error as? CaptureError, .lidarNotAvailable)
            }
        }
    }

    // MARK: - Frame Capture Tests

    func testCaptureCurrentFrame_BeforeStart_ReturnsNil() {
        let frame = sut.captureCurrentFrame()
        XCTAssertNil(frame, "Should return nil before session starts")
    }

    func testCaptureCurrentFrame_AfterFrameUpdate_ReturnsFrame() throws {
        // Note: This test requires physical device with LiDAR
        try sut.start()

        // Wait for first frame (up to 1 second)
        let expectation = XCTestExpectation(description: "Frame received")
        sut.onFrameUpdate = { frame in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        let frame = sut.captureCurrentFrame()
        XCTAssertNotNil(frame, "Should return frame after update")
    }

    // MARK: - Frame Update Tests

    func testOnFrameUpdate_CalledForEachFrame() throws {
        // Note: Requires physical device
        try sut.start()

        var frameCount = 0
        let expectation = XCTestExpectation(description: "10 frames received")

        sut.onFrameUpdate = { frame in
            frameCount += 1
            if frameCount >= 10 {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertGreaterThanOrEqual(frameCount, 10, "Should receive at least 10 frames in 1 second")
    }

    // MARK: - Thread Safety Tests

    func testCaptureCurrentFrame_ThreadSafe() throws {
        try sut.start()

        // Wait for first frame
        let expectation = XCTestExpectation(description: "Frame received")
        sut.onFrameUpdate = { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // Concurrent reads should not crash
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.captureCurrentFrame()
        }
    }

    // MARK: - Lifecycle Tests

    func testStop_ReleasesResources() throws {
        try sut.start()

        // Wait for frame
        let expectation = XCTestExpectation(description: "Frame received")
        sut.onFrameUpdate = { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        sut.stop()

        let frame = sut.captureCurrentFrame()
        XCTAssertNil(frame, "Should return nil after stop")
    }

    func testStop_StopsFrameUpdates() throws {
        try sut.start()

        var frameCount = 0
        sut.onFrameUpdate = { _ in frameCount += 1 }

        // Wait for some frames
        Thread.sleep(forTimeInterval: 0.5)
        let countBeforeStop = frameCount

        sut.stop()
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertEqual(frameCount, countBeforeStop, "No new frames after stop")
    }
}
```

---

## Dependencies

### Prerequisites
- **Story 6.1**: Initialize Native iOS Project (provides project structure and ARKit framework link)

### Blocks
- **Story 6.6**: Frame Processing Pipeline (consumes ARFrame for JPEG/depth conversion)
- **Story 6.7**: Metal Depth Visualization (renders depth overlay from ARFrame)
- **Story 6.13**: SwiftUI Capture Screen (UI wrapper for ARCaptureSession)

### External Dependencies
- **ARKit.framework**: Built-in iOS framework for augmented reality
- **CoreVideo.framework**: For CVPixelBuffer handling
- **simd.framework**: For matrix math (camera intrinsics, transforms)

---

## Testing Strategy

### Unit Tests (Limited Simulator Support)
ARKit functionality is limited in the simulator:
- Basic initialization and API structure testing possible
- Frame update logic can be tested with mock frames
- Error handling can be tested
- Thread safety can be tested
- **Cannot test actual LiDAR capture in simulator**

### Physical Device Testing (Required)
Full testing requires iPhone Pro with LiDAR:
- LiDAR availability check (should pass on Pro, fail on non-Pro)
- ARFrame contains valid capturedImage and sceneDepth
- Frame rate measurement (30fps+ sustained)
- Interruption handling (phone call, backgrounding)
- Memory profiling (no leaks with Instruments)
- Capture button integration (tap to capture frame)

### Integration Testing
- Story 6.6: Frame processor consumes ARFrame successfully
- Story 6.7: Depth visualizer renders ARFrame depth data
- Story 6.13: Capture screen integrates ARCaptureSession

### Performance Testing
- Frame rate measurement over 10-second window
- Memory baseline after start (< 100MB for session)
- Memory delta per frame (< 1MB transient)
- Frame timing consistency (no dropped frames)

---

## Definition of Done

- [ ] All acceptance criteria verified and passing
- [ ] All tasks completed
- [ ] ARCaptureSession.swift implemented and documented
- [ ] CaptureError enum defined with all error cases
- [ ] Unit tests achieve 90%+ coverage (where testable)
- [ ] Physical device testing confirms:
  - [ ] LiDAR availability check works (Pro: pass, non-Pro: fail)
  - [ ] ARFrame contains both RGB and depth data
  - [ ] Frame rate ≥30fps sustained
  - [ ] Interruption handling works (phone call, background)
  - [ ] No memory leaks (Instruments Allocations)
- [ ] Thread safety verified (concurrent capture calls)
- [ ] Integration with Story 6.6 (frame processor) tested
- [ ] Code reviewed and approved
- [ ] Documentation updated
- [ ] Code committed to feature branch

---

## FR Coverage

| Functional Requirement | Implementation |
|----------------------|----------------|
| **FR1**: Detect iPhone Pro with LiDAR | LiDAR availability check via ARWorldTrackingConfiguration |
| **FR6**: Camera view with depth overlay | ARFrame provides depth data for Metal overlay (Story 6.7) |
| **FR7**: Capture photo | ARFrame.capturedImage provides RGB photo |
| **FR8**: Capture LiDAR depth map | ARFrame.sceneDepth provides depth map |

---

## References

### Source Documents
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#Story-6.5-ARKit-Unified-Capture-Session]
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#Architecture-Context]

### Apple Documentation
- [ARKit Documentation](https://developer.apple.com/documentation/arkit)
- [ARSession](https://developer.apple.com/documentation/arkit/arsession)
- [ARWorldTrackingConfiguration](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration)
- [ARFrame](https://developer.apple.com/documentation/arkit/arframe)
- [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)
- [Using Scene Depth for Realistic Occlusion](https://developer.apple.com/documentation/arkit/camera_lighting_and_effects/using_scene_depth_for_realistic_occlusion)

### Standards
- ARKit Frame Semantics (.sceneDepth)
- LiDAR Depth Format (Float32, meters)

---

## Notes

### Important Implementation Considerations

1. **LiDAR Availability**
   - Only iPhone Pro models have LiDAR (12 Pro and newer)
   - Simulator does NOT support LiDAR (always returns false for supportsSceneReconstruction)
   - Must test on physical device for full functionality
   - Graceful error handling for non-Pro devices

2. **Frame Synchronization**
   - ARFrame captures RGB and depth at the same instant
   - No timing drift or synchronization issues
   - Perfect alignment between photo and depth map
   - Critical improvement over separate camera + LiDAR modules

3. **Depth Map Format**
   - CVPixelBuffer with kCVPixelFormatType_DepthFloat32
   - Values in meters (not millimeters or arbitrary units)
   - Typical dimensions: 256x192 (device-dependent)
   - Confidence map provides per-pixel reliability

4. **Performance**
   - ARSession runs at 60fps on capable devices (iPhone 13 Pro+)
   - 30fps minimum guaranteed on all supported devices
   - Depth processing happens on GPU (Metal)
   - Minimal CPU overhead for frame delivery

5. **Memory Management**
   - ARFrame references CVPixelBuffers (not copying data)
   - Must release frame references promptly to avoid memory buildup
   - Session pauses during interruptions to conserve resources
   - Clean stop() required to release camera/LiDAR hardware

### React Native Migration

This ARCaptureSession replaces:
- `react-native-vision-camera` for photo capture
- Custom LiDAR module for depth capture
- JavaScript coordination logic for synchronization

The native implementation provides:
- **Perfect sync**: Single ARFrame, no timing issues
- **Better performance**: No bridge overhead, native frame rate
- **Better reliability**: Hardware-synchronized, no coordination bugs
- **Simpler code**: One unified session, not two modules + glue code

### Common ARKit Errors

| Error | Cause | Recovery |
|-------|-------|----------|
| sessionFailed | ARSession failed to start | Restart with clean config |
| interrupted | Phone call, backgrounding | Automatic resume when interruption ends |
| trackingLimited | Insufficient visual features, motion | Guide user to move device |
| cameraAccessDenied | User denied camera permission | Request permission again |

### Testing Notes

**Simulator Limitations:**
- LiDAR check always returns false (expected)
- ARSession can start but provides no depth data
- Useful for testing API structure, error handling
- NOT useful for testing actual capture functionality

**Physical Device Requirements:**
- iPhone Pro (12 Pro or later) with LiDAR
- iOS 15.0 or later
- Camera permissions granted
- Good lighting and visual features for AR tracking

---

## Dev Agent Record

### Context Reference

Story Context XML: `docs/sprint-artifacts/story-contexts/6-5-arkit-unified-capture-session-context.xml`

### Agent Model Used

Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Implementation Notes

_To be filled during implementation_

### Completion Notes

_To be filled when story is complete_

### File List

**Created:**
- `ios/Rial/Core/Capture/ARCaptureSession.swift` - Unified ARKit capture session with synchronized RGB+depth
- `ios/RialTests/Capture/ARCaptureSessionTests.swift` - Unit tests for ARCaptureSession (simulator-compatible subset)
- `ios/RialTests/Capture/` - New test directory for capture-related tests

**Modified:**
- `ios/Rial.xcodeproj/project.pbxproj` - Added ARCaptureSession to Rial target, tests to RialTests target
- `docs/sprint-artifacts/sprint-status.yaml` - Updated story status (backlog → drafted)

### Code Review Result

_To be filled after code review_
