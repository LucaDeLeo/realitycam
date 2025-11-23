//! Verification routes (Stories 5-6, 5-7)
//!
//! Implements file verification endpoint for checking photos against the database
//! and extracting C2PA manifest information.
//!
//! ## Endpoints
//! - POST /api/v1/verify-file - Upload a file to verify against database
//!
//! ## Response Types
//! - "verified" - File hash matches a capture in database
//! - "c2pa_only" - File has C2PA manifest but no database match
//! - "no_record" - No provenance record found

use axum::{
    extract::{Extension, Path, State},
    routing::{get, post},
    Json, Router,
};
use axum_extra::extract::Multipart;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{ApiError, ApiErrorWithRequestId};
use crate::services::C2paManifestInfo;
use crate::types::ApiResponse;

// ============================================================================
// Configuration
// ============================================================================

/// Maximum file size for verification (20MB per PRD)
const MAX_FILE_SIZE: usize = 20 * 1024 * 1024;

/// Verification base URL
const VERIFICATION_BASE_URL: &str = "https://realitycam.app/verify";

// ============================================================================
// Response Types
// ============================================================================

/// Status of file verification
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VerificationStatus {
    /// File hash matches a capture in database
    Verified,
    /// File has C2PA manifest but no database match
    C2paOnly,
    /// No provenance record found
    NoRecord,
}

/// File verification response data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileVerificationResponse {
    /// Verification status
    pub status: VerificationStatus,

    /// Capture ID if verified
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capture_id: Option<String>,

    /// Confidence level if verified
    #[serde(skip_serializing_if = "Option::is_none")]
    pub confidence_level: Option<String>,

    /// Verification URL if verified
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verification_url: Option<String>,

    /// C2PA manifest info if present
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manifest_info: Option<C2paManifestInfo>,

    /// Explanatory note
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,

    /// File hash (SHA-256, base64)
    pub file_hash: String,
}

/// Public capture details response (for web verification page)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureDetailsPublic {
    /// Capture ID
    pub capture_id: String,
    /// Confidence level
    pub confidence_level: String,
    /// Capture timestamp
    pub captured_at: String,
    /// Upload timestamp
    pub uploaded_at: String,
    /// Coarse location (city-level, privacy protected)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location_coarse: Option<String>,
    /// Full evidence package
    pub evidence: serde_json::Value,
    /// Photo URL (presigned S3 URL)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub photo_url: Option<String>,
    /// Depth map URL (presigned S3 URL)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub depth_map_url: Option<String>,
}

// ============================================================================
// Router Setup
// ============================================================================

