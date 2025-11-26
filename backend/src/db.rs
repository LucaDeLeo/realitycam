//! Database connection pool module
//!
//! Provides PostgreSQL connection pool configuration and initialization.

use crate::config::Config;
use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;

/// Creates a PostgreSQL connection pool with the configured settings.
///
/// Includes retry logic to handle Fly.io Postgres cold starts (auto-suspend).
/// Will retry up to 5 times with exponential backoff before failing.
///
/// # Arguments
/// * `config` - Application configuration containing database URL and pool settings
///
/// # Returns
/// * `Ok(PgPool)` - Successfully created connection pool
/// * `Err(sqlx::Error)` - Failed to connect to the database after all retries
///
/// # Pool Configuration
/// - `max_connections`: Maximum number of connections (default: 10)
/// - `min_connections`: Minimum connections to keep warm (default: 0 for serverless)
/// - `acquire_timeout`: Time to wait for a connection (default: 30s)
/// - `idle_timeout`: Time before idle connections are closed (default: 10min)
pub async fn create_pool(config: &Config) -> Result<PgPool, sqlx::Error> {
    let max_retries = 5;
    let mut last_error = None;

    for attempt in 1..=max_retries {
        tracing::info!(
            "Attempting database connection (attempt {}/{})",
            attempt,
            max_retries
        );

        match PgPoolOptions::new()
            .max_connections(config.db_max_connections)
            // Use 0 min connections to allow lazy connection establishment
            // This prevents startup failures when DB is waking from suspend
            .min_connections(0)
            .acquire_timeout(Duration::from_secs(config.db_acquire_timeout_secs))
            .idle_timeout(Duration::from_secs(config.db_idle_timeout_secs))
            .connect(&config.database_url)
            .await
        {
            Ok(pool) => {
                tracing::info!("Database connection established on attempt {}", attempt);
                return Ok(pool);
            }
            Err(e) => {
                tracing::warn!("Database connection attempt {} failed: {}", attempt, e);
                last_error = Some(e);

                if attempt < max_retries {
                    // Exponential backoff: 2s, 4s, 8s, 16s
                    let delay = Duration::from_secs(2u64.pow(attempt as u32));
                    tracing::info!("Retrying in {:?}...", delay);
                    tokio::time::sleep(delay).await;
                }
            }
        }
    }

    Err(last_error.unwrap())
}

/// Runs pending database migrations.
///
/// # Arguments
/// * `pool` - Database connection pool
///
/// # Returns
/// * `Ok(())` - All migrations completed successfully
/// * `Err(sqlx::migrate::MigrateError)` - Migration failed
pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    sqlx::migrate!("./migrations").run(pool).await
}
