//! Middleware modules for the RealityCam API
//!
//! Contains authentication and authorization middleware for protecting routes.

pub mod device_auth;

pub use device_auth::{
    lookup_device, update_device_counter, DeviceAuthConfig, DeviceAuthLayer, DeviceContext,
};
