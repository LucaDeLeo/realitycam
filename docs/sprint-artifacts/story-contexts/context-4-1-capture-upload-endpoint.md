# Story Context: 4-1 Capture Upload Endpoint

**Story Key:** 4-1-capture-upload-endpoint
**Status:** ready-for-dev
**Generated:** 2025-11-23

---

## 1. Story Reference

**File:** `docs/sprint-artifacts/stories/story-4-1-capture-upload-endpoint.md`

**Summary:** Implement POST /api/v1/captures endpoint to accept multipart uploads of photo + depth map + metadata from authenticated iOS devices, store files in S3, create database records, and return capture_id with verification URL.

---

## 2. Epic Context

**Epic:** 4 - Upload, Processing & Evidence Generation
**Tech Spec:** `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

This story implements AC-4.1 from Epic 4, establishing the upload pipeline foundation. Subsequent stories build on this:
- Story 4-2: Retry queue logic (mobile side)
- Story 4-4: Assertion verification
- Story 4-5: Depth analysis
- Story 4-7: Evidence package assembly

---

## 3. Documentation Artifacts

### 3.1 Architecture Document
**Path:** `docs/architecture.md`

**Relevant Sections:**
- API Contracts > Capture Upload (lines 531-553)
- Security Architecture > Authentication Flow (lines 596-612)
- Data Architecture > Database Schema (lines 456-486)
- Data Architecture > S3 Structure (lines 488-500)
- Implementation Patterns > API Response Format (lines 397-419)
- Implementation Patterns > Error Codes (lines 421-434)

**Key Constraints:**
- All requests require device signature headers (X-Device-Id, X-Device-Timestamp, X-Device-Signature)
- Response must follow standard envelope: `{ data: {...}, meta: { request_id, timestamp } }`
- S3 bucket structure: `captures/{capture_id}/original.jpg`, `captures/{capture_id}/depth.gz`

### 3.2 Epic 4 Tech Spec
**Path:** `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

**Relevant Sections:**
- AC-4.1: Multipart Upload Endpoint (lines 729-735)
- APIs: POST /api/v1/captures (lines 311-383)
- Data Models: Capture Entity SQL (lines 98-124)
- Data Models: Rust Types (lines 165-250)
- Data Models: Mobile Types (lines 254-307)
- Backend Dependencies (lines 688-698)
- Non-Functional: Performance targets (lines 589-605)
- Non-Functional: Security requirements (lines 609-634)

**Performance Requirements:**
- Response within 2 seconds for typical payloads (~4MB)
- Stream multipart directly to S3 (no memory buffering)
- Evidence processing < 5s total (handled by later stories)

**Error Response Codes:**
| HTTP Status | Error Code | Condition |
|-------------|------------|-----------|
| 400 | VALIDATION_ERROR | Missing required parts, invalid metadata |
| 401 | SIGNATURE_INVALID | Device signature verification failed |
| 401 | TIMESTAMP_EXPIRED | Request timestamp outside 5-minute window |
| 404 | DEVICE_NOT_FOUND | Unknown device ID |
| 413 | PAYLOAD_TOO_LARGE | Photo > 10MB or depth > 5MB |
| 429 | RATE_LIMITED | Exceeded 10 captures/hour/device |
| 500 | STORAGE_ERROR | S3 upload failed |

---

## 4. Existing Code Interfaces

### 4.1 Captures Route (STUB TO REPLACE)
**Path:** `backend/src/routes/captures.rs`

```rust
//! Capture routes
//!
//! Stub implementations for capture upload and retrieval endpoints.

use axum::{
    extract::{Extension, Path},
    routing::{get, post},
    Json, Router,
};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::ApiError;
use crate::types::ApiErrorResponse;

/// Creates the captures routes router.
pub fn router() -> Router<PgPool> {
    Router::new()
        .route("/", post(upload_capture))
        .route("/{id}", get(get_capture))
}

/// POST /api/v1/captures - Upload a new capture
/// Currently returns 501 Not Implemented.
async fn upload_capture(
    Extension(request_id): Extension<Uuid>,
) -> (axum::http::StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}

/// GET /api/v1/captures/{id} - Get capture by ID
/// Currently returns 501 Not Implemented.
async fn get_capture(
    Path(_id): Path<String>,
    Extension(request_id): Extension<Uuid>,
) -> (axum::http::StatusCode, Json<ApiErrorResponse>) {
    let error = ApiError::NotImplemented;
    let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
    (error.status_code(), Json(response))
}
```

