import Foundation
import Security
import CryptoKit
import os.log

/// Service for secure storage of sensitive data in iOS Keychain
///
/// Provides hardware-backed secure storage using Apple's Keychain Services API.
/// All items are scoped to the app identifier and protected with device-only
/// accessibility attributes (no iCloud sync).
///
/// ## Features
/// - Basic CRUD operations for arbitrary Data
/// - SymmetricKey storage with CryptoService integration
/// - DeviceState JSON storage for device registration
/// - Secure Enclave key management (hardware-backed, non-extractable)
/// - Comprehensive error handling with LocalizedError conformance
///
/// ## Security Attributes
/// - Default accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// - No iCloud sync: `kSecAttrSynchronizable = false`
/// - Service identifier: "app.rial.keychain"
///
/// ## Example Usage
/// ```swift
/// let keychain = KeychainService()
///
/// // Store data
/// let data = "Secret".data(using: .utf8)!
/// try keychain.save(data, forKey: "test.key")
///
/// // Retrieve data
/// if let loaded = try keychain.load(forKey: "test.key") {
///     print("Loaded: \(String(data: loaded, encoding: .utf8)!)")
/// }
///
/// // Store SymmetricKey
/// let key = CryptoService.generateKey()
/// try keychain.saveSymmetricKey(key, forKey: "rial.encryption.key")
///
/// // Load and use key
/// if let storedKey = try keychain.loadSymmetricKey(forKey: "rial.encryption.key") {
///     let encrypted = try CryptoService.encrypt(data, using: storedKey)
/// }
/// ```
class KeychainService {
    private static let logger = Logger(subsystem: "app.rial", category: "keychain")

    /// Service identifier for all Keychain items
    private let service = "app.rial.keychain"

    /// Default accessibility level for stored items
    private let defaultAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    // MARK: - Basic Operations

    /// Save data to Keychain
    ///
    /// If an item with the same key already exists, it will be updated automatically.
    /// Data is stored with `AfterFirstUnlockThisDeviceOnly` accessibility and no
    /// iCloud sync.
    ///
    /// - Parameters:
    ///   - data: Data to store
    ///   - key: Unique identifier for this item
    /// - Throws: `KeychainError.saveFailed` if save operation fails
    ///
    /// ## Example
    /// ```swift
    /// let data = "Hello, Keychain!".data(using: .utf8)!
    /// try keychainService.save(data, forKey: "test.key")
    /// ```
    func save(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: defaultAccessibility,
            kSecAttrSynchronizable as String: false
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update instead
            try update(data, forKey: key)
        } else if status != errSecSuccess {
            Self.logger.error("Keychain save failed for key '\(key, privacy: .public)': \(status)")
            throw KeychainError.saveFailed(status)
        }

