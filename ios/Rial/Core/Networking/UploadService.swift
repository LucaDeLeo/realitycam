//
//  UploadService.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Background upload service for captures.
//

import Foundation
import os.log

/// Service for uploading captures with background URLSession support.
///
/// Provides reliable capture uploads that continue even when the app
/// is backgrounded or terminated. Uses URLSession background configuration
/// with multipart form-data encoding.
///
/// ## Features
/// - Background uploads survive app termination
/// - App woken on completion via sessionSendsLaunchEvents
/// - Multipart form-data for JPEG, depth, metadata, assertion
/// - Device authentication headers
/// - Progress tracking via delegate
/// - Automatic temp file cleanup
///
/// ## Usage
/// ```swift
/// // Configure once at app startup
/// UploadService.shared.configure(
///     baseURL: AppEnvironment.apiBaseURL,
///     captureStore: CaptureStore.shared,
///     keychain: KeychainService()
/// )
///
/// // Upload a capture
/// try await UploadService.shared.upload(capture)
///
/// // In AppDelegate, set completion handler for session identifier
/// UploadService.shared.backgroundCompletionHandler = completionHandler
/// ```
final class UploadService: NSObject {
    private static let logger = Logger(subsystem: "app.rial", category: "upload-service")

    /// ISO8601 formatter for metadata timestamps (reused across uploads)
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Background session identifier
    static let sessionIdentifier = "app.rial.upload"

    /// Shared singleton instance
    static let shared = UploadService()

    /// Base URL for API
    private var baseURL: URL?

    /// Capture store for status updates
    private var captureStore: CaptureStore?

    /// Keychain for device state
    private var keychain: KeychainService?

