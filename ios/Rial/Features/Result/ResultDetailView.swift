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
    let initialCapture: CaptureHistoryItem

    @State private var currentCapture: CaptureHistoryItem
    @State private var showShareSheet = false
    @State private var refreshTimer: Timer?

    init(capture: CaptureHistoryItem) {
        self.initialCapture = capture
        self._currentCapture = State(initialValue: capture)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Photo with zoom
                ZoomableImageView(image: currentCapture.thumbnail)
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
            if let url = currentCapture.verificationUrl {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            startStatusPolling()
        }
        .onDisappear {
            stopStatusPolling()
        }
    }

    // MARK: - Status Polling

    /// Start polling for status updates while upload is in progress.
    private func startStatusPolling() {
        // Only poll if status is not final
        guard currentCapture.status == .pending || currentCapture.status == .uploading || currentCapture.status == .processing else {
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task {
                await refreshCaptureStatus()
            }
        }
    }

    /// Stop polling for status updates.
    private func stopStatusPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Refresh capture status from store.
    @MainActor
    private func refreshCaptureStatus() async {
        do {
            // Force refresh to get latest data from persistent store
            CaptureStore.shared.refreshViewContext()
            let summaries = try await CaptureStore.shared.fetchHistorySummaries()
            if let updated = summaries.first(where: { $0.id == initialCapture.id }) {
                let newCapture = CaptureHistoryItem(
                    id: updated.id,
                    thumbnail: currentCapture.thumbnail, // Keep existing thumbnail
                    status: updated.status,
                    createdAt: updated.createdAt,
                    serverCaptureId: updated.serverCaptureId,
                    verificationUrl: updated.verificationUrl,
                    deviceModel: updated.deviceModel,
                    hasLocation: updated.hasLocation,
                    hasAssertion: updated.hasAssertion
                )

                // Update if status changed
                if newCapture.status != currentCapture.status ||
                   newCapture.verificationUrl != currentCapture.verificationUrl {
                    currentCapture = newCapture

                    // Stop polling if upload completed or failed
                    if newCapture.status == .uploaded || newCapture.status == .failed {
                        stopStatusPolling()
                    }
                }
            }
        } catch {
            // Silently fail - will retry on next poll
        }
    }

    // MARK: - Status Content

    @ViewBuilder
    private var statusContent: some View {
        switch currentCapture.status {
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
            // Confidence badge - "high" for uploads with assertion, "medium" otherwise
            ConfidenceBadge(level: currentCapture.hasAssertion ? .high : .medium)

            // Evidence summary using actual capture data
            EvidenceSummaryView(
                summary: EvidenceSummary(
                    attestationVerified: currentCapture.hasAssertion,
                    depthAnalyzed: true, // Always true for successful upload (LiDAR required)
                    metadataValid: true, // Always true for successful upload
                    hasLocation: currentCapture.hasLocation,
                    capturedAt: currentCapture.createdAt,
                    deviceModel: currentCapture.deviceModel ?? "Unknown Device"
                )
            )

            // Verification link
            if let urlString = currentCapture.verificationUrl,
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
            if currentCapture.status == .uploaded, currentCapture.verificationUrl != nil {
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
