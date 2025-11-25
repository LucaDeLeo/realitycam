//
//  ConfidenceBadge.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Confidence level badge for capture verification.
//

import SwiftUI

/// Confidence level from backend verification.
enum ConfidenceLevel: String, Codable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case suspicious = "SUSPICIOUS"
    case unknown = "UNKNOWN"

    /// Display color for confidence level
    var color: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .yellow
        case .low:
            return .orange
        case .suspicious:
            return .red
        case .unknown:
            return .gray
        }
    }

    /// SF Symbol icon for confidence level
    var icon: String {
        switch self {
        case .high:
            return "checkmark.seal.fill"
        case .medium:
            return "checkmark.circle.fill"
        case .low:
            return "exclamationmark.circle.fill"
        case .suspicious:
            return "xmark.octagon.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    /// Display title
    var title: String {
        switch self {
        case .high:
            return "Verified"
        case .medium:
            return "Partially Verified"
        case .low:
            return "Low Confidence"
        case .suspicious:
            return "Verification Failed"
        case .unknown:
            return "Pending"
        }
    }

    /// Description of what the confidence level means
    var description: String {
        switch self {
        case .high:
            return "All verification checks passed"
        case .medium:
            return "Some verification checks incomplete"
        case .low:
            return "Verification concerns detected"
        case .suspicious:
            return "Photo may have been modified"
        case .unknown:
            return "Verification in progress"
        }
    }
}

/// Badge showing confidence level.
///
/// Displays a colored badge with icon indicating the verification
/// confidence level of a capture.
///
/// ## Usage
/// ```swift
/// ConfidenceBadge(level: .high)
/// ```
struct ConfidenceBadge: View {
    let level: ConfidenceLevel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: level.icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(level.title)
                    .font(.headline)
                Text(level.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level.color.opacity(0.15))
        .foregroundColor(level.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(level.color.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Compact confidence indicator for list views.
struct ConfidenceIndicator: View {
    let level: ConfidenceLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(level.color)
                .frame(width: 8, height: 8)
            Text(level.title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ConfidenceBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ConfidenceBadge(level: .high)
            ConfidenceBadge(level: .medium)
            ConfidenceBadge(level: .low)
            ConfidenceBadge(level: .suspicious)
            ConfidenceBadge(level: .unknown)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
