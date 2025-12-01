//
//  MetadataFilterServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-12-01.
//
//  Unit tests for MetadataFilterService (Story 8-3).
//

import XCTest
@testable import Rial

final class MetadataFilterServiceTests: XCTestCase {

    // MARK: - Test Data

    private var sampleLocationData: LocationData!
    private var sampleCaptureMetadata: CaptureMetadata!

    override func setUp() {
        super.setUp()
        sampleLocationData = LocationData(
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 10.0,
            accuracy: 5.0,
            timestamp: Date()
        )
        sampleCaptureMetadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone 15 Pro",
            photoHash: "abc123",
            location: sampleLocationData,
            depthMapDimensions: DepthDimensions(width: 256, height: 192),
            iosVersion: "18.1",
            appVersion: "1.0.0"
        )
    }

    // MARK: - Location Filtering Tests (AC #3)

    /// Test location filtering with level = none
    func testFilterLocationSync_LevelNone_ReturnsNil() {
        let result = MetadataFilterService.filterLocationSync(
            data: sampleLocationData,
            level: .none
        )

        XCTAssertNil(result, "Location level none should return nil")
    }

    /// Test location filtering with level = precise
    func testFilterLocationSync_LevelPrecise_ReturnsCoordinates() {
        let result = MetadataFilterService.filterLocationSync(
            data: sampleLocationData,
            level: .precise
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.latitude, 37.7749)
        XCTAssertEqual(result?.longitude, -122.4194)
        XCTAssertNil(result?.city)
        XCTAssertNil(result?.country)
    }

    /// Test location filtering with nil location data
    func testFilterLocationSync_NilLocation_ReturnsNil() {
        let result = MetadataFilterService.filterLocationSync(
            data: nil,
            level: .precise
        )

        XCTAssertNil(result)
    }

    /// Test async location filtering with level = none
    func testFilterLocation_LevelNone_ReturnsNil() async {
        let result = await MetadataFilterService.filterLocation(
            data: sampleLocationData,
            level: .none
        )

        XCTAssertNil(result)
    }

    /// Test async location filtering with level = precise
    func testFilterLocation_LevelPrecise_ReturnsCoordinates() async {
        let result = await MetadataFilterService.filterLocation(
            data: sampleLocationData,
            level: .precise
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.latitude, 37.7749)
        XCTAssertEqual(result?.longitude, -122.4194)
    }

    // MARK: - Timestamp Filtering Tests (AC #3)

    /// Test timestamp filtering with level = none
    func testFilterTimestamp_LevelNone_ReturnsNil() {
        let result = MetadataFilterService.filterTimestamp(
            date: Date(),
            level: .none
        )

        XCTAssertNil(result, "Timestamp level none should return nil")
    }

    /// Test timestamp filtering with level = dayOnly
    func testFilterTimestamp_LevelDayOnly_ReturnsDateOnly() {
        // Use a specific date for deterministic testing
        let dateComponents = DateComponents(year: 2025, month: 12, day: 1)
        let date = Calendar.current.date(from: dateComponents)!

        let result = MetadataFilterService.filterTimestamp(
            date: date,
            level: .dayOnly
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("2025-12-01"), "Should contain date only: \(result!)")
        XCTAssertFalse(result!.contains("T"), "Should not contain time separator")
    }

    /// Test timestamp filtering with level = exact
    func testFilterTimestamp_LevelExact_ReturnsFullISO8601() {
        let date = Date()

        let result = MetadataFilterService.filterTimestamp(
            date: date,
            level: .exact
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("T"), "Should contain time separator")
        XCTAssertTrue(result!.contains("Z") || result!.contains("+"), "Should contain timezone")
    }

    /// Test all timestamp levels produce different results
    func testFilterTimestamp_DifferentLevels_ProduceDifferentResults() {
        let date = Date()

        let noneResult = MetadataFilterService.filterTimestamp(date: date, level: .none)
        let dayOnlyResult = MetadataFilterService.filterTimestamp(date: date, level: .dayOnly)
        let exactResult = MetadataFilterService.filterTimestamp(date: date, level: .exact)

        // None should be nil
        XCTAssertNil(noneResult)

        // DayOnly and Exact should both be non-nil but different
        XCTAssertNotNil(dayOnlyResult)
        XCTAssertNotNil(exactResult)
        XCTAssertNotEqual(dayOnlyResult, exactResult)
    }

    // MARK: - Device Info Filtering Tests (AC #3)

    /// Test device info filtering with level = none
    func testFilterDeviceInfo_LevelNone_ReturnsNil() {
        let result = MetadataFilterService.filterDeviceInfo(
            metadata: sampleCaptureMetadata,
            level: .none
        )

        XCTAssertNil(result, "Device info level none should return nil")
    }

    /// Test device info filtering with level = modelOnly
    func testFilterDeviceInfo_LevelModelOnly_ReturnsModelOnly() {
        let result = MetadataFilterService.filterDeviceInfo(
            metadata: sampleCaptureMetadata,
            level: .modelOnly
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result, "iPhone 15 Pro")
        XCTAssertFalse(result!.contains("/"), "Should not contain version separator")
    }

    /// Test device info filtering with level = full
    func testFilterDeviceInfo_LevelFull_ReturnsFullInfo() {
        let result = MetadataFilterService.filterDeviceInfo(
            metadata: sampleCaptureMetadata,
            level: .full
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("iPhone 15 Pro"), "Should contain model")
        XCTAssertTrue(result!.contains("iOS"), "Should contain iOS version")
        XCTAssertTrue(result!.contains("18.1"), "Should contain version number")
        XCTAssertTrue(result!.contains("1.0.0"), "Should contain app version")
        XCTAssertTrue(result!.contains("/"), "Should contain separator")
    }

    // MARK: - Build Flags Tests

    /// Test building flags from privacy settings
    func testBuildFlags_FromSettings_CreatesCorrectFlags() {
        let settings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .coarse,
            timestampLevel: .dayOnly,
            deviceInfoLevel: .full
        )

        let flags = MetadataFilterService.buildFlags(from: settings)

        XCTAssertTrue(flags.locationIncluded)
        XCTAssertEqual(flags.locationLevel, "coarse")
        XCTAssertTrue(flags.timestampIncluded)
        XCTAssertEqual(flags.timestampLevel, "day_only")
        XCTAssertTrue(flags.deviceInfoIncluded)
        XCTAssertEqual(flags.deviceInfoLevel, "full")
    }

    /// Test building flags when all levels are none
    func testBuildFlags_AllNone_CorrectIncludedFlags() {
        let settings = PrivacySettings(
            privacyModeEnabled: true,
            locationLevel: .none,
            timestampLevel: .none,
            deviceInfoLevel: .none
        )

        let flags = MetadataFilterService.buildFlags(from: settings)

        XCTAssertFalse(flags.locationIncluded)
        XCTAssertFalse(flags.timestampIncluded)
        XCTAssertFalse(flags.deviceInfoIncluded)
    }

    // MARK: - All Filtering Combinations Tests

    /// Test all 27 filtering combinations (3x3x3)
    func testFilterAll_AllCombinations() async {
        let locationLevels = MetadataLevel.allCases
        let timestampLevels = TimestampLevel.allCases
        let deviceInfoLevels = DeviceInfoLevel.allCases

        for location in locationLevels {
            for timestamp in timestampLevels {
                for deviceInfo in deviceInfoLevels {
                    let settings = PrivacySettings(
                        privacyModeEnabled: true,
                        locationLevel: location,
                        timestampLevel: timestamp,
                        deviceInfoLevel: deviceInfo
                    )

                    // Create a minimal CaptureData for testing
                    let captureData = CaptureData(
                        jpeg: Data(),
                        depth: Data(),
                        metadata: sampleCaptureMetadata,
                        timestamp: Date()
                    )

                    let filtered = await MetadataFilterService.filterAll(
                        captureData: captureData,
                        settings: settings
                    )

                    // Verify consistency
                    if location == .none {
                        XCTAssertNil(filtered.location, "Location should be nil for level none")
                    }
                    if timestamp == .none {
                        XCTAssertNil(filtered.timestamp, "Timestamp should be nil for level none")
                    }
                    if deviceInfo == .none {
                        XCTAssertNil(filtered.deviceModel, "DeviceModel should be nil for level none")
                    }

                    if location == .precise {
                        XCTAssertNotNil(filtered.location?.latitude, "Precise should have latitude")
                        XCTAssertNotNil(filtered.location?.longitude, "Precise should have longitude")
                    }

                    if timestamp == .exact {
                        XCTAssertTrue(filtered.timestamp?.contains("T") ?? false, "Exact should have time")
                    }

                    if deviceInfo == .full {
                        XCTAssertTrue(filtered.deviceModel?.contains("/") ?? false, "Full should have separator")
                    }
                }
            }
        }
    }
}
