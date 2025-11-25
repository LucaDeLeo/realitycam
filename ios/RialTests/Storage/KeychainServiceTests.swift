import XCTest
import CryptoKit
@testable import Rial

/// Comprehensive tests for KeychainService
///
/// Tests all public methods including:
/// - Basic CRUD operations (save/load/delete)
/// - SymmetricKey storage and retrieval
/// - DeviceState JSON encoding/decoding
/// - Error handling paths
/// - Edge cases (empty data, large data, persistence)
///
/// ## Test Coverage Goals
/// - All public methods tested
/// - Error paths verified
/// - Edge cases covered
/// - Integration with CryptoService validated
/// - Target: 95%+ code coverage
class KeychainServiceTests: XCTestCase {
    var keychainService: KeychainService!

    /// Test keys used for cleanup
    let testKeys = [
        "test.key",
        "test.key.duplicate",
        "test.key.empty",
        "test.key.large",
        "test.symmetric",
        "test.symmetric.missing",
        "rial.device.state"
    ]

    override func setUp() {
        super.setUp()
        keychainService = KeychainService()

        // Clean up any leftover test items
        for key in testKeys {
            try? keychainService.delete(forKey: key)
        }
    }

    override func tearDown() {
        // Clean up test items
        for key in testKeys {
            try? keychainService.delete(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Basic Operations Tests

    /// Test save and load round-trip
    ///
    /// Verifies that data can be saved to Keychain and loaded back with identical content.
    func testSaveAndLoad_RoundTrip() throws {
        let testData = "Hello, Keychain!".data(using: .utf8)!

        try keychainService.save(testData, forKey: "test.key")
        let loaded = try keychainService.load(forKey: "test.key")

        XCTAssertNotNil(loaded, "Loaded data should not be nil")
        XCTAssertEqual(testData, loaded, "Loaded data should match saved data")
    }

    /// Test loading non-existent key returns nil
    ///
    /// Verifies that attempting to load a key that doesn't exist returns nil
    /// rather than throwing an error (expected behavior).
    func testLoad_NonExistentKey_ReturnsNil() throws {
        let loaded = try keychainService.load(forKey: "nonexistent.key")
        XCTAssertNil(loaded, "Loading non-existent key should return nil")
    }

    /// Test saving duplicate key updates the item
    ///
    /// Verifies that saving to an existing key updates the value rather than
    /// throwing a duplicate error.
    func testSave_DuplicateKey_UpdatesItem() throws {
        let data1 = "First value".data(using: .utf8)!
        let data2 = "Second value".data(using: .utf8)!

        try keychainService.save(data1, forKey: "test.key.duplicate")
        try keychainService.save(data2, forKey: "test.key.duplicate") // Should update, not error

        let loaded = try keychainService.load(forKey: "test.key.duplicate")
        XCTAssertEqual(data2, loaded, "Should load updated value")
    }

    /// Test deleting existing item succeeds
    ///
    /// Verifies that an item can be deleted and is no longer retrievable.
    func testDelete_ExistingItem_Succeeds() throws {
        let testData = "Delete me".data(using: .utf8)!
        try keychainService.save(testData, forKey: "test.key")

        try keychainService.delete(forKey: "test.key")

        let loaded = try keychainService.load(forKey: "test.key")
        XCTAssertNil(loaded, "Item should be deleted")
    }

    /// Test deleting non-existent item succeeds silently
    ///
    /// Verifies that delete operation is idempotent (doesn't throw if item doesn't exist).
    func testDelete_NonExistentItem_Succeeds() throws {
        // Should not throw
        try keychainService.delete(forKey: "nonexistent.key")
    }

    // MARK: - SymmetricKey Tests

    /// Test SymmetricKey save and load with encryption verification
    ///
    /// Verifies that a SymmetricKey can be stored, retrieved, and used for
    /// encryption/decryption operations (tests round-trip functionality).
    func testSymmetricKey_SaveAndLoad() throws {
        let key = CryptoService.generateKey()

        try keychainService.saveSymmetricKey(key, forKey: "test.symmetric")
        let loadedKey = try keychainService.loadSymmetricKey(forKey: "test.symmetric")

        XCTAssertNotNil(loadedKey, "Loaded key should not be nil")

        // Verify key works by encrypting and decrypting
        let plaintext = "Test encryption".data(using: .utf8)!
        let ciphertext = try CryptoService.encrypt(plaintext, using: key)
        let decrypted = try CryptoService.decrypt(ciphertext, using: loadedKey!)

        XCTAssertEqual(plaintext, decrypted, "Loaded key should work for encryption/decryption")
    }

    /// Test loading non-existent SymmetricKey returns nil
    ///
    /// Verifies that attempting to load a key that doesn't exist returns nil.
    func testSymmetricKey_LoadNonExistent_ReturnsNil() throws {
        let key = try keychainService.loadSymmetricKey(forKey: "test.symmetric.missing")
        XCTAssertNil(key, "Loading non-existent key should return nil")
    }

    /// Test SymmetricKey serialization round-trip preserves functionality
    ///
    /// Verifies that the key serialization/deserialization doesn't corrupt the key
    /// by testing encryption with original key and decryption with loaded key.
    func testSymmetricKey_RoundTrip_PreservesFunctionality() throws {
        let originalKey = CryptoService.generateKey()
        let plaintext = "Round-trip test".data(using: .utf8)!

        // Encrypt with original key
        let ciphertext = try CryptoService.encrypt(plaintext, using: originalKey)

        // Save and load key
        try keychainService.saveSymmetricKey(originalKey, forKey: "test.symmetric")
        guard let loadedKey = try keychainService.loadSymmetricKey(forKey: "test.symmetric") else {
            XCTFail("Failed to load key")
            return
        }

        // Decrypt with loaded key
        let decrypted = try CryptoService.decrypt(ciphertext, using: loadedKey)

        XCTAssertEqual(plaintext, decrypted, "Key should work after round-trip")
    }

    // MARK: - DeviceState Tests

    /// Test DeviceState save and load with complete data
    ///
    /// Verifies that DeviceState can be encoded to JSON, stored, and decoded
    /// with all fields preserved.
    func testDeviceState_SaveAndLoad() throws {
        let state = DeviceState(
            deviceId: UUID().uuidString,
            attestationKeyId: "test-key-id-abc123",
            isRegistered: true,
            registeredAt: Date()
        )

        try keychainService.saveDeviceState(state)
        let loadedState = try keychainService.loadDeviceState()

        XCTAssertNotNil(loadedState, "Loaded state should not be nil")
        XCTAssertEqual(state.deviceId, loadedState!.deviceId)
        XCTAssertEqual(state.attestationKeyId, loadedState!.attestationKeyId)
        XCTAssertEqual(state.isRegistered, loadedState!.isRegistered)

        // Compare dates with tolerance (JSON encoding may lose sub-second precision)
        if let originalDate = state.registeredAt, let loadedDate = loadedState!.registeredAt {
            XCTAssertEqual(originalDate.timeIntervalSince1970,
                          loadedDate.timeIntervalSince1970,
                          accuracy: 1.0,
                          "Dates should match within 1 second")
        }
    }

    /// Test loading non-existent DeviceState returns nil
    ///
    /// Verifies that attempting to load DeviceState when none exists returns nil
    /// (indicates device not registered yet).
    func testDeviceState_LoadNonExistent_ReturnsNil() throws {
        let state = try keychainService.loadDeviceState()
        XCTAssertNil(state, "Loading non-existent state should return nil")
    }

    /// Test DeviceState with partial data (unregistered device)
    ///
    /// Verifies that DeviceState works with optional fields set to nil
    /// (device created but not yet registered).
    func testDeviceState_PartialData() throws {
        let state = DeviceState(
            deviceId: UUID().uuidString,
            attestationKeyId: nil,  // Not yet registered
            isRegistered: false,
            registeredAt: nil
        )

        try keychainService.saveDeviceState(state)
        let loadedState = try keychainService.loadDeviceState()

        XCTAssertNotNil(loadedState, "Loaded state should not be nil")
        XCTAssertEqual(state.deviceId, loadedState!.deviceId)
        XCTAssertNil(loadedState!.attestationKeyId)
        XCTAssertFalse(loadedState!.isRegistered)
        XCTAssertNil(loadedState!.registeredAt)
    }

    // MARK: - Data Protection Tests

    /// Test Keychain item persists across service instances
    ///
    /// Verifies that data stored by one KeychainService instance can be
    /// retrieved by another instance (tests actual Keychain persistence).
    func testKeychainItem_PersistsAcrossInstances() throws {
        let testData = "Persistent data".data(using: .utf8)!
        try keychainService.save(testData, forKey: "test.key")

        // Create new instance
        let newService = KeychainService()
        let loaded = try newService.load(forKey: "test.key")

        XCTAssertEqual(testData, loaded, "Data should persist across service instances")
    }

    // MARK: - Edge Case Tests

    /// Test saving empty data
    ///
    /// Verifies that empty Data() can be stored and retrieved correctly.
    func testSave_EmptyData_Succeeds() throws {
        let emptyData = Data()
        try keychainService.save(emptyData, forKey: "test.key.empty")

        let loaded = try keychainService.load(forKey: "test.key.empty")
        XCTAssertNotNil(loaded, "Should load empty data")
        XCTAssertEqual(emptyData, loaded, "Empty data should be stored correctly")
    }

    /// Test saving large data (1MB)
    ///
    /// Verifies that Keychain can handle larger data items (up to practical limits).
    /// Note: Keychain has practical limits around 1MB, though exact limit varies.
    func testSave_LargeData_Succeeds() throws {
        let largeData = Data(repeating: 0x42, count: 1_000_000) // 1MB
        try keychainService.save(largeData, forKey: "test.key.large")

        let loaded = try keychainService.load(forKey: "test.key.large")
        XCTAssertNotNil(loaded, "Should load large data")
        XCTAssertEqual(largeData.count, loaded?.count, "Large data size should match")
        XCTAssertEqual(largeData, loaded, "Large data should be stored correctly")
    }

    /// Test saving binary data (non-UTF8)
    ///
    /// Verifies that arbitrary binary data can be stored, not just text.
    func testSave_BinaryData_Succeeds() throws {
        var binaryData = Data()
        for byte in UInt8(0)...UInt8(255) {
            binaryData.append(byte)
        }

        try keychainService.save(binaryData, forKey: "test.key")
        let loaded = try keychainService.load(forKey: "test.key")

        XCTAssertEqual(binaryData, loaded, "Binary data should be stored correctly")
    }

    // MARK: - Error Handling Tests

    /// Test that invalid key data throws appropriate error
    ///
    /// Verifies that attempting to load a SymmetricKey from invalid data
    /// (not 32 bytes) throws KeychainError.invalidData.
    func testLoadSymmetricKey_InvalidData_ThrowsError() throws {
        // Save invalid data (not 32 bytes)
        let invalidData = Data(repeating: 0x42, count: 16) // Only 16 bytes
        try keychainService.save(invalidData, forKey: "test.symmetric")

        // Attempt to load as SymmetricKey should throw
        XCTAssertThrowsError(try keychainService.loadSymmetricKey(forKey: "test.symmetric")) { error in
            guard let keychainError = error as? KeychainError else {
                XCTFail("Error should be KeychainError")
                return
            }
            if case .invalidData = keychainError {
                // Expected error
            } else {
                XCTFail("Error should be .invalidData")
            }
        }
    }

    /// Test that corrupted DeviceState JSON throws decoding error
    ///
    /// Verifies that attempting to load corrupted JSON as DeviceState
    /// throws KeychainError.decodingFailed.
    func testLoadDeviceState_CorruptedJSON_ThrowsError() throws {
        // Save invalid JSON
        let invalidJSON = "not valid json".data(using: .utf8)!
        try keychainService.save(invalidJSON, forKey: "rial.device.state")

        // Attempt to load as DeviceState should throw
        XCTAssertThrowsError(try keychainService.loadDeviceState()) { error in
            guard let keychainError = error as? KeychainError else {
                XCTFail("Error should be KeychainError")
                return
            }
            if case .decodingFailed = keychainError {
                // Expected error
            } else {
                XCTFail("Error should be .decodingFailed")
            }
        }
    }

    // MARK: - Integration Tests

    /// Test complete workflow: generate key, encrypt, store, load, decrypt
    ///
    /// Verifies the complete integration between KeychainService and CryptoService
    /// for a real-world use case (encrypting data with a stored key).
    func testIntegration_EncryptStoreLoadDecrypt() throws {
        // Generate and store key
        let key = CryptoService.generateKey()
        try keychainService.saveSymmetricKey(key, forKey: "test.symmetric")

        // Encrypt some data
        let originalData = "Sensitive data to encrypt".data(using: .utf8)!
        let encrypted = try CryptoService.encrypt(originalData, using: key)

        // Simulate app restart - load key from Keychain
        guard let loadedKey = try keychainService.loadSymmetricKey(forKey: "test.symmetric") else {
            XCTFail("Failed to load key")
            return
        }

        // Decrypt with loaded key
        let decrypted = try CryptoService.decrypt(encrypted, using: loadedKey)

        XCTAssertEqual(originalData, decrypted, "Complete workflow should preserve data")
    }

    /// Test DeviceState update workflow
    ///
    /// Verifies that DeviceState can be updated from unregistered to registered state.
    func testIntegration_DeviceStateUpdate() throws {
        // Initial state: unregistered
        let unregisteredState = DeviceState(
            deviceId: UUID().uuidString,
            attestationKeyId: nil,
            isRegistered: false,
            registeredAt: nil
        )

        try keychainService.saveDeviceState(unregisteredState)

        // Verify unregistered state
        var loadedState = try keychainService.loadDeviceState()
        XCTAssertNotNil(loadedState)
        XCTAssertFalse(loadedState!.isRegistered)

        // Update to registered state
        let registeredState = DeviceState(
            deviceId: unregisteredState.deviceId,  // Same device ID
            attestationKeyId: "key-abc-123",
            isRegistered: true,
            registeredAt: Date()
        )

        try keychainService.saveDeviceState(registeredState)

        // Verify registered state
        loadedState = try keychainService.loadDeviceState()
        XCTAssertNotNil(loadedState)
        XCTAssertTrue(loadedState!.isRegistered)
        XCTAssertEqual("key-abc-123", loadedState!.attestationKeyId)
    }

    // MARK: - Performance Tests

    /// Test save operation performance
    ///
    /// Verifies that save operations complete within acceptable time limits.
    func testPerformance_Save() throws {
        let testData = "Performance test data".data(using: .utf8)!

        measure {
            try? keychainService.save(testData, forKey: "test.key")
        }
    }

    /// Test load operation performance
    ///
    /// Verifies that load operations complete within acceptable time limits.
    func testPerformance_Load() throws {
        let testData = "Performance test data".data(using: .utf8)!
        try keychainService.save(testData, forKey: "test.key")

        measure {
            _ = try? keychainService.load(forKey: "test.key")
        }
    }

    /// Test SymmetricKey round-trip performance
    ///
    /// Verifies that key serialization/deserialization is fast enough for
    /// frequent operations.
    func testPerformance_SymmetricKeyRoundTrip() throws {
        let key = CryptoService.generateKey()

        measure {
            try? keychainService.saveSymmetricKey(key, forKey: "test.symmetric")
            _ = try? keychainService.loadSymmetricKey(forKey: "test.symmetric")
        }
    }
}
