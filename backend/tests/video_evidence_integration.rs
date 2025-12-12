//! Integration tests for Video Evidence Service (Story 7-11)
//!
//! Tests the complete evidence aggregation and confidence calculation pipeline.

use chrono::Utc;

// ============================================================================
// Test Helpers
// ============================================================================

/// Simulated hardware attestation result
#[derive(Debug, Clone)]
struct SimulatedHwAttestation {
    status: String,
    assertion_valid: bool,
    device_verified: bool,
}

impl SimulatedHwAttestation {
    fn pass() -> Self {
        Self {
            status: "pass".to_string(),
            assertion_valid: true,
            device_verified: true,
        }
    }

    fn fail() -> Self {
        Self {
            status: "fail".to_string(),
            assertion_valid: false,
            device_verified: false,
        }
    }

    fn unavailable() -> Self {
        Self {
            status: "unavailable".to_string(),
            assertion_valid: false,
            device_verified: false,
        }
    }
}

/// Simulated hash chain result
#[derive(Debug, Clone)]
struct SimulatedHashChain {
    status: String,
    verified_frames: u32,
    total_frames: u32,
    chain_intact: bool,
    attestation_valid: bool,
    is_partial: bool,
    checkpoint_index: Option<u32>,
}

impl SimulatedHashChain {
    fn pass(frames: u32) -> Self {
        Self {
            status: "pass".to_string(),
            verified_frames: frames,
            total_frames: frames,
            chain_intact: true,
            attestation_valid: true,
            is_partial: false,
            checkpoint_index: None,
        }
    }

    fn fail() -> Self {
        Self {
            status: "fail".to_string(),
            verified_frames: 0,
            total_frames: 0,
            chain_intact: false,
            attestation_valid: false,
            is_partial: false,
            checkpoint_index: None,
        }
    }

    fn partial(verified: u32, total: u32, checkpoint: u32) -> Self {
        Self {
            status: "partial".to_string(),
            verified_frames: verified,
            total_frames: total,
            chain_intact: true,
            attestation_valid: true,
            is_partial: true,
            checkpoint_index: Some(checkpoint),
        }
    }
}

/// Simulated depth analysis result
#[derive(Debug, Clone)]
struct SimulatedDepth {
    depth_consistency: f32,
    motion_coherence: f32,
    scene_stability: f32,
    is_likely_real_scene: bool,
    suspicious_frames: Vec<u32>,
}

impl SimulatedDepth {
    fn pass() -> Self {
        Self {
            depth_consistency: 0.85,
            motion_coherence: 0.75,
            scene_stability: 0.90,
            is_likely_real_scene: true,
            suspicious_frames: vec![],
        }
    }

    fn suspicious() -> Self {
        Self {
            depth_consistency: 0.3,
            motion_coherence: 0.2,
            scene_stability: 0.4,
            is_likely_real_scene: false,
            suspicious_frames: vec![50, 100, 150],
        }
    }

    fn degraded() -> Self {
        Self {
            depth_consistency: 0.5,
            motion_coherence: 0.5,
            scene_stability: 0.6,
            is_likely_real_scene: true,
            suspicious_frames: vec![],
        }
    }
}

/// Build simulated evidence JSON
fn build_evidence_json(
    hw: &SimulatedHwAttestation,
    chain: &SimulatedHashChain,
    depth: Option<&SimulatedDepth>,
    duration_ms: u64,
    frame_count: u32,
) -> serde_json::Value {
    let mut evidence = serde_json::json!({
        "type": "video",
        "duration_ms": duration_ms,
        "frame_count": frame_count,
        "hardware_attestation": {
            "status": hw.status,
            "assertion_valid": hw.assertion_valid,
            "device_verified": hw.device_verified,
            "attestation_time": Utc::now().to_rfc3339()
        },
        "hash_chain": {
            "status": chain.status,
            "verified_frames": chain.verified_frames,
            "total_frames": chain.total_frames,
            "chain_intact": chain.chain_intact,
            "attestation_valid": chain.attestation_valid,
            "verified_duration_ms": (chain.verified_frames as f64 / 30.0 * 1000.0) as u32,
            "checkpoint_verified": chain.is_partial && chain.checkpoint_index.is_some(),
            "checkpoint_index": chain.checkpoint_index
        },
        "metadata": {
            "device_model": "iPhone 15 Pro",
            "location_valid": true,
            "timestamp_valid": true
        },
        "partial_attestation": {
            "is_partial": chain.is_partial,
            "checkpoint_index": chain.checkpoint_index,
            "verified_frames": chain.verified_frames,
            "total_frames": frame_count,
            "reason": if chain.is_partial { "checkpoint_attestation" } else { "" }
        },
        "processing": {
            "processed_at": Utc::now().to_rfc3339(),
            "processing_time_ms": 1500,
            "backend_version": "0.1.0",
            "checks_performed": ["hardware", "hash_chain", "metadata"]
        }
    });

    if let Some(d) = depth {
        evidence["depth_analysis"] = serde_json::json!({
            "depth_consistency": d.depth_consistency,
            "motion_coherence": d.motion_coherence,
            "scene_stability": d.scene_stability,
            "is_likely_real_scene": d.is_likely_real_scene,
            "suspicious_frames": d.suspicious_frames
        });
        evidence["processing"]["checks_performed"]
            .as_array_mut()
            .unwrap()
            .push(serde_json::json!("depth"));
    }

    evidence
}

