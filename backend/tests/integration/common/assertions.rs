//! Custom assertions for RealityCam tests
//!
//! Provides domain-specific assertions for evidence verification.

use serde_json::Value;

/// Assert that evidence has expected confidence level
pub fn assert_confidence_level(evidence: &Value, expected: &str) {
    let confidence = evidence
        .get("confidence_level")
        .and_then(|v| v.as_str())
        .expect("Missing confidence_level in evidence");

    assert_eq!(
        confidence, expected,
        "Expected confidence level '{}', got '{}'",
        expected, confidence
    );
}

/// Assert hardware attestation passed
pub fn assert_hardware_attestation_pass(evidence: &Value) {
    let status = evidence
        .pointer("/hardware_attestation/status")
        .and_then(|v| v.as_str())
        .expect("Missing hardware_attestation.status");

    assert_eq!(status, "pass", "Expected hardware attestation to pass");
}

/// Assert depth analysis indicates real scene
pub fn assert_real_scene(evidence: &Value) {
    let is_real = evidence
        .pointer("/depth_analysis/is_likely_real_scene")
        .and_then(|v| v.as_bool())
        .expect("Missing depth_analysis.is_likely_real_scene");

    assert!(is_real, "Expected depth analysis to indicate real scene");
}

/// Assert depth analysis indicates flat surface (potential fake)
pub fn assert_flat_surface(evidence: &Value) {
    let is_real = evidence
        .pointer("/depth_analysis/is_likely_real_scene")
        .and_then(|v| v.as_bool())
        .expect("Missing depth_analysis.is_likely_real_scene");

    assert!(!is_real, "Expected depth analysis to indicate flat surface");
}

/// Assert depth variance is above threshold
pub fn assert_depth_variance_above(evidence: &Value, threshold: f64) {
    let variance = evidence
        .pointer("/depth_analysis/depth_variance")
        .and_then(|v| v.as_f64())
        .expect("Missing depth_analysis.depth_variance");

    assert!(
        variance > threshold,
        "Expected depth variance > {}, got {}",
        threshold,
        variance
    );
}

/// Assert evidence check passed
pub fn assert_check_passed(evidence: &Value, check_path: &str) {
    let status = evidence
        .pointer(&format!("{}/status", check_path))
        .and_then(|v| v.as_str())
        .unwrap_or("missing");

    assert_eq!(
        status, "pass",
        "Expected check '{}' to pass, got '{}'",
        check_path, status
    );
}

/// Assert evidence check failed
pub fn assert_check_failed(evidence: &Value, check_path: &str) {
    let status = evidence
        .pointer(&format!("{}/status", check_path))
        .and_then(|v| v.as_str())
        .unwrap_or("missing");

    assert_eq!(
        status, "fail",
        "Expected check '{}' to fail, got '{}'",
        check_path, status
    );
}

/// Assert API error response
pub fn assert_api_error(response: &Value, expected_code: &str) {
    let code = response
        .pointer("/error/code")
        .and_then(|v| v.as_str())
        .expect("Missing error.code in response");

    assert_eq!(
        code, expected_code,
        "Expected error code '{}', got '{}'",
        expected_code, code
    );
}

/// Assert response has request_id in meta
pub fn assert_has_request_id(response: &Value) {
    let request_id = response
        .pointer("/meta/request_id")
        .and_then(|v| v.as_str());

    assert!(request_id.is_some(), "Response missing meta.request_id");
}