### 4.2 Router Configuration
**Path:** `backend/src/routes/mod.rs`

```rust
// Captures router with device authentication middleware
let captures_router = captures::router()
    .with_state(state.db.clone())
    .layer(DeviceAuthLayer::new(state.db.clone(), device_auth_config));

// V1 API routes
let v1_router = Router::new()
    .nest("/devices", devices::router())
    .nest("/captures", captures_router)
    .merge(verify::router().with_state(state.db.clone()))
    .with_state(state);
```

**Key Points:**
- Captures router already has DeviceAuthLayer applied
- DeviceContext is injected into request extensions by middleware
- State provides access to `db: PgPool`, `challenge_store`, `config`

### 4.3 Device Auth Middleware (DeviceContext)
**Path:** `backend/src/middleware/device_auth.rs`

```rust
/// Device context injected into request extensions after successful authentication
#[derive(Debug, Clone)]
pub struct DeviceContext {
    /// Device UUID
    pub device_id: Uuid,
    /// Attestation level of the device
    pub attestation_level: AttestationLevel,
    /// Device model (e.g., "iPhone 15 Pro")
    pub model: String,
    /// Whether device has LiDAR sensor
    pub has_lidar: bool,
    /// True if signature was verified (false for unverified devices)
    pub is_verified: bool,
}

pub enum AttestationLevel {
    SecureEnclave,
    Unverified,
}
```

**Usage in Handler:**
```rust
// Extract DeviceContext from request extensions
Extension(device_ctx): Extension<DeviceContext>
// Access: device_ctx.device_id, device_ctx.attestation_level, etc.
```

### 4.4 Capture Model
**Path:** `backend/src/models/capture.rs`

```rust
/// A photo capture with verification evidence and confidence scoring.
#[derive(Debug, sqlx::FromRow, Serialize)]
pub struct Capture {
    pub id: Uuid,
    pub device_id: Uuid,
    pub target_media_hash: Vec<u8>,
    pub depth_map_key: Option<String>,
    pub evidence: serde_json::Value,
    pub confidence_level: String,
    pub status: String,
    pub captured_at: DateTime<Utc>,
    pub uploaded_at: DateTime<Utc>,
}
```

**Note:** Per Epic 4 Tech Spec, this model needs additional fields:
- `photo_s3_key: String`
- `depth_map_s3_key: String` (rename from `depth_map_key`)
- `thumbnail_s3_key: Option<String>`
- `location_precise: Option<serde_json::Value>`
- `location_coarse: Option<String>`

### 4.5 Database Pool
**Path:** `backend/src/db.rs`

```rust
pub async fn create_pool(config: &Config) -> Result<PgPool, sqlx::Error>
pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError>
```

### 4.6 API Types
**Path:** `backend/src/types/mod.rs`

```rust
/// Standard API success response wrapper.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub data: T,
    pub meta: Meta,
}

impl<T> ApiResponse<T> {
    pub fn new(data: T, request_id: Uuid) -> Self { ... }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Meta {
    pub request_id: Uuid,
    pub timestamp: DateTime<Utc>,
}
```

### 4.7 Error Types
**Path:** `backend/src/error.rs`

```rust
pub enum ApiError {
    NotImplemented,
    Validation(String),
    Internal(#[from] anyhow::Error),
    Database(#[from] sqlx::Error),
    DeviceNotFound,
    CaptureNotFound,
    // ... more variants
    StorageError(String),
    // NOTE: Need to add PayloadTooLarge variant
}
```

**Missing Error Codes for Story 4-1:**
```rust
// Add to ApiError enum:
#[error("Payload too large")]
PayloadTooLarge,

// Add to codes module:
pub const PAYLOAD_TOO_LARGE: &str = "PAYLOAD_TOO_LARGE";
```

### 4.8 Services Module
**Path:** `backend/src/services/mod.rs`

```rust
pub mod attestation;
pub mod challenge_store;
// NOTE: Add storage module for S3 operations
```

### 4.9 Device Route (Pattern Reference)
**Path:** `backend/src/routes/devices.rs`

