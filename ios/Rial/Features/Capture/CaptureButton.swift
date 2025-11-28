//
//  CaptureButton.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Styled capture button with haptic feedback and hold-to-record support.
//

import SwiftUI

/// Large capture button with haptic feedback and hold-to-record video support.
///
/// Displays as a white circle with inner ring, similar to iPhone camera app.
/// Behavior depends on currentMode (Story 7-14):
/// - Photo mode: Tap to capture photo, hold to record video
/// - Video mode: Tap to start/stop recording (toggle behavior)
///
/// ## Usage
/// ```swift
/// CaptureButton(
///     isCapturing: viewModel.isCapturing,
///     isRecordingVideo: viewModel.isRecordingVideo,
///     currentMode: viewModel.currentMode,
///     action: { viewModel.capture() },
///     onRecordingStart: { viewModel.startVideoRecording() },
///     onRecordingStop: { viewModel.stopVideoRecording() }
/// )
/// ```
struct CaptureButton: View {
    /// Whether photo capture is in progress
    let isCapturing: Bool

    /// Whether video recording is in progress
    let isRecordingVideo: Bool

    /// Current capture mode (photo or video)
    var currentMode: CaptureMode = .photo

    /// Action to perform on tap (photo capture)
    let action: () -> Void

    /// Action to perform when hold starts (video recording start)
    let onRecordingStart: () -> Void

    /// Action to perform when hold ends (video recording stop)
    let onRecordingStop: () -> Void

    /// Haptic feedback generator
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    /// Button size
    private let buttonSize: CGFloat = 72

    /// Inner ring size ratio
    private let innerRingRatio: CGFloat = 0.85

    /// Recording inner circle size ratio (smaller when recording)
    private let recordingInnerRatio: CGFloat = 0.4

    /// State for tracking press gesture
    @State private var isPressed = false

    /// Timer for detecting long press
    @State private var longPressTimer: Timer?

    /// Minimum hold duration to trigger video recording (seconds)
    private let longPressThreshold: TimeInterval = 0.3

    init(
        isCapturing: Bool = false,
        isRecordingVideo: Bool = false,
        currentMode: CaptureMode = .photo,
        action: @escaping () -> Void,
        onRecordingStart: @escaping () -> Void = {},
        onRecordingStop: @escaping () -> Void = {}
    ) {
        self.isCapturing = isCapturing
        self.isRecordingVideo = isRecordingVideo
        self.currentMode = currentMode
        self.action = action
        self.onRecordingStart = onRecordingStart
        self.onRecordingStop = onRecordingStop
    }

    var body: some View {
        ZStack {
            // Outer ring - red when recording, white otherwise
            Circle()
                .strokeBorder(isRecordingVideo ? Color.red : Color.white, lineWidth: 4)
                .frame(width: buttonSize, height: buttonSize)
                .animation(.easeInOut(duration: 0.2), value: isRecordingVideo)

            // Inner content
            if isCapturing {
                // Processing indicator for photo capture
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            } else if isRecordingVideo {
                // Recording state: smaller red rounded rectangle (like stop button)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red)
                    .frame(
                        width: buttonSize * recordingInnerRatio,
                        height: buttonSize * recordingInnerRatio
                    )
                    .modifier(RecordingPulseAnimation())
            } else {
                // Default state: white circle (photo mode) or red circle (video mode ready)
                Circle()
                    .fill(currentMode == .video ? Color.red : Color.white)
                    .frame(
                        width: buttonSize * innerRingRatio,
                        height: buttonSize * innerRingRatio
                    )
                    .scaleEffect(isPressed ? 0.85 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && !isCapturing && !isRecordingVideo {
                        isPressed = true
                        startLongPressTimer()
                    }
                }
                .onEnded { _ in
                    handleGestureEnd()
                }
        )
        .disabled(isCapturing)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    /// Start timer to detect long press for video recording
    private func startLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.isPressed && !self.isRecordingVideo {
                    // Long press detected - start video recording
                    self.onRecordingStart()
                }
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if isRecordingVideo {
            return "Stop recording"
        }
        return currentMode == .video ? "Record video" : "Capture photo"
    }

    private var accessibilityHint: String {
        if isCapturing {
            return "Capturing in progress"
        }
        if isRecordingVideo {
            return "Tap to stop recording"
        }
        switch currentMode {
        case .video:
            return "Tap to start recording, tap again to stop"
        case .photo:
            return "Tap to capture photo, hold to record video"
        }
    }

    /// Handle gesture end (finger lifted)
    private func handleGestureEnd() {
        longPressTimer?.invalidate()
        longPressTimer = nil

        if isRecordingVideo {
            // Was recording - stop recording (works in both modes)
            onRecordingStop()
        } else if isPressed {
            // Short press behavior depends on mode
            impactFeedback.prepare()
            impactFeedback.impactOccurred()

            if currentMode == .video {
                // Video mode: tap starts recording (AC-3)
                onRecordingStart()
            } else {
                // Photo mode: tap captures photo
                action()
            }
        }

        isPressed = false
    }
}

/// Pulse animation for recording state
struct RecordingPulseAnimation: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .animation(
                Animation.easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true),
                value: scale
            )
            .onAppear {
                scale = 0.9
            }
    }
}

