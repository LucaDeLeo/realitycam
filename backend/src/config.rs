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
}

impl Config {
    /// Loads configuration from environment variables.
    ///
    /// Falls back to sensible defaults for local development if variables are not set.
    pub fn load() -> Self {
        // Load .env file if it exists
        dotenv().ok();

        Self {
            database_url: env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgres://realitycam:localdev@localhost:5432/realitycam".to_string()),
            s3_endpoint: env::var("S3_ENDPOINT")
                .unwrap_or_else(|_| "http://localhost:4566".to_string()),
            s3_bucket: env::var("S3_BUCKET")
                .unwrap_or_else(|_| "realitycam-media-dev".to_string()),
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
        }
    }
}
