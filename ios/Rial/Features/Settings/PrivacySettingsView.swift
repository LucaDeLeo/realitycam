//
//  PrivacySettingsView.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Privacy settings UI for Story 8-2.
//  Provides toggle for privacy mode and granular metadata controls.
//

import SwiftUI

// MARK: - PrivacySettingsView

/// Privacy settings screen with privacy mode toggle and metadata controls.
///
/// ## Features
/// - Privacy Mode toggle with explanation (AC #1)
/// - Conditional metadata controls when enabled (AC #2)
/// - Location, timestamp, and device info pickers
/// - Learn More sheet explaining privacy mode (AC #6)
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     PrivacySettingsView()
///         .environmentObject(privacySettings)
/// }
/// ```
public struct PrivacySettingsView: View {
    @EnvironmentObject private var privacySettings: PrivacySettingsManager

    /// Whether to show the Learn More sheet
    @State private var showLearnMore = false

    /// Haptic feedback generator
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        Form {
            // MARK: - Privacy Mode Section
            Section {
                // Privacy Mode Toggle (AC #1)
                Toggle(isOn: $privacySettings.settings.privacyModeEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy Mode")
                            .font(.body)
                        Text("When enabled, only a hash of your capture is uploaded. The actual photo/video never leaves your device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: privacySettings.settings.privacyModeEnabled) { _ in
                    impactFeedback.impactOccurred()
                }
                .accessibilityLabel("Privacy Mode")
                .accessibilityHint(privacySettings.settings.privacyModeEnabled
                    ? "Currently enabled. Double tap to disable."
                    : "Currently disabled. Double tap to enable.")

                // Learn More Button (AC #6)
                Button {
                    showLearnMore = true
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Learn More")
                    }
                    .accentColor(.accentColor)
                }
                .accessibilityLabel("Learn more about privacy mode")
            } header: {
                Text("Privacy & Security")
            } footer: {
                if privacySettings.settings.privacyModeEnabled {
                    Text("Privacy Mode is ON. Configure what metadata to include below.")
                }
            }

            // MARK: - Metadata Controls Section (AC #2)
            // Only shown when privacy mode is enabled
            if privacySettings.settings.privacyModeEnabled {
                Section {
                    // Location Picker
                    Picker(selection: $privacySettings.settings.locationLevel) {
                        ForEach(MetadataLevel.allCases, id: \.self) { level in
                            Label(level.displayName, systemImage: level.systemImage)
                                .tag(level)
                        }
                    } label: {
                        Label("Location", systemImage: "location")
                    }
                    .onChange(of: privacySettings.settings.locationLevel) { _ in
                        impactFeedback.impactOccurred()
                    }
                    .accessibilityLabel("Location level")
                    .accessibilityHint("Currently set to \(privacySettings.settings.locationLevel.displayName)")

                    // Timestamp Picker
                    Picker(selection: $privacySettings.settings.timestampLevel) {
                        ForEach(TimestampLevel.allCases, id: \.self) { level in
                            Label(level.displayName, systemImage: level.systemImage)
                                .tag(level)
                        }
                    } label: {
                        Label("Timestamp", systemImage: "clock")
                    }
                    .onChange(of: privacySettings.settings.timestampLevel) { _ in
                        impactFeedback.impactOccurred()
                    }
                    .accessibilityLabel("Timestamp level")
                    .accessibilityHint("Currently set to \(privacySettings.settings.timestampLevel.displayName)")

                    // Device Info Picker
                    Picker(selection: $privacySettings.settings.deviceInfoLevel) {
                        ForEach(DeviceInfoLevel.allCases, id: \.self) { level in
                            Label(level.displayName, systemImage: level.systemImage)
                                .tag(level)
                        }
                    } label: {
                        Label("Device Info", systemImage: "iphone")
                    }
                    .onChange(of: privacySettings.settings.deviceInfoLevel) { _ in
                        impactFeedback.impactOccurred()
                    }
                    .accessibilityLabel("Device info level")
                    .accessibilityHint("Currently set to \(privacySettings.settings.deviceInfoLevel.displayName)")
                } header: {
                    Text("Metadata Controls")
                } footer: {
                    Text("Control what metadata is included with your privacy mode captures.")
                }
            }

            // MARK: - Reset Section
            Section {
                Button(role: .destructive) {
                    privacySettings.resetToDefaults()
                    impactFeedback.impactOccurred()
                } label: {
                    Text("Reset to Defaults")
                }
                .accessibilityLabel("Reset privacy settings to defaults")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLearnMore) {
            LearnMorePrivacyView()
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
struct PrivacySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Privacy mode off
            NavigationStack {
                PrivacySettingsView()
                    .environmentObject(PrivacySettingsManager.preview())
            }
            .previewDisplayName("Privacy Mode Off")

            // Privacy mode on
            NavigationStack {
                PrivacySettingsView()
                    .environmentObject(PrivacySettingsManager.previewEnabled)
            }
            .previewDisplayName("Privacy Mode On")
        }
    }
}
#endif