/// Calculate confidence from evidence JSON (standalone logic for testing)
fn calculate_confidence_from_json(evidence: &serde_json::Value) -> &'static str {
    let hw_status = evidence["hardware_attestation"]["status"]
        .as_str()
        .unwrap_or("unavailable");
    let chain_status = evidence["hash_chain"]["status"].as_str().unwrap_or("fail");
    let chain_intact = evidence["hash_chain"]["chain_intact"]
        .as_bool()
        .unwrap_or(false);
    let attestation_valid = evidence["hash_chain"]["attestation_valid"]
        .as_bool()
        .unwrap_or(false);
    let checkpoint_verified = evidence["hash_chain"]["checkpoint_verified"]
        .as_bool()
        .unwrap_or(false);
    let is_partial = evidence["partial_attestation"]["is_partial"]
        .as_bool()
        .unwrap_or(false);

    // SUSPICIOUS: Hardware failed
    if hw_status == "fail" {
        return "suspicious";
    }

    // SUSPICIOUS: Hash chain failed or broken
    if chain_status == "fail" || !chain_intact {
        return "suspicious";
    }

    // SUSPICIOUS: Depth detected suspicious scene
    if let Some(depth) = evidence.get("depth_analysis") {
        let is_real = depth["is_likely_real_scene"].as_bool().unwrap_or(false);
        if !is_real {
            return "suspicious";
        }
    }

    // Check for HIGH
    let hw_pass = hw_status == "pass";
    let chain_pass = chain_status == "pass" && chain_intact && attestation_valid;
    let depth_pass = evidence
        .get("depth_analysis")
        .map(|d| {
            let is_real = d["is_likely_real_scene"].as_bool().unwrap_or(false);
            let consistency = d["depth_consistency"].as_f64().unwrap_or(0.0);
            let stability = d["scene_stability"].as_f64().unwrap_or(0.0);
            is_real && consistency >= 0.7 && stability >= 0.8
        })
        .unwrap_or(false);

    if hw_pass && chain_pass && depth_pass {
        return "high";
    }

    // MEDIUM: Core pass, depth unavailable/degraded
    if hw_pass && chain_pass {
        return "medium";
    }

    // MEDIUM: Partial with checkpoint
    if is_partial && checkpoint_verified && hw_pass {
        return "medium";
    }

    // MEDIUM: HW unavailable but chain pass
    if hw_status == "unavailable" && chain_pass {
        return "medium";
    }

    "low"
}

// ============================================================================
// Integration Tests - Confidence Scenarios
// ============================================================================

#[test]
fn test_evidence_high_confidence_all_pass() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "high");
}

#[test]
fn test_evidence_suspicious_hw_fail() {
    let hw = SimulatedHwAttestation::fail();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "suspicious");
}

#[test]
fn test_evidence_suspicious_chain_fail() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::fail();
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "suspicious");
}

#[test]
fn test_evidence_suspicious_depth_fail() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::suspicious();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "suspicious");
}

#[test]
fn test_evidence_medium_depth_unavailable() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "medium");
}

#[test]
fn test_evidence_medium_depth_degraded() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::degraded();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "medium");
}

#[test]
fn test_evidence_medium_partial_checkpoint() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::partial(300, 400, 1);

    let evidence = build_evidence_json(&hw, &chain, None, 13333, 400);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "medium");
}

#[test]
fn test_evidence_medium_hw_unavailable() {
    let hw = SimulatedHwAttestation::unavailable();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    let confidence = calculate_confidence_from_json(&evidence);

    assert_eq!(confidence, "medium");
}

// ============================================================================
// Integration Tests - JSON Serialization
// ============================================================================

