//! Capture upload integration tests

use super::common::{TestApp, DeviceFactory, CaptureFactory};
use super::common::assertions::*;

#[tokio::test]
async fn test_upload_capture_with_real_scene_depth() {
    let app = TestApp::spawn().await;

    // First register a device
    let device = DeviceFactory::new();
    let device_id = uuid::Uuid::new_v4(); // TODO: Get from device registration

    // Create capture with realistic depth
    let capture = CaptureFactory::new()
        .with_device_id(device_id)
        .with_real_scene_depth();

    // TODO: Upload capture via multipart POST
    // Expected: HIGH confidence, real scene detected

    app.cleanup().await;
}

#[tokio::test]
async fn test_upload_capture_with_flat_depth_detected() {
    let app = TestApp::spawn().await;

    let device = DeviceFactory::new();
    let device_id = uuid::Uuid::new_v4();

    // Create capture with flat depth (simulating photo of screen)
    let capture = CaptureFactory::new()
        .with_device_id(device_id)
        .with_flat_depth();

    // TODO: Upload capture
    // Expected: Depth analysis should flag as flat surface, lower confidence

    app.cleanup().await;
}

#[tokio::test]
async fn test_upload_capture_without_device_signature_rejected() {
    let app = TestApp::spawn().await;

    // Attempt upload without valid device signature
    // TODO: Expect 401 SIGNATURE_INVALID

    app.cleanup().await;
}

#[tokio::test]
async fn test_upload_capture_with_old_timestamp_rejected() {
    let app = TestApp::spawn().await;

    let capture = CaptureFactory::new()
        .with_captured_at(chrono::Utc::now() - chrono::Duration::minutes(10));

    // TODO: Upload with timestamp outside 5-minute window
    // Expected: 401 TIMESTAMP_EXPIRED

    app.cleanup().await;
}
