//
//  PartialVideoBadge.swift
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  Badge for displaying partial video verification status.
//

import SwiftUI

/// Badge showing partial video verification information.
///
/// Displays "Verified: Xs of Ys recorded" for interrupted video recordings
/// that were successfully attested at a checkpoint boundary.
///
/// ## Usage
/// ```swift
/// if let attestation = videoResult.attestation, attestation.isPartial {
///     PartialVideoBadge(
///         verifiedDuration: TimeInterval(attestation.durationMs) / 1000.0,
///         totalDuration: videoResult.duration,
///         checkpointIndex: attestation.checkpointIndex ?? 0
///     )
/// }
/// ```
struct PartialVideoBadge: View {
    /// Verified duration in seconds (from checkpoint)
    let verifiedDuration: TimeInterval

    /// Total recording duration in seconds (including unverified portion)
    let totalDuration: TimeInterval

    /// Checkpoint index (0=5s, 1=10s, 2=15s)
    let checkpointIndex: Int

    var body: some View {
        VStack(spacing: 8) {
            // Main verification badge
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Partial Verification")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Verified: \(formatDuration(verifiedDuration)) of \(formatDuration(totalDuration)) recorded")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Checkpoint info
            HStack(spacing: 4) {
                Image(systemName: "flag.checkered")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Checkpoint \(checkpointIndex) (\(formatDuration(verifiedDuration)))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(verifiedDuration * 30)) frames verified")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Helpers

    /// Format duration as "Xs" or "XmYs"
    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m\(remainingSeconds)s"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PartialVideoBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // 10s of 12s recorded (checkpoint 1)
            PartialVideoBadge(
                verifiedDuration: 10.0,
                totalDuration: 12.0,
                checkpointIndex: 1
            )
            .previewDisplayName("10s of 12s")

            // 5s of 7s recorded (checkpoint 0)
            PartialVideoBadge(
                verifiedDuration: 5.0,
                totalDuration: 7.0,
                checkpointIndex: 0
            )
            .previewDisplayName("5s of 7s")
        }
        .padding()
    }
}
#endif
