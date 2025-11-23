//! Health check routes
//!
//! Provides /health and /ready endpoints at root level for monitoring.

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;

/// Health check response structure.
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub database: String,
    pub version: String,
    pub timestamp: DateTime<Utc>,
}

/// Readiness check response structure.
#[derive(Debug, Serialize)]
pub struct ReadyResponse {
    pub ready: bool,
    pub database: String,
    pub timestamp: DateTime<Utc>,
}

/// GET /health - Health check endpoint
///
/// Returns the overall health status of the service including database connectivity.
/// Always returns 200 OK but indicates database status in the response body.
pub async fn health_check(State(db): State<PgPool>) -> Json<HealthResponse> {
    let db_status = match sqlx::query("SELECT 1").execute(&db).await {
        Ok(_) => "connected",
        Err(e) => {
            tracing::warn!("Database health check failed: {}", e);
            "disconnected"
        }
    };

    Json(HealthResponse {
        status: "ok".to_string(),
        database: db_status.to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        timestamp: Utc::now(),
    })
}

/// GET /ready - Readiness check endpoint
///
/// Returns 200 OK if the service is ready to handle requests (database connected).
/// Returns 503 Service Unavailable if the database is unreachable.
pub async fn readiness_check(State(db): State<PgPool>) -> impl IntoResponse {
    match sqlx::query("SELECT 1").execute(&db).await {
        Ok(_) => {
            let response = ReadyResponse {
                ready: true,
                database: "connected".to_string(),
                timestamp: Utc::now(),
            };
            (StatusCode::OK, Json(response)).into_response()
        }
        Err(e) => {
            tracing::warn!("Readiness check failed: {}", e);
            let response = ReadyResponse {
                ready: false,
                database: "disconnected".to_string(),
                timestamp: Utc::now(),
            };
            (StatusCode::SERVICE_UNAVAILABLE, Json(response)).into_response()
        }
    }
}
