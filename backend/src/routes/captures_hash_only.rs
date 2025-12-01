//! Hash-only capture routes (Story 8-4)
//!
//! Implements the hash-only capture endpoint for privacy-first mode.
//! In this mode, clients submit only a hash of the media along with
//! pre-computed depth analysis - the actual media never touches the server.
//!
//! ## Endpoint
//! - POST /api/v1/captures/hash-only - Accept hash-only capture with client analysis
//!
//! ## Key Differences from Full Captures
//! - JSON body (not multipart) - no media files uploaded
//! - Assertion verification is BLOCKING (returns 401 on failure)
//! - No S3 storage operations - significantly faster processing
//! - Depth analysis comes from client, not computed server-side

use axum::{
    extract::{Extension, State},
    http::StatusCode,
    routing::post,
    Json, Router,
};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::middleware::{lookup_device, update_device_counter, DeviceContext};
use crate::models::{
    CheckStatus, ConfidenceLevel, DepthAnalysis, EvidencePackage, HardwareAttestation,
    MetadataEvidence, ProcessingInfo,
};
use crate::routes::AppState;
use crate::services::verify_hash_only_assertion;
use crate::types::{
    ApiResponse, HashOnlyCapturePayload, HashOnlyCaptureResponse, InsertHashOnlyCaptureParams,
};

/// Backend version for processing info
const BACKEND_VERSION: &str = env!("CARGO_PKG_VERSION");

// ============================================================================
// Router Setup
// ============================================================================

/// Creates the hash-only captures routes router.
///
/// Routes:
/// - POST / - Accept hash-only capture (protected by DeviceAuthLayer)
pub fn router() -> Router<AppState> {
    Router::new().route("/", post(upload_hash_only_capture))
}

// ============================================================================
// Database Operations
// ============================================================================

