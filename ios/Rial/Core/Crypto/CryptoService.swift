import CryptoKit
import Foundation
import os.log

/// Service for cryptographic operations using CryptoKit
///
/// Provides hardware-accelerated cryptographic operations including:
/// - SHA-256 hashing (in-memory and streaming)
/// - AES-GCM authenticated encryption/decryption
/// - Symmetric key generation and serialization
/// - Cryptographically secure random data generation
///
/// All operations use Apple's CryptoKit framework for hardware acceleration
/// and integration with the Secure Enclave on A-series chips.
struct CryptoService {
    private static let logger = Logger(subsystem: "app.rial", category: "crypto")

    // MARK: - SHA-256 Hashing

    /// Compute SHA-256 hash and return hex-encoded string
    ///
    /// Uses hardware-accelerated SHA-256 implementation on Apple Silicon.
    /// For large files, consider using `sha256Stream(url:)` to avoid memory pressure.
    ///
    /// - Parameter data: Data to hash
    /// - Returns: Hex-encoded SHA-256 digest (64 characters, lowercase)
    ///
    /// ## Example
    /// ```swift
    /// let data = "Hello, World!".data(using: .utf8)!
    /// let hash = CryptoService.sha256(data)
    /// print(hash) // "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"
    /// ```
    static func sha256(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute SHA-256 hash and return raw bytes
    ///
    /// - Parameter data: Data to hash
    /// - Returns: SHA-256 digest as Data (32 bytes)
    static func sha256Data(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// Compute SHA-256 hash of a file using streaming (for large files)
    ///
    /// Processes file in 1MB chunks to avoid loading entire file into memory.
    /// Produces identical hash to `sha256(_:)` for the same data.
    ///
    /// - Parameter url: File URL to hash
    /// - Returns: Hex-encoded SHA-256 digest (64 characters, lowercase)
    /// - Throws: `CryptoError.fileNotFound` if file doesn't exist
    /// - Throws: `CryptoError.fileReadError` if file cannot be read
    ///
    /// ## Example
    /// ```swift
    /// let fileURL = URL(fileURLWithPath: "/path/to/large/file.jpg")
    /// let hash = try CryptoService.sha256Stream(url: fileURL)
    /// ```
    static func sha256Stream(url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("File not found: \(url.path, privacy: .public)")
            throw CryptoError.fileNotFound
        }

        guard let stream = InputStream(url: url) else {
            logger.error("Failed to create input stream for: \(url.path, privacy: .public)")
            throw CryptoError.fileReadError
        }

        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var totalBytes = 0
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                hasher.update(data: Data(bytes: buffer, count: bytesRead))
                totalBytes += bytesRead
            } else if bytesRead < 0 {
                logger.error("Stream read error: \(stream.streamError?.localizedDescription ?? "unknown")")
                throw CryptoError.fileReadError
            }
        }

        let hash = hasher.finalize()
        logger.debug("Streamed hash of \(totalBytes) bytes from \(url.lastPathComponent, privacy: .public)")
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - AES-GCM Encryption

