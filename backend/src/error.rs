//! API error handling module
//!
//! Defines error types and their HTTP response conversions.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use thiserror::Error;
use uuid::Uuid;

use crate::types::ApiErrorResponse;

/// Error codes as defined in the architecture document.
pub mod codes {
    pub const NOT_IMPLEMENTED: &str = "NOT_IMPLEMENTED";
    pub const VALIDATION_ERROR: &str = "VALIDATION_ERROR";
    pub const INTERNAL_ERROR: &str = "INTERNAL_ERROR";
    pub const ATTESTATION_FAILED: &str = "ATTESTATION_FAILED";
    pub const DEVICE_NOT_FOUND: &str = "DEVICE_NOT_FOUND";
    pub const CAPTURE_NOT_FOUND: &str = "CAPTURE_NOT_FOUND";
    pub const HASH_NOT_FOUND: &str = "HASH_NOT_FOUND";
    pub const SIGNATURE_INVALID: &str = "SIGNATURE_INVALID";
    pub const TIMESTAMP_EXPIRED: &str = "TIMESTAMP_EXPIRED";
    pub const PROCESSING_FAILED: &str = "PROCESSING_FAILED";
    pub const STORAGE_ERROR: &str = "STORAGE_ERROR";
    pub const DEVICE_ALREADY_REGISTERED: &str = "DEVICE_ALREADY_REGISTERED";
    pub const TOO_MANY_REQUESTS: &str = "TOO_MANY_REQUESTS";
    pub const CHALLENGE_INVALID: &str = "CHALLENGE_INVALID";
    // Device authentication middleware error codes (Story 2.6)
    pub const DEVICE_AUTH_REQUIRED: &str = "DEVICE_AUTH_REQUIRED";
    pub const DEVICE_UNVERIFIED: &str = "DEVICE_UNVERIFIED";
    pub const TIMESTAMP_INVALID: &str = "TIMESTAMP_INVALID";
    pub const REPLAY_DETECTED: &str = "REPLAY_DETECTED";
}