**Pattern for Request/Response Structs:**
```rust
#[derive(Debug, Deserialize)]
pub struct DeviceRegistrationRequest {
    pub platform: String,
    pub model: String,
    pub has_lidar: bool,
    // ...
}

#[derive(Debug, Serialize)]
pub struct DeviceRegistrationResponse {
    pub device_id: Uuid,
    pub attestation_level: String,
    pub has_lidar: bool,
}
```

**Pattern for Handler:**
```rust
async fn register_device(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Json(req): Json<DeviceRegistrationRequest>,
) -> Result<(StatusCode, Json<ApiResponse<DeviceRegistrationResponse>>), ApiErrorWithRequestId> {
    // Validate, process, respond
}
```

### 4.10 Main App Setup
**Path:** `backend/src/main.rs`

**App State:**
```rust
let app_state = routes::AppState {
    db: pool.clone(),
    challenge_store,
    config: std::sync::Arc::new(config.clone()),
};
```

**Note:** For S3 client, either add to AppState or create in handler using aws-config.

---

## 5. Shared Types (Mobile/Web)

**Path:** `packages/shared/src/types/capture.ts`

### CaptureMetadata (Upload Payload)
```typescript
export interface CaptureMetadata {
  captured_at: string;           // ISO 8601
  device_model: string;
  photo_hash: string;            // SHA-256 base64
  depth_map_dimensions: {
    width: number;
    height: number;
  };
  location?: CaptureLocation;
  assertion?: string;            // Base64 per-capture assertion
}
```

### ProcessedCapture (What Mobile Sends)
```typescript
export interface ProcessedCapture {
  id: string;
  photoUri: string;
  photoHash: string;
  compressedDepthMap: string;    // Base64 gzipped Float32Array
  depthDimensions: { width: number; height: number };
  metadata: CaptureMetadata;
  assertion?: string;
  status: CaptureStatus;
  createdAt: string;
}
```

### CaptureLocation
```typescript
export interface CaptureLocation {
  latitude: number;
  longitude: number;
  altitude: number | null;
  accuracy: number;
  timestamp: string;
}
```

---

## 6. Development Constraints

### 6.1 Architecture Constraints (ADRs)
- **ADR-005:** Device signature required on all requests (already handled by middleware)
- **ADR-006:** JSONB for evidence storage (flexible schema)
- **ADR-007:** @expo/app-integrity returns assertion as base64 string

### 6.2 Performance Constraints
- Response within 2 seconds for typical 4MB payload
- Stream multipart to S3 (no full memory buffering)
- Photo max: 10MB, Depth max: 5MB

### 6.3 Security Constraints
- Never expose internal S3 paths in error messages
- Never expose database errors to client
- Device auth middleware validates signature (already applied)

### 6.4 Rate Limiting
- 10 captures/hour/device (placeholder for MVP, implement enforcement later)
- Return 429 with Retry-After header when enforced

---

## 7. Dependencies

### 7.1 Cargo.toml (Current)
```toml
[dependencies]
axum = "0.8"
axum-extra = { version = "0.10", features = ["typed-header"] }
# ... existing deps
aws-sdk-s3 = "1"
aws-config = "1"
```

### 7.2 Required Additions
```toml
# Add multipart feature to axum-extra
axum-extra = { version = "0.10", features = ["typed-header", "multipart"] }
```

### 7.3 Environment Variables (S3)
```env
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
S3_BUCKET=realitycam-captures

# For LocalStack development
AWS_ENDPOINT_URL=http://localhost:4566
```

---

## 8. Testing Context

### 8.1 Unit Test Targets
- Metadata JSON validation
- File size checks (photo <= 10MB, depth <= 5MB)
- Timestamp format validation (ISO 8601)
- Location coordinate validation (-90 to 90, -180 to 180)
- Depth map dimension validation (< 1000x1000)

### 8.2 Integration Test Requirements
- Full upload flow with LocalStack S3 and test database
- Mock DeviceContext for handler testing
- Test all error paths (400, 401, 413, 500)

### 8.3 Test Data
- Sample JPEG (3-4MB typical)
- Gzipped Float32Array depth map (~1MB)
- Valid CaptureMetadata JSON
- Mock DeviceContext with test device_id

