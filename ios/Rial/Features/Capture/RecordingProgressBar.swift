//
//  RecordingProgressBar.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Progress bar for video recording duration (Story 7-14).
//

import SwiftUI

// MARK: - RecordingProgressBar

/// Progress bar showing video recording duration with 5-second warning indicator.
///
/// Displays a horizontal progress bar that fills from left to right as
/// recording progresses toward the maximum duration. The bar changes
/// color in the last 5 seconds to provide visual warning.
///
/// ## Key Features (AC-5)
/// - Shows elapsed time and remaining time (AC-5.1)
/// - Progress bar fills from 0 to maxDuration (AC-5.2)
/// - Color changes to yellow in last 5 seconds
/// - Smooth animation for real-time updates
///
/// ## Usage
/// ```swift
/// RecordingProgressBar(
///     currentDuration: viewModel.recordingDuration,
///     maxDuration: 15.0
/// )
/// ```
public struct RecordingProgressBar: View {
    /// Current recording duration in seconds
    let currentDuration: TimeInterval

    /// Maximum recording duration in seconds
    let maxDuration: TimeInterval

    /// Duration at which warning color activates (5 seconds remaining)
    private let warningThreshold: TimeInterval = 5.0

    /// Whether we're in the warning zone (< 5s remaining)
    private var isWarningZone: Bool {
        currentDuration >= (maxDuration - warningThreshold)
    }

    /// Progress from 0 to 1
    private var progress: Double {
        guard maxDuration > 0 else { return 0 }
        return min(currentDuration / maxDuration, 1.0)
    }

    /// Remaining time in seconds
    private var remainingTime: TimeInterval {
        max(maxDuration - currentDuration, 0)
    }

    public init(currentDuration: TimeInterval, maxDuration: TimeInterval) {
        self.currentDuration = currentDuration
        self.maxDuration = maxDuration
    }

    public var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 6)

                    // Progress fill
                    Capsule()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.linear(duration: 0.1), value: progress)
                }
            }
            .frame(height: 6)

            // Time labels
            HStack {
                // Elapsed
                Text(formatDuration(currentDuration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                // Remaining
                HStack(spacing: 2) {
                    if isWarningZone {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    Text("-\(formatDuration(remainingTime))")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(isWarningZone ? .yellow : .white.opacity(0.8))
                }
            }
        }
    }

    /// Progress bar fill color
    private var progressColor: Color {
        if isWarningZone {
            return .yellow
        }
        return .red
    }

    /// Format duration as "0:00" string
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Compact Recording Progress Bar

/// Minimal progress bar without time labels.
///
/// Useful when space is limited or time display is shown elsewhere.
public struct CompactRecordingProgressBar: View {
    let progress: Double
    var isWarning: Bool = false

    public init(progress: Double, isWarning: Bool = false) {
        self.progress = progress
        self.isWarning = isWarning
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)

                // Progress fill
                Capsule()
                    .fill(isWarning ? Color.yellow : Color.red)
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Preview

#if DEBUG
struct RecordingProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                // Normal progress (3s of 15s)
                RecordingProgressBar(
                    currentDuration: 3.0,
                    maxDuration: 15.0
                )
                .frame(width: 200)
                .previewDisplayName("3s of 15s")

                // Mid progress (8s of 15s)
                RecordingProgressBar(
                    currentDuration: 8.0,
                    maxDuration: 15.0
                )
                .frame(width: 200)
                .previewDisplayName("8s of 15s")

                // Warning zone (11s of 15s)
                RecordingProgressBar(
                    currentDuration: 11.0,
                    maxDuration: 15.0
                )
                .frame(width: 200)
                .previewDisplayName("11s of 15s - Warning")

                // Almost done (14s of 15s)
                RecordingProgressBar(
                    currentDuration: 14.0,
                    maxDuration: 15.0
                )
                .frame(width: 200)
                .previewDisplayName("14s of 15s - Warning")

                Divider()
                    .background(Color.white)

                // Compact versions
                HStack(spacing: 20) {
                    CompactRecordingProgressBar(progress: 0.3)
                        .frame(width: 60)

                    CompactRecordingProgressBar(progress: 0.8, isWarning: true)
                        .frame(width: 60)
                }
            }
            .padding()
        }
    }
}
#endif