        Self.logger.debug("Saved \(data.count) bytes to Keychain for key '\(key, privacy: .public)'")
    }

    /// Load data from Keychain
    ///
    /// Returns `nil` if the item doesn't exist (not an error condition).
    /// Throws only for unexpected Keychain errors.
    ///
    /// - Parameter key: Unique identifier for the item
    /// - Returns: Stored data, or `nil` if not found
    /// - Throws: `KeychainError.loadFailed` if load operation fails (excluding item not found)
    /// - Throws: `KeychainError.invalidData` if stored item is not Data
    ///
    /// ## Example
    /// ```swift
    /// if let data = try keychainService.load(forKey: "test.key") {
    ///     print("Found: \(data.count) bytes")
    /// } else {
    ///     print("Item not found")
    /// }
    /// ```
    func load(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            Self.logger.debug("Item not found for key '\(key, privacy: .public)'")
            return nil
        }

        guard status == errSecSuccess else {
            Self.logger.error("Keychain load failed for key '\(key, privacy: .public)': \(status)")
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data else {
            Self.logger.error("Keychain item for '\(key, privacy: .public)' is not Data")
            throw KeychainError.invalidData
        }

        Self.logger.debug("Loaded \(data.count) bytes from Keychain for key '\(key, privacy: .public)'")
        return data
    }

    /// Update existing Keychain item
    ///
    /// Internal helper method called by `save(_:forKey:)` when an item already exists.
    ///
    /// - Parameters:
    ///   - data: New data to store
    ///   - key: Unique identifier for the item
    /// - Throws: `KeychainError.saveFailed` if update operation fails
    private func update(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service
        ]

        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        guard status == errSecSuccess else {
            Self.logger.error("Keychain update failed for key '\(key, privacy: .public)': \(status)")
            throw KeychainError.saveFailed(status)
        }

        Self.logger.debug("Updated Keychain item for key '\(key, privacy: .public)'")
    }

    /// Delete item from Keychain
    ///
    /// Succeeds silently if the item doesn't exist (idempotent operation).
    ///
    /// - Parameter key: Unique identifier for the item
    /// - Throws: `KeychainError.deleteFailed` if delete operation fails (excluding item not found)
    ///
    /// ## Example
    /// ```swift
    /// try keychainService.delete(forKey: "test.key")
    /// // Safe to call multiple times - won't error if already deleted
    /// ```
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Succeed silently if item doesn't exist
        if status == errSecItemNotFound {
            Self.logger.debug("Delete called for non-existent key '\(key, privacy: .public)'")
            return
        }

        guard status == errSecSuccess else {
            Self.logger.error("Keychain delete failed for key '\(key, privacy: .public)': \(status)")
            throw KeychainError.deleteFailed(status)
        }

        Self.logger.debug("Deleted Keychain item for key '\(key, privacy: .public)'")
    }

    // MARK: - SymmetricKey Operations

    /// Save SymmetricKey to Keychain
    ///
    /// Uses `CryptoService.keyToData()` to serialize the key before storage.
    /// The key can be retrieved and used for encryption/decryption immediately.
    ///
    /// - Parameters:
    ///   - key: CryptoKit SymmetricKey to store (typically 256-bit AES key)
    ///   - keyName: Unique identifier for this key
    /// - Throws: `KeychainError.saveFailed` if save operation fails
    ///
    /// ## Example
    /// ```swift
    /// let key = CryptoService.generateKey()
    /// try keychainService.saveSymmetricKey(key, forKey: "rial.encryption.key")
    /// ```
    ///
    /// ## Security Notes
    /// - Keys are stored with device-only accessibility
    /// - Keys are never synchronized to iCloud
    /// - Use for offline capture encryption (Story 6.10)
    func saveSymmetricKey(_ key: SymmetricKey, forKey keyName: String) throws {
        let keyData = CryptoService.keyToData(key)
        try save(keyData, forKey: keyName)
        Self.logger.info("Saved SymmetricKey to Keychain: '\(keyName, privacy: .public)'")
    }

    /// Load SymmetricKey from Keychain
    ///
    /// Uses `CryptoService.keyFromData()` to reconstruct the key from stored data.
    /// Returns `nil` if the key doesn't exist (not an error).
    ///
    /// - Parameter keyName: Unique identifier for the key
    /// - Returns: CryptoKit SymmetricKey, or `nil` if not found
    /// - Throws: `KeychainError.invalidData` if stored data is not a valid 32-byte key
    ///
    /// ## Example
    /// ```swift
    /// guard let key = try keychainService.loadSymmetricKey(forKey: "rial.encryption.key") else {
    ///     throw CaptureError.encryptionKeyNotFound
    /// }
    /// let encrypted = try CryptoService.encrypt(captureData, using: key)
    /// ```
    func loadSymmetricKey(forKey keyName: String) throws -> SymmetricKey? {
        guard let keyData = try load(forKey: keyName) else {
            return nil
        }

        do {
            let key = try CryptoService.keyFromData(keyData)
            Self.logger.info("Loaded SymmetricKey from Keychain: '\(keyName, privacy: .public)'")
            return key
        } catch {
            Self.logger.error("Failed to deserialize SymmetricKey: \(error.localizedDescription)")
            throw KeychainError.invalidData
        }
    }

    // MARK: - Device State Operations

    /// Key prefix for device state storage
    private static let deviceStateKeyPrefix = "rial.device.state"

    /// Generate environment-specific key for device state.
    ///
    /// Device registrations are per-backend, so we key by API host.
    /// This allows seamless switching between local/production without
    /// losing registrations or conflicting device IDs.
    ///
    /// - Parameter apiBaseURL: The API base URL to derive the key from
    /// - Returns: Keychain key like "rial.device.state.localhost" or "rial.device.state.rial-api.fly.dev"
    private func deviceStateKey(for apiBaseURL: URL) -> String {
        let host = apiBaseURL.host ?? "unknown"
        return "\(Self.deviceStateKeyPrefix).\(host)"
    }

    /// Save device state to Keychain for a specific API environment.
    ///
    /// Encodes `DeviceState` to JSON and stores it with an environment-specific key.
    /// Each backend (localhost, production, etc.) gets its own device registration.
    ///
    /// - Parameters:
    ///   - state: DeviceState to store
    ///   - apiBaseURL: The API base URL this registration is for
    /// - Throws: `KeychainError.encodingFailed` if JSON encoding fails
    /// - Throws: `KeychainError.saveFailed` if save operation fails
    func saveDeviceState(_ state: DeviceState, for apiBaseURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let key = deviceStateKey(for: apiBaseURL)

        do {
            let data = try encoder.encode(state)
            try save(data, forKey: key)
            Self.logger.info("Saved DeviceState to Keychain for \(apiBaseURL.host ?? "unknown")")
        } catch is EncodingError {
            Self.logger.error("Failed to encode DeviceState")
            throw KeychainError.encodingFailed
        }
    }

    /// Load device state from Keychain for a specific API environment.
    ///
    /// Retrieves and decodes `DeviceState` for the given API base URL.
    /// Returns `nil` if no device state exists for this environment.
    ///
    /// - Parameter apiBaseURL: The API base URL to load registration for
    /// - Returns: DeviceState, or `nil` if not found
    /// - Throws: `KeychainError.decodingFailed` if JSON decoding fails
    func loadDeviceState(for apiBaseURL: URL) throws -> DeviceState? {
        let key = deviceStateKey(for: apiBaseURL)
        guard let data = try load(forKey: key) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let state = try decoder.decode(DeviceState.self, from: data)
            Self.logger.info("Loaded DeviceState from Keychain for \(apiBaseURL.host ?? "unknown")")
            return state
        } catch {
            Self.logger.error("Failed to decode DeviceState: \(error.localizedDescription)")
            throw KeychainError.decodingFailed
        }
    }

    /// Delete device state for a specific API environment.
    ///
    /// Removes the device registration for the given API base URL.
    /// Used when resetting registration or switching environments.
    ///
    /// - Parameter apiBaseURL: The API base URL to delete registration for
    /// - Throws: `KeychainError.deleteFailed` if delete operation fails
    func deleteDeviceState(for apiBaseURL: URL) throws {
        let key = deviceStateKey(for: apiBaseURL)
        try delete(forKey: key)
        Self.logger.info("Deleted DeviceState from Keychain for \(apiBaseURL.host ?? "unknown")")
    }

    // MARK: - Legacy Device State Operations (deprecated)

    /// Save device state to Keychain (legacy, environment-agnostic).
    ///
    /// - Note: Prefer `saveDeviceState(_:for:)` for new code.
    @available(*, deprecated, message: "Use saveDeviceState(_:for:) instead")
    func saveDeviceState(_ state: DeviceState) throws {
        try saveDeviceState(state, for: AppEnvironment.apiBaseURL)
    }

    /// Load device state from Keychain (legacy, environment-agnostic).
    ///
    /// - Note: Prefer `loadDeviceState(for:)` for new code.
    @available(*, deprecated, message: "Use loadDeviceState(for:) instead")
    func loadDeviceState() throws -> DeviceState? {
        // First try current environment
        if let state = try loadDeviceState(for: AppEnvironment.apiBaseURL) {
            return state
        }
        // Fall back to legacy key for migration
        guard let data = try load(forKey: Self.deviceStateKeyPrefix) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let state = try decoder.decode(DeviceState.self, from: data)
            Self.logger.info("Loaded DeviceState from legacy Keychain key")
            return state
        } catch {
            Self.logger.error("Failed to decode DeviceState: \(error.localizedDescription)")
            throw KeychainError.decodingFailed
        }
    }

    // MARK: - Secure Enclave Key Operations

    /// Create a Secure Enclave key
    ///
    /// Generates a P-256 elliptic curve key in the Secure Enclave. Keys are
    /// hardware-bound and non-extractable, providing maximum security for
    /// cryptographic operations.
    ///
    /// - Parameter tag: Unique tag for the key
    /// - Returns: SecKey reference to the created key
    /// - Throws: `KeychainError.secureEnclaveUnavailable` if Secure Enclave is not available
    /// - Throws: `KeychainError.saveFailed` if key creation fails
    ///
    /// ## Note
    /// Requires physical device with Secure Enclave. Simulator has limited support.
    ///
    /// ## Example
    /// ```swift
    /// // Story 6.2 will use this for attestation keys
    /// let attestationKey = try keychainService.createSecureEnclaveKey(forKey: "rial.attestation.key")
    /// ```
    func createSecureEnclaveKey(forKey tag: String) throws -> SecKey {
        let tagData = tag.data(using: .utf8)!

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
                kSecAttrAccessControl as String: try secureEnclaveAccessControl()
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let err = error!.takeRetainedValue() as Error
            Self.logger.error("Failed to create Secure Enclave key: \(err.localizedDescription)")

            // Check if Secure Enclave is unavailable (common in simulator)
            let nsError = err as NSError
            if nsError.domain == NSOSStatusErrorDomain && nsError.code == Int(errSecUnimplemented) {
                throw KeychainError.secureEnclaveUnavailable
            }

            throw KeychainError.saveFailed(OSStatus(nsError.code))
        }

        Self.logger.info("Created Secure Enclave key with tag '\(tag, privacy: .public)'")
        return privateKey
    }

    /// Load an existing Secure Enclave key
    ///
    /// Retrieves a previously created Secure Enclave key by its tag.
    /// Returns `nil` if the key doesn't exist (not an error).
    ///
    /// - Parameter tag: Unique tag for the key
    /// - Returns: SecKey reference, or `nil` if not found
    /// - Throws: `KeychainError.loadFailed` if load operation fails
    ///
    /// ## Example
    /// ```swift
    /// if let key = try keychainService.loadSecureEnclaveKey(forKey: "rial.attestation.key") {
    ///     // Use key for signing operations
    /// }
    /// ```
    func loadSecureEnclaveKey(forKey tag: String) throws -> SecKey? {
        let tagData = tag.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            Self.logger.debug("Secure Enclave key not found for tag '\(tag, privacy: .public)'")
            return nil
        }

        guard status == errSecSuccess else {
            Self.logger.error("Failed to load Secure Enclave key: \(status)")
            throw KeychainError.loadFailed(status)
        }

        guard let key = result else {
            throw KeychainError.invalidData
        }

        Self.logger.info("Loaded Secure Enclave key with tag '\(tag, privacy: .public)'")
        return (key as! SecKey)
    }

    /// Delete a Secure Enclave key
    ///
    /// Removes a Secure Enclave key from the Keychain. Succeeds silently if
    /// the key doesn't exist (idempotent operation).
    ///
    /// - Parameter tag: Unique tag for the key
    /// - Throws: `KeychainError.deleteFailed` if delete operation fails
    ///
    /// ## Example
    /// ```swift
    /// try keychainService.deleteSecureEnclaveKey(forKey: "rial.attestation.key")
    /// ```
    func deleteSecureEnclaveKey(forKey tag: String) throws {
        let tagData = tag.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecItemNotFound {
            Self.logger.debug("Delete called for non-existent Secure Enclave key '\(tag, privacy: .public)'")
            return
        }

        guard status == errSecSuccess else {
            Self.logger.error("Failed to delete Secure Enclave key: \(status)")
            throw KeychainError.deleteFailed(status)
        }

        Self.logger.info("Deleted Secure Enclave key with tag '\(tag, privacy: .public)'")
    }

    /// Create access control for Secure Enclave keys
    ///
    /// Internal helper to configure access control attributes for Secure Enclave keys.
    /// Uses `privateKeyUsage` flag to allow cryptographic operations.
    ///
    /// - Returns: SecAccessControl instance
    /// - Throws: `KeychainError.saveFailed` if access control creation fails
    private func secureEnclaveAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .privateKeyUsage,
            &error
        ) else {
            let err = error!.takeRetainedValue() as Error
            let nsError = err as NSError
            Self.logger.error("Failed to create access control: \(err.localizedDescription)")
            throw KeychainError.saveFailed(OSStatus(nsError.code))
        }
        return accessControl
    }
}

