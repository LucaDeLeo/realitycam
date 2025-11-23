//! Route modules and router assembly
//!
//! Organizes all API routes with proper versioning:
//! - Health endpoints at root level (/health, /ready)
//! - Feature endpoints under /api/v1/ prefix

use axum::{routing::get, Router};
use sqlx::PgPool;

pub mod captures;
pub mod devices;
pub mod health;
pub mod verify;

/// Creates the main API router with all routes.
///
/// Route structure:
/// - `/health` - Health check (root level)
/// - `/ready` - Readiness check (root level)
/// - `/api/v1/devices/*` - Device routes
/// - `/api/v1/captures/*` - Capture routes
/// - `/api/v1/verify-file` - Verification route
pub fn api_router(db: PgPool) -> Router {
    // Create stateful router for health endpoints that need db access
    let health_router = Router::new()
        .route("/health", get(health::health_check))
        .route("/ready", get(health::readiness_check))
        .with_state(db);

    // Create stateless v1 API routes (stubs don't need state)
    let v1_router = Router::new()
        .nest("/devices", devices::router())
        .nest("/captures", captures::router())
        .merge(verify::router());

    // Combine all routes
    Router::new()
        .merge(health_router)
        .nest("/api/v1", v1_router)
}