/// Inserts a hash-only capture record into the database
async fn insert_hash_only_capture(
    pool: &PgPool,
    params: InsertHashOnlyCaptureParams,
) -> Result<Uuid, ApiError> {
    let capture_id = params.capture_id;

    // Using query_scalar with explicit SQL for the new schema
    sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO captures (
            id, device_id, target_media_hash, evidence, confidence_level, status,
            captured_at, capture_mode, media_stored, analysis_source, metadata_flags,
            location_coarse
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        RETURNING id
        "#,
    )
    .bind(capture_id)
    .bind(params.device_id)
    .bind(&params.target_media_hash)
    .bind(&params.evidence)
    .bind(&params.confidence_level)
    .bind("complete") // Hash-only captures complete synchronously
    .bind(params.captured_at)
    .bind("hash_only") // capture_mode
    .bind(false) // media_stored
    .bind("device") // analysis_source
    .bind(&params.metadata_flags)
    .bind(&params.location_coarse)
    .fetch_one(pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to insert hash-only capture record");
        ApiError::Database(e)
    })
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/v1/captures/hash-only - Accept hash-only capture
///
/// Accepts a JSON body with:
/// - capture_mode: "hash_only"
/// - media_hash: SHA-256 of the photo (hex string)
/// - media_type: "photo" (video in Story 8-8)
/// - depth_analysis: Client-computed depth analysis results
/// - metadata: Filtered metadata per privacy settings
/// - metadata_flags: Flags indicating what was included
/// - captured_at: ISO8601 timestamp
/// - assertion: DCAppAttest assertion (Base64 CBOR)
///
/// ## Security
/// Device authentication via DeviceAuthLayer middleware.
/// Assertion verification is BLOCKING - 401 on failure.
///
/// # Responses
/// - 202 Accepted: Capture processed successfully
/// - 400 Bad Request: Validation error
/// - 401 Unauthorized: Device auth failed or assertion invalid
async fn upload_hash_only_capture(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Extension(device_ctx): Extension<DeviceContext>,
    Json(payload): Json<HashOnlyCapturePayload>,
) -> Result<(StatusCode, Json<ApiResponse<HashOnlyCaptureResponse>>), ApiErrorWithRequestId> {
    // Start timing for processing info
    let processing_start = std::time::Instant::now();

    tracing::info!(
        request_id = %request_id,
        device_id = %device_ctx.device_id,
        device_model = %device_ctx.model,
        media_hash = %payload.media_hash,
        capture_mode = %payload.capture_mode,
        "[hash_only] Processing hash-only capture request"
    );

    // ========================================================================
    // AC 2: Payload Validation
    // ========================================================================
    payload.validate().map_err(|e| {
        tracing::warn!(
            request_id = %request_id,
            error = %e,
            "[hash_only] Payload validation failed"
        );
        ApiErrorWithRequestId {
            error: e,
            request_id,
        }
    })?;

    tracing::debug!(
        request_id = %request_id,
        "[hash_only] Payload validation passed"
    );

    // ========================================================================
    // AC 3: DCAppAttest Assertion Verification (BLOCKING)
    // ========================================================================
    // For hash-only captures, assertion failure returns 401 (not recorded in evidence)
    // because the assertion is the only proof of authenticity.

    // Lookup full device record for public key and counter
    let device = lookup_device(&state.db, device_ctx.device_id)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    let assertion_result = verify_hash_only_assertion(&device, &payload, &state.config, request_id)
        .map_err(|e| {
            tracing::warn!(
                request_id = %request_id,
                device_id = %device_ctx.device_id,
                error = %e,
                "[hash_only] Assertion verification failed - rejecting request"
            );
            ApiErrorWithRequestId {
                error: ApiError::AttestationFailed(e.to_string()),
                request_id,
            }
        })?;

    tracing::info!(
        request_id = %request_id,
        device_id = %device_ctx.device_id,
        assertion_verified = assertion_result.assertion_verified,
        counter_valid = assertion_result.counter_valid,
        new_counter = ?assertion_result.new_counter,
        "[hash_only] Assertion verification passed"
    );

    // Update device counter on successful verification
    if let Some(new_counter) = assertion_result.new_counter {
        if let Err(e) = update_device_counter(&state.db, device.id, new_counter as i64).await {
            tracing::error!(
                request_id = %request_id,
                device_id = %device.id,
                new_counter = new_counter,
                error = %e,
                "[hash_only] Failed to update device counter"
            );
        } else {
            tracing::debug!(
                request_id = %request_id,
                device_id = %device.id,
                new_counter = new_counter,
                "[hash_only] Device counter updated"
            );
        }
    }

    // ========================================================================
    // AC 6: Build Evidence Package
    // ========================================================================

    // Build hardware attestation from assertion result
    let hardware_attestation: HardwareAttestation = assertion_result.into();

    // Build depth analysis from client-provided data (AC 6.3: source="device")
    let depth_analysis = DepthAnalysis {
        status: if payload.depth_analysis.is_likely_real_scene {
            CheckStatus::Pass
        } else {
            // Note: is_likely_real_scene=false does NOT reject - just recorded
            CheckStatus::Fail
        },
        depth_variance: payload.depth_analysis.depth_variance as f64,
        depth_layers: payload.depth_analysis.depth_layers as u32,
        edge_coherence: payload.depth_analysis.edge_coherence as f64,
        min_depth: payload.depth_analysis.min_depth as f64,
        max_depth: payload.depth_analysis.max_depth as f64,
        is_likely_real_scene: payload.depth_analysis.is_likely_real_scene,
    };

    // Build metadata evidence from filtered metadata
    let metadata_evidence = build_metadata_evidence(&payload);

    // Calculate processing time
    let processing_time_ms = processing_start.elapsed().as_millis() as u64;
    let processing_info = ProcessingInfo::new(processing_time_ms, BACKEND_VERSION);

    // Assemble evidence package
    let evidence_package = EvidencePackage {
        hardware_attestation,
        depth_analysis,
        metadata: metadata_evidence,
        processing: processing_info,
    };

    // Calculate confidence level
    let confidence_level = evidence_package.calculate_confidence();

    tracing::info!(
        request_id = %request_id,
        confidence_level = ?confidence_level,
        processing_time_ms = processing_time_ms,
        "[hash_only] Evidence package assembled"
    );

    // ========================================================================
    // AC 4: Database Storage
    // ========================================================================

    // Generate capture ID
    let capture_id = Uuid::new_v4();

    // Convert media hash from hex to bytes
    let target_media_hash = payload
        .media_hash_bytes()
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    // Parse captured_at timestamp
    let captured_at = payload
        .captured_at_datetime()
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    // Serialize evidence package
    let evidence_json = serde_json::to_value(&evidence_package).map_err(|e| {
        tracing::error!(error = %e, "Failed to serialize evidence package");
        ApiErrorWithRequestId {
            error: ApiError::Internal(anyhow::anyhow!("Failed to serialize evidence")),
            request_id,
        }
    })?;

    // Serialize metadata flags
    let metadata_flags_json = serde_json::to_value(&payload.metadata_flags).map_err(|e| {
        tracing::error!(error = %e, "Failed to serialize metadata flags");
        ApiErrorWithRequestId {
            error: ApiError::Internal(anyhow::anyhow!("Failed to serialize metadata flags")),
            request_id,
        }
    })?;

    // Extract coarse location if available
    let location_coarse = extract_coarse_location(&payload);

    // Convert confidence to string
    let confidence_str = match confidence_level {
        ConfidenceLevel::High => "high",
        ConfidenceLevel::Medium => "medium",
        ConfidenceLevel::Low => "low",
        ConfidenceLevel::Suspicious => "suspicious",
    };

    // Insert capture record
    let db_capture_id = insert_hash_only_capture(
        &state.db,
        InsertHashOnlyCaptureParams {
            capture_id,
            device_id: device_ctx.device_id,
            target_media_hash,
            captured_at,
            evidence: evidence_json,
            confidence_level: confidence_str.to_string(),
            metadata_flags: metadata_flags_json,
            location_coarse,
        },
    )
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: e,
        request_id,
    })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %db_capture_id,
        device_id = %device_ctx.device_id,
        confidence_level = confidence_str,
        "[hash_only] Capture record created"
    );

    // ========================================================================
    // AC 5: Verify No S3 Upload (implicit - we simply don't call StorageService)
    // ========================================================================

    // ========================================================================
    // AC 7: Build Response
    // ========================================================================

    let verification_url = format!("{}/{db_capture_id}", state.config.verification_base_url);

    let response_data = HashOnlyCaptureResponse {
        capture_id: db_capture_id,
        status: "complete".to_string(),
        capture_mode: "hash_only".to_string(),
        media_stored: false,
        verification_url,
    };

    let total_time_ms = processing_start.elapsed().as_millis();
    tracing::info!(
        request_id = %request_id,
        capture_id = %db_capture_id,
        total_time_ms = total_time_ms,
        "[hash_only] Request completed successfully"
    );

    Ok((
        StatusCode::ACCEPTED,
        Json(ApiResponse::new(response_data, request_id)),
    ))
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Builds MetadataEvidence from the filtered metadata in the payload
fn build_metadata_evidence(payload: &HashOnlyCapturePayload) -> MetadataEvidence {
    let timestamp_valid = payload.metadata_flags.timestamp_included;
    let model_verified = payload.metadata_flags.device_info_included;
    let location_available = payload.metadata_flags.location_included;

    MetadataEvidence {
        timestamp_valid,
        timestamp_delta_seconds: 0, // Not applicable for hash-only (client timestamp)
        model_verified,
        model_name: payload
            .metadata
            .device_model
            .clone()
            .unwrap_or_else(|| "Unknown".to_string()),
        resolution_valid: true, // Assume valid for hash-only (client verified)
        location_available,
        location_opted_out: !location_available,
        location_coarse: None, // Set separately if available
    }
}