/// API error type with associated HTTP status codes.
#[derive(Debug, Error)]
pub enum ApiError {
    #[error("This endpoint is not yet implemented")]
    NotImplemented,

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Internal server error")]
    Internal(#[from] anyhow::Error),

    #[error("Database error")]
    Database(#[from] sqlx::Error),

    #[error("Device not found")]
    DeviceNotFound,

    #[error("Capture not found")]
    CaptureNotFound,

    #[error("Hash not found")]
    HashNotFound,

    #[error("Attestation failed: {0}")]
    AttestationFailed(String),

    #[error("Signature invalid")]
    SignatureInvalid,

    #[error("Timestamp expired")]
    TimestampExpired,

    #[error("Processing failed: {0}")]
    ProcessingFailed(String),

    #[error("Storage error: {0}")]
    StorageError(String),

    #[error("Device already registered")]
    DeviceAlreadyRegistered,

    #[error("Too many requests")]
    TooManyRequests,

    #[error("Challenge invalid: {0}")]
    ChallengeInvalid(String),

    // Device authentication middleware errors (Story 2.6)
    #[error("Device authentication required")]
    DeviceAuthRequired,

    #[error("Device unverified")]
    DeviceUnverified,

    #[error("Timestamp invalid")]
    TimestampInvalid,

    #[error("Replay detected")]
    ReplayDetected,
}

impl ApiError {
    /// Returns the error code for this error type.
    pub fn code(&self) -> &'static str {
        match self {
            ApiError::NotImplemented => codes::NOT_IMPLEMENTED,
            ApiError::Validation(_) => codes::VALIDATION_ERROR,
            ApiError::Internal(_) => codes::INTERNAL_ERROR,
            ApiError::Database(_) => codes::INTERNAL_ERROR,
            ApiError::DeviceNotFound => codes::DEVICE_NOT_FOUND,
            ApiError::CaptureNotFound => codes::CAPTURE_NOT_FOUND,
            ApiError::HashNotFound => codes::HASH_NOT_FOUND,
            ApiError::AttestationFailed(_) => codes::ATTESTATION_FAILED,
            ApiError::SignatureInvalid => codes::SIGNATURE_INVALID,
            ApiError::TimestampExpired => codes::TIMESTAMP_EXPIRED,
            ApiError::ProcessingFailed(_) => codes::PROCESSING_FAILED,
            ApiError::StorageError(_) => codes::STORAGE_ERROR,
            ApiError::DeviceAlreadyRegistered => codes::DEVICE_ALREADY_REGISTERED,
            ApiError::TooManyRequests => codes::TOO_MANY_REQUESTS,
            ApiError::ChallengeInvalid(_) => codes::CHALLENGE_INVALID,
            ApiError::DeviceAuthRequired => codes::DEVICE_AUTH_REQUIRED,
            ApiError::DeviceUnverified => codes::DEVICE_UNVERIFIED,
            ApiError::TimestampInvalid => codes::TIMESTAMP_INVALID,
            ApiError::ReplayDetected => codes::REPLAY_DETECTED,
        }
    }

    /// Returns the HTTP status code for this error type.
    pub fn status_code(&self) -> StatusCode {
        match self {
            ApiError::NotImplemented => StatusCode::NOT_IMPLEMENTED,
            ApiError::Validation(_) => StatusCode::BAD_REQUEST,
            ApiError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
            ApiError::Database(_) => StatusCode::INTERNAL_SERVER_ERROR,
            ApiError::DeviceNotFound => StatusCode::NOT_FOUND,
            ApiError::CaptureNotFound => StatusCode::NOT_FOUND,
            ApiError::HashNotFound => StatusCode::NOT_FOUND,
            ApiError::AttestationFailed(_) => StatusCode::UNAUTHORIZED,
            ApiError::SignatureInvalid => StatusCode::UNAUTHORIZED,
            ApiError::TimestampExpired => StatusCode::UNAUTHORIZED,
            ApiError::ProcessingFailed(_) => StatusCode::INTERNAL_SERVER_ERROR,
            ApiError::StorageError(_) => StatusCode::INTERNAL_SERVER_ERROR,
            ApiError::DeviceAlreadyRegistered => StatusCode::CONFLICT,
            ApiError::TooManyRequests => StatusCode::TOO_MANY_REQUESTS,
            ApiError::ChallengeInvalid(_) => StatusCode::UNAUTHORIZED,
            ApiError::DeviceAuthRequired => StatusCode::UNAUTHORIZED,
            ApiError::DeviceUnverified => StatusCode::FORBIDDEN,
            ApiError::TimestampInvalid => StatusCode::UNAUTHORIZED,
            ApiError::ReplayDetected => StatusCode::UNAUTHORIZED,
        }
    }

    /// Returns a safe message for external consumption (no internal details).
    pub fn safe_message(&self) -> String {
        match self {
            // These are safe to expose
            ApiError::NotImplemented => self.to_string(),
            ApiError::Validation(msg) => format!("Validation error: {msg}"),
            ApiError::DeviceNotFound => self.to_string(),
            ApiError::CaptureNotFound => self.to_string(),
            ApiError::HashNotFound => "No capture matches the uploaded file hash".to_string(),
            ApiError::AttestationFailed(_) => "Device attestation verification failed".to_string(),
            ApiError::SignatureInvalid => self.to_string(),
            ApiError::TimestampExpired => "Request timestamp is outside the allowed window".to_string(),

            // These should not expose internal details
            ApiError::Internal(_) => "An internal error occurred".to_string(),
            ApiError::Database(_) => "A database error occurred".to_string(),
            ApiError::ProcessingFailed(_) => "Evidence processing failed".to_string(),
            ApiError::StorageError(_) => "A storage error occurred".to_string(),
            ApiError::DeviceAlreadyRegistered => {
                "A device with this attestation key is already registered".to_string()
            }
            ApiError::TooManyRequests => {
                "Too many requests. Please wait before trying again.".to_string()
            }
            ApiError::ChallengeInvalid(_) => "Challenge is invalid or expired".to_string(),
            ApiError::DeviceAuthRequired => {
                "Device authentication headers required".to_string()
            }
            ApiError::DeviceUnverified => "Device is not verified".to_string(),
            ApiError::TimestampInvalid => "Request timestamp is invalid".to_string(),
            ApiError::ReplayDetected => "Request replay detected".to_string(),
        }
    }

    /// Converts the error to a response with the given request ID.
    pub fn into_response_with_request_id(self, request_id: Uuid) -> Response {
        let status = self.status_code();
        let body = ApiErrorResponse::new(self.code(), self.safe_message(), request_id);

        (status, Json(body)).into_response()
    }
}

/// A wrapper that carries the request ID with an error for response generation.
pub struct ApiErrorWithRequestId {
    pub error: ApiError,
    pub request_id: Uuid,
}

impl IntoResponse for ApiErrorWithRequestId {
    fn into_response(self) -> Response {
        self.error.into_response_with_request_id(self.request_id)
    }
}
