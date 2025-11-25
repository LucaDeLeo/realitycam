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
/// let uploadService = UploadService(
///     baseURL: URL(string: "https://backend-production-5e5a.up.railway.app")!,
///     captureStore: captureStore,
///     keychain: keychainService
/// )
///
/// // Upload a capture
/// try await uploadService.upload(capture)
///
/// // Set background completion handler in AppDelegate
/// uploadService.backgroundCompletionHandler = completionHandler
/// ```
final class UploadService: NSObject {
    private static let logger = Logger(subsystem: "app.rial", category: "upload-service")

    /// Background session identifier
    private static let sessionIdentifier = "app.rial.upload"

    /// Base URL for API
    private let baseURL: URL

    /// Capture store for status updates
    private let captureStore: CaptureStore

    /// Keychain for device state
    private let keychain: KeychainService

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

    // MARK: - Initialization

    /// Creates a new UploadService.
    ///
    /// - Parameters:
    ///   - baseURL: API base URL
    ///   - captureStore: Store for status updates
    ///   - keychain: Keychain for device credentials
    init(baseURL: URL, captureStore: CaptureStore, keychain: KeychainService) {
        self.baseURL = baseURL
        self.captureStore = captureStore
        self.keychain = keychain
        super.init()
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
        Self.logger.info("Starting upload for capture: \(capture.id.uuidString)")

        // Update status to uploading
        try await captureStore.updateStatus(.uploading, for: capture.id)

        // Get device credentials
        guard let deviceState = try keychain.loadDeviceState() else {
            Self.logger.error("Device not registered - cannot upload")
            try await captureStore.updateStatus(.failed, for: capture.id)
            throw UploadError.deviceNotRegistered
        }

        // Create multipart request
        let (request, tempFileURL) = try createUploadRequest(
            for: capture,
            deviceId: deviceState.deviceId
        )

        // Write multipart body to temp file
        try writeMultipartBody(for: capture, to: tempFileURL)

        // Create background upload task
        let task = backgroundSession.uploadTask(with: request, fromFile: tempFileURL)

        // Track task -> capture mapping
        lock.lock()
        taskToCaptureMap[task.taskIdentifier] = capture.id
        lock.unlock()

        task.resume()

        Self.logger.info("Upload task \(task.taskIdentifier) started for capture \(capture.id.uuidString)")
    }

    /// Resume any incomplete uploads from previous session.
    ///
    /// Called on app launch to recover interrupted uploads.
    func resumePendingUploads() async {
        backgroundSession.getTasksWithCompletionHandler { [weak self] _, uploadTasks, _ in
            Self.logger.info("Found \(uploadTasks.count) pending upload tasks")

            // Tasks will be handled by delegate when they complete
            for task in uploadTasks {
                Self.logger.debug("Resuming task \(task.taskIdentifier)")
            }
        }
    }

    // MARK: - Private Methods

    /// Create upload request with auth headers.
    private func createUploadRequest(
        for capture: CaptureData,
        deviceId: String
    ) throws -> (URLRequest, URL) {
        let url = baseURL.appendingPathComponent("/api/v1/captures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Generate boundary
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

        return (request, tempFile)
    }

    /// Write multipart body to temp file.
    private func writeMultipartBody(for capture: CaptureData, to fileURL: URL) throws {
        let boundary = "Rial-\(UUID().uuidString)"
        var body = Data()

        // JPEG part
        body.append(multipartPart(
            name: "photo",
            filename: "photo.jpg",
            contentType: "image/jpeg",
            data: capture.jpeg,
            boundary: boundary
        ))

        // Depth part
        body.append(multipartPart(
            name: "depth",
            filename: "depth.bin",
            contentType: "application/octet-stream",
            data: capture.depth,
            boundary: boundary
        ))

        // Metadata part (JSON)
        let metadataJSON = try JSONEncoder().encode(capture.metadata)
        body.append(multipartPart(
            name: "metadata",
            filename: "metadata.json",
            contentType: "application/json",
            data: metadataJSON,
            boundary: boundary
        ))

        // Assertion part (optional)
        if let assertion = capture.assertion {
            body.append(multipartPart(
                name: "assertion",
                filename: "assertion.bin",
                contentType: "application/octet-stream",
                data: assertion,
                boundary: boundary
            ))
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
                try? await captureStore.updateStatus(.failed, for: captureId)
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

        // Try to parse upload response
        do {
            let response = try JSONDecoder().decode(UploadResponse.self, from: data)

            Task {
                try? await captureStore.updateUploadResult(
                    for: captureId,
                    serverCaptureId: response.captureId,
                    verificationUrl: response.verificationUrl
                )
            }

            Self.logger.info("Upload success - server ID: \(response.captureId.uuidString)")
        } catch {
            Self.logger.warning("Failed to parse upload response: \(error.localizedDescription)")
        }
    }
}

// MARK: - UploadResponse

/// Response from capture upload endpoint.
private struct UploadResponse: Decodable {
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
