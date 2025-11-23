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
/// - `/api/v1/devices/*` - Device routes (with database state)
/// - `/api/v1/captures/*` - Capture routes
/// - `/api/v1/verify-file` - Verification route
pub fn api_router(db: PgPool) -> Router {
    // Create stateful router for health endpoints that need db access
    let health_router = Router::new()
        .route("/health", get(health::health_check))
        .route("/ready", get(health::readiness_check))
        .with_state(db.clone());

    // Create v1 API routes
    // - devices router needs PgPool state for database operations
    // - other routes are currently stubs (stateless)
    let v1_router = Router::new()
        .nest("/devices", devices::router())
        .nest("/captures", captures::router())
        .merge(verify::router())
        .with_state(db);

    // Combine all routes
    Router::new()
        .merge(health_router)
        .nest("/api/v1", v1_router)
}
