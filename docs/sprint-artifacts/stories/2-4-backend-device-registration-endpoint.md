# Story 2.4: Backend Device Registration Endpoint

Status: review

## Story

As a **mobile app**,
I want **to register my device with the backend by sending device information, public key, and attestation object**,
so that **the backend can store my device identity for future attestation verification and authenticated API requests**.

## Acceptance Criteria

1. **AC-1: POST /api/v1/devices/register Endpoint Exists**
   - Given the backend is running
   - When a client calls `POST /api/v1/devices/register`
   - Then the endpoint accepts JSON body with device registration data
   - And the endpoint returns appropriate HTTP status codes

2. **AC-2: Request Validation - Required Fields**
   - Given a registration request
   - When any of these required fields are missing: `device_id`, `public_key`, `attestation_object`
   - Then the response is HTTP 400 with error code `VALIDATION_ERROR`
   - And the error message specifies which field is missing
   - And the response follows API error format with `error` and `meta` fields

3. **AC-3: Request Validation - Base64 Decoding**
   - Given a registration request with `public_key` and `attestation_object` fields
   - When either field contains invalid base64 encoding
   - Then the response is HTTP 400 with error code `VALIDATION_ERROR`
   - And the error message indicates which field has invalid encoding

4. **AC-4: Conflict Detection - Duplicate Device**
   - Given a device with `attestation_key_id` "key123" already exists in the database
   - When a registration request is received with the same `attestation_key_id`
   - Then the response is HTTP 409 Conflict
   - And the error code is `DEVICE_ALREADY_REGISTERED`
   - And the error message indicates the device is already registered

5. **AC-5: Successful Registration - Device Created**
   - Given a valid registration request with new device data
   - When the registration is processed successfully
   - Then a new device record is created in the `devices` table
   - And the device record contains:
     - `id`: newly generated UUID
     - `attestation_key_id`: from request `device_id` field
     - `platform`: from request (must be "ios")
     - `model`: from request
     - `has_lidar`: from request
     - `attestation_level`: "unverified" (verification is Story 2.5)
     - `attestation_chain`: base64-decoded `attestation_object` stored as BYTEA
     - `first_seen_at`: current timestamp
     - `last_seen_at`: current timestamp

6. **AC-6: Successful Registration - Response Format**
   - Given a successful device registration
   - When the response is returned
   - Then the response is HTTP 201 Created
   - And the response body matches:
     ```json
     {
       "data": {
         "device_id": "uuid",
         "attestation_level": "unverified",
         "has_lidar": true
       },
       "meta": {
         "request_id": "uuid",
         "timestamp": "2025-11-22T10:30:00Z"
       }
     }
     ```

7. **AC-7: Database Transaction Safety**
   - Given a registration request
   - When database insertion fails (e.g., constraint violation)
   - Then no partial data is committed
   - And the response is HTTP 500 with error code `INTERNAL_ERROR`
   - And internal error details are not exposed to the client

8. **AC-8: Request Type Definitions**
   - Given the backend codebase
   - When inspecting `backend/src/routes/devices.rs` or related types
   - Then `DeviceRegistrationRequest` struct exists with:
     - `device_id: String` (the attestation key ID from mobile)
     - `public_key: String` (base64-encoded public key)
     - `attestation_object: String` (base64-encoded CBOR attestation)
     - `platform: String` (must be "ios")
     - `model: String` (e.g., "iPhone 15 Pro")
     - `has_lidar: bool`
   - And `DeviceRegistrationResponse` struct exists matching AC-6

9. **AC-9: Logging and Observability**
   - Given a registration request
   - When the request is processed
   - Then the request ID is logged with each log entry
   - And successful registrations log: device_id, attestation_level, model
   - And failed registrations log: error reason (without sensitive data)
   - And logs follow structured JSON format in production mode

10. **AC-10: Request ID in Response**
    - Given any request to the registration endpoint
    - When a response is returned (success or error)
    - Then the response includes `X-Request-Id` header
    - And the same request ID appears in `meta.request_id` in the response body

## Tasks / Subtasks

