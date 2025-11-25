//
//  EvidenceSummaryView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Evidence summary for verified captures.
//

import SwiftUI

/// Summary of evidence collected for a capture.
struct EvidenceSummary: Sendable {
    let attestationVerified: Bool
    let depthAnalyzed: Bool
    let metadataValid: Bool
    let hasLocation: Bool
    let capturedAt: Date
    let deviceModel: String
}

/// View showing evidence summary for a verified capture.
///
/// Displays the verification checks performed on a capture
/// with status indicators for each check.
///
/// ## Usage
/// ```swift
/// EvidenceSummaryView(summary: evidenceSummary)
/// ```
struct EvidenceSummaryView: View {
    let summary: EvidenceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Evidence Summary")
                .font(.headline)

            VStack(spacing: 12) {
                EvidenceRow(
                    title: "Hardware Attestation",
                    subtitle: "Verified by Apple DCAppAttest",
                    isVerified: summary.attestationVerified
                )

                EvidenceRow(
                    title: "LiDAR Depth Analysis",
                    subtitle: "3D depth map captured",
                    isVerified: summary.depthAnalyzed
                )

                EvidenceRow(
                    title: "Metadata Validation",
                    subtitle: "Photo hash and timestamps valid",
                    isVerified: summary.metadataValid
                )

                EvidenceRow(
                    title: "Location Data",
                    subtitle: summary.hasLocation ? "GPS coordinates captured" : "Location not available",
                    isVerified: summary.hasLocation
                )
            }

            Divider()

            // Capture details
            VStack(alignment: .leading, spacing: 8) {
                Text("Capture Details")
                    .font(.subheadline)
                    .fontWeight(.medium)

                DetailRow(label: "Captured", value: formattedDate)
                DetailRow(label: "Device", value: summary.deviceModel)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: summary.capturedAt)
    }
}

/// Row showing a single evidence check.
struct EvidenceRow: View {
    let title: String
    let subtitle: String
    let isVerified: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isVerified ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isVerified ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

/// Row showing a detail key-value pair.
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct EvidenceSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        EvidenceSummaryView(
            summary: EvidenceSummary(
                attestationVerified: true,
                depthAnalyzed: true,
                metadataValid: true,
                hasLocation: true,
                capturedAt: Date(),
                deviceModel: "iPhone 15 Pro"
            )
        )
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
