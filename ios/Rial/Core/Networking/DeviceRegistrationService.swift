//
//  DeviceRegistrationService.swift
//  Rial
//
//  Handles device registration with the backend.
//

import Foundation
import UIKit
import ARKit
import os.log

/// Service for registering device with the backend.
///
/// Handles the full registration flow:
/// 1. Check if already registered
/// 2. Generate attestation key
/// 3. Request challenge from backend
/// 4. Create attestation object
/// 5. Register with backend
/// 6. Save device state to keychain
final class DeviceRegistrationService {
    private static let logger = Logger(subsystem: "app.rial", category: "device-registration")

    /// Shared singleton instance
    static let shared = DeviceRegistrationService()

    /// API client for backend requests
    private let apiClient: APIClient

    /// Attestation service
    private let attestationService: DeviceAttestationService

    /// Keychain for device state
    private let keychain: KeychainService

    /// Registration state
    @Published private(set) var isRegistered = false
    @Published private(set) var isRegistering = false
    @Published private(set) var registrationError: String?

    // MARK: - Initialization

    init(
        apiClient: APIClient? = nil,
        attestationService: DeviceAttestationService? = nil,
        keychain: KeychainService? = nil
    ) {
        let kc = keychain ?? KeychainService()
        self.keychain = kc
        self.attestationService = attestationService ?? DeviceAttestationService(keychain: kc)
        self.apiClient = apiClient ?? APIClient(baseURL: AppEnvironment.apiBaseURL)

        // Check initial state
        checkRegistrationState()
    }

    // MARK: - Public Methods

    /// Check if device is already registered.
    func checkRegistrationState() {
        do {
            if let state = try keychain.loadDeviceState(), state.isRegistered {
                isRegistered = true
                Self.logger.info("Device is registered (deviceId: \(state.deviceId))")
            } else {
                isRegistered = false
                Self.logger.info("Device is not registered")
            }
        } catch {
            isRegistered = false
            Self.logger.error("Failed to check registration state: \(error.localizedDescription)")
        }
    }

    /// Register the device with the backend.
    ///
    /// If already registered, returns immediately.
    /// Otherwise performs full registration flow.
    func registerIfNeeded() async throws {
        // Already registered?
        if isRegistered {
            Self.logger.debug("Device already registered, skipping")
            return
        }

        // Already registering?
        guard !isRegistering else {
            Self.logger.debug("Registration already in progress")
            return
        }

        await MainActor.run {
            isRegistering = true
            registrationError = nil
        }

        do {
            try await performRegistration()

            await MainActor.run {
                isRegistering = false
                isRegistered = true
            }

            Self.logger.info("Device registration completed successfully")
        } catch {
            await MainActor.run {
                isRegistering = false
                registrationError = error.localizedDescription
            }
            throw error
        }
    }

    // MARK: - Private Methods

    private func performRegistration() async throws {
        Self.logger.info("Starting device registration flow")

        // Step 1: Generate attestation key
        Self.logger.debug("Step 1: Generating attestation key")
        let keyId = try await attestationService.generateKey()
        Self.logger.info("Attestation key generated: \(keyId.prefix(20))...")

        // Step 2: Request challenge from backend
        Self.logger.debug("Step 2: Requesting challenge from backend")
        let challengeResponse: APIResponse<ChallengeData> = try await apiClient.get(
            path: "/api/v1/devices/challenge",
            authenticated: false
        )

        guard let challengeData = Data(base64Encoded: challengeResponse.data.challenge) else {
            throw RegistrationError.invalidChallenge
        }
        Self.logger.info("Challenge received, expires: \(challengeResponse.data.expiresAt)")

        // Step 3: Create attestation object
        Self.logger.debug("Step 3: Creating attestation object")
        let attestationObject = try await attestationService.attestKey(keyId, challenge: challengeData)
        Self.logger.info("Attestation object created (\(attestationObject.count) bytes)")

        // Step 4: Register with backend
        Self.logger.debug("Step 4: Registering with backend")
        let request = DeviceRegistrationRequest(
            platform: "ios",
            model: deviceModel(),
            hasLidar: ARCaptureSession.isLiDARAvailable,
            attestation: AttestationPayload(
                keyId: keyId,
                attestationObject: attestationObject.base64EncodedString(),
                challenge: challengeResponse.data.challenge
            )
        )

        let response: APIResponse<RegistrationData> = try await apiClient.post(
            path: "/api/v1/devices/register",
            body: request,
            authenticated: false
        )

        Self.logger.info("Backend registration successful: deviceId=\(response.data.deviceId), level=\(response.data.attestationLevel)")

        // Step 5: Save device state to keychain
        Self.logger.debug("Step 5: Saving device state to keychain")
        try attestationService.saveDeviceState(
            deviceId: response.data.deviceId,
            attestationKeyId: keyId
        )

        Self.logger.info("Device state saved to keychain")
    }

    /// Get device model string.
    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

// MARK: - API Types

/// Generic wrapper for backend responses that use {"data": {...}, "meta": {...}} format.
private struct APIResponse<T: Decodable>: Decodable {
    let data: T
}

/// Challenge response data from backend.
/// Note: APIClient uses convertFromSnakeCase, so no CodingKeys needed.
private struct ChallengeData: Decodable {
    let challenge: String
    let expiresAt: String
}

/// Device registration request.
/// Note: APIClient uses convertToSnakeCase, so no CodingKeys needed.
private struct DeviceRegistrationRequest: Encodable {
    let platform: String
    let model: String
    let hasLidar: Bool
    let attestation: AttestationPayload
}

/// Attestation payload for registration.
/// Note: APIClient uses convertToSnakeCase, so no CodingKeys needed.
private struct AttestationPayload: Encodable {
    let keyId: String
    let attestationObject: String
    let challenge: String
}

/// Registration response data from backend.
/// Note: APIClient uses convertFromSnakeCase, so no CodingKeys needed.
private struct RegistrationData: Decodable {
    let deviceId: String
    let attestationLevel: String
    let hasLidar: Bool
}

// MARK: - Errors

/// Registration errors.
enum RegistrationError: Error, LocalizedError {
    case invalidChallenge
    case attestationFailed(Error)
    case networkError(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidChallenge:
            return "Invalid challenge from server"
        case .attestationFailed(let error):
            return "Attestation failed: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
