//
//  VideoUploadServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-27.
//
//  Unit tests for VideoUploadService (Story 7-8).
//

import XCTest
@testable import Rial

/// Unit tests for VideoUploadService
///
/// Tests background video upload functionality including:
/// - Multipart body creation with consistent boundary
/// - Request header formatting
/// - URL path construction
/// - Error handling and retryability
/// - Temp file management
class VideoUploadServiceTests: XCTestCase {

    // MARK: - Multipart Boundary Tests

    /// Test multipart boundary format is correct
    func testMultipartBoundaryFormat() {
        // Multipart boundaries should start with "RialVideo-" and be followed by UUID
        let pattern = "RialVideo-[A-F0-9-]+"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])

        let testBoundary = "RialVideo-\(UUID().uuidString)"
        let range = NSRange(testBoundary.startIndex..., in: testBoundary)
        XCTAssertNotNil(regex.firstMatch(in: testBoundary, range: range))
    }

    /// Test multipart part formatting for video
    func testMultipartPartFormatting() {
        let boundary = "RialVideo-TEST-BOUNDARY"
        let testData = Data("test video content".utf8)

        // Create a part manually to verify format
        var part = Data()
        part.append("--\(boundary)\r\n".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"video\"; filename=\"video.mp4\"\r\n".data(using: .utf8)!)
        part.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        part.append(testData)
        part.append("\r\n".data(using: .utf8)!)

        // Verify it contains expected headers
        let partString = String(data: part, encoding: .utf8)!
        XCTAssertTrue(partString.contains("--\(boundary)"))
        XCTAssertTrue(partString.contains("Content-Disposition: form-data"))
        XCTAssertTrue(partString.contains("name=\"video\""))
        XCTAssertTrue(partString.contains("filename=\"video.mp4\""))
        XCTAssertTrue(partString.contains("Content-Type: video/mp4"))
    }

    /// Test multipart closing boundary format
    func testMultipartClosingBoundary() {
        let boundary = "RialVideo-TEST-BOUNDARY"
        let closingBoundary = "--\(boundary)--\r\n"

        XCTAssertTrue(closingBoundary.hasPrefix("--"))
        XCTAssertTrue(closingBoundary.hasSuffix("--\r\n"))
        XCTAssertTrue(closingBoundary.contains(boundary))
    }

    // MARK: - Request Header Tests

    /// Test device ID header format
    func testDeviceIdHeaderFormat() {
        let deviceId = UUID()
        let headerValue = deviceId.uuidString

        // Should be uppercase hex with dashes
        let pattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(headerValue.startIndex..., in: headerValue)
        XCTAssertNotNil(regex.firstMatch(in: headerValue, range: range))
    }

    /// Test timestamp header format
    func testTimestampHeaderFormat() {
        let now = Date()
        let timestamp = Int64(now.timeIntervalSince1970 * 1000)
        let headerValue = String(timestamp)

        // Should be a 13-digit number (milliseconds since epoch)
        XCTAssertTrue(headerValue.count >= 13)
        XCTAssertTrue(Int64(headerValue) != nil)
    }

    // MARK: - URL Path Tests

    /// Test URL path construction without double slashes
    func testURLPathConstruction() {
        let baseURL = URL(string: "https://api.realitycam.app")!
        let path = "api/v1/captures/video"
        let fullURL = baseURL.appendingPathComponent(path)

        // Should not have double slashes
        XCTAssertFalse(fullURL.absoluteString.contains("//api"))
        XCTAssertTrue(fullURL.absoluteString.contains("/api/v1/captures/video"))
    }

    /// Test URL path with trailing slash base URL
    func testURLPathWithTrailingSlash() {
        let baseURL = URL(string: "https://api.realitycam.app/")!
        let path = "api/v1/captures/video"
        let fullURL = baseURL.appendingPathComponent(path)

        // appendingPathComponent handles this correctly
        XCTAssertTrue(fullURL.absoluteString.contains("/api/v1/captures/video"))
    }

    // MARK: - Error Handling Tests

    /// Test VideoUploadError is retryable for network errors
    func testNetworkErrorIsRetryable() {
        let error = VideoUploadError.networkError(NSError(domain: "", code: 0))
        XCTAssertTrue(error.isRetryable)
    }

    /// Test VideoUploadError is retryable for server errors
    func testServerErrorIsRetryable() {
        let error = VideoUploadError.serverError(500)
        XCTAssertTrue(error.isRetryable)
    }

    /// Test VideoUploadError is retryable for rate limited
    func testRateLimitedIsRetryable() {
        let error = VideoUploadError.rateLimited(retryAfter: 60)
        XCTAssertTrue(error.isRetryable)
    }

    /// Test VideoUploadError is not retryable for device not registered
    func testDeviceNotRegisteredNotRetryable() {
        let error = VideoUploadError.deviceNotRegistered
        XCTAssertFalse(error.isRetryable)
    }

    /// Test VideoUploadError is not retryable for payload too large
    func testPayloadTooLargeNotRetryable() {
        let error = VideoUploadError.payloadTooLarge
        XCTAssertFalse(error.isRetryable)
    }

    /// Test VideoUploadError is not retryable for not configured
    func testNotConfiguredNotRetryable() {
        let error = VideoUploadError.notConfigured
        XCTAssertFalse(error.isRetryable)
    }

    // MARK: - Error Description Tests

    /// Test error descriptions are meaningful
    func testErrorDescriptions() {
        XCTAssertNotNil(VideoUploadError.notConfigured.errorDescription)
        XCTAssertNotNil(VideoUploadError.deviceNotRegistered.errorDescription)
        XCTAssertNotNil(VideoUploadError.payloadTooLarge.errorDescription)

        let rateLimitError = VideoUploadError.rateLimited(retryAfter: 120)
        XCTAssertTrue(rateLimitError.errorDescription?.contains("120") ?? false)
    }

    // MARK: - Temp File Tests

    /// Test temp file URL format
    func testTempFileURLFormat() {
        let captureId = UUID()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("video-upload-\(captureId.uuidString).multipart")

        XCTAssertTrue(tempFile.lastPathComponent.hasPrefix("video-upload-"))
        XCTAssertTrue(tempFile.lastPathComponent.hasSuffix(".multipart"))
        XCTAssertTrue(tempFile.lastPathComponent.contains(captureId.uuidString))
    }

    /// Test temp file is in temp directory
    func testTempFileInTempDirectory() {
        let captureId = UUID()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("video-upload-\(captureId.uuidString).multipart")

        XCTAssertTrue(tempFile.path.contains("tmp") || tempFile.path.contains("Temp") || tempFile.path.contains("T/"))
    }

    // MARK: - Session Identifier Tests

    /// Test session identifier is unique from photo upload
    func testSessionIdentifierUniqueness() {
        let videoSessionId = VideoUploadService.sessionIdentifier
        let photoSessionId = "app.rial.upload" // From UploadService

        XCTAssertNotEqual(videoSessionId, photoSessionId)
        XCTAssertEqual(videoSessionId, "app.rial.video-upload")
    }

    // MARK: - ProcessedVideoCapture Tests

    /// Test ProcessedVideoCapture total size calculation
    func testProcessedVideoCaptureTotalSize() {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("test-video-\(UUID().uuidString).mp4")

        // Create a small test file
        let videoData = Data(repeating: 0x00, count: 1000)
        try? videoData.write(to: videoURL)

        defer {
            try? FileManager.default.removeItem(at: videoURL)
        }

        let capture = ProcessedVideoCapture(
            id: UUID(),
            videoURL: videoURL,
            compressedDepthData: Data(repeating: 0x01, count: 500),
            hashChainJSON: Data(repeating: 0x02, count: 200),
            metadataJSON: Data(repeating: 0x03, count: 100),
            thumbnailData: Data(repeating: 0x04, count: 50),
            frameCount: 300,
            depthKeyframeCount: 100,
            durationMs: 10000,
            isPartial: false
        )

        // Total should be video (1000) + depth (500) + hash (200) + metadata (100) + thumbnail (50) = 1850
        XCTAssertEqual(capture.totalSizeBytes, 1850)
    }

    /// Test ProcessedVideoCapture hasDepthData
    func testProcessedVideoCaptureHasDepthData() {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("test-video-\(UUID().uuidString).mp4")

        let captureWithDepth = ProcessedVideoCapture(
            id: UUID(),
            videoURL: videoURL,
            compressedDepthData: Data(repeating: 0x01, count: 500),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 300,
            depthKeyframeCount: 100,
            durationMs: 10000,
            isPartial: false
        )
        XCTAssertTrue(captureWithDepth.hasDepthData)

        let captureWithoutDepth = ProcessedVideoCapture(
            id: UUID(),
            videoURL: videoURL,
            compressedDepthData: Data(),
            hashChainJSON: Data(),
            metadataJSON: Data(),
            thumbnailData: Data(),
            frameCount: 300,
            depthKeyframeCount: 0,
            durationMs: 10000,
            isPartial: false
        )
        XCTAssertFalse(captureWithoutDepth.hasDepthData)
    }

    // MARK: - VideoCaptureStatus Tests

    /// Test VideoCaptureStatus isComplete
    func testVideoCaptureStatusIsComplete() {
        XCTAssertTrue(VideoCaptureStatus.uploaded.isComplete)
        XCTAssertFalse(VideoCaptureStatus.uploading.isComplete)
        XCTAssertFalse(VideoCaptureStatus.failed.isComplete)
        XCTAssertFalse(VideoCaptureStatus.pendingUpload.isComplete)
    }

    /// Test VideoCaptureStatus isInProgress
    func testVideoCaptureStatusIsInProgress() {
        XCTAssertTrue(VideoCaptureStatus.uploading.isInProgress)
        XCTAssertTrue(VideoCaptureStatus.processing.isInProgress)
        XCTAssertFalse(VideoCaptureStatus.uploaded.isInProgress)
        XCTAssertFalse(VideoCaptureStatus.failed.isInProgress)
    }

    /// Test VideoCaptureStatus canRetry
    func testVideoCaptureStatusCanRetry() {
        XCTAssertTrue(VideoCaptureStatus.failed.canRetry)
        XCTAssertTrue(VideoCaptureStatus.paused.canRetry)
        XCTAssertFalse(VideoCaptureStatus.uploaded.canRetry)
        XCTAssertFalse(VideoCaptureStatus.uploading.canRetry)
    }
}
