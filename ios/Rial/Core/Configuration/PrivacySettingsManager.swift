//
//  PrivacySettingsManager.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Privacy settings manager for Story 8-2.
//  Provides ObservableObject with @AppStorage persistence for privacy mode settings.
//

import Foundation
import SwiftUI
import os

// MARK: - PrivacySettingsManager

/// Manager for privacy mode settings with UserDefaults persistence.
///
/// Provides an ObservableObject that stores privacy settings as JSON-encoded
/// data in @AppStorage for atomic updates and type safety.
///
/// ## Usage
/// ```swift
/// // In RialApp.swift
/// @StateObject private var privacySettings = PrivacySettingsManager()
///
/// var body: some Scene {
///     WindowGroup {
///         ContentView()
///             .environmentObject(privacySettings)
///     }
/// }
///
/// // In any view
/// @EnvironmentObject var privacySettings: PrivacySettingsManager
///
/// Toggle("Privacy Mode", isOn: $privacySettings.settings.privacyModeEnabled)
/// ```
///
/// ## Persistence
/// Settings are stored as JSON in UserDefaults with key "app.rial.privacySettings".
/// The encoded data survives app updates and device restarts.
@MainActor
public final class PrivacySettingsManager: ObservableObject {

    // MARK: - Constants

    /// UserDefaults key for privacy settings
    private static let settingsKey = "app.rial.privacySettings"

    // MARK: - Private Properties

    /// Logger for diagnostics
    private static let logger = Logger(subsystem: "app.rial", category: "privacysettings")

    /// Raw JSON data stored in UserDefaults
    @AppStorage(PrivacySettingsManager.settingsKey) private var settingsData: Data?

    // MARK: - Published Properties

    /// Current privacy settings.
    ///
    /// Changes to this property are automatically persisted to UserDefaults
    /// and trigger SwiftUI view updates.
    @Published public var settings: PrivacySettings {
        didSet {
            saveSettings()
        }
    }

    // MARK: - Computed Properties

    /// Convenience property for checking if privacy mode is enabled.
    public var isPrivacyModeEnabled: Bool {
        settings.privacyModeEnabled
    }

    // MARK: - Initialization

    /// Creates a new privacy settings manager.
    ///
    /// Loads existing settings from UserDefaults or uses defaults.
    public init() {
        // Load settings from UserDefaults or use defaults
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(PrivacySettings.self, from: data) {
            self.settings = decoded
            Self.logger.debug("Loaded privacy settings from storage")
        } else {
            self.settings = PrivacySettings.default
            Self.logger.debug("Using default privacy settings")
        }
    }

    // MARK: - Public Methods

    /// Resets settings to default values.
    ///
    /// Clears stored settings and applies defaults.
    public func resetToDefaults() {
        settings = PrivacySettings.default
        Self.logger.info("Privacy settings reset to defaults")
    }

    /// Toggles privacy mode on/off.
    public func togglePrivacyMode() {
        settings.privacyModeEnabled.toggle()
        Self.logger.info("Privacy mode toggled to: \(self.settings.privacyModeEnabled)")
    }

    // MARK: - Private Methods

    /// Saves current settings to UserDefaults.
    private func saveSettings() {
        do {
            let encoded = try JSONEncoder().encode(settings)
            settingsData = encoded
            Self.logger.debug("Privacy settings saved")
        } catch {
            Self.logger.error("Failed to encode privacy settings: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension PrivacySettingsManager {
    /// Creates a preview instance with specified settings.
    ///
    /// - Parameter settings: Initial settings for preview
    /// - Returns: Configured PrivacySettingsManager instance
    static func preview(settings: PrivacySettings = .default) -> PrivacySettingsManager {
        let manager = PrivacySettingsManager()
        manager.settings = settings
        return manager
    }

    /// Creates a preview instance with privacy mode enabled.
    static var previewEnabled: PrivacySettingsManager {
        preview(settings: PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .coarse,
            timestampLevel: .exact,
            deviceInfoLevel: .modelOnly
        ))
    }
}
#endif
