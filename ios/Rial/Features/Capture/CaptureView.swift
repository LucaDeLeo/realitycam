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
/// ## Features
/// - Full-screen ARKit camera preview
/// - Real-time LiDAR depth visualization overlay
/// - Large capture button with haptic feedback
/// - Capture preview with Use/Retake options
/// - Permission handling
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     CaptureView()
/// }
/// ```
struct CaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()

    /// Whether to show depth overlay
    @State private var showDepthOverlay = true

    /// Depth overlay opacity
    @State private var depthOpacity: Float = 0.4

    /// Whether to show history sheet
    @State private var showHistory = false

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
        .sheet(isPresented: $showHistory) {
            // History view will be implemented in Story 6.14
            Text("Capture History")
                .font(.title)
                .padding()
        }
    }

    // MARK: - Camera Content

    @ViewBuilder
    private var cameraContent: some View {
        ZStack {
            // AR Camera Preview
            if let session = viewModel.isRunning ? captureSession : nil {
                ARViewContainer(session: session)
                    .ignoresSafeArea()
            }

            // Depth Overlay
            if showDepthOverlay {
                DepthOverlayView(
                    depthFrame: viewModel.currentDepthFrame,
                    opacity: $depthOpacity,
                    isVisible: $showDepthOverlay
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Controls overlay
            VStack {
                // Top bar
                topBar

                Spacer()

                // Tracking state indicator
                trackingStateIndicator

                // Bottom controls
                CaptureControlsBar(
                    showDepthOverlay: $showDepthOverlay,
                    isCapturing: viewModel.isCapturing,
                    onCapture: { viewModel.capture() },
                    onShowHistory: { showHistory = true }
                )
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Opacity slider when depth visible
            if showDepthOverlay {
                DepthOverlayOpacitySlider(opacity: $depthOpacity)
                    .frame(maxWidth: 200)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

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
                    viewModel.saveCapture()
                }
                .foregroundColor(.blue)
                .font(.title3.bold())
            }
            .font(.title3)
            .padding(.bottom, 40)
        }
        .modifier(SheetPresentationModifier())
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

// MARK: - CaptureView Extension

extension CaptureView {
    /// Access to ARSession for ARViewContainer
    var captureSession: ARSession {
        // Note: In production, this would properly access the ARSession
        // For now, create a placeholder that the ARCaptureSession manages
        ARSession()
    }
}

// MARK: - Preview

#if DEBUG
struct CaptureView_Previews: PreviewProvider {
    static var previews: some View {
        CaptureView()
            .preferredColorScheme(.dark)
    }
}
#endif
