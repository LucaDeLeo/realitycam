//
//  CaptureThumbnailView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Thumbnail cell for capture history grid.
//

import SwiftUI

/// Display item for capture history.
struct CaptureHistoryItem: Identifiable {
    let id: UUID
    let thumbnail: UIImage?
    let status: CaptureStatus
    let createdAt: Date
    let serverCaptureId: UUID?
    let verificationUrl: String?
}

/// Thumbnail view for a single capture in history grid.
///
/// Shows capture thumbnail with status badge overlay.
/// Badges indicate upload state: uploaded, uploading, pending, failed.
///
/// ## Usage
/// ```swift
/// LazyVGrid(columns: columns) {
///     ForEach(captures) { capture in
///         CaptureThumbnailView(capture: capture)
///     }
/// }
/// ```
struct CaptureThumbnailView: View {
    let capture: CaptureHistoryItem

    /// Thumbnail size
    private let thumbnailSize: CGFloat = 100

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail image
            thumbnailImage
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Status badge
            statusBadge
                .padding(4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailImage: some View {
        if let thumbnail = capture.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                        .font(.title)
                )
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch capture.status {
        case .uploaded:
            StatusBadge(
                icon: "checkmark.circle.fill",
                color: .green
            )
        case .uploading:
            StatusBadge(
                icon: "arrow.up.circle.fill",
                color: .blue
            )
        case .pending, .processing:
            StatusBadge(
                icon: "clock.fill",
                color: .gray
            )
        case .failed:
            StatusBadge(
                icon: "exclamationmark.circle.fill",
                color: .red
            )
        case .paused:
            StatusBadge(
                icon: "pause.circle.fill",
                color: .orange
            )
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let dateString = dateFormatter.string(from: capture.createdAt)
        let statusString: String

        switch capture.status {
        case .uploaded:
            statusString = "Uploaded"
        case .uploading:
            statusString = "Uploading"
        case .pending:
            statusString = "Pending upload"
        case .processing:
            statusString = "Processing"
        case .paused:
            statusString = "Paused"
        case .failed:
            statusString = "Upload failed"
        }

        return "Capture from \(dateString), \(statusString)"
    }
}

// MARK: - Status Badge

/// Small circular badge showing status.
struct StatusBadge: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(4)
            .background(color)
            .clipShape(Circle())
            .shadow(radius: 2)
    }
}

// MARK: - Preview

#if DEBUG
struct CaptureThumbnailView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                CaptureThumbnailView(capture: .preview(status: .uploaded))
                CaptureThumbnailView(capture: .preview(status: .uploading))
            }
            HStack(spacing: 20) {
                CaptureThumbnailView(capture: .preview(status: .pending))
                CaptureThumbnailView(capture: .preview(status: .failed))
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

extension CaptureHistoryItem {
    static func preview(status: CaptureStatus) -> CaptureHistoryItem {
        CaptureHistoryItem(
            id: UUID(),
            thumbnail: nil,
            status: status,
            createdAt: Date(),
            serverCaptureId: status == .uploaded ? UUID() : nil,
            verificationUrl: status == .uploaded ? "https://verify.rial.app/abc123" : nil
        )
    }
}
#endif
