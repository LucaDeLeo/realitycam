//
//  CaptureAssertionServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for CaptureAssertionService.
//

import XCTest
@testable import Rial

/// Unit tests for CaptureAssertionService
///
/// Tests per-capture assertion generation, error handling, caching,
/// and integration with DeviceAttestationService.
///
/// ## Testing Strategy
/// - Uses MockDeviceAttestationService to simulate Secure Enclave operations
/// - Uses MockKeychainService for key ID storage
/// - Physical device required for integration tests with real DCAppAttest
class CaptureAssertionServiceTests: XCTestCase {

    var sut: CaptureAssertionService!
    var mockAttestation: MockDeviceAttestationService!
    var mockKeychain: MockKeychainService!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
        mockAttestation = MockDeviceAttestationService(keychain: mockKeychain)
        sut = CaptureAssertionService(attestation: mockAttestation, keychain: mockKeychain)
    }

    override func tearDown() {
        sut = nil
        mockAttestation = nil
        mockKeychain = nil
        super.tearDown()
    }

    // MARK: - Successful Assertion Tests

    /// Test successful assertion generation
    ///
    /// AC1: createAssertion returns non-empty assertion data
    func testCreateAssertionSuccess() async throws {
        // Setup: Store key ID in keychain
        let keyId = "test-key-id-123"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = keyId
        mockAttestation.mockAssertionData = Data(repeating: 0x42, count: 1024)

        // Create mock capture
        let capture = createMockCapture()

        // Test
        let assertion = try await sut.createAssertion(for: capture)

        // Verify
        XCTAssertFalse(assertion.isEmpty, "Assertion should not be empty")
        XCTAssertGreaterThan(assertion.count, 100, "Assertion should be substantial")
    }

    /// Test assertion data size is within expected range
    ///
    /// AC3: Data size between 500 bytes and 5KB (typical: 1-2KB)
    func testAssertionDataSizeRange() async throws {
        // Setup
        let keyId = "test-key-id"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = keyId
        mockAttestation.mockAssertionData = Data(repeating: 0x42, count: 1500) // ~1.5KB

        let capture = createMockCapture()

        // Test
        let assertion = try await sut.createAssertion(for: capture)

        // Verify typical assertion size
        XCTAssertGreaterThanOrEqual(assertion.count, 500, "Assertion should be at least 500 bytes")
        XCTAssertLessThanOrEqual(assertion.count, 5000, "Assertion should not exceed 5KB")
    }

    /// Test assertion with different capture sizes
    func testAssertionWithVariousCapturesSizes() async throws {
        let keyId = "test-key-id"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = keyId
        mockAttestation.mockAssertionData = Data(repeating: 0x42, count: 1024)

        let testCases: [(jpegSize: Int, depthSize: Int)] = [
            (1_000_000, 500_000),   // ~1.5MB total
            (3_000_000, 1_000_000), // ~4MB total
            (5_000_000, 2_000_000)  // ~7MB total
        ]

        for testCase in testCases {
            let capture = createMockCapture(jpegSize: testCase.jpegSize, depthSize: testCase.depthSize)
            let assertion = try await sut.createAssertion(for: capture)
            XCTAssertFalse(assertion.isEmpty, "Assertion should work for \(testCase.jpegSize + testCase.depthSize) bytes")
        }
    }

    // MARK: - Error Handling Tests

    /// Test error when key ID not found in keychain
    ///
    /// AC1: If key ID not found in keychain, throw .attestationKeyNotFound
    func testCreateAssertionThrowsWhenKeyNotFound() async {
        // No key ID stored in keychain

        let capture = createMockCapture()

        do {
            _ = try await sut.createAssertion(for: capture)
            XCTFail("Expected attestationKeyNotFound error")
        } catch CaptureAssertionError.attestationKeyNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    /// Test error when DCAppAttest fails
    ///
    /// AC1: If DCAppAttest fails, throw .assertionGenerationFailed
    func testCreateAssertionThrowsWhenDCAppAttestFails() async {
        // Setup: Store key ID but simulate DCAppAttest failure
        let keyId = "test-key-id"
        try? mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = keyId
        mockAttestation.shouldFailAssertion = true

        let capture = createMockCapture()

        do {
            _ = try await sut.createAssertion(for: capture)
            XCTFail("Expected assertionGenerationFailed error")
        } catch CaptureAssertionError.assertionGenerationFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Key ID Caching Tests

    /// Test key ID is cached after first load
    func testKeyIdCaching() async throws {
        let keyId = "cached-key-id"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = keyId
        mockAttestation.mockAssertionData = Data(repeating: 0x42, count: 1024)

        let capture = createMockCapture()

        // First call loads from keychain
        _ = try await sut.createAssertion(for: capture)

        // Delete from keychain
        try mockKeychain.delete(forKey: "rial.attestation.keyId")

        // Second call should use cached value
        let assertion = try await sut.createAssertion(for: capture)
        XCTAssertFalse(assertion.isEmpty, "Should use cached key ID")
    }

    /// Test clearCache invalidates cached key ID
    func testClearCache() async throws {
        let keyId = "cached-key-id"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = keyId
        mockAttestation.mockAssertionData = Data(repeating: 0x42, count: 1024)

        let capture = createMockCapture()

        // Load key ID into cache
        _ = try await sut.createAssertion(for: capture)

        // Clear cache
        sut.clearCache()

        // Simulate key ID no longer available (cleared from both keychain and mock)
        try mockKeychain.delete(forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = nil

        // Should now fail since cache is cleared and key ID is not available
        do {
            _ = try await sut.createAssertion(for: capture)
            XCTFail("Expected error after cache cleared")
        } catch CaptureAssertionError.attestationKeyNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - isAvailable Tests

    /// Test isAvailable returns true when device is registered
    func testIsAvailableWhenRegistered() throws {
        let keyId = "test-key-id"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockIsSupported = true
        mockAttestation.mockKeyId = keyId

        XCTAssertTrue(sut.isAvailable, "Should be available when registered")
    }

    /// Test isAvailable returns false when not registered
    func testIsAvailableWhenNotRegistered() {
        mockAttestation.mockIsSupported = true
        mockAttestation.mockKeyId = nil

        XCTAssertFalse(sut.isAvailable, "Should not be available when not registered")
    }

    /// Test isAvailable returns false when DCAppAttest not supported
    func testIsAvailableWhenNotSupported() throws {
        let keyId = "test-key-id"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockIsSupported = false
        mockAttestation.mockKeyId = keyId

        XCTAssertFalse(sut.isAvailable, "Should not be available when DCAppAttest not supported")
    }

    // MARK: - Error Description Tests

    /// Test all error cases have descriptions
    func testAllErrorCasesHaveDescriptions() {
        let errors: [CaptureAssertionError] = [
            .attestationKeyNotFound,
            .assertionGenerationFailed(NSError(domain: "test", code: 1)),
            .hashComputationFailed
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) description should not be empty")
        }
    }

    /// Test specific error descriptions
    func testSpecificErrorDescriptions() {
        XCTAssertEqual(
            CaptureAssertionError.attestationKeyNotFound.errorDescription,
            "Device attestation key not found in keychain"
        )

        XCTAssertEqual(
            CaptureAssertionError.hashComputationFailed.errorDescription,
            "Failed to compute capture data hash"
        )

        let underlyingError = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = CaptureAssertionError.assertionGenerationFailed(underlyingError)
        XCTAssertTrue(error.errorDescription!.contains("Test error"), "Should include underlying error description")
    }

    // MARK: - Equatable Tests

    /// Test error equality
    func testErrorEquality() {
        XCTAssertEqual(
            CaptureAssertionError.attestationKeyNotFound,
            CaptureAssertionError.attestationKeyNotFound
        )

        XCTAssertEqual(
            CaptureAssertionError.hashComputationFailed,
            CaptureAssertionError.hashComputationFailed
        )

        XCTAssertNotEqual(
            CaptureAssertionError.attestationKeyNotFound,
            CaptureAssertionError.hashComputationFailed
        )
    }

    // MARK: - AssertionStatus Tests

    /// Test AssertionStatus enum values
    func testAssertionStatusValues() {
        XCTAssertEqual(AssertionStatus.none.rawValue, "none")
        XCTAssertEqual(AssertionStatus.generated.rawValue, "generated")
        XCTAssertEqual(AssertionStatus.pending.rawValue, "pending")
        XCTAssertEqual(AssertionStatus.failed.rawValue, "failed")
    }

    /// Test AssertionStatus Codable conformance
    func testAssertionStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [AssertionStatus.none, .generated, .pending, .failed] {
            let encoded = try encoder.encode(status)
            let decoded = try decoder.decode(AssertionStatus.self, from: encoded)
            XCTAssertEqual(status, decoded, "Status should round-trip through Codable")
        }
    }

    // MARK: - CaptureData Extensions Tests

    /// Test CaptureData assertion extensions
    func testCaptureDataAssertionExtensions() {
        var capture = createMockCapture()

        // Initially no assertion
        XCTAssertFalse(capture.hasAssertion)
        XCTAssertNil(capture.base64EncodedAssertion)

        // After adding assertion
        capture.assertion = Data(repeating: 0x42, count: 100)
        capture.assertionStatus = .generated

        XCTAssertTrue(capture.hasAssertion)
        XCTAssertNotNil(capture.base64EncodedAssertion)
    }

    /// Test needsAssertionRetry
    func testNeedsAssertionRetry() {
        var capture = createMockCapture()

        // Not pending
        capture.assertionStatus = .none
        XCTAssertFalse(capture.needsAssertionRetry)

        // Pending but within retry limit
        capture.assertionStatus = .pending
        capture.assertionAttemptCount = 2
        XCTAssertTrue(capture.needsAssertionRetry)

        // Pending but exceeded retry limit
        capture.assertionAttemptCount = 3
        XCTAssertFalse(capture.needsAssertionRetry)
    }

    // MARK: - Performance Tests (Simulator-Safe)

    /// Test hash computation is reasonable (timing test)
    /// Note: Actual performance tests require physical device
    func testHashComputationNotBlocking() async throws {
        let keyId = "test-key-id"
        try mockKeychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        mockAttestation.mockKeyId = keyId
        mockAttestation.mockAssertionData = Data(repeating: 0x42, count: 1024)

        // Create 4MB capture (typical size)
        let capture = createMockCapture(jpegSize: 3_000_000, depthSize: 1_000_000)

        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await sut.createAssertion(for: capture)
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Hash computation should complete in reasonable time (generous for CI)
        // Mock assertion is instant, so this primarily tests hash computation
        XCTAssertLessThan(duration, 500, "Hash computation should complete in < 500ms")
    }

    // MARK: - Helpers

    /// Create mock CaptureData for testing
    private func createMockCapture(
        jpegSize: Int = 100_000,
        depthSize: Int = 50_000
    ) -> CaptureData {
        let jpeg = Data(repeating: 0x42, count: jpegSize)
        let depth = Data(repeating: 0x43, count: depthSize)

        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: "iPhone Test",
            photoHash: "mock-hash-\(UUID().uuidString)",
            location: nil,
            depthMapDimensions: DepthDimensions(width: 256, height: 192)
        )

        return CaptureData(
            jpeg: jpeg,
            depth: depth,
            metadata: metadata,
            assertion: nil,
            assertionStatus: .none,
            assertionAttemptCount: 0
        )
    }
}

