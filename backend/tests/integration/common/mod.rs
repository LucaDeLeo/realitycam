//! Common test utilities and fixtures for integration tests
//!
//! Provides:
//! - TestApp: Spawns the API server with test containers
//! - Factories: Generate test data (devices, captures, attestations)
//! - Assertions: Custom assertions for evidence verification

pub mod test_app;
pub mod factories;
pub mod assertions;

pub use test_app::TestApp;
pub use factories::*;
