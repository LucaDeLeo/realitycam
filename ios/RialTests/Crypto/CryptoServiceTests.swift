import XCTest
import CryptoKit
@testable import Rial

/// Comprehensive test suite for CryptoService
///
/// Tests cover:
/// - SHA-256 hashing with known test vectors
/// - SHA-256 streaming for large files
/// - AES-GCM encryption/decryption round-trips
/// - Authentication failure detection
/// - Wrong key detection
/// - Key serialization/deserialization
/// - Random data generation
/// - Performance benchmarks
class CryptoServiceTests: XCTestCase {

    // MARK: - SHA-256 Tests

    func testSHA256_EmptyString() {
        // Test vector from FIPS 180-4
        let data = Data()
        let hash = CryptoService.sha256(data)
        XCTAssertEqual(
            hash,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "Empty string SHA-256 hash mismatch"
        )
    }

    func testSHA256_ABC() {
        // Test vector from FIPS 180-4
        let data = "abc".data(using: .utf8)!
        let hash = CryptoService.sha256(data)
        XCTAssertEqual(
            hash,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "SHA-256 hash of 'abc' mismatch"
        )
    }

    func testSHA256_QuickBrownFox() {
        // Standard test phrase
        let data = "The quick brown fox jumps over the lazy dog".data(using: .utf8)!
        let hash = CryptoService.sha256(data)
        XCTAssertEqual(
            hash,
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
            "SHA-256 hash of 'quick brown fox' mismatch"
        )
    }

