//
//  VideoRecordingSession.swift
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  Coordinates ARKit video recording with AVAssetWriter for synchronized
//  RGB video and LiDAR depth capture.
//

import Foundation
import ARKit
import AVFoundation
import os.log

// MARK: - RecordingState

/// State of the video recording session.
public enum RecordingState: Equatable, Sendable {
    /// Not recording
    case idle
    /// Actively recording video
    case recording
    /// Finalizing video file
    case processing
    /// Recording failed with error
    case error(VideoRecordingError)

    public static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.processing, .processing):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - VideoRecordingError

/// Errors that can occur during video recording.
public enum VideoRecordingError: Error, LocalizedError, Equatable {
    /// AR session is not running
    case sessionNotRunning
    /// Failed to create AVAssetWriter
    case writerCreationFailed
    /// Failed to create AVAssetWriterInput
    case inputCreationFailed
    /// AVAssetWriter failed during writing
    case writingFailed(String)
    /// Recording was interrupted (phone call, backgrounding)
    case interrupted
    /// Maximum recording duration reached
    case maxDurationReached
    /// No frames were captured
    case noFramesCaptured
    /// Invalid pixel buffer format
    case invalidPixelFormat
    /// Already recording
    case alreadyRecording
    /// Not currently recording
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .sessionNotRunning:
            return "AR session is not running"
        case .writerCreationFailed:
            return "Failed to create video writer"
        case .inputCreationFailed:
            return "Failed to create video input"
        case .writingFailed(let reason):
            return "Video writing failed: \(reason)"
        case .interrupted:
            return "Recording was interrupted"
        case .maxDurationReached:
            return "Maximum recording duration reached"
        case .noFramesCaptured:
            return "No frames were captured"
        case .invalidPixelFormat:
            return "Invalid pixel buffer format"
        case .alreadyRecording:
            return "Already recording"
        case .notRecording:
            return "Not currently recording"
        }
    }

    public static func == (lhs: VideoRecordingError, rhs: VideoRecordingError) -> Bool {
        switch (lhs, rhs) {
        case (.sessionNotRunning, .sessionNotRunning),
             (.writerCreationFailed, .writerCreationFailed),
             (.inputCreationFailed, .inputCreationFailed),
             (.interrupted, .interrupted),
             (.maxDurationReached, .maxDurationReached),
             (.noFramesCaptured, .noFramesCaptured),
             (.invalidPixelFormat, .invalidPixelFormat),
             (.alreadyRecording, .alreadyRecording),
             (.notRecording, .notRecording):
            return true
        case (.writingFailed(let lhsReason), .writingFailed(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}

// MARK: - VideoRecordingSessionDelegate

/// Delegate protocol for VideoRecordingSession events.
public protocol VideoRecordingSessionDelegate: AnyObject {
    /// Called when a frame is processed during recording.
    func recordingSession(_ session: VideoRecordingSession, didProcessFrame frame: ARFrame, frameNumber: Int)
    /// Called when the recording state changes.
    func recordingSession(_ session: VideoRecordingSession, didChangeState state: RecordingState)
    /// Called when an error occurs during recording.
    func recordingSession(_ session: VideoRecordingSession, didEncounterError error: VideoRecordingError)
    /// Called when the recording session is interrupted.
    func recordingSessionWasInterrupted(_ session: VideoRecordingSession)
}

// MARK: - Default implementations

public extension VideoRecordingSessionDelegate {
    func recordingSession(_ session: VideoRecordingSession, didProcessFrame frame: ARFrame, frameNumber: Int) {}
    func recordingSession(_ session: VideoRecordingSession, didChangeState state: RecordingState) {}
    func recordingSession(_ session: VideoRecordingSession, didEncounterError error: VideoRecordingError) {}
    func recordingSessionWasInterrupted(_ session: VideoRecordingSession) {}
}

// MARK: - VideoRecordingSession

/// Coordinates ARKit video recording with AVAssetWriter.
///
/// VideoRecordingSession wraps an ARSession and AVAssetWriter to record synchronized
/// RGB video frames at 30fps. It provides frame callbacks for downstream processing
/// (depth extraction, hash chain computation) and handles recording interruptions.
///
/// ## Usage
/// ```swift
/// let recordingSession = VideoRecordingSession(arCaptureSession: captureSession)
/// recordingSession.onFrameProcessed = { frame, frameNumber in
///     // Process frame for hash chain, depth extraction, etc.
/// }
///
/// try await recordingSession.startRecording()
/// // ... recording in progress ...
/// let result = try await recordingSession.stopRecording()
/// ```
///
/// ## Key Features
/// - 30fps video recording synchronized with ARKit
/// - HEVC codec with H.264 fallback
/// - 15-second maximum duration with auto-stop
/// - Frame delivery callbacks for downstream processing
/// - Graceful interruption handling
///
/// - Note: Requires iPhone Pro with LiDAR for depth capture.
public final class VideoRecordingSession: NSObject {

    // MARK: - Properties

    /// Logger for recording session events
    private static let logger = Logger(subsystem: "app.rial", category: "videorecording")

    /// Maximum recording duration in seconds
    public static let maxDuration: TimeInterval = 15.0

    /// Target frame rate for video recording
    public static let targetFrameRate: Int = 30

    /// Target bitrate for video encoding (10 Mbps)
    private static let targetBitrate: Int = 10_000_000

    /// Reference to the AR capture session
    private let arCaptureSession: ARCaptureSession

    /// AVAssetWriter for video encoding
    private var assetWriter: AVAssetWriter?

    /// Video input for AVAssetWriter
    private var videoInput: AVAssetWriterInput?

    /// Pixel buffer adaptor for efficient frame appending
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// Serial queue for thread-safe recording operations
    private let recordingQueue = DispatchQueue(label: "app.rial.videorecording", qos: .userInitiated)

    /// Current recording state
    private var _state: RecordingState = .idle

    /// Thread-safe state access
    private let stateLock = NSLock()

    /// Current recording state (thread-safe)
    public private(set) var state: RecordingState {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _state
        }
        set {
            stateLock.lock()
            let oldValue = _state
            _state = newValue
            stateLock.unlock()

            if oldValue != newValue {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.onRecordingStateChanged?(newValue)
                    self.delegate?.recordingSession(self, didChangeState: newValue)
                }
            }
        }
    }

    /// Number of frames recorded
    private var _frameCount: Int = 0

    /// Frame count lock
    private let frameCountLock = NSLock()

    /// Total frames recorded (thread-safe)
    public var frameCount: Int {
        frameCountLock.lock()
        defer { frameCountLock.unlock() }
        return _frameCount
    }

    /// Recording start timestamp (ARFrame.timestamp)
    private var startTimestamp: TimeInterval?

    /// Recording start time for duration tracking
    private var recordingStartTime: Date?

    /// Output URL for the recorded video
    public private(set) var outputURL: URL?

    /// Current recording duration in seconds
    public var duration: TimeInterval {
        guard let start = recordingStartTime, state == .recording else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Whether recording was interrupted
    public private(set) var wasInterrupted: Bool = false

    // MARK: - Callbacks

    /// Callback invoked for each processed frame during recording.
    /// Provides the ARFrame and frame number for downstream processing.
    public var onFrameProcessed: ((ARFrame, Int) -> Void)?

    /// Callback invoked when recording state changes.
    public var onRecordingStateChanged: ((RecordingState) -> Void)?

    /// Callback invoked when an error occurs.
    public var onError: ((VideoRecordingError) -> Void)?

    /// Delegate for recording events
    public weak var delegate: VideoRecordingSessionDelegate?

    // MARK: - Video Settings

    /// Video width in pixels (determined from first frame)
    private var videoWidth: Int = 1920

    /// Video height in pixels (determined from first frame)
    private var videoHeight: Int = 1080

    /// Whether first frame has been processed (to set dimensions)
    private var hasConfiguredDimensions: Bool = false

    /// Buffer for accumulating depth keyframes at 10fps
    private let depthKeyframeBuffer = DepthKeyframeBuffer()

    // MARK: - Initialization

    /// Creates a new VideoRecordingSession.
    ///
    /// - Parameter arCaptureSession: The ARCaptureSession to record from.
    public init(arCaptureSession: ARCaptureSession) {
        self.arCaptureSession = arCaptureSession
        super.init()
        Self.logger.debug("VideoRecordingSession initialized")
    }

    deinit {
        cleanup()
        Self.logger.debug("VideoRecordingSession deinitialized")
    }

    // MARK: - Public Methods

    /// Start video recording.
    ///
    /// Initializes AVAssetWriter and begins capturing frames from the ARSession.
    /// Recording will automatically stop at `maxDuration` (15 seconds).
    ///
    /// - Throws: `VideoRecordingError` if recording cannot start.
    public func startRecording() async throws {
        Self.logger.info("Starting video recording")

        // Check if already recording
        guard state == .idle else {
            Self.logger.warning("Cannot start recording - state is \(String(describing: self.state))")
            throw VideoRecordingError.alreadyRecording
        }

        // Verify AR session is running
        guard arCaptureSession.isRunning else {
            Self.logger.error("AR session not running")
            throw VideoRecordingError.sessionNotRunning
        }

        // Reset state
        _frameCount = 0
        startTimestamp = nil
        recordingStartTime = nil
        wasInterrupted = false
        hasConfiguredDimensions = false

        // Initialize depth keyframe buffer for new recording
        depthKeyframeBuffer.startRecording()

        // Create output URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mov"
        outputURL = tempDir.appendingPathComponent(fileName)

        guard let outputURL = outputURL else {
            Self.logger.error("Failed to create output URL")
            throw VideoRecordingError.writerCreationFailed
        }

        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)

        do {
            // Create AVAssetWriter
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

            // Configure video input with initial dimensions
            // Actual dimensions will be set from first frame
            try setupVideoInput()

            guard let assetWriter = assetWriter else {
                throw VideoRecordingError.writerCreationFailed
            }

            // Start writing
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)

            // Update state
            state = .recording
            recordingStartTime = Date()

            // Subscribe to frame updates
            setupFrameCallback()

            Self.logger.info("Video recording started - output: \(outputURL.lastPathComponent)")

        } catch let error as VideoRecordingError {
            cleanup()
            throw error
        } catch {
            Self.logger.error("Failed to start recording: \(error.localizedDescription)")
            cleanup()
            throw VideoRecordingError.writerCreationFailed
        }
    }

    /// Stop video recording.
    ///
    /// Finalizes the video file and returns the result including depth keyframe data.
    ///
    /// - Returns: `VideoRecordingResult` containing video URL and depth keyframe data.
    /// - Throws: `VideoRecordingError` if recording cannot be stopped.
    @discardableResult
    public func stopRecording() async throws -> VideoRecordingResult {
        Self.logger.info("Stopping video recording")

        guard state == .recording else {
            Self.logger.warning("Cannot stop recording - state is \(String(describing: self.state))")
            throw VideoRecordingError.notRecording
        }

        // Capture end time
        let endTime = Date()
        let startTime = recordingStartTime ?? endTime

        // Update state to processing
        state = .processing

        // Check if we captured any frames
        let finalFrameCount = frameCount
        if finalFrameCount == 0 {
            Self.logger.error("No frames captured")
            depthKeyframeBuffer.reset()
            cleanup()
            throw VideoRecordingError.noFramesCaptured
        }

        // Finish writing
        guard let assetWriter = assetWriter, let outputURL = outputURL else {
            depthKeyframeBuffer.reset()
            cleanup()
            throw VideoRecordingError.writerCreationFailed
        }

        // Mark inputs as finished
        videoInput?.markAsFinished()

        // Wait for writer to finish
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            assetWriter.finishWriting {
                continuation.resume()
            }
        }

        // Check writer status
        if assetWriter.status == .failed {
            let errorMessage = assetWriter.error?.localizedDescription ?? "Unknown error"
            Self.logger.error("AVAssetWriter failed: \(errorMessage)")
            depthKeyframeBuffer.reset()
            cleanup()
            throw VideoRecordingError.writingFailed(errorMessage)
        }

        // Finalize depth keyframe buffer (compresses data)
        let depthData = depthKeyframeBuffer.finalize()
        let depthKeyframeCount = depthData?.keyframeCount ?? 0

        let duration = self.duration
        Self.logger.info("Recording complete - \(finalFrameCount) frames, \(depthKeyframeCount) depth keyframes, \(String(format: "%.1f", duration))s, output: \(outputURL.lastPathComponent)")

        // Capture values before cleanup
        let savedURL = outputURL
        let savedWidth = videoWidth
        let savedHeight = videoHeight
        let savedWasInterrupted = wasInterrupted

        // Cleanup resources
        self.assetWriter = nil
        self.videoInput = nil
        self.pixelBufferAdaptor = nil
        self.state = .idle

        // Build result
        let result = VideoRecordingResult(
            videoURL: savedURL,
            frameCount: finalFrameCount,
            duration: duration,
            resolution: (width: savedWidth, height: savedHeight),
            codec: "hevc",
            wasInterrupted: savedWasInterrupted,
            startedAt: startTime,
            endedAt: endTime,
            depthKeyframeData: depthData
        )

        return result
    }

    /// Cancel recording without saving.
    public func cancelRecording() {
        Self.logger.info("Cancelling video recording")

        guard state == .recording || state == .processing else {
            return
        }

        assetWriter?.cancelWriting()

        // Delete partial file
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }

        // Reset depth buffer
        depthKeyframeBuffer.reset()

        cleanup()
    }

    /// Handle session interruption (phone call, backgrounding, etc.)
    public func handleInterruption() {
        Self.logger.warning("Recording interrupted")

        wasInterrupted = true

        recordingQueue.async { [weak self] in
            guard let self = self, self.state == .recording else { return }

            // Finalize what we have
            Task {
                do {
                    _ = try await self.stopRecording()
                    DispatchQueue.main.async {
                        self.delegate?.recordingSessionWasInterrupted(self)
                    }
                } catch {
                    Self.logger.error("Failed to save partial recording on interruption: \(error.localizedDescription)")
                    self.cleanup()
                    DispatchQueue.main.async {
                        self.state = .error(.interrupted)
                        self.delegate?.recordingSession(self, didEncounterError: .interrupted)
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Set up video input with codec selection.
    private func setupVideoInput() throws {
        // Check for HEVC support (A10+ chips, iOS 11+)
        let codec = selectCodec()

        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: Self.targetBitrate,
            AVVideoExpectedSourceFrameRateKey: Self.targetFrameRate
        ]

        // Add profile level for H.264 (HEVC uses automatic profile selection)
        if codec == AVVideoCodecType.h264 {
            compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)

        guard let videoInput = videoInput else {
            throw VideoRecordingError.inputCreationFailed
        }

        videoInput.expectsMediaDataInRealTime = true

        // Set up pixel buffer adaptor
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )

        guard let assetWriter = assetWriter else {
            throw VideoRecordingError.writerCreationFailed
        }

        if assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
            Self.logger.debug("Video input added with codec: \(codec.rawValue)")
        } else {
            throw VideoRecordingError.inputCreationFailed
        }
    }

    /// Select the best available codec (HEVC preferred, H.264 fallback).
    private func selectCodec() -> AVVideoCodecType {
        // HEVC is supported on A10+ chips (iPhone 7 and newer)
        // Since we require LiDAR (iPhone 12 Pro+), HEVC is always available
        if AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality) {
            Self.logger.debug("Using HEVC codec")
            return AVVideoCodecType.hevc
        } else {
            Self.logger.debug("Falling back to H.264 codec")
            return AVVideoCodecType.h264
        }
    }

    /// Set up frame callback from ARCaptureSession.
    private func setupFrameCallback() {
        let previousCallback = arCaptureSession.onFrameUpdate

        arCaptureSession.onFrameUpdate = { [weak self] frame in
            // Call previous callback first
            previousCallback?(frame)

            // Process frame for recording
            self?.handleFrame(frame)
        }
    }

    /// Handle incoming ARFrame from the ARSession.
    private func handleFrame(_ frame: ARFrame) {
        recordingQueue.async { [weak self] in
            guard let self = self else { return }

            // Only process if recording
            guard self.state == .recording else { return }

            // Configure dimensions from first frame
            if !self.hasConfiguredDimensions {
                self.configureFromFirstFrame(frame)
            }

            // Check for max duration
            if let start = self.startTimestamp {
                let elapsed = frame.timestamp - start
                if elapsed >= Self.maxDuration {
                    Self.logger.info("Max duration reached (\(Self.maxDuration)s)")
                    Task {
                        do {
                            _ = try await self.stopRecording()
                            DispatchQueue.main.async {
                                self.onError?(VideoRecordingError.maxDurationReached)
                                self.delegate?.recordingSession(self, didEncounterError: .maxDurationReached)
                            }
                        } catch {
                            Self.logger.error("Error stopping recording at max duration: \(error.localizedDescription)")
                        }
                    }
                    return
                }
            } else {
                self.startTimestamp = frame.timestamp
            }

            // Append frame to video
            self.appendFrame(frame)
        }
    }

    /// Configure video dimensions from the first frame.
    private func configureFromFirstFrame(_ frame: ARFrame) {
        let width = CVPixelBufferGetWidth(frame.capturedImage)
        let height = CVPixelBufferGetHeight(frame.capturedImage)

        // Only reconfigure if dimensions are different
        if width != videoWidth || height != videoHeight {
            Self.logger.info("Configuring video dimensions: \(width)x\(height)")

            // Store dimensions for metadata
            videoWidth = width
            videoHeight = height
        }

        hasConfiguredDimensions = true
    }

    /// Append a frame to the AVAssetWriter.
    private func appendFrame(_ frame: ARFrame) {
        guard state == .recording,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor else {
            return
        }

        // Check if ready for more data
        guard videoInput.isReadyForMoreMediaData else {
            Self.logger.warning("Video input not ready for more data - dropping frame")
            return
        }

        // Calculate presentation time relative to start
        guard let startTimestamp = startTimestamp else { return }
        let relativeTime = frame.timestamp - startTimestamp
        let presentationTime = CMTime(seconds: relativeTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        // Append pixel buffer
        if pixelBufferAdaptor.append(frame.capturedImage, withPresentationTime: presentationTime) {
            // Increment frame count
            frameCountLock.lock()
            _frameCount += 1
            let currentFrameCount = _frameCount
            frameCountLock.unlock()

            // Process depth keyframe (every 3rd frame for 10fps from 30fps)
            // This is done synchronously on the recording queue for thread safety
            depthKeyframeBuffer.processFrame(frame, frameNumber: currentFrameCount)

            // Log progress periodically
            if currentFrameCount % 30 == 0 {
                Self.logger.debug("Recorded \(currentFrameCount) frames (\(String(format: "%.1f", relativeTime))s)")
            }

            // Notify delegate/callback
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onFrameProcessed?(frame, currentFrameCount)
                self.delegate?.recordingSession(self, didProcessFrame: frame, frameNumber: currentFrameCount)
            }
        } else {
            Self.logger.warning("Failed to append pixel buffer at time \(String(format: "%.3f", relativeTime))")
        }
    }

    /// Clean up all resources.
    private func cleanup() {
        Self.logger.debug("Cleaning up VideoRecordingSession resources")

        // Cancel any active writing
        if assetWriter?.status == .writing {
            assetWriter?.cancelWriting()
        }

        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        startTimestamp = nil
        recordingStartTime = nil
        _frameCount = 0
        hasConfiguredDimensions = false
        state = .idle
    }
}

// MARK: - VideoCapture Result

/// Result of a video recording session.
public struct VideoRecordingResult: Sendable {
    /// URL of the recorded video file
    public let videoURL: URL

    /// Number of frames captured
    public let frameCount: Int

    /// Recording duration in seconds
    public let duration: TimeInterval

    /// Video resolution
    public let resolution: (width: Int, height: Int)

    /// Codec used for encoding
    public let codec: String

    /// Whether recording was interrupted
    public let wasInterrupted: Bool

    /// Recording start time
    public let startedAt: Date

    /// Recording end time
    public let endedAt: Date

    /// Depth keyframe data captured at 10fps (optional, may be nil if no depth data)
    public let depthKeyframeData: DepthKeyframeData?

    /// Number of depth keyframes captured (convenience property)
    public var depthKeyframeCount: Int {
        depthKeyframeData?.keyframeCount ?? 0
    }
}
