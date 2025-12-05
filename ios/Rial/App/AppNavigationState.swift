//
//  AppNavigationState.swift
//  Rial
//
//  Created by RealityCam on 2025-12-05.
//
//  Shared navigation state for coordinating navigation across tabs.
//

import SwiftUI

/// Shared navigation state for coordinating between tabs.
///
/// Used to navigate from Capture tab to History tab after saving a capture,
/// and to automatically show the capture detail view.
@MainActor
final class AppNavigationState: ObservableObject {
    /// Currently selected tab index (0 = Capture, 1 = History)
    @Published var selectedTab: Int = 0

    /// Capture ID to navigate to after switching to History tab.
    /// Set this before switching tabs to auto-navigate to detail view.
    @Published var pendingCaptureId: UUID?

    /// Navigate to History tab and show a specific capture's detail view.
    ///
    /// - Parameter captureId: The capture ID to show
    func navigateToCapture(_ captureId: UUID) {
        pendingCaptureId = captureId
        selectedTab = 1  // Switch to History tab
    }

    /// Clear pending navigation after it has been consumed.
    func clearPendingNavigation() {
        pendingCaptureId = nil
    }
}
