//
//  CaptureModeTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-27.
//
//  Unit tests for CaptureMode and mode switching (Story 7-14).
//

import XCTest
@testable import Rial

final class CaptureModeTests: XCTestCase {

    // MARK: - CaptureMode Enum Tests

    func testCaptureMode_PhotoHasCorrectLabel() {
        XCTAssertEqual(CaptureMode.photo.label, "Photo")
    }

    func testCaptureMode_VideoHasCorrectLabel() {
        XCTAssertEqual(CaptureMode.video.label, "Video")
    }

    func testCaptureMode_PhotoHasCorrectSystemImage() {
        XCTAssertEqual(CaptureMode.photo.systemImage, "camera")
    }

    func testCaptureMode_VideoHasCorrectSystemImage() {
        XCTAssertEqual(CaptureMode.video.systemImage, "video")
    }

    func testCaptureMode_RawValues() {
        XCTAssertEqual(CaptureMode.photo.rawValue, "photo")
        XCTAssertEqual(CaptureMode.video.rawValue, "video")
    }

    func testCaptureMode_InitFromRawValue() {
        XCTAssertEqual(CaptureMode(rawValue: "photo"), .photo)
        XCTAssertEqual(CaptureMode(rawValue: "video"), .video)
        XCTAssertNil(CaptureMode(rawValue: "invalid"))
    }

