//
//  HistoryViewModel.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  View model for capture history screen.
//

import SwiftUI
import os.log

/// View model for capture history screen.
///
/// Manages loading captures from CoreData store and retry logic for failed uploads.
///
/// ## Usage
/// ```swift
/// struct HistoryView: View {
///     @StateObject private var viewModel = HistoryViewModel()
///
///     var body: some View {
///         // ... use viewModel.captures
///     }
/// }
/// ```
@MainActor
final class HistoryViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "app.rial", category: "history-viewmodel")

    // MARK: - Published Properties

    /// All captures sorted by date (newest first)
    @Published private(set) var captures: [CaptureHistoryItem] = []

    /// Whether data is currently loading
    @Published private(set) var isLoading = false

    /// Error message if load fails
    @Published var errorMessage: String?

    // MARK: - Private Properties

    /// Capture store for data access
    private let captureStore: CaptureStore

    /// Upload service for retry logic
    private let uploadService: UploadService?

    // MARK: - Initialization

    init(
        captureStore: CaptureStore? = nil,
        uploadService: UploadService? = nil
    ) {
        self.captureStore = captureStore ?? CaptureStore()
        self.uploadService = uploadService
    }

    // MARK: - Public Methods

    /// Load all captures from store.
    func loadCaptures() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let captureData = try await captureStore.fetchAllCaptures()
            captures = captureData.map { data in
                CaptureHistoryItem(
                    id: data.id,
                    thumbnail: generateThumbnail(from: data.jpeg),
                    status: determineStatus(data),
                    createdAt: data.timestamp,
                    serverCaptureId: nil, // Would come from store
                    verificationUrl: nil
                )
            }

            Self.logger.info("Loaded \(self.captures.count) captures")
        } catch {
            Self.logger.error("Failed to load captures: \(error.localizedDescription)")
            errorMessage = "Failed to load captures"
        }
    }

    /// Retry all failed uploads.
    func retryFailedUploads() async {
        Self.logger.info("Retrying failed uploads")

        do {
            let pending = try await captureStore.fetchPendingCaptures()
            let failed = captures.filter { $0.status == .failed }

            Self.logger.info("Found \(pending.count) pending, \(failed.count) failed uploads")

            // Reload to refresh status
            await loadCaptures()
        } catch {
            Self.logger.error("Failed to retry uploads: \(error.localizedDescription)")
            errorMessage = "Failed to retry uploads"
        }
    }

    /// Delete a capture by ID.
    func deleteCapture(_ id: UUID) async {
        do {
            try await captureStore.deleteCapture(byId: id)
            captures.removeAll { $0.id == id }
            Self.logger.info("Deleted capture: \(id.uuidString)")
        } catch {
            Self.logger.error("Failed to delete capture: \(error.localizedDescription)")
            errorMessage = "Failed to delete capture"
        }
    }

    // MARK: - Private Methods

    /// Generate thumbnail from JPEG data.
    private func generateThumbnail(from jpegData: Data) -> UIImage? {
        guard let image = UIImage(data: jpegData) else {
            return nil
        }

        // Generate 200x200 thumbnail
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Determine capture status based on assertion state.
    private func determineStatus(_ data: CaptureData) -> CaptureStatus {
        switch data.assertionStatus {
        case .none, .pending:
            return .pending
        case .generated:
            return .pending // Has assertion but not yet uploaded
        case .failed:
            return .failed
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension HistoryViewModel {
    /// Creates a preview instance with mock data.
    static var preview: HistoryViewModel {
        let vm = HistoryViewModel()
        vm.captures = [
            .preview(status: .uploaded),
            .preview(status: .uploading),
            .preview(status: .pending),
            .preview(status: .failed),
        ]
        return vm
    }
}
#endif