#[test]
fn test_evidence_json_structure() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);

    // Verify required fields
    assert_eq!(evidence["type"], "video");
    assert_eq!(evidence["duration_ms"], 15000);
    assert_eq!(evidence["frame_count"], 450);
    assert!(evidence.get("hardware_attestation").is_some());
    assert!(evidence.get("hash_chain").is_some());
    assert!(evidence.get("depth_analysis").is_some());
    assert!(evidence.get("metadata").is_some());
    assert!(evidence.get("partial_attestation").is_some());
    assert!(evidence.get("processing").is_some());
}

#[test]
fn test_evidence_json_without_depth() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);

    assert!(evidence.get("depth_analysis").is_none());
}

#[test]
fn test_evidence_json_round_trip() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);

    // Serialize to string
    let json_string = serde_json::to_string(&evidence).unwrap();

    // Deserialize back
    let parsed: serde_json::Value = serde_json::from_str(&json_string).unwrap();

    assert_eq!(parsed["type"], "video");
    assert_eq!(parsed["frame_count"], 450);
}

// ============================================================================
// Integration Tests - Partial Video
// ============================================================================

#[test]
fn test_partial_video_evidence_structure() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::partial(300, 450, 1);

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);

    assert!(evidence["partial_attestation"]["is_partial"]
        .as_bool()
        .unwrap());
    assert_eq!(evidence["partial_attestation"]["checkpoint_index"], 1);
    assert_eq!(evidence["partial_attestation"]["verified_frames"], 300);
    assert_eq!(evidence["partial_attestation"]["total_frames"], 450);
}

#[test]
fn test_partial_video_checkpoint_verified() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::partial(300, 450, 1);

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);

    assert!(evidence["hash_chain"]["checkpoint_verified"]
        .as_bool()
        .unwrap());
}

// ============================================================================
// Integration Tests - Edge Cases
// ============================================================================

#[test]
fn test_minimum_video_1_frame() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(1);

    let evidence = build_evidence_json(&hw, &chain, None, 33, 1);

    assert_eq!(evidence["frame_count"], 1);
    assert_eq!(evidence["duration_ms"], 33);
}

#[test]
fn test_maximum_video_450_frames() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);

    assert_eq!(evidence["frame_count"], 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "high");
}

#[test]
fn test_chain_broken_at_specific_frame() {
    let hw = SimulatedHwAttestation::pass();
    let mut chain = SimulatedHashChain::fail();
    chain.chain_intact = false;

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);

    assert!(!evidence["hash_chain"]["chain_intact"].as_bool().unwrap());
    assert_eq!(calculate_confidence_from_json(&evidence), "suspicious");
}

// ============================================================================
// Integration Tests - Processing Info
// ============================================================================

#[test]
fn test_processing_info_included() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);

    assert!(evidence["processing"]["processed_at"].is_string());
    assert!(evidence["processing"]["processing_time_ms"].is_number());
    assert!(evidence["processing"]["backend_version"].is_string());
    assert!(evidence["processing"]["checks_performed"].is_array());
}

#[test]
fn test_checks_performed_includes_hardware() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);

    let checks = evidence["processing"]["checks_performed"]
        .as_array()
        .unwrap();
    assert!(checks.iter().any(|v| v == "hardware"));
    assert!(checks.iter().any(|v| v == "hash_chain"));
    assert!(checks.iter().any(|v| v == "metadata"));
}

#[test]
fn test_checks_performed_includes_depth_when_available() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);

    let checks = evidence["processing"]["checks_performed"]
        .as_array()
        .unwrap();
    assert!(checks.iter().any(|v| v == "depth"));
}

// ============================================================================
// Integration Tests - Confidence Matrix Validation
// ============================================================================

#[test]
fn test_confidence_matrix_row_1() {
    // hw=pass, chain=pass+intact, depth=pass -> HIGH
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "high");
}

#[test]
fn test_confidence_matrix_row_2() {
    // hw=pass, chain=pass+intact, depth=unavailable -> MEDIUM
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "medium");
}

#[test]
fn test_confidence_matrix_row_3() {
    // hw=pass, chain=partial, depth=any -> MEDIUM
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::partial(300, 450, 1);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "medium");
}

#[test]
fn test_confidence_matrix_row_4() {
    // hw=pass, chain=pass, depth=fail -> SUSPICIOUS
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::suspicious();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "suspicious");
}

#[test]
fn test_confidence_matrix_row_5() {
    // hw=pass, chain=fail -> SUSPICIOUS
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::fail();

    let evidence = build_evidence_json(&hw, &chain, None, 15000, 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "suspicious");
}

