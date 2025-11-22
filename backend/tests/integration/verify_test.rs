//! Verification endpoint integration tests

use super::common::TestApp;
use super::common::assertions::*;

#[tokio::test]
async fn test_get_capture_by_id() {
    let app = TestApp::spawn().await;

    // TODO: Create a capture, then fetch it by ID
    // Verify evidence structure is complete

    app.cleanup().await;
}

#[tokio::test]
async fn test_get_capture_not_found() {
    let app = TestApp::spawn().await;

    let fake_id = uuid::Uuid::new_v4();

    // TODO: GET /captures/{fake_id}
    // Expected: 404 CAPTURE_NOT_FOUND

    app.cleanup().await;
}

#[tokio::test]
async fn test_verify_file_by_hash_match() {
    let app = TestApp::spawn().await;

    // TODO: Upload a capture, then verify by file hash
    // Expected: Returns linked capture evidence

    app.cleanup().await;
}

#[tokio::test]
async fn test_verify_file_by_hash_no_match() {
    let app = TestApp::spawn().await;

    // TODO: POST /verify-file with random file
    // Expected: 404 HASH_NOT_FOUND

    app.cleanup().await;
}
