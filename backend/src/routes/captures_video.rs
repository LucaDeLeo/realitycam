//! Video capture routes (Story 7-8)
//!
//! Implements video upload endpoint for the captures API.
//!
//! ## Endpoints
//! - POST /api/v1/captures/video - Upload a new video capture with depth and hash chain
//!
//! ## Authentication
//! All endpoints require device authentication via DeviceAuthLayer middleware.
//! DeviceContext is injected into request extensions.
//!
//! ## Rate Limiting
//! Video uploads are rate limited to 5 per hour per device to prevent abuse.
//! Returns 429 Too Many Requests with Retry-After header when exceeded.

use axum::{
    extract::{Extension, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use axum_extra::extract::Multipart;
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::middleware::DeviceContext;
use crate::routes::AppState;
use crate::types::{
    validate_hash_chain_size, validate_video_depth_size, validate_video_metadata_size,
    validate_video_size, ApiErrorResponse, ApiResponse, VideoUploadMetadata, VideoUploadResponse,
    VIDEO_RATE_LIMIT_PER_HOUR,
};

// ============================================================================
// Router Setup
// ============================================================================

/// Creates the video captures routes router.
///
/// Routes:
/// - POST / - Upload a new video capture (protected by DeviceAuthLayer)
pub fn router() -> Router<AppState> {
    Router::new().route("/", post(upload_video))
}

// ============================================================================
// Multipart Parsing
// ============================================================================

/// Parsed video multipart upload data
struct ParsedVideoMultipart {
    video_bytes: Vec<u8>,
    depth_bytes: Vec<u8>,
    hash_chain_bytes: Vec<u8>,
    metadata: VideoUploadMetadata,
}

/// Parses multipart form data for video capture upload
///
/// Extracts four parts:
/// - "video" - MP4/MOV binary (max 100MB)
/// - "depth_data" - Gzipped depth keyframes (max 20MB)
/// - "hash_chain" - JSON with frame hashes (max 1MB)
/// - "metadata" - JSON metadata payload (max 100KB)
async fn parse_video_multipart(mut multipart: Multipart) -> Result<ParsedVideoMultipart, ApiError> {
    let mut video_bytes: Option<Vec<u8>> = None;
    let mut depth_bytes: Option<Vec<u8>> = None;
    let mut hash_chain_bytes: Option<Vec<u8>> = None;
    let mut metadata: Option<VideoUploadMetadata> = None;

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        tracing::warn!(error = %e, "Failed to read multipart field");
        ApiError::Validation(format!("Failed to read multipart form: {e}"))
    })? {
        let name = field.name().map(String::from);

        match name.as_deref() {
            Some("video") => {
                let bytes = field.bytes().await.map_err(|e| {
                    tracing::warn!(error = %e, "Failed to read video field");
                    ApiError::Validation("Failed to read video data".to_string())
                })?;

                validate_video_size(bytes.len())?;
                video_bytes = Some(bytes.to_vec());

                tracing::debug!(size = bytes.len(), "Video field parsed");
            }

            Some("depth_data") => {
                let bytes = field.bytes().await.map_err(|e| {
                    tracing::warn!(error = %e, "Failed to read depth_data field");
                    ApiError::Validation("Failed to read depth_data".to_string())
                })?;

                validate_video_depth_size(bytes.len())?;
                depth_bytes = Some(bytes.to_vec());

                tracing::debug!(size = bytes.len(), "Depth data field parsed");
            }

            Some("hash_chain") => {
                let bytes = field.bytes().await.map_err(|e| {
                    tracing::warn!(error = %e, "Failed to read hash_chain field");
                    ApiError::Validation("Failed to read hash_chain data".to_string())
                })?;

                validate_hash_chain_size(bytes.len())?;
                hash_chain_bytes = Some(bytes.to_vec());

                tracing::debug!(size = bytes.len(), "Hash chain field parsed");
            }

            Some("metadata") => {
                let text = field.text().await.map_err(|e| {
                    tracing::warn!(error = %e, "Failed to read metadata field");
                    ApiError::Validation("Failed to read metadata".to_string())
                })?;

                validate_video_metadata_size(text.len())?;

                let parsed: VideoUploadMetadata = serde_json::from_str(&text).map_err(|e| {
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
    let video_bytes = video_bytes
        .ok_or_else(|| ApiError::Validation("Missing required part: video".to_string()))?;

    let depth_bytes = depth_bytes
        .ok_or_else(|| ApiError::Validation("Missing required part: depth_data".to_string()))?;

    let hash_chain_bytes = hash_chain_bytes
        .ok_or_else(|| ApiError::Validation("Missing required part: hash_chain".to_string()))?;

    let metadata = metadata
        .ok_or_else(|| ApiError::Validation("Missing required part: metadata".to_string()))?;

    Ok(ParsedVideoMultipart {
        video_bytes,
        depth_bytes,
        hash_chain_bytes,
        metadata,
    })
}

// ============================================================================
// Rate Limiting
// ============================================================================

/// Check if device has exceeded video upload rate limit
///
/// Returns Ok(()) if under limit, Err with retry_after seconds if exceeded.
async fn check_video_rate_limit(pool: &PgPool, device_id: Uuid) -> Result<(), (i64, ApiError)> {
    let recent_count: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*)::bigint FROM captures
        WHERE device_id = $1
        AND capture_type = 'video'
        AND uploaded_at > NOW() - INTERVAL '1 hour'
        "#,
    )
    .bind(device_id)
    .fetch_one(pool)
    .await
    .unwrap_or(0);

    if recent_count >= VIDEO_RATE_LIMIT_PER_HOUR {
        // Calculate retry_after based on oldest upload in the window
        let oldest_upload: Option<chrono::DateTime<chrono::Utc>> = sqlx::query_scalar(
            r#"
            SELECT MIN(uploaded_at) FROM captures
            WHERE device_id = $1
            AND capture_type = 'video'
            AND uploaded_at > NOW() - INTERVAL '1 hour'
            "#,
        )
        .bind(device_id)
        .fetch_one(pool)
        .await
        .ok()
        .flatten();

        let retry_after = oldest_upload
            .map(|oldest| {
                let expires_at = oldest + chrono::Duration::hours(1);
                let now = chrono::Utc::now();
                if expires_at > now {
                    (expires_at - now).num_seconds().max(1)
                } else {
                    1
                }
            })
            .unwrap_or(3600); // Default to 1 hour if we can't calculate

        tracing::warn!(
            device_id = %device_id,
            recent_count = recent_count,
            retry_after = retry_after,
            "[rate_limit] Video upload rate limit exceeded"
        );

        return Err((retry_after, ApiError::RateLimited));
    }

    Ok(())
}

// ============================================================================
// Database Operations
// ============================================================================

/// Insert a new video capture record
#[allow(clippy::too_many_arguments)]
async fn insert_video_capture(
    pool: &PgPool,
    capture_id: Uuid,
    device_id: Uuid,
    video_s3_key: &str,
    depth_s3_key: &str,
    hash_chain_s3_key: &str,
    captured_at: chrono::DateTime<chrono::Utc>,
    location_precise: Option<serde_json::Value>,
    duration_ms: i64,
    frame_count: i32,
    is_partial: bool,
) -> Result<Uuid, ApiError> {
    // Initial evidence package (minimal for video - full evidence built in Stories 7-9, 7-10)
    let evidence = json!({
        "hardware_attestation": {
            "status": "pending",
            "assertion_verified": false,
            "counter_valid": false,
            "failure_reason": "Video attestation pending verification"
        },
        "depth_analysis": {
            "status": "pending",
            "analysis_type": "video_keyframes",
            "keyframe_count": 0
        },
        "hash_chain": {
            "status": "pending",
            "frame_count": frame_count,
            "checkpoints_verified": 0
        },
        "metadata": {
            "duration_ms": duration_ms,
            "is_partial": is_partial
        }
    });

    sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO captures (
            id, device_id, capture_type, video_s3_key, depth_map_s3_key,
            hash_chain_s3_key, evidence, confidence_level, status,
            location_precise, captured_at, duration_ms, frame_count, is_partial
        )
        VALUES ($1, $2, 'video', $3, $4, $5, $6, 'low', 'processing', $7, $8, $9, $10, $11)
        RETURNING id
        "#,
    )
    .bind(capture_id)
    .bind(device_id)
    .bind(video_s3_key)
    .bind(depth_s3_key)
    .bind(hash_chain_s3_key)
    .bind(&evidence)
    .bind(&location_precise)
    .bind(captured_at)
    .bind(duration_ms)
    .bind(frame_count)
    .bind(is_partial)
    .fetch_one(pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to insert video capture record");
        ApiError::Database(e)
    })
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/v1/captures/video - Upload a new video capture
///
/// Accepts multipart form data with:
/// - video: MP4/MOV binary (max 100MB)
/// - depth_data: Gzipped depth keyframes (max 20MB)
/// - hash_chain: JSON with frame hashes (max 1MB)
/// - metadata: JSON metadata with attestation (max 100KB)
///
/// Device authentication is handled by DeviceAuthLayer middleware.
///
/// ## Rate Limiting
/// Limited to 5 video uploads per hour per device.
/// Returns 429 Too Many Requests with Retry-After header when exceeded.
///
/// # Responses
/// - 202 Accepted: Video uploaded successfully, processing queued
/// - 400 Bad Request: Validation error
/// - 401 Unauthorized: Device auth failed (handled by middleware)
/// - 413 Payload Too Large: File exceeds size limit
/// - 429 Too Many Requests: Rate limit exceeded
/// - 500 Internal Server Error: Storage or database error
async fn upload_video(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Extension(device_ctx): Extension<DeviceContext>,
    multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<VideoUploadResponse>>), Response> {
    tracing::info!(
        request_id = %request_id,
        device_id = %device_ctx.device_id,
        device_model = %device_ctx.model,
        "Processing video capture upload request"
    );

    // Check rate limit FIRST before parsing multipart
    if let Err((retry_after, _err)) = check_video_rate_limit(&state.db, device_ctx.device_id).await
    {
        tracing::warn!(
            request_id = %request_id,
            device_id = %device_ctx.device_id,
            retry_after = retry_after,
            "[rate_limit] Video upload rejected due to rate limit"
        );

        // HIGH-1 fix: Return 429 with Retry-After header (AC-7.8.6)
        let error_response = ApiErrorResponse::new(
            "RATE_LIMITED",
            "Rate limit exceeded. Please wait before trying again.".to_string(),
            request_id,
        );

        return Err((
            StatusCode::TOO_MANY_REQUESTS,
            [(header::RETRY_AFTER, retry_after.to_string())],
            Json(error_response),
        )
            .into_response());
    }

    // Parse multipart form data
    let parsed = parse_video_multipart(multipart).await.map_err(|e| {
        ApiErrorWithRequestId {
            error: e,
            request_id,
        }
        .into_response()
    })?;

    tracing::info!(
        request_id = %request_id,
        video_size = parsed.video_bytes.len(),
        depth_size = parsed.depth_bytes.len(),
        hash_chain_size = parsed.hash_chain_bytes.len(),
        device_model = %parsed.metadata.device_model,
        duration_ms = parsed.metadata.duration_ms,
        frame_count = parsed.metadata.frame_count,
        is_partial = parsed.metadata.is_partial,
        "Video multipart data parsed successfully"
    );

    // Generate capture ID
    let capture_id = Uuid::new_v4();

    // Upload files to S3
    let storage = &state.storage;

    let (video_s3_key, depth_s3_key, hash_chain_s3_key) = storage
        .upload_video_files(
            capture_id,
            parsed.video_bytes,
            parsed.depth_bytes,
            parsed.hash_chain_bytes,
        )
        .await
        .map_err(|e| {
            ApiErrorWithRequestId {
                error: e,
                request_id,
            }
            .into_response()
        })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        video_s3_key = %video_s3_key,
        depth_s3_key = %depth_s3_key,
        hash_chain_s3_key = %hash_chain_s3_key,
        "Video files uploaded to S3"
    );

    // Parse capture timestamp
    let captured_at = parsed.metadata.started_at_datetime().map_err(|e| {
        ApiErrorWithRequestId {
            error: e,
            request_id,
        }
        .into_response()
    })?;

    // Prepare location data if present
    let location_precise = parsed.metadata.location.as_ref().map(|loc| {
        json!({
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "altitude": loc.altitude,
            "accuracy": loc.accuracy
        })
    });

    // Create database record
    let db_capture_id = insert_video_capture(
        &state.db,
        capture_id,
        device_ctx.device_id,
        &video_s3_key,
        &depth_s3_key,
        &hash_chain_s3_key,
        captured_at,
        location_precise,
        parsed.metadata.duration_ms as i64,
        parsed.metadata.frame_count as i32,
        parsed.metadata.is_partial,
    )
    .await
    .map_err(|e| {
        ApiErrorWithRequestId {
            error: e,
            request_id,
        }
        .into_response()
    })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %db_capture_id,
        device_id = %device_ctx.device_id,
        "Video capture record created in database"
    );

    // Build response
    let config = &state.config;
    let verification_url = format!("{}/{db_capture_id}", config.verification_base_url);

    let response_data = VideoUploadResponse {
        capture_id: db_capture_id,
        capture_type: "video".to_string(),
        status: "processing".to_string(),
        verification_url,
    };

    tracing::info!(
        request_id = %request_id,
        capture_id = %db_capture_id,
        "Video capture upload completed successfully"
    );

    Ok((
        StatusCode::ACCEPTED,
        Json(ApiResponse::new(response_data, request_id)),
    ))
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

    #[test]
    fn test_video_upload_response_serialization() {
        let response = VideoUploadResponse {
            capture_id: Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap(),
            capture_type: "video".to_string(),
            status: "processing".to_string(),
            verification_url: "https://realitycam.app/verify/550e8400-e29b-41d4-a716-446655440000"
                .to_string(),
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains(r#""type":"video""#));
        assert!(json.contains(r#""status":"processing""#));
        assert!(json.contains(r#""capture_id":"550e8400-e29b-41d4-a716-446655440000""#));
    }
}
