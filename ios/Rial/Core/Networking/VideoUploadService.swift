//
//  VideoUploadService.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Background upload service for video captures (Story 7-8).
//

import Foundation
import os.log

// MARK: - VideoUploadService

/// Service for uploading video captures with background URLSession support.
///
/// Provides reliable video uploads that continue even when the app
/// is backgrounded or terminated. Uses URLSession background configuration
/// with multipart form-data encoding for large video files (~30-45MB).
///
/// ## Features
/// - Background uploads survive app termination
/// - App woken on completion via sessionSendsLaunchEvents
/// - Multipart form-data for video, depth_data, hash_chain, metadata
/// - Device authentication headers
/// - Progress tracking via delegate
/// - Automatic temp file cleanup
///
/// ## Usage
/// ```swift
/// // Use shared singleton
/// let service = VideoUploadService.shared
///
/// // Upload a processed video capture
/// try await service.upload(processedCapture, captureStore: store)
///
/// // In AppDelegate, set completion handler for session identifier
/// VideoUploadService.shared.backgroundCompletionHandler = completionHandler
/// ```
final class VideoUploadService: NSObject {
    private static let logger = Logger(subsystem: "app.rial", category: "video-upload")

    /// Background session identifier (different from photo upload service)
    static let sessionIdentifier = "app.rial.video-upload"

    /// Shared singleton instance
    static let shared = VideoUploadService()

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
        config.timeoutIntervalForResource = 7200 // 2 hours max upload time for large videos
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

    /// Response data accumulated during download
    private var responseData: [Int: Data] = [:]

    // MARK: - Initialization

    /// Private initializer for singleton
    private override init() {
        super.init()
    }

    /// Configure the service with dependencies.
    ///
    /// Must be called before using the service.
    ///
    /// - Parameters:
    ///   - baseURL: API base URL
    ///   - captureStore: Store for status updates
    ///   - keychain: Keychain for device credentials
    func configure(baseURL: URL, captureStore: CaptureStore, keychain: KeychainService) {
        self.baseURL = baseURL
        self.captureStore = captureStore
        self.keychain = keychain
        Self.logger.info("VideoUploadService configured with baseURL: \(baseURL.absoluteString)")
    }

    // MARK: - Upload Methods

    /// Upload a processed video capture to the server.
    ///
    /// Creates a background upload task that continues even if the app
    /// is terminated. Updates CaptureStore status on completion.
    ///
    /// - Parameters:
    ///   - capture: ProcessedVideoCapture to upload
    ///   - store: CaptureStore to use for this upload (overrides configured store)
    /// - Throws: `VideoUploadError` if upload cannot be started
    func upload(_ capture: ProcessedVideoCapture, captureStore store: CaptureStore? = nil) async throws {
        let effectiveStore = store ?? captureStore

        guard let baseURL = baseURL else {
            throw VideoUploadError.notConfigured
        }

        guard let keychain = keychain else {
            throw VideoUploadError.notConfigured
        }

        Self.logger.info("Starting video upload for capture: \(capture.id.uuidString)")

        // Update status to uploading
        if let store = effectiveStore {
            try await store.updateVideoCaptureStatus(.uploading, for: capture.id)
        }

        // Get device credentials
        guard let deviceState = try keychain.loadDeviceState() else {
            Self.logger.error("Device not registered - cannot upload video")
            if let store = effectiveStore {
                try? await store.updateVideoCaptureStatus(.failed, for: capture.id)
            }
            throw VideoUploadError.deviceNotRegistered
        }

        // Create multipart request
        // CRIT-1 fix: boundary is now returned and passed to writeMultipartBody
        let (request, tempFileURL, boundary) = try createUploadRequest(
            for: capture,
            deviceId: deviceState.deviceId,
            baseURL: baseURL
        )

        // Write multipart body to temp file using the same boundary from the request header
        try writeMultipartBody(for: capture, to: tempFileURL, boundary: boundary)

        // Create background upload task
        let task = backgroundSession.uploadTask(with: request, fromFile: tempFileURL)

        // Track task -> capture mapping
        registerTask(task.taskIdentifier, forCapture: capture.id)

        task.resume()

        Self.logger.info("Video upload task \(task.taskIdentifier) started for capture \(capture.id.uuidString)")
    }

