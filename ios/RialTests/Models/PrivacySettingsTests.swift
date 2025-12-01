//
//  PrivacySettingsTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-01.
//
//  Unit tests for PrivacySettings model (Story 8-2).
//

import XCTest
@testable import Rial

final class PrivacySettingsTests: XCTestCase {

    // MARK: - Default Values Tests (AC #4)

    /// Test that default privacy settings match specification
    func testDefault_MatchesSpecification() {
        let settings = PrivacySettings.default

        // AC #4.1: Privacy Mode is OFF
        XCTAssertFalse(settings.privacyModeEnabled, "Privacy mode should be OFF by default")

        // AC #4.2: Location defaults to "Coarse (city)"
        XCTAssertEqual(settings.locationLevel, .coarse, "Location should default to coarse")

        // AC #4.3: Timestamp defaults to "Exact"
        XCTAssertEqual(settings.timestampLevel, .exact, "Timestamp should default to exact")

        // AC #4.4: Device Info defaults to "Model only"
        XCTAssertEqual(settings.deviceInfoLevel, .modelOnly, "Device info should default to modelOnly")
    }

    /// Test that init without parameters uses correct defaults
    func testInit_WithoutParameters_UsesDefaults() {
        let settings = PrivacySettings()

        XCTAssertFalse(settings.privacyModeEnabled)
        XCTAssertEqual(settings.locationLevel, .coarse)
        XCTAssertEqual(settings.timestampLevel, .exact)
        XCTAssertEqual(settings.deviceInfoLevel, .modelOnly)
    }

    /// Test that init with custom parameters works correctly
    func testInit_WithCustomParameters_SetsValues() {
        let settings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .precise,
            timestampLevel: .none,
            deviceInfoLevel: .full
        )

        XCTAssertTrue(settings.privacyModeEnabled)
        XCTAssertEqual(settings.locationLevel, .precise)
        XCTAssertEqual(settings.timestampLevel, .none)
        XCTAssertEqual(settings.deviceInfoLevel, .full)
    }

    // MARK: - Codable Encoding/Decoding Tests (AC #3)

    /// Test that PrivacySettings can be encoded and decoded
    func testCodable_RoundTrip_PreservesValues() throws {
        let original = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .precise,
            timestampLevel: .dayOnly,
            deviceInfoLevel: .full
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PrivacySettings.self, from: data)

        XCTAssertEqual(decoded.privacyModeEnabled, original.privacyModeEnabled)
        XCTAssertEqual(decoded.locationLevel, original.locationLevel)
        XCTAssertEqual(decoded.timestampLevel, original.timestampLevel)
        XCTAssertEqual(decoded.deviceInfoLevel, original.deviceInfoLevel)
    }

    /// Test that default values survive encoding/decoding
    func testCodable_DefaultValues_RoundTrip() throws {
        let original = PrivacySettings.default

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PrivacySettings.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    /// Test that all enum combinations encode/decode correctly
    func testCodable_AllEnumCombinations_RoundTrip() throws {
        for location in MetadataLevel.allCases {
            for timestamp in TimestampLevel.allCases {
                for deviceInfo in DeviceInfoLevel.allCases {
                    let original = PrivacySettings(
                        privacyModeEnabled: true,
                        locationLevel: location,
                        timestampLevel: timestamp,
                        deviceInfoLevel: deviceInfo
                    )

                    let encoder = JSONEncoder()
                    let data = try encoder.encode(original)

                    let decoder = JSONDecoder()
                    let decoded = try decoder.decode(PrivacySettings.self, from: data)

                    XCTAssertEqual(decoded, original, "Failed for location=\(location), timestamp=\(timestamp), deviceInfo=\(deviceInfo)")
                }
            }
        }
    }

    // MARK: - Equatable Tests

    /// Test that identical settings are equal
    func testEquatable_IdenticalSettings_AreEqual() {
        let settings1 = PrivacySettings.default
        let settings2 = PrivacySettings.default

        XCTAssertEqual(settings1, settings2)
    }

    /// Test that different settings are not equal
    func testEquatable_DifferentSettings_AreNotEqual() {
        let settings1 = PrivacySettings.default
        let settings2 = PrivacySettings(privacyModeEnabled: true)

        XCTAssertNotEqual(settings1, settings2)
    }

    // MARK: - Description Tests

    /// Test that description contains all fields
    func testDescription_ContainsAllFields() {
        let settings = PrivacySettings.default
        let description = settings.description

        XCTAssertTrue(description.contains("privacyModeEnabled"))
        XCTAssertTrue(description.contains("locationLevel"))
        XCTAssertTrue(description.contains("timestampLevel"))
        XCTAssertTrue(description.contains("deviceInfoLevel"))
    }
}

