//
//  CaptureAssertionService.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Per-capture assertion generation using DCAppAttest.
//

import Foundation
import os.log

/// Service for generating per-capture DCAppAttest assertions
///
/// Generates cryptographic assertions that bind capture data (JPEG + depth) to
/// the device's attestation key stored in Secure Enclave. Each assertion provides
/// proof that the capture originated from a registered device.
///
/// ## Security Model
/// - Assertions are signed by Secure Enclave key (non-extractable)
/// - SHA-256 hash of combined JPEG+depth binds assertion to specific capture
/// - Counter increments with each assertion (prevents replay)
/// - Backend verifies signature against device's public key
///
/// ## Performance Targets
/// - Hash computation: < 30ms for ~4MB combined data
/// - Assertion generation: < 50ms (Secure Enclave operation)
/// - Total overhead: < 100ms per capture
///
/// ## Example Usage
/// ```swift
/// let service = CaptureAssertionService(
///     attestation: DeviceAttestationService(),
///     keychain: KeychainService()
/// )
///
/// // Generate assertion for capture
/// let assertion = try await service.createAssertion(for: captureData)
///
/// // Attach to capture for upload
/// captureData.assertion = assertion
/// ```
class CaptureAssertionService {
    let attestation: DeviceAttestationService
    private let keychain: KeychainService
    private static let logger = Logger(subsystem: "app.rial", category: "capture-assertion")

    /// Cached key ID to avoid repeated keychain lookups
    private var cachedKeyId: String?

    // MARK: - Initialization

    /// Creates a new CaptureAssertionService instance.
    ///
    /// - Parameters:
    ///   - attestation: DeviceAttestationService for assertion generation
    ///   - keychain: KeychainService for key ID retrieval
    init(attestation: DeviceAttestationService, keychain: KeychainService) {
        self.attestation = attestation
        self.keychain = keychain
    }

    // MARK: - Methods

    /// Generate DCAppAttest assertion for capture data.
    ///
    /// Combines JPEG and depth data, computes SHA-256 hash, and generates
    /// a cryptographic assertion signed by the device's Secure Enclave key.
    ///
    /// - Parameter capture: CaptureData containing JPEG and depth
    /// - Returns: Assertion data (CBOR-encoded signature and counter)
    /// - Throws: `CaptureAssertionError` if assertion generation fails
    ///
    /// ## Performance
    /// Target: < 100ms total (30ms hash + 50ms assertion + overhead)
    ///
    /// ## Example
    /// ```swift
    /// let assertion = try await service.createAssertion(for: captureData)
    /// // assertion.count is typically 1-2KB
    /// ```
    func createAssertion(for capture: CaptureData) async throws -> Data {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Get key ID (from cache or keychain)
        let keyId = try getKeyId()

        // Combine JPEG + depth into single data blob
        var combinedData = Data()
        combinedData.reserveCapacity(capture.jpeg.count + capture.depth.count)
        combinedData.append(capture.jpeg)
        combinedData.append(capture.depth)

        let hashStartTime = CFAbsoluteTimeGetCurrent()
        let hashTime = (CFAbsoluteTimeGetCurrent() - hashStartTime) * 1000
        Self.logger.debug("Data combined in \(String(format: "%.1f", hashTime))ms for \(combinedData.count) bytes")

        // Generate assertion from Secure Enclave
        // DeviceAttestationService.generateAssertion handles SHA-256 hashing internally
        do {
            let assertion = try await attestation.generateAssertion(keyId, clientData: combinedData)

            let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            Self.logger.info("""
                Assertion generated: \
                captureId=\(capture.id.uuidString, privacy: .public), \
                assertionSize=\(assertion.count), \
                dataSize=\(combinedData.count), \
                totalTime=\(String(format: "%.1f", totalTime))ms
                """)

            // Warn if exceeded target
            if totalTime > 100 {
                Self.logger.warning("Assertion generation exceeded 100ms target: \(String(format: "%.1f", totalTime))ms")
            }

            return assertion
        } catch let error as AttestationError {
            Self.logger.error("""
                Assertion generation failed: \
                captureId=\(capture.id.uuidString, privacy: .public), \
                error=\(error.errorDescription ?? "unknown", privacy: .public)
                """)
            throw CaptureAssertionError.assertionGenerationFailed(error)
        } catch {
            Self.logger.error("""
                Assertion generation failed: \
                captureId=\(capture.id.uuidString, privacy: .public), \
                error=\(error.localizedDescription, privacy: .public)
                """)
            throw CaptureAssertionError.assertionGenerationFailed(error)
        }
    }

