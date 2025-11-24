//! Capture routes (Story 4.1, 4.4)
//!
//! Implements capture upload and retrieval endpoints.
//!
//! ## Endpoints
//! - POST /api/v1/captures - Upload a new capture with photo, depth map, and metadata
//! - GET /api/v1/captures/{id} - Get capture by ID
//!
//! ## Authentication
//! All endpoints require device authentication via DeviceAuthLayer middleware.
//! DeviceContext is injected into request extensions.
//!
//! ## Attestation Verification (Story 4.4)
//! Capture uploads include optional per-capture assertions that are verified
//! against the device's registered public key. Verification failures do NOT
//! reject the upload - instead, the failure is recorded in the evidence package.

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use axum_extra::extract::Multipart;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::json;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::middleware::DeviceContext;
use crate::models::{Device, EvidencePackage, HardwareAttestation, ProcessingInfo};
use crate::routes::AppState;
use crate::services::{
    analyze_depth_map_from_bytes, process_location_for_evidence, validate_metadata,
    verify_capture_assertion,
};

/// Backend version for processing info (from Cargo.toml)
const BACKEND_VERSION: &str = env!("CARGO_PKG_VERSION");
use crate::types::{
    capture::{validate_depth_map_size, validate_photo_size},
    ApiResponse, CaptureMetadataPayload, CaptureUploadResponse,
};

// ============================================================================
// Router Setup
// ============================================================================
// Note: Rate limiting is handled by tower_governor middleware layer in routes/mod.rs

/// Creates the captures routes router.
///
/// Routes:
/// - POST / - Upload a new capture (protected by DeviceAuthLayer)
/// - GET /{id} - Get capture by ID (protected by DeviceAuthLayer)
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", post(upload_capture))
        .route("/{id}", get(get_capture))
}

// ============================================================================
// Multipart Parsing
// ============================================================================

/// Parsed multipart upload data
struct ParsedMultipart {
    photo_bytes: Vec<u8>,
    depth_map_bytes: Vec<u8>,
    metadata: CaptureMetadataPayload,
}

/// Parses multipart form data for capture upload
///
/// Extracts three parts:
/// - "photo" - JPEG image (max 10MB)
/// - "depth_map" - Gzipped depth data (max 5MB)
/// - "metadata" - JSON metadata payload
async fn parse_multipart(mut multipart: Multipart) -> Result<ParsedMultipart, ApiError> {
    let mut photo_bytes: Option<Vec<u8>> = None;
    let mut depth_map_bytes: Option<Vec<u8>> = None;
    let mut metadata: Option<CaptureMetadataPayload> = None;

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        tracing::warn!(error = %e, "Failed to read multipart field");
        ApiError::Validation(format!("Failed to read multipart form: {e}"))
    })? {
        let name = field.name().map(String::from);

        match name.as_deref() {
            Some("photo") => {
                let bytes = field.bytes().await.map_err(|e| {
                    tracing::warn!(error = %e, "Failed to read photo field");
                    ApiError::Validation("Failed to read photo data".to_string())
                })?;

                validate_photo_size(bytes.len())?;
                photo_bytes = Some(bytes.to_vec());

                tracing::debug!(size = bytes.len(), "Photo field parsed");
            }

            Some("depth_map") => {
                let bytes = field.bytes().await.map_err(|e| {
                    tracing::warn!(error = %e, "Failed to read depth_map field");
                    ApiError::Validation("Failed to read depth_map data".to_string())
                })?;

                validate_depth_map_size(bytes.len())?;
                depth_map_bytes = Some(bytes.to_vec());

                tracing::debug!(size = bytes.len(), "Depth map field parsed");
            }

            Some("metadata") => {
                let text = field.text().await.map_err(|e| {
                    tracing::warn!(error = %e, "Failed to read metadata field");
                    ApiError::Validation("Failed to read metadata".to_string())
                })?;

                let parsed: CaptureMetadataPayload = serde_json::from_str(&text).map_err(|e| {
                    tracing::warn!(error = %e, "Failed to parse metadata JSON");
                    ApiError::Validation(format!("Invalid metadata JSON: {e}"))
                })?;

                // Validate metadata fields
                parsed.validate()?;

                metadata = Some(parsed);

                tracing::debug!("Metadata field parsed and validated");
            }

            Some(other) => {
                tracing::debug!(field = other, "Ignoring unknown multipart field");
            }

            None => {
                tracing::debug!("Ignoring unnamed multipart field");
            }
        }
    }

    // Ensure all required parts are present
    let photo_bytes = photo_bytes
        .ok_or_else(|| ApiError::Validation("Missing required part: photo".to_string()))?;

    let depth_map_bytes = depth_map_bytes
        .ok_or_else(|| ApiError::Validation("Missing required part: depth_map".to_string()))?;

    let metadata = metadata
        .ok_or_else(|| ApiError::Validation("Missing required part: metadata".to_string()))?;

    Ok(ParsedMultipart {
        photo_bytes,
        depth_map_bytes,
        metadata,
    })
}

