//! Route modules and router assembly
//!
//! Organizes all API routes with proper versioning:
//! - Health endpoints at root level (/health, /ready)
//! - Feature endpoints under /api/v1/ prefix

use axum::{routing::get, Router};
use sqlx::PgPool;
use std::sync::Arc;

use crate::config::Config;
use crate::middleware::{DeviceAuthConfig, DeviceAuthLayer};
use crate::services::{ChallengeStore, StorageService};

pub mod captures;
pub mod devices;
pub mod health;
pub mod test;
pub mod verify;

/// Shared application state for all routes
#[derive(Clone)]
pub struct AppState {
    /// Database connection pool
    pub db: PgPool,
    /// Challenge store for attestation verification
    pub challenge_store: Arc<ChallengeStore>,
    /// Application configuration
    pub config: Arc<Config>,
    /// S3 storage service (shared, connection-pooled)
    pub storage: Arc<StorageService>,
}

/// Creates the main API router with all routes.
///
/// Route structure:
/// - `/health` - Health check (root level)
/// - `/ready` - Readiness check (root level)
/// - `/api/v1/devices/*` - Device routes (public - no auth middleware)
/// - `/api/v1/captures/*` - Capture routes (protected with device auth middleware)
/// - `/api/v1/verify-file` - Verification route (public)
pub fn api_router(state: AppState) -> Router {
    // Create stateful router for health endpoints that need db access
    let health_router = Router::new()
        .route("/health", get(health::health_check))
        .route("/ready", get(health::readiness_check))
        .with_state(state.db.clone());

    // Configure device authentication middleware for captures router
    // Controlled by REQUIRE_VERIFIED_DEVICES env var (default: false for MVP)
    let device_auth_config = DeviceAuthConfig {
        require_verified: state.config.require_verified_devices,
        timestamp_tolerance_secs: 300, // 5 minutes
        future_tolerance_secs: 60,     // 1 minute
    };

    // Captures router with device authentication middleware (rate limiting disabled for hackathon demo)
    // This protects all capture-related endpoints
    // Pass full AppState for access to storage, config, and db
    let captures_router = captures::router()
        .with_state(state.clone())
        .layer(DeviceAuthLayer::new(state.db.clone(), device_auth_config));

    // Verify router (rate limiting disabled for hackathon demo)
    let verify_router = verify::router().with_state(state.db.clone());

    // Create v1 API routes
    // - devices router: public (registration, challenge)
    // - captures router: protected with device auth middleware
    // - verify router: public with rate limiting (file verification)
    // - test router: conditionally enabled for E2E test seeding
    let mut v1_router = Router::new()
        .nest("/devices", devices::router())
        .nest("/captures", captures_router)
        .merge(verify_router);

    // Conditionally add test routes (SECURITY: only enabled via ENABLE_TEST_ENDPOINTS)
    if state.config.enable_test_endpoints {
        tracing::warn!("Test endpoints enabled - DO NOT USE IN PRODUCTION");
        v1_router = v1_router.nest("/test", test::router());
    }

    let v1_router = v1_router.with_state(state);

    // Combine all routes
    Router::new()
        .merge(health_router)
        .nest("/api/v1", v1_router)
}