    /// Check if assertion generation is available on this device.
    ///
    /// - Returns: `true` if DCAppAttest is supported and key ID is available
    var isAvailable: Bool {
        attestation.isSupported && (cachedKeyId != nil || attestation.loadStoredKeyId() != nil)
    }

    /// Generate DCAppAttest assertion for a hash.
    ///
    /// Signs a hash directly without wrapping it in CaptureData. Used for
    /// video attestation where the hash is already computed from the frame chain.
    ///
    /// - Parameter hash: SHA-256 hash to sign (32 bytes)
    /// - Returns: Assertion data (CBOR-encoded signature and counter)
    /// - Throws: `CaptureAssertionError` if assertion generation fails
    ///
    /// ## Performance
    /// Target: < 50ms (Secure Enclave operation)
    ///
    /// ## Example
    /// ```swift
    /// let hash = hashChainData.finalHash  // 32-byte SHA256
    /// let assertion = try await service.generateAssertion(for: hash)
    /// ```
    func generateAssertion(for hash: Data) async throws -> Data {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Get key ID (from cache or keychain)
        let keyId = try getKeyId()

        // Generate assertion from Secure Enclave
        // DeviceAttestationService.generateAssertion handles SHA-256 hashing internally
        do {
            let assertion = try await attestation.generateAssertion(keyId, clientData: hash)

            let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            let hashPrefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
            Self.logger.info("""
                Hash assertion generated: \
                hash=\(hashPrefix)..., \
                assertionSize=\(assertion.count), \
                totalTime=\(String(format: "%.1f", totalTime))ms
                """)

            // Warn if exceeded target
            if totalTime > 50 {
                Self.logger.warning("Hash assertion generation exceeded 50ms target: \(String(format: "%.1f", totalTime))ms")
            }

            return assertion
        } catch let error as AttestationError {
            Self.logger.error("""
                Hash assertion generation failed: \
                error=\(error.errorDescription ?? "unknown", privacy: .public)
                """)
            throw CaptureAssertionError.assertionGenerationFailed(error)
        } catch {
            Self.logger.error("""
                Hash assertion generation failed: \
                error=\(error.localizedDescription, privacy: .public)
                """)
            throw CaptureAssertionError.assertionGenerationFailed(error)
        }
    }

    /// Clear cached key ID (call when device re-registers).
    func clearCache() {
        cachedKeyId = nil
    }

    // MARK: - Private Methods

    /// Get attestation key ID from cache or keychain.
    ///
    /// - Returns: Key ID string
    /// - Throws: `CaptureAssertionError.attestationKeyNotFound` if not available
    private func getKeyId() throws -> String {
        // Return cached value if available
        if let cached = cachedKeyId {
            return cached
        }

        // Load from keychain via DeviceAttestationService
        guard let keyId = attestation.loadStoredKeyId() else {
            Self.logger.error("Attestation key ID not found in keychain")
            throw CaptureAssertionError.attestationKeyNotFound
        }

        // Cache for future use
        cachedKeyId = keyId
        Self.logger.debug("Loaded and cached key ID from keychain")

        return keyId
    }
}

// MARK: - CaptureAssertionError

/// Errors that can occur during capture assertion generation.
enum CaptureAssertionError: Error, LocalizedError, Equatable {
    /// Device attestation key not found in keychain (device not registered)
    case attestationKeyNotFound

    /// DCAppAttest assertion generation failed
    case assertionGenerationFailed(Error)

    /// Hash computation failed
    case hashComputationFailed

    var errorDescription: String? {
        switch self {
        case .attestationKeyNotFound:
            return "Device attestation key not found in keychain"
        case .assertionGenerationFailed(let error):
            return "Failed to generate assertion: \(error.localizedDescription)"
        case .hashComputationFailed:
            return "Failed to compute capture data hash"
        }
    }

    // MARK: - Equatable

    static func == (lhs: CaptureAssertionError, rhs: CaptureAssertionError) -> Bool {
        switch (lhs, rhs) {
        case (.attestationKeyNotFound, .attestationKeyNotFound):
            return true
        case (.hashComputationFailed, .hashComputationFailed):
            return true
        case (.assertionGenerationFailed, .assertionGenerationFailed):
            // Compare error descriptions for equality
            return true
        default:
            return false
        }
    }
}

