//! Device registration routes
//!
//! Stub implementations for device challenge and registration endpoints.

use axum::{
    extract::Extension,
    routing::{get, post},
    Json, Router,
};
use uuid::Uuid;

use crate::error::ApiError;
use crate::types::ApiErrorResponse;

/// Creates the device routes router.
pub fn router() -> Router {
    Router::new()
        .route("/challenge", get(get_challenge))
        .route("/register", post(register_device))
}

/// GET /api/v1/devices/challenge - Request attestation challenge
///
/// Returns a unique challenge for device attestation.
/// Currently returns 501 Not Implemented.
async fn get_challenge(
    Extension(request_id): Extension<Uuid>,
) -> (axum::http::StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}

/// POST /api/v1/devices/register - Register a new device
///
/// Registers a device with its attestation data.
/// Currently returns 501 Not Implemented.
async fn register_device(
    Extension(request_id): Extension<Uuid>,
) -> (axum::http::StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}