// MARK: - Error Types

/// Errors that can occur during Keychain operations
enum KeychainError: Error, LocalizedError {
    /// Item could not be saved to Keychain
    case saveFailed(OSStatus)

    /// Item could not be retrieved from Keychain
    case loadFailed(OSStatus)

    /// Item could not be deleted from Keychain
    case deleteFailed(OSStatus)

    /// Keychain item was not found (informational, typically not thrown)
    case itemNotFound

    /// Attempted to save item that already exists (handled automatically)
    case duplicateItem

    /// Keychain data is invalid or corrupted
    case invalidData

    /// JSON encoding failed
    case encodingFailed

    /// JSON decoding failed
    case decodingFailed

    /// Secure Enclave is not available (simulator or unsupported device)
    case secureEnclaveUnavailable

    /// Unexpected Keychain error
    case unexpectedError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save item to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load item from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete item from Keychain (status: \(status))"
        case .itemNotFound:
            return "Keychain item not found"
        case .duplicateItem:
            return "Keychain item already exists"
        case .invalidData:
            return "Keychain data is invalid or corrupted"
        case .encodingFailed:
            return "Failed to encode data for Keychain storage"
        case .decodingFailed:
            return "Failed to decode data from Keychain storage"
        case .secureEnclaveUnavailable:
            return "Secure Enclave is not available on this device"
        case .unexpectedError(let status):
            return "Unexpected Keychain error (status: \(status))"
        }
    }
}

// MARK: - Data Models

/// Device state persisted in Keychain after registration
///
/// Stores device registration information including attestation key ID and
/// registration status. Used by Story 6.2 (DCAppAttest) to track device state.
///
/// ## Example
/// ```swift
/// let state = DeviceState(
///     deviceId: "abc-123-def",
///     attestationKeyId: "key-xyz",
///     isRegistered: true,
///     registeredAt: Date()
/// )
/// try keychainService.saveDeviceState(state)
/// ```
struct DeviceState: Codable {
    /// Unique device identifier (UUID string)
    let deviceId: String

    /// DCAppAttest key identifier (optional until registration completes)
    let attestationKeyId: String?

    /// Whether device has completed registration with backend
    let isRegistered: Bool

    /// Timestamp of successful registration (optional until registered)
    let registeredAt: Date?
}