    func testSHA256Data_ReturnsRawBytes() {
        let data = "abc".data(using: .utf8)!
        let hashData = CryptoService.sha256Data(data)
        XCTAssertEqual(hashData.count, 32, "SHA-256 should produce 32 bytes")

        // Verify raw bytes match hex representation
        let expectedHex = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let actualHex = hashData.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHex, expectedHex, "Raw bytes should match hex representation")
    }

    func testSHA256_LargeData() {
        // Test with 1MB of data
        let largeData = Data(repeating: 0x42, count: 1_000_000)
        let hash = CryptoService.sha256(largeData)
        XCTAssertEqual(hash.count, 64, "SHA-256 hex should be 64 characters")

        // Verify consistency - same input produces same hash
        let hash2 = CryptoService.sha256(largeData)
        XCTAssertEqual(hash, hash2, "Hash should be deterministic")
    }

    func testSHA256Stream_FileNotFound_ThrowsError() {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent-file-\(UUID().uuidString).dat")

        XCTAssertThrowsError(try CryptoService.sha256Stream(url: nonExistentURL)) { error in
            guard let cryptoError = error as? CryptoError else {
                XCTFail("Expected CryptoError")
                return
            }
            if case .fileNotFound = cryptoError {
                // Expected
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testSHA256Stream_MatchesInMemoryHash() throws {
        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cryptotest-\(UUID().uuidString).dat")

        let testData = Data(repeating: 0x42, count: 5_000_000) // 5MB
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Compare streaming hash to in-memory hash
        let streamHash = try CryptoService.sha256Stream(url: tempURL)
        let memoryHash = CryptoService.sha256(testData)

        XCTAssertEqual(
            streamHash,
            memoryHash,
            "Streaming hash should match in-memory hash for identical data"
        )
    }

    // MARK: - AES-GCM Encryption Tests

    func testEncryptDecrypt_RoundTrip() throws {
        let plaintext = "Hello, World!".data(using: .utf8)!
        let key = CryptoService.generateKey()

        let ciphertext = try CryptoService.encrypt(plaintext, using: key)
        let decrypted = try CryptoService.decrypt(ciphertext, using: key)

        XCTAssertEqual(plaintext, decrypted, "Decrypted data should match plaintext")
    }

    func testEncryptDecrypt_EmptyData() throws {
        let plaintext = Data()
        let key = CryptoService.generateKey()

        let ciphertext = try CryptoService.encrypt(plaintext, using: key)
        let decrypted = try CryptoService.decrypt(ciphertext, using: key)

        XCTAssertEqual(plaintext, decrypted, "Empty data should encrypt/decrypt correctly")
    }

    func testEncryptDecrypt_LargeData() throws {
        let plaintext = Data(repeating: 0x42, count: 1_000_000) // 1MB
        let key = CryptoService.generateKey()

        let ciphertext = try CryptoService.encrypt(plaintext, using: key)
        let decrypted = try CryptoService.decrypt(ciphertext, using: key)

        XCTAssertEqual(plaintext, decrypted, "Large data should encrypt/decrypt correctly")
    }

    func testEncrypt_ProducesUniqueNonces() throws {
        let plaintext = "Same message".data(using: .utf8)!
        let key = CryptoService.generateKey()

        // Encrypt same message twice
        let ciphertext1 = try CryptoService.encrypt(plaintext, using: key)
        let ciphertext2 = try CryptoService.encrypt(plaintext, using: key)

        // Ciphertexts should differ (due to unique nonces)
        XCTAssertNotEqual(
            ciphertext1,
            ciphertext2,
            "Same plaintext should produce different ciphertext due to unique nonces"
        )

        // Both should decrypt to same plaintext
        let decrypted1 = try CryptoService.decrypt(ciphertext1, using: key)
        let decrypted2 = try CryptoService.decrypt(ciphertext2, using: key)
        XCTAssertEqual(decrypted1, plaintext)
        XCTAssertEqual(decrypted2, plaintext)
    }

    func testDecrypt_WrongKey_Fails() throws {
        let plaintext = "Secret message".data(using: .utf8)!
        let key1 = CryptoService.generateKey()
        let key2 = CryptoService.generateKey()

        let ciphertext = try CryptoService.encrypt(plaintext, using: key1)

        XCTAssertThrowsError(try CryptoService.decrypt(ciphertext, using: key2)) { error in
            XCTAssertTrue(
                error is CryptoError,
                "Should throw CryptoError for wrong key"
            )
            // Wrong key typically causes authentication failure
        }
    }

    func testDecrypt_TamperedData_Fails() throws {
        let plaintext = "Authenticated data".data(using: .utf8)!
        let key = CryptoService.generateKey()

        var ciphertext = try CryptoService.encrypt(plaintext, using: key)

        // Tamper with the ciphertext (flip last byte)
        ciphertext[ciphertext.count - 1] ^= 0xFF

        XCTAssertThrowsError(try CryptoService.decrypt(ciphertext, using: key)) { error in
            guard let cryptoError = error as? CryptoError else {
                XCTFail("Expected CryptoError")
                return
            }
            if case .authenticationFailed = cryptoError {
                // Expected - tampering detected
            } else {
                XCTFail("Expected authenticationFailed error")
            }
        }
    }

    func testDecrypt_TruncatedData_Fails() throws {
        let plaintext = "Test data".data(using: .utf8)!
        let key = CryptoService.generateKey()

        var ciphertext = try CryptoService.encrypt(plaintext, using: key)

        // Truncate ciphertext
        ciphertext = ciphertext.prefix(ciphertext.count - 5)

        XCTAssertThrowsError(try CryptoService.decrypt(ciphertext, using: key)) { error in
            XCTAssertTrue(error is CryptoError, "Should throw CryptoError for truncated data")
        }
    }

    // MARK: - Key Generation Tests

    func testGenerateKey_ReturnsValidKey() {
        let key = CryptoService.generateKey()
        let keyData = CryptoService.keyToData(key)
        XCTAssertEqual(keyData.count, 32, "AES-256 key should be 32 bytes")
    }

    func testGenerateKey_ProducesUniqueKeys() {
        let key1 = CryptoService.generateKey()
        let key2 = CryptoService.generateKey()

        let keyData1 = CryptoService.keyToData(key1)
        let keyData2 = CryptoService.keyToData(key2)

        XCTAssertNotEqual(keyData1, keyData2, "Generated keys should be unique")
    }

    func testKeySerializationRoundTrip() throws {
        let key = CryptoService.generateKey()
        let keyData = CryptoService.keyToData(key)
        let reconstructed = try CryptoService.keyFromData(keyData)

        // Test by encrypting with original and decrypting with reconstructed
        let plaintext = "Test data".data(using: .utf8)!
        let ciphertext = try CryptoService.encrypt(plaintext, using: key)
        let decrypted = try CryptoService.decrypt(ciphertext, using: reconstructed)

        XCTAssertEqual(plaintext, decrypted, "Reconstructed key should work identically")
    }

    func testKeyFromData_InvalidSize_Throws() {
        // Test with too small key
        let tooSmall = Data(repeating: 0, count: 16)
        XCTAssertThrowsError(try CryptoService.keyFromData(tooSmall)) { error in
            guard let cryptoError = error as? CryptoError else {
                XCTFail("Expected CryptoError")
                return
            }
            if case .invalidKey = cryptoError {
                // Expected
            } else {
                XCTFail("Expected invalidKey error")
            }
        }

        // Test with too large key
        let tooLarge = Data(repeating: 0, count: 64)
        XCTAssertThrowsError(try CryptoService.keyFromData(tooLarge)) { error in
            guard let cryptoError = error as? CryptoError else {
                XCTFail("Expected CryptoError")
                return
            }
            if case .invalidKey = cryptoError {
                // Expected
            } else {
                XCTFail("Expected invalidKey error")
            }
        }
    }

    // MARK: - Random Data Tests

    func testRandomData_GeneratesCorrectLength() {
        let lengths = [1, 16, 32, 64, 128, 256]
        for length in lengths {
            let data = CryptoService.randomData(count: length)
            XCTAssertEqual(data.count, length, "Random data should match requested length")
        }
    }

    func testRandomData_IsNotPredictable() {
        let data1 = CryptoService.randomData(count: 32)
        let data2 = CryptoService.randomData(count: 32)
        XCTAssertNotEqual(data1, data2, "Random data should not be identical")
    }

    func testRandomData_NotAllZeros() {
        let data = CryptoService.randomData(count: 32)
        let allZeros = Data(repeating: 0, count: 32)
        XCTAssertNotEqual(data, allZeros, "Random data should not be all zeros")
    }

    func testRandomData_NotAllOnes() {
        let data = CryptoService.randomData(count: 32)
        let allOnes = Data(repeating: 0xFF, count: 32)
        XCTAssertNotEqual(data, allOnes, "Random data should not be all ones")
    }

    func testRandomData_HasVariation() {
        // Generate 32 bytes and ensure they're not all the same value
        let data = CryptoService.randomData(count: 32)
        let bytes = [UInt8](data)
        let firstByte = bytes[0]
        let allSame = bytes.allSatisfy { $0 == firstByte }
        XCTAssertFalse(allSame, "Random data should have variation in byte values")
    }

    // MARK: - Error Handling Tests

    func testCryptoError_HasDescriptions() {
        let errors: [CryptoError] = [
            .encryptionFailed,
            .decryptionFailed,
            .authenticationFailed,
            .invalidKey,
            .fileNotFound,
            .fileReadError
        ]

        for error in errors {
            XCTAssertNotNil(
                error.errorDescription,
                "Error \(error) should have description"
            )
            XCTAssertFalse(
                error.errorDescription?.isEmpty ?? true,
                "Error description should not be empty"
            )
        }
    }

    // MARK: - Performance Tests

    func testSHA256_10MB_Performance() {
        let testData = Data(repeating: 0x42, count: 10_000_000) // 10MB

        measure {
            _ = CryptoService.sha256(testData)
        }

        // Target: < 100ms
        // Actual performance depends on hardware
        // iPhone 12 Pro should complete in ~20-30ms
    }

    func testSHA256Stream_10MB_Performance() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perftest-\(UUID().uuidString).dat")

        let testData = Data(repeating: 0x42, count: 10_000_000) // 10MB
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        measure {
            _ = try? CryptoService.sha256Stream(url: tempURL)
        }

        // Should be comparable to in-memory hash
    }

    func testEncryption_5MB_Performance() throws {
        let testData = Data(repeating: 0x42, count: 5_000_000) // 5MB
        let key = CryptoService.generateKey()

        measure {
            _ = try? CryptoService.encrypt(testData, using: key)
        }

        // Target: < 50ms
        // Actual performance depends on hardware
        // iPhone 12 Pro should complete in ~10-20ms
    }

    func testDecryption_5MB_Performance() throws {
        let testData = Data(repeating: 0x42, count: 5_000_000) // 5MB
        let key = CryptoService.generateKey()
        let ciphertext = try CryptoService.encrypt(testData, using: key)

        measure {
            _ = try? CryptoService.decrypt(ciphertext, using: key)
        }

        // Target: < 50ms
        // Similar to encryption performance
    }

    func testKeyGeneration_Performance() {
        measure {
            _ = CryptoService.generateKey()
        }

        // Target: < 1ms
        // Key generation should be very fast
    }

    func testRandomData_Performance() {
        measure {
            _ = CryptoService.randomData(count: 256)
        }

        // Should be very fast (< 1ms)
    }

    // MARK: - Integration Tests

    func testRealWorldWorkflow_CaptureEncryption() throws {
        // Simulate real-world scenario: encrypt a capture for offline storage

        // 1. Generate encryption key (would be stored in Keychain)
        let key = CryptoService.generateKey()
        let keyData = CryptoService.keyToData(key)

        // 2. Create mock capture data (photo + depth + metadata)
        let photoData = Data(repeating: 0xAB, count: 2_000_000) // 2MB photo
        let depthData = Data(repeating: 0xCD, count: 500_000)   // 500KB depth
        let metadataJSON = """
        {
            "timestamp": "2025-11-25T12:00:00Z",
            "location": {"lat": 37.7749, "lon": -122.4194},
            "device": "iPhone 12 Pro"
        }
        """.data(using: .utf8)!

        var captureData = Data()
        captureData.append(photoData)
        captureData.append(depthData)
        captureData.append(metadataJSON)

        // 3. Compute hash before encryption
        let hashBeforeEncryption = CryptoService.sha256(captureData)

        // 4. Encrypt for offline storage
        let encryptedCapture = try CryptoService.encrypt(captureData, using: key)

        // 5. Simulate app restart - reconstruct key from Keychain
        let reconstructedKey = try CryptoService.keyFromData(keyData)

        // 6. Decrypt when ready to upload
        let decryptedCapture = try CryptoService.decrypt(encryptedCapture, using: reconstructedKey)

        // 7. Verify hash after decryption
        let hashAfterDecryption = CryptoService.sha256(decryptedCapture)

        XCTAssertEqual(captureData, decryptedCapture, "Decrypted capture should match original")
        XCTAssertEqual(
            hashBeforeEncryption,
            hashAfterDecryption,
            "Hash should match before/after encryption"
        )
    }

    func testRealWorldWorkflow_StreamingHashForLargeCapture() throws {
        // Simulate hashing a large capture file

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("large-capture-\(UUID().uuidString).dat")

        // Create a 20MB mock capture
        let largeCapture = Data(repeating: 0x42, count: 20_000_000)
        try largeCapture.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Hash using streaming (memory efficient)
        let streamHash = try CryptoService.sha256Stream(url: tempURL)

        // Verify it matches in-memory hash
        let memoryHash = CryptoService.sha256(largeCapture)

        XCTAssertEqual(streamHash, memoryHash, "Streaming hash should match in-memory hash")
    }
}