    /// Background URLSession (lazy initialized)
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 3600 // 1 hour max upload time
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "Rial-iOS/\(Self.appVersion)"
        ]

        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Completion handler called when background session finishes
    var backgroundCompletionHandler: (() -> Void)?

    /// Mapping of task identifiers to capture IDs
    private var taskToCaptureMap: [Int: UUID] = [:]

    /// Lock for thread-safe access to taskToCaptureMap
    private let lock = NSLock()

    /// Thread-safe registration of task to capture mapping.
    private func registerTask(_ taskId: Int, forCapture captureId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        taskToCaptureMap[taskId] = captureId
    }

    // MARK: - Initialization

    /// Private initializer for singleton.
    private override init() {
        super.init()
    }

    /// Configure the service with dependencies.
    ///
    /// Must be called before using the service (typically in AppDelegate).
    ///
    /// - Parameters:
    ///   - baseURL: API base URL
    ///   - captureStore: Store for status updates
    ///   - keychain: Keychain for device credentials
    func configure(baseURL: URL, captureStore: CaptureStore, keychain: KeychainService) {
        self.baseURL = baseURL
        self.captureStore = captureStore
        self.keychain = keychain
        Self.logger.info("UploadService configured with baseURL: \(baseURL.absoluteString)")
    }

    // MARK: - Upload Methods

    /// Upload a capture to the server.
    ///
    /// Creates a background upload task that continues even if the app
    /// is terminated. Updates CaptureStore status on completion.
    ///
    /// - Parameter capture: CaptureData to upload
    /// - Throws: `UploadError` if upload cannot be started
    func upload(_ capture: CaptureData) async throws {
        guard let baseURL = baseURL, let captureStore = captureStore, let keychain = keychain else {
            throw UploadError.notConfigured
        }

        Self.logger.info("Starting upload for capture: \(capture.id.uuidString)")

        // Update status to uploading
        try await captureStore.updateStatus(.uploading, for: capture.id)

        // Get device credentials
        guard let deviceState = try keychain.loadDeviceState() else {
            Self.logger.error("Device not registered - cannot upload")
            try await captureStore.updateStatus(.failed, for: capture.id)
            throw UploadError.deviceNotRegistered
        }

        // Create multipart request (returns boundary for body)
        let (request, tempFileURL, boundary) = try createUploadRequest(
            for: capture,
            deviceId: deviceState.deviceId,
            baseURL: baseURL
        )

        // Write multipart body to temp file (using same boundary as header)
        try writeMultipartBody(for: capture, to: tempFileURL, boundary: boundary)

        // Create background upload task
        let task = backgroundSession.uploadTask(with: request, fromFile: tempFileURL)

        // Track task -> capture mapping
        registerTask(task.taskIdentifier, forCapture: capture.id)

        task.resume()

        Self.logger.info("Upload task \(task.taskIdentifier) started for capture \(capture.id.uuidString)")
    }

    /// Resume any incomplete uploads from previous session.
    ///
    /// Called on app launch to recover interrupted uploads.
    func resumePendingUploads() async {
        let (_, uploadTasks, _) = await backgroundSession.tasks
        Self.logger.info("Found \(uploadTasks.count) pending upload tasks")

        // Tasks will be handled by delegate when they complete
        for task in uploadTasks {
            Self.logger.debug("Resuming task \(task.taskIdentifier)")
        }
    }

    // MARK: - Private Methods

    /// Create upload request with auth headers.
    /// Returns (request, tempFileURL, boundary) - boundary must be used in writeMultipartBody.
    private func createUploadRequest(
        for capture: CaptureData,
        deviceId: String,
        baseURL: URL
    ) throws -> (URLRequest, URL, String) {
        let url = baseURL.appendingPathComponent("/api/v1/captures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Generate boundary (must be used in both header and body)
        let boundary = "Rial-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        // Add device auth headers
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-Device-Timestamp")

        // Sign request (simplified - actual implementation would use Secure Enclave)
        let signaturePayload = "POST\n/api/v1/captures\n\(timestamp)\n\(deviceId)"
        let signatureData = Data(signaturePayload.utf8)
        request.setValue(signatureData.base64EncodedString(), forHTTPHeaderField: "X-Device-Signature")

        // Create temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("upload-\(capture.id.uuidString).multipart")

        return (request, tempFile, boundary)
    }

    /// Write multipart body to temp file.
    /// - Parameters:
    ///   - capture: The capture data to upload
    ///   - fileURL: Temp file to write to
    ///   - boundary: The boundary string (must match Content-Type header)
    private func writeMultipartBody(for capture: CaptureData, to fileURL: URL, boundary: String) throws {
        var body = Data()

        // JPEG part
        body.append(multipartPart(
            name: "photo",
            filename: "photo.jpg",
            contentType: "image/jpeg",
            data: capture.jpeg,
            boundary: boundary
        ))

        // Depth part (backend expects field name "depth_map")
        body.append(multipartPart(
            name: "depth_map",
            filename: "depth.bin",
            contentType: "application/octet-stream",
            data: capture.depth,
            boundary: boundary
        ))

        // Metadata part (JSON) - must match backend's CaptureMetadataPayload format
        // Assertion is included IN the metadata JSON (as base64), not as a separate part
        let uploadLocation: UploadLocation? = capture.metadata.location.map { loc in
            UploadLocation(
                latitude: loc.latitude,
                longitude: loc.longitude,
                altitude: loc.altitude,
                accuracy: loc.accuracy
            )
        }

        // Extract detection summary for metadata (Story 9-6)
        let detectionResults = capture.detectionResults
        let hasDetection = detectionResults?.hasAnyResults ?? false

        let uploadMetadata = UploadMetadataPayload(
            capturedAt: Self.iso8601Formatter.string(from: capture.metadata.capturedAt),
            deviceModel: capture.metadata.deviceModel,
            photoHash: capture.metadata.photoHash,
            depthMapDimensions: UploadDepthDimensions(
                width: capture.metadata.depthMapDimensions.width,
                height: capture.metadata.depthMapDimensions.height
            ),
            assertion: capture.assertion?.base64EncodedString(),
            location: uploadLocation,
            detectionAvailable: hasDetection,
            detectionConfidenceLevel: detectionResults?.confidenceLevel?.rawValue,
            detectionPrimaryValid: detectionResults?.primarySignalValid,
            detectionSignalsAgree: detectionResults?.signalsAgree
        )

        let metadataJSON = try JSONEncoder().encode(uploadMetadata)
        body.append(multipartPart(
            name: "metadata",
            filename: "metadata.json",
            contentType: "application/json",
            data: metadataJSON,
            boundary: boundary
        ))

        // Detection part (JSON) - only included when detection results are present (Story 9-6)
        if let detectionResults = capture.detectionResults, detectionResults.hasAnyResults {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let detectionJSON = try encoder.encode(detectionResults)
            body.append(multipartPart(
                name: "detection",
                filename: "detection.json",
                contentType: "application/json",
                data: detectionJSON,
                boundary: boundary
            ))
            Self.logger.info("Upload includes multi-signal detection data (\(detectionJSON.count) bytes)")
        }

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Write to temp file
        try body.write(to: fileURL)

        Self.logger.debug("Wrote \(body.count) bytes to temp file")
    }

    /// Create a multipart form-data part.
    private func multipartPart(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) -> Data {
        var part = Data()

        part.append("--\(boundary)\r\n".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        part.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        part.append(data)
        part.append("\r\n".data(using: .utf8)!)

        return part
    }

    /// Clean up temp file for capture.
    private func cleanupTempFile(for captureId: UUID) {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("upload-\(captureId.uuidString).multipart")

        try? FileManager.default.removeItem(at: tempFile)
        Self.logger.debug("Cleaned up temp file for capture \(captureId.uuidString)")
    }

    /// Get app version string.
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - URLSessionDelegate

extension UploadService: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Self.logger.info("Background session finished events")

        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension UploadService: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Get capture ID for this task
        lock.lock()
        let captureId = taskToCaptureMap.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        guard let captureId = captureId else {
            Self.logger.warning("No capture ID found for task \(task.taskIdentifier)")
            return
        }

        if let error = error {
            Self.logger.error("Upload failed for \(captureId.uuidString): \(error.localizedDescription)")

            Task {
                try? await captureStore?.updateStatus(.failed, for: captureId)
            }
        } else {
            Self.logger.info("Upload completed for \(captureId.uuidString)")
        }

        // Clean up temp file
        cleanupTempFile(for: captureId)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Self.logger.debug("Upload progress: \(Int(progress * 100))%")
    }
}

