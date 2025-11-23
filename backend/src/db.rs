//! Database connection pool module
//!
//! Provides PostgreSQL connection pool configuration and initialization.

use crate::config::Config;
use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;

/// Creates a PostgreSQL connection pool with the configured settings.
///
/// # Arguments
/// * `config` - Application configuration containing database URL and pool settings
///
/// # Returns
/// * `Ok(PgPool)` - Successfully created connection pool
/// * `Err(sqlx::Error)` - Failed to connect to the database
///
/// # Pool Configuration
/// - `max_connections`: Maximum number of connections (default: 10)
/// - `min_connections`: Minimum connections to keep warm (default: 2)
/// - `acquire_timeout`: Time to wait for a connection (default: 30s)
/// - `idle_timeout`: Time before idle connections are closed (default: 10min)
pub async fn create_pool(config: &Config) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(config.db_max_connections)
        .min_connections(config.db_min_connections)
        .acquire_timeout(Duration::from_secs(config.db_acquire_timeout_secs))
        .idle_timeout(Duration::from_secs(config.db_idle_timeout_secs))
        .connect(&config.database_url)
        .await
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
