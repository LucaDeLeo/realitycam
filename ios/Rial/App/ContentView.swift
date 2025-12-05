import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            CaptureView()
                .tabItem {
                    Label("Capture", systemImage: "camera.fill")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(1)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigationState())
        .environmentObject(PrivacySettingsManager.preview())
}
