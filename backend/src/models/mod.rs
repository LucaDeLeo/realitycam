//! Database entity models for RealityCam
//!
//! This module contains Rust structs that map to PostgreSQL tables.
//! All models derive `sqlx::FromRow` for compile-time checked queries.

mod capture;
mod device;
mod verification_log;

pub use capture::Capture;
pub use device::Device;
pub use verification_log::VerificationLog;
