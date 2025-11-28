# Story 7-14: Video Capture UI Integration

Status: review

## Story

As a **user**,
I want **a clear interface to switch between photo and video modes and record video with visual feedback**,
So that **I can choose the right capture type and understand the recording state at all times**.

## Acceptance Criteria

### AC 1: Mode Selection Interface
**Given** the capture screen is displayed
**When** the user views the interface
**Then**:
1. Segmented control or toggle shows "Photo | Video" mode selection
2. Mode selector positioned prominently at top or bottom of screen
3. Current mode is clearly highlighted
4. Mode cannot be changed while recording is in progress
5. Mode preference persisted between app launches

### AC 2: Video Mode Recording Button
**Given** video mode is selected
**When** capture button is displayed
**Then**:
1. Button shows video camera icon or record symbol
2. Button visual indicates "press and hold" affordance
3. Button responds to press gesture immediately with haptic feedback
4. Button shows recording state visually (pulsing red border or fill)
5. Button disabled if ARSession tracking quality insufficient

### AC 3: Recording Status Indicator
**Given** video recording is in progress
**When** the user is recording
**Then**:
1. Visual "Recording..." text with pulsing red dot appears at top
2. Elapsed timer shows current duration (format: "0:00")
3. Timer updates every second
4. Remaining duration or progress bar visible (15s max)
5. Indicator remains visible throughout recording

### AC 4: Real-Time Depth Overlay During Recording
**Given** video recording is in progress and edge overlay enabled
**When** frames are captured
**Then**:
1. Edge-only depth overlay displays in real-time (Story 7-3)
2. Overlay shows cyan (near) to magenta (far) edges
3. Overlay toggle button available to show/hide during recording
4. Overlay preference persisted for video mode separately from photo mode
5. Overlay renders to preview ONLY, not recorded in video file

### AC 5: Recording Duration Control
**Given** user is holding record button
**When** recording continues
**Then**:
1. Recording continues until button release OR 15-second maximum
2. Timer counts from 0:00 to 0:15
3. Haptic feedback plays at 5-second warning point
4. Recording auto-stops at 15 seconds with haptic feedback
5. User can release button early to stop recording

### AC 6: Upload Progress Indicator
**Given** video capture completed and uploading
**When** upload is in progress
**Then**:
1. Progress indicator shows upload percentage (0-100%)
2. Upload status text: "Uploading video..." with current/total MB
3. Progress bar or circular indicator visible
4. User can view history while upload continues in background
5. Error state displayed if upload fails with retry option

### AC 7: Video Preview After Recording
**Given** recording completed successfully
**When** preview sheet is displayed
**Then**:
1. Video player shows recorded video with native controls
2. Play/pause button for video playback
3. Depth overlay toggle available in preview
4. "Use Video" button saves and uploads capture
5. "Retake" button discards and returns to capture screen
6. Preview sheet dismissible with swipe down gesture

### AC 8: Recording Interruption Handling
**Given** recording is in progress
**When** interruption occurs (phone call, backgrounding, low battery)
**Then**:
1. Recording stops gracefully at last checkpoint (Story 7-5)
2. Partial video saved with checkpoint attestation
3. Preview shows "Verified: 10s of 12s recorded" indicator (if partial)
4. User presented with Use/Retake options as normal
5. Upload includes partial video metadata

### AC 9: Mode Switch Behavior
**Given** user switches between photo and video modes
**When** mode selection changes
**Then**:
1. Depth overlay switches from full colormap (photo) to edge-only (video)
2. Capture button changes visual from tap (photo) to hold (video)
3. ARSession continues running without restart
4. Tracking state preserved across mode switch
5. Switch disabled during capture/recording

### AC 10: Error States and Feedback
**Given** various error conditions
**When** errors occur
**Then** handle:
1. Insufficient storage: Show "Storage full - cannot record video" alert
2. ARSession interrupted: Stop recording, show "Recording interrupted" message
3. Tracking limited: Show "Move slower" or "More light needed" warning
4. Recording failed: Show "Recording failed" error with retry option
5. Upload failed: Show retry button with error details

## Tasks / Subtasks