// MARK: - MetadataLevel Tests

final class MetadataLevelTests: XCTestCase {

    /// Test raw values match API specification (snake_case)
    func testRawValues_MatchAPISpec() {
        XCTAssertEqual(MetadataLevel.none.rawValue, "none")
        XCTAssertEqual(MetadataLevel.coarse.rawValue, "coarse")
        XCTAssertEqual(MetadataLevel.precise.rawValue, "precise")
    }

    /// Test CaseIterable contains all cases
    func testCaseIterable_ContainsAllCases() {
        let allCases = MetadataLevel.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.none))
        XCTAssertTrue(allCases.contains(.coarse))
        XCTAssertTrue(allCases.contains(.precise))
    }

    /// Test displayName for all cases
    func testDisplayName_AllCases() {
        XCTAssertEqual(MetadataLevel.none.displayName, "None")
        XCTAssertEqual(MetadataLevel.coarse.displayName, "City Level")
        XCTAssertEqual(MetadataLevel.precise.displayName, "Precise")
    }

    /// Test Codable round-trip for all cases
    func testCodable_AllCases() throws {
        for level in MetadataLevel.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(level)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(MetadataLevel.self, from: data)

            XCTAssertEqual(decoded, level)
        }
    }
}

// MARK: - TimestampLevel Tests

final class TimestampLevelTests: XCTestCase {

    /// Test raw values match API specification (snake_case)
    func testRawValues_MatchAPISpec() {
        XCTAssertEqual(TimestampLevel.none.rawValue, "none")
        XCTAssertEqual(TimestampLevel.dayOnly.rawValue, "day_only")
        XCTAssertEqual(TimestampLevel.exact.rawValue, "exact")
    }

    /// Test CaseIterable contains all cases
    func testCaseIterable_ContainsAllCases() {
        let allCases = TimestampLevel.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.none))
        XCTAssertTrue(allCases.contains(.dayOnly))
        XCTAssertTrue(allCases.contains(.exact))
    }

    /// Test displayName for all cases
    func testDisplayName_AllCases() {
        XCTAssertEqual(TimestampLevel.none.displayName, "None")
        XCTAssertEqual(TimestampLevel.dayOnly.displayName, "Day Only")
        XCTAssertEqual(TimestampLevel.exact.displayName, "Exact")
    }

    /// Test Codable round-trip for all cases
    func testCodable_AllCases() throws {
        for level in TimestampLevel.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(level)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(TimestampLevel.self, from: data)

            XCTAssertEqual(decoded, level)
        }
    }
}

// MARK: - DeviceInfoLevel Tests

final class DeviceInfoLevelTests: XCTestCase {

    /// Test raw values match API specification (snake_case)
    func testRawValues_MatchAPISpec() {
        XCTAssertEqual(DeviceInfoLevel.none.rawValue, "none")
        XCTAssertEqual(DeviceInfoLevel.modelOnly.rawValue, "model_only")
        XCTAssertEqual(DeviceInfoLevel.full.rawValue, "full")
    }

    /// Test CaseIterable contains all cases
    func testCaseIterable_ContainsAllCases() {
        let allCases = DeviceInfoLevel.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.none))
        XCTAssertTrue(allCases.contains(.modelOnly))
        XCTAssertTrue(allCases.contains(.full))
    }

    /// Test displayName for all cases
    func testDisplayName_AllCases() {
        XCTAssertEqual(DeviceInfoLevel.none.displayName, "None")
        XCTAssertEqual(DeviceInfoLevel.modelOnly.displayName, "Model Only")
        XCTAssertEqual(DeviceInfoLevel.full.displayName, "Full")
    }

    /// Test Codable round-trip for all cases
    func testCodable_AllCases() throws {
        for level in DeviceInfoLevel.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(level)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(DeviceInfoLevel.self, from: data)

            XCTAssertEqual(decoded, level)
        }
    }
}
