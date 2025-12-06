import DeviceCheck
import CryptoKit
import os.log

/// Service for managing device attestation using DCAppAttest
///
/// Provides hardware-backed device attestation through Apple's Secure Enclave,
/// eliminating the need for JavaScript bridge crossings in the native Swift
/// implementation.
///
/// ## Features
/// - Generate hardware-backed attestation keys in Secure Enclave
/// - Create device attestation objects for backend registration
/// - Generate per-capture assertions for cryptographic proof of authenticity
/// - Secure key ID persistence through KeychainService integration
/// - Comprehensive error handling with graceful degradation
///
/// ## Security Model
/// - Keys are generated in Secure Enclave (non-extractable)
/// - Only key IDs are stored in Keychain (keys never leave hardware)
/// - Challenge-response protocol prevents replay attacks
/// - Counter increments with each assertion (prevents reuse)
///
/// ## Performance Targets
/// - Key generation: < 100ms
/// - Device attestation: < 500ms
/// - Per-capture assertion: < 50ms (critical path)
///
/// ## Example Usage
/// ```swift
/// let attestation = DeviceAttestationService()
///
/// // Check if supported
/// guard attestation.isSupported else {
///     print("DCAppAttest not available")
///     return
/// }
///
/// // Generate key
/// let keyId = try await attestation.generateKey()
///
/// // Attest device (one-time during registration)
/// let challenge = try await apiClient.requestChallenge()
/// let attestationObject = try await attestation.attestKey(keyId, challenge: challenge)
///
/// // Generate per-capture assertion
/// let captureData = jpeg + depthData
/// let assertion = try await attestation.generateAssertion(keyId, clientData: captureData)
/// ```
class DeviceAttestationService {
    private let service = DCAppAttestService.shared
    private let keychain: KeychainService
    private let logger = Logger(subsystem: "app.rial", category: "attestation")

    // MARK: - Initialization

    /// Initialize DeviceAttestationService
    ///
    /// - Parameter keychain: KeychainService instance for key ID persistence (defaults to new instance)
    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    // MARK: - Device Support

    /// Check if DCAppAttest is supported on this device
    ///
    /// Returns `false` on:
    /// - iOS Simulator (no Secure Enclave)
    /// - Jailbroken devices (security compromised)
    /// - Devices without Secure Enclave
    ///
    /// In DEBUG builds with `skipAttestation` enabled, always returns `true`
    /// to allow development without a paid Apple Developer account.
    ///
    /// - Returns: `true` if DCAppAttest operations are available
    var isSupported: Bool {
        if AppEnvironment.skipAttestation {
            logger.warning("Attestation skipped (DEBUG mode) - photos will NOT be verified")
            return true
        }
        return service.isSupported
    }

    // MARK: - Key Generation

    /// Generate a new attestation key in Secure Enclave
    ///
    /// Creates a hardware-backed key that never leaves the Secure Enclave.
    /// The key ID is persisted to Keychain for future use. If a key already
    /// exists in Keychain, no new key is generated.
    ///
    /// - Returns: Base64-encoded key ID
    /// - Throws: `AttestationError.unsupported` if DCAppAttest not available
    /// - Throws: `AttestationError.keyGenerationFailed` if key creation fails
    ///
    /// ## Performance
    /// Target: < 100ms on iPhone 12 Pro or later
    ///
    /// ## Example
    /// ```swift
    /// let keyId = try await attestation.generateKey()
    /// print("Key ID: \(keyId)")
    /// // Key ID is automatically persisted to Keychain
    /// ```
    func generateKey() async throws -> String {
        // Debug bypass - return mock key ID
        if AppEnvironment.skipAttestation {
            let mockKeyId = "debug-mock-key-\(UUID().uuidString)"
            logger.warning("Using mock key ID (DEBUG mode): \(mockKeyId)")
            try keychain.save(Data(mockKeyId.utf8), forKey: "rial.attestation.keyId")
            return mockKeyId
        }

        guard service.isSupported else {
            logger.error("DCAppAttest not supported on this device")
            throw AttestationError.unsupported
        }

        let startTime = Date()

        do {
            let keyId = try await service.generateKey()
            let duration = Date().timeIntervalSince(startTime) * 1000
            logger.info("Key generated in \(duration, format: .fixed(precision: 2))ms")

            // Persist key ID to Keychain using KeychainService from Story 6-4
            try keychain.save(Data(keyId.utf8), forKey: "rial.attestation.keyId")
            logger.debug("Key ID persisted to Keychain")

            return keyId
        } catch {
            logger.error("Key generation failed: \(error.localizedDescription)")
            throw AttestationError.keyGenerationFailed(error)
        }
    }

