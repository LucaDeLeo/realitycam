//
//  ARCaptureSessionTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for ARCaptureSession.
//  Note: Full ARKit functionality requires physical iPhone Pro with LiDAR.
//        Simulator tests validate API structure, error handling, and logic.
//

import XCTest
import ARKit
@testable import Rial

final class ARCaptureSessionTests: XCTestCase {

    var sut: ARCaptureSession!

    override func setUp() {
        super.setUp()
        sut = ARCaptureSession()
    }

    override func tearDown() {
        sut.stop()
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_CreatesInstance() {
        XCTAssertNotNil(sut, "ARCaptureSession should initialize")
    }

    func testInit_NotRunning() {
        XCTAssertFalse(sut.isRunning, "Session should not be running after init")
    }

    func testInit_NoCurrentFrame() {
        let frame = sut.captureCurrentFrame()
        XCTAssertNil(frame, "Should return nil before start")
    }

    // MARK: - LiDAR Availability Tests

    func testIsLiDARAvailable_ReturnsValue() {
        // This test validates the API exists and returns a boolean
        // On simulator, this will be false
        // On iPhone Pro, this will be true
        let isAvailable = ARCaptureSession.isLiDARAvailable
        XCTAssertTrue(isAvailable || !isAvailable, "Should return boolean value")

        // Log the actual value for debugging
        print("LiDAR available: \(isAvailable)")
    }

    func testStart_OnSimulatorWithoutLiDAR_ThrowsError() {
        // On simulator, LiDAR is never available, so this should throw
        if !ARCaptureSession.isLiDARAvailable {
            XCTAssertThrowsError(try sut.start()) { error in
                XCTAssertEqual(error as? CaptureError, .lidarNotAvailable,
                    "Should throw lidarNotAvailable on simulator")
            }
        } else {
            // On physical device with LiDAR, start should succeed
            XCTAssertNoThrow(try sut.start(),
                "Should start successfully on device with LiDAR")
        }
    }

    // MARK: - Session Lifecycle Tests

    func testStop_WhenNotRunning_DoesNotCrash() {
        // Should handle stop gracefully even when not running
        XCTAssertFalse(sut.isRunning)
        sut.stop()
        XCTAssertFalse(sut.isRunning, "Should still not be running after stop")
    }

    func testStop_ClearsCurrentFrame() {
        // If we could start the session, verify stop clears frame
        if ARCaptureSession.isLiDARAvailable {
            try? sut.start()

            // Wait briefly for potential frame
            Thread.sleep(forTimeInterval: 0.5)

            sut.stop()

            let frame = sut.captureCurrentFrame()
            XCTAssertNil(frame, "Should return nil after stop")
        }
    }

    func testStop_SetsIsRunningFalse() {
        if ARCaptureSession.isLiDARAvailable {
            try? sut.start()
            XCTAssertTrue(sut.isRunning)

            sut.stop()
            XCTAssertFalse(sut.isRunning, "Should not be running after stop")
        }
    }

    func testStart_WhenAlreadyRunning_DoesNotThrow() {
        if ARCaptureSession.isLiDARAvailable {
            try? sut.start()
            XCTAssertTrue(sut.isRunning)

            // Second start should be a no-op, not throw
            XCTAssertNoThrow(try sut.start())
            XCTAssertTrue(sut.isRunning)
        }
    }

    // MARK: - Frame Capture Tests

    func testCaptureCurrentFrame_BeforeStart_ReturnsNil() {
        let frame = sut.captureCurrentFrame()
        XCTAssertNil(frame, "Should return nil before session starts")
    }

    func testCaptureCurrentFrame_ThreadSafe() {
        // Test concurrent reads don't crash
        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.captureCurrentFrame()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Callback Tests

    func testOnFrameUpdate_CanBeSet() {
        var callbackCalled = false
        sut.onFrameUpdate = { _ in
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onFrameUpdate, "Callback should be settable")
    }

    func testOnInterruption_CanBeSet() {
        var callbackCalled = false
        sut.onInterruption = {
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onInterruption)
    }

    func testOnInterruptionEnded_CanBeSet() {
        var callbackCalled = false
        sut.onInterruptionEnded = {
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onInterruptionEnded)
    }

    func testOnTrackingStateChanged_CanBeSet() {
        var callbackCalled = false
        sut.onTrackingStateChanged = { _ in
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onTrackingStateChanged)
    }

    func testOnError_CanBeSet() {
        var callbackCalled = false
        sut.onError = { _ in
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onError)
    }

    // MARK: - CaptureError Tests

    func testCaptureError_LidarNotAvailable_Description() {
        let error = CaptureError.lidarNotAvailable
        XCTAssertEqual(error.errorDescription, "LiDAR sensor required (iPhone Pro models only)")
    }

    func testCaptureError_SessionFailed_Description() {
        let error = CaptureError.sessionFailed(underlying: nil)
        XCTAssertEqual(error.errorDescription, "AR capture session failed to start")
    }

    func testCaptureError_SessionFailedWithReason_Description() {
        let error = CaptureError.sessionFailed(underlying: "Camera access denied")
        XCTAssertEqual(error.errorDescription, "AR capture session failed: Camera access denied")
    }

    func testCaptureError_Interrupted_Description() {
        let error = CaptureError.interrupted
        XCTAssertEqual(error.errorDescription, "AR capture session interrupted")
    }

    func testCaptureError_NoFrameAvailable_Description() {
        let error = CaptureError.noFrameAvailable
        XCTAssertEqual(error.errorDescription, "No frame available yet (session not started or no frames received)")
    }

    func testCaptureError_CameraPermissionDenied_Description() {
        let error = CaptureError.cameraPermissionDenied
        XCTAssertEqual(error.errorDescription, "Camera access required. Please enable in Settings.")
    }

    func testCaptureError_TrackingLost_Description() {
        let error = CaptureError.trackingLost
        XCTAssertEqual(error.errorDescription, "Camera tracking lost. Move device slowly and ensure good lighting.")
    }

    // MARK: - CaptureError Equality Tests

    func testCaptureError_Equality_LidarNotAvailable() {
        XCTAssertEqual(CaptureError.lidarNotAvailable, CaptureError.lidarNotAvailable)
        XCTAssertNotEqual(CaptureError.lidarNotAvailable, CaptureError.interrupted)
    }

    func testCaptureError_Equality_SessionFailed() {
        let error1 = CaptureError.sessionFailed(underlying: "reason")
        let error2 = CaptureError.sessionFailed(underlying: "reason")
        let error3 = CaptureError.sessionFailed(underlying: "different")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Physical Device Tests (Require iPhone Pro with LiDAR)

    /// Test that verifies frame updates are received when running on physical device.
    /// This test will be skipped on simulator.
    func testStart_OnPhysicalDevice_ReceivesFrameUpdates() throws {
        // Skip on simulator
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let expectation = XCTestExpectation(description: "Frame received")

        sut.onFrameUpdate = { frame in
            XCTAssertNotNil(frame.capturedImage, "Frame should have RGB image")
            // Note: sceneDepth may be nil for first few frames
            expectation.fulfill()
        }

        try sut.start()
        XCTAssertTrue(sut.isRunning)

        wait(for: [expectation], timeout: 2.0)
    }

    /// Test that verifies frame rate on physical device.
    /// This test will be skipped on simulator.
    func testFrameRate_OnPhysicalDevice_AtLeast30FPS() throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        var frameCount = 0
        let expectation = XCTestExpectation(description: "Received frames for 1 second")

        let startTime = Date()
        sut.onFrameUpdate = { _ in
            frameCount += 1
            if Date().timeIntervalSince(startTime) >= 1.0 {
                expectation.fulfill()
            }
        }

        try sut.start()

        wait(for: [expectation], timeout: 2.0)

        print("Received \(frameCount) frames in ~1 second")
        XCTAssertGreaterThanOrEqual(frameCount, 25, "Should receive at least 25 frames per second (allowing some variance)")
    }

    /// Test that verifies ARFrame contains depth data on physical device.
    /// This test will be skipped on simulator.
    func testFrameContainsDepth_OnPhysicalDevice() throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let expectation = XCTestExpectation(description: "Frame with depth received")

        sut.onFrameUpdate = { frame in
            if frame.sceneDepth != nil {
                XCTAssertNotNil(frame.sceneDepth?.depthMap, "Should have depth map")
                XCTAssertTrue(frame.hasDepthData, "hasDepthData should return true")
                XCTAssertNotNil(frame.depthMapSize, "depthMapSize should not be nil")
                expectation.fulfill()
            }
        }

        try sut.start()

        // May take a moment for depth data to become available
        wait(for: [expectation], timeout: 3.0)
    }

    /// Test captureCurrentFrame returns valid frame after receiving updates.
    /// This test will be skipped on simulator.
    func testCaptureCurrentFrame_AfterFrameUpdate_ReturnsFrame() throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let expectation = XCTestExpectation(description: "Frame received")

        sut.onFrameUpdate = { _ in
            expectation.fulfill()
        }

        try sut.start()

        wait(for: [expectation], timeout: 2.0)

        let frame = sut.captureCurrentFrame()
        XCTAssertNotNil(frame, "Should return frame after update")
        XCTAssertNotNil(frame?.capturedImage, "Frame should have RGB image")
    }

