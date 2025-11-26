//
//  VideoRecordingSessionTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-26.
//
//  Unit tests for VideoRecordingSession.
//  Note: Full ARKit + AVAssetWriter functionality requires physical iPhone Pro with LiDAR.
//        Simulator tests validate API structure, error handling, state transitions, and logic.
//

import XCTest
import ARKit
@testable import Rial

final class VideoRecordingSessionTests: XCTestCase {

    var arCaptureSession: ARCaptureSession!
    var sut: VideoRecordingSession!

    override func setUp() {
        super.setUp()
        arCaptureSession = ARCaptureSession()
        sut = VideoRecordingSession(arCaptureSession: arCaptureSession)
    }

    override func tearDown() {
        sut.cancelRecording()
        arCaptureSession.stop()
        sut = nil
        arCaptureSession = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_CreatesInstance() {
        XCTAssertNotNil(sut, "VideoRecordingSession should initialize")
    }

    func testInit_StateIsIdle() {
        XCTAssertEqual(sut.state, .idle, "Initial state should be idle")
    }

    func testInit_FrameCountIsZero() {
        XCTAssertEqual(sut.frameCount, 0, "Initial frame count should be zero")
    }

    func testInit_OutputURLIsNil() {
        XCTAssertNil(sut.outputURL, "Initial output URL should be nil")
    }

    func testInit_DurationIsZero() {
        XCTAssertEqual(sut.duration, 0, "Initial duration should be zero")
    }

    func testInit_WasInterruptedIsFalse() {
        XCTAssertFalse(sut.wasInterrupted, "Initial wasInterrupted should be false")
    }

    // MARK: - Constants Tests

    func testMaxDuration_Is15Seconds() {
        XCTAssertEqual(VideoRecordingSession.maxDuration, 15.0, "Max duration should be 15 seconds")
    }

    func testTargetFrameRate_Is30FPS() {
        XCTAssertEqual(VideoRecordingSession.targetFrameRate, 30, "Target frame rate should be 30 fps")
    }

    // MARK: - RecordingState Tests

    func testRecordingState_Equality_Idle() {
        XCTAssertEqual(RecordingState.idle, RecordingState.idle)
        XCTAssertNotEqual(RecordingState.idle, RecordingState.recording)
    }

    func testRecordingState_Equality_Recording() {
        XCTAssertEqual(RecordingState.recording, RecordingState.recording)
        XCTAssertNotEqual(RecordingState.recording, RecordingState.processing)
    }

    func testRecordingState_Equality_Processing() {
        XCTAssertEqual(RecordingState.processing, RecordingState.processing)
        XCTAssertNotEqual(RecordingState.processing, RecordingState.idle)
    }

    func testRecordingState_Equality_Error() {
        let error1 = RecordingState.error(.sessionNotRunning)
        let error2 = RecordingState.error(.sessionNotRunning)
        let error3 = RecordingState.error(.interrupted)

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - VideoRecordingError Tests

    func testVideoRecordingError_SessionNotRunning_Description() {
        let error = VideoRecordingError.sessionNotRunning
        XCTAssertEqual(error.errorDescription, "AR session is not running")
    }

    func testVideoRecordingError_WriterCreationFailed_Description() {
        let error = VideoRecordingError.writerCreationFailed
        XCTAssertEqual(error.errorDescription, "Failed to create video writer")
    }

    func testVideoRecordingError_InputCreationFailed_Description() {
        let error = VideoRecordingError.inputCreationFailed
        XCTAssertEqual(error.errorDescription, "Failed to create video input")
    }

    func testVideoRecordingError_WritingFailed_Description() {
        let error = VideoRecordingError.writingFailed("Test reason")
        XCTAssertEqual(error.errorDescription, "Video writing failed: Test reason")
    }

    func testVideoRecordingError_Interrupted_Description() {
        let error = VideoRecordingError.interrupted
        XCTAssertEqual(error.errorDescription, "Recording was interrupted")
    }

    func testVideoRecordingError_MaxDurationReached_Description() {
        let error = VideoRecordingError.maxDurationReached
        XCTAssertEqual(error.errorDescription, "Maximum recording duration reached")
    }

    func testVideoRecordingError_NoFramesCaptured_Description() {
        let error = VideoRecordingError.noFramesCaptured
        XCTAssertEqual(error.errorDescription, "No frames were captured")
    }

    func testVideoRecordingError_InvalidPixelFormat_Description() {
        let error = VideoRecordingError.invalidPixelFormat
        XCTAssertEqual(error.errorDescription, "Invalid pixel buffer format")
    }

    func testVideoRecordingError_AlreadyRecording_Description() {
        let error = VideoRecordingError.alreadyRecording
        XCTAssertEqual(error.errorDescription, "Already recording")
    }

    func testVideoRecordingError_NotRecording_Description() {
        let error = VideoRecordingError.notRecording
        XCTAssertEqual(error.errorDescription, "Not currently recording")
    }

    // MARK: - VideoRecordingError Equality Tests

    func testVideoRecordingError_Equality_SessionNotRunning() {
        XCTAssertEqual(VideoRecordingError.sessionNotRunning, VideoRecordingError.sessionNotRunning)
        XCTAssertNotEqual(VideoRecordingError.sessionNotRunning, VideoRecordingError.interrupted)
    }

    func testVideoRecordingError_Equality_WritingFailed() {
        let error1 = VideoRecordingError.writingFailed("reason")
        let error2 = VideoRecordingError.writingFailed("reason")
        let error3 = VideoRecordingError.writingFailed("different")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Start Recording Tests

    func testStartRecording_WhenSessionNotRunning_ThrowsError() async {
        // AR session is not started, so should throw sessionNotRunning
        do {
            try await sut.startRecording()
            XCTFail("Should throw sessionNotRunning error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .sessionNotRunning)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testStartRecording_WhenAlreadyRecording_ThrowsError() async throws {
        // Skip on simulator
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for frames
        let expectation = XCTestExpectation(description: "Frame received")
        arCaptureSession.onFrameUpdate = { _ in
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2.0)

        // Start recording
        try await sut.startRecording()
        XCTAssertEqual(sut.state, .recording)

        // Try to start again - should fail
        do {
            try await sut.startRecording()
            XCTFail("Should throw alreadyRecording error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .alreadyRecording)
        }

        // Cleanup
        sut.cancelRecording()
    }

    // MARK: - Stop Recording Tests

    func testStopRecording_WhenNotRecording_ThrowsError() async {
        do {
            try await sut.stopRecording()
            XCTFail("Should throw notRecording error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .notRecording)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cancel Recording Tests

    func testCancelRecording_WhenNotRecording_DoesNotCrash() {
        // Should handle cancel gracefully when not recording
        sut.cancelRecording()
        XCTAssertEqual(sut.state, .idle)
    }

    func testCancelRecording_CleansUpState() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for frames
        let expectation = XCTestExpectation(description: "Frame received")
        arCaptureSession.onFrameUpdate = { _ in
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2.0)

        // Start recording
        try await sut.startRecording()
        XCTAssertEqual(sut.state, .recording)

        // Cancel
        sut.cancelRecording()
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.frameCount, 0)
    }

    // MARK: - Callback Tests

    func testOnFrameProcessed_CanBeSet() {
        var callbackCalled = false
        sut.onFrameProcessed = { _, _ in
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onFrameProcessed)
    }

    func testOnRecordingStateChanged_CanBeSet() {
        var callbackCalled = false
        sut.onRecordingStateChanged = { _ in
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onRecordingStateChanged)
    }

    func testOnError_CanBeSet() {
        var callbackCalled = false
        sut.onError = { _ in
            callbackCalled = true
        }

        XCTAssertNotNil(sut.onError)
    }

    // MARK: - Delegate Tests

    func testDelegate_CanBeSet() {
        let mockDelegate = MockVideoRecordingDelegate()
        sut.delegate = mockDelegate

        XCTAssertNotNil(sut.delegate)
    }

    // MARK: - Thread Safety Tests

    func testFrameCount_ThreadSafe() {
        // Test concurrent reads don't crash
        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.frameCount
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testState_ThreadSafe() {
        // Test concurrent reads don't crash
        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.state
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testDuration_ThreadSafe() {
        // Test concurrent reads don't crash
        let expectation = XCTestExpectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = sut.duration
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Physical Device Tests (Require iPhone Pro with LiDAR)

    /// Test that recording starts and stops successfully on physical device.
    func testFullRecordingCycle_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for frames
        let frameExpectation = XCTestExpectation(description: "Frame received")
        arCaptureSession.onFrameUpdate = { _ in
            frameExpectation.fulfill()
        }
        await fulfillment(of: [frameExpectation], timeout: 2.0)

        // Start recording
        try await sut.startRecording()
        XCTAssertEqual(sut.state, .recording)
        XCTAssertNotNil(sut.outputURL)

        // Record for 1 second
        let recordExpectation = XCTestExpectation(description: "Recording time")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            recordExpectation.fulfill()
        }
        await fulfillment(of: [recordExpectation], timeout: 2.0)

        // Stop recording
        let outputURL = try await sut.stopRecording()
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan(sut.frameCount, 0)

        // Cleanup
        try? FileManager.default.removeItem(at: outputURL)
    }

    /// Test that frame callbacks are called during recording.
    func testFrameCallback_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for initial frames
        let frameExpectation = XCTestExpectation(description: "Initial frame received")
        arCaptureSession.onFrameUpdate = { _ in
            frameExpectation.fulfill()
        }
        await fulfillment(of: [frameExpectation], timeout: 2.0)

        // Set up frame callback
        var framesProcessed = 0
        let callbackExpectation = XCTestExpectation(description: "Frame callbacks received")
        callbackExpectation.expectedFulfillmentCount = 5

        sut.onFrameProcessed = { frame, frameNumber in
            framesProcessed += 1
            XCTAssertNotNil(frame.capturedImage)
            XCTAssertGreaterThan(frameNumber, 0)
            if framesProcessed <= 5 {
                callbackExpectation.fulfill()
            }
        }

        // Start recording
        try await sut.startRecording()

        // Wait for callbacks
        await fulfillment(of: [callbackExpectation], timeout: 2.0)

        // Stop recording
        _ = try await sut.stopRecording()

        XCTAssertGreaterThanOrEqual(framesProcessed, 5)
    }

    /// Test that state change callback is called during recording lifecycle.
    func testStateChangeCallback_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for frames
        let frameExpectation = XCTestExpectation(description: "Frame received")
        arCaptureSession.onFrameUpdate = { _ in
            frameExpectation.fulfill()
        }
        await fulfillment(of: [frameExpectation], timeout: 2.0)

        // Set up state callback
        var stateChanges: [RecordingState] = []
        sut.onRecordingStateChanged = { state in
            stateChanges.append(state)
        }

        // Start recording
        try await sut.startRecording()

        // Brief delay to ensure frame processing starts
        try await Task.sleep(nanoseconds: 500_000_000)

        // Stop recording
        _ = try await sut.stopRecording()

        // Verify state transitions
        XCTAssertTrue(stateChanges.contains(.recording), "Should have transitioned to recording")
        XCTAssertTrue(stateChanges.contains(.processing), "Should have transitioned to processing")
        XCTAssertTrue(stateChanges.contains(.idle), "Should have transitioned back to idle")
    }

    /// Test video file is created with valid content.
    func testVideoFileCreation_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for frames
        let frameExpectation = XCTestExpectation(description: "Frame received")
        arCaptureSession.onFrameUpdate = { _ in
            frameExpectation.fulfill()
        }
        await fulfillment(of: [frameExpectation], timeout: 2.0)

        // Start recording
        try await sut.startRecording()

        // Record for 0.5 seconds
        try await Task.sleep(nanoseconds: 500_000_000)

        // Stop recording
        let outputURL = try await sut.stopRecording()

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        // Verify file has content
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Video file should have content")

        // Verify file is a valid video
        let asset = AVAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0, "Video should have duration")

        // Cleanup
        try? FileManager.default.removeItem(at: outputURL)
    }

    /// Test that delegate receives events during recording.
    func testDelegate_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for frames
        let frameExpectation = XCTestExpectation(description: "Frame received")
        arCaptureSession.onFrameUpdate = { _ in
            frameExpectation.fulfill()
        }
        await fulfillment(of: [frameExpectation], timeout: 2.0)

        // Set up delegate
        let mockDelegate = MockVideoRecordingDelegate()
        sut.delegate = mockDelegate

        // Start recording
        try await sut.startRecording()

        // Record briefly
        try await Task.sleep(nanoseconds: 500_000_000)

        // Stop recording
        _ = try await sut.stopRecording()

        // Verify delegate was called
        XCTAssertGreaterThan(mockDelegate.frameProcessedCount, 0)
        XCTAssertGreaterThan(mockDelegate.stateChanges.count, 0)
    }

    /// Test duration tracking during recording.
    func testDuration_OnPhysicalDevice() async throws {
        guard ARCaptureSession.isLiDARAvailable else {
            throw XCTSkip("LiDAR not available - run on physical iPhone Pro device")
        }

        // Start AR session
        try arCaptureSession.start()

        // Wait for frames
        let frameExpectation = XCTestExpectation(description: "Frame received")
        arCaptureSession.onFrameUpdate = { _ in
            frameExpectation.fulfill()
        }
        await fulfillment(of: [frameExpectation], timeout: 2.0)

        // Start recording
        try await sut.startRecording()
        XCTAssertEqual(sut.duration, 0, accuracy: 0.1)

        // Wait 1 second
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Check duration
        XCTAssertEqual(sut.duration, 1.0, accuracy: 0.2)

        // Stop recording
        _ = try await sut.stopRecording()
    }
}

// MARK: - Mock Delegate

final class MockVideoRecordingDelegate: VideoRecordingSessionDelegate {
    var frameProcessedCount = 0
    var stateChanges: [RecordingState] = []
    var errors: [VideoRecordingError] = []
    var wasInterruptedCalled = false

    func recordingSession(_ session: VideoRecordingSession, didProcessFrame frame: ARFrame, frameNumber: Int) {
        frameProcessedCount += 1
    }

    func recordingSession(_ session: VideoRecordingSession, didChangeState state: RecordingState) {
        stateChanges.append(state)
    }

    func recordingSession(_ session: VideoRecordingSession, didEncounterError error: VideoRecordingError) {
        errors.append(error)
    }

    func recordingSessionWasInterrupted(_ session: VideoRecordingSession) {
        wasInterruptedCalled = true
    }
}