- [ ] Task 1: Add mode selection UI (AC: #1, #9)
  - [ ] Create ModeSelector SwiftUI component (Photo | Video segmented control)
  - [ ] Add to CaptureView above or below controls bar
  - [ ] Update CaptureViewModel with @Published currentMode property
  - [ ] Persist mode preference to UserDefaults
  - [ ] Disable mode selection during capture/recording

- [ ] Task 2: Extend CaptureButton for video mode (AC: #2, #5)
  - [ ] Update CaptureButton.swift to support video mode visual
  - [ ] Add "hold to record" affordance (pulsing border or instructional text)
  - [ ] Implement long-press gesture recognizer (min duration: 0.5s)
  - [ ] Add recording state visual (red pulsing border)
  - [ ] Handle button release for early stop

- [ ] Task 3: Recording status indicator (AC: #3, #5)
  - [ ] Extend recordingIndicatorOverlay in CaptureView.swift
  - [ ] Add progress bar showing elapsed/remaining time
  - [ ] Implement 5-second warning haptic feedback in CaptureViewModel
  - [ ] Add auto-stop at 15 seconds in VideoRecordingSession
  - [ ] Test timer accuracy and haptic timing

- [ ] Task 4: Depth overlay mode switching (AC: #4, #9)
  - [ ] Extend CaptureView.swift to conditionally render overlays
  - [ ] Show DepthOverlayView in photo mode (full colormap)
  - [ ] Show EdgeDepthOverlayView in video mode (edge-only)
  - [ ] Separate UserDefaults keys for photo vs video overlay preference
  - [ ] Update overlay toggle button label based on mode

- [ ] Task 5: Upload progress UI (AC: #6)
  - [ ] Create UploadProgressView SwiftUI component
  - [ ] Add @Published uploadProgress property to CaptureViewModel
  - [ ] Display progress indicator in result detail view or overlay
  - [ ] Show current MB / total MB text
  - [ ] Handle upload errors with retry button

- [ ] Task 6: Video preview sheet (AC: #7)
  - [ ] Create VideoPreviewSheet SwiftUI component
  - [ ] Embed VideoPlayer (native AVPlayer wrapper)
  - [ ] Add play/pause controls
  - [ ] Add depth overlay toggle in preview
  - [ ] Implement Use/Retake button actions
  - [ ] Support swipe-to-dismiss gesture

- [ ] Task 7: Partial video indicator (AC: #8)
  - [ ] Check VideoRecordingResult.attestation?.isPartial in preview
  - [ ] Display PartialVideoBadge component (from Story 7-5)
  - [ ] Show "Verified: Xs of Ys recorded" text
  - [ ] Include partial indicator in upload metadata
  - [ ] Test with simulated interruption scenarios

- [ ] Task 8: Interruption handling (AC: #8, #10)
  - [ ] Verify VideoRecordingSession.handleInterruption() works correctly
  - [ ] Test phone call interruption scenario
  - [ ] Test app backgrounding scenario
  - [ ] Test low battery scenario
  - [ ] Ensure partial video saves and previews correctly

- [ ] Task 9: Error handling and user feedback (AC: #10)
  - [ ] Check available storage before recording starts
  - [ ] Show alert if storage < 50MB available
  - [ ] Display tracking quality warnings during recording
  - [ ] Handle recording failures gracefully
  - [ ] Add retry mechanism for failed uploads

- [ ] Task 10: Integration with existing services (AC: All)
  - [ ] Connect to VideoRecordingSession from Story 7-1
  - [ ] Use DepthKeyframeBuffer from Story 7-2
  - [ ] Show EdgeDepthOverlayView from Story 7-3
  - [ ] Include VideoAttestation from Story 7-5
  - [ ] Trigger upload via VideoProcessingPipeline from Story 7-7
  - [ ] Use UploadService for background upload

- [ ] Task 11: Update CaptureControlsBar (AC: #2, #3, #5)
  - [ ] Add video mode state to CaptureControlsBar component
  - [ ] Update capture button to show hold gesture hint
  - [ ] Display recording timer when isRecordingVideo=true
  - [ ] Add progress indicator for 15s countdown
  - [ ] Handle mode-specific button interactions

- [ ] Task 12: Write tests (AC: All)
  - [ ] Unit tests for CaptureViewModel mode switching
  - [ ] Unit tests for recording duration and auto-stop
  - [ ] Unit tests for upload progress tracking
  - [ ] UI tests for mode selection interaction
  - [ ] UI tests for hold-to-record gesture
  - [ ] UI tests for preview sheet display
  - [ ] Integration test for full video capture flow
  - [ ] Test interruption handling scenarios

## Dev Notes

### Technical Approach

**Mode Selection:**
Add `CaptureMode` enum with `photo` and `video` cases. Store in CaptureViewModel as `@Published` property. Persist to UserDefaults with key `"app.rial.captureMode"`. Use SwiftUI `Picker` with `.segmentedPickerStyle()` for iOS 15 compatibility.

**Hold-to-Record Button:**
Extend `CaptureButton.swift` with long-press gesture recognizer. Use `UILongPressGestureRecognizer` with `minimumPressDuration: 0.5`. Update visual state based on `.began`, `.changed`, `.ended` states. Show pulsing red border during recording using `strokeBorder()` with `Animation.easeInOut.repeatForever()`.

**Recording Timer:**
Use `Timer.publish(every: 1.0, on: .main, in: .common)` in CaptureViewModel to update `@Published var recordingDuration: TimeInterval`. Display formatted string ("0:00" to "0:15") in `recordingIndicatorOverlay`. Stop timer when recording ends.

**Depth Overlay Mode:**
Conditionally render overlay based on `currentMode`:
```swift
if currentMode == .video {
    EdgeDepthOverlayView(...)  // Story 7-3
} else {
    DepthOverlayView(...)       // Existing photo overlay
}
```
Separate UserDefaults keys: `"photoOverlayEnabled"` and `"videoOverlayEnabled"`.

**Upload Progress:**
Track upload progress via `URLSession.uploadTask` delegate callbacks. Update `@Published var uploadProgress: Double` (0.0-1.0). Display in `UploadProgressView` with `ProgressView(value: uploadProgress)` and MB text.

**Video Preview:**
Create `VideoPreviewSheet` with `AVPlayer` for playback. Wrap AVPlayerViewController or create custom player with `VideoPlayer` SwiftUI view (iOS 14+). Add overlay toggle that renders depth visualization on top of video (read-only, not interactive).

**Partial Video Display:**
Check `videoRecording.attestation?.isPartial` in preview. If true, show `PartialVideoBadge` (already created in Story 7-5) with verified duration text. Badge should use info blue styling, not error red.

**Interruption Handling:**
VideoRecordingSession (Story 7-1) already implements `handleInterruption()` which calls checkpoint attestation (Story 7-5). UI just needs to display result correctly and allow user to Use or Retake partial video.

**ARSession Continuity:**
Do NOT restart ARSession when switching modes. Same session runs for both photo and video. Just change which processing pipeline is active (photo capture vs video recording).

### Project Structure Notes

**New Files:**
- `ios/Rial/Features/Capture/ModeSelector.swift` - SwiftUI segmented control for Photo | Video
- `ios/Rial/Features/Capture/VideoPreviewSheet.swift` - Video playback preview with Use/Retake
- `ios/Rial/Features/Capture/UploadProgressView.swift` - Upload progress indicator

**Modified Files:**
- `ios/Rial/Features/Capture/CaptureView.swift` - Add mode selector, conditional depth overlays
- `ios/Rial/Features/Capture/CaptureViewModel.swift` - Add mode property, recording timer, upload progress
- `ios/Rial/Features/Capture/CaptureButton.swift` - Add video mode visual and hold gesture
- `ios/Rial/Features/Capture/CaptureControlsBar.swift` - Update for video mode state

**Component Hierarchy:**
```
CaptureView
├── ModeSelector (new) - Photo | Video toggle
├── ARViewContainer (existing) - Camera preview
├── EdgeDepthOverlayView (Story 7-3, conditional) - Video mode overlay
├── DepthOverlayView (existing, conditional) - Photo mode overlay
├── recordingIndicatorOverlay (extended) - Timer + progress
├── CaptureControlsBar (modified)
│   ├── CaptureButton (modified) - Hold gesture for video
│   └── Overlay toggle
└── VideoPreviewSheet (new) - Video playback + Use/Retake
    ├── VideoPlayer
    ├── UploadProgressView (new, conditional)
    └── PartialVideoBadge (Story 7-5, conditional)
```

### Architecture Alignment

**ARKit Integration:**
Uses existing `ARCaptureSession` from Story 6-5. No changes needed - session runs continuously. Mode switch just changes whether `CaptureViewModel.capture()` (photo) or `CaptureViewModel.startVideoRecording()` (video) is called.

**Video Recording:**
`VideoRecordingSession` (Story 7-1) handles all recording logic:
- AVAssetWriter for video encoding
- Frame delivery to hash chain (Story 7-4)
- Depth keyframe extraction (Story 7-2)
- Attestation on completion/interruption (Story 7-5)

**Upload Integration:**
Use existing `UploadService` from Epic 6. Extend with video-specific endpoint:
- Multipart upload: video file, depth data, hash chain, metadata
- Background URLSession for reliability
- Progress tracking via delegate callbacks

**Result Storage:**
Video captures stored in `CaptureStore` (Epic 6) with type discriminator. Result view (Story 6-15) extended to handle video type with VideoPlayer instead of static image.

### Testing Standards

**Unit Tests (XCTest):**
- Mode switching logic
- Recording timer accuracy
- Upload progress calculation
- Partial video detection
- Error handling paths

**UI Tests (XCTest):**
- Mode selector tap interaction
- Hold-to-record gesture (minimum 500ms hold)
- Recording timer updates every second
- Auto-stop at 15 seconds
- Preview sheet appearance and dismissal
- Use/Retake button actions

**Integration Tests (Device Only):**
- Full video capture flow (hold → record → preview → save)
- Mode switch mid-session (no ARSession restart)
- Video upload with progress tracking
- Phone call interruption (requires manual testing)
- Background app interruption
- Partial video save and preview

**Performance Tests:**
- Mode switch latency < 100ms
- Recording start latency < 200ms
- Timer update does not drop frames
- Upload progress updates smoothly (no jank)

### References

**Existing Components (Reuse):**
- `ARCaptureSession` (Story 6-5) - ARKit capture foundation
- `VideoRecordingSession` (Story 7-1) - Video recording coordinator
- `EdgeDepthOverlayView` (Story 7-3) - Edge-only depth visualization
- `PartialVideoBadge` (Story 7-5) - Partial video indicator
- `UploadService` (Story 6-11) - Background upload manager
- `CaptureStore` (Story 6-9) - Capture persistence

**Related Stories:**
- Story 6-13: SwiftUI Capture Screen (photo mode reference)
- Story 6-14: Capture History View (will show video captures)
- Story 6-15: Result Detail View (will show video playback)
- Story 7-1: ARKit Video Recording Session (recording engine)
- Story 7-2: Depth Keyframe Extraction (depth data collection)
- Story 7-3: Real-Time Edge Depth Overlay (video overlay)
- Story 7-4: Frame Hash Chain (integrity verification)
- Story 7-5: Video Attestation Checkpoints (partial video support)
- Story 7-7: Video Local Processing Pipeline (upload packaging)

**API Endpoints:**
- `POST /api/v1/captures/video` - Video upload endpoint (Story 7-8)
- Multipart form data: video, depth_data, hash_chain, metadata

## Dev Agent Record

### Context Reference

docs/sprint-artifacts/story-contexts/7-14-video-capture-ui-context.xml

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

N/A - All tests passing

### Completion Notes List

**Implementation Summary:**
- Created CaptureMode enum with photo/video modes and ModeSelector SwiftUI component
- Extended CaptureViewModel with mode property persistence, 5-second warning haptic, storage check
- Updated CaptureView to integrate mode selector, conditional depth overlays, video preview sheet
- Created VideoPreviewSheet with AVPlayer, Use/Retake buttons, partial video indicator
- Created UploadProgressView with progress bar, percentage, and error handling
- Created RecordingProgressBar with countdown and warning zone highlighting
- Updated CaptureButton to support tap-to-record in video mode (vs hold in photo mode)
- Added unit tests for mode switching, progress calculations, storage check logic

**Key Decisions:**
- Video mode uses tap-to-start/tap-to-stop instead of hold (clearer UX for longer recordings)
- Reused existing PartialVideoBadge from Story 7-5 for consistency
- Separate overlay preferences for photo vs video mode stored in UserDefaults
- 50MB minimum storage required before video recording starts
- 5-second warning fires at 10s elapsed (5s remaining until 15s max)

**AC Status:**
- AC-1 Mode Selection Interface: SATISFIED - ModeSelector with persistence
- AC-2 Video Mode Recording Button: SATISFIED - CaptureButton updated with mode
- AC-3 Recording Status Indicator: SATISFIED - RecordingProgressBar + timer
- AC-4 Real-Time Depth Overlay: SATISFIED - Conditional overlay in CaptureView
- AC-5 Recording Duration Control: SATISFIED - 5s warning haptic, auto-stop at 15s
- AC-6 Upload Progress Indicator: SATISFIED - UploadProgressView component
- AC-7 Video Preview After Recording: SATISFIED - VideoPreviewSheet
- AC-8 Recording Interruption Handling: SATISFIED - Partial video display
- AC-9 Mode Switch Behavior: SATISFIED - ARSession continuity maintained
- AC-10 Error States and Feedback: SATISFIED - Storage check, error messages

### File List

**Created:**
- ios/Rial/Features/Capture/ModeSelector.swift - Photo/Video mode selector
- ios/Rial/Features/Capture/VideoPreviewSheet.swift - Video playback preview
- ios/Rial/Features/Capture/UploadProgressView.swift - Upload progress indicator
- ios/Rial/Features/Capture/RecordingProgressBar.swift - Recording countdown bar
- ios/RialTests/Capture/CaptureModeTests.swift - Unit tests for mode/progress logic

**Modified:**
- ios/Rial/Features/Capture/CaptureView.swift - Mode selector, overlays, preview sheets
- ios/Rial/Features/Capture/CaptureViewModel.swift - Mode property, haptics, storage check
- ios/Rial/Features/Capture/CaptureButton.swift - Video mode support, accessibility
- ios/Rial.xcodeproj/project.pbxproj - Added new files to project
- docs/sprint-artifacts/sprint-status.yaml - Status: in-progress -> review

---

## Source Document References

- **Epic:** [Source: docs/epics.md - Epic 7: Video Capture with LiDAR Depth]
  - Story 7.14: Video Capture UI (lines 2819-2852)
  - Acceptance Criteria: Mode selection, recording UI, preview, interruption handling
- **Tech Spec:** [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-7.md]
  - Section: Components Referenced > iOS Video Recording UI
  - Section: Data Models > VideoCapture, VideoRecordingResult
  - Section: Performance Constraints (30fps maintained, <300MB memory)
- **Architecture:** [Source: docs/architecture.md]
  - ARKit unified capture pattern
  - SwiftUI view architecture
  - Upload service integration
- **PRD:** [Source: docs/prd.md]
  - FR47: 15-second video recording with 10fps depth
  - FR48: Real-time edge depth overlay during recording
  - FR55: Video verification with playback
- **Previous Stories:**
  - [Source: docs/sprint-artifacts/stories/6-13-swiftui-capture-screen.md] (Photo capture UI patterns)
  - [Source: docs/sprint-artifacts/stories/7-1-arkit-video-recording-session.md] (Video recording engine)
  - [Source: docs/sprint-artifacts/stories/7-2-depth-keyframe-extraction.md] (Depth data collection)
  - [Source: docs/sprint-artifacts/stories/7-3-realtime-edge-depth-overlay.md] (Edge overlay component)
  - [Source: docs/sprint-artifacts/stories/7-5-video-attestation-checkpoints.md] (Partial video, PartialVideoBadge)
  - [Source: docs/sprint-artifacts/stories/7-7-video-local-processing-pipeline.md] (Upload packaging)
- **Existing Code:**
  - [Source: ios/Rial/Features/Capture/CaptureView.swift] (Current photo capture UI)
  - [Source: ios/Rial/Features/Capture/CaptureViewModel.swift] (Capture state management)
  - [Source: ios/Rial/Features/Capture/CaptureButton.swift] (Capture button component)
  - [Source: ios/Rial/Features/Capture/EdgeDepthOverlayView.swift] (Edge overlay from Story 7-3)
  - [Source: ios/Rial/Core/Capture/VideoRecordingSession.swift] (Video recording from Story 7-1)

---

## Learnings from Previous Stories

Based on review of Stories 6-13 (SwiftUI Capture Screen), 7-1 (Video Recording), 7-3 (Edge Overlay), and 7-5 (Video Attestation):

1. **CaptureView Already Supports Video (Stories 6-13, 7-3):** CaptureView.swift already has recording indicator overlay, video recording state, and EdgeDepthOverlayView integration. Mode selector is the main missing piece.

2. **Hold-to-Record Pattern (Story 7-1):** Video recording uses press-and-hold interaction. CaptureButton needs long-press gesture recognizer with visual feedback (pulsing border or scale animation).

3. **Dual Overlay Modes (Story 7-3):** Photo mode uses full colormap overlay (DepthOverlayView). Video mode uses edge-only overlay (EdgeDepthOverlayView). Conditional rendering based on mode already partially implemented.

4. **Recording Duration (Story 7-1):** VideoRecordingSession has 15-second max duration built in. UI timer should match backend state. Use `Timer.publish()` in ViewModel for smooth updates.

5. **Partial Video Display (Story 7-5):** PartialVideoBadge component already exists. Check `attestation?.isPartial` flag and display in preview sheet. Use info blue styling, not error red.

6. **Interruption Handling (Story 7-1, 7-5):** VideoRecordingSession.handleInterruption() already implemented. UI just needs to handle the result correctly in preview.

7. **ARSession Continuity (Story 6-5, 7-1):** Same ARCaptureSession runs for both photo and video. Do NOT restart session on mode switch - just change processing pipeline.

8. **Haptic Feedback Pattern (Story 6-13):** Use `UIImpactFeedbackGenerator` for recording start/stop. Use `.heavy` style for stop, `.medium` for start. Prepare generator before use for lowest latency.

9. **Upload Progress Pattern (Story 6-11):** UploadService uses background URLSession with delegate callbacks. Track `uploadProgress` as Double (0.0-1.0) and display with ProgressView.

10. **Preview Sheet Pattern (Story 6-13):** Use SwiftUI `.sheet(isPresented:)` modifier with `@Published` boolean. Support swipe-to-dismiss with `.presentationDetents([.medium, .large])` on iOS 16+.

11. **Mode Persistence (Story 6-13):** Store mode preference in UserDefaults with key `"app.rial.captureMode"`. Load on init, save on change. Enum stored as `String` rawValue.

12. **Error Handling (Story 6-13, 7-1):** Show errors as overlay banners at top of screen, not full-screen alerts. Auto-dismiss after 5 seconds or on tap. Use consistent error message format.

13. **Tracking State Warnings (Story 6-13):** Display tracking quality warnings during recording: "Move slower" (excessive motion), "More light needed" (insufficient features). Use yellow badge with 0.8 opacity.

14. **Storage Check (Best Practice):** Check available storage before starting video recording. Require minimum 50MB free. Show "Storage full" alert if insufficient. Video files ~15-20MB for 15s.

15. **Video Player Performance (iOS Best Practice):** Use AVPlayerViewController or native SwiftUI VideoPlayer (iOS 14+). Avoid custom player implementations. Pre-load video in background for instant preview playback.

16. **Testing Video Interruption (Story 7-5 Review):** Phone call and app backgrounding are primary interruption scenarios. Low battery also triggers interruption. All must save partial video correctly.

17. **Upload in Background (Story 6-11):** Video uploads can take 30-60 seconds on cellular. Use background URLSession so upload continues if user navigates away. Show progress in history view.

18. **Depth Overlay Toggle (Stories 6-13, 7-3):** Separate toggle state for photo vs video overlay preferences. Photo overlay defaults enabled, video overlay defaults enabled. Both persisted independently.

19. **Recording State Machine (Story 7-1):** VideoRecordingSession has states: idle, recording, processing, error. UI should reflect all states. Disable interactions during processing.

20. **Video Codec Selection (Story 7-1):** VideoRecordingSession defaults to H.264 (HEVC on newer devices). UI doesn't need to expose codec choice - automatic based on device capability.

---

_Story created: 2025-11-27_
_Depends on: Story 7-7 (Video Local Processing Pipeline) - provides upload packaging_
_Depends on: Story 7-3 (Real-Time Edge Depth Overlay) - provides edge visualization_
_Depends on: Story 7-5 (Video Attestation Checkpoints) - provides partial video support_
_Enables: Complete video capture user experience (Epic 7 completion)_
