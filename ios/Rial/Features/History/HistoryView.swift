//
//  HistoryView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Main capture history view with grid of thumbnails.
//

import SwiftUI
import os.log

/// Main capture history view displaying grid of capture thumbnails.
///
/// ## Features
/// - 3-column adaptive grid layout
/// - Status badges on each thumbnail
/// - Pull-to-refresh for retry
/// - Empty state with capture CTA
/// - Navigation to detail view
/// - Auto-navigation from Capture tab after save
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     HistoryView()
/// }
/// ```
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @EnvironmentObject private var navigationState: AppNavigationState

    /// Navigation action for capture
    var onNavigateToCapture: (() -> Void)?

    /// Selected capture for programmatic navigation
    @State private var selectedCapture: CaptureHistoryItem?

    /// Whether navigation is active (for programmatic navigation)
    @State private var isNavigationActive = false

    /// 3-column adaptive grid
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
    ]

    /// Whether there are any pending or failed uploads
    private var hasPendingUploads: Bool {
        viewModel.captures.contains { $0.status == .pending || $0.status == .failed }
    }

    var body: some View {
        navigationWrapper {
            Group {
                if viewModel.isLoading && viewModel.captures.isEmpty {
                    loadingView
                } else if viewModel.captures.isEmpty {
                    EmptyHistoryView(onCaptureTap: onNavigateToCapture)
                } else {
                    captureGrid
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if hasPendingUploads {
                        Button {
                            Task {
                                await viewModel.retryFailedUploads()
                            }
                        } label: {
                            Label("Upload All", systemImage: "arrow.up.circle")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { onNavigateToCapture?() }) {
                        Image(systemName: "camera")
                    }
                }
            }
            .refreshable {
                await viewModel.retryFailedUploads()
            }
            .task {
                await viewModel.loadCaptures()
            }
            .onChange(of: navigationState.pendingCaptureId) { newId in
                // Handle pending navigation from Capture tab
                handlePendingNavigation(captureId: newId)
            }
            .onAppear {
                // Check for pending navigation on appear
                if let pendingId = navigationState.pendingCaptureId {
                    handlePendingNavigation(captureId: pendingId)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    /// Handle pending navigation to a specific capture
    private func handlePendingNavigation(captureId: UUID?) {
        guard let captureId = captureId else { return }

        Task {
            // First, reset navigation state to pop back if we're currently in a detail view
            // This is critical for back-to-back captures where we might still be viewing the previous one
            if isNavigationActive {
                await MainActor.run {
                    isNavigationActive = false
                    selectedCapture = nil
                }
                // Wait for SwiftUI to process the navigation state reset
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            // Retry up to 5 times with 500ms delay to allow save to complete
            for attempt in 1...5 {
                // Reload captures
                await viewModel.loadCaptures()

                // Check if capture is now in list
                if let capture = viewModel.captures.first(where: { $0.id == captureId }) {
                    await MainActor.run {
                        selectedCapture = capture
                        isNavigationActive = true
                        navigationState.clearPendingNavigation()
                    }
                    return
                }

                // Wait before retrying
                if attempt < 5 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                }
            }

            // Give up after retries - clear pending to avoid stuck state
            await MainActor.run {
                navigationState.clearPendingNavigation()
            }
        }
    }

    // MARK: - Navigation Wrapper

    @ViewBuilder
    private func navigationWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                ZStack {
                    content()
                    // Hidden NavigationLink for programmatic navigation
                    NavigationLink(
                        destination: selectedCapture.map { ResultDetailView(capture: $0) },
                        isActive: $isNavigationActive
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        } else {
            NavigationView {
                ZStack {
                    content()
                    // Hidden NavigationLink for programmatic navigation (iOS 15)
                    NavigationLink(
                        destination: selectedCapture.map { ResultDetailView(capture: $0) },
                        isActive: $isNavigationActive
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading captures...")
                .foregroundColor(.secondary)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Capture Grid

    private var captureGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.captures) { capture in
                    NavigationLink {
                        ResultDetailView(capture: capture)
                    } label: {
                        CaptureThumbnailView(capture: capture)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        contextMenuItems(for: capture)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for capture: CaptureHistoryItem) -> some View {
        if capture.status == .failed || capture.status == .pending {
            Button {
                Task {
                    await viewModel.retryFailedUploads()
                }
            } label: {
                Label("Upload Now", systemImage: "arrow.up.circle")
            }
        }

        if let url = capture.verificationUrl {
            Button {
                shareVerificationLink(url)
            } label: {
                Label("Share Verification Link", systemImage: "square.and.arrow.up")
            }
        }

        Button(role: .destructive) {
            Task {
                await viewModel.deleteCapture(capture.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Share

    private func shareVerificationLink(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }

        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // Present share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HistoryView()
                .previewDisplayName("Empty")

            HistoryViewWithMockData()
                .previewDisplayName("With Data")
        }
    }
}

struct HistoryViewWithMockData: View {
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(0..<8) { index in
                        CaptureThumbnailView(
                            capture: .preview(
                                status: CaptureStatus.allCases[index % 4]
                            )
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("History")
        }
        .navigationViewStyle(.stack)
    }
}
#endif