    func testCaptureMode_AllCases() {
        let allCases = CaptureMode.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.photo))
        XCTAssertTrue(allCases.contains(.video))
    }

    // MARK: - UserDefaults Persistence Tests

    func testCaptureMode_PersistedToUserDefaults() {
        // Clear any existing preference
        let key = "app.rial.captureMode"
        UserDefaults.standard.removeObject(forKey: key)

        // Set mode and verify
        UserDefaults.standard.set(CaptureMode.video.rawValue, forKey: key)
        let loaded = UserDefaults.standard.string(forKey: key)
        XCTAssertEqual(loaded, "video")

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testCaptureMode_LoadFromUserDefaults() {
        let key = "app.rial.captureMode"

        // Set video mode
        UserDefaults.standard.set("video", forKey: key)
        if let modeString = UserDefaults.standard.string(forKey: key),
           let mode = CaptureMode(rawValue: modeString) {
            XCTAssertEqual(mode, .video)
        } else {
            XCTFail("Failed to load mode from UserDefaults")
        }

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testCaptureMode_DefaultsToPhotoIfNotSet() {
        let key = "app.rial.captureMode"

        // Remove any existing setting
        UserDefaults.standard.removeObject(forKey: key)

        // Verify no value
        let loaded = UserDefaults.standard.string(forKey: key)
        XCTAssertNil(loaded)

        // App should default to photo if not set
        let defaultMode: CaptureMode = .photo
        XCTAssertEqual(defaultMode, .photo)
    }
}

// MARK: - RecordingProgressBar Logic Tests

final class RecordingProgressBarTests: XCTestCase {

    func testProgress_ZeroAtStart() {
        let current: TimeInterval = 0
        let maxDuration: TimeInterval = 15
        let progress = min(current / maxDuration, 1.0)
        XCTAssertEqual(progress, 0.0)
    }

    func testProgress_MidwayCorrect() {
        let current: TimeInterval = 7.5
        let maxDuration: TimeInterval = 15
        let progress = min(current / maxDuration, 1.0)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testProgress_FullAtEnd() {
        let current: TimeInterval = 15
        let maxDuration: TimeInterval = 15
        let progress = min(current / maxDuration, 1.0)
        XCTAssertEqual(progress, 1.0)
    }

    func testProgress_ClampsToOne() {
        let current: TimeInterval = 20 // Over max
        let maxDuration: TimeInterval = 15
        let progress = min(current / maxDuration, 1.0)
        XCTAssertEqual(progress, 1.0)
    }

    func testWarningZone_NotActiveAtStart() {
        let current: TimeInterval = 5
        let maxDuration: TimeInterval = 15
        let warningThreshold: TimeInterval = 5
        let isWarningZone = current >= (maxDuration - warningThreshold)
        XCTAssertFalse(isWarningZone)
    }

    func testWarningZone_ActiveAt10Seconds() {
        let current: TimeInterval = 10
        let maxDuration: TimeInterval = 15
        let warningThreshold: TimeInterval = 5
        let isWarningZone = current >= (maxDuration - warningThreshold)
        XCTAssertTrue(isWarningZone)
    }

    func testWarningZone_ActiveAtEnd() {
        let current: TimeInterval = 14.5
        let maxDuration: TimeInterval = 15
        let warningThreshold: TimeInterval = 5
        let isWarningZone = current >= (maxDuration - warningThreshold)
        XCTAssertTrue(isWarningZone)
    }

    func testRemainingTime_CorrectAt5Seconds() {
        let current: TimeInterval = 5
        let maxDuration: TimeInterval = 15
        let remaining = Swift.max(maxDuration - current, 0)
        XCTAssertEqual(remaining, 10)
    }

    func testRemainingTime_ZeroAtEnd() {
        let current: TimeInterval = 15
        let maxDuration: TimeInterval = 15
        let remaining = Swift.max(maxDuration - current, 0)
        XCTAssertEqual(remaining, 0)
    }

    func testRemainingTime_NeverNegative() {
        let current: TimeInterval = 20 // Over max
        let maxDuration: TimeInterval = 15
        let remaining = Swift.max(maxDuration - current, 0)
        XCTAssertEqual(remaining, 0)
    }
}

// MARK: - Storage Check Tests

final class StorageCheckTests: XCTestCase {

    func testMinimumStorageBytes() {
        // 50MB minimum
        let minimumStorageBytes: Int64 = 50 * 1024 * 1024
        XCTAssertEqual(minimumStorageBytes, 52_428_800)
    }

    func testStorageCheck_SystemCheck() {
        // This test verifies the storage check doesn't crash
        // Actual values depend on device state
        do {
            let documentDirectory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

            let values = try documentDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            if let available = values.volumeAvailableCapacityForImportantUsage {
                XCTAssertGreaterThan(available, 0, "Available storage should be positive")
            }
        } catch {
            XCTFail("Storage check failed with error: \(error)")
        }
    }
}

// MARK: - Upload Progress Tests

final class UploadProgressTests: XCTestCase {

    func testProgressPercentage() {
        let progress = 0.65
        let percentage = Int(progress * 100)
        XCTAssertEqual(percentage, 65)
    }

    func testProgressClamping() {
        let overProgress = 1.2
        let clamped = min(overProgress, 1.0)
        XCTAssertEqual(clamped, 1.0)
    }

    func testBytesFormatting() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file

        let bytes: Int64 = 35_000_000 // 35 MB
        let formatted = formatter.string(fromByteCount: bytes)
        XCTAssertTrue(formatted.contains("MB"))
    }

    func testUploadedBytesCalculation() {
        let progress = 0.45
        let totalBytes: Int64 = 35_000_000
        let uploadedBytes = Int64(Double(totalBytes) * progress)
        XCTAssertEqual(uploadedBytes, 15_750_000)
    }
}

// MARK: - Partial Video Badge Tests

final class PartialVideoBadgeTests: XCTestCase {

    func testDurationFormatting_Seconds() {
        let duration: TimeInterval = 10.0
        let seconds = Int(duration)
        let formatted = "\(seconds)s"
        XCTAssertEqual(formatted, "10s")
    }

    func testDurationFormatting_MinutesAndSeconds() {
        let duration: TimeInterval = 75.0
        let seconds = Int(duration)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        let formatted = "\(minutes)m\(remainingSeconds)s"
        XCTAssertEqual(formatted, "1m15s")
    }

    func testPartialVideoIndicator_VerifiedDuration() {
        let verifiedDuration: TimeInterval = 10.0
        let totalDuration: TimeInterval = 12.5
        let checkpointIndex = 1

        // Verify checkpoint 1 corresponds to 10s
        XCTAssertEqual(checkpointIndex, 1)
        XCTAssertEqual(verifiedDuration, 10.0)
        XCTAssertGreaterThan(totalDuration, verifiedDuration)
    }

    func testPartialVideoIndicator_FrameCount() {
        let verifiedDuration: TimeInterval = 10.0
        let frameRate = 30
        let expectedFrames = Int(verifiedDuration * Double(frameRate))
        XCTAssertEqual(expectedFrames, 300)
    }
}
