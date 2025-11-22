//! Test application setup with containers
//!
//! Spawns PostgreSQL and LocalStack containers for integration tests.
//! Each test gets an isolated database schema for parallelism.

use std::sync::Arc;
use testcontainers::{
    runners::AsyncRunner,
    ContainerAsync,
    ImageExt,
};
use testcontainers_modules::{
    postgres::Postgres,
    localstack::LocalStack,
};
use sqlx::{postgres::PgPoolOptions, PgPool};
use tokio::sync::OnceCell;

/// Global containers shared across tests (one PostgreSQL, one LocalStack)
static POSTGRES_CONTAINER: OnceCell<ContainerAsync<Postgres>> = OnceCell::const_new();
static LOCALSTACK_CONTAINER: OnceCell<ContainerAsync<LocalStack>> = OnceCell::const_new();

/// Test application context
pub struct TestApp {
    pub db_pool: PgPool,
    pub s3_endpoint: String,
    pub api_base_url: String,
    pub client: reqwest::Client,
    schema_name: String,
}

impl TestApp {
    /// Create a new test app with isolated database schema
    pub async fn spawn() -> Self {
        // Start containers (reused across tests)
        let pg = POSTGRES_CONTAINER
            .get_or_init(|| async {
                Postgres::default()
                    .with_tag("16-alpine")
                    .start()
                    .await
                    .expect("Failed to start PostgreSQL container")
            })
            .await;

        let localstack = LOCALSTACK_CONTAINER
            .get_or_init(|| async {
                LocalStack::default()
                    .with_tag("3.0")
                    .start()
                    .await
                    .expect("Failed to start LocalStack container")
            })
            .await;

        // Get container ports
        let pg_port = pg.get_host_port_ipv4(5432).await.unwrap();
        let s3_port = localstack.get_host_port_ipv4(4566).await.unwrap();

        // Create unique schema for test isolation
        let schema_name = format!("test_{}", uuid::Uuid::new_v4().to_string().replace('-', "_"));

        // Connect to PostgreSQL
        let database_url = format!(
            "postgres://postgres:postgres@127.0.0.1:{}/postgres",
            pg_port
        );

        let db_pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(&database_url)
            .await
            .expect("Failed to connect to test database");

        // Create isolated schema and run migrations
        sqlx::query(&format!("CREATE SCHEMA IF NOT EXISTS {}", schema_name))
            .execute(&db_pool)
            .await
            .expect("Failed to create test schema");

        sqlx::query(&format!("SET search_path TO {}", schema_name))
            .execute(&db_pool)
            .await
            .expect("Failed to set search path");

        // Run migrations (assumes migrations are in backend/migrations/)
        sqlx::migrate!("./migrations")
            .run(&db_pool)
            .await
            .expect("Failed to run migrations");

        let s3_endpoint = format!("http://127.0.0.1:{}", s3_port);

        // TODO: Start the actual API server on a random port
        // For now, tests will call services directly
        let api_base_url = "http://127.0.0.1:3001".to_string();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            db_pool,
            s3_endpoint,
            api_base_url,
            client,
            schema_name,
        }
    }

    /// Clean up test schema after test completes
    pub async fn cleanup(&self) {
        sqlx::query(&format!("DROP SCHEMA IF EXISTS {} CASCADE", self.schema_name))
            .execute(&self.db_pool)
            .await
            .ok();
    }
}

impl Drop for TestApp {
    fn drop(&mut self) {
        // Note: async cleanup in Drop is tricky; prefer explicit cleanup
        // The schema will be cleaned up on next test run anyway
    }
}

/// Macro for creating integration tests with automatic setup/teardown
#[macro_export]
macro_rules! integration_test {
    ($name:ident, $body:expr) => {
        #[tokio::test]
        async fn $name() {
            let app = TestApp::spawn().await;
            let result = std::panic::AssertUnwindSafe(async { $body(&app).await })
                .catch_unwind()
                .await;
            app.cleanup().await;
            if let Err(e) = result {
                std::panic::resume_unwind(e);
            }
        }
    };
}