// ============================================================================
// Database Operations
// ============================================================================

/// Looks up a device by ID from the database (for assertion verification)
async fn lookup_device(pool: &PgPool, device_id: Uuid) -> Result<Device, ApiError> {
    let device = sqlx::query_as!(
        Device,
        r#"
        SELECT id, attestation_level, attestation_key_id, attestation_chain,
               platform, model, has_lidar, first_seen_at, last_seen_at,
               assertion_counter, public_key
        FROM devices
        WHERE id = $1
        "#,
        device_id
    )
    .fetch_optional(pool)
    .await?
    .ok_or(ApiError::DeviceNotFound)?;

    Ok(device)
}

/// Updates the device assertion counter after successful verification
async fn update_device_counter(
    pool: &PgPool,
    device_id: Uuid,
    new_counter: i64,
) -> Result<(), sqlx::Error> {
    sqlx::query!(
        r#"
        UPDATE devices
        SET assertion_counter = $2, last_seen_at = NOW()
        WHERE id = $1
        "#,
        device_id,
        new_counter
    )
    .execute(pool)
    .await?;

    Ok(())
}

/// Parameters for inserting a capture with evidence
struct InsertCaptureWithEvidenceParams {
    pub capture_id: Uuid,
    pub device_id: Uuid,
    pub target_media_hash: Vec<u8>,
    pub photo_s3_key: String,
    pub depth_map_s3_key: String,
    pub captured_at: chrono::DateTime<chrono::Utc>,
    pub location_precise: Option<serde_json::Value>,
    pub evidence: serde_json::Value,
    pub confidence_level: String,
}