    /// Resume any incomplete video uploads from previous session.
    ///
    /// Called on app launch to recover interrupted uploads.
    func resumePendingUploads() async {
        let (_, uploadTasks, _) = await backgroundSession.tasks
        Self.logger.info("Found \(uploadTasks.count) pending video upload tasks")

        // Tasks will be handled by delegate when they complete
        for task in uploadTasks {
            Self.logger.debug("Resuming video upload task \(task.taskIdentifier)")
        }
    }

    // MARK: - Private Methods

    /// Create upload request with auth headers.
    private func createUploadRequest(
        for capture: ProcessedVideoCapture,
        deviceId: String,
        baseURL: URL
    ) throws -> (URLRequest, URL, String) {
        // LOW-1 fix: Remove leading slash - appendingPathComponent handles this
        let url = baseURL.appendingPathComponent("api/v1/captures/video")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // CRIT-1 fix: Generate boundary once and return it for use in writeMultipartBody
        let boundary = "RialVideo-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        // Add device auth headers
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-Device-Timestamp")

        // MED-2: TODO - This is a placeholder signature implementation.
        // Real implementation should use CryptoService.sign() with Secure Enclave key.
        // Technical debt: Replace with actual Ed25519 signing before production release.
        // See: CaptureAssertionService for proper signing pattern.
        let signaturePayload = "POST\n/api/v1/captures/video\n\(timestamp)\n\(deviceId)"
        let signatureData = Data(signaturePayload.utf8)
        request.setValue(signatureData.base64EncodedString(), forHTTPHeaderField: "X-Device-Signature")

        // Create temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("video-upload-\(capture.id.uuidString).multipart")

        return (request, tempFile, boundary)
    }

    /// Write multipart body to temp file.
    private func writeMultipartBody(for capture: ProcessedVideoCapture, to fileURL: URL, boundary: String) throws {
        var body = Data()

        // Read video file data
        let videoData = try Data(contentsOf: capture.videoURL)

        // Video part
        body.append(multipartPart(
            name: "video",
            filename: "video.mp4",
            contentType: "video/mp4",
            data: videoData,
            boundary: boundary
        ))

        // Depth data part
        body.append(multipartPart(
            name: "depth_data",
            filename: "depth.gz",
            contentType: "application/gzip",
            data: capture.compressedDepthData,
            boundary: boundary
        ))

        // Hash chain part
        body.append(multipartPart(
            name: "hash_chain",
            filename: "hash_chain.json",
            contentType: "application/json",
            data: capture.hashChainJSON,
            boundary: boundary
        ))

        // Metadata part
        body.append(multipartPart(
            name: "metadata",
            filename: "metadata.json",
            contentType: "application/json",
            data: capture.metadataJSON,
            boundary: boundary
        ))

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Write to temp file
        try body.write(to: fileURL)

        Self.logger.debug("Wrote \(body.count) bytes to temp file for video upload")
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
        let tempFile = tempDir.appendingPathComponent("video-upload-\(captureId.uuidString).multipart")

        try? FileManager.default.removeItem(at: tempFile)
        Self.logger.debug("Cleaned up temp file for video capture \(captureId.uuidString)")
    }

    /// Get app version string.
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - URLSessionDelegate

extension VideoUploadService: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Self.logger.info("Video background session finished events")

        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension VideoUploadService: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Get capture ID for this task
        lock.lock()
        let captureId = taskToCaptureMap.removeValue(forKey: task.taskIdentifier)
        let data = responseData.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        guard let captureId = captureId else {
            Self.logger.warning("No capture ID found for video upload task \(task.taskIdentifier)")
            return
        }

