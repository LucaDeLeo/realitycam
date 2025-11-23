//! Privacy Controls Service (Story 4-8)
//!
//! Implements privacy controls for capture metadata, including:
//! - Location coarsening (GPS to ~1km precision)
//! - Location display formatting
//! - Privacy-aware evidence generation
//!
//! ## Privacy Levels
//! - Precise: 6 decimal places (~0.1m) - internal storage only
//! - Coarse: 2 decimal places (~1.1km) - public display
//!
//! ## Principles
//! - Never expose precise location via public API
//! - Treat missing location as user choice (opted-out), not failure
//! - Raw depth maps are never publicly accessible

use tracing::debug;

use crate::types::capture::CaptureLocation;

// ============================================================================
// Configuration Constants
// ============================================================================

/// Decimal places for coarse location (2 = ~1.1km precision)
const COARSE_DECIMAL_PLACES: i32 = 2;

// ============================================================================
// Location Coarsening Functions
// ============================================================================

/// Coarsens GPS coordinates for privacy
///
/// Rounds coordinates to 2 decimal places, providing approximately
/// 1.1km precision (at equator, less at higher latitudes).
///
/// # Arguments
/// * `latitude` - Precise latitude (-90 to 90)
/// * `longitude` - Precise longitude (-180 to 180)
///
/// # Returns
/// Tuple of (coarse_lat, coarse_lng)
pub fn coarsen_coordinates(latitude: f64, longitude: f64) -> (f64, f64) {
    let factor = 10f64.powi(COARSE_DECIMAL_PLACES);
    let coarse_lat = (latitude * factor).round() / factor;
    let coarse_lng = (longitude * factor).round() / factor;

    debug!(
        precise_lat = latitude,
        precise_lng = longitude,
        coarse_lat = coarse_lat,
        coarse_lng = coarse_lng,
        "[privacy] Coordinates coarsened"
    );

    (coarse_lat, coarse_lng)
}

/// Formats coarsened coordinates for display
///
/// Returns a human-readable string like "37.77, -122.42"
///
/// # Arguments
/// * `latitude` - Coarse latitude
/// * `longitude` - Coarse longitude
///
/// # Returns
/// Formatted coordinate string
pub fn format_location_coarse(latitude: f64, longitude: f64) -> String {
    let (coarse_lat, coarse_lng) = coarsen_coordinates(latitude, longitude);
    format!("{:.2}, {:.2}", coarse_lat, coarse_lng)
}

/// Processes location data for privacy-aware storage
///
/// Takes precise location and returns coarse string for public display.
/// Returns None if location is not available.
///
/// # Arguments
/// * `location` - Optional capture location from metadata
///
/// # Returns
/// Optional coarse location string for display
pub fn process_location_for_evidence(location: Option<&CaptureLocation>) -> Option<String> {
    location.map(|loc| format_location_coarse(loc.latitude, loc.longitude))
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_coarsen_coordinates_basic() {
        // San Francisco City Hall
        let (lat, lng) = coarsen_coordinates(37.779260, -122.419336);
        assert!((lat - 37.78).abs() < 0.001);
        assert!((lng - (-122.42)).abs() < 0.001);
    }

    #[test]
    fn test_coarsen_coordinates_rounding_down() {
        let (lat, lng) = coarsen_coordinates(37.774, -122.414);
        assert!((lat - 37.77).abs() < 0.001);
        assert!((lng - (-122.41)).abs() < 0.001);
    }

    #[test]
    fn test_coarsen_coordinates_rounding_up() {
        let (lat, lng) = coarsen_coordinates(37.776, -122.416);
        assert!((lat - 37.78).abs() < 0.001);
        assert!((lng - (-122.42)).abs() < 0.001);
    }

    #[test]
    fn test_coarsen_coordinates_equator() {
        let (lat, lng) = coarsen_coordinates(0.0, 0.0);
        assert!((lat - 0.0).abs() < 0.001);
        assert!((lng - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_coarsen_coordinates_poles() {
        // North pole
        let (lat, _) = coarsen_coordinates(90.0, 0.0);
        assert!((lat - 90.0).abs() < 0.001);

        // South pole
        let (lat, _) = coarsen_coordinates(-90.0, 0.0);
        assert!((lat - (-90.0)).abs() < 0.001);
    }

    #[test]
    fn test_coarsen_coordinates_dateline() {
        // International date line
        let (_, lng) = coarsen_coordinates(0.0, 180.0);
        assert!((lng - 180.0).abs() < 0.001);

        let (_, lng) = coarsen_coordinates(0.0, -180.0);
        assert!((lng - (-180.0)).abs() < 0.001);
    }

    #[test]
    fn test_format_location_coarse() {
        let result = format_location_coarse(37.779260, -122.419336);
        assert_eq!(result, "37.78, -122.42");
    }

    #[test]
    fn test_format_location_coarse_negative() {
        let result = format_location_coarse(-33.8688, 151.2093);
        assert_eq!(result, "-33.87, 151.21");
    }

    #[test]
    fn test_process_location_for_evidence_some() {
        let loc = CaptureLocation {
            latitude: 37.779260,
            longitude: -122.419336,
            altitude: Some(10.0),
            accuracy: Some(5.0),
        };
        let result = process_location_for_evidence(Some(&loc));
        assert_eq!(result, Some("37.78, -122.42".to_string()));
    }

    #[test]
    fn test_process_location_for_evidence_none() {
        let result = process_location_for_evidence(None);
        assert_eq!(result, None);
    }

    #[test]
    fn test_coarsening_precision() {
        // Test that precision is approximately 1km
        // At equator, 0.01 degrees longitude = ~1.11 km
        // 0.01 degrees latitude = ~1.11 km everywhere
        let precise = (37.7749295, -122.4194155);
        let (coarse_lat, coarse_lng) = coarsen_coordinates(precise.0, precise.1);

        // Should lose the fine precision
        assert!((coarse_lat - 37.77).abs() < 0.001);
        assert!((coarse_lng - (-122.42)).abs() < 0.001);

        // The difference should be at most ~0.005 degrees (half the rounding)
        // which is ~0.5km
        let lat_diff = (precise.0 - coarse_lat).abs();
        let lng_diff = (precise.1 - coarse_lng).abs();
        assert!(lat_diff < 0.01);
        assert!(lng_diff < 0.01);
    }
}
