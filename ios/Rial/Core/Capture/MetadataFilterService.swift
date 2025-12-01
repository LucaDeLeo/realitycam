//
//  MetadataFilterService.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Metadata filtering service for privacy mode (Story 8-3).
//  Filters location, timestamp, and device info based on privacy settings.
//

import Foundation
import CoreLocation
import os.log

// MARK: - MetadataFilterService

/// Service for filtering metadata according to privacy settings.
///
/// Provides static methods to filter:
/// - Location: none/coarse/precise
/// - Timestamp: none/dayOnly/exact
/// - Device info: none/modelOnly/full
///
/// ## Usage
/// ```swift
/// let settings = privacySettings.settings
///
/// let filteredLocation = await MetadataFilterService.filterLocation(
///     data: captureData.metadata.location,
///     level: settings.locationLevel
/// )
///
/// let filteredTimestamp = MetadataFilterService.filterTimestamp(
///     date: captureData.timestamp,
///     level: settings.timestampLevel
/// )
///
/// let filteredDevice = MetadataFilterService.filterDeviceInfo(
///     metadata: captureData.metadata,
///     level: settings.deviceInfoLevel
/// )
/// ```
public enum MetadataFilterService {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "app.rial", category: "metadatafilter")

    // MARK: - Location Filtering

    /// Filters location data according to privacy level.
    ///
    /// - Parameters:
    ///   - data: Original location data (nil if no location available)
    ///   - level: Privacy level to apply
    /// - Returns: Filtered location or nil
    ///
    /// ## Level Behavior
    /// - `.none`: Returns nil (no location included)
    /// - `.coarse`: Returns city/country via reverse geocoding
    /// - `.precise`: Returns full coordinates
    public static func filterLocation(
        data: LocationData?,
        level: MetadataLevel
    ) async -> FilteredLocation? {
        guard let location = data else {
            logger.debug("No location data to filter")
            return nil
        }

        switch level {
        case .none:
            logger.debug("Location level: none - excluding location")
            return nil

        case .coarse:
            logger.debug("Location level: coarse - reverse geocoding")
            return await reverseGeocodeToCoarse(location: location)

        case .precise:
            logger.debug("Location level: precise - including coordinates")
            return .precise(latitude: location.latitude, longitude: location.longitude)
        }
    }

    /// Synchronous version of location filtering (for cases where async isn't available).
    /// Falls back to coordinates if geocoding is needed but can't be done synchronously.
    ///
    /// - Parameters:
    ///   - data: Original location data
    ///   - level: Privacy level to apply
    /// - Returns: Filtered location or nil
    public static func filterLocationSync(
        data: LocationData?,
        level: MetadataLevel
    ) -> FilteredLocation? {
        guard let location = data else {
            return nil
        }

        switch level {
        case .none:
            return nil

        case .coarse:
            // For sync version, we can't do async geocoding
            // Return a placeholder that caller should replace with geocoded data
            // In practice, use the async version when possible
            logger.warning("Sync location filtering for coarse level - returning nil (use async)")
            return nil

        case .precise:
            return .precise(latitude: location.latitude, longitude: location.longitude)
        }
    }

    // MARK: - Timestamp Filtering

    /// Filters timestamp according to privacy level.
    ///
    /// - Parameters:
    ///   - date: Original capture timestamp
    ///   - level: Privacy level to apply
    /// - Returns: Filtered timestamp string or nil
    ///
    /// ## Level Behavior
    /// - `.none`: Returns nil (no timestamp included)
    /// - `.dayOnly`: Returns date only ("2025-12-01")
    /// - `.exact`: Returns full ISO8601 ("2025-12-01T10:30:00Z")
    public static func filterTimestamp(
        date: Date,
        level: TimestampLevel
    ) -> String? {
        switch level {
        case .none:
            logger.debug("Timestamp level: none - excluding timestamp")
            return nil

        case .dayOnly:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            let dateString = formatter.string(from: date)
            logger.debug("Timestamp level: dayOnly - \(dateString)")
            return dateString

        case .exact:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let dateString = formatter.string(from: date)
            logger.debug("Timestamp level: exact - \(dateString)")
            return dateString
        }
    }

    // MARK: - Device Info Filtering

    /// Filters device information according to privacy level.
    ///
    /// - Parameters:
    ///   - metadata: Original capture metadata
    ///   - level: Privacy level to apply
    /// - Returns: Filtered device info string or nil
    ///
    /// ## Level Behavior
    /// - `.none`: Returns nil (no device info included)
    /// - `.modelOnly`: Returns device model only ("iPhone 15 Pro")
    /// - `.full`: Returns full info ("iPhone 15 Pro / iOS 18.1 / 1.0.0")
    public static func filterDeviceInfo(
        metadata: CaptureMetadata,
        level: DeviceInfoLevel
    ) -> String? {
        switch level {
        case .none:
            logger.debug("Device info level: none - excluding device info")
            return nil

        case .modelOnly:
            logger.debug("Device info level: modelOnly - \(metadata.deviceModel)")
            return metadata.deviceModel

        case .full:
            let fullInfo = "\(metadata.deviceModel) / iOS \(metadata.iosVersion) / \(metadata.appVersion)"
            logger.debug("Device info level: full - \(fullInfo)")
            return fullInfo
        }
    }

    // MARK: - Combined Filtering

    /// Filters all metadata according to privacy settings.
    ///
    /// Convenience method that filters location, timestamp, and device info
    /// in a single call.
    ///
    /// - Parameters:
    ///   - captureData: Original capture data
    ///   - settings: Privacy settings to apply
    /// - Returns: Filtered metadata
    public static func filterAll(
        captureData: CaptureData,
        settings: PrivacySettings
    ) async -> FilteredMetadata {
        let location = await filterLocation(
            data: captureData.metadata.location,
            level: settings.locationLevel
        )

        let timestamp = filterTimestamp(
            date: captureData.timestamp,
            level: settings.timestampLevel
        )

        let deviceInfo = filterDeviceInfo(
            metadata: captureData.metadata,
            level: settings.deviceInfoLevel
        )

        return FilteredMetadata(
            location: location,
            timestamp: timestamp,
            deviceModel: deviceInfo
        )
    }

    // MARK: - Private Helpers

    /// Reverse geocodes coordinates to city/country.
    ///
    /// Uses CLGeocoder to convert coordinates to place names.
    /// Falls back to nil if geocoding fails.
    ///
    /// - Parameter location: Location with coordinates
    /// - Returns: Coarse location with city/country, or nil on failure
    private static func reverseGeocodeToCoarse(location: LocationData) async -> FilteredLocation? {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(clLocation)

            guard let placemark = placemarks.first else {
                logger.warning("No placemarks returned from geocoding")
                return nil
            }

            let city = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
            let country = placemark.isoCountryCode ?? placemark.country ?? "Unknown"

            logger.debug("Geocoded to: \(city), \(country)")
            return .coarse(city: city, country: country)

        } catch {
            logger.error("Reverse geocoding failed: \(error.localizedDescription)")
            // On failure, don't include location rather than exposing coordinates
            return nil
        }
    }
}

// MARK: - Metadata Flags Builder

extension MetadataFilterService {

    /// Builds metadata flags from privacy settings.
    ///
    /// - Parameter settings: Privacy settings
    /// - Returns: MetadataFlags indicating what was included
    public static func buildFlags(from settings: PrivacySettings) -> MetadataFlags {
        MetadataFlags.from(settings: settings)
    }
}