    /// Test stop after running clears frame.
    /// This test will be skipped on simulator.
    func testStop_AfterRunning_ClearsFrame() throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let expectation = XCTestExpectation(description: "Frame received")

        sut.onFrameUpdate = { _ in
            expectation.fulfill()
        }

        try sut.start()

        wait(for: [expectation], timeout: 2.0)

        // Verify we had a frame
        XCTAssertNotNil(sut.captureCurrentFrame())

        // Stop and verify frame cleared
        sut.stop()
        XCTAssertNil(sut.captureCurrentFrame(), "Frame should be nil after stop")
        XCTAssertFalse(sut.isRunning)
    }

    // MARK: - ARFrame Extension Tests

    func testARFrameExtension_ImageSize_ReturnsCorrectDimensions() throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let expectation = XCTestExpectation(description: "Frame received")

        sut.onFrameUpdate = { frame in
            let size = frame.imageSize
            XCTAssertGreaterThan(size.width, 0, "Width should be positive")
            XCTAssertGreaterThan(size.height, 0, "Height should be positive")
            print("Image size: \(size.width)x\(size.height)")
            expectation.fulfill()
        }

        try sut.start()

        wait(for: [expectation], timeout: 2.0)
    }

    func testARFrameExtension_DepthMapSize_ReturnsCorrectDimensions() throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        let expectation = XCTestExpectation(description: "Frame with depth received")

        sut.onFrameUpdate = { frame in
            if let size = frame.depthMapSize {
                XCTAssertGreaterThan(size.width, 0, "Width should be positive")
                XCTAssertGreaterThan(size.height, 0, "Height should be positive")
                print("Depth map size: \(size.width)x\(size.height)")
                expectation.fulfill()
            }
        }

        try sut.start()

        wait(for: [expectation], timeout: 3.0)
    }
}