// MARK: - CaptureButtonStyle

/// Custom button style for capture button with scale animation.
struct CaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Mini Capture Button

/// Smaller capture button for secondary actions.
struct MiniCaptureButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.white)
                .padding(12)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

// MARK: - Capture Controls Bar

/// Bottom control bar with capture button and toggles.
///
/// Supports both photo capture (tap) and video recording modes.
/// Behavior adapts based on currentMode (Story 7-14).
struct CaptureControlsBar: View {
    @Binding var showDepthOverlay: Bool
    let isCapturing: Bool
    let isRecordingVideo: Bool
    let recordingDuration: TimeInterval
    let currentMode: CaptureMode
    let onCapture: () -> Void
    let onRecordingStart: () -> Void
    let onRecordingStop: () -> Void
    let onShowHistory: () -> Void

    /// Convenience initializer with default video recording values
    init(
        showDepthOverlay: Binding<Bool>,
        isCapturing: Bool,
        isRecordingVideo: Bool = false,
        recordingDuration: TimeInterval = 0,
        currentMode: CaptureMode = .photo,
        onCapture: @escaping () -> Void,
        onRecordingStart: @escaping () -> Void = {},
        onRecordingStop: @escaping () -> Void = {},
        onShowHistory: @escaping () -> Void
    ) {
        self._showDepthOverlay = showDepthOverlay
        self.isCapturing = isCapturing
        self.isRecordingVideo = isRecordingVideo
        self.recordingDuration = recordingDuration
        self.currentMode = currentMode
        self.onCapture = onCapture
        self.onRecordingStart = onRecordingStart
        self.onRecordingStop = onRecordingStop
        self.onShowHistory = onShowHistory
    }

    var body: some View {
        HStack {
            // Depth/Edge toggle (Story 7.3: ENABLED during recording for edge overlay)
            // In video mode, this toggles the edge overlay visibility
            // In photo mode, this toggles the full colormap overlay
            DepthOverlayToggleButton(isVisible: $showDepthOverlay)

            Spacer()

            // Main capture button with video recording support
            CaptureButton(
                isCapturing: isCapturing,
                isRecordingVideo: isRecordingVideo,
                currentMode: currentMode,
                action: onCapture,
                onRecordingStart: onRecordingStart,
                onRecordingStop: onRecordingStop
            )

            Spacer()

            // History button (disabled during recording)
            Button(action: onShowHistory) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .opacity(isRecordingVideo ? 0.3 : 1.0)
            .disabled(isRecordingVideo)
            .accessibilityLabel("View capture history")
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}

// MARK: - Preview

#if DEBUG
struct CaptureButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                // Default state
                CaptureButton(
                    isCapturing: false,
                    action: { print("Capture!") }
                )

                // Capturing state
                CaptureButton(
                    isCapturing: true,
                    action: { print("Capture!") }
                )

                // Recording state
                CaptureButton(
                    isCapturing: false,
                    isRecordingVideo: true,
                    action: { print("Capture!") },
                    onRecordingStart: { print("Recording started!") },
                    onRecordingStop: { print("Recording stopped!") }
                )

                // Control bar - default
                CaptureControlsBar(
                    showDepthOverlay: .constant(true),
                    isCapturing: false,
                    onCapture: {},
                    onShowHistory: {}
                )

                // Control bar - recording
                CaptureControlsBar(
                    showDepthOverlay: .constant(true),
                    isCapturing: false,
                    isRecordingVideo: true,
                    recordingDuration: 5.5,
                    onCapture: {},
                    onRecordingStart: {},
                    onRecordingStop: {},
                    onShowHistory: {}
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
