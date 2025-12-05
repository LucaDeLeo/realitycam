//
//  CaptureView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Main capture screen with AR camera preview and depth overlay.
//

import SwiftUI
import ARKit

/// Main capture screen displaying AR camera with depth overlay and capture controls.
///
/// ## Features (Story 7-14 additions)
/// - Photo/Video mode selector with persistent preference (AC-1)
/// - Full-screen ARKit camera preview
/// - Real-time LiDAR depth visualization overlay (photo mode: full colormap)
/// - Real-time edge depth overlay (video mode: Sobel edge detection)
/// - Large capture button with haptic feedback (tap for photo, hold for video)
/// - Video recording with timer, progress bar, and 5-second warning haptic (AC-5)
/// - Video preview sheet with Use/Retake options (AC-7)
/// - Partial video indicator for interrupted recordings (AC-8)
/// - Permission handling
///
/// ## Features (Story 8-2 additions)
/// - Privacy mode indicator when privacy mode is enabled (AC-5)
/// - Tap indicator to navigate to privacy settings
///
/// ## Depth Overlay Modes
/// - **Photo mode**: Full colormap depth visualization (red=near, blue=far)
/// - **Video mode**: Edge-only depth visualization (cyan=near, magenta=far)
///
/// The edge overlay in video mode is sparse and doesn't obscure the preview,
/// while still providing depth feedback. It renders to preview ONLY - the
/// recorded video contains raw RGB frames without any overlay.
///
/// ## Mode Switching
/// - Mode can be switched via ModeSelector at the bottom
/// - Mode preference persisted to UserDefaults
/// - ARSession continues running on mode switch (no restart needed)
/// - Mode selector disabled during capture or recording
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     CaptureView()
/// }
/// ```
struct CaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @EnvironmentObject private var privacySettings: PrivacySettingsManager
    @EnvironmentObject private var navigationState: AppNavigationState

    /// Depth overlay opacity (photo mode)
    @State private var depthOpacity: Float = 0.4


    /// Whether to show privacy settings sheet (Story 8-2)
    @State private var showPrivacySettings = false

    #if DEBUG
    /// Whether to show debug environment settings
    @State private var showDebugSettings = false
    #endif

    /// Haptic feedback generators
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactFeedback = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack {
            // Background - black when no camera
            Color.black.ignoresSafeArea()

            // Content based on state
            if !viewModel.hasCameraPermission {
                CameraPermissionView()
            } else if !viewModel.isLiDARAvailable {
                LiDARUnavailableView()
            } else {
                // Camera and controls
                cameraContent
            }

            // Error overlay
            if let error = viewModel.errorMessage {
                errorOverlay(message: error)
            }

            // Success overlay (auto-dismisses)
            if let success = viewModel.successMessage {
                successOverlay(message: success)
            }
        }
        .onAppear {
            if viewModel.hasCameraPermission && viewModel.isLiDARAvailable {
                viewModel.start()
            } else if !viewModel.hasCameraPermission {
                viewModel.requestCameraPermission()
            }
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $viewModel.showCapturePreview) {
            capturePreviewSheet
        }
        .sheet(isPresented: $viewModel.showVideoPreview) {
            videoPreviewSheet
        }
        .sheet(isPresented: $showPrivacySettings) {
            privacySettingsSheet
        }
        #if DEBUG
        .sheet(isPresented: $showDebugSettings) {
            DebugEnvironmentView()
        }
        #endif
    }

    // MARK: - Privacy Settings Sheet

    @ViewBuilder
    private var privacySettingsSheet: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                PrivacySettingsView()
                    .environmentObject(privacySettings)
            }
        } else {
            NavigationView {
                PrivacySettingsView()
                    .environmentObject(privacySettings)
            }
            .navigationViewStyle(.stack)
        }
    }

    // MARK: - Camera Content

    @ViewBuilder
    private var cameraContent: some View {
        ZStack {
            // AR Camera Preview
            if viewModel.isRunning {
                ARViewContainer(session: viewModel.arSession)
                    .ignoresSafeArea()
            }

            // Depth Overlay - mode-dependent (Story 7.3, 7-14)
            // Video mode: Edge-only overlay (sparse, doesn't obscure preview)
            // Photo mode: Full colormap overlay (red=near, blue=far)
            if viewModel.currentMode == .video || viewModel.isRecordingVideo {
                // Edge overlay for video mode (Story 7.3)
                // Renders to preview ONLY - NOT in recorded video
                EdgeDepthOverlayView(
                    depthFrame: viewModel.currentDepthFrame,
                    edgeThreshold: viewModel.edgeThreshold,
                    isVisible: $viewModel.showEdgeOverlay
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            } else if viewModel.showPhotoOverlay {
                // Full colormap overlay for photo mode
                DepthOverlayView(
                    depthFrame: viewModel.currentDepthFrame,
                    opacity: $depthOpacity,
                    isVisible: $viewModel.showPhotoOverlay
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Recording indicator overlay (appears at top when recording)
            if viewModel.isRecordingVideo {
                recordingIndicatorOverlay
            }

            // Controls overlay
            VStack {
                // Top bar (hidden when recording)
                if !viewModel.isRecordingVideo {
                    topBar
                } else {
                    // Spacer to push content down when recording indicator is shown
                    Spacer().frame(height: 60)
                }

                Spacer()

                // Tracking state indicator (hidden when recording)
                if !viewModel.isRecordingVideo {
                    trackingStateIndicator
                }

                // Mode selector (Story 7-14, AC-1)
                // Positioned above capture button, disabled during capture/recording
                if !viewModel.isRecordingVideo {
                    ModeSelector(
                        currentMode: $viewModel.currentMode,
                        isDisabled: viewModel.isCapturing || viewModel.isRecordingVideo
                    )
                    .padding(.bottom, 8)
                }

                // Bottom controls
                // Toggle binding switches between photo (colormap) and video (edge) overlay
                CaptureControlsBar(
                    showDepthOverlay: viewModel.currentMode == .video ? $viewModel.showEdgeOverlay : $viewModel.showPhotoOverlay,
                    isCapturing: viewModel.isCapturing,
                    isRecordingVideo: viewModel.isRecordingVideo,
                    recordingDuration: viewModel.recordingDuration,
                    currentMode: viewModel.currentMode,
                    onCapture: { viewModel.capture() },
                    onRecordingStart: {
                        impactFeedback.prepare()
                        impactFeedback.impactOccurred()
                        viewModel.startVideoRecording()
                    },
                    onRecordingStop: {
                        heavyImpactFeedback.prepare()
                        heavyImpactFeedback.impactOccurred()
                        viewModel.stopVideoRecording()
                    }
                )
            }
        }
    }

    // MARK: - Recording Indicator Overlay

    private var recordingIndicatorOverlay: some View {
        VStack {
            VStack(spacing: 8) {
                // Status badge
                HStack(spacing: 8) {
                    // Pulsing red recording dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .modifier(PulsingAnimation())

                    Text("Recording...")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    // Elapsed time timer
                    Text(formatDuration(viewModel.recordingDuration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.white)
                }

                // Progress bar (AC-5)
                RecordingProgressBar(
                    currentDuration: viewModel.recordingDuration,
                    maxDuration: CaptureViewModel.maxRecordingDuration
                )
                .frame(width: 180)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            .padding(.top, 50)

            Spacer()
        }
    }

    /// Format duration as "0:00" string
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Privacy Mode Indicator (Story 8-2, AC #5)
            // Shows when privacy mode is enabled, tap to open settings
            if privacySettings.isPrivacyModeEnabled {
                PrivacyModeIndicator {
                    showPrivacySettings = true
                }
            }

            // Opacity slider when depth visible (photo mode only)
            if viewModel.currentMode == .photo && viewModel.showPhotoOverlay {
                DepthOverlayOpacitySlider(opacity: $depthOpacity)
                    .frame(maxWidth: 200)
            }

            Spacer()

            #if DEBUG
            // Debug Settings Button - opens environment switcher
            debugSettingsButton
            #endif
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Debug Settings Button

    #if DEBUG
    private var debugSettingsButton: some View {
        Button {
            showDebugSettings = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape.fill")
                // Show indicator when using non-default environment
                if EnvironmentStore.shared.isOverrideActive {
                    Circle()
                        .fill(EnvironmentStore.shared.currentEnvironment == .production ? .orange : .green)
                        .frame(width: 8, height: 8)
                }
            }
            .font(.system(size: 18))
            .foregroundColor(.white)
            .padding(8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
        }
    }
    #endif

    // MARK: - Tracking State Indicator

    @ViewBuilder
    private var trackingStateIndicator: some View {
        switch viewModel.trackingState {
        case .notAvailable:
            trackingBadge("Initializing...", color: .orange)
        case .limited(let reason):
            trackingBadge(trackingLimitedMessage(reason), color: .yellow)
        case .normal:
            EmptyView()
        }
    }

    private func trackingBadge(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.8))
            .cornerRadius(8)
            .padding(.bottom, 20)
    }

    private func trackingLimitedMessage(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing:
            return "Initializing..."
        case .excessiveMotion:
            return "Move slower"
        case .insufficientFeatures:
            return "More light needed"
        case .relocalizing:
            return "Relocalizing..."
        @unknown default:
            return "Limited tracking"
        }
    }

    // MARK: - Error Overlay

    private func errorOverlay(message: String) -> some View {
        VStack {
            Text(message)
                .foregroundColor(.white)
                .padding()
                .background(Color.red.opacity(0.9))
                .cornerRadius(10)
                .padding()

            Spacer()
        }
        .transition(.move(edge: .top))
        .onTapGesture {
            viewModel.errorMessage = nil
        }
    }

    // MARK: - Success Overlay

    private func successOverlay(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                Text(message)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.green.opacity(0.9))
            .cornerRadius(10)
            .padding()

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: viewModel.successMessage)
        .onTapGesture {
            viewModel.successMessage = nil
        }
    }

    // MARK: - Capture Preview Sheet

    private var capturePreviewSheet: some View {
        VStack(spacing: 20) {
            // Preview image
            if let photo = viewModel.lastCapturedPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .padding()
            }

            // Action buttons
            HStack(spacing: 40) {
                Button("Retake") {
                    viewModel.discardCapture()
                }
                .foregroundColor(.red)

                Button("Use Photo") {
                    // Get capture ID before saving (will be cleared after save)
                    let captureId = viewModel.pendingCaptureId
                    viewModel.saveCapture()
                    // Navigate to history tab and show capture detail
                    if let captureId = captureId {
                        navigationState.navigateToCapture(captureId)
                    }
                }
                .foregroundColor(.blue)
                .font(.title3.bold())
            }
            .font(.title3)
            .padding(.bottom, 40)
        }
        .modifier(SheetPresentationModifier())
    }

    // MARK: - Video Preview Sheet (Story 7-14, AC-7)

    private var videoPreviewSheet: some View {
        VideoPreviewSheet(
            result: viewModel.lastVideoResult,
            onUseVideo: {
                viewModel.useVideo()
            },
            onRetake: {
                viewModel.discardVideo()
            },
            isUploading: viewModel.isUploading,
            uploadProgress: viewModel.uploadProgress,
            uploadError: viewModel.uploadError
        )
    }
}

/// Modifier for sheet presentation that handles iOS 15 vs 16+ differences.
struct SheetPresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

/// Pulsing animation modifier for recording indicator.
struct PulsingAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}


// MARK: - Preview

#if DEBUG
struct CaptureView_Previews: PreviewProvider {
    static var previews: some View {
        CaptureView()
            .environmentObject(PrivacySettingsManager.preview())
            .preferredColorScheme(.dark)
    }
}
#endif
