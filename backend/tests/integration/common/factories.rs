//! Test data factories for RealityCam
//!
//! Factories generate realistic test data using the `fake` crate.
//! All factories support builder pattern for customization.

use fake::{Fake, Faker};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Device factory for creating test devices
#[derive(Debug, Clone)]
pub struct DeviceFactory {
    pub id: Option<Uuid>,
    pub platform: String,
    pub model: String,
    pub attestation_level: String,
    pub attestation_key_id: String,
    pub has_lidar: bool,
}

impl Default for DeviceFactory {
    fn default() -> Self {
        Self {
            id: None,
            platform: "ios".to_string(),
            model: Self::random_iphone_pro_model(),
            attestation_level: "secure_enclave".to_string(),
            attestation_key_id: Uuid::new_v4().to_string(),
            has_lidar: true,
        }
    }
}

impl DeviceFactory {
    /// Create a new device factory with defaults
    pub fn new() -> Self {
        Self::default()
    }

    /// Set a specific device model
    pub fn with_model(mut self, model: &str) -> Self {
        self.model = model.to_string();
        self.has_lidar = model.contains("Pro");
        self
    }

    /// Set attestation level
    pub fn with_attestation_level(mut self, level: &str) -> Self {
        self.attestation_level = level.to_string();
        self
    }

    /// Create an unattested device (for negative testing)
    pub fn unattested() -> Self {
        Self {
            attestation_level: "unverified".to_string(),
            ..Self::default()
        }
    }

    /// Create a device without LiDAR (for negative testing)
    pub fn without_lidar() -> Self {
        Self {
            model: "iPhone 15".to_string(), // Non-Pro model
            has_lidar: false,
            ..Self::default()
        }
    }

    /// Generate random iPhone Pro model
    fn random_iphone_pro_model() -> String {
        let models = [
            "iPhone 12 Pro",
            "iPhone 12 Pro Max",
            "iPhone 13 Pro",
            "iPhone 13 Pro Max",
            "iPhone 14 Pro",
            "iPhone 14 Pro Max",
            "iPhone 15 Pro",
            "iPhone 15 Pro Max",
            "iPhone 16 Pro",
            "iPhone 16 Pro Max",
        ];
        models[rand::random::<usize>() % models.len()].to_string()
    }

    /// Build the device registration request payload
    pub fn build_request(&self) -> DeviceRegistrationRequest {
        DeviceRegistrationRequest {
            platform: self.platform.clone(),
            model: self.model.clone(),
            attestation: AttestationPayload {
                key_id: self.attestation_key_id.clone(),
                attestation_object: generate_mock_attestation_object(),
            },
        }
    }
}

/// Capture factory for creating test captures
#[derive(Debug, Clone)]
pub struct CaptureFactory {
    pub device_id: Uuid,
    pub captured_at: DateTime<Utc>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub photo_data: Vec<u8>,
    pub depth_map: Vec<f32>,
    pub depth_width: u32,
    pub depth_height: u32,
}

impl Default for CaptureFactory {
    fn default() -> Self {
        Self {
            device_id: Uuid::new_v4(),
            captured_at: Utc::now(),
            latitude: Some(37.7749), // San Francisco
            longitude: Some(-122.4194),
            photo_data: generate_mock_jpeg(),
            depth_map: generate_mock_depth_map(256, 192),
            depth_width: 256,
            depth_height: 192,
        }
    }
}

impl CaptureFactory {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_device_id(mut self, device_id: Uuid) -> Self {
        self.device_id = device_id;
        self
    }

    pub fn with_captured_at(mut self, captured_at: DateTime<Utc>) -> Self {
        self.captured_at = captured_at;
        self
    }

    pub fn without_location(mut self) -> Self {
        self.latitude = None;
        self.longitude = None;
        self
    }

    /// Create a capture with flat depth (simulating photo of screen)
    pub fn with_flat_depth(mut self) -> Self {
        // All depth values at ~0.4m (typical screen distance)
        self.depth_map = vec![0.4; (self.depth_width * self.depth_height) as usize];
        self
    }

    /// Create a capture with realistic 3D scene depth
    pub fn with_real_scene_depth(mut self) -> Self {
        self.depth_map = generate_realistic_depth_map(self.depth_width, self.depth_height);
        self
    }

    /// Build the capture upload request metadata
    pub fn build_metadata(&self) -> CaptureMetadata {
        CaptureMetadata {
            captured_at: self.captured_at,
            device_model: "iPhone 15 Pro".to_string(),
            latitude: self.latitude,
            longitude: self.longitude,
        }
    }
}

// --- Request/Response types for testing ---

#[derive(Debug, Serialize)]
pub struct DeviceRegistrationRequest {
    pub platform: String,
    pub model: String,
    pub attestation: AttestationPayload,
}

#[derive(Debug, Serialize)]
pub struct AttestationPayload {
    pub key_id: String,
    pub attestation_object: String,
}

#[derive(Debug, Serialize)]
pub struct CaptureMetadata {
    pub captured_at: DateTime<Utc>,
    pub device_model: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}

// --- Mock data generators ---

/// Generate mock DCAppAttest attestation object (base64-encoded CBOR)
fn generate_mock_attestation_object() -> String {
    // This is a mock; real tests would use pre-generated valid attestation fixtures
    base64::encode(b"mock-attestation-object-cbor")
}

/// Generate mock JPEG data
fn generate_mock_jpeg() -> Vec<u8> {
    // Minimal valid JPEG header + some random data
    let mut data = vec![0xFF, 0xD8, 0xFF, 0xE0]; // JPEG SOI + APP0 marker
    data.extend(vec![0u8; 1024]); // Padding
    data.extend(vec![0xFF, 0xD9]); // JPEG EOI
    data
}

/// Generate mock depth map with uniform depth (flat surface)
fn generate_mock_depth_map(width: u32, height: u32) -> Vec<f32> {
    vec![1.0; (width * height) as usize]
}

/// Generate realistic depth map simulating a 3D scene
fn generate_realistic_depth_map(width: u32, height: u32) -> Vec<f32> {
    let mut depth = Vec::with_capacity((width * height) as usize);

    for y in 0..height {
        for x in 0..width {
            // Simulate depth gradient with some noise (real 3D scene)
            let base_depth = 1.0 + (y as f32 / height as f32) * 3.0; // 1m to 4m
            let noise = (rand::random::<f32>() - 0.5) * 0.3;
            depth.push(base_depth + noise);
        }
    }

    depth
}

// --- Attestation fixtures ---

/// Pre-generated valid attestation fixture for testing
/// In production tests, these would be real captured attestations from test devices
pub struct AttestationFixtures;

impl AttestationFixtures {
    /// Valid DCAppAttest from iPhone 15 Pro (mock for unit tests)
    pub fn valid_iphone_15_pro() -> String {
        // TODO: Replace with real pre-captured attestation from test device
        generate_mock_attestation_object()
    }

    /// Invalid/tampered attestation (for negative testing)
    pub fn invalid_tampered() -> String {
        base64::encode(b"invalid-tampered-attestation")
    }

    /// Expired attestation certificate (for negative testing)
    pub fn expired_certificate() -> String {
        base64::encode(b"expired-certificate-attestation")
    }
}
