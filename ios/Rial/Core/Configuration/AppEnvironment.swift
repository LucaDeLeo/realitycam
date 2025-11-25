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
    /// Priority:
    /// 1. Info.plist `API_BASE_URL` key
    /// 2. Default production URL
    static var apiBaseURL: URL {
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: urlString) {
            return url
        }
        // Default to Railway production URL
        return URL(string: "https://backend-production-5e5a.up.railway.app")!
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
}
