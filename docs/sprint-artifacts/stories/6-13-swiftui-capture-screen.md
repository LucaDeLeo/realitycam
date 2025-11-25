# Story 6.13: SwiftUI Capture Screen

**Status:** Done
**Epic:** 6 - Native Swift Implementation
**Sprint:** Current
**Completed:** 2025-11-25

## Story Description
As a mobile user, I want a camera screen with depth visualization and capture controls so that I can take authenticated photos with LiDAR depth data.

## Acceptance Criteria

### AC1: AR Camera Preview
- [x] Full-screen ARKit camera preview
- [x] Continuous LiDAR depth capture
- [x] Smooth frame rate (30fps minimum)

### AC2: Depth Overlay
- [x] Toggleable depth visualization overlay
- [x] Colorized depth representation
- [x] SF Symbol toggle button (eye/eye.slash)
- [x] Adjustable opacity (40%)

### AC3: Capture Controls
- [x] Large capture button with haptic feedback
- [x] Capture state feedback (processing indicator)
- [x] Depth toggle on left side
- [x] Balanced layout with proper spacing

### AC4: Capture Flow
- [x] Capture triggers frame + depth extraction
- [x] Processing indicator during assertion
- [x] Success/failure feedback
- [x] Auto-queue for upload

### AC5: Permission Handling
- [x] Camera permission request on first use
- [x] Clear messaging for permission denied state
- [x] Settings link for permission recovery

## Technical Notes

### Files Created
- `ios/Rial/Features/Capture/CaptureView.swift` - Main SwiftUI view
- `ios/Rial/Features/Capture/CaptureViewModel.swift` - View model with capture logic
- `ios/Rial/Features/Capture/CaptureButton.swift` - Styled capture button
- `ios/Rial/Features/Capture/ARViewContainer.swift` - UIViewRepresentable for ARKit

### SwiftUI + ARKit Integration
```swift
struct ARViewContainer: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView
    func updateUIView(_ uiView: ARSCNView, context: Context)
}
```

### Implementation Details
- `CaptureView`: Main SwiftUI view with ZStack layout for camera preview, depth overlay, and controls
- `CaptureViewModel`: @MainActor view model managing AR session lifecycle, frame updates, and capture flow
- `CaptureButton`: Large capture button (72pt) with UIImpactFeedbackGenerator haptic feedback
- `ARViewContainer`: UIViewRepresentable wrapping ARSCNView for camera feed display
- `CaptureControlsBar`: Bottom bar with depth toggle, capture button, and history access
- `SheetPresentationModifier`: iOS 15/16+ compatible sheet presentation

### iOS Version Compatibility
- Minimum: iOS 15.0
- Sheet presentation modifiers conditionally available on iOS 16+
- Uses `.font(.title3.bold())` instead of `.fontWeight(.semibold)` for iOS 15 compatibility

## Dependencies
- Story 6.5: ARCaptureSession (completed)
- Story 6.6: FrameProcessor (completed)
- Story 6.7: DepthVisualizer (completed)

## Definition of Done
- [x] CaptureView displays AR camera preview
- [x] Depth overlay toggleable with SF Symbol
- [x] Capture button triggers photo capture
- [x] Haptic feedback on capture
- [x] Preview shows with confirmation
- [x] Build succeeds
- [x] All existing tests pass

## Estimation
- Points: 5
- Complexity: Medium (SwiftUI + ARKit integration)
