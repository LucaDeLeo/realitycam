//! Test seeding endpoints for E2E tests
//!
//! SECURITY: These endpoints are ONLY available when ENABLE_TEST_ENDPOINTS=true
//! They should NEVER be enabled in production environments.
//!
//! ## Endpoints
//! - POST /api/v1/test/evidence - Create synthetic evidence for testing
//! - DELETE /api/v1/test/evidence/:id - Delete test evidence

use axum::{
    extract::{Extension, Path, State},
    routing::{delete, post},
    Json, Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::models::{
    AttestationLevel, CheckStatus, DepthAnalysis, EvidencePackage, HardwareAttestation,
    MetadataEvidence, ProcessingInfo,
};
use crate::routes::AppState;
use crate::types::ApiResponse;

// ============================================================================
// Request/Response Types
// ============================================================================

/// Depth analysis input from test factory
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DepthAnalysisInput {
    pub has_depth: bool,
    pub depth_layers: u32,
    #[serde(default)]
    pub variance: f64,
    #[serde(default)]
    pub coherence: f64,
}

/// C2PA input from test factory
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct C2paInput {
    pub has_claim: bool,
    pub claim_generator: String,
    pub signature_valid: bool,
}

/// Metadata input from test factory
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetadataInput {
    pub timestamp: String,
    pub device_model: String,
    #[serde(default)]
    pub latitude: Option<f64>,
    #[serde(default)]
    pub longitude: Option<f64>,
}

/// Request body for creating test evidence
/// Matches the structure sent by EvidenceFactory in Playwright tests
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateTestEvidenceRequest {
    pub confidence_score: f64,
    pub status: String,
    pub depth_analysis: DepthAnalysisInput,
    pub c2pa: C2paInput,
    pub metadata: MetadataInput,
}

/// Response for created test evidence
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TestEvidenceResponse {
    pub id: String,
    pub capture_id: String,
    pub device_id: String,
    pub confidence_score: f64,
    pub status: String,
    pub depth_analysis: TestDepthAnalysisResponse,
    pub c2pa: TestC2paResponse,
    pub metadata: TestMetadataResponse,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TestDepthAnalysisResponse {
    pub has_depth: bool,
    pub depth_layers: u32,
    pub variance: f64,
    pub coherence: f64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TestC2paResponse {
    pub has_claim: bool,
    pub claim_generator: String,
    pub signature_valid: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TestMetadataResponse {
    pub timestamp: String,
    pub device_model: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub longitude: Option<f64>,
}

// ============================================================================
// Router Setup
// ============================================================================

/// Creates the test routes router.
/// These routes are for E2E test data seeding only.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/evidence", post(create_test_evidence))
        .route("/evidence/{id}", delete(delete_test_evidence))
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/v1/test/evidence - Create synthetic test evidence
///
/// Creates a capture record with the provided evidence data.
/// Used by Playwright E2E tests to seed test data.
///
/// SECURITY: Only available when ENABLE_TEST_ENDPOINTS=true
async fn create_test_evidence(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Json(req): Json<CreateTestEvidenceRequest>,
) -> Result<Json<ApiResponse<TestEvidenceResponse>>, ApiErrorWithRequestId> {
    tracing::info!(
        request_id = %request_id,
        confidence_score = req.confidence_score,
        status = %req.status,
        "Creating test evidence"
    );

    // Generate IDs
    let capture_id = Uuid::new_v4();
    let device_id = Uuid::new_v4();

    // First, create a test device (required due to foreign key constraint)
    sqlx::query!(
        r#"
        INSERT INTO devices (
            id, attestation_level, attestation_key_id, platform, model,
            has_lidar, first_seen_at, last_seen_at, assertion_counter
        )
        VALUES ($1, 'secure_enclave', $2, 'iOS', $3, true, NOW(), NOW(), 0)
        ON CONFLICT (attestation_key_id) DO UPDATE SET last_seen_at = NOW()
        "#,
        device_id,
        format!("test-key-{}", device_id),
        req.metadata.device_model,
    )
    .execute(&state.db)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to create test device");
        ApiErrorWithRequestId {
            error: ApiError::Database(e),
            request_id,
        }
    })?;

    // Build evidence package matching the real structure
    let depth_status = if req.depth_analysis.has_depth {
        CheckStatus::Pass
    } else {
        CheckStatus::Unavailable
    };

    let hw_status = if req.c2pa.signature_valid {
        CheckStatus::Pass
    } else if req.c2pa.has_claim {
        CheckStatus::Fail
    } else {
        CheckStatus::Unavailable
    };

    let evidence = EvidencePackage {
        hardware_attestation: HardwareAttestation {
            status: hw_status,
            level: AttestationLevel::SecureEnclave,
            device_model: req.metadata.device_model.clone(),
            assertion_verified: req.c2pa.signature_valid,
            counter_valid: req.c2pa.signature_valid,
            security_level: None, // Story 10-2: Test endpoint doesn't need security level
        },
        depth_analysis: DepthAnalysis {
            status: depth_status,
            depth_variance: req.depth_analysis.variance,
            depth_layers: req.depth_analysis.depth_layers,
            edge_coherence: req.depth_analysis.coherence,
            min_depth: 0.5,
            max_depth: 5.0,
            is_likely_real_scene: req.depth_analysis.has_depth
                && req.depth_analysis.depth_layers > 1,
            source: None,
        },
        metadata: MetadataEvidence {
            timestamp_valid: true,
            timestamp_delta_seconds: 0,
            model_verified: true,
            model_name: req.metadata.device_model.clone(),
            resolution_valid: true,
            location_available: req.metadata.latitude.is_some(),
            location_opted_out: false,
            location_coarse: None,
        },
        processing: ProcessingInfo::new(100, env!("CARGO_PKG_VERSION")),
    };

    // Calculate confidence level from score
    let confidence_level = match req.confidence_score {
        s if s >= 0.8 => "high",
        s if s >= 0.5 => "medium",
        s if s >= 0.3 => "low",
        _ => "suspicious",
    };

    // Serialize evidence to JSON
    let evidence_json = serde_json::to_value(&evidence).map_err(|e| ApiErrorWithRequestId {
        error: ApiError::Internal(anyhow::anyhow!("Failed to serialize evidence: {e}")),
        request_id,
    })?;

    // Generate a fake hash for the test capture
    let fake_hash = format!("test-{capture_id}");
    let hash_bytes = fake_hash.as_bytes().to_vec();

    // Parse captured_at timestamp
    let captured_at = chrono::DateTime::parse_from_rfc3339(&req.metadata.timestamp)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now());

    // Build location JSON if provided
    let location_precise = match (req.metadata.latitude, req.metadata.longitude) {
        (Some(lat), Some(lon)) => Some(serde_json::json!({
            "latitude": lat,
            "longitude": lon,
            "accuracy": 10.0
        })),
        _ => None,
    };

    // Insert into database
    sqlx::query!(
        r#"
        INSERT INTO captures (
            id, device_id, target_media_hash, evidence, confidence_level,
            status, captured_at, uploaded_at, location_precise
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $8)
        "#,
        capture_id,
        device_id,
        hash_bytes,
        evidence_json,
        confidence_level,
        req.status,
        captured_at,
        location_precise,
    )
    .execute(&state.db)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to insert test evidence");
        ApiErrorWithRequestId {
            error: ApiError::Database(e),
            request_id,
        }
    })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        "Test evidence created successfully"
    );

    let response = TestEvidenceResponse {
        id: capture_id.to_string(),
        capture_id: capture_id.to_string(),
        device_id: device_id.to_string(),
        confidence_score: req.confidence_score,
        status: req.status,
        depth_analysis: TestDepthAnalysisResponse {
            has_depth: req.depth_analysis.has_depth,
            depth_layers: req.depth_analysis.depth_layers,
            variance: req.depth_analysis.variance,
            coherence: req.depth_analysis.coherence,
        },
        c2pa: TestC2paResponse {
            has_claim: req.c2pa.has_claim,
            claim_generator: req.c2pa.claim_generator,
            signature_valid: req.c2pa.signature_valid,
        },
        metadata: TestMetadataResponse {
            timestamp: req.metadata.timestamp,
            device_model: req.metadata.device_model,
            latitude: req.metadata.latitude,
            longitude: req.metadata.longitude,
        },
    };

    Ok(Json(ApiResponse::new(response, request_id)))
}