        if let error = error {
            Self.logger.error("Video upload failed for \(captureId.uuidString): \(error.localizedDescription)")

            Task {
                try? await captureStore?.updateVideoCaptureStatus(.failed, for: captureId)
            }
        } else if let httpResponse = task.response as? HTTPURLResponse {
            Self.logger.info("Video upload completed with status \(httpResponse.statusCode) for \(captureId.uuidString)")

            // Handle different response codes
            switch httpResponse.statusCode {
            case 200...299:
                // Parse response to get server capture ID
                if let data = data {
                    parseUploadResponse(data, for: captureId)
                }
            case 429:
                // Rate limited - mark as paused for retry later
                Self.logger.warning("Video upload rate limited for \(captureId.uuidString)")
                Task {
                    try? await captureStore?.updateVideoCaptureStatus(.paused, for: captureId)
                }
            case 401:
                // Device auth failed - needs re-registration
                Self.logger.error("Video upload auth failed for \(captureId.uuidString)")
                Task {
                    try? await captureStore?.updateVideoCaptureStatus(.failed, for: captureId)
                }
            case 413:
                // Payload too large - permanent failure
                Self.logger.error("Video upload payload too large for \(captureId.uuidString)")
                Task {
                    try? await captureStore?.updateVideoCaptureStatus(.failed, for: captureId)
                }
            default:
                // Server error - retry later
                Self.logger.error("Video upload server error (\(httpResponse.statusCode)) for \(captureId.uuidString)")
                Task {
                    try? await captureStore?.updateVideoCaptureStatus(.failed, for: captureId)
                }
            }
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
        Self.logger.debug("Video upload progress: \(Int(progress * 100))%")
    }

    /// Parse upload response and update capture store
    private func parseUploadResponse(_ data: Data, for captureId: UUID) {
        do {
            let response = try JSONDecoder().decode(VideoUploadResponse.self, from: data)

            Task {
                try? await captureStore?.updateVideoUploadResult(
                    for: captureId,
                    serverCaptureId: response.captureId,
                    verificationUrl: response.verificationUrl
                )
            }

            Self.logger.info("Video upload success - server ID: \(response.captureId.uuidString)")
        } catch {
            Self.logger.warning("Failed to parse video upload response: \(error.localizedDescription)")

            // Still mark as uploaded even if we can't parse the response
            Task {
                try? await captureStore?.updateVideoCaptureStatus(.uploaded, for: captureId)
            }
        }
    }
}

// MARK: - URLSessionDataDelegate

extension VideoUploadService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Accumulate response data
        lock.lock()
        if responseData[dataTask.taskIdentifier] == nil {
            responseData[dataTask.taskIdentifier] = Data()
        }
        responseData[dataTask.taskIdentifier]?.append(data)
        lock.unlock()
    }
}

// MARK: - VideoUploadResponse

/// Response from video capture upload endpoint.
private struct VideoUploadResponse: Decodable {
    let captureId: UUID
    let type: String
    let status: String
    let verificationUrl: String

    enum CodingKeys: String, CodingKey {
        case data
    }

    enum DataKeys: String, CodingKey {
        case captureId = "capture_id"
        case type
        case status
        case verificationUrl = "verification_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)

        captureId = try data.decode(UUID.self, forKey: .captureId)
        type = try data.decode(String.self, forKey: .type)
        status = try data.decode(String.self, forKey: .status)
        verificationUrl = try data.decode(String.self, forKey: .verificationUrl)
    }
}

// MARK: - VideoUploadError

/// Errors that can occur during video upload.
enum VideoUploadError: Error, LocalizedError {
    /// Service not configured
    case notConfigured

    /// Device not registered
    case deviceNotRegistered

    /// Failed to create request
    case requestFailed(String)

    /// Failed to read video file
    case videoReadFailed(String)

    /// Network error
    case networkError(Error)

    /// Server error
    case serverError(Int)

    /// Rate limited
    case rateLimited(retryAfter: Int)

    /// Payload too large
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "VideoUploadService not configured. Call configure() first."
        case .deviceNotRegistered:
            return "Device is not registered"
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .videoReadFailed(let message):
            return "Failed to read video file: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code):
            return "Server error (\(code))"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(retryAfter) seconds."
        case .payloadTooLarge:
            return "Video exceeds maximum upload size"
        }
    }

    /// Whether this error should be retried
    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError, .rateLimited:
            return true
        default:
            return false
        }
    }
}