    /// Encrypt data using AES-GCM with authenticated encryption
    ///
    /// Uses AES-GCM (Galois/Counter Mode) which provides both confidentiality
    /// and authenticity. The returned ciphertext includes a nonce and authentication
    /// tag, allowing detection of tampering.
    ///
    /// - Parameters:
    ///   - data: Plaintext data to encrypt
    ///   - key: 256-bit symmetric key (generate with `generateKey()`)
    /// - Returns: Encrypted data in combined format (nonce + ciphertext + tag)
    /// - Throws: `CryptoError.encryptionFailed` if encryption fails
    ///
    /// ## Example
    /// ```swift
    /// let plaintext = "Secret message".data(using: .utf8)!
    /// let key = CryptoService.generateKey()
    /// let ciphertext = try CryptoService.encrypt(plaintext, using: key)
    /// ```
    ///
    /// ## Security Notes
    /// - Nonce is automatically generated (cryptographically random)
    /// - Never reuse the same key+nonce pair
    /// - Store keys securely in Keychain, never in UserDefaults
    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                logger.error("Failed to get combined representation of sealed box")
                throw CryptoError.encryptionFailed
            }
            logger.debug("Encrypted \(data.count) bytes -> \(combined.count) bytes")
            return combined
        } catch {
            logger.error("Encryption failed: \(error.localizedDescription)")
            throw CryptoError.encryptionFailed
        }
    }

    /// Decrypt data using AES-GCM
    ///
    /// Decrypts ciphertext created by `encrypt(_:using:)`. Automatically verifies
    /// the authentication tag to detect tampering.
    ///
    /// - Parameters:
    ///   - data: Encrypted data in combined format (nonce + ciphertext + tag)
    ///   - key: 256-bit symmetric key (same key used for encryption)
    /// - Returns: Decrypted plaintext data
    /// - Throws: `CryptoError.authenticationFailed` if data has been tampered
    /// - Throws: `CryptoError.decryptionFailed` if decryption fails (e.g., wrong key)
    ///
    /// ## Example
    /// ```swift
    /// let key = CryptoService.generateKey()
    /// let ciphertext = try CryptoService.encrypt(plaintext, using: key)
    /// let recovered = try CryptoService.decrypt(ciphertext, using: key)
    /// assert(plaintext == recovered)
    /// ```
    ///
    /// ## Security Notes
    /// - Authentication failure indicates data tampering or corruption
    /// - Wrong key typically triggers authentication failure
    /// - Never ignore authentication failures
    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            logger.debug("Decrypted \(data.count) bytes -> \(plaintext.count) bytes")
            return plaintext
        } catch CryptoKitError.authenticationFailure {
            logger.error("Authentication failed - data may be tampered or wrong key used")
            throw CryptoError.authenticationFailed
        } catch {
            logger.error("Decryption failed: \(error.localizedDescription)")
            throw CryptoError.decryptionFailed
        }
    }

    // MARK: - Key Generation

    /// Generate a new 256-bit AES symmetric key
    ///
    /// Creates a cryptographically random 256-bit key suitable for AES-GCM encryption.
    /// Keys should be stored securely in the Keychain using `keyToData(_:)`.
    ///
    /// - Returns: Cryptographically random SymmetricKey (256 bits)
    ///
    /// ## Example
    /// ```swift
    /// let key = CryptoService.generateKey()
    /// let keyData = CryptoService.keyToData(key)
    /// // Store keyData in Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    /// ```
    ///
    /// ## Security Notes
    /// - Always use 256-bit keys for maximum security
    /// - Store keys in Keychain, never in UserDefaults or files
    /// - Use kSecAttrAccessibleWhenUnlockedThisDeviceOnly for key protection
    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Convert SymmetricKey to Data for Keychain storage
    ///
    /// Serializes key material for persistent storage in the Keychain.
    ///
    /// - Parameter key: Symmetric key to serialize
    /// - Returns: Key material as Data (32 bytes for AES-256)
    ///
    /// ## Example
    /// ```swift
    /// let key = CryptoService.generateKey()
    /// let keyData = CryptoService.keyToData(key)
    /// // Store in Keychain: keychainService.save(keyData, forKey: "encryption.key")
    /// ```
    static func keyToData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// Reconstruct SymmetricKey from Data
    ///
    /// Deserializes key material from Keychain storage to create a SymmetricKey.
    ///
    /// - Parameter data: Key material (must be 32 bytes for AES-256)
    /// - Returns: SymmetricKey instance
    /// - Throws: `CryptoError.invalidKey` if data is not exactly 32 bytes
    ///
    /// ## Example
    /// ```swift
    /// let keyData = try keychainService.load(forKey: "encryption.key")
    /// let key = try CryptoService.keyFromData(keyData)
    /// let plaintext = try CryptoService.decrypt(ciphertext, using: key)
    /// ```
    static func keyFromData(_ data: Data) throws -> SymmetricKey {
        guard data.count == 32 else {
            logger.error("Invalid key size: \(data.count) bytes (expected 32)")
            throw CryptoError.invalidKey
        }
        return SymmetricKey(data: data)
    }

    // MARK: - Random Data Generation

    /// Generate cryptographically secure random data
    ///
    /// Uses the system's secure random number generator (SecRandomCopyBytes).
    /// Suitable for generating nonces, random IDs, salts, and other security-sensitive
    /// random values.
    ///
    /// - Parameter count: Number of random bytes to generate
    /// - Returns: Random data of specified length
    ///
    /// ## Example
    /// ```swift
    /// // Generate random nonce
    /// let nonce = CryptoService.randomData(count: 12)
    ///
    /// // Generate random ID
    /// let id = CryptoService.randomData(count: 16)
    /// print("ID: \(id.base64EncodedString())")
    /// ```
    ///
    /// ## Use Cases
    /// - Nonces for encryption/signatures
    /// - Random identifiers
    /// - Salts for key derivation
    /// - Challenge-response protocols
    static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

// MARK: - Error Types

/// Errors that can occur during cryptographic operations
enum CryptoError: Error, LocalizedError {
    /// Encryption operation failed
    case encryptionFailed

    /// Decryption operation failed (wrong key or corrupted data)
    case decryptionFailed

    /// Authentication failed - data has been tampered or corrupted
    case authenticationFailed

    /// Invalid encryption key (wrong size or format)
    case invalidKey

    /// File not found at specified path
    case fileNotFound

    /// Failed to read file (permissions or I/O error)
    case fileReadError

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .authenticationFailed:
            return "Authentication failed - data may be corrupted or tampered"
        case .invalidKey:
            return "Invalid encryption key"
        case .fileNotFound:
            return "File not found"
        case .fileReadError:
            return "Failed to read file"
        }
    }
}
