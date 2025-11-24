//! S3 Storage Service (Story 4.1)
//!
//! Provides functions for uploading capture files to S3-compatible storage.
//! Supports both AWS S3 and LocalStack for development/testing.

use aws_config::BehaviorVersion;
use aws_sdk_s3::config::Credentials;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::Client as S3Client;
use tracing::{info, warn};
use uuid::Uuid;

use crate::config::Config;
use crate::error::ApiError;

// ============================================================================
// S3 Key Patterns
// ============================================================================

/// Generates the S3 key for a capture's photo
/// Pattern: captures/{capture_id}/photo.jpg
pub fn photo_s3_key(capture_id: Uuid) -> String {
    format!("captures/{capture_id}/photo.jpg")
}

/// Generates the S3 key for a capture's depth map
/// Pattern: captures/{capture_id}/depth.gz
pub fn depth_map_s3_key(capture_id: Uuid) -> String {
    format!("captures/{capture_id}/depth.gz")
}

// ============================================================================
// Storage Service
// ============================================================================

/// S3 storage service for capture file uploads
#[derive(Clone)]
pub struct StorageService {
    pub(crate) client: S3Client,
    pub(crate) bucket: String,
}

impl StorageService {
    /// Creates a new StorageService from application config
    pub async fn new(config: &Config) -> Self {
        // Load AWS config with custom endpoint for LocalStack
        let client = if config.s3_endpoint.contains("localhost")
            || config.s3_endpoint.contains("127.0.0.1")
            || config.s3_endpoint.contains("localstack")
        {
            // LocalStack configuration - use explicit credentials and path-style
            info!(
                endpoint = %config.s3_endpoint,
                bucket = %config.s3_bucket,
                "Configuring S3 client for LocalStack"
            );

            // LocalStack accepts any credentials
            let creds = Credentials::new("test", "test", None, None, "localstack");

            let s3_config = aws_sdk_s3::Config::builder()
                .behavior_version(BehaviorVersion::latest())
                .endpoint_url(&config.s3_endpoint)
                .credentials_provider(creds)
                .region(aws_sdk_s3::config::Region::new("us-east-1"))
                .force_path_style(true)
                .build();

            S3Client::from_conf(s3_config)
        } else {
            // Production AWS configuration
            info!(
                bucket = %config.s3_bucket,
                "Configuring S3 client for AWS"
            );
            let aws_config = aws_config::load_defaults(BehaviorVersion::latest()).await;
            S3Client::new(&aws_config)
        };

        Self {
            client,
            bucket: config.s3_bucket.clone(),
        }
    }

    /// Uploads a photo to S3
    ///
    /// # Arguments
    /// * `capture_id` - Unique capture identifier
    /// * `photo_bytes` - Raw JPEG photo data
    ///
    /// # Returns
    /// The S3 key where the photo was stored
    pub async fn upload_photo(
        &self,
        capture_id: Uuid,
        photo_bytes: Vec<u8>,
    ) -> Result<String, ApiError> {
        let key = photo_s3_key(capture_id);
        let size = photo_bytes.len();

        info!(
            capture_id = %capture_id,
            key = %key,
            size_bytes = size,
            "Uploading photo to S3"
        );

        self.client
            .put_object()
            .bucket(&self.bucket)
            .key(&key)
            .body(ByteStream::from(photo_bytes))
            .content_type("image/jpeg")
            .send()
            .await
            .map_err(|e| {
                warn!(
                    capture_id = %capture_id,
                    error = %e,
                    "Failed to upload photo to S3"
                );
                ApiError::StorageError("Failed to upload photo".to_string())
            })?;

        info!(
            capture_id = %capture_id,
            key = %key,
            "Photo uploaded successfully"
        );

        Ok(key)
    }