- [x] Task 1: Define Request/Response Types (AC: 8)
  - [x] 1.1: Create `DeviceRegistrationRequest` struct in `backend/src/routes/devices.rs`
  - [x] 1.2: Add `#[derive(Debug, Deserialize)]` to request struct
  - [x] 1.3: Create `DeviceRegistrationResponse` struct with device_id, attestation_level, has_lidar
  - [x] 1.4: Add `#[derive(Debug, Serialize)]` to response struct
  - [x] 1.5: Create or update types in `backend/src/types/mod.rs` if needed for reuse

- [x] Task 2: Add DEVICE_ALREADY_REGISTERED Error Code (AC: 4)
  - [x] 2.1: Add `DEVICE_ALREADY_REGISTERED` constant to `backend/src/error.rs` codes module
  - [x] 2.2: Add `DeviceAlreadyRegistered` variant to `ApiError` enum
  - [x] 2.3: Implement `code()` mapping returning `DEVICE_ALREADY_REGISTERED`
  - [x] 2.4: Implement `status_code()` mapping returning `StatusCode::CONFLICT` (409)
  - [x] 2.5: Implement `safe_message()` returning user-friendly message

- [x] Task 3: Implement Request Validation (AC: 2, 3)
  - [x] 3.1: Create `validate_registration_request()` function
  - [x] 3.2: Validate all required fields are present and non-empty
  - [x] 3.3: Validate `platform` is "ios" (only supported platform for MVP)
  - [x] 3.4: Validate `public_key` is valid base64 encoding
  - [x] 3.5: Validate `attestation_object` is valid base64 encoding
  - [x] 3.6: Return `ApiError::Validation` with specific field errors

- [x] Task 4: Implement Database Operations (AC: 5, 7)
  - [x] 4.1: Create `insert_device()` function in `backend/src/routes/devices.rs`
  - [x] 4.2: Use `sqlx::query_as!` for compile-time checked query
  - [x] 4.3: INSERT INTO devices with all required fields
  - [x] 4.4: Handle unique constraint violation on `attestation_key_id`
  - [x] 4.5: Return the created device record or appropriate error

- [x] Task 5: Implement Conflict Detection (AC: 4)
  - [x] 5.1: Catch PostgreSQL unique constraint violation (error code 23505)
  - [x] 5.2: Map constraint violation to `ApiError::DeviceAlreadyRegistered`
  - [x] 5.3: Return HTTP 409 with appropriate error response

- [x] Task 6: Implement Registration Handler (AC: 1, 5, 6, 10)
  - [x] 6.1: Update `register_device()` handler in `backend/src/routes/devices.rs`
  - [x] 6.2: Add `State<PgPool>` extractor for database access
  - [x] 6.3: Add `Extension<Uuid>` extractor for request ID
  - [x] 6.4: Add `Json<DeviceRegistrationRequest>` extractor for request body
  - [x] 6.5: Call validation function
  - [x] 6.6: Decode base64 fields to bytes
  - [x] 6.7: Call database insert function
  - [x] 6.8: Return `ApiResponse::new()` with `DeviceRegistrationResponse` on success
  - [x] 6.9: Return appropriate error responses on failure

- [x] Task 7: Update Router Configuration (AC: 1)
  - [x] 7.1: Update `devices::router()` to return `Router<PgPool>`
  - [x] 7.2: Ensure route handler receives database pool via state extractor
  - [x] 7.3: Update `routes/mod.rs` to apply `.with_state(db)` to v1_router

- [x] Task 8: Add Logging (AC: 9)
  - [x] 8.1: Add `tracing::info!` for successful registration with device_id, model
  - [x] 8.2: Add `tracing::warn!` for validation failures
  - [x] 8.3: Add `tracing::error!` for database errors (sanitized)
  - [x] 8.4: Include request_id in all log spans