/// DELETE /api/v1/test/evidence/:id - Delete test evidence
///
/// Removes a capture record created by the test seeding endpoint.
/// Used by Playwright E2E tests for cleanup.
///
/// SECURITY: Only available when ENABLE_TEST_ENDPOINTS=true
async fn delete_test_evidence(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Path(id): Path<String>,
) -> Result<Json<ApiResponse<()>>, ApiErrorWithRequestId> {
    // Parse capture ID
    let capture_id = Uuid::parse_str(&id).map_err(|_| ApiErrorWithRequestId {
        error: ApiError::Validation(format!("Invalid capture ID format: {id}")),
        request_id,
    })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        "Deleting test evidence"
    );

    // First get the device_id for this capture so we can clean it up too
    let capture_record = sqlx::query!(
        r#"SELECT device_id FROM captures WHERE id = $1"#,
        capture_id
    )
    .fetch_optional(&state.db)
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: ApiError::Database(e),
        request_id,
    })?;

    // Delete the capture
    let result = sqlx::query!(r#"DELETE FROM captures WHERE id = $1"#, capture_id)
        .execute(&state.db)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to delete test evidence");
            ApiErrorWithRequestId {
                error: ApiError::Database(e),
                request_id,
            }
        })?;

    // Also clean up the test device if no other captures reference it
    if let Some(record) = capture_record {
        let _ = sqlx::query!(
            r#"
            DELETE FROM devices
            WHERE id = $1
            AND attestation_key_id LIKE 'test-key-%'
            AND NOT EXISTS (SELECT 1 FROM captures WHERE device_id = $1)
            "#,
            record.device_id
        )
        .execute(&state.db)
        .await;
    }

    if result.rows_affected() == 0 {
        tracing::warn!(
            request_id = %request_id,
            capture_id = %capture_id,
            "Test evidence not found for deletion (may already be deleted)"
        );
    } else {
        tracing::info!(
            request_id = %request_id,
            capture_id = %capture_id,
            "Test evidence deleted successfully"
        );
    }

    Ok(Json(ApiResponse::new((), request_id)))
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deserialize_create_request() {
        let json = r#"{
            "confidenceScore": 0.85,
            "status": "complete",
            "depthAnalysis": {
                "hasDepth": true,
                "depthLayers": 4,
                "variance": 0.42,
                "coherence": 0.78
            },
            "c2pa": {
                "hasClaim": true,
                "claimGenerator": "RealityCam/1.0",
                "signatureValid": true
            },
            "metadata": {
                "timestamp": "2024-01-01T12:00:00Z",
                "deviceModel": "iPhone 15 Pro"
            }
        }"#;

        let request: CreateTestEvidenceRequest = serde_json::from_str(json).unwrap();
        assert!((request.confidence_score - 0.85).abs() < f64::EPSILON);
        assert_eq!(request.status, "complete");
        assert!(request.depth_analysis.has_depth);
        assert_eq!(request.depth_analysis.depth_layers, 4);
        assert!(request.c2pa.signature_valid);
        assert_eq!(request.metadata.device_model, "iPhone 15 Pro");
    }

    #[test]
    fn test_serialize_response() {
        let response = TestEvidenceResponse {
            id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            capture_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            device_id: "660e8400-e29b-41d4-a716-446655440000".to_string(),
            confidence_score: 0.85,
            status: "complete".to_string(),
            depth_analysis: TestDepthAnalysisResponse {
                has_depth: true,
                depth_layers: 4,
                variance: 0.42,
                coherence: 0.78,
            },
            c2pa: TestC2paResponse {
                has_claim: true,
                claim_generator: "RealityCam/1.0".to_string(),
                signature_valid: true,
            },
            metadata: TestMetadataResponse {
                timestamp: "2024-01-01T12:00:00Z".to_string(),
                device_model: "iPhone 15 Pro".to_string(),
                latitude: None,
                longitude: None,
            },
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"confidenceScore\":0.85"));
        assert!(json.contains("\"hasDepth\":true"));
        assert!(json.contains("\"depthLayers\":4"));
    }
}