    /// Uploads a depth map to S3
    ///
    /// # Arguments
    /// * `capture_id` - Unique capture identifier
    /// * `depth_map_bytes` - Gzipped depth map data
    ///
    /// # Returns
    /// The S3 key where the depth map was stored
    pub async fn upload_depth_map(
        &self,
        capture_id: Uuid,
        depth_map_bytes: Vec<u8>,
    ) -> Result<String, ApiError> {
        let key = depth_map_s3_key(capture_id);
        let size = depth_map_bytes.len();

        info!(
            capture_id = %capture_id,
            key = %key,
            size_bytes = size,
            "Uploading depth map to S3"
        );

        self.client
            .put_object()
            .bucket(&self.bucket)
            .key(&key)
            .body(ByteStream::from(depth_map_bytes))
            .content_type("application/gzip")
            .send()
            .await
            .map_err(|e| {
                warn!(
                    capture_id = %capture_id,
                    error = %e,
                    "Failed to upload depth map to S3"
                );
                ApiError::StorageError("Failed to upload depth map".to_string())
            })?;

        info!(
            capture_id = %capture_id,
            key = %key,
            "Depth map uploaded successfully"
        );

        Ok(key)
    }

    /// Uploads both photo and depth map for a capture
    ///
    /// Performs uploads in parallel for efficiency.
    ///
    /// # Arguments
    /// * `capture_id` - Unique capture identifier
    /// * `photo_bytes` - Raw JPEG photo data
    /// * `depth_map_bytes` - Gzipped depth map data
    ///
    /// # Returns
    /// Tuple of (photo_s3_key, depth_map_s3_key)
    pub async fn upload_capture_files(
        &self,
        capture_id: Uuid,
        photo_bytes: Vec<u8>,
        depth_map_bytes: Vec<u8>,
    ) -> Result<(String, String), ApiError> {
        // Clone self for the parallel uploads
        let storage_photo = self.clone();
        let storage_depth = self.clone();

        // Upload in parallel
        let (photo_result, depth_result) = tokio::join!(
            storage_photo.upload_photo(capture_id, photo_bytes),
            storage_depth.upload_depth_map(capture_id, depth_map_bytes),
        );

        // Handle results
        let photo_key = photo_result?;
        let depth_key = depth_result?;

        Ok((photo_key, depth_key))
    }

    /// Returns the bucket name (for testing/debugging)
    #[allow(dead_code)]
    pub fn bucket(&self) -> &str {
        &self.bucket
    }

    /// Downloads a depth map from S3
    ///
    /// # Arguments
    /// * `capture_id` - Unique capture identifier
    ///
    /// # Returns
    /// The raw gzipped depth map bytes
    pub async fn download_depth_map(&self, capture_id: Uuid) -> Result<Vec<u8>, ApiError> {
        let key = depth_map_s3_key(capture_id);

        tracing::debug!(
            capture_id = %capture_id,
            key = %key,
            "Downloading depth map from S3"
        );

        let response = self
            .client
            .get_object()
            .bucket(&self.bucket)
            .key(&key)
            .send()
            .await
            .map_err(|e| {
                warn!(
                    capture_id = %capture_id,
                    key = %key,
                    error = %e,
                    "Failed to download depth map from S3"
                );
                ApiError::StorageError(format!("Failed to download depth map: {e}"))
            })?;

        let bytes = response
            .body
            .collect()
            .await
            .map_err(|e| {
                warn!(
                    capture_id = %capture_id,
                    error = %e,
                    "Failed to read depth map body from S3"
                );
                ApiError::StorageError(format!("Failed to read depth map body: {e}"))
            })?
            .into_bytes()
            .to_vec();

        tracing::debug!(
            capture_id = %capture_id,
            key = %key,
            size_bytes = bytes.len(),
            "Depth map downloaded successfully"
        );

        Ok(bytes)
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_photo_s3_key() {
        let capture_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let key = photo_s3_key(capture_id);
        assert_eq!(
            key,
            "captures/550e8400-e29b-41d4-a716-446655440000/photo.jpg"
        );
    }

    #[test]
    fn test_depth_map_s3_key() {
        let capture_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let key = depth_map_s3_key(capture_id);
        assert_eq!(
            key,
            "captures/550e8400-e29b-41d4-a716-446655440000/depth.gz"
        );
    }
}