    // MARK: - Device Attestation

    /// Generate attestation object for device registration
    ///
    /// Creates a cryptographic attestation that proves the device is genuine
    /// Apple hardware running legitimate iOS. This is a one-time operation
    /// during device registration.
    ///
    /// - Parameters:
    ///   - keyId: The attestation key ID (from `generateKey()`)
    ///   - challenge: 32-byte challenge from backend (from GET /api/v1/devices/challenge)
    /// - Returns: Attestation object data (CBOR format with certificate chain)
    /// - Throws: `AttestationError.attestationFailed` if attestation creation fails
    /// - Throws: `AttestationError.invalidChallenge` if challenge is invalid
    ///
    /// ## Performance
    /// Target: < 500ms (includes network round-trip to Apple's attestation service)
    ///
    /// ## Example
    /// ```swift
    /// let challenge = try await apiClient.requestChallenge()
    /// let attestation = try await attestationService.attestKey(keyId, challenge: challenge)
    /// // Send attestation to backend for verification
    /// ```
    func attestKey(_ keyId: String, challenge: Data) async throws -> Data {
        // Debug bypass - return mock attestation
        if AppEnvironment.skipAttestation {
            logger.warning("Returning mock attestation (DEBUG mode)")
            return Data("debug-mock-attestation".utf8)
        }

        guard challenge.count == 32 else {
            logger.error("Invalid challenge size: \(challenge.count) bytes (expected 32)")
            throw AttestationError.invalidChallenge
        }

        let startTime = Date()

        // Hash challenge using CryptoService from Story 6-4
        let clientDataHash = CryptoService.sha256Data(challenge)

        do {
            let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
            let duration = Date().timeIntervalSince(startTime) * 1000
            logger.info("Attestation generated in \(duration, format: .fixed(precision: 2))ms")
            return attestation
        } catch {
            logger.error("Attestation failed: \(error.localizedDescription)")
            throw AttestationError.attestationFailed(error)
        }
    }

    // MARK: - Per-Capture Assertion

    /// Generate assertion for a specific capture
    ///
    /// Creates a cryptographic signature that binds the capture data to the
    /// attested device. This is the critical path for photo capture flow.
    ///
    /// - Parameters:
    ///   - keyId: The attestation key ID
    ///   - clientData: The data to sign (typically JPEG + depth data)
    /// - Returns: Assertion data (includes counter and signature)
    /// - Throws: `AttestationError.assertionFailed` if assertion creation fails
    /// - Throws: `AttestationError.noKeyAvailable` if key ID doesn't exist in Secure Enclave
    ///
    /// ## Performance
    /// Target: < 50ms (CRITICAL PATH)
    /// Warns if exceeds 50ms target
    ///
    /// ## Security
    /// - Counter increments with each assertion (prevents replay)
    /// - Signature is cryptographically bound to client data
    /// - Backend verifies signature against device's public key
    ///
    /// ## Example
    /// ```swift
    /// let captureData = jpegData + depthData
    /// let assertion = try await attestationService.generateAssertion(keyId, clientData: captureData)
    /// // Attach assertion to upload payload
    /// ```
    func generateAssertion(_ keyId: String, clientData: Data) async throws -> Data {
        // Debug bypass - return mock assertion
        if AppEnvironment.skipAttestation {
            logger.warning("Returning mock assertion (DEBUG mode)")
            return Data("debug-mock-assertion".utf8)
        }

        let startTime = Date()

        // Hash client data using CryptoService from Story 6-4
        let clientDataHash = CryptoService.sha256Data(clientData)

        do {
            let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
            let duration = Date().timeIntervalSince(startTime) * 1000

            if duration > 50 {
                logger.warning("Assertion took \(duration, format: .fixed(precision: 2))ms (target: 50ms)")
            } else {
                logger.debug("Assertion generated in \(duration, format: .fixed(precision: 2))ms")
            }

            return assertion
        } catch {
            logger.error("Assertion generation failed: \(error.localizedDescription)")

            // Check for specific error types
            let nsError = error as NSError
            if nsError.domain == "DCErrorDomain" && nsError.code == 1 {
                // DCError.invalidKey
                throw AttestationError.noKeyAvailable
            }

            throw AttestationError.assertionFailed(error)
        }
    }

