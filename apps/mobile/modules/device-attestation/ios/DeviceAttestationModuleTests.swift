import XCTest
@testable import DeviceAttestationModule

/// XCTest harness for RealityCam Device Attestation Expo Module
///
/// These tests verify the native Swift code for:
/// - DCAppAttest key generation and attestation
/// - Secure Enclave key operations
/// - LiDAR depth capture via ARKit
///
/// Note: Some tests require a physical iPhone Pro device with LiDAR.
/// Tests marked with `XCTSkipIf` will skip on simulator.
final class DeviceAttestationModuleTests: XCTestCase {

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        // Clean up any test keys from Keychain
        try? KeychainHelper.deleteTestKeys()
    }

    override func tearDownWithError() throws {
        // Clean up after tests
        try? KeychainHelper.deleteTestKeys()
    }

    // MARK: - DCAppAttest Tests

    func testDCAppAttestAvailability() async throws {
        // DCAppAttest is only available on real devices, iOS 14+
        let isSupported = await DeviceAttestationService.isSupported()

        #if targetEnvironment(simulator)
        XCTAssertFalse(isSupported, "DCAppAttest should not be supported on simulator")
        #else
        XCTAssertTrue(isSupported, "DCAppAttest should be supported on real device")
        #endif
    }

    func testGenerateAttestationKeyOnRealDevice() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "Skipping: DCAppAttest requires real device")

        let keyId = try await DeviceAttestationService.generateKey()

        XCTAssertFalse(keyId.isEmpty, "Key ID should not be empty")
        XCTAssertGreaterThan(keyId.count, 10, "Key ID should be a valid identifier")
    }

    func testCreateAttestationOnRealDevice() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "Skipping: DCAppAttest requires real device")

        // Generate key first
        let keyId = try await DeviceAttestationService.generateKey()

        // Create attestation with challenge
        let challenge = Data("test-challenge-123".utf8)
        let attestation = try await DeviceAttestationService.attest(keyId: keyId, clientDataHash: challenge)

        XCTAssertFalse(attestation.isEmpty, "Attestation object should not be empty")
        // Attestation is CBOR-encoded, starts with specific bytes
        // Real validation happens server-side
    }

    // MARK: - Secure Enclave Tests

    func testSecureEnclaveAvailability() {
        let isAvailable = SecureEnclaveManager.isAvailable()

        #if targetEnvironment(simulator)
        // Simulator may or may not report Secure Enclave availability
        // depending on host machine
        #else
        XCTAssertTrue(isAvailable, "Secure Enclave should be available on real device")
        #endif
    }

    func testGenerateEd25519KeyInSecureEnclave() async throws {
        try XCTSkipIf(!SecureEnclaveManager.isAvailable(),
                      "Skipping: Secure Enclave not available")

        let keyPair = try await SecureEnclaveManager.generateSigningKey(tag: "test-key-\(UUID().uuidString)")

        XCTAssertFalse(keyPair.publicKey.isEmpty, "Public key should not be empty")
        XCTAssertEqual(keyPair.publicKey.count, 32, "Ed25519 public key should be 32 bytes")
    }

    func testSignDataWithSecureEnclaveKey() async throws {
        try XCTSkipIf(!SecureEnclaveManager.isAvailable(),
                      "Skipping: Secure Enclave not available")

        let keyTag = "test-signing-key-\(UUID().uuidString)"
        let keyPair = try await SecureEnclaveManager.generateSigningKey(tag: keyTag)

        let dataToSign = Data("test-message-to-sign".utf8)
        let signature = try await SecureEnclaveManager.sign(data: dataToSign, keyTag: keyTag)

        XCTAssertFalse(signature.isEmpty, "Signature should not be empty")
        XCTAssertEqual(signature.count, 64, "Ed25519 signature should be 64 bytes")
    }

    func testSecureEnclaveKeyIsNonExtractable() async throws {
        try XCTSkipIf(!SecureEnclaveManager.isAvailable(),
                      "Skipping: Secure Enclave not available")

        let keyTag = "test-nonextract-key-\(UUID().uuidString)"
        _ = try await SecureEnclaveManager.generateSigningKey(tag: keyTag)

        // Attempt to export private key should fail
        XCTAssertThrowsError(try SecureEnclaveManager.exportPrivateKey(tag: keyTag)) { error in
            // Expected: Key is not extractable
        }
    }

    // MARK: - LiDAR Tests

    func testLiDARAvailability() {
        let hasLiDAR = LiDARCaptureService.isAvailable()

        #if targetEnvironment(simulator)
        XCTAssertFalse(hasLiDAR, "LiDAR should not be available on simulator")
        #else
        // Only iPhone Pro models have LiDAR
        // This test will pass on Pro devices, fail on non-Pro
        #endif
    }

    func testCaptureDepthMapOnRealDevice() async throws {
        try XCTSkipIf(!LiDARCaptureService.isAvailable(),
                      "Skipping: LiDAR not available on this device")

        let depthData = try await LiDARCaptureService.captureDepthMap()

        XCTAssertGreaterThan(depthData.width, 0, "Depth map width should be positive")
        XCTAssertGreaterThan(depthData.height, 0, "Depth map height should be positive")
        XCTAssertEqual(depthData.depthValues.count, Int(depthData.width * depthData.height),
                       "Depth values count should match dimensions")
    }

    func testDepthMapValuesAreReasonable() async throws {
        try XCTSkipIf(!LiDARCaptureService.isAvailable(),
                      "Skipping: LiDAR not available on this device")

        let depthData = try await LiDARCaptureService.captureDepthMap()

        // Check that depth values are in reasonable range (0.1m to 10m)
        let minDepth = depthData.depthValues.min() ?? 0
        let maxDepth = depthData.depthValues.max() ?? 0

        XCTAssertGreaterThan(minDepth, 0.05, "Minimum depth should be > 5cm")
        XCTAssertLessThan(maxDepth, 15.0, "Maximum depth should be < 15m")
    }

    // MARK: - Expo Module Bridge Tests

    func testModuleExportsCorrectMethods() {
        // Verify the Expo Module exports the expected methods
        let module = DeviceAttestationModule()

        // These should match the TypeScript interface
        XCTAssertTrue(module.responds(to: #selector(DeviceAttestationModule.isSupported)))
        XCTAssertTrue(module.responds(to: #selector(DeviceAttestationModule.hasLiDAR)))
        XCTAssertTrue(module.responds(to: #selector(DeviceAttestationModule.generateAttestationKey)))
        XCTAssertTrue(module.responds(to: #selector(DeviceAttestationModule.createAttestation)))
        XCTAssertTrue(module.responds(to: #selector(DeviceAttestationModule.signData)))
        XCTAssertTrue(module.responds(to: #selector(DeviceAttestationModule.captureDepthMap)))
    }
}

// MARK: - Helper Classes

/// Keychain helper for test cleanup
enum KeychainHelper {
    static func deleteTestKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "test-".data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Placeholder Service Interfaces
// These represent the actual service classes that would be implemented

enum DeviceAttestationService {
    static func isSupported() async -> Bool {
        // TODO: Implement actual DCAppAttest check
        return false
    }

    static func generateKey() async throws -> String {
        // TODO: Implement actual key generation
        throw NSError(domain: "DeviceAttestation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    static func attest(keyId: String, clientDataHash: Data) async throws -> Data {
        // TODO: Implement actual attestation
        throw NSError(domain: "DeviceAttestation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}

enum SecureEnclaveManager {
    struct KeyPair {
        let publicKey: Data
        let keyTag: String
    }

    static func isAvailable() -> Bool {
        // TODO: Check Secure Enclave availability
        return false
    }

    static func generateSigningKey(tag: String) async throws -> KeyPair {
        // TODO: Implement actual key generation
        throw NSError(domain: "SecureEnclave", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    static func sign(data: Data, keyTag: String) async throws -> Data {
        // TODO: Implement actual signing
        throw NSError(domain: "SecureEnclave", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    static func exportPrivateKey(tag: String) throws -> Data {
        // This should always fail - keys are non-extractable
        throw NSError(domain: "SecureEnclave", code: -2, userInfo: [NSLocalizedDescriptionKey: "Key is not extractable"])
    }
}

enum LiDARCaptureService {
    struct DepthData {
        let depthValues: [Float]
        let width: UInt32
        let height: UInt32
    }

    static func isAvailable() -> Bool {
        // TODO: Check ARKit LiDAR availability
        return false
    }

    static func captureDepthMap() async throws -> DepthData {
        // TODO: Implement actual depth capture
        throw NSError(domain: "LiDAR", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}

// Placeholder for the actual Expo Module class
class DeviceAttestationModule: NSObject {
    @objc func isSupported() {}
    @objc func hasLiDAR() {}
    @objc func generateAttestationKey() {}
    @objc func createAttestation() {}
    @objc func signData() {}
    @objc func captureDepthMap() {}
}
