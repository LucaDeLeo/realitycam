//
//  CaptureViewModel.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  View model for capture screen managing AR session and capture flow.
//

import SwiftUI
import ARKit
import Combine
import os.log

/// View model managing the capture screen state and AR session.
///
/// Handles:
/// - AR session lifecycle (start/stop)
/// - Frame updates for depth visualization
/// - Photo capture and processing
/// - Video recording with hold-to-record
/// - Edge depth overlay for video mode (Story 7.3)
/// - Permission checking
/// - Error handling
///
/// ## Usage
/// ```swift
/// struct CaptureView: View {
///     @StateObject private var viewModel = CaptureViewModel()
///
///     var body: some View {
///         // ... UI
///         .onAppear { viewModel.start() }
///         .onDisappear { viewModel.stop() }
///     }
/// }
/// ```
@MainActor
final class CaptureViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "app.rial", category: "capture-viewmodel")

    // MARK: - UserDefaults Keys

    /// UserDefaults key for edge overlay visibility preference
    private static let edgeOverlayEnabledKey = "app.rial.edgeOverlayEnabled"

    // MARK: - Published Properties

    /// Whether AR session is running
    @Published private(set) var isRunning = false

    /// Whether capture is in progress
    @Published private(set) var isCapturing = false

    /// Current depth frame for visualization
    @Published private(set) var currentDepthFrame: DepthFrame?

    /// Current AR camera tracking state
    @Published private(set) var trackingState: ARCamera.TrackingState = .notAvailable

    /// Error message to display
    @Published var errorMessage: String?

    /// Whether LiDAR is available on this device
    @Published private(set) var isLiDARAvailable = ARCaptureSession.isLiDARAvailable

    /// Whether camera permission is granted
    @Published private(set) var hasCameraPermission = false

    /// Last captured photo for preview
    @Published private(set) var lastCapturedPhoto: UIImage?

    /// Whether showing capture preview
    @Published var showCapturePreview = false

    // MARK: - Video Recording Published Properties

    /// Whether video recording is in progress
    @Published private(set) var isRecordingVideo = false

    /// Current video recording duration in seconds
    @Published private(set) var recordingDuration: TimeInterval = 0

    /// Number of frames recorded in current session
    @Published private(set) var recordingFrameCount: Int = 0

    /// Maximum video recording duration (15 seconds)
    public static let maxRecordingDuration: TimeInterval = VideoRecordingSession.maxDuration

    // MARK: - Edge Overlay Properties (Story 7.3)

    /// Whether edge overlay is visible during video recording.
    /// Persisted to UserDefaults so preference survives app restarts.
    @Published var showEdgeOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showEdgeOverlay, forKey: Self.edgeOverlayEnabledKey)
            Self.logger.debug("Edge overlay visibility changed: \(self.showEdgeOverlay)")
        }
    }

    /// Edge detection threshold for Sobel operator.
    /// Higher values show fewer, more prominent edges.
    /// Default: 0.1 as specified in AC-7.3.5.
    public let edgeThreshold: Float = 0.1

    /// Near plane for edge coloring (meters).
    /// Objects closer than this appear cyan.
    public let edgeNearPlane: Float = 0.5

    /// Far plane for edge coloring (meters).
    /// Objects farther than this appear magenta.
    public let edgeFarPlane: Float = 5.0

    // MARK: - Private Properties

    /// AR capture session
    private let captureSession = ARCaptureSession()

    /// Frame processor for capture
    private let frameProcessor: FrameProcessor

    /// Capture store for saving
    private let captureStore: CaptureStore

    /// Assertion service for attestation
    private let assertionService: CaptureAssertionService

    /// Last captured data (for save/discard)
    private var pendingCapture: CaptureData?

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Video recording session
    private var videoRecordingSession: VideoRecordingSession?

    /// Timer for updating recording duration display
    private var recordingTimer: Timer?

    // MARK: - Initialization

    init(
        frameProcessor: FrameProcessor = FrameProcessor(),
        captureStore: CaptureStore? = nil,
        assertionService: CaptureAssertionService? = nil
    ) {
        self.frameProcessor = frameProcessor

        // Create default instances if not provided
        self.captureStore = captureStore ?? CaptureStore()
        let keychain = KeychainService()
        let attestation = DeviceAttestationService(keychain: keychain)
        self.assertionService = assertionService ?? CaptureAssertionService(attestation: attestation, keychain: keychain)

        // Load edge overlay preference from UserDefaults
        // Default to true if key doesn't exist (first launch)
        if UserDefaults.standard.object(forKey: Self.edgeOverlayEnabledKey) == nil {
            self.showEdgeOverlay = true
            UserDefaults.standard.set(true, forKey: Self.edgeOverlayEnabledKey)
        } else {
            self.showEdgeOverlay = UserDefaults.standard.bool(forKey: Self.edgeOverlayEnabledKey)
        }

        setupCallbacks()
        checkCameraPermission()
    }

    // MARK: - Public Methods

    /// Start the AR capture session.
    func start() {
        guard hasCameraPermission else {
            Self.logger.warning("Cannot start - no camera permission")
            return
        }

        guard isLiDARAvailable else {
            Self.logger.warning("Cannot start - LiDAR not available")
            return
        }

        do {
            try captureSession.start()
            isRunning = true
            Self.logger.info("Capture session started")
        } catch {
            Self.logger.error("Failed to start capture session: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Stop the AR capture session.
    func stop() {
        captureSession.stop()
        isRunning = false
        currentDepthFrame = nil
        Self.logger.info("Capture session stopped")
    }

    /// Capture the current frame.
    func capture() {
        guard !isCapturing else {
            Self.logger.warning("Capture already in progress")
            return
        }

        isCapturing = true
        Self.logger.info("Starting capture")

        Task {
            await performCapture()
        }
    }

    /// Save the pending capture.
    func saveCapture() {
        guard let capture = pendingCapture else {
            Self.logger.warning("No pending capture to save")
            return
        }

        Task {
            do {
                try await captureStore.saveCapture(capture, status: .pending)
                Self.logger.info("Capture saved: \(capture.id.uuidString)")
                clearPendingCapture()
            } catch {
                Self.logger.error("Failed to save capture: \(error.localizedDescription)")
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }

    /// Discard the pending capture.
    func discardCapture() {
        clearPendingCapture()
        Self.logger.info("Capture discarded")
    }

    /// Request camera permission.
    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasCameraPermission = granted
                if granted {
                    Self.logger.info("Camera permission granted")
                } else {
                    Self.logger.warning("Camera permission denied")
                }
            }
        }
    }

    // MARK: - Private Methods

    private func setupCallbacks() {
        // Frame updates
        captureSession.onFrameUpdate = { [weak self] frame in
            guard let self = self else { return }

            // Extract depth frame for visualization
            if let depthData = frame.sceneDepth {
                let depthFrame = DepthFrame(
                    depthMap: depthData.depthMap,
                    timestamp: frame.timestamp
                )

                DispatchQueue.main.async {
                    self.currentDepthFrame = depthFrame
                }
            }
        }

        // Tracking state
        captureSession.onTrackingStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.trackingState = state
            }
        }

        // Errors
        captureSession.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error.localizedDescription
                Self.logger.error("Capture error: \(error.localizedDescription)")
            }
        }

        // Interruptions
        captureSession.onInterruption = { [weak self] in
            Self.logger.info("Session interrupted")
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }

        captureSession.onInterruptionEnded = { [weak self] in
            Self.logger.info("Interruption ended, resuming")
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }

    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraPermission = status == .authorized
    }

    private func performCapture() async {
        defer {
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }

        // Capture current frame
        guard let frame = captureSession.captureCurrentFrame() else {
            Self.logger.error("No frame available for capture")
            errorMessage = "No frame available"
            return
        }

        do {
            // Process frame
            let captureData = try await frameProcessor.process(frame, location: nil)

            // Generate assertion (if available)
            var finalCapture = captureData
            if assertionService.isAvailable {
                do {
                    let assertion = try await assertionService.createAssertion(for: captureData)
                    finalCapture = CaptureData(
                        id: captureData.id,
                        jpeg: captureData.jpeg,
                        depth: captureData.depth,
                        metadata: captureData.metadata,
                        assertion: assertion,
                        assertionStatus: .generated,
                        assertionAttemptCount: 1,
                        timestamp: captureData.timestamp
                    )
                } catch {
                    Self.logger.warning("Assertion failed, saving without: \(error.localizedDescription)")
                }
            }

            // Generate preview image
            if let jpegImage = UIImage(data: captureData.jpeg) {
                DispatchQueue.main.async {
                    self.lastCapturedPhoto = jpegImage
                    self.pendingCapture = finalCapture
                    self.showCapturePreview = true
                }
            }

            Self.logger.info("Capture processed successfully")
        } catch {
            Self.logger.error("Capture processing failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    private func clearPendingCapture() {
        pendingCapture = nil
        lastCapturedPhoto = nil
        showCapturePreview = false
    }

    // MARK: - Video Recording Methods

    /// Start video recording.
    ///
    /// Creates a VideoRecordingSession and begins capturing video frames.
    /// Recording will automatically stop at `maxRecordingDuration` (15 seconds).
    func startVideoRecording() {
        guard !isRecordingVideo else {
            Self.logger.warning("Video recording already in progress")
            return
        }

        guard isRunning else {
            Self.logger.error("Cannot start video recording - AR session not running")
            errorMessage = "Camera not ready"
            return
        }

        Self.logger.info("Starting video recording")

        // Create video recording session
        videoRecordingSession = VideoRecordingSession(arCaptureSession: captureSession)

        // Set up frame callback for downstream processing (depth extraction, hash chain)
        videoRecordingSession?.onFrameProcessed = { [weak self] frame, frameNumber in
            DispatchQueue.main.async {
                self?.recordingFrameCount = frameNumber
            }
        }

        // Set up state change callback
        videoRecordingSession?.onRecordingStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch state {
                case .recording:
                    self.isRecordingVideo = true
                case .idle, .processing:
                    self.isRecordingVideo = false
                case .error(let error):
                    self.isRecordingVideo = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }

        // Set up error callback
        videoRecordingSession?.onError = { [weak self] error in
            DispatchQueue.main.async {
                Self.logger.error("Video recording error: \(error.localizedDescription)")
                // maxDurationReached is not really an error, just a notification
                if error != .maxDurationReached {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }

        // Start recording
        Task {
            do {
                try await videoRecordingSession?.startRecording()

                // Start duration timer
                startRecordingTimer()

            } catch {
                Self.logger.error("Failed to start video recording: \(error.localizedDescription)")
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                isRecordingVideo = false
            }
        }
    }

    /// Stop video recording.
    ///
    /// Finalizes the video file and prepares it for processing.
    func stopVideoRecording() {
        guard isRecordingVideo else {
            Self.logger.debug("stopVideoRecording called but not recording")
            return
        }

        Self.logger.info("Stopping video recording")

        // Stop timer
        stopRecordingTimer()

        Task {
            do {
                guard let result = try await videoRecordingSession?.stopRecording() else {
                    Self.logger.error("No result from video recording")
                    return
                }

                Self.logger.info("Video recording saved to: \(result.videoURL.lastPathComponent)")

                // Log depth keyframe extraction results (Story 7.2)
                let depthKeyframeCount = result.depthKeyframeCount
                if depthKeyframeCount > 0 {
                    Self.logger.info("Depth keyframes captured: \(depthKeyframeCount)")
                    if let depthData = result.depthKeyframeData {
                        Self.logger.info("Depth blob: \(depthData.compressedBlob.count) bytes (ratio: \(String(format: "%.1f", depthData.compressionRatio))x)")
                    }
                }

                // TODO: Story 7.3+ will process the video (hash chain, attestation)
                // For now, just log completion
                Self.logger.info("Recording complete: \(result.frameCount) frames, \(depthKeyframeCount) depth keyframes, \(String(format: "%.1f", result.duration))s")

                // Reset state
                resetRecordingState()

            } catch {
                Self.logger.error("Failed to stop video recording: \(error.localizedDescription)")
                errorMessage = "Failed to save recording: \(error.localizedDescription)"
                resetRecordingState()
            }
        }
    }

    /// Cancel video recording without saving.
    func cancelVideoRecording() {
        guard isRecordingVideo else { return }

        Self.logger.info("Cancelling video recording")
        stopRecordingTimer()
        videoRecordingSession?.cancelRecording()
        resetRecordingState()
    }

    // MARK: - Recording Timer

    /// Start the recording duration update timer.
    private func startRecordingTimer() {
        recordingDuration = 0
        recordingFrameCount = 0

        // Update every 0.1 seconds for smooth UI
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let session = self.videoRecordingSession else { return }
                self.recordingDuration = session.duration

                // Auto-stop at max duration (handled by VideoRecordingSession, but update UI)
                if self.recordingDuration >= CaptureViewModel.maxRecordingDuration {
                    self.stopVideoRecording()
                }
            }
        }
    }

    /// Stop the recording duration update timer.
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    /// Reset video recording state.
    private func resetRecordingState() {
        isRecordingVideo = false
        recordingDuration = 0
        recordingFrameCount = 0
        videoRecordingSession = nil
    }
}

// MARK: - Preview Support

#if DEBUG
extension CaptureViewModel {
    /// Creates a preview instance with mock state.
    static var preview: CaptureViewModel {
        let vm = CaptureViewModel()
        vm.isLiDARAvailable = true
        vm.hasCameraPermission = true
        return vm
    }
}
#endif