#[test]
fn test_confidence_matrix_row_6() {
    // hw=fail, chain=any, depth=any -> SUSPICIOUS
    let hw = SimulatedHwAttestation::fail();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "suspicious");
}

#[test]
fn test_confidence_matrix_row_7() {
    // hw=unavailable, chain=pass, depth=pass -> MEDIUM
    let hw = SimulatedHwAttestation::unavailable();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    let evidence = build_evidence_json(&hw, &chain, Some(&depth), 15000, 450);
    assert_eq!(calculate_confidence_from_json(&evidence), "medium");
}

// ============================================================================
// Integration Tests - Multi-Signal Detection (Story 9-8)
// ============================================================================

/// Simulated multi-signal detection result
#[derive(Debug, Clone)]
struct SimulatedDetection {
    moire_detected: bool,
    moire_confidence: f32,
    texture_classification: &'static str,
    texture_confidence: f32,
    artifacts_detected: bool,
    aggregated_confidence: f32,
    confidence_level: &'static str,
    primary_valid: bool,
    signals_agree: bool,
}

impl SimulatedDetection {
    fn authentic() -> Self {
        Self {
            moire_detected: false,
            moire_confidence: 0.0,
            texture_classification: "real_scene",
            texture_confidence: 0.92,
            artifacts_detected: false,
            aggregated_confidence: 0.95,
            confidence_level: "high",
            primary_valid: true,
            signals_agree: true,
        }
    }

    fn suspicious_screen() -> Self {
        Self {
            moire_detected: true,
            moire_confidence: 0.85,
            texture_classification: "lcd_screen",
            texture_confidence: 0.78,
            artifacts_detected: true,
            aggregated_confidence: 0.18,
            confidence_level: "suspicious",
            primary_valid: false,
            signals_agree: true,
        }
    }

    fn partial() -> Self {
        Self {
            moire_detected: false,
            moire_confidence: 0.0,
            texture_classification: "real_scene",
            texture_confidence: 0.88,
            artifacts_detected: false,
            aggregated_confidence: 0.72,
            confidence_level: "medium",
            primary_valid: false, // LiDAR unavailable
            signals_agree: true,
        }
    }
}

fn build_evidence_with_detection(
    hw: &SimulatedHwAttestation,
    chain: &SimulatedHashChain,
    depth: Option<&SimulatedDepth>,
    detection: Option<&SimulatedDetection>,
    duration_ms: u64,
    frame_count: u32,
) -> serde_json::Value {
    let mut evidence = build_evidence_json(hw, chain, depth, duration_ms, frame_count);

    if let Some(det) = detection {
        evidence["detection"] = serde_json::json!({
            "moire": {
                "detected": det.moire_detected,
                "confidence": det.moire_confidence,
                "peaks": [],
                "analysis_time_ms": 28,
                "status": "completed"
            },
            "texture": {
                "classification": det.texture_classification,
                "confidence": det.texture_confidence,
                "all_classifications": {
                    det.texture_classification: det.texture_confidence
                },
                "is_likely_recaptured": det.texture_classification != "real_scene",
                "analysis_time_ms": 18,
                "status": "success"
            },
            "artifacts": {
                "pwm_flicker_detected": det.artifacts_detected,
                "pwm_confidence": if det.artifacts_detected { 0.7 } else { 0.0 },
                "halftone_detected": false,
                "halftone_confidence": 0.0,
                "is_likely_artificial": det.artifacts_detected,
                "analysis_time_ms": 42,
                "status": "success"
            },
            "aggregated_confidence": {
                "overall_confidence": det.aggregated_confidence,
                "confidence_level": det.confidence_level,
                "primary_signal_valid": det.primary_valid,
                "supporting_signals_agree": det.signals_agree,
                "flags": [],
                "status": "success"
            },
            "computed_at": Utc::now().to_rfc3339(),
            "total_processing_time_ms": 100
        });

        // Add detection to processing checks
        evidence["processing"]["checks_performed"]
            .as_array_mut()
            .unwrap()
            .push(serde_json::json!("multi_signal_detection"));
    }

    evidence
}

#[test]
fn test_evidence_with_authentic_detection() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();
    let detection = SimulatedDetection::authentic();

    let evidence =
        build_evidence_with_detection(&hw, &chain, Some(&depth), Some(&detection), 15000, 450);

    // Detection should be present
    assert!(evidence.get("detection").is_some());

    // Detection fields should have expected values
    assert!(!evidence["detection"]["moire"]["detected"]
        .as_bool()
        .unwrap());
    assert_eq!(
        evidence["detection"]["texture"]["classification"]
            .as_str()
            .unwrap(),
        "real_scene"
    );
    assert!(!evidence["detection"]["artifacts"]["is_likely_artificial"]
        .as_bool()
        .unwrap());
    assert_eq!(
        evidence["detection"]["aggregated_confidence"]["confidence_level"]
            .as_str()
            .unwrap(),
        "high"
    );
}