// MARK: - Mock DeviceAttestationService

/// Mock DeviceAttestationService for testing without real DCAppAttest
class MockDeviceAttestationService: DeviceAttestationService {
    var mockIsSupported: Bool = true
    var mockKeyId: String?
    var mockAssertionData: Data?
    var shouldFailAssertion: Bool = false
    var shouldFailAttestation: Bool = false

    private let _keychain: MockKeychainService

    override var isSupported: Bool {
        mockIsSupported
    }

    init(keychain: MockKeychainService) {
        self._keychain = keychain
        super.init(keychain: keychain)
    }

    override func generateKey() async throws -> String {
        guard mockIsSupported else {
            throw AttestationError.unsupported
        }

        let keyId = mockKeyId ?? UUID().uuidString
        try _keychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
        return keyId
    }

    override func attestKey(_ keyId: String, challenge: Data) async throws -> Data {
        guard mockIsSupported else {
            throw AttestationError.unsupported
        }
        guard challenge.count == 32 else {
            throw AttestationError.invalidChallenge
        }
        guard !shouldFailAttestation else {
            throw AttestationError.attestationFailed(NSError(domain: "MockError", code: 1))
        }

        // Return mock attestation
        return Data(repeating: 0xAB, count: 2048)
    }

    override func generateAssertion(_ keyId: String, clientData: Data) async throws -> Data {
        guard mockIsSupported else {
            throw AttestationError.unsupported
        }
        guard !shouldFailAssertion else {
            throw AttestationError.assertionFailed(NSError(domain: "MockError", code: 2))
        }
        guard keyId == mockKeyId else {
            throw AttestationError.noKeyAvailable
        }

        // Return mock assertion
        return mockAssertionData ?? Data(repeating: 0xCD, count: 1024)
    }

    override func loadStoredKeyId() -> String? {
        mockKeyId
    }
}