/// Inserts a new capture record into the database with evidence
async fn insert_capture_with_evidence(
    pool: &PgPool,
    params: InsertCaptureWithEvidenceParams,
) -> Result<Uuid, ApiError> {
    // Use the capture_id from params (same ID used for S3 upload)
    let capture_id = params.capture_id;

    // Using query_scalar with explicit SQL to avoid compile-time schema dependency
    // This allows the code to compile before the migration is applied
    sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO captures (
            id, device_id, target_media_hash, photo_s3_key, depth_map_s3_key,
            evidence, confidence_level, status, location_precise, captured_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING id
        "#,
    )
    .bind(capture_id)
    .bind(params.device_id)
    .bind(&params.target_media_hash)
    .bind(&params.photo_s3_key)
    .bind(&params.depth_map_s3_key)
    .bind(&params.evidence)
    .bind(&params.confidence_level)
    .bind("complete") // Status set to complete after evidence pipeline (Story 4-7)
    .bind(&params.location_precise)
    .bind(params.captured_at)
    .fetch_one(pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to insert capture record");
        ApiError::Database(e)
    })
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/v1/captures - Upload a new capture
///
/// Accepts multipart form data with:
/// - photo: JPEG image (max 10MB)
/// - depth_map: Gzipped depth data (max 5MB)
/// - metadata: JSON metadata (including optional per-capture assertion)
///
/// Device authentication is handled by DeviceAuthLayer middleware.
///
/// ## Assertion Verification (Story 4.4)
/// If metadata contains an assertion, it is verified against the device's
/// registered public key. Verification failures do NOT reject the upload -
/// instead, the failure is recorded in the evidence package.
///
/// # Responses
/// - 202 Accepted: Capture uploaded successfully, processing queued
/// - 400 Bad Request: Validation error
/// - 401 Unauthorized: Device auth failed (handled by middleware)
/// - 413 Payload Too Large: Photo or depth map exceeds size limit
/// - 429 Too Many Requests: Rate limit exceeded (when enabled)
/// - 500 Internal Server Error: Storage or database error
async fn upload_capture(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Extension(device_ctx): Extension<DeviceContext>,
    multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<CaptureUploadResponse>>), ApiErrorWithRequestId> {
    // Start timing for processing info (Story 4-7)
    let processing_start = std::time::Instant::now();

    tracing::info!(
        request_id = %request_id,
        device_id = %device_ctx.device_id,
        device_model = %device_ctx.model,
        "Processing capture upload request"
    );

    // Note: Rate limiting is handled by tower_governor middleware layer

    // Parse multipart form data
    let parsed = parse_multipart(multipart)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    tracing::info!(
        request_id = %request_id,
        photo_size = parsed.photo_bytes.len(),
        depth_map_size = parsed.depth_map_bytes.len(),
        device_model = %parsed.metadata.device_model,
        has_assertion = parsed.metadata.assertion.is_some(),
        "Multipart data parsed successfully"
    );

    // ========================================================================
    // SECURITY FIX: Server-side hash verification
    // ========================================================================
    // Compute SHA256 to match mobile's method: hash the base64 STRING (not raw bytes).
    // Mobile does: digestStringAsync(SHA256, base64EncodedPhoto) which hashes the base64 text.
    // TODO: Fix mobile to hash raw bytes instead for proper security.
    let photo_base64 = STANDARD.encode(&parsed.photo_bytes);
    let computed_hash = Sha256::digest(photo_base64.as_bytes());
    let claimed_hash_bytes = STANDARD.decode(&parsed.metadata.photo_hash).map_err(|e| {
        tracing::warn!(
            request_id = %request_id,
            error = %e,
            "Invalid base64 encoding in photo_hash"
        );
        ApiErrorWithRequestId {
            error: ApiError::Validation("Invalid base64 encoding in photo_hash".to_string()),
            request_id,
        }
    })?;

    if computed_hash[..] != claimed_hash_bytes[..] {
        tracing::warn!(
            request_id = %request_id,
            device_id = %device_ctx.device_id,
            computed_hash = %STANDARD.encode(computed_hash),
            claimed_hash = %parsed.metadata.photo_hash,
            "Photo hash mismatch - rejecting upload"
        );
        return Err(ApiErrorWithRequestId {
            error: ApiError::Validation(
                "Photo hash does not match uploaded content. Ensure hash is SHA256 of photo bytes."
                    .to_string(),
            ),
            request_id,
        });
    }

    tracing::debug!(
        request_id = %request_id,
        hash = %parsed.metadata.photo_hash,
        "Photo hash verified successfully"
    );

    // Generate capture ID
    let capture_id = Uuid::new_v4();

    // Use shared storage service and config from AppState (connection-pooled)
    let storage = &state.storage;
    let config = &state.config;

    // Upload files to S3
    let (photo_s3_key, depth_map_s3_key) = storage
        .upload_capture_files(
            capture_id,
            parsed.photo_bytes.clone(),
            parsed.depth_map_bytes.clone(),
        )
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        photo_s3_key = %photo_s3_key,
        depth_map_s3_key = %depth_map_s3_key,
        "Files uploaded to S3"
    );

    // ========================================================================
    // STORY 4.4: Assertion Verification (after S3 upload)
    // ========================================================================
    // Verify the per-capture assertion against the device's registered public key.
    // This is NON-BLOCKING: failures do not reject the upload.

    // Lookup full device record (needed for public_key and assertion_counter)
    let device = lookup_device(&state.db, device_ctx.device_id)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    // Verify the capture assertion
    let assertion_result = verify_capture_assertion(
        &device,
        parsed.metadata.assertion.as_deref(),
        &parsed.metadata.photo_hash,
        &parsed.metadata.captured_at,
        config,
        request_id,
    );

    tracing::info!(
        request_id = %request_id,
        device_id = %device_ctx.device_id,
        assertion_status = ?assertion_result.status,
        assertion_verified = assertion_result.assertion_verified,
        counter_valid = assertion_result.counter_valid,
        new_counter = ?assertion_result.new_counter,
        "[capture_attestation] Assertion verification completed"
    );

    // Update device counter if verification succeeded
    if let Some(new_counter) = assertion_result.new_counter {
        if let Err(e) = update_device_counter(&state.db, device.id, new_counter as i64).await {
            // Log error but continue - counter update failure is not fatal
            tracing::error!(
                request_id = %request_id,
                device_id = %device.id,
                new_counter = new_counter,
                error = %e,
                "[capture_attestation] Failed to update device counter"
            );
        } else {
            tracing::debug!(
                request_id = %request_id,
                device_id = %device.id,
                new_counter = new_counter,
                "[capture_attestation] Device counter updated"
            );
        }
    }

    // Build hardware attestation evidence from assertion result
    let hardware_attestation: HardwareAttestation = assertion_result.into();

    // ========================================================================
    // STORY 4.5: LiDAR Depth Analysis
    // ========================================================================
    // Analyze the depth map to determine if scene is real vs flat (screen photo).
    // This is NON-BLOCKING: failures do not reject the upload.

    // Extract dimensions from metadata
    let depth_dimensions = Some((
        parsed.metadata.depth_map_dimensions.width,
        parsed.metadata.depth_map_dimensions.height,
    ));

    // Perform depth analysis - uses in-memory bytes to avoid redundant S3 download
    let depth_analysis = analyze_depth_map_from_bytes(&parsed.depth_map_bytes, depth_dimensions);

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        depth_status = ?depth_analysis.status,
        depth_variance = depth_analysis.depth_variance,
        depth_layers = depth_analysis.depth_layers,
        edge_coherence = depth_analysis.edge_coherence,
        is_likely_real_scene = depth_analysis.is_likely_real_scene,
        "[depth_analysis] Depth analysis completed"
    );

    // ========================================================================
    // End Story 4.5 additions
    // ========================================================================

    // ========================================================================
    // STORY 4.6: Metadata Validation
    // ========================================================================
    // Validate capture metadata (timestamp, device model, location, resolution).
    // This is NON-BLOCKING: failures do not reject the upload.

    let metadata_evidence = validate_metadata(&parsed.metadata);

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        timestamp_valid = metadata_evidence.timestamp_valid,
        timestamp_delta = metadata_evidence.timestamp_delta_seconds,
        model_verified = metadata_evidence.model_verified,
        resolution_valid = metadata_evidence.resolution_valid,
        location_available = metadata_evidence.location_available,
        "[metadata_validation] Metadata validation completed"
    );

    // ========================================================================
    // End Story 4.6 additions
    // ========================================================================

    // ========================================================================
    // STORY 4.8: Privacy Controls
    // ========================================================================
    // Apply location coarsening for privacy protection.
    // Precise location stored separately; coarse location in evidence package.

    let location_coarse = process_location_for_evidence(parsed.metadata.location.as_ref());

    // Update metadata evidence with coarsened location
    let mut metadata_evidence = metadata_evidence;
    metadata_evidence.location_coarse = location_coarse.clone();

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        location_coarse = ?location_coarse,
        location_opted_out = metadata_evidence.location_opted_out,
        "[privacy] Location privacy controls applied"
    );

    // ========================================================================
    // End Story 4.8 additions
    // ========================================================================

    // ========================================================================
    // STORY 4.7: Evidence Package & Processing Info
    // ========================================================================
    // Finalize evidence package with processing timing and version info.

    let processing_time_ms = processing_start.elapsed().as_millis() as u64;
    let processing_info = ProcessingInfo::new(processing_time_ms, BACKEND_VERSION);

    // Build complete evidence package
    let evidence_package = EvidencePackage {
        hardware_attestation,
        depth_analysis,
        metadata: metadata_evidence,
        processing: processing_info,
    };

    // Calculate confidence level based on evidence
    let confidence_level = evidence_package.calculate_confidence();

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        confidence_level = ?confidence_level,
        processing_time_ms = processing_time_ms,
        backend_version = BACKEND_VERSION,
        "[evidence_pipeline] Evidence package finalized"
    );

    // ========================================================================
    // End Story 4.7 additions
    // ========================================================================

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        confidence_level = ?confidence_level,
        hw_status = ?evidence_package.hardware_attestation.status,
        "[capture_attestation] Evidence package built"
    );

    // Serialize evidence to JSON for database storage
    let evidence_json = serde_json::to_value(&evidence_package).map_err(|e| {
        tracing::error!(error = %e, "Failed to serialize evidence package");
        ApiErrorWithRequestId {
            error: ApiError::Internal(anyhow::anyhow!("Failed to serialize evidence")),
            request_id,
        }
    })?;

    // ========================================================================
    // End Story 4.4 additions
    // ========================================================================

    // Use the server-computed hash (already verified above) as the authoritative hash
    // This ensures we store what we actually received, not what the client claimed
    let photo_hash_bytes = computed_hash.to_vec();

    // Prepare location data if present
    let location_precise = parsed.metadata.location.as_ref().map(|loc| {
        json!({
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "altitude": loc.altitude,
            "accuracy": loc.accuracy
        })
    });

    // Parse captured_at timestamp
    let captured_at =
        parsed
            .metadata
            .captured_at_datetime()
            .map_err(|e| ApiErrorWithRequestId {
                error: e,
                request_id,
            })?;

    // Cap confidence for unverified devices (Phase 3 hardening)
    // Devices that haven't passed full attestation verification cannot achieve High confidence
    let confidence_level = if !device_ctx.is_verified {
        match confidence_level {
            crate::models::ConfidenceLevel::High => {
                tracing::info!(
                    request_id = %request_id,
                    capture_id = %capture_id,
                    "Capping confidence from High to Medium for unverified device"
                );
                crate::models::ConfidenceLevel::Medium
            }
            other => other,
        }
    } else {
        confidence_level
    };

    // Create database record with evidence
    let confidence_str = match confidence_level {
        crate::models::ConfidenceLevel::High => "high",
        crate::models::ConfidenceLevel::Medium => "medium",
        crate::models::ConfidenceLevel::Low => "low",
        crate::models::ConfidenceLevel::Suspicious => "suspicious",
    };

    let db_capture_id = insert_capture_with_evidence(
        &state.db,
        InsertCaptureWithEvidenceParams {
            capture_id,  // Use the same ID that was used for S3 upload
            device_id: device_ctx.device_id,
            target_media_hash: photo_hash_bytes,
            photo_s3_key,
            depth_map_s3_key,
            captured_at,
            location_precise,
            evidence: evidence_json,
            confidence_level: confidence_str.to_string(),
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
        "Capture record created in database with evidence"
    );

    // Build response
    let verification_url = format!("{}/{db_capture_id}", config.verification_base_url);

    let response_data = CaptureUploadResponse {
        capture_id: db_capture_id,
        status: "complete".to_string(), // Evidence pipeline completed synchronously (Story 4-7)
        verification_url,
    };

    tracing::info!(
        request_id = %request_id,
        capture_id = %db_capture_id,
        "Capture upload completed successfully"
    );

    Ok((
        StatusCode::ACCEPTED,
        Json(ApiResponse::new(response_data, request_id)),
    ))
}

