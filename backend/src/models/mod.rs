//! Database entity models for RealityCam
//!
//! This module contains Rust structs that map to PostgreSQL tables.
//! All models derive `sqlx::FromRow` for compile-time checked queries.

mod capture;
mod debug_log;
mod device;
mod evidence;
mod verification_log;

pub use capture::{Capture, CreateCaptureParams};
pub use debug_log::{
    BatchInsertResponse, CreateDebugLog, DebugLog, DebugLogDelete, DebugLogQuery, DebugLogStats,
    DeleteResponse, LevelCounts, LogLevel, LogSource, QueryLogsResponse, SourceCounts,
};
pub use device::Device;
pub use evidence::{
    AttestationLevel, CheckStatus, ConfidenceLevel, DepthAnalysis, EvidencePackage,
    HardwareAttestation, MetadataEvidence, ProcessingInfo,
};
pub use verification_log::VerificationLog;