---

## 9. File Structure After Implementation

```
backend/src/
+-- routes/
|   +-- captures.rs          # MODIFIED - implement upload_capture handler
+-- types/
|   +-- mod.rs               # MODIFIED - export capture types
|   +-- capture.rs           # NEW - upload request/response types
+-- services/
|   +-- mod.rs               # MODIFIED - export storage service
|   +-- storage.rs           # NEW - S3 upload functions
+-- models/
|   +-- capture.rs           # MODIFIED - add S3 key fields
+-- error.rs                 # MODIFIED - add PayloadTooLarge error
```

---

## 10. Request/Response Format

### 10.1 Request Format
```http
POST /api/v1/captures
Content-Type: multipart/form-data; boundary=----boundary123
X-Device-Id: {device_uuid}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {base64_signature}

------boundary123
Content-Disposition: form-data; name="photo"; filename="capture.jpg"
Content-Type: image/jpeg

{JPEG binary ~3MB}
------boundary123
Content-Disposition: form-data; name="depth_map"; filename="depth.gz"
Content-Type: application/gzip

{gzipped Float32Array ~1MB}
------boundary123
Content-Disposition: form-data; name="metadata"
Content-Type: application/json

{
  "captured_at": "2025-11-23T10:30:00.123Z",
  "device_model": "iPhone 15 Pro",
  "photo_hash": "base64-sha256...",
  "depth_map_dimensions": { "width": 256, "height": 192 },
  "assertion": "base64-assertion...",
  "location": { "latitude": 37.7749, "longitude": -122.4194 }
}
------boundary123--
```

### 10.2 Response Format (Success)
```json
{
  "data": {
    "capture_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/550e8400-e29b-41d4-a716-446655440000"
  },
  "meta": {
    "request_id": "req-abc123",
    "timestamp": "2025-11-23T10:30:01Z"
  }
}
```

### 10.3 Response Format (Error)
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Missing required part: metadata"
  },
  "meta": {
    "request_id": "req-abc123",
    "timestamp": "2025-11-23T10:30:01Z"
  }
}
```

---

## 11. Implementation Notes

### 11.1 Key Implementation Steps
1. Add `multipart` feature to axum-extra in Cargo.toml
2. Create `types/capture.rs` with request/response structs
3. Create `services/storage.rs` with S3 upload functions
4. Update `models/capture.rs` with S3 key fields
5. Add `PayloadTooLarge` to error.rs
6. Replace stub in `routes/captures.rs` with full implementation

### 11.2 S3 Key Pattern
```
captures/{capture_id}/photo.jpg
captures/{capture_id}/depth.gz
```

### 11.3 Verification URL Pattern
```
https://realitycam.app/verify/{capture_id}
```
Note: Use config for base URL in production.

### 11.4 Multipart Handling with Axum
```rust
use axum_extra::extract::Multipart;

async fn upload_capture(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Extension(device_ctx): Extension<DeviceContext>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<CaptureUploadResponse>>), ApiErrorWithRequestId> {
    // Extract parts from multipart
    while let Some(field) = multipart.next_field().await? {
        let name = field.name();
        match name {
            Some("photo") => { /* handle photo */ },
            Some("depth_map") => { /* handle depth map */ },
            Some("metadata") => { /* handle metadata JSON */ },
            _ => { /* ignore unknown fields */ }
        }
    }
}
```

### 11.5 S3 Client Setup
```rust
use aws_config::BehaviorVersion;
use aws_sdk_s3::Client as S3Client;

// In handler or service init:
let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
let s3_client = S3Client::new(&config);
```

---

## 12. Acceptance Criteria Checklist

- [ ] AC-1: POST /api/v1/captures accepts multipart with photo, depth_map, metadata
- [ ] AC-2: Multipart parts extracted with content-type validation
- [ ] AC-3: Request validation (file sizes, metadata schema, timestamp)
- [ ] AC-4: S3 storage integration (photo and depth uploaded)
- [ ] AC-5: Response with capture_id, status, verification_url
- [ ] AC-6: Error handling (400, 401, 413, 500 with request_id)
- [ ] AC-7: Rate limiting placeholder (config flag, 429 type)

---

_Context generated by Story Context Assembly Workflow_
_Date: 2025-11-23_
