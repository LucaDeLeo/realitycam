//
//  VideoPreviewSheet.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Video playback preview with Use/Retake options (Story 7-14).
//

import SwiftUI
import AVKit

// MARK: - VideoPreviewSheet

/// Video preview sheet with playback controls and Use/Retake buttons.
///
/// Displays the recorded video with native AVPlayer controls,
/// optional depth overlay toggle, and action buttons to save or discard.
///
/// ## Key Features (AC-7)
/// - Video player with native controls (AC-7.1, AC-7.2)
/// - Depth overlay toggle (AC-7.3)
/// - "Use Video" saves and uploads (AC-7.4)
/// - "Retake" discards and returns to capture (AC-7.5)
/// - Swipe-to-dismiss gesture (AC-7.6)
/// - Partial video indicator when recording was interrupted (AC-8)
///
/// ## Usage
/// ```swift
/// .sheet(isPresented: $viewModel.showVideoPreview) {
///     VideoPreviewSheet(
///         result: viewModel.lastVideoResult,
///         onUseVideo: { viewModel.useVideo() },
///         onRetake: { viewModel.discardVideo() }
///     )
/// }
/// ```
public struct VideoPreviewSheet: View {
    /// Video recording result to preview
    let result: VideoRecordingResult?

    /// Action when user taps "Use Video"
    let onUseVideo: () -> Void

    /// Action when user taps "Retake"
    let onRetake: () -> Void

    /// Whether upload is in progress
    var isUploading: Bool = false

    /// Current upload progress (0.0 - 1.0)
    var uploadProgress: Double = 0.0

    /// Upload error message (if any)
    var uploadError: String?

    /// Action to retry failed upload
    var onRetryUpload: (() -> Void)?

    /// AVPlayer instance for video playback
    @State private var player: AVPlayer?

    /// Whether depth overlay is shown in preview
    @State private var showDepthOverlay = false

    public init(
        result: VideoRecordingResult?,
        onUseVideo: @escaping () -> Void,
        onRetake: @escaping () -> Void,
        isUploading: Bool = false,
        uploadProgress: Double = 0.0,
        uploadError: String? = nil,
        onRetryUpload: (() -> Void)? = nil
    ) {
        self.result = result
        self.onUseVideo = onUseVideo
        self.onRetake = onRetake
        self.isUploading = isUploading
        self.uploadProgress = uploadProgress
        self.uploadError = uploadError
        self.onRetryUpload = onRetryUpload
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Video Player
                if let result = result {
                    videoPlayerSection(result: result)
                } else {
                    noVideoPlaceholder
                }

                // Partial video indicator (AC-8)
                if let result = result, result.isPartial {
                    partialVideoIndicator(result: result)
                }

                // Upload progress (AC-6)
                if isUploading {
                    uploadProgressSection
                }

                // Upload error
                if let error = uploadError {
                    uploadErrorSection(error: error)
                }

                Spacer()

                // Action buttons
                actionButtons
            }
            .padding()
            .navigationTitle("Video Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onRetake()
                    }
                    .disabled(isUploading)
                }
            }
        }
        .modifier(SheetPresentationModifier())
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Video Player Section

    @ViewBuilder
    private func videoPlayerSection(result: VideoRecordingResult) -> some View {
        ZStack {
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(12)
            } else {
                loadingPlaceholder
            }

            // Depth overlay (rendered on top, not in video)
            // Note: In a full implementation, this would show depth visualization
            // overlaid on the video preview. For now, it's a placeholder.
            if showDepthOverlay {
                DepthPreviewOverlay()
            }
        }

        // Video info and overlay toggle
        HStack {
            // Duration badge
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                Text(formatDuration(result.duration))
                    .font(.caption.monospacedDigit())
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .cornerRadius(6)

            // Frame count
            HStack(spacing: 4) {
                Image(systemName: "film")
                    .font(.caption)
                Text("\(result.frameCount) frames")
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            Spacer()

            // Depth overlay toggle (AC-7.3)
            Button {
                showDepthOverlay.toggle()
            } label: {
                Image(systemName: showDepthOverlay ? "eye" : "eye.slash")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityLabel(showDepthOverlay ? "Hide depth overlay" : "Show depth overlay")
        }
    }

    // MARK: - Partial Video Indicator

    @ViewBuilder
    private func partialVideoIndicator(result: VideoRecordingResult) -> some View {
        let verifiedDuration = result.verifiedDuration
        let totalDuration = result.duration

        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Partial Recording")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)

                Text("Verified: \(formatDuration(verifiedDuration)) of \(formatDuration(totalDuration)) recorded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Upload Progress Section

    private var uploadProgressSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Uploading video...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(uploadProgress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            ProgressView(value: uploadProgress)
                .progressViewStyle(LinearProgressViewStyle())
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Upload Error Section

    private func uploadErrorSection(error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            if let retry = onRetryUpload {
                Button("Retry") {
                    retry()
                }
                .font(.subheadline.bold())
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 40) {
            // Retake button
            Button {
                onRetake()
            } label: {
                Text("Retake")
                    .font(.title3)
                    .foregroundColor(.red)
            }
            .disabled(isUploading)
            .opacity(isUploading ? 0.5 : 1.0)

            // Use Video button
            Button {
                onUseVideo()
            } label: {
                Text("Use Video")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(isUploading)
            .opacity(isUploading ? 0.5 : 1.0)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Placeholders

    private var noVideoPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No video available")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading preview...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .cornerRadius(12)
    }

    // MARK: - Helper Methods

    private func setupPlayer() {
        guard let result = result else { return }
        player = AVPlayer(url: result.videoURL)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Depth Preview Overlay

/// Placeholder overlay for depth visualization in video preview.
///
/// In a full implementation, this would render depth keyframe data
/// synchronized with video playback. For Story 7-14, this is a
/// visual placeholder to demonstrate the overlay toggle functionality.
private struct DepthPreviewOverlay: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.cyan.opacity(0.3),
                        Color.purple.opacity(0.3)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Preview

#if DEBUG
struct VideoPreviewSheet_Previews: PreviewProvider {
    static var previews: some View {
        // Normal preview
        VideoPreviewSheet(
            result: nil,
            onUseVideo: {},
            onRetake: {}
        )
        .previewDisplayName("No Video")

        // With upload progress
        VideoPreviewSheet(
            result: nil,
            onUseVideo: {},
            onRetake: {},
            isUploading: true,
            uploadProgress: 0.65
        )
        .previewDisplayName("Uploading")

        // With error
        VideoPreviewSheet(
            result: nil,
            onUseVideo: {},
            onRetake: {},
            uploadError: "Network connection lost",
            onRetryUpload: {}
        )
        .previewDisplayName("Upload Error")
    }
}
#endif
