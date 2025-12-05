//
//  EnvironmentStore.swift
//  Rial
//
//  Debug-only environment configuration store.
//  Allows runtime switching between API environments without rebuilding.
//

import Foundation
import Combine

#if DEBUG

/// Available API environments for debug builds.
enum APIEnvironment: String, CaseIterable, Identifiable {
    case local = "local"
    case localDevice = "localDevice"
    case production = "production"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:
            return "Local (Simulator)"
        case .localDevice:
            return "Local (Device)"
        case .production:
            return "Production"
        }
    }

    var description: String {
        switch self {
        case .local:
            return "localhost:8080 - Use in Simulator"
        case .localDevice:
            return "Custom IP - Use on physical device"
        case .production:
            return "rial-api.fly.dev"
        }
    }

    /// Default base URL for this environment
    func defaultURL(customIP: String?) -> URL {
        switch self {
        case .local:
            return URL(string: "http://localhost:8080")!
        case .localDevice:
            let ip = customIP ?? "192.168.1.1"
            return URL(string: "http://\(ip):8080")!
        case .production:
            return URL(string: "https://rial-api.fly.dev")!
        }
    }
}

/// Persists debug environment selection to UserDefaults.
/// Only available in DEBUG builds.
final class EnvironmentStore: ObservableObject {
    static let shared = EnvironmentStore()

    private enum Keys {
        static let environment = "debug_api_environment"
        static let customIP = "debug_custom_api_ip"
    }

    private let defaults = UserDefaults.standard

    /// Currently selected environment
    @Published var currentEnvironment: APIEnvironment {
        didSet {
            defaults.set(currentEnvironment.rawValue, forKey: Keys.environment)
            objectWillChange.send()
        }
    }

    /// Custom IP address for localDevice environment
    @Published var customIP: String {
        didSet {
            defaults.set(customIP, forKey: Keys.customIP)
            objectWillChange.send()
        }
    }

    /// Whether an override is active (user has explicitly selected an environment)
    @Published var isOverrideActive: Bool {
        didSet {
            defaults.set(isOverrideActive, forKey: "debug_override_active")
        }
    }

    private init() {
        // Load persisted values
        if let savedEnv = defaults.string(forKey: Keys.environment),
           let env = APIEnvironment(rawValue: savedEnv) {
            self.currentEnvironment = env
        } else {
            self.currentEnvironment = .local
        }

        self.customIP = defaults.string(forKey: Keys.customIP) ?? ""
        self.isOverrideActive = defaults.bool(forKey: "debug_override_active")
    }

    /// Get the current API base URL based on selected environment
    var apiBaseURL: URL {
        currentEnvironment.defaultURL(customIP: customIP.isEmpty ? nil : customIP)
    }

    /// Reset to default (no override)
    func reset() {
        isOverrideActive = false
        currentEnvironment = .local
        customIP = ""
    }

    /// Activate override with specific environment
    func activate(environment: APIEnvironment) {
        isOverrideActive = true
        currentEnvironment = environment
    }
}

#endif
