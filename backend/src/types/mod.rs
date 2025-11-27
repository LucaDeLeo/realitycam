//! API request/response types
//!
//! Defines the standard API response format per architecture specification.

pub mod capture;
pub mod video_capture;
pub mod video_depth_analysis;

pub use capture::{
    CaptureDetailsResponse, CaptureLocation, CaptureMetadataPayload, CaptureUploadResponse,
    DepthMapDimensions, ParsedCaptureUpload, MAX_DEPTH_DIMENSION, MAX_DEPTH_MAP_SIZE,
    MAX_PHOTO_SIZE,
};

pub use video_capture::{
    validate_hash_chain_size, validate_video_depth_size, validate_video_metadata_size,
    validate_video_size, HashCheckpoint, Resolution, VideoUploadMetadata, VideoUploadResponse,
    MAX_HASH_CHAIN_SIZE, MAX_VIDEO_DEPTH_SIZE, MAX_VIDEO_METADATA_SIZE, MAX_VIDEO_SIZE,
    VIDEO_RATE_LIMIT_PER_HOUR,
};

pub use video_depth_analysis::{
    DepthKeyframe, FrameDepthAnalysis, VideoDepthAnalysis, VideoDepthAnalysisConfig,
    VideoDepthAnalysisError,
};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Standard API success response wrapper.
///
/// All successful API responses follow this format:
/// ```json
/// {
///   "data": { /* payload */ },
///   "meta": {
///     "request_id": "uuid",
///     "timestamp": "2025-11-22T10:00:00Z"
///   }
/// }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub data: T,
    pub meta: Meta,
}

impl<T> ApiResponse<T> {
    /// Creates a new API response with the given data and request ID.
    pub fn new(data: T, request_id: Uuid) -> Self {
        Self {
            data,
            meta: Meta::new(request_id),
        }
    }
}

/// Standard API error response wrapper.
///
/// All error responses follow this format:
/// ```json
/// {
///   "error": {
///     "code": "NOT_IMPLEMENTED",
///     "message": "This endpoint is not yet implemented",
///     "details": { /* optional */ }
///   },
///   "meta": {
///     "request_id": "uuid",
///     "timestamp": "2025-11-22T10:00:00Z"
///   }
/// }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiErrorResponse {
    pub error: ErrorBody,
    pub meta: Meta,
}

impl ApiErrorResponse {
    /// Creates a new error response.
    pub fn new(code: impl Into<String>, message: impl Into<String>, request_id: Uuid) -> Self {
        Self {
            error: ErrorBody {
                code: code.into(),
                message: message.into(),
                details: None,
            },
            meta: Meta::new(request_id),
        }
    }

    /// Creates a new error response with details.
    pub fn with_details(
        code: impl Into<String>,
        message: impl Into<String>,
        details: serde_json::Value,
        request_id: Uuid,
    ) -> Self {
        Self {
            error: ErrorBody {
                code: code.into(),
                message: message.into(),
                details: Some(details),
            },
            meta: Meta::new(request_id),
        }
    }
}

/// Error body containing code, message, and optional details.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorBody {
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<serde_json::Value>,
}

/// Response metadata containing request ID and timestamp.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Meta {
    pub request_id: Uuid,
    pub timestamp: DateTime<Utc>,
}

impl Meta {
    /// Creates new metadata with the given request ID and current timestamp.
    pub fn new(request_id: Uuid) -> Self {
        Self {
            request_id,
            timestamp: Utc::now(),
        }
    }
}