/// GET /api/v1/captures/{id} - Get capture by ID
///
/// Retrieves capture details and evidence by ID.
/// Returns the capture metadata, evidence package, and verification URL.
///
/// Access control: Only the device that created the capture can retrieve it.
async fn get_capture(
    State(state): State<AppState>,
    Extension(device_ctx): Extension<DeviceContext>,
    Extension(request_id): Extension<Uuid>,
    Path(id): Path<String>,
) -> Result<
    (
        StatusCode,
        Json<ApiResponse<crate::types::CaptureDetailsResponse>>,
    ),
    ApiErrorWithRequestId,
> {
    // Parse capture ID from path
    let capture_id = Uuid::parse_str(&id).map_err(|_| ApiErrorWithRequestId {
        error: ApiError::Validation(format!("Invalid capture ID format: {id}")),
        request_id,
    })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        device_id = %device_ctx.device_id,
        "Looking up capture"
    );

    // Query the capture from database
    let capture = sqlx::query_as!(
        crate::models::Capture,
        r#"
        SELECT id, device_id, target_media_hash, photo_s3_key, depth_map_s3_key,
               thumbnail_s3_key, evidence, confidence_level, status,
               location_precise, location_coarse, captured_at, uploaded_at
        FROM captures
        WHERE id = $1
        "#,
        capture_id
    )
    .fetch_optional(&state.db)
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: ApiError::Database(e),
        request_id,
    })?;

    let capture = capture.ok_or_else(|| ApiErrorWithRequestId {
        error: ApiError::CaptureNotFound,
        request_id,
    })?;

    // Access control: only the owning device can retrieve the capture
    if capture.device_id != device_ctx.device_id {
        tracing::warn!(
            request_id = %request_id,
            capture_id = %capture_id,
            capture_device_id = %capture.device_id,
            requesting_device_id = %device_ctx.device_id,
            "Access denied: device does not own capture"
        );
        return Err(ApiErrorWithRequestId {
            error: ApiError::Forbidden("You do not have access to this capture".to_string()),
            request_id,
        });
    }

    // Build verification URL
    let verification_url = format!("{}/{}", state.config.verification_base_url, capture_id);

    // Build response
    let response = crate::types::CaptureDetailsResponse {
        capture_id: capture.id,
        device_id: capture.device_id,
        confidence_level: capture.confidence_level,
        status: capture.status,
        evidence: capture.evidence,
        captured_at: capture.captured_at.to_rfc3339(),
        uploaded_at: capture.uploaded_at.to_rfc3339(),
        location_coarse: capture.location_coarse,
        verification_url,
    };

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        confidence_level = %response.confidence_level,
        "Capture retrieved successfully"
    );

    Ok((StatusCode::OK, Json(ApiResponse::new(response, request_id))))
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_verification_url_format() {
        let capture_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let base_url = "https://realitycam.app/verify";
        let url = format!("{base_url}/{capture_id}");
        assert_eq!(
            url,
            "https://realitycam.app/verify/550e8400-e29b-41d4-a716-446655440000"
        );
    }
}
