//
//  UploadProgressView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Upload progress indicator for video captures (Story 7-14).
//

import SwiftUI

// MARK: - UploadProgressView

/// Upload progress indicator for video captures (AC-6).
///
/// Displays upload progress as a percentage with a progress bar,
/// upload status text with MB transferred, and error handling with retry.
///
/// ## Key Features
/// - Progress indicator shows upload percentage (0-100%) (AC-6.1)
/// - Upload status text with current/total MB (AC-6.2)
/// - Progress bar or circular indicator (AC-6.3)
/// - Error state with retry option (AC-6.5)
///
/// ## Usage
/// ```swift
/// UploadProgressView(
///     isUploading: viewModel.isUploading,
///     progress: viewModel.uploadProgress,
///     totalBytes: captureSize,
///     error: viewModel.uploadError,
///     onRetry: { viewModel.retryUpload() },
///     onCancel: { viewModel.cancelUpload() }
/// )
/// ```
public struct UploadProgressView: View {
    /// Whether upload is in progress
    let isUploading: Bool

    /// Upload progress (0.0 - 1.0)
    let progress: Double

    /// Total bytes to upload (for MB display)
    var totalBytes: Int64 = 0

    /// Error message (if any)
    var error: String?

    /// Action to retry failed upload
    var onRetry: (() -> Void)?

    /// Action to cancel upload
    var onCancel: (() -> Void)?

    public init(
        isUploading: Bool,
        progress: Double,
        totalBytes: Int64 = 0,
        error: String? = nil,
        onRetry: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.isUploading = isUploading
        self.progress = progress
        self.totalBytes = totalBytes
        self.error = error
        self.onRetry = onRetry
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let error = error {
                errorView(error: error)
            } else if isUploading {
                uploadingView
            } else if progress >= 1.0 {
                completedView
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
    }

    // MARK: - Uploading View

    private var uploadingView: some View {
        VStack(spacing: 10) {
            // Header with icon and status
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.title3)
                    .foregroundColor(.blue)

                Text("Uploading video...")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                Spacer()

                // Percentage
                Text("\(Int(progress * 100))%")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundColor(.blue)
            }

            // Progress bar
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))

            // MB progress text
            HStack {
                if totalBytes > 0 {
                    let uploadedBytes = Int64(Double(totalBytes) * progress)
                    Text("\(formatBytes(uploadedBytes)) / \(formatBytes(totalBytes))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Cancel button
                if let cancel = onCancel {
                    Button("Cancel") {
                        cancel()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Error View

    private func errorView(error: String) -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Upload failed")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Retry button
            if let retry = onRetry {
                Button {
                    retry()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Upload")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Completed View

    private var completedView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)

            Text("Upload complete")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        if error != nil {
            return Color.red.opacity(0.1)
        } else if progress >= 1.0 {
            return Color.green.opacity(0.1)
        } else {
            return Color(.systemGray6)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Compact Upload Progress View

/// Compact upload progress indicator for use in list views.
///
/// Shows a minimal progress bar and percentage without
/// detailed status text. Suitable for history list items.
public struct CompactUploadProgressView: View {
    let progress: Double
    var error: Bool = false

    public init(progress: Double, error: Bool = false) {
        self.progress = progress
        self.error = error
    }

    public var body: some View {
        HStack(spacing: 8) {
            if error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)

                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if progress >= 1.0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)

                Text("Uploaded")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(width: 60)

                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Circular Upload Progress View

/// Circular upload progress indicator.
///
/// Shows progress as a circular gauge. Useful for overlaying
/// on thumbnails or in space-constrained layouts.
public struct CircularUploadProgressView: View {
    let progress: Double
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4

    public init(progress: Double, size: CGFloat = 40, lineWidth: CGFloat = 4) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)

            // Percentage or checkmark
            if progress >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundColor(.green)
            } else {
                Text("\(Int(progress * 100))")
                    .font(.system(size: size * 0.25, weight: .semibold).monospacedDigit())
                    .foregroundColor(.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#if DEBUG
struct UploadProgressView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Uploading
            UploadProgressView(
                isUploading: true,
                progress: 0.45,
                totalBytes: 35_000_000,
                onCancel: {}
            )

            // Error
            UploadProgressView(
                isUploading: false,
                progress: 0.3,
                error: "Network connection lost",
                onRetry: {}
            )

            // Completed
            UploadProgressView(
                isUploading: false,
                progress: 1.0
            )

            Divider()

            // Compact variants
            HStack(spacing: 20) {
                CompactUploadProgressView(progress: 0.65)
                CompactUploadProgressView(progress: 1.0)
                CompactUploadProgressView(progress: 0.3, error: true)
            }

            Divider()

            // Circular variants
            HStack(spacing: 20) {
                CircularUploadProgressView(progress: 0.25)
                CircularUploadProgressView(progress: 0.65)
                CircularUploadProgressView(progress: 1.0)
            }
        }
        .padding()
    }
}
#endif
