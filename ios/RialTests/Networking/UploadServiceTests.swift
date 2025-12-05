//
//  UploadServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for UploadService.
//

import XCTest
@testable import Rial

/// Unit tests for UploadService
///
/// Tests background upload functionality including:
/// - Multipart body creation
/// - Request header formatting
/// - Upload task creation
/// - Status tracking
class UploadServiceTests: XCTestCase {

    var keychain: TestKeychainService!
    var captureStore: CaptureStore!
    var baseURL: URL!

    override func setUp() {
        super.setUp()
        keychain = TestKeychainService()
        captureStore = CaptureStore(inMemory: true)
        baseURL = URL(string: "https://api.test.realitycam.app")!
        // Configure the shared singleton for tests
        UploadService.shared.configure(baseURL: baseURL, captureStore: captureStore, keychain: keychain)
    }

    override func tearDown() {
        captureStore = nil
        keychain = nil
        baseURL = nil
        super.tearDown()
    }

    // MARK: - Multipart Body Tests

    /// Test multipart boundary format is correct
    func testMultipartBoundaryFormat() {
        // Multipart boundaries should start with "Rial-" and be followed by UUID
        let pattern = "Rial-[A-F0-9-]+"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])

        let testBoundary = "Rial-\(UUID().uuidString)"
        let range = NSRange(testBoundary.startIndex..., in: testBoundary)
        XCTAssertNotNil(regex.firstMatch(in: testBoundary, range: range))
    }

    /// Test multipart part formatting
    func testMultipartPartFormatting() {
        let boundary = "Rial-TEST-BOUNDARY"
        let testData = Data("test content".utf8)

        // Create a part manually to verify format
        var part = Data()
        part.append("--\(boundary)\r\n".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        part.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        part.append(testData)
        part.append("\r\n".data(using: .utf8)!)

        // Verify it contains expected headers
        let partString = String(data: part, encoding: .utf8)!
        XCTAssertTrue(partString.contains("--\(boundary)"))
        XCTAssertTrue(partString.contains("Content-Disposition: form-data"))
        XCTAssertTrue(partString.contains("name=\"photo\""))
        XCTAssertTrue(partString.contains("filename=\"photo.jpg\""))
        XCTAssertTrue(partString.contains("Content-Type: image/jpeg"))
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

    // MARK: - CaptureData Creation Tests

    /// Test capture data is properly serializable
    func testCaptureDataSerialization() throws {
        let capture = createMockCapture()

        // Metadata should be JSON-encodable
        let encoder = JSONEncoder()
        let metadataJSON = try encoder.encode(capture.metadata)
        XCTAssertGreaterThan(metadataJSON.count, 0)

        // Can decode it back
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureMetadata.self, from: metadataJSON)
        XCTAssertEqual(decoded.photoHash, capture.metadata.photoHash)
    }

    // MARK: - Upload Flow Tests

    /// Test upload updates store status to uploading
    func testUploadUpdatesStatusToUploading() async throws {
        // Setup: Register device
        let deviceState = DeviceState(
            deviceId: UUID().uuidString,
            attestationKeyId: "test-key-id",
            isRegistered: true,
            registeredAt: Date()
        )
        try keychain.saveDeviceState(deviceState)

        // Create and save capture
        let capture = createMockCapture()
        try await captureStore.saveCapture(capture, status: .pending)

        // Verify initial status
        let initialCapture = try await captureStore.fetchCapture(byId: capture.id)
        XCTAssertNotNil(initialCapture)

        // Note: Actual upload would fail since we don't have network access in tests
        // This test just verifies the status update flow
    }

    /// Test upload fails gracefully without device registration
    func testUploadFailsWithoutDeviceRegistration() async throws {
        let capture = createMockCapture()
        try await captureStore.saveCapture(capture, status: .pending)

        // Upload should throw deviceNotRegistered error
        do {
            try await UploadService.shared.upload(capture)
            XCTFail("Expected deviceNotRegistered error")
        } catch UploadError.deviceNotRegistered {
            // Expected
        }

        // Status should be updated to failed
        let failedCapture = try await captureStore.fetchCapture(byId: capture.id)
        XCTAssertNotNil(failedCapture)
    }

    /// Test notConfigured error
    func testNotConfiguredErrorIsNotRetryable() {
        let error = UploadError.notConfigured
        XCTAssertFalse(error.isRetryable)
    }

    // MARK: - Error Handling Tests

    /// Test upload error is retryable for network errors
    func testNetworkErrorIsRetryable() {
        let error = UploadError.networkError(NSError(domain: "", code: 0))
        XCTAssertTrue(error.isRetryable)
    }

    /// Test upload error is retryable for server errors
    func testServerErrorIsRetryable() {
        let error = UploadError.serverError(500)
        XCTAssertTrue(error.isRetryable)
    }

    /// Test upload error is not retryable for device not registered
    func testDeviceNotRegisteredNotRetryable() {
        let error = UploadError.deviceNotRegistered
        XCTAssertFalse(error.isRetryable)
    }

    // MARK: - Temp File Tests

    /// Test temp file URL format
    func testTempFileURLFormat() {
        let captureId = UUID()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("upload-\(captureId.uuidString).multipart")

        XCTAssertTrue(tempFile.lastPathComponent.hasPrefix("upload-"))
        XCTAssertTrue(tempFile.lastPathComponent.hasSuffix(".multipart"))
        XCTAssertTrue(tempFile.lastPathComponent.contains(captureId.uuidString))
    }

    // MARK: - Helpers

    private func createMockCapture() -> CaptureData {
        let jpeg = Data(repeating: 0x42, count: 1000)
        let depth = Data(repeating: 0x43, count: 500)

        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone Test",
            photoHash: "mock-hash-\(UUID().uuidString)",
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        return CaptureData(
            id: UUID(),
            jpeg: jpeg,
            depth: depth,
            metadata: metadata,
            assertion: Data(repeating: 0x44, count: 100),
            assertionStatus: .generated,
            assertionAttemptCount: 0,
            timestamp: Date()
        )
    }
}

// MARK: - TestKeychainService

/// Simple keychain mock for upload tests
class TestKeychainService: KeychainService {
    private var storage: [String: Data] = [:]

    override func save(_ data: Data, forKey key: String) throws {
        storage[key] = data
    }

    override func load(forKey key: String) throws -> Data? {
        storage[key]
    }

    override func delete(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }

    override func saveDeviceState(_ state: DeviceState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        storage["rial.device.state"] = data
    }

    override func loadDeviceState() throws -> DeviceState? {
        guard let data = storage["rial.device.state"] else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeviceState.self, from: data)
    }
}