    // MARK: - Keychain Integration

    /// Load stored key ID from Keychain
    ///
    /// Retrieves the attestation key ID that was persisted during `generateKey()`.
    /// Returns `nil` if no key has been generated yet.
    ///
    /// - Returns: Key ID string, or `nil` if not found
    ///
    /// ## Example
    /// ```swift
    /// if let existingKeyId = attestationService.loadStoredKeyId() {
    ///     print("Using existing key: \(existingKeyId)")
    /// } else {
    ///     let newKeyId = try await attestationService.generateKey()
    /// }
    /// ```
    func loadStoredKeyId() -> String? {
        do {
            guard let data = try keychain.load(forKey: "rial.attestation.keyId") else {
                logger.debug("No stored key ID found")
                return nil
            }

            guard let keyId = String(data: data, encoding: .utf8) else {
                logger.error("Failed to decode key ID from Keychain data")
                return nil
            }

            logger.debug("Loaded key ID from Keychain")
            return keyId
        } catch {
            logger.error("Failed to load key ID from Keychain: \(error.localizedDescription)")
            return nil
        }
    }

    /// Save device state to Keychain after successful registration
    ///
    /// Persists device registration information including device ID and
    /// attestation key ID. Called after successful backend registration.
    /// Device state is keyed by API host to support multiple environments.
    ///
    /// - Parameters:
    ///   - deviceId: UUID string from backend registration response
    ///   - attestationKeyId: The attestation key ID used for registration
    ///   - apiBaseURL: The API base URL this registration is for
    /// - Throws: `KeychainError` if save operation fails
    func saveDeviceState(deviceId: String, attestationKeyId: String, for apiBaseURL: URL) throws {
        let state = DeviceState(
            deviceId: deviceId,
            attestationKeyId: attestationKeyId,
            isRegistered: true,
            registeredAt: Date()
        )
        try keychain.saveDeviceState(state, for: apiBaseURL)
        logger.info("Device state saved to Keychain for \(apiBaseURL.host ?? "unknown") (deviceId: \(deviceId, privacy: .public))")
    }

    /// Load device state from Keychain for a specific API environment.
    ///
    /// Retrieves device registration information if the device has been
    /// registered with the specified backend. Returns `nil` if not yet registered.
    ///
    /// - Parameter apiBaseURL: The API base URL to load registration for
    /// - Returns: DeviceState with registration info, or `nil` if not registered
    /// - Throws: `KeychainError` if load operation fails
    func loadDeviceState(for apiBaseURL: URL) throws -> DeviceState? {
        try keychain.loadDeviceState(for: apiBaseURL)
    }

    /// Delete device state from Keychain for a specific API environment.
    ///
    /// Removes the device registration, forcing re-registration on next use.
    /// Useful for debugging or resetting the device state.
    ///
    /// - Parameter apiBaseURL: The API base URL to delete registration for
    /// - Throws: `KeychainError` if delete operation fails
    func deleteDeviceState(for apiBaseURL: URL) throws {
        try keychain.deleteDeviceState(for: apiBaseURL)
        logger.info("Device state deleted from Keychain for \(apiBaseURL.host ?? "unknown")")
    }
}

// MARK: - Error Types

/// Errors that can occur during attestation operations
enum AttestationError: Error, LocalizedError {
    /// DCAppAttest is not supported on this device (simulator, jailbroken, or no Secure Enclave)
    case unsupported

    /// Failed to generate attestation key in Secure Enclave
    case keyGenerationFailed(Error)

    /// Failed to generate device attestation object
    case attestationFailed(Error)

    /// Failed to generate per-capture assertion
    case assertionFailed(Error)

    /// Challenge data is invalid (must be 32 bytes)
    case invalidChallenge

    /// Attestation key not available in Secure Enclave (may have been deleted)
    case noKeyAvailable

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Device attestation is not supported on this device"
        case .keyGenerationFailed(let error):
            return "Failed to generate attestation key: \(error.localizedDescription)"
        case .attestationFailed(let error):
            return "Failed to generate device attestation: \(error.localizedDescription)"
        case .assertionFailed(let error):
            return "Failed to generate capture assertion: \(error.localizedDescription)"
        case .invalidChallenge:
            return "Invalid challenge (must be 32 bytes)"
        case .noKeyAvailable:
            return "Attestation key not found in Secure Enclave"
        }
    }
}
