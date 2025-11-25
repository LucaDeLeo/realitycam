//
//  CaptureButton.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Styled capture button with haptic feedback.
//

import SwiftUI

/// Large capture button with haptic feedback.
///
/// Displays as a white circle with inner ring, similar to iPhone camera app.
/// Provides haptic feedback on tap and shows processing state.
///
/// ## Usage
/// ```swift
/// CaptureButton(isCapturing: viewModel.isCapturing) {
///     viewModel.capture()
/// }
/// ```
struct CaptureButton: View {
    /// Whether capture is in progress
    let isCapturing: Bool

    /// Action to perform on tap
    let action: () -> Void

    /// Haptic feedback generator
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    /// Button size
    private let buttonSize: CGFloat = 72

    /// Inner ring size ratio
    private let innerRingRatio: CGFloat = 0.85

    init(isCapturing: Bool = false, action: @escaping () -> Void) {
        self.isCapturing = isCapturing
        self.action = action
    }

    var body: some View {
        Button(action: performCapture) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                // Inner filled circle
                if isCapturing {
                    // Processing indicator
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(
                            width: buttonSize * innerRingRatio,
                            height: buttonSize * innerRingRatio
                        )
                }
            }
        }
        .buttonStyle(CaptureButtonStyle())
        .disabled(isCapturing)
        .accessibilityLabel("Capture photo")
        .accessibilityHint(isCapturing ? "Capturing in progress" : "Double tap to capture authenticated photo")
    }

    private func performCapture() {
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
        action()
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
struct CaptureControlsBar: View {
    @Binding var showDepthOverlay: Bool
    let isCapturing: Bool
    let onCapture: () -> Void
    let onShowHistory: () -> Void

    var body: some View {
        HStack {
            // Depth toggle
            DepthOverlayToggleButton(isVisible: $showDepthOverlay)

            Spacer()

            // Main capture button
            CaptureButton(isCapturing: isCapturing, action: onCapture)

            Spacer()

            // History button
            Button(action: onShowHistory) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
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
                CaptureButton(isCapturing: false) {
                    print("Capture!")
                }

                CaptureButton(isCapturing: true) {
                    print("Capture!")
                }

                CaptureControlsBar(
                    showDepthOverlay: .constant(true),
                    isCapturing: false,
                    onCapture: {},
                    onShowHistory: {}
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
