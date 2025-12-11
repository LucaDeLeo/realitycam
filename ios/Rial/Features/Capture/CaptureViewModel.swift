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

    /// UserDefaults key for photo overlay visibility preference
    private static let photoOverlayEnabledKey = "app.rial.photoOverlayEnabled"

    /// UserDefaults key for capture mode preference
    private static let captureModeKey = "app.rial.captureMode"

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

    /// Success message to display (auto-dismisses)
    @Published var successMessage: String?

    /// Whether LiDAR is available on this device
    @Published private(set) var isLiDARAvailable = ARCaptureSession.isLiDARAvailable

    /// Whether camera permission is granted
    @Published private(set) var hasCameraPermission = false

    /// Last captured photo for preview
    @Published private(set) var lastCapturedPhoto: UIImage?

    /// Whether showing capture preview
    @Published var showCapturePreview = false

    /// ID of the pending capture (for navigation after save)
    var pendingCaptureId: UUID? {
        pendingCapture?.id
    }

    // MARK: - Capture Mode Properties (Story 7-14)

    /// Current capture mode (photo or video).
    /// Persisted to UserDefaults so preference survives app restarts.
    @Published var currentMode: CaptureMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: Self.captureModeKey)
            Self.logger.debug("Capture mode changed: \(self.currentMode.rawValue)")
        }
    }

    /// Whether photo depth overlay is visible.
    /// Persisted separately from video edge overlay.
    @Published var showPhotoOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showPhotoOverlay, forKey: Self.photoOverlayEnabledKey)
            Self.logger.debug("Photo overlay visibility changed: \(self.showPhotoOverlay)")
        }
    }

    // MARK: - Video Recording Published Properties

    /// Whether video recording is in progress
    @Published private(set) var isRecordingVideo = false

    /// Current video recording duration in seconds
    @Published private(set) var recordingDuration: TimeInterval = 0

    /// Number of frames recorded in current session
    @Published private(set) var recordingFrameCount: Int = 0

    /// Maximum video recording duration (15 seconds)
    public static let maxRecordingDuration: TimeInterval = VideoRecordingSession.maxDuration

    /// Duration at which 5-second warning haptic should fire
    private static let fiveSecondWarningDuration: TimeInterval = 10.0  // 10s elapsed = 5s remaining

    // MARK: - Video Preview Properties (Story 7-14)

    /// Whether showing video preview sheet
    @Published var showVideoPreview = false

    /// Last recorded video result for preview
    @Published private(set) var lastVideoResult: VideoRecordingResult?

    // MARK: - Upload Progress Properties (Story 7-14)

    /// Current upload progress (0.0 - 1.0)
    @Published private(set) var uploadProgress: Double = 0.0

    /// Whether upload is in progress
    @Published private(set) var isUploading = false

    /// Upload error message (if any)
    @Published var uploadError: String?

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

    /// Public access to ARSession for ARView binding.
    public var arSession: ARSession { captureSession.arSession }

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

    /// Whether 5-second warning haptic has been triggered
    private var hasFiredFiveSecondWarning = false

    /// Haptic feedback generators for recording events
    private let warningHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let stopHaptic = UIImpactFeedbackGenerator(style: .heavy)

    /// Video processing pipeline for preparing uploads
    private let videoProcessingPipeline = VideoProcessingPipeline()

    /// Privacy settings manager for checking privacy mode (Story 8-3)
    private var privacySettingsManager: PrivacySettingsManager?

    /// Pending hash-only payload for privacy mode captures (Story 8-3)
    private var pendingHashOnlyPayload: HashOnlyCapturePayload?

    // MARK: - Initialization

    init(
        frameProcessor: FrameProcessor = FrameProcessor(),
        captureStore: CaptureStore? = nil,
        assertionService: CaptureAssertionService? = nil,
        privacySettingsManager: PrivacySettingsManager? = nil
    ) {
        self.frameProcessor = frameProcessor
        self.privacySettingsManager = privacySettingsManager

        // Create default instances if not provided
        self.captureStore = captureStore ?? .shared
        let keychain = KeychainService()
        let attestation = DeviceAttestationService(keychain: keychain)
        self.assertionService = assertionService ?? CaptureAssertionService(attestation: attestation, keychain: keychain)

        // Load capture mode preference from UserDefaults (default: photo)
        if let modeString = UserDefaults.standard.string(forKey: Self.captureModeKey),
           let mode = CaptureMode(rawValue: modeString) {
            self.currentMode = mode
        } else {
            self.currentMode = .photo
            UserDefaults.standard.set(CaptureMode.photo.rawValue, forKey: Self.captureModeKey)
        }

        // Load photo overlay preference from UserDefaults (default: true)
        if UserDefaults.standard.object(forKey: Self.photoOverlayEnabledKey) == nil {
            self.showPhotoOverlay = true
            UserDefaults.standard.set(true, forKey: Self.photoOverlayEnabledKey)
        } else {
            self.showPhotoOverlay = UserDefaults.standard.bool(forKey: Self.photoOverlayEnabledKey)
        }

        // Load edge overlay preference from UserDefaults (default: true)
        if UserDefaults.standard.object(forKey: Self.edgeOverlayEnabledKey) == nil {
            self.showEdgeOverlay = true
            UserDefaults.standard.set(true, forKey: Self.edgeOverlayEnabledKey)
        } else {
            self.showEdgeOverlay = UserDefaults.standard.bool(forKey: Self.edgeOverlayEnabledKey)
        }

        setupCallbacks()
        checkCameraPermission()

        // Prepare haptic generators for lowest latency
        warningHaptic.prepare()
        stopHaptic.prepare()
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

    /// Save the pending capture and trigger upload.
    func saveCapture() {
        guard let capture = pendingCapture else {
            Self.logger.warning("No pending capture to save")
            return
        }

        Task {
            do {
                try await captureStore.saveCapture(capture, status: .pending)
                Self.logger.info("Capture saved: \(capture.id.uuidString)")

                // Trigger upload if device is registered
                if DeviceRegistrationService.shared.isRegistered {
                    try await UploadService.shared.upload(capture)
                    Self.logger.info("Upload started for: \(capture.id.uuidString)")
                    showSuccessMessage("Photo uploading...")
                } else {
                    Self.logger.warning("Device not registered - capture queued for later upload")
                    showSuccessMessage("Photo saved • Will upload when connected")
                }

                clearPendingCapture()
            } catch {
                Self.logger.error("Failed to save/upload capture: \(error.localizedDescription)")
                errorMessage = "Failed to save: \(error.localizedDescription)"
                clearPendingCapture()
            }
        }
    }

    /// Show a success message that auto-dismisses after 3 seconds.
    private func showSuccessMessage(_ message: String) {
        successMessage = message

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if self.successMessage == message {
                    self.successMessage = nil
                }
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

    // MARK: - Privacy Mode Support (Story 8-3)

    /// Sets the privacy settings manager for privacy mode support.
    ///
    /// Call this method to inject the privacy settings manager, typically
    /// from the view that hosts the capture view model.
    ///
    /// - Parameter manager: The privacy settings manager to use
    func setPrivacySettingsManager(_ manager: PrivacySettingsManager) {
        self.privacySettingsManager = manager
        Self.logger.debug("Privacy settings manager set, privacyModeEnabled: \(manager.isPrivacyModeEnabled)")
    }

    /// Whether privacy mode is currently enabled.
    var isPrivacyModeEnabled: Bool {
        privacySettingsManager?.isPrivacyModeEnabled ?? false
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
            // Process frame with multi-signal detection enabled by default (Story 9-6)
            // Detection runs in parallel and adds ~200ms to processing
            let captureData = try await frameProcessor.process(frame, location: nil, runDetection: true)

            // Log detection results for debugging
            if let detection = captureData.detectionResults {
                Self.logger.info("""
                    Detection results:
                    hasAnyResults=\(detection.hasAnyResults),
                    confidenceLevel=\(detection.confidenceLevel?.rawValue ?? "nil"),
                    methods=\(detection.methodsUsed.joined(separator: ", "))
                    """)
            }

            // Check privacy mode
            if let privacyManager = privacySettingsManager,
               privacyManager.isPrivacyModeEnabled {
                // Privacy mode: run client-side depth analysis and build hash-only payload
                // Detection results are still included alongside the hash
                await performPrivacyModeCapture(frame: frame, captureData: captureData, privacySettings: privacyManager.settings)
            } else {
                // Full mode: existing flow with full upload
                // Detection results flow through to upload
                await performFullModeCapture(captureData: captureData)
            }
        } catch {
            Self.logger.error("Capture processing failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    /// Performs privacy mode capture with client-side depth analysis (Story 8-3).
    ///
    /// - Parameters:
    ///   - frame: The AR frame containing depth data
    ///   - captureData: Processed capture data
    ///   - privacySettings: Current privacy settings snapshot
    private func performPrivacyModeCapture(
        frame: ARFrame,
        captureData: CaptureData,
        privacySettings: PrivacySettings
    ) async {
        Self.logger.info("Privacy mode capture: running client-side depth analysis")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Run client-side depth analysis
        var depthAnalysis: DepthAnalysisResult
        if let depthMap = frame.sceneDepth?.depthMap {
            depthAnalysis = await DepthAnalysisService.shared.analyze(depthMap: depthMap)
            Self.logger.debug("Depth analysis completed: isRealScene=\(depthAnalysis.isLikelyRealScene)")
        } else {
            // No depth data available - continue with unavailable status
            Self.logger.warning("No depth data for privacy mode capture - continuing with unavailable status")
            depthAnalysis = .unavailable()
        }

        // Build hash-only payload
        var payload = await HashOnlyPayloadBuilder.build(
            from: captureData,
            privacySettings: privacySettings,
            depthAnalysis: depthAnalysis
        )

        // Sign payload (if assertion service available)
        if assertionService.isAvailable {
            do {
                payload = try await HashOnlyPayloadBuilder.sign(
                    payload: payload,
                    with: assertionService
                )
                Self.logger.info("Hash-only payload signed successfully")
            } catch {
                Self.logger.warning("Failed to sign hash-only payload: \(error.localizedDescription)")
                // Continue without assertion - will be marked as pending retry
            }
        }

        // Verify payload size
        if let size = payload.serializedSize() {
            Self.logger.info("Hash-only payload size: \(size) bytes")
            if !payload.isWithinSizeLimit() {
                Self.logger.warning("Hash-only payload exceeds 10KB limit!")
            }
        }

        // Create CaptureData with privacy mode fields
        var finalCapture = captureData
        finalCapture.uploadMode = .hashOnly
        finalCapture.depthAnalysisResult = depthAnalysis
        finalCapture.privacySettings = privacySettings

        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Self.logger.info("Privacy mode capture processed in \(String(format: "%.1f", totalTime))ms")

        // Generate preview image and store captures
        if let jpegImage = UIImage(data: captureData.jpeg) {
            DispatchQueue.main.async {
                self.lastCapturedPhoto = jpegImage
                self.pendingCapture = finalCapture
                self.pendingHashOnlyPayload = payload
                self.showCapturePreview = true
            }
        }
    }

    /// Performs full mode capture with raw media upload (existing behavior).
    ///
    /// - Parameter captureData: Processed capture data
    private func performFullModeCapture(captureData: CaptureData) async {
        // Generate assertion (if available)
        var finalCapture = captureData
        finalCapture.uploadMode = .full

        if assertionService.isAvailable {
            do {
                let assertion = try await assertionService.createAssertion(for: captureData)
                // Preserve detection results when creating new CaptureData (Story 9-6)
                finalCapture = CaptureData(
                    id: captureData.id,
                    jpeg: captureData.jpeg,
                    depth: captureData.depth,
                    metadata: captureData.metadata,
                    assertion: assertion,
                    assertionStatus: .generated,
                    assertionAttemptCount: 1,
                    timestamp: captureData.timestamp,
                    uploadMode: .full,
                    depthAnalysisResult: captureData.depthAnalysisResult,
                    privacySettings: captureData.privacySettings,
                    detectionResults: captureData.detectionResults
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
                self.pendingHashOnlyPayload = nil
                self.showCapturePreview = true
            }
        }

        Self.logger.info("Full mode capture processed successfully, detection=\(captureData.detectionResults != nil)")
    }

    private func clearPendingCapture() {
        pendingCapture = nil
        pendingHashOnlyPayload = nil
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

        // Check storage before starting (AC-10.1)
        guard hasStorageForRecording() else {
            Self.logger.error("Cannot start video recording - insufficient storage")
            errorMessage = "Storage full - cannot record video"
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

                Self.logger.info("Recording complete: \(result.frameCount) frames, \(depthKeyframeCount) depth keyframes, \(String(format: "%.1f", result.duration))s")

                // Store result for preview (Story 7-14)
                self.lastVideoResult = result

                // Reset recording state but keep video result for preview
                self.isRecordingVideo = false
                self.recordingDuration = 0
                self.recordingFrameCount = 0
                self.videoRecordingSession = nil
                self.hasFiredFiveSecondWarning = false

                // Show video preview sheet (AC-7)
                self.showVideoPreview = true

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
        hasFiredFiveSecondWarning = false

        // Update every 0.1 seconds for smooth UI
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let session = self.videoRecordingSession else { return }
                self.recordingDuration = session.duration

                // 5-second warning haptic (AC-5.3)
                // Fire at 10s elapsed (5s remaining until 15s max)
                if !self.hasFiredFiveSecondWarning &&
                   self.recordingDuration >= Self.fiveSecondWarningDuration {
                    self.hasFiredFiveSecondWarning = true
                    self.warningHaptic.impactOccurred()
                    Self.logger.debug("5-second warning haptic fired at \(self.recordingDuration)s")
                }

                // Auto-stop at max duration (handled by VideoRecordingSession, but update UI)
                if self.recordingDuration >= CaptureViewModel.maxRecordingDuration {
                    self.stopHaptic.impactOccurred()
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
        hasFiredFiveSecondWarning = false
    }

    // MARK: - Video Use/Retake (Story 7-14)

    /// Use the recorded video (save and upload).
    ///
    /// Processes the video through the pipeline and initiates background upload.
    func useVideo() {
        guard let result = lastVideoResult else {
            Self.logger.warning("No video result to use")
            return
        }

        showVideoPreview = false

        Task {
            do {
                // Process video through pipeline
                isUploading = true
                uploadProgress = 0.0

                let processed = try await videoProcessingPipeline.process(result: result) { [weak self] progress in
                    self?.uploadProgress = progress * 0.5  // Processing is 50% of progress
                }

                // Save to capture store
                try await captureStore.saveVideoCapture(processed)
                Self.logger.info("Video capture saved: \(result.videoURL.lastPathComponent)")

                // Reset state after successful save
                uploadProgress = 1.0
                isUploading = false
                clearVideoPreview()

            } catch {
                Self.logger.error("Failed to process/save video: \(error.localizedDescription)")
                uploadError = "Failed to save video: \(error.localizedDescription)"
                isUploading = false
            }
        }
    }

    /// Discard the recorded video.
    func discardVideo() {
        guard let result = lastVideoResult else { return }

        // Delete the temp video file
        try? FileManager.default.removeItem(at: result.videoURL)
        Self.logger.info("Video discarded")

        clearVideoPreview()
    }

    /// Clear video preview state.
    private func clearVideoPreview() {
        lastVideoResult = nil
        showVideoPreview = false
        uploadProgress = 0.0
        uploadError = nil
    }

    // MARK: - Storage Check (Story 7-14, AC-10.1)

    /// Minimum storage required for video recording (50MB)
    private static let minimumStorageBytes: Int64 = 50 * 1024 * 1024

    /// Check if sufficient storage is available for video recording.
    ///
    /// Videos typically require 15-20MB for 15 seconds, so we require
    /// at least 50MB free to ensure recording completes successfully.
    ///
    /// - Returns: True if sufficient storage available
    func hasStorageForRecording() -> Bool {
        do {
            let documentDirectory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

            let values = try documentDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            if let available = values.volumeAvailableCapacityForImportantUsage {
                let hasSpace = available >= Self.minimumStorageBytes
                if !hasSpace {
                    Self.logger.warning("Insufficient storage: \(available) bytes available, need \(Self.minimumStorageBytes)")
                }
                return hasSpace
            }
        } catch {
            Self.logger.error("Failed to check storage: \(error.localizedDescription)")
        }

        // Default to allowing recording if check fails
        return true
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
