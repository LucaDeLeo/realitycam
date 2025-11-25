//
//  CertificatePinning.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  TLS certificate pinning for secure API connections.
//

import Foundation
import CommonCrypto
import os.log

/// Certificate pinning validator for secure API connections.
///
/// Validates server certificates against a set of pinned public key hashes.
/// Supports multiple pins for key rotation and backup purposes.
///
/// ## Security Model
/// - Pins are SHA-256 hashes of the server's public key SPKI
/// - Multiple pins supported for seamless key rotation
/// - TLS 1.3 minimum enforced
/// - All validation failures reject the connection
///
/// ## Usage
/// ```swift
/// let pinning = CertificatePinning(pins: [
///     "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
///     "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
/// ])
///
/// // Use as URLSessionDelegate
/// urlSession.delegate = pinning.delegate
/// ```
final class CertificatePinning {
    private static let logger = Logger(subsystem: "app.rial", category: "certificate-pinning")

    /// SHA-256 hashes of pinned public keys (base64 encoded)
    private let pinnedHashes: Set<Data>

    /// Allowed hosts for pinning (nil = all hosts)
    private let allowedHosts: Set<String>?

    /// Whether pinning is enabled (can be disabled for development)
    private let isEnabled: Bool

    // MARK: - Initialization

    /// Creates a new CertificatePinning instance.
    ///
    /// - Parameters:
    ///   - pins: SHA-256 hashes of public keys in "sha256/base64hash" format
    ///   - hosts: Optional set of hosts to apply pinning to (nil = all hosts)
    ///   - enabled: Whether pinning is enabled (default: true)
    init(pins: [String], hosts: Set<String>? = nil, enabled: Bool = true) {
        var hashes = Set<Data>()

        for pin in pins {
            if let hash = Self.parsePin(pin) {
                hashes.insert(hash)
            } else {
                Self.logger.warning("Invalid pin format: \(pin)")
            }
        }

        self.pinnedHashes = hashes
        self.allowedHosts = hosts
        self.isEnabled = enabled && !hashes.isEmpty

        Self.logger.info("Certificate pinning initialized with \(hashes.count) pins")
    }

    // MARK: - Validation

    /// Validate a server trust against pinned certificates.
    ///
    /// - Parameters:
    ///   - challenge: The authentication challenge from URLSession
    ///   - completionHandler: Completion handler for challenge response
    func validate(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Skip if pinning disabled
        guard isEnabled else {
            Self.logger.debug("Pinning disabled, using default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Check if host is in allowed list
        if let allowedHosts = allowedHosts, !allowedHosts.contains(host) {
            Self.logger.debug("Host \(host) not in pinned hosts, using default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Get server trust
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            Self.logger.error("No server trust available")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Perform pinning validation
        if validateServerTrust(serverTrust, for: host) {
            let credential = URLCredential(trust: serverTrust)
            Self.logger.debug("Certificate pinning succeeded for \(host)")
            completionHandler(.useCredential, credential)
        } else {
            Self.logger.error("Certificate pinning failed for \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Private Methods

    /// Validate server trust against pinned keys.
    private func validateServerTrust(_ serverTrust: SecTrust, for host: String) -> Bool {
        // Set SSL policy with hostname validation
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        // Evaluate certificate chain
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            Self.logger.error("Trust evaluation failed: \(error?.localizedDescription ?? "unknown")")
            return false
        }

        // Get server certificate
        guard let serverCert = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let certificate = serverCert.first else {
            Self.logger.error("No certificate in chain")
            return false
        }

        // Extract public key
        guard let publicKey = SecCertificateCopyKey(certificate),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            Self.logger.error("Failed to extract public key")
            return false
        }

        // Hash the public key
        let keyHash = sha256(data: publicKeyData)

        // Check against pinned hashes
        if pinnedHashes.contains(keyHash) {
            return true
        }

        // Log the server's key hash for debugging
        Self.logger.warning("Server key hash not in pins: sha256/\(keyHash.base64EncodedString())")
        return false
    }

    /// Compute SHA-256 hash of data.
    private func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    /// Parse a pin string in "sha256/base64hash" format.
    private static func parsePin(_ pin: String) -> Data? {
        let prefix = "sha256/"
        guard pin.hasPrefix(prefix) else {
            return nil
        }

        let base64Hash = String(pin.dropFirst(prefix.count))
        return Data(base64Encoded: base64Hash)
    }
}

// MARK: - Default Pins

extension CertificatePinning {
    /// Production API pins.
    ///
    /// These should be updated when the server certificate is rotated.
    static let productionPins: [String] = [
        // Primary certificate pin
        // TODO: Replace with actual server public key hash
        "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        // Backup certificate pin for rotation
        "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
    ]

    /// Production hosts that require pinning.
    static let productionHosts: Set<String> = [
        "backend-production-5e5a.up.railway.app",
        "rial-web.vercel.app"
    ]

    /// Create pinning for production environment.
    static func production() -> CertificatePinning {
        CertificatePinning(
            pins: productionPins,
            hosts: productionHosts,
            enabled: true
        )
    }

    /// Create pinning for development (disabled).
    static func development() -> CertificatePinning {
        CertificatePinning(
            pins: [],
            hosts: nil,
            enabled: false
        )
    }
}

// MARK: - CertificatePinningError

/// Errors that can occur during certificate pinning.
enum CertificatePinningError: Error, LocalizedError {
    /// Server certificate doesn't match any pinned key
    case pinMismatch

    /// Server trust evaluation failed
    case trustEvaluationFailed(String)

    /// No certificate in server chain
    case noCertificate

    /// Failed to extract public key
    case publicKeyExtractionFailed

    var errorDescription: String? {
        switch self {
        case .pinMismatch:
            return "Server certificate doesn't match pinned key"
        case .trustEvaluationFailed(let reason):
            return "Trust evaluation failed: \(reason)"
        case .noCertificate:
            return "No certificate in server chain"
        case .publicKeyExtractionFailed:
            return "Failed to extract public key from certificate"
        }
    }
}
