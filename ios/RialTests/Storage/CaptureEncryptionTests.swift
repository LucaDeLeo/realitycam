//
//  CaptureEncryptionTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-25.
//
//  Unit tests for CaptureEncryption service.
//

import XCTest
@testable import Rial

/// Unit tests for CaptureEncryption
///
/// Tests encryption/decryption, key management, and integration with CaptureStore.
class CaptureEncryptionTests: XCTestCase {

    var keychain: MockKeychainService!
    var sut: CaptureEncryption!

    override func setUp() {
        super.setUp()
        keychain = MockKeychainService()
        sut = CaptureEncryption(keychain: keychain)
    }

    override func tearDown() {
        sut = nil
        keychain = nil
        super.tearDown()
    }

    // MARK: - Encryption Tests

    /// Test encrypting and decrypting capture data
    func testEncryptDecryptCapture() throws {
        let jpeg = Data(repeating: 0x42, count: 1000)
        let depth = Data(repeating: 0x43, count: 500)
        let metadata = Data(repeating: 0x44, count: 100)

        // Encrypt
        let encrypted = try sut.encryptCapture(jpeg: jpeg, depth: depth, metadata: metadata)

        // Verify encrypted data is different from original
        XCTAssertNotEqual(encrypted.jpeg, jpeg)
        XCTAssertNotEqual(encrypted.depth, depth)
        XCTAssertNotEqual(encrypted.metadata, metadata)

        // Verify encrypted data is larger (includes nonce + tag)
        XCTAssertGreaterThan(encrypted.jpeg.count, jpeg.count)
        XCTAssertGreaterThan(encrypted.depth.count, depth.count)
        XCTAssertGreaterThan(encrypted.metadata.count, metadata.count)

        // Decrypt
        let decrypted = try sut.decryptCapture(
            jpeg: encrypted.jpeg,
            depth: encrypted.depth,
            metadata: encrypted.metadata
        )

        // Verify decrypted data matches original
        XCTAssertEqual(decrypted.jpeg, jpeg)
        XCTAssertEqual(decrypted.depth, depth)
        XCTAssertEqual(decrypted.metadata, metadata)
    }

    /// Test encrypting single data blob
    func testEncryptDecryptSingle() throws {
        let original = Data("Hello, World!".utf8)

        let encrypted = try sut.encrypt(original)
        let decrypted = try sut.decrypt(encrypted)

        XCTAssertEqual(decrypted, original)
        XCTAssertNotEqual(encrypted, original)
    }

    /// Test encrypting optional data
    func testEncryptDecryptOptional() throws {
        let original = Data(repeating: 0x55, count: 50)

        // Non-nil case
        let encrypted = try sut.encrypt(optional: original)
        XCTAssertNotNil(encrypted)
        let decrypted = try sut.decrypt(optional: encrypted)
        XCTAssertEqual(decrypted, original)

        // Nil case
        let nilEncrypted = try sut.encrypt(optional: nil)
        XCTAssertNil(nilEncrypted)
        let nilDecrypted = try sut.decrypt(optional: nil)
        XCTAssertNil(nilDecrypted)
    }

    /// Test that each encryption produces different ciphertext (random nonce)
    func testEncryptionProducesDifferentCiphertext() throws {
        let data = Data("Same data".utf8)

        let encrypted1 = try sut.encrypt(data)
        let encrypted2 = try sut.encrypt(data)

        // Ciphertexts should be different due to random nonce
        XCTAssertNotEqual(encrypted1, encrypted2)

        // But both should decrypt to the same plaintext
        let decrypted1 = try sut.decrypt(encrypted1)
        let decrypted2 = try sut.decrypt(encrypted2)
        XCTAssertEqual(decrypted1, decrypted2)
        XCTAssertEqual(decrypted1, data)
    }

    // MARK: - Key Management Tests

    /// Test key is created on first encryption
    func testKeyCreatedOnFirstEncryption() throws {
        XCTAssertFalse(sut.hasKey)

        _ = try sut.encrypt(Data("test".utf8))

        XCTAssertTrue(sut.hasKey)
    }

    /// Test key is reused across encryptions
    func testKeyReusedAcrossEncryptions() throws {
        let data = Data("test".utf8)

        // First encryption creates key
        let encrypted1 = try sut.encrypt(data)

        // Clear cache to force reload from keychain
        sut.clearCache()

        // Second encryption should use same key
        let encrypted2 = try sut.encrypt(data)

        // Both should decrypt successfully (same key)
        let decrypted1 = try sut.decrypt(encrypted1)
        let decrypted2 = try sut.decrypt(encrypted2)
        XCTAssertEqual(decrypted1, data)
        XCTAssertEqual(decrypted2, data)
    }

    /// Test decryption fails without key
    func testDecryptionFailsWithoutKey() throws {
        // Encrypt with one CaptureEncryption instance
        _ = try sut.encrypt(Data("test".utf8))

        // Create new instance with empty keychain (simulating different device)
        let newKeychain = MockKeychainService()
        let newEncryption = CaptureEncryption(keychain: newKeychain)

        // Decryption should fail
        do {
            _ = try newEncryption.decrypt(Data(repeating: 0x42, count: 100))
            XCTFail("Expected keyNotFound error")
        } catch CaptureEncryptionError.keyNotFound {
            // Expected
        }
    }

    /// Test deleting key
    func testDeleteKey() throws {
        // Create key
        _ = try sut.encrypt(Data("test".utf8))
        XCTAssertTrue(sut.hasKey)

        // Delete key
        try sut.deleteKey()
        XCTAssertFalse(sut.hasKey)
    }

    // MARK: - Integration Tests

    /// Test encryption with CaptureStore
    func testEncryptedCaptureStore() async throws {
        let store = CaptureStore(inMemory: true, encryption: sut)

        let capture = createMockCapture()
        try await store.saveCapture(capture)

        // Fetch and verify data matches
        let fetched = try await store.fetchCapture(byId: capture.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.jpeg, capture.jpeg)
        XCTAssertEqual(fetched?.depth, capture.depth)
        XCTAssertEqual(fetched?.metadata.photoHash, capture.metadata.photoHash)
    }

    /// Test encrypted captures survive reload
    func testEncryptedCapturesRoundTrip() async throws {
        let store = CaptureStore(inMemory: true, encryption: sut)

        let capture1 = createMockCapture()
        let capture2 = createMockCapture()

        try await store.saveCapture(capture1)
        try await store.saveCapture(capture2)

        let all = try await store.fetchAllCaptures()
        XCTAssertEqual(all.count, 2)

        // Verify data integrity
        for fetched in all {
            let original = fetched.id == capture1.id ? capture1 : capture2
            XCTAssertEqual(fetched.jpeg, original.jpeg)
            XCTAssertEqual(fetched.depth, original.depth)
        }
    }

    // MARK: - Helpers

    private func createMockCapture() -> CaptureData {
        let jpeg = Data(repeating: 0x42, count: 10_000)
        let depth = Data(repeating: 0x43, count: 5_000)

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
            assertion: nil,
            assertionStatus: .none,
            assertionAttemptCount: 0,
            timestamp: Date()
        )
    }
}