/// Extracts coarse location string from filtered metadata if available
fn extract_coarse_location(payload: &HashOnlyCapturePayload) -> Option<String> {
    if !payload.metadata_flags.location_included {
        return None;
    }

    payload.metadata.location.as_ref().map(|loc| {
        // Generate coarse location based on privacy level
        match payload.metadata_flags.location_level.as_str() {
            "coarse" => format!("~{:.1}, ~{:.1}", loc.latitude, loc.longitude),
            "precise" => format!("{:.4}, {:.4}", loc.latitude, loc.longitude),
            _ => "Location available".to_string(),
        }
    })
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{ClientDepthAnalysis, FilteredMetadata, MetadataFlags};
    use base64::Engine;

    fn test_payload() -> HashOnlyCapturePayload {
        HashOnlyCapturePayload {
            capture_mode: "hash_only".to_string(),
            media_hash: "a".repeat(64),
            media_type: "photo".to_string(),
            depth_analysis: ClientDepthAnalysis {
                depth_variance: 0.5,
                depth_layers: 5,
                edge_coherence: 0.8,
                min_depth: 0.5,
                max_depth: 5.0,
                is_likely_real_scene: true,
                algorithm_version: "1.0".to_string(),
            },
            metadata: FilteredMetadata::default(),
            metadata_flags: MetadataFlags {
                location_included: false,
                location_level: "none".to_string(),
                timestamp_included: true,
                timestamp_level: "exact".to_string(),
                device_info_included: true,
                device_info_level: "model_only".to_string(),
            },
            captured_at: "2025-12-01T10:00:00Z".to_string(),
            assertion: base64::engine::general_purpose::STANDARD.encode("test-assertion"),
            hash_chain: None,
            frame_count: None,
            duration_ms: None,
        }
    }

    #[test]
    fn test_build_metadata_evidence_no_location() {
        let payload = test_payload();
        let evidence = build_metadata_evidence(&payload);

        assert!(evidence.timestamp_valid);
        assert!(evidence.model_verified);
        assert!(!evidence.location_available);
        assert!(evidence.location_opted_out);
    }

    #[test]
    fn test_build_metadata_evidence_with_location() {
        let mut payload = test_payload();
        payload.metadata_flags.location_included = true;
        payload.metadata_flags.location_level = "coarse".to_string();
        payload.metadata.location = Some(crate::types::FilteredLocation {
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: None,
            accuracy: None,
        });

        let evidence = build_metadata_evidence(&payload);

        assert!(evidence.location_available);
        assert!(!evidence.location_opted_out);
    }

    #[test]
    fn test_extract_coarse_location_none() {
        let payload = test_payload();
        let location = extract_coarse_location(&payload);
        assert!(location.is_none());
    }

    #[test]
    fn test_extract_coarse_location_coarse() {
        let mut payload = test_payload();
        payload.metadata_flags.location_included = true;
        payload.metadata_flags.location_level = "coarse".to_string();
        payload.metadata.location = Some(crate::types::FilteredLocation {
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: None,
            accuracy: None,
        });

        let location = extract_coarse_location(&payload);
        assert!(location.is_some());
        let loc_str = location.unwrap();
        assert!(loc_str.contains("~37.8"));
        assert!(loc_str.contains("~-122.4"));
    }
}
