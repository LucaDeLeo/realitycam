//! Capture routes
//!
//! Stub implementations for capture upload and retrieval endpoints.

use axum::{
    extract::{Extension, Path},
    routing::{get, post},
    Json, Router,
};
use uuid::Uuid;

use crate::error::ApiError;
use crate::types::ApiErrorResponse;

/// Creates the captures routes router.
pub fn router() -> Router {
    Router::new()
        .route("/", post(upload_capture))
        .route("/{id}", get(get_capture))
}

/// POST /api/v1/captures - Upload a new capture
///
/// Uploads photo with depth map and metadata.
/// Currently returns 501 Not Implemented.
async fn upload_capture(
    Extension(request_id): Extension<Uuid>,
) -> (axum::http::StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}

/// GET /api/v1/captures/{id} - Get capture by ID
///
/// Retrieves capture details and evidence by ID.
/// Currently returns 501 Not Implemented.
async fn get_capture(
    Path(_id): Path<String>,
    Extension(request_id): Extension<Uuid>,
) -> (axum::http::StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}
