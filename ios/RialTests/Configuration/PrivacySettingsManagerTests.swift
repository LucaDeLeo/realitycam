//
//  PrivacySettingsManagerTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-01.
//
//  Unit tests for PrivacySettingsManager (Story 8-2).
//

import XCTest
@testable import Rial

@MainActor
final class PrivacySettingsManagerTests: XCTestCase {

    // MARK: - Properties

    /// UserDefaults key used by PrivacySettingsManager
    private static let settingsKey = "app.rial.privacySettings"

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()
        // Clear UserDefaults before each test for isolation
        UserDefaults.standard.removeObject(forKey: Self.settingsKey)
    }

    override func tearDown() async throws {
        // Clean up after tests
        UserDefaults.standard.removeObject(forKey: Self.settingsKey)
        try await super.tearDown()
    }

    // MARK: - Default Values Tests (AC #4)

    /// Test fresh installation uses default values
    func testInit_FreshInstall_UsesDefaults() {
        // Ensure no stored settings
        UserDefaults.standard.removeObject(forKey: Self.settingsKey)

        let manager = PrivacySettingsManager()

        // AC #4: Fresh install should use defaults
        XCTAssertFalse(manager.settings.privacyModeEnabled, "Privacy mode should be OFF by default")
        XCTAssertEqual(manager.settings.locationLevel, .coarse, "Location should default to coarse")
        XCTAssertEqual(manager.settings.timestampLevel, .exact, "Timestamp should default to exact")
        XCTAssertEqual(manager.settings.deviceInfoLevel, .modelOnly, "Device info should default to modelOnly")
    }

    /// Test isPrivacyModeEnabled convenience property
    func testIsPrivacyModeEnabled_ReflectsSettings() {
        let manager = PrivacySettingsManager()

        XCTAssertFalse(manager.isPrivacyModeEnabled)

        manager.settings.privacyModeEnabled = true
        XCTAssertTrue(manager.isPrivacyModeEnabled)

        manager.settings.privacyModeEnabled = false
        XCTAssertFalse(manager.isPrivacyModeEnabled)
    }

    // MARK: - Persistence Tests (AC #3)

    /// Test settings persist to UserDefaults
    func testSettings_PersistToUserDefaults() {
        let manager = PrivacySettingsManager()

        // Modify settings
        manager.settings.privacyModeEnabled = true
        manager.settings.locationLevel = .precise
        manager.settings.timestampLevel = .none
        manager.settings.deviceInfoLevel = .full

        // Verify stored in UserDefaults
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey) else {
            XCTFail("Settings should be stored in UserDefaults")
            return
        }

        // Decode and verify
        do {
            let decoded = try JSONDecoder().decode(PrivacySettings.self, from: data)
            XCTAssertTrue(decoded.privacyModeEnabled)
            XCTAssertEqual(decoded.locationLevel, .precise)
            XCTAssertEqual(decoded.timestampLevel, .none)
            XCTAssertEqual(decoded.deviceInfoLevel, .full)
        } catch {
            XCTFail("Failed to decode settings: \(error)")
        }
    }

    /// Test settings load from UserDefaults on init
    func testInit_LoadsFromUserDefaults() {
        // Pre-populate UserDefaults with custom settings
        let customSettings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .none,
            timestampLevel: .dayOnly,
            deviceInfoLevel: .none
        )

        do {
            let data = try JSONEncoder().encode(customSettings)
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        } catch {
            XCTFail("Failed to encode settings: \(error)")
            return
        }

        // Create new manager - should load from UserDefaults
        let manager = PrivacySettingsManager()

        XCTAssertTrue(manager.settings.privacyModeEnabled)
        XCTAssertEqual(manager.settings.locationLevel, .none)
        XCTAssertEqual(manager.settings.timestampLevel, .dayOnly)
        XCTAssertEqual(manager.settings.deviceInfoLevel, .none)
    }

    /// Test settings persist across manager instances (simulates app relaunch - AC #3.1-4)
    func testSettings_PersistAcrossInstances() {
        // First instance - make changes
        let manager1 = PrivacySettingsManager()
        manager1.settings.privacyModeEnabled = true
        manager1.settings.locationLevel = .precise

        // Second instance - should load persisted settings
        let manager2 = PrivacySettingsManager()

        XCTAssertTrue(manager2.settings.privacyModeEnabled, "Privacy mode should persist")
        XCTAssertEqual(manager2.settings.locationLevel, .precise, "Location level should persist")
    }

    /// Test individual setting changes persist
    func testIndividualSettingChanges_Persist() {
        let manager = PrivacySettingsManager()

        // Change privacy mode
        manager.settings.privacyModeEnabled = true
        let manager2 = PrivacySettingsManager()
        XCTAssertTrue(manager2.settings.privacyModeEnabled)

        // Change location level
        manager2.settings.locationLevel = .none
        let manager3 = PrivacySettingsManager()
        XCTAssertEqual(manager3.settings.locationLevel, .none)

        // Change timestamp level
        manager3.settings.timestampLevel = .dayOnly
        let manager4 = PrivacySettingsManager()
        XCTAssertEqual(manager4.settings.timestampLevel, .dayOnly)

        // Change device info level
        manager4.settings.deviceInfoLevel = .full
        let manager5 = PrivacySettingsManager()
        XCTAssertEqual(manager5.settings.deviceInfoLevel, .full)
    }

    // MARK: - Reset Tests

    /// Test resetToDefaults restores default values
    func testResetToDefaults_RestoresDefaults() {
        let manager = PrivacySettingsManager()

        // Modify all settings
        manager.settings.privacyModeEnabled = true
        manager.settings.locationLevel = .precise
        manager.settings.timestampLevel = .none
        manager.settings.deviceInfoLevel = .full

        // Reset
        manager.resetToDefaults()

        // Verify defaults restored
        XCTAssertFalse(manager.settings.privacyModeEnabled)
        XCTAssertEqual(manager.settings.locationLevel, .coarse)
        XCTAssertEqual(manager.settings.timestampLevel, .exact)
        XCTAssertEqual(manager.settings.deviceInfoLevel, .modelOnly)
    }

    /// Test resetToDefaults persists the reset
    func testResetToDefaults_PersistsReset() {
        let manager = PrivacySettingsManager()

        // Modify settings
        manager.settings.privacyModeEnabled = true
        manager.settings.locationLevel = .precise

        // Reset
        manager.resetToDefaults()

        // New instance should have defaults
        let manager2 = PrivacySettingsManager()
        XCTAssertFalse(manager2.settings.privacyModeEnabled)
        XCTAssertEqual(manager2.settings.locationLevel, .coarse)
    }

    // MARK: - Toggle Tests

    /// Test togglePrivacyMode toggles the setting
    func testTogglePrivacyMode_TogglesValue() {
        let manager = PrivacySettingsManager()

        XCTAssertFalse(manager.settings.privacyModeEnabled)

        manager.togglePrivacyMode()
        XCTAssertTrue(manager.settings.privacyModeEnabled)

        manager.togglePrivacyMode()
        XCTAssertFalse(manager.settings.privacyModeEnabled)
    }

    /// Test togglePrivacyMode persists change
    func testTogglePrivacyMode_PersistsChange() {
        let manager = PrivacySettingsManager()
        manager.togglePrivacyMode()

        let manager2 = PrivacySettingsManager()
        XCTAssertTrue(manager2.settings.privacyModeEnabled)
    }

    // MARK: - Corrupt Data Handling Tests

    /// Test manager handles corrupt UserDefaults data gracefully
    func testInit_CorruptData_UsesDefaults() {
        // Store invalid JSON
        let corruptData = "not valid json".data(using: .utf8)!
        UserDefaults.standard.set(corruptData, forKey: Self.settingsKey)

        // Manager should fall back to defaults
        let manager = PrivacySettingsManager()

        XCTAssertFalse(manager.settings.privacyModeEnabled)
        XCTAssertEqual(manager.settings.locationLevel, .coarse)
        XCTAssertEqual(manager.settings.timestampLevel, .exact)
        XCTAssertEqual(manager.settings.deviceInfoLevel, .modelOnly)
    }

    // MARK: - ObservableObject Tests

    /// Test that settings changes trigger objectWillChange
    func testSettingsChange_TriggersObjectWillChange() {
        let manager = PrivacySettingsManager()
        let expectation = XCTestExpectation(description: "objectWillChange should fire")

        let cancellable = manager.objectWillChange.sink { _ in
            expectation.fulfill()
        }

        manager.settings.privacyModeEnabled = true

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}

// MARK: - Preview Support Tests

#if DEBUG
@MainActor
final class PrivacySettingsManagerPreviewTests: XCTestCase {

    /// Test preview factory method
    func testPreview_CreatesManagerWithSettings() {
        let customSettings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .precise,
            timestampLevel: .none,
            deviceInfoLevel: .full
        )

        let manager = PrivacySettingsManager.preview(settings: customSettings)

        XCTAssertTrue(manager.settings.privacyModeEnabled)
        XCTAssertEqual(manager.settings.locationLevel, .precise)
        XCTAssertEqual(manager.settings.timestampLevel, .none)
        XCTAssertEqual(manager.settings.deviceInfoLevel, .full)
    }

    /// Test previewEnabled factory
    func testPreviewEnabled_HasPrivacyModeOn() {
        let manager = PrivacySettingsManager.previewEnabled

        XCTAssertTrue(manager.isPrivacyModeEnabled)
    }
}
#endif
