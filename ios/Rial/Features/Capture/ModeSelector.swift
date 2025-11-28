//
//  ModeSelector.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Photo/Video mode selector for capture screen (Story 7-14).
//

import SwiftUI

// MARK: - CaptureMode

/// Capture mode for photo or video recording.
///
/// Persisted to UserDefaults with key `app.rial.captureMode` so that
/// user preference survives app restarts.
public enum CaptureMode: String, CaseIterable {
    case photo
    case video

    /// Display label for the mode selector
    var label: String {
        switch self {
        case .photo:
            return "Photo"
        case .video:
            return "Video"
        }
    }

    /// System image for the mode
    var systemImage: String {
        switch self {
        case .photo:
            return "camera"
        case .video:
            return "video"
        }
    }
}

// MARK: - ModeSelector

/// Segmented control for switching between Photo and Video capture modes.
///
/// Positioned at the top or bottom of the capture screen, allows users
/// to switch between photo and video capture modes. The selector is
/// disabled during active capture or recording.
///
/// ## Key Behaviors
/// - Mode preference persisted to UserDefaults (AC-1.5)
/// - Disabled during capture/recording (AC-1.4)
/// - Clear visual highlighting of current mode (AC-1.3)
/// - ARSession continues running without restart on mode switch (AC-9.3)
///
/// ## Usage
/// ```swift
/// ModeSelector(
///     currentMode: $viewModel.currentMode,
///     isDisabled: viewModel.isCapturing || viewModel.isRecordingVideo
/// )
/// ```
public struct ModeSelector: View {
    /// Current capture mode binding
    @Binding var currentMode: CaptureMode

    /// Whether the selector is disabled
    var isDisabled: Bool = false

    /// Haptic feedback generator
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init(currentMode: Binding<CaptureMode>, isDisabled: Bool = false) {
        self._currentMode = currentMode
        self.isDisabled = isDisabled
    }

    public var body: some View {
        Picker("Capture Mode", selection: $currentMode) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                HStack(spacing: 6) {
                    Image(systemName: mode.systemImage)
                        .font(.caption)
                    Text(mode.label)
                        .font(.subheadline.weight(.medium))
                }
                .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 60)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .padding(.horizontal, 40)
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .onChange(of: currentMode) { _ in
            impactFeedback.impactOccurred()
        }
        .accessibilityLabel("Capture mode: \(currentMode.label)")
        .accessibilityHint(isDisabled ? "Cannot change mode during capture" : "Double tap to change capture mode")
    }
}

// MARK: - Compact Mode Selector

/// Compact mode selector for space-constrained layouts.
///
/// Uses icon-only buttons instead of segmented control.
/// Useful for overlaying on camera preview with minimal obstruction.
public struct CompactModeSelector: View {
    @Binding var currentMode: CaptureMode
    var isDisabled: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init(currentMode: Binding<CaptureMode>, isDisabled: Bool = false) {
        self._currentMode = currentMode
        self.isDisabled = isDisabled
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button {
                    impactFeedback.impactOccurred()
                    currentMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.title3)
                        .foregroundColor(currentMode == mode ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            currentMode == mode
                                ? Color.white.opacity(0.2)
                                : Color.clear
                        )
                }
                .disabled(isDisabled)
            }
        }
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
        .opacity(isDisabled ? 0.5 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture mode: \(currentMode.label)")
    }
}

// MARK: - Preview

#if DEBUG
struct ModeSelector_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                // Standard selector - photo mode
                ModeSelector(currentMode: .constant(.photo))

                // Standard selector - video mode
                ModeSelector(currentMode: .constant(.video))

                // Standard selector - disabled
                ModeSelector(currentMode: .constant(.video), isDisabled: true)

                // Compact selector - photo mode
                CompactModeSelector(currentMode: .constant(.photo))

                // Compact selector - video mode
                CompactModeSelector(currentMode: .constant(.video))
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
