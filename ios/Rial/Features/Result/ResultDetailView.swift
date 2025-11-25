//
//  ResultDetailView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Detail view for a single capture with verification results.
//

import SwiftUI

/// Detail view for a single capture.
///
/// Shows the full photo with zoom capability, verification status,
/// confidence badge, and evidence summary for uploaded captures.
///
/// ## Features
/// - Full photo with pinch-to-zoom
/// - Confidence badge for verified captures
/// - Evidence summary with verification checks
/// - Share button for verification URL
/// - Status display for pending/failed uploads
///
/// ## Usage
/// ```swift
/// NavigationLink {
///     ResultDetailView(capture: capture)
/// } label: {
///     CaptureThumbnailView(capture: capture)
/// }
/// ```
struct ResultDetailView: View {
    let capture: CaptureHistoryItem

    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Photo with zoom
                ZoomableImageView(image: capture.thumbnail)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Status-dependent content
                statusContent
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Capture Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = capture.verificationUrl {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Status Content

    @ViewBuilder
    private var statusContent: some View {
        switch capture.status {
        case .uploaded:
            uploadedContent
        case .uploading:
            uploadingContent
        case .pending, .processing:
            pendingContent
        case .paused:
            pausedContent
        case .failed:
            failedContent
        }
    }

    private var uploadedContent: some View {
        VStack(spacing: 16) {
            // Confidence badge
            ConfidenceBadge(level: .high) // Would come from actual server response

            // Evidence summary
            EvidenceSummaryView(
                summary: EvidenceSummary(
                    attestationVerified: true,
                    depthAnalyzed: true,
                    metadataValid: true,
                    hasLocation: true,
                    capturedAt: capture.createdAt,
                    deviceModel: "iPhone Pro" // Would come from actual capture
                )
            )

            // Verification link
            if let urlString = capture.verificationUrl,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "link")
                        Text("View Verification Page")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var uploadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Uploading...")
                .font(.headline)
            Text("Your capture is being uploaded and verified")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }

    private var pendingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("Pending Upload")
                .font(.headline)
            Text("This capture will be uploaded when network is available")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }

    private var pausedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Upload Paused")
                .font(.headline)
            Text("Upload will resume automatically")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }

    private var failedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Upload Failed")
                .font(.headline)
            Text("Pull down to retry uploading this capture")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                // Retry would be handled by parent view model
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry Upload")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 32)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if capture.status == .uploaded, capture.verificationUrl != nil {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}

// MARK: - Share Sheet

/// UIKit share sheet wrapper for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#if DEBUG
struct ResultDetailView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                ResultDetailView(capture: .preview(status: .uploaded))
            }
            .previewDisplayName("Uploaded")

            NavigationView {
                ResultDetailView(capture: .preview(status: .uploading))
            }
            .previewDisplayName("Uploading")

            NavigationView {
                ResultDetailView(capture: .preview(status: .failed))
            }
            .previewDisplayName("Failed")
        }
    }
}
#endif
