//
//  CaptureEncryption.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Capture-specific encryption using iOS Data Protection.
//

import Foundation
import CryptoKit
import os.log

/// Service for encrypting/decrypting capture data using AES-256-GCM.
///
/// Provides transparent encryption for capture data stored in CoreData.
/// Uses a single encryption key per device, stored securely in Keychain.
///
/// ## Security Model
/// - AES-256-GCM provides authenticated encryption (confidentiality + integrity)
/// - Key stored in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
/// - Key never leaves device (no iCloud sync)
/// - Each encryption operation uses a fresh random nonce
///
/// ## Usage
/// ```swift
/// let encryption = CaptureEncryption(keychain: keychainService)
///
/// // Encrypt capture data
/// let encrypted = try encryption.encryptCapture(jpeg: jpegData, depth: depthData)
///
/// // Decrypt capture data
/// let (jpeg, depth) = try encryption.decryptCapture(jpeg: encrypted.0, depth: encrypted.1)
/// ```
final class CaptureEncryption {
    private static let logger = Logger(subsystem: "app.rial", category: "capture-encryption")

    /// Keychain key for capture encryption key
    private static let encryptionKeyName = "rial.capture.encryption.key"

    /// Keychain service for key storage
    private let keychain: KeychainService

    /// Cached encryption key to avoid repeated Keychain lookups
    private var cachedKey: SymmetricKey?

    // MARK: - Initialization

    /// Creates a new CaptureEncryption instance.
    ///
    /// - Parameter keychain: KeychainService for key storage
    init(keychain: KeychainService) {
        self.keychain = keychain
    }

    // MARK: - Encryption

    /// Encrypt capture data (JPEG + depth).
    ///
    /// - Parameters:
    ///   - jpeg: JPEG photo data
    ///   - depth: Compressed depth map data
    ///   - metadata: Capture metadata (JSON-encoded)
    /// - Returns: Tuple of encrypted (jpeg, depth, metadata)
    /// - Throws: `CaptureEncryptionError` if encryption fails
    func encryptCapture(
        jpeg: Data,
        depth: Data,
        metadata: Data
    ) throws -> (jpeg: Data, depth: Data, metadata: Data) {
        let key = try getOrCreateKey()

        let encryptedJpeg = try CryptoService.encrypt(jpeg, using: key)
        let encryptedDepth = try CryptoService.encrypt(depth, using: key)
        let encryptedMetadata = try CryptoService.encrypt(metadata, using: key)

        Self.logger.debug("""
            Encrypted capture: \
            jpeg=\(jpeg.count)->\(encryptedJpeg.count), \
            depth=\(depth.count)->\(encryptedDepth.count), \
            metadata=\(metadata.count)->\(encryptedMetadata.count)
            """)

        return (encryptedJpeg, encryptedDepth, encryptedMetadata)
    }

    /// Decrypt capture data.
    ///
    /// - Parameters:
    ///   - jpeg: Encrypted JPEG data
    ///   - depth: Encrypted depth data
    ///   - metadata: Encrypted metadata
    /// - Returns: Tuple of decrypted (jpeg, depth, metadata)
    /// - Throws: `CaptureEncryptionError` if decryption fails
    func decryptCapture(
        jpeg: Data,
        depth: Data,
        metadata: Data
    ) throws -> (jpeg: Data, depth: Data, metadata: Data) {
        let key = try getKey()

        let decryptedJpeg = try CryptoService.decrypt(jpeg, using: key)
        let decryptedDepth = try CryptoService.decrypt(depth, using: key)
        let decryptedMetadata = try CryptoService.decrypt(metadata, using: key)

        Self.logger.debug("""
            Decrypted capture: \
            jpeg=\(jpeg.count)->\(decryptedJpeg.count), \
            depth=\(depth.count)->\(decryptedDepth.count), \
            metadata=\(metadata.count)->\(decryptedMetadata.count)
            """)

        return (decryptedJpeg, decryptedDepth, decryptedMetadata)
    }

    /// Encrypt single data blob.
    ///
    /// - Parameter data: Data to encrypt
    /// - Returns: Encrypted data
    func encrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()
        return try CryptoService.encrypt(data, using: key)
    }

    /// Decrypt single data blob.
    ///
    /// - Parameter data: Data to decrypt
    /// - Returns: Decrypted data
    func decrypt(_ data: Data) throws -> Data {
        let key = try getKey()
        return try CryptoService.decrypt(data, using: key)
    }

    /// Encrypt optional data blob.
    ///
    /// - Parameter data: Optional data to encrypt
    /// - Returns: Encrypted data, or nil if input was nil
    func encrypt(optional data: Data?) throws -> Data? {
        guard let data = data else { return nil }
        return try encrypt(data)
    }

    /// Decrypt optional data blob.
    ///
    /// - Parameter data: Optional data to decrypt
    /// - Returns: Decrypted data, or nil if input was nil
    func decrypt(optional data: Data?) throws -> Data? {
        guard let data = data else { return nil }
        return try decrypt(data)
    }

    // MARK: - Key Management

    /// Check if encryption key exists.
    var hasKey: Bool {
        if cachedKey != nil { return true }
        return (try? keychain.loadSymmetricKey(forKey: Self.encryptionKeyName)) != nil
    }

    /// Clear cached key (for testing).
    func clearCache() {
        cachedKey = nil
    }

    /// Delete encryption key (WARNING: all encrypted data becomes unreadable).
    ///
    /// Only call this when deliberately resetting device state.
    func deleteKey() throws {
        try keychain.delete(forKey: Self.encryptionKeyName)
        cachedKey = nil
        Self.logger.warning("Encryption key deleted - encrypted captures are now unrecoverable")
    }

    // MARK: - Private Methods

    /// Get existing key or create new one.
    private func getOrCreateKey() throws -> SymmetricKey {
        // Return cached key
        if let cached = cachedKey {
            return cached
        }

        // Try to load from Keychain
        if let stored = try keychain.loadSymmetricKey(forKey: Self.encryptionKeyName) {
            cachedKey = stored
            Self.logger.debug("Loaded encryption key from Keychain")
            return stored
        }

        // Generate new key
        let newKey = CryptoService.generateKey()
        try keychain.saveSymmetricKey(newKey, forKey: Self.encryptionKeyName)
        cachedKey = newKey
        Self.logger.info("Generated new encryption key and saved to Keychain")
        return newKey
    }

    /// Get existing key (throws if not found).
    private func getKey() throws -> SymmetricKey {
        // Return cached key
        if let cached = cachedKey {
            return cached
        }

        // Load from Keychain
        guard let stored = try keychain.loadSymmetricKey(forKey: Self.encryptionKeyName) else {
            Self.logger.error("Encryption key not found in Keychain")
            throw CaptureEncryptionError.keyNotFound
        }

        cachedKey = stored
        Self.logger.debug("Loaded encryption key from Keychain")
        return stored
    }
}

// MARK: - CaptureEncryptionError

/// Errors that can occur during capture encryption.
enum CaptureEncryptionError: Error, LocalizedError {
    /// Encryption key not found in Keychain
    case keyNotFound

    /// Encryption operation failed
    case encryptionFailed(Error)

    /// Decryption operation failed
    case decryptionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .keyNotFound:
            return "Capture encryption key not found"
        case .encryptionFailed(let error):
            return "Encryption failed: \(error.localizedDescription)"
        case .decryptionFailed(let error):
            return "Decryption failed: \(error.localizedDescription)"
        }
    }
}