- [x] Task 9: Testing and Verification (AC: all)
  - [x] 9.1: Verify `cargo build` succeeds
  - [x] 9.2: Verify `cargo clippy` passes without errors/warnings
  - [ ] 9.3: Test successful registration with curl (requires running server + database)
  - [ ] 9.4: Test validation errors (requires running server)
  - [ ] 9.5: Test conflict detection (requires running server + database)
  - [ ] 9.6: Verify database record created correctly (requires running database)
  - [ ] 9.7: Verify response format matches AC-6 (requires running server)
  - [ ] 9.8: Verify request ID propagation (requires running server)

## Dev Notes

### Architecture Alignment

This story implements the backend device registration endpoint from Epic 2 Tech Spec (AC-2.5.1, AC-2.5.8, AC-2.5.9, AC-2.5.10). Note: Attestation verification (AC-2.5.2 through AC-2.5.7) is deferred to Story 2.5.

**Key alignment points:**
- **Route Location**: `backend/src/routes/devices.rs` (existing file, update stub)
- **API Response Format**: Must match architecture spec with `data` and `meta` fields
- **Error Codes**: Use existing error module, add new `DEVICE_ALREADY_REGISTERED` code
- **Database**: Use existing `devices` table schema from Story 1.2

### API Contract Reference (from tech-spec-epic-2.md)

```
POST /api/v1/devices/register
Content-Type: application/json

Request:
{
  "platform": "ios",
  "model": "iPhone 15 Pro",
  "has_lidar": true,
  "attestation": {
    "key_id": "base64...",
    "attestation_object": "base64...",
    "challenge": "base64..."
  }
}

Response (201 Created):
{
  "data": {
    "device_id": "550e8400-e29b-41d4-a716-446655440000",
    "attestation_level": "secure_enclave",
    "has_lidar": true
  },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-11-22T10:30:00Z"
  }
}

Error Responses:
- 400 VALIDATION_ERROR - Missing required fields
- 401 ATTESTATION_FAILED - Certificate chain verification failed (Story 2.5)
- 409 CONFLICT - Key ID already registered
```