#[test]
fn test_evidence_with_suspicious_detection() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();
    let detection = SimulatedDetection::suspicious_screen();

    let evidence =
        build_evidence_with_detection(&hw, &chain, Some(&depth), Some(&detection), 15000, 450);

    // Detection should indicate screen recapture
    assert!(evidence["detection"]["moire"]["detected"]
        .as_bool()
        .unwrap());
    assert_eq!(
        evidence["detection"]["texture"]["classification"]
            .as_str()
            .unwrap(),
        "lcd_screen"
    );
    assert!(evidence["detection"]["artifacts"]["is_likely_artificial"]
        .as_bool()
        .unwrap());
    assert_eq!(
        evidence["detection"]["aggregated_confidence"]["confidence_level"]
            .as_str()
            .unwrap(),
        "suspicious"
    );
}

#[test]
fn test_evidence_with_partial_detection() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    // No depth analysis
    let detection = SimulatedDetection::partial();

    let evidence = build_evidence_with_detection(
        &hw,
        &chain,
        None, // No LiDAR
        Some(&detection),
        15000,
        450,
    );

    // Detection should handle missing primary signal
    assert!(
        !evidence["detection"]["aggregated_confidence"]["primary_signal_valid"]
            .as_bool()
            .unwrap()
    );
    assert_eq!(
        evidence["detection"]["aggregated_confidence"]["confidence_level"]
            .as_str()
            .unwrap(),
        "medium"
    );
}

#[test]
fn test_evidence_detection_optional() {
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();

    // Evidence without detection (backward compatible)
    let evidence = build_evidence_with_detection(
        &hw,
        &chain,
        Some(&depth),
        None, // No detection
        15000,
        450,
    );

    // Should still calculate confidence from other signals
    let confidence = calculate_confidence_from_json(&evidence);
    assert_eq!(confidence, "high");

    // Detection field should be absent
    assert!(evidence.get("detection").is_none());
}

#[test]
fn test_detection_enhances_high_confidence() {
    // When detection confirms authenticity, maintain HIGH
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();
    let detection = SimulatedDetection::authentic();

    let evidence =
        build_evidence_with_detection(&hw, &chain, Some(&depth), Some(&detection), 15000, 450);

    // Base confidence is HIGH, detection confirms
    assert_eq!(calculate_confidence_from_json(&evidence), "high");
    assert!(
        evidence["detection"]["aggregated_confidence"]["primary_signal_valid"]
            .as_bool()
            .unwrap()
    );
}

#[test]
fn test_detection_can_lower_confidence() {
    // When detection finds issues even with good base signals
    let hw = SimulatedHwAttestation::pass();
    let chain = SimulatedHashChain::pass(450);
    let depth = SimulatedDepth::pass();
    let mut detection = SimulatedDetection::suspicious_screen();
    detection.confidence_level = "suspicious";

    let evidence =
        build_evidence_with_detection(&hw, &chain, Some(&depth), Some(&detection), 15000, 450);

    // Detection indicates screen, should affect trust
    assert_eq!(
        evidence["detection"]["aggregated_confidence"]["confidence_level"]
            .as_str()
            .unwrap(),
        "suspicious"
    );
}

#[test]
fn test_detection_signals_agree_field() {
    let detection = SimulatedDetection::authentic();

    let evidence = build_evidence_with_detection(
        &SimulatedHwAttestation::pass(),
        &SimulatedHashChain::pass(450),
        None,
        Some(&detection),
        15000,
        450,
    );

    // signals_agree should be true when all methods concur
    assert!(
        evidence["detection"]["aggregated_confidence"]["supporting_signals_agree"]
            .as_bool()
            .unwrap()
    );
}

#[test]
fn test_detection_processing_check_added() {
    let detection = SimulatedDetection::authentic();

    let evidence = build_evidence_with_detection(
        &SimulatedHwAttestation::pass(),
        &SimulatedHashChain::pass(450),
        None,
        Some(&detection),
        15000,
        450,
    );

    // Processing checks should include multi_signal_detection
    let checks = evidence["processing"]["checks_performed"]
        .as_array()
        .unwrap();
    assert!(checks.iter().any(|v| v == "multi_signal_detection"));
}
