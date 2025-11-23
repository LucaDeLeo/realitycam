use dotenvy::dotenv;
use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub s3_endpoint: String,
    pub s3_bucket: String,
    pub port: u16,
}

impl Config {
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
        }
    }
}
