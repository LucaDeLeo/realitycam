//! Middleware modules for the RealityCam API
//!
//! Contains authentication and authorization middleware for protecting routes.

pub mod device_auth;

pub use device_auth::{DeviceAuthConfig, DeviceAuthLayer, DeviceContext};
