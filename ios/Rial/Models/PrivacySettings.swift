//
//  PrivacySettings.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Privacy mode settings model for Story 8-2.
//  Defines privacy mode configuration with metadata granularity levels.
//

import Foundation

// MARK: - MetadataLevel

/// Location metadata granularity level.
///
/// Controls how much location information is included in privacy mode captures.
/// Raw values use snake_case for backend API compatibility.
public enum MetadataLevel: String, Codable, CaseIterable, Sendable {
    /// No location information included
    case none = "none"
    /// City-level location (coarse)
    case coarse = "coarse"
    /// Precise GPS coordinates
    case precise = "precise"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .coarse:
            return "City Level"
        case .precise:
            return "Precise"
        }
    }

    /// Description for accessibility and help text
    var description: String {
        switch self {
        case .none:
            return "No location data included"
        case .coarse:
            return "City-level location only"
        case .precise:
            return "Exact GPS coordinates"
        }
    }

    /// System image for UI
    var systemImage: String {
        switch self {
        case .none:
            return "location.slash"
        case .coarse:
            return "location"
        case .precise:
            return "location.fill"
        }
    }
}

// MARK: - TimestampLevel

/// Timestamp precision level for privacy mode.
///
/// Controls how much timing information is included in captures.
/// Raw values use snake_case for backend API compatibility.
public enum TimestampLevel: String, Codable, CaseIterable, Sendable {
    /// No timestamp included
    case none = "none"
    /// Date only (day precision)
    case dayOnly = "day_only"
    /// Full timestamp with time
    case exact = "exact"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .dayOnly:
            return "Day Only"
        case .exact:
            return "Exact"
        }
    }

    /// Description for accessibility and help text
    var description: String {
        switch self {
        case .none:
            return "No timestamp included"
        case .dayOnly:
            return "Date without time"
        case .exact:
            return "Full date and time"
        }
    }

    /// System image for UI
    var systemImage: String {
        switch self {
        case .none:
            return "clock.badge.xmark"
        case .dayOnly:
            return "calendar"
        case .exact:
            return "clock.fill"
        }
    }
}

// MARK: - DeviceInfoLevel

/// Device information level for privacy mode.
///
/// Controls how much device information is included in captures.
/// Raw values use snake_case for backend API compatibility.
public enum DeviceInfoLevel: String, Codable, CaseIterable, Sendable {
    /// No device information included
    case none = "none"
    /// Device model only (e.g., "iPhone 15 Pro")
    case modelOnly = "model_only"
    /// Full device information
    case full = "full"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .modelOnly:
            return "Model Only"
        case .full:
            return "Full"
        }
    }

    /// Description for accessibility and help text
    var description: String {
        switch self {
        case .none:
            return "No device info included"
        case .modelOnly:
            return "Device model only"
        case .full:
            return "Complete device details"
        }
    }

    /// System image for UI
    var systemImage: String {
        switch self {
        case .none:
            return "iphone.slash"
        case .modelOnly:
            return "iphone"
        case .full:
            return "iphone.badge.checkmark"
        }
    }
}

// MARK: - PrivacySettings

/// User privacy mode settings for capture behavior.
///
/// When privacy mode is enabled, the app performs depth analysis locally
/// and uploads only a hash of the capture instead of the raw media.
///
/// ## Default Values (per tech spec)
/// - privacyModeEnabled: false
/// - locationLevel: .coarse
/// - timestampLevel: .exact
/// - deviceInfoLevel: .modelOnly
///
/// ## Usage
/// ```swift
/// let settings = PrivacySettings.default
/// if settings.privacyModeEnabled {
///     // Use hash-only capture mode
/// }
/// ```
public struct PrivacySettings: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Whether privacy mode is enabled.
    /// When true, only a hash of the capture is uploaded.
    public var privacyModeEnabled: Bool

    /// Location metadata granularity level.
    public var locationLevel: MetadataLevel

    /// Timestamp precision level.
    public var timestampLevel: TimestampLevel

    /// Device information level.
    public var deviceInfoLevel: DeviceInfoLevel

    // MARK: - Initialization

    /// Creates privacy settings with specified values.
    ///
    /// - Parameters:
    ///   - privacyModeEnabled: Whether privacy mode is enabled
    ///   - locationLevel: Location metadata granularity
    ///   - timestampLevel: Timestamp precision
    ///   - deviceInfoLevel: Device information level
    public init(
        privacyModeEnabled: Bool = false,
        locationLevel: MetadataLevel = .coarse,
        timestampLevel: TimestampLevel = .exact,
        deviceInfoLevel: DeviceInfoLevel = .modelOnly
    ) {
        self.privacyModeEnabled = privacyModeEnabled
        self.locationLevel = locationLevel
        self.timestampLevel = timestampLevel
        self.deviceInfoLevel = deviceInfoLevel
    }

    // MARK: - Default Values

    /// Default privacy settings for fresh installs.
    ///
    /// Values per tech spec:
    /// - privacyModeEnabled: false
    /// - locationLevel: .coarse
    /// - timestampLevel: .exact
    /// - deviceInfoLevel: .modelOnly
    public static let `default` = PrivacySettings(
        privacyModeEnabled: false,
        locationLevel: .coarse,
        timestampLevel: .exact,
        deviceInfoLevel: .modelOnly
    )
}

// MARK: - CustomStringConvertible

extension PrivacySettings: CustomStringConvertible {
    public var description: String {
        """
        PrivacySettings(
            privacyModeEnabled: \(privacyModeEnabled),
            locationLevel: \(locationLevel.rawValue),
            timestampLevel: \(timestampLevel.rawValue),
            deviceInfoLevel: \(deviceInfoLevel.rawValue)
        )
        """
    }
}
