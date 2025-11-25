//
//  DeviceSignature.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Device authentication for API requests.
//

import Foundation
import CryptoKit
import os.log

/// Service for generating device authentication signatures.
///
/// Provides Ed25519 signatures for API requests using the device's
/// Secure Enclave-backed private key.
///
/// ## Security Model
/// - Private key never leaves Secure Enclave
/// - Signatures include timestamp to prevent replay attacks
/// - Device ID included in signed payload for binding
///
/// ## Usage
/// ```swift
/// let signature = DeviceSignature(keychain: keychainService)
///
/// // Sign a request
/// let auth = try signature.sign(
///     method: "POST",
///     path: "/api/v1/captures",
///     timestamp: Date()
/// )
/// request.addValue(auth.deviceId, forHTTPHeaderField: "X-Device-Id")
/// request.addValue(auth.timestamp, forHTTPHeaderField: "X-Device-Timestamp")
/// request.addValue(auth.signature, forHTTPHeaderField: "X-Device-Signature")
/// ```
final class DeviceSignature {
    private static let logger = Logger(subsystem: "app.rial", category: "device-signature")

    /// Keychain service for key access
    private let keychain: KeychainService

    /// Tag for signing key in Keychain
    private static let signingKeyTag = "app.rial.device.signing.key"

    // MARK: - Initialization

    /// Creates a new DeviceSignature instance.
    ///
    /// - Parameter keychain: KeychainService for key storage
    init(keychain: KeychainService) {
        self.keychain = keychain
    }

    // MARK: - Signing

    /// Generate authentication headers for an API request.
    ///
    /// Creates a signature over the request method, path, and timestamp
    /// using the device's signing key.
    ///
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - path: Request path (e.g., "/api/v1/captures")
    ///   - body: Optional request body data
    ///   - timestamp: Timestamp for the signature (defaults to now)
    /// - Returns: Authentication headers struct
    /// - Throws: `DeviceSignatureError` if signing fails
    func sign(
        method: String,
        path: String,
        body: Data? = nil,
        timestamp: Date = Date()
    ) throws -> AuthHeaders {
        // Load device state
        guard let deviceState = try keychain.loadDeviceState() else {
            Self.logger.error("Device not registered - cannot sign request")
            throw DeviceSignatureError.deviceNotRegistered
        }

        // Load signing key
        guard let signingKey = try keychain.loadSecureEnclaveKey(forKey: Self.signingKeyTag) else {
            Self.logger.error("Signing key not found")
            throw DeviceSignatureError.keyNotFound
        }

        // Create signature payload
        let timestampMillis = Int64(timestamp.timeIntervalSince1970 * 1000)
        let payload = createSignaturePayload(
            method: method,
            path: path,
            timestamp: timestampMillis,
            deviceId: deviceState.deviceId
        )

        // Sign the payload
        let signature = try signPayload(payload, with: signingKey)

        Self.logger.debug("Signed request: \(method) \(path)")

        return AuthHeaders(
            deviceId: deviceState.deviceId,
            timestamp: String(timestampMillis),
            signature: signature.base64EncodedString()
        )
    }

    /// Sign a request and add headers.
    ///
    /// Convenience method that modifies a URLRequest in place.
    ///
    /// - Parameter request: URLRequest to sign
    /// - Throws: `DeviceSignatureError` if signing fails
    func sign(_ request: inout URLRequest) throws {
        guard let url = request.url,
              let method = request.httpMethod else {
            throw DeviceSignatureError.invalidRequest
        }

        let path = url.path.isEmpty ? "/" : url.path
        let auth = try sign(method: method, path: path, body: request.httpBody)

        request.setValue(auth.deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(auth.timestamp, forHTTPHeaderField: "X-Device-Timestamp")
        request.setValue(auth.signature, forHTTPHeaderField: "X-Device-Signature")
    }

    // MARK: - Private Methods

    /// Create signature payload string.
    private func createSignaturePayload(
        method: String,
        path: String,
        timestamp: Int64,
        deviceId: String
    ) -> Data {
        // Format: METHOD\nPATH\nTIMESTAMP\nDEVICE_ID
        let payloadString = "\(method)\n\(path)\n\(timestamp)\n\(deviceId)"
        return Data(payloadString.utf8)
    }

    /// Sign payload with Secure Enclave key.
    private func signPayload(_ payload: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .ecdsaSignatureMessageX962SHA256,
            payload as CFData,
            &error
        ) as Data? else {
            let errorMsg = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            Self.logger.error("Signing failed: \(errorMsg)")
            throw DeviceSignatureError.signingFailed(errorMsg)
        }

        return signature
    }
}

// MARK: - AuthHeaders

/// Authentication headers for API requests.
struct AuthHeaders {
    /// Device UUID string
    let deviceId: String

    /// Timestamp in milliseconds since epoch
    let timestamp: String

    /// Base64-encoded signature
    let signature: String
}

// MARK: - DeviceSignatureError

/// Errors that can occur during device signature operations.
enum DeviceSignatureError: Error, LocalizedError {
    /// Device not registered with backend
    case deviceNotRegistered

    /// Signing key not found in Keychain
    case keyNotFound

    /// Invalid request (missing URL or method)
    case invalidRequest

    /// Signing operation failed
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotRegistered:
            return "Device is not registered"
        case .keyNotFound:
            return "Device signing key not found"
        case .invalidRequest:
            return "Invalid request"
        case .signingFailed(let message):
            return "Signing failed: \(message)"
        }
    }
}
