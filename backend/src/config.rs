//! Application configuration
//!
//! Loads configuration from environment variables with sensible defaults.

use dotenvy::dotenv;
use std::env;

/// Application configuration loaded from environment variables.
#[derive(Debug, Clone)]
pub struct Config {
    /// PostgreSQL connection URL
    pub database_url: String,

    /// S3-compatible storage endpoint (e.g., LocalStack for dev)
    pub s3_endpoint: String,

    /// S3 bucket name for media storage
    pub s3_bucket: String,

    /// HTTP server host (default: 0.0.0.0)
    pub host: String,

    /// HTTP server port
    pub port: u16,

    /// Maximum database connections in the pool (default: 10)
    pub db_max_connections: u32,

    /// Minimum database connections to keep warm (default: 2)
    pub db_min_connections: u32,

    /// Timeout in seconds to acquire a database connection (default: 30)
    pub db_acquire_timeout_secs: u64,

    /// Idle timeout in seconds before connections are closed (default: 600 = 10min)
    pub db_idle_timeout_secs: u64,

    /// CORS allowed origins (comma-separated, default: localhost dev ports)
    pub cors_origins: Vec<String>,

    /// Log format: "json" for structured, "pretty" for human-readable (default: pretty)
    pub log_format: String,

    /// Graceful shutdown timeout in seconds (default: 30)
    pub shutdown_timeout_secs: u64,

    /// Apple Developer Team ID for DCAppAttest verification (AC-6)
    pub apple_team_id: String,

    /// Apple Bundle ID for DCAppAttest verification (AC-6)
    pub apple_bundle_id: String,

    /// Base URL for verification pages (e.g., https://realitycam.app/verify)
    pub verification_base_url: String,

    /// Enable strict attestation verification (reject invalid certificate chains)
    /// When false (MVP mode), invalid chains are logged but allowed
    pub strict_attestation: bool,
}

impl Config {
    /// Loads configuration from environment variables.
    ///
    /// Falls back to sensible defaults for local development if variables are not set.
    pub fn load() -> Self {
        // Load .env file if it exists
        dotenv().ok();

        let cors_origins_str = env::var("CORS_ORIGINS")
            .unwrap_or_else(|_| "http://localhost:3000,http://localhost:8081".to_string());
        let cors_origins: Vec<String> = cors_origins_str
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        Self {
            database_url: env::var("DATABASE_URL").unwrap_or_else(|_| {
                "postgres://realitycam:localdev@localhost:5432/realitycam".to_string()
            }),
            s3_endpoint: env::var("S3_ENDPOINT")
                .unwrap_or_else(|_| "http://localhost:4566".to_string()),
            s3_bucket: env::var("S3_BUCKET").unwrap_or_else(|_| "realitycam-media-dev".to_string()),
            host: env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: env::var("PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()
                .expect("PORT must be a number"),
            db_max_connections: env::var("DB_MAX_CONNECTIONS")
                .unwrap_or_else(|_| "10".to_string())
                .parse()
                .expect("DB_MAX_CONNECTIONS must be a number"),
            db_min_connections: env::var("DB_MIN_CONNECTIONS")
                .unwrap_or_else(|_| "2".to_string())
                .parse()
                .expect("DB_MIN_CONNECTIONS must be a number"),
            db_acquire_timeout_secs: env::var("DB_ACQUIRE_TIMEOUT_SECS")
                .unwrap_or_else(|_| "30".to_string())
                .parse()
                .expect("DB_ACQUIRE_TIMEOUT_SECS must be a number"),
            db_idle_timeout_secs: env::var("DB_IDLE_TIMEOUT_SECS")
                .unwrap_or_else(|_| "600".to_string())
                .parse()
                .expect("DB_IDLE_TIMEOUT_SECS must be a number"),
            cors_origins,
            log_format: env::var("LOG_FORMAT").unwrap_or_else(|_| "pretty".to_string()),
            shutdown_timeout_secs: env::var("SHUTDOWN_TIMEOUT_SECS")
                .unwrap_or_else(|_| "30".to_string())
                .parse()
                .expect("SHUTDOWN_TIMEOUT_SECS must be a number"),
            apple_team_id: env::var("APPLE_TEAM_ID").unwrap_or_else(|_| "XXXXXXXXXX".to_string()),
            apple_bundle_id: env::var("APPLE_BUNDLE_ID")
                .unwrap_or_else(|_| "com.realitycam.app".to_string()),
            verification_base_url: env::var("VERIFICATION_BASE_URL")
                .unwrap_or_else(|_| "https://realitycam.app/verify".to_string()),
            strict_attestation: env::var("STRICT_ATTESTATION")
                .map(|v| v.to_lowercase() == "true" || v == "1")
                .unwrap_or(false), // MVP default: permissive mode
        }
    }

    /// Creates a default configuration for testing purposes.
    #[cfg(test)]
    pub fn default_for_test() -> Self {
        Self {
            database_url: "postgres://test:test@localhost:5432/test".to_string(),
            s3_endpoint: "http://localhost:4566".to_string(),
            s3_bucket: "test-bucket".to_string(),
            host: "127.0.0.1".to_string(),
            port: 8080,
            db_max_connections: 5,
            db_min_connections: 1,
            db_acquire_timeout_secs: 10,
            db_idle_timeout_secs: 60,
            cors_origins: vec!["http://localhost:3000".to_string()],
            log_format: "pretty".to_string(),
            shutdown_timeout_secs: 5,
            apple_team_id: "XXXXXXXXXX".to_string(),
            apple_bundle_id: "com.test.app".to_string(),
            verification_base_url: "https://test.realitycam.app/verify".to_string(),
            strict_attestation: false,
        }
    }
}
