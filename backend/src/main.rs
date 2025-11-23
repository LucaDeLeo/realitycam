//! RealityCam API Server
//!
//! Main entry point for the backend API with:
//! - Modular routing with /api/v1 versioning
//! - Health/ready endpoints at root level
//! - Request ID middleware for traceability
//! - Request logging with structured output
//! - CORS configuration for development
//! - Graceful shutdown handling

use axum::http::{header, HeaderName, Method};
use std::net::SocketAddr;
use std::time::Duration;
use tokio::signal;
use tower::ServiceBuilder;
use tower_http::{
    cors::{Any, CorsLayer},
    request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
    trace::TraceLayer,
};
use tracing::Span;
use tracing_subscriber::{
    fmt::{self, format::FmtSpan},
    layer::SubscriberExt,
    util::SubscriberInitExt,
    EnvFilter,
};
use uuid::Uuid;

mod config;
pub mod db;
pub mod error;
pub mod middleware;
pub mod models;
pub mod routes;
pub mod services;
pub mod types;

/// Request ID header name
const X_REQUEST_ID: &str = "x-request-id";

#[tokio::main]
async fn main() {
    // Load configuration first
    let config = config::Config::load();

    // Initialize tracing with format based on config
    init_tracing(&config.log_format);

    tracing::info!("Starting RealityCam API server");

    // Initialize database connection pool
    let pool = db::create_pool(&config)
        .await
        .expect("Failed to create database pool");
    tracing::info!("Database connection pool created");

    // Run pending migrations
    db::run_migrations(&pool)
        .await
        .expect("Failed to run database migrations");
    tracing::info!("Database migrations completed");

    // Initialize challenge store for attestation verification (AC-1, AC-2)
    let challenge_store = services::ChallengeStore::new();
    tracing::info!("Challenge store initialized");

    // Spawn background cleanup task for expired challenges
    let _cleanup_handle = services::ChallengeStore::spawn_cleanup_task(challenge_store.clone());
    tracing::info!("Challenge cleanup task spawned");

    // Build CORS layer
    let cors = build_cors_layer(&config.cors_origins);

    // Request ID header
    let x_request_id = HeaderName::from_static(X_REQUEST_ID);

    // Build the application state with database, challenge store, and config
    let app_state = routes::AppState {
        db: pool.clone(),
        challenge_store,
        config: std::sync::Arc::new(config.clone()),
    };

    // Build the router with middleware stack
    let app = routes::api_router(app_state)
        .layer(
            ServiceBuilder::new()
                // Set request ID on incoming requests
                .layer(SetRequestIdLayer::new(
                    x_request_id.clone(),
                    MakeRequestUuid,
                ))
                // Propagate request ID to response headers
                .layer(PropagateRequestIdLayer::new(x_request_id))
                // Add tracing with request ID in spans
                .layer(
                    TraceLayer::new_for_http()
                        .make_span_with(|request: &axum::http::Request<_>| {
                            let request_id = request
                                .headers()
                                .get(X_REQUEST_ID)
                                .and_then(|v| v.to_str().ok())
                                .and_then(|s| Uuid::parse_str(s).ok())
                                .unwrap_or_else(Uuid::new_v4);

                            tracing::info_span!(
                                "http_request",
                                method = %request.method(),
                                uri = %request.uri(),
                                request_id = %request_id,
                            )
                        })
                        .on_response(
                            |response: &axum::http::Response<_>,
                             latency: Duration,
                             _span: &Span| {
                                tracing::info!(
                                    status = %response.status().as_u16(),
                                    latency_ms = %latency.as_millis(),
                                    "request completed"
                                );
                            },
                        ),
                )
                // CORS layer
                .layer(cors)
                // Extract request ID as extension for handlers
                .layer(axum::middleware::from_fn(extract_request_id)),
        );

    // Run the server with graceful shutdown
    let addr: SocketAddr = format!("{}:{}", config.host, config.port)
        .parse()
        .expect("Invalid host:port combination");
    tracing::info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal(config.shutdown_timeout_secs))
        .await
        .unwrap();

    // Cleanup: close database pool
    pool.close().await;
    tracing::info!("Server shutdown complete");
}

/// Initialize tracing subscriber based on format preference.
fn init_tracing(log_format: &str) {
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,sqlx=warn,tower_http=debug"));

    match log_format {
        "json" => {
            tracing_subscriber::registry()
                .with(env_filter)
                .with(fmt::layer().json().with_span_events(FmtSpan::CLOSE))
                .init();
        }
        _ => {
            tracing_subscriber::registry()
                .with(env_filter)
                .with(fmt::layer().with_span_events(FmtSpan::CLOSE))
                .init();
        }
    }
}

/// Build CORS layer from configured origins.
fn build_cors_layer(origins: &[String]) -> CorsLayer {
    if origins.is_empty() {
        tracing::warn!("No CORS origins configured, allowing any origin");
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods([
                Method::GET,
                Method::POST,
                Method::PUT,
                Method::DELETE,
                Method::OPTIONS,
            ])
            .allow_headers([
                header::CONTENT_TYPE,
                header::AUTHORIZATION,
                header::ACCEPT,
                HeaderName::from_static(X_REQUEST_ID),
            ])
    } else {
        let allowed_origins: Vec<_> = origins
            .iter()
            .filter_map(|o| o.parse().ok())
            .collect();

        CorsLayer::new()
            .allow_origin(allowed_origins)
            .allow_methods([
                Method::GET,
                Method::POST,
                Method::PUT,
                Method::DELETE,
                Method::OPTIONS,
            ])
            .allow_headers([
                header::CONTENT_TYPE,
                header::AUTHORIZATION,
                header::ACCEPT,
                HeaderName::from_static(X_REQUEST_ID),
            ])
    }
}

/// Middleware to extract request ID from headers and add as extension.
async fn extract_request_id(
    request: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let request_id = request
        .headers()
        .get(X_REQUEST_ID)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
        .unwrap_or_else(Uuid::new_v4);

    let mut request = request;
    request.extensions_mut().insert(request_id);

    next.run(request).await
}

/// Shutdown signal handler for graceful shutdown.
///
/// Listens for SIGINT (Ctrl+C) and SIGTERM signals.
async fn shutdown_signal(timeout_secs: u64) {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {
            tracing::info!("Received SIGINT (Ctrl+C)");
        },
        _ = terminate => {
            tracing::info!("Received SIGTERM");
        },
    }

    tracing::info!(
        "Shutdown signal received, starting graceful shutdown (timeout: {}s)",
        timeout_secs
    );

    // Note: Axum handles the actual graceful shutdown of connections.
    // The timeout is informational; axum will wait for active requests to complete.
}