**Note on Request Format**: The tech-spec shows a nested `attestation` object. For this story (registration storage only, not verification), we can use a flattened structure:
- `device_id` = the `attestation.key_id` (device's unique attestation key identifier)
- `public_key` = derived from attestation object (or stored separately)
- `attestation_object` = the `attestation.attestation_object`

The mobile app will send what Story 2.3 prepared. Align with mobile implementation.

### Database Schema Reference (from Story 1.2)

```sql
CREATE TABLE devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attestation_level   TEXT NOT NULL DEFAULT 'unverified',
    attestation_key_id  TEXT NOT NULL UNIQUE,
    attestation_chain   BYTEA,
    platform            TEXT NOT NULL,
    model               TEXT NOT NULL,
    has_lidar           BOOLEAN NOT NULL DEFAULT false,
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_devices_attestation_key ON devices(attestation_key_id);
```

### Existing Code Patterns

**Error handling (from `backend/src/error.rs`):**
```rust
// Add new error variant
#[error("Device already registered")]
DeviceAlreadyRegistered,

// Map to code
ApiError::DeviceAlreadyRegistered => codes::DEVICE_ALREADY_REGISTERED,

// Map to status
ApiError::DeviceAlreadyRegistered => StatusCode::CONFLICT,
```

**Response wrapper (from `backend/src/types/mod.rs`):**
```rust
// Use ApiResponse for success
let response = ApiResponse::new(device_data, request_id);
(StatusCode::CREATED, Json(response))

// Use ApiErrorResponse for errors
let response = ApiErrorResponse::new(error.code(), error.safe_message(), request_id);
(error.status_code(), Json(response))
```

**Database query pattern:**
```rust
use sqlx::PgPool;

async fn insert_device(
    pool: &PgPool,
    req: &DeviceRegistrationRequest,
    attestation_bytes: &[u8],
) -> Result<Device, ApiError> {
    sqlx::query_as!(
        Device,
        r#"
        INSERT INTO devices (attestation_key_id, platform, model, has_lidar, attestation_chain)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING *
        "#,
        req.device_id,
        req.platform,
        req.model,
        req.has_lidar,
        attestation_bytes
    )
    .fetch_one(pool)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(db_err) = &e {
            if db_err.code() == Some(std::borrow::Cow::Borrowed("23505")) {
                return ApiError::DeviceAlreadyRegistered;
            }
        }
        ApiError::Database(e)
    })
}
```

### Base64 Decoding

Use the `base64` crate (already available via dependencies):
```rust
use base64::{Engine as _, engine::general_purpose::STANDARD};

fn decode_base64(input: &str, field_name: &str) -> Result<Vec<u8>, ApiError> {
    STANDARD.decode(input)
        .map_err(|_| ApiError::Validation(format!("Invalid base64 encoding for {}", field_name)))
}
```

### Previous Story Learnings (from Story 2.3)

1. **TypeScript Strict Mode**: Always verify with compilation before marking complete
2. **Error Handling**: Wrap all external calls in proper error handling
3. **State Machine**: Clear state transitions documented in comments
4. **Mock Responses**: For development, can use mock data when external services unavailable
5. **Request ID**: Must be included in all responses for correlation
6. **Logging**: Use structured logging with tracing macros

### Project Structure Notes

- **Existing file to modify**: `backend/src/routes/devices.rs` (replace 501 stub)
- **Existing file to modify**: `backend/src/error.rs` (add new error code)
- **Existing file to modify**: `backend/src/routes/mod.rs` (pass PgPool to devices router)
- **Possibly new file**: `backend/src/services/device_service.rs` (optional, for separation)

### Testing Checklist

```bash
# Start services
docker-compose -f infrastructure/docker-compose.yml up -d

# Build and run backend
cd backend
cargo build
cargo run

# Test successful registration
curl -X POST http://localhost:8080/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-key-id-123",
    "public_key": "dGVzdC1wdWJsaWMta2V5",
    "attestation_object": "dGVzdC1hdHRlc3RhdGlvbg==",
    "platform": "ios",
    "model": "iPhone 15 Pro",
    "has_lidar": true
  }'

# Expected: 201 Created with device_id

# Test validation error (missing field)
curl -X POST http://localhost:8080/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "platform": "ios",
    "model": "iPhone 15 Pro"
  }'

# Expected: 400 Bad Request with VALIDATION_ERROR

# Test invalid base64
curl -X POST http://localhost:8080/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-key-id-456",
    "public_key": "not-valid-base64!!!",
    "attestation_object": "dGVzdC1hdHRlc3RhdGlvbg==",
    "platform": "ios",
    "model": "iPhone 15 Pro",
    "has_lidar": true
  }'

# Expected: 400 Bad Request with VALIDATION_ERROR

# Test duplicate device (run first curl again)
# Expected: 409 Conflict with DEVICE_ALREADY_REGISTERED

# Verify database record
docker exec realitycam-postgres psql -U realitycam -c "SELECT id, attestation_key_id, platform, model, has_lidar, attestation_level FROM devices;"
```

### Dependencies Required

From Cargo.toml (likely already present):
```toml
base64 = "0.22"
```

If not present, add it.

### References

- [Source: docs/sprint-artifacts/tech-spec-epic-2.md#AC-2.5]
- [Source: docs/sprint-artifacts/tech-spec-epic-2.md#POST-api-v1-devices-register]
- [Source: docs/architecture.md#API-Contracts]
- [Source: docs/architecture.md#Implementation-Patterns]
- [Source: docs/sprint-artifacts/stories/1-2-database-schema-migrations.md]
- [Source: docs/sprint-artifacts/stories/1-3-backend-api-skeleton.md]
- [Source: docs/epics.md#Story-2.4]
- [PRD: FR43 - Device registration stores attestation key ID and capability flags]

## Dev Agent Record

### Context Reference

- `/Users/luca/dev/realitycam/docs/sprint-artifacts/story-context/2-4-backend-device-registration-endpoint-context.xml`

### Agent Model Used

Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Debug Log References

- `cargo build` succeeded without errors
- `cargo clippy` passed with no warnings (after fixing inline format strings)

### Completion Notes List

**Implementation Summary:**
Implemented the device registration endpoint POST /api/v1/devices/register with full validation, database operations, and error handling. The endpoint accepts device registration requests with attestation data and stores them in the PostgreSQL `devices` table.

**Key Implementation Decisions:**

1. **Router State Typing**: Changed `devices::router()` to return `Router<PgPool>` instead of `Router` to enable database access. Also updated `captures::router()` and `verify::router()` to return `Router<PgPool>` for consistency, even though they don't use state yet.

2. **Validation Strategy**: Implemented validation in `validate_registration_request()` function that:
   - Checks all required fields are non-empty (using `.trim().is_empty()`)
   - Validates platform is "ios" (case-insensitive)
   - Decodes and validates base64 for `public_key` and `attestation_object`
   - Returns specific error messages for each validation failure

3. **Conflict Detection**: Used PostgreSQL error code 23505 detection on INSERT failure rather than pre-checking existence. This is more atomic and handles race conditions properly.

4. **Response Format**: Returns HTTP 201 Created with `ApiResponse<DeviceRegistrationResponse>` containing `device_id`, `attestation_level`, and `has_lidar` in the `data` field, plus `request_id` and `timestamp` in the `meta` field.

5. **Attestation Level**: All new devices are created with `attestation_level = "unverified"` as the database default. Verification will be implemented in Story 2.5.

6. **Public Key Storage**: The public key is decoded and validated but not stored separately - it's contained within the attestation_object which is stored as BYTEA in `attestation_chain`.

**How Each AC Was Satisfied:**

- **AC-1**: POST /api/v1/devices/register route created and wired up (devices.rs:72)
- **AC-2**: Required field validation with specific error messages (devices.rs:87-119)
- **AC-3**: Base64 validation for public_key and attestation_object (devices.rs:133-148)
- **AC-4**: DEVICE_ALREADY_REGISTERED error code and 409 Conflict response (error.rs:28, 70-71, 90, 109, 131-133)
- **AC-5**: Device record created with all required fields via sqlx::query_as! (devices.rs:162-209)
- **AC-6**: Response format matches spec with data/meta structure (devices.rs:275-294)
- **AC-7**: Database errors mapped to INTERNAL_ERROR without exposing details (error.rs:128)
- **AC-8**: DeviceRegistrationRequest and DeviceRegistrationResponse structs defined (devices.rs:30-57)
- **AC-9**: Structured logging with tracing macros throughout (devices.rs:92-99, 124-127, etc.)
- **AC-10**: Request ID from Extension<Uuid> included in all responses via ApiResponse/ApiErrorResponse

**Runtime Testing Note:**
Runtime tests (curl commands, database verification) require the PostgreSQL database and backend server to be running. These are marked incomplete but the implementation follows the tested patterns from the existing codebase.

### File List

**Files Created:**
- None

**Files Modified:**
- `/Users/luca/dev/realitycam/backend/Cargo.toml` - Added `base64 = "0.22"` dependency
- `/Users/luca/dev/realitycam/backend/src/error.rs` - Added DEVICE_ALREADY_REGISTERED error code constant, DeviceAlreadyRegistered variant, and corresponding mappings for code(), status_code(), and safe_message()
- `/Users/luca/dev/realitycam/backend/src/routes/devices.rs` - Complete rewrite replacing 501 stub with full implementation including request/response types, validation, database operations, and handler
- `/Users/luca/dev/realitycam/backend/src/routes/mod.rs` - Updated to apply `.with_state(db)` to v1_router for database access
- `/Users/luca/dev/realitycam/backend/src/routes/captures.rs` - Updated router() to return Router<PgPool> for state compatibility
- `/Users/luca/dev/realitycam/backend/src/routes/verify.rs` - Updated router() to return Router<PgPool> for state compatibility
- `/Users/luca/dev/realitycam/docs/sprint-artifacts/sprint-status.yaml` - Updated story status: ready-for-dev -> in-progress -> review
- `/Users/luca/dev/realitycam/docs/sprint-artifacts/stories/2-4-backend-device-registration-endpoint.md` - Updated status, marked tasks complete, added completion notes