/// Creates the verification routes router.
pub fn router() -> Router<PgPool> {
    Router::new()
        .route("/verify-file", post(verify_file))
        .route("/verify/{id}", get(get_capture_public))
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/v1/verify-file - Verify an uploaded file
///
/// Accepts a file upload (JPEG, PNG, HEIC up to 20MB) and:
/// 1. Computes SHA-256 hash
/// 2. Checks if hash matches any capture in database
/// 3. If no match, attempts to extract C2PA manifest
/// 4. Returns appropriate verification status
///
/// # Request
/// Content-Type: multipart/form-data
/// - file: The image file to verify
///
/// # Responses
/// - 200 OK: Verification result (verified, c2pa_only, or no_record)
/// - 400 Bad Request: No file uploaded or invalid format
/// - 413 Payload Too Large: File > 20MB
/// - 429 Too Many Requests: Rate limit exceeded
/// - 500 Internal Server Error: Processing failed
async fn verify_file(
    State(pool): State<PgPool>,
    Extension(request_id): Extension<Uuid>,
    multipart: Multipart,
) -> Result<Json<ApiResponse<FileVerificationResponse>>, ApiErrorWithRequestId> {
    tracing::info!(
        request_id = %request_id,
        "Processing file verification request"
    );

    // Parse multipart to get file bytes
    let file_bytes = parse_file_multipart(multipart)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    tracing::info!(
        request_id = %request_id,
        file_size = file_bytes.len(),
        "File received for verification"
    );

    // Compute SHA-256 hash
    let mut hasher = Sha256::new();
    hasher.update(&file_bytes);
    let hash_bytes = hasher.finalize().to_vec();
    let hash_base64 = STANDARD.encode(&hash_bytes);

    tracing::debug!(
        request_id = %request_id,
        file_hash = %hash_base64,
        "File hash computed"
    );

    // Check database for matching capture
    let capture = lookup_capture_by_hash(&pool, &hash_bytes)
        .await
        .map_err(|e| ApiErrorWithRequestId {
            error: e,
            request_id,
        })?;

    if let Some(capture) = capture {
        // Match found - return verified status
        tracing::info!(
            request_id = %request_id,
            capture_id = %capture.id,
            confidence_level = %capture.confidence_level,
            "File verified - match found in database"
        );

        let response = FileVerificationResponse {
            status: VerificationStatus::Verified,
            capture_id: Some(capture.id.to_string()),
            confidence_level: Some(capture.confidence_level),
            verification_url: Some(format!("{}/{}", VERIFICATION_BASE_URL, capture.id)),
            manifest_info: None,
            note: None,
            file_hash: hash_base64,
        };

        return Ok(Json(ApiResponse::new(response, request_id)));
    }

    // No match in database
    // Note: For MVP, we skip C2PA extraction since we store manifests as JSON
    // This can be enhanced post-MVP to extract embedded C2PA manifests
    tracing::info!(
        request_id = %request_id,
        "No provenance record found for file"
    );

    let response = FileVerificationResponse {
        status: VerificationStatus::NoRecord,
        capture_id: None,
        confidence_level: None,
        verification_url: None,
        manifest_info: None,
        note: Some(
            "No provenance record found for this file. This doesn't mean the photo is fake - it just wasn't captured with RealityCam."
                .to_string(),
        ),
        file_hash: hash_base64,
    };

    Ok(Json(ApiResponse::new(response, request_id)))
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Parses multipart form data to extract file bytes
async fn parse_file_multipart(mut multipart: Multipart) -> Result<Vec<u8>, ApiError> {
    while let Some(field) = multipart.next_field().await.map_err(|e| {
        tracing::warn!(error = %e, "Failed to read multipart field");
        ApiError::Validation(format!("Failed to read multipart form: {e}"))
    })? {
        let name = field.name().map(String::from);

        if name.as_deref() == Some("file") {
            let bytes = field.bytes().await.map_err(|e| {
                tracing::warn!(error = %e, "Failed to read file field");
                ApiError::Validation("Failed to read file data".to_string())
            })?;

            // Check file size
            if bytes.len() > MAX_FILE_SIZE {
                return Err(ApiError::PayloadTooLarge(format!(
                    "File size {} exceeds maximum {}",
                    bytes.len(),
                    MAX_FILE_SIZE
                )));
            }

            return Ok(bytes.to_vec());
        }
    }

    Err(ApiError::Validation(
        "Missing required part: file".to_string(),
    ))
}

/// Database record for capture lookup
struct CaptureRecord {
    id: Uuid,
    confidence_level: String,
}

/// Looks up a capture by its target_media_hash
async fn lookup_capture_by_hash(
    pool: &PgPool,
    hash_bytes: &[u8],
) -> Result<Option<CaptureRecord>, ApiError> {
    let record = sqlx::query_as!(
        CaptureRecord,
        r#"
        SELECT id, confidence_level
        FROM captures
        WHERE target_media_hash = $1
        AND status = 'complete'
        "#,
        hash_bytes
    )
    .fetch_optional(pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Database error looking up capture by hash");
        ApiError::Database(e)
    })?;

    Ok(record)
}

/// Full capture record for public details
struct CaptureFullRecord {
    id: Uuid,
    confidence_level: String,
    captured_at: chrono::DateTime<chrono::Utc>,
    uploaded_at: chrono::DateTime<chrono::Utc>,
    location_coarse: Option<String>,
    evidence: Option<serde_json::Value>,
}

/// GET /api/v1/verify/{id} - Get public capture details
///
/// Returns capture details for the web verification page.
/// This is a PUBLIC endpoint - no authentication required.
/// Only returns coarse location (not precise) for privacy.
async fn get_capture_public(
    State(pool): State<PgPool>,
    Extension(request_id): Extension<Uuid>,
    Path(id): Path<String>,
) -> Result<Json<ApiResponse<CaptureDetailsPublic>>, ApiErrorWithRequestId> {
    // Parse capture ID
    let capture_id = Uuid::parse_str(&id).map_err(|_| ApiErrorWithRequestId {
        error: ApiError::Validation(format!("Invalid capture ID format: {id}")),
        request_id,
    })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        "Looking up capture for public verification"
    );

    // Query capture from database
    let capture = sqlx::query_as!(
        CaptureFullRecord,
        r#"
        SELECT id, confidence_level, captured_at, uploaded_at,
               location_coarse, evidence
        FROM captures
        WHERE id = $1 AND status = 'complete'
        "#,
        capture_id
    )
    .fetch_optional(&pool)
    .await
    .map_err(|e| ApiErrorWithRequestId {
        error: ApiError::Database(e),
        request_id,
    })?;

    let capture = capture.ok_or_else(|| ApiErrorWithRequestId {
        error: ApiError::CaptureNotFound,
        request_id,
    })?;

    tracing::info!(
        request_id = %request_id,
        capture_id = %capture_id,
        confidence_level = %capture.confidence_level,
        "Capture found for public verification"
    );

    // Build response (no presigned URLs for MVP - just return the data)
    let response = CaptureDetailsPublic {
        capture_id: capture.id.to_string(),
        confidence_level: capture.confidence_level,
        captured_at: capture.captured_at.to_rfc3339(),
        uploaded_at: capture.uploaded_at.to_rfc3339(),
        location_coarse: capture.location_coarse,
        evidence: capture.evidence.unwrap_or(serde_json::json!({})),
        photo_url: None, // TODO: Generate presigned S3 URL
        depth_map_url: None,
    };

    Ok(Json(ApiResponse::new(response, request_id)))
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_verification_status_serialization() {
        assert_eq!(
            serde_json::to_string(&VerificationStatus::Verified).unwrap(),
            "\"verified\""
        );
        assert_eq!(
            serde_json::to_string(&VerificationStatus::C2paOnly).unwrap(),
            "\"c2pa_only\""
        );
        assert_eq!(
            serde_json::to_string(&VerificationStatus::NoRecord).unwrap(),
            "\"no_record\""
        );
    }

    #[test]
    fn test_max_file_size() {
        assert_eq!(MAX_FILE_SIZE, 20 * 1024 * 1024); // 20MB
    }

    #[test]
    fn test_file_verification_response_serialization() {
        let response = FileVerificationResponse {
            status: VerificationStatus::Verified,
            capture_id: Some("550e8400-e29b-41d4-a716-446655440000".to_string()),
            confidence_level: Some("high".to_string()),
            verification_url: Some("https://realitycam.app/verify/550e8400".to_string()),
            manifest_info: None,
            note: None,
            file_hash: "abc123".to_string(),
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"verified\""));
        assert!(json.contains("\"capture_id\""));
        assert!(json.contains("\"confidence_level\""));
        assert!(!json.contains("\"note\"")); // Should be skipped when None
    }

    #[test]
    fn test_no_record_response() {
        let response = FileVerificationResponse {
            status: VerificationStatus::NoRecord,
            capture_id: None,
            confidence_level: None,
            verification_url: None,
            manifest_info: None,
            note: Some("No provenance record found".to_string()),
            file_hash: "xyz789".to_string(),
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"no_record\""));
        assert!(json.contains("\"note\""));
        assert!(!json.contains("\"capture_id\"")); // Should be skipped when None
    }
}
