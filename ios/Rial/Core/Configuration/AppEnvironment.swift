//
//  AppEnvironment.swift
//  Rial
//
//  App-wide configuration and environment settings.
//

import Foundation

/// Central configuration for app environment settings.
///
/// Reads from Info.plist or uses defaults. To configure:
/// 1. Add API_BASE_URL key to Info.plist, or
/// 2. Change the default value below for development
enum AppEnvironment {
    // MARK: - API Configuration

    /// Base URL for the RealityCam API.
    ///
    /// Priority (DEBUG builds):
    /// 1. EnvironmentStore override (runtime debug settings)
    /// 2. Info.plist `API_BASE_URL` key
    /// 3. Default localhost
    ///
    /// Priority (RELEASE builds):
    /// 1. Info.plist `API_BASE_URL` key
    /// 2. Default production URL
    static var apiBaseURL: URL {
        #if DEBUG
        // Check for runtime debug override first
        if EnvironmentStore.shared.isOverrideActive {
            return EnvironmentStore.shared.apiBaseURL
        }
        #endif

        // Check Info.plist override
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: urlString) {
            return url
        }

        #if DEBUG
        // Local development default:
        // - Simulator: localhost works directly
        // - Physical device: Use Debug Settings to set your Mac's IP
        return URL(string: "http://localhost:8080")!
        #else
        // Production URL
        return URL(string: "https://rial-api.fly.dev")!
        #endif
    }

    /// Whether the app is running in debug mode
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// API version path prefix
    static let apiVersion = "api/v1"

    // MARK: - Feature Flags

    /// Enable verbose network logging in debug builds
    static var enableNetworkLogging: Bool {
        isDebug
    }

    /// Skip device attestation in debug builds (for development without paid Apple Developer account)
    /// WARNING: Photos captured with this enabled will NOT be verified by the backend
    static var skipAttestation: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
