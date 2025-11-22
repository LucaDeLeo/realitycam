//! Integration tests for RealityCam API
//!
//! These tests run against real PostgreSQL and LocalStack (S3) containers.
//! Use `cargo test --test integration` to run only integration tests.
//!
//! Test organization:
//! - `devices_test.rs` - Device registration and attestation
//! - `captures_test.rs` - Capture upload and processing
//! - `verify_test.rs` - Verification and hash lookup
//! - `evidence_test.rs` - Evidence computation pipeline

mod common;
mod devices_test;
mod captures_test;
mod verify_test;
mod evidence_test;
