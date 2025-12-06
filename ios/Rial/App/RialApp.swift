import SwiftUI

@main
struct RialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Scene phase for detecting app lifecycle transitions
    @Environment(\.scenePhase) private var scenePhase

    /// Privacy settings manager injected as environment object (Story 8-2)
    @StateObject private var privacySettings = PrivacySettingsManager()

    /// Navigation state for coordinating tab navigation after capture
    @StateObject private var navigationState = AppNavigationState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(privacySettings)
                .environmentObject(navigationState)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .background {
                        #if DEBUG
                        // Flush buffered debug logs when app enters background
                        Task {
                            await DebugLogger.shared.flush()
                        }
                        #endif
                    }
                }
        }
    }
}
