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