// MARK: - URLSessionDataDelegate

extension UploadService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Parse response for server capture ID and verification URL
        lock.lock()
        let captureId = taskToCaptureMap[dataTask.taskIdentifier]
        lock.unlock()

        guard let captureId = captureId else { return }

        // Log raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            Self.logger.debug("Upload response: \(responseString)")
        }

        // Try to parse upload response (wrapped in {"data": {...}})
        do {
            let response = try JSONDecoder().decode(UploadAPIResponse.self, from: data)

            Task {
                try? await captureStore?.updateUploadResult(
                    for: captureId,
                    serverCaptureId: response.data.captureId,
                    verificationUrl: response.data.verificationUrl
                )
            }

            Self.logger.info("Upload success - server ID: \(response.data.captureId.uuidString)")
        } catch {
            Self.logger.warning("Failed to parse upload response: \(error.localizedDescription)")
        }
    }
}

// MARK: - Upload Metadata (matches backend CaptureMetadataPayload)

/// Metadata payload for upload that matches backend's expected format.
/// Uses snake_case keys to match Rust's serde conventions.
private struct UploadMetadataPayload: Encodable {
    let capturedAt: String  // ISO 8601 string
    let deviceModel: String
    let photoHash: String
    let depthMapDimensions: UploadDepthDimensions
    let assertion: String?  // base64 encoded
    let location: UploadLocation?

    // Detection summary fields (Story 9-6)
    let detectionAvailable: Bool
    let detectionConfidenceLevel: String?
    let detectionPrimaryValid: Bool?
    let detectionSignalsAgree: Bool?

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case deviceModel = "device_model"
        case photoHash = "photo_hash"
        case depthMapDimensions = "depth_map_dimensions"
        case assertion
        case location
        case detectionAvailable = "detection_available"
        case detectionConfidenceLevel = "detection_confidence_level"
        case detectionPrimaryValid = "detection_primary_valid"
        case detectionSignalsAgree = "detection_signals_agree"
    }
}

/// Depth dimensions for upload payload.
private struct UploadDepthDimensions: Encodable {
    let width: Int
    let height: Int
}

/// Location data for upload payload.
private struct UploadLocation: Encodable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double?
}

// MARK: - UploadResponse

/// Wrapper for API responses that use {"data": {...}} format.
private struct UploadAPIResponse: Decodable {
    let data: UploadResponseData
}

/// Response data from capture upload endpoint.
private struct UploadResponseData: Decodable {
    let captureId: UUID
    let verificationUrl: String

    enum CodingKeys: String, CodingKey {
        case captureId = "capture_id"
        case verificationUrl = "verification_url"
    }
}

// MARK: - UploadError

/// Errors that can occur during upload.
enum UploadError: Error, LocalizedError {
    /// Service not configured
    case notConfigured

    /// Device not registered
    case deviceNotRegistered

    /// Failed to create request
    case requestFailed(String)

    /// Network error
    case networkError(Error)

    /// Server error
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "UploadService not configured. Call configure() first."
        case .deviceNotRegistered:
            return "Device is not registered"
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code):
            return "Server error (\(code))"
        }
    }

    /// Whether this error should be retried
    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError:
            return true
        default:
            return false
        }
    }
}
