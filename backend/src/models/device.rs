//! Device entity model
//!
//! Represents a registered device with attestation data and hardware capabilities.

use chrono::{DateTime, Utc};
use serde::Serialize;
use uuid::Uuid;

/// A registered device with attestation status and hardware capabilities.
///
/// Devices are registered via the DeviceCheck App Attest flow and track
/// their attestation level (unverified, basic, or full).
#[derive(Debug, sqlx::FromRow, Serialize)]
pub struct Device {
    /// Unique identifier for the device
    pub id: Uuid,

    /// Attestation level: "unverified", "basic", or "full"
    pub attestation_level: String,

    /// Unique key ID from DeviceCheck App Attest
    pub attestation_key_id: String,

    /// X.509 certificate chain from attestation (DER encoded)
    pub attestation_chain: Option<Vec<u8>>,

    /// Platform identifier (e.g., "iOS")
    pub platform: String,

    /// Device model (e.g., "iPhone 15 Pro")
    pub model: String,

    /// Whether device has LiDAR sensor
    pub has_lidar: bool,

    /// When the device first registered
    pub first_seen_at: DateTime<Utc>,

    /// When the device was last seen
    pub last_seen_at: DateTime<Utc>,
}
