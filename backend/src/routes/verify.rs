//! Verification routes
//!
//! Stub implementation for file verification endpoint.

use axum::{extract::Extension, routing::post, Json, Router};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::ApiError;
use crate::types::ApiErrorResponse;

/// Creates the verification routes router.
///
/// Returns a router that expects PgPool state (for future database operations).
pub fn router() -> Router<PgPool> {
    Router::new().route("/verify-file", post(verify_file))
}

/// POST /api/v1/verify-file - Verify a file
///
/// Verifies the authenticity of an uploaded file by checking its hash.
/// Currently returns 501 Not Implemented.
async fn verify_file(
    Extension(request_id): Extension<Uuid>,
) -> (axum::http::StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}
