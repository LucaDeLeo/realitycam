//! Device registration integration tests

use super::common::{TestApp, DeviceFactory, AttestationFixtures};
use super::common::assertions::*;

#[tokio::test]
async fn test_register_device_with_valid_attestation() {
    let app = TestApp::spawn().await;

    let device = DeviceFactory::new();
    let request = device.build_request();

    // TODO: When API server is integrated, make actual HTTP request
    // let response = app.client
    //     .post(&format!("{}/api/v1/devices/register", app.api_base_url))
    //     .json(&request)
    //     .send()
    //     .await
    //     .expect("Failed to send request");

    // For now, this is a placeholder for the test structure
    // assert_eq!(response.status(), 200);
    // let body: Value = response.json().await.unwrap();
    // assert!(body.get("data").is_some());
    // assert_has_request_id(&body);

    app.cleanup().await;
}

#[tokio::test]
async fn test_register_device_with_invalid_attestation() {
    let app = TestApp::spawn().await;

    let device = DeviceFactory::new();
    let mut request = device.build_request();
    request.attestation.attestation_object = AttestationFixtures::invalid_tampered();

    // TODO: Expect 401 ATTESTATION_FAILED error

    app.cleanup().await;
}

#[tokio::test]
async fn test_register_device_without_lidar_rejected() {
    let app = TestApp::spawn().await;

    let device = DeviceFactory::without_lidar();
    let request = device.build_request();

    // TODO: Expect error for non-Pro device (no LiDAR)

    app.cleanup().await;
}
