import SwiftUI

@main
struct RialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Privacy settings manager injected as environment object (Story 8-2)
    @StateObject private var privacySettings = PrivacySettingsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(privacySettings)
        }
    }
}
