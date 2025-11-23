//! Route modules and router assembly
//!
//! Organizes all API routes with proper versioning:
//! - Health endpoints at root level (/health, /ready)
//! - Feature endpoints under /api/v1/ prefix

use axum::{routing::get, Router};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;
use tower_governor::{
    governor::GovernorConfigBuilder, key_extractor::SmartIpKeyExtractor, GovernorLayer,
};

use crate::config::Config;
use crate::middleware::{DeviceAuthConfig, DeviceAuthLayer};
use crate::services::{ChallengeStore, StorageService};

pub mod captures;
pub mod devices;
pub mod health;
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
    // MVP mode: allow unverified devices (require_verified = false)
    let device_auth_config = DeviceAuthConfig {
        require_verified: false,       // MVP: allow unverified devices
        timestamp_tolerance_secs: 300, // 5 minutes
        future_tolerance_secs: 60,     // 1 minute
    };

    // Configure rate limiting for captures router
    // Uses token bucket algorithm: refills at rate_limit_per_second, bursts up to rate_limit_burst
    let governor_config = GovernorConfigBuilder::default()
        .per_second(state.config.rate_limit_per_second)
        .burst_size(state.config.rate_limit_burst)
        .key_extractor(SmartIpKeyExtractor)
        .finish()
        .expect("Failed to build rate limiter config");
    let governor_limiter = governor_config.limiter().clone();
    let rate_limit_layer = GovernorLayer::new(Arc::new(governor_config));

    // Spawn background task to clean up rate limiter state
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(60)).await;
            tracing::debug!("[rate_limiter] Cleaning up expired rate limit entries");
            governor_limiter.retain_recent();
        }
    });

    // Captures router with device authentication and rate limiting middleware
    // This protects all capture-related endpoints
    // Pass full AppState for access to storage, config, and db
    let captures_router = captures::router()
        .with_state(state.clone())
        .layer(DeviceAuthLayer::new(state.db.clone(), device_auth_config))
        .layer(rate_limit_layer);

    // Create v1 API routes
    // - devices router: public (registration, challenge)
    // - captures router: protected with device auth middleware
    // - verify router: public (file verification)
    let v1_router = Router::new()
        .nest("/devices", devices::router())
        .nest("/captures", captures_router)
        .merge(verify::router().with_state(state.db.clone()))
        .with_state(state);

    // Combine all routes
    Router::new()
        .merge(health_router)
        .nest("/api/v1", v1_router)
}
