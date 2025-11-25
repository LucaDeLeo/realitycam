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
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     HistoryView()
/// }
/// ```
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    /// Navigation action for capture
    var onNavigateToCapture: (() -> Void)?

    /// 3-column adaptive grid
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
    ]

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
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Navigation Wrapper

    @ViewBuilder
    private func navigationWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
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
        if capture.status == .failed {
            Button {
                Task {
                    await viewModel.retryFailedUploads()
                }
            } label: {
                Label("Retry Upload", systemImage: "arrow.clockwise")
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
