//
//  PrivacyModeIndicator.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Privacy mode indicator for capture screen (Story 8-2).
//  Shows visual indicator when privacy mode is active.
//

import SwiftUI

// MARK: - PrivacyModeIndicator

/// Visual indicator showing privacy mode is active on capture screen.
///
/// ## Features (AC #5)
/// - Visible only when privacy mode is enabled
/// - Unobtrusive but clearly visible
/// - Uses shield icon for consistent iconography
/// - Tap navigates to privacy settings
/// - Subtle appear animation
///
/// ## Usage
/// ```swift
/// if privacySettings.isPrivacyModeEnabled {
///     PrivacyModeIndicator(onTap: { showSettings = true })
/// }
/// ```
public struct PrivacyModeIndicator: View {
    /// Action to perform when indicator is tapped
    var onTap: () -> Void

    /// Haptic feedback generator
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    /// Animation state for appear effect
    @State private var isVisible = false

    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            impactFeedback.impactOccurred()
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 14, weight: .semibold))

                Text("Privacy")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.8))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(IndicatorButtonStyle())
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
        .accessibilityLabel("Privacy Mode Active")
        .accessibilityHint("Double tap to open privacy settings")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Indicator Button Style

/// Custom button style for privacy indicator with press feedback.
private struct IndicatorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Compact Privacy Indicator

/// Compact version of privacy indicator showing only the shield icon.
///
/// Useful for space-constrained layouts like video recording overlay.
public struct CompactPrivacyIndicator: View {
    var onTap: () -> Void

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    @State private var isVisible = false

    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            impactFeedback.impactOccurred()
            onTap()
        } label: {
            Image(systemName: "shield.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(IndicatorButtonStyle())
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
        .accessibilityLabel("Privacy Mode Active")
        .accessibilityHint("Double tap to open privacy settings")
    }
}

// MARK: - Preview

#if DEBUG
struct PrivacyModeIndicator_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                // Standard indicator
                PrivacyModeIndicator(onTap: {})

                // Compact indicator
                CompactPrivacyIndicator(onTap: {})

                // In context (simulated capture screen header)
                HStack {
                    PrivacyModeIndicator(onTap: {})
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.5))
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
