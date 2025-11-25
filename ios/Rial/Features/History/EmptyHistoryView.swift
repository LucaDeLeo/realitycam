//
//  EmptyHistoryView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Empty state view when no captures exist.
//

import SwiftUI

/// Empty state view for history when no captures exist.
///
/// Displays a friendly message and CTA to start capturing.
///
/// ## Usage
/// ```swift
/// if captures.isEmpty {
///     EmptyHistoryView(onCaptureTap: navigateToCapture)
/// }
/// ```
struct EmptyHistoryView: View {
    /// Action when "Start Capturing" button is tapped
    var onCaptureTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.6))

            // Title
            Text("No Captures Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            // Description
            Text("Take your first authenticated photo with LiDAR depth verification.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // CTA button
            if let onCaptureTap = onCaptureTap {
                Button(action: onCaptureTap) {
                    HStack {
                        Image(systemName: "camera")
                        Text("Start Capturing")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview

#if DEBUG
struct EmptyHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EmptyHistoryView(onCaptureTap: { print("Capture tapped") })
                .previewDisplayName("With CTA")

            EmptyHistoryView(onCaptureTap: nil)
                .previewDisplayName("Without CTA")
        }
    }
}
#endif
