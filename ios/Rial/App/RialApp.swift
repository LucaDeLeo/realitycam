import SwiftUI

@main
struct RialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Privacy settings manager injected as environment object (Story 8-2)
    @StateObject private var privacySettings = PrivacySettingsManager()

    /// Navigation state for coordinating tab navigation after capture
    @StateObject private var navigationState = AppNavigationState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(privacySettings)
                .environmentObject(navigationState)
        }
    }
}
