# Story Context: 4-4 Attestation Verification on Upload

Generated: 2025-11-23
Story: 4-4-attestation-verification-upload
Epic: 4 - Upload, Processing & Evidence Generation

---

## Story Reference

**Story File**: `docs/sprint-artifacts/stories/story-4-4-attestation-verification-upload.md`

**Story Summary**: Implement per-capture attestation (assertion) verification on the backend during capture upload. This verifies the assertion's signature against the device's registered public key, validates the counter for replay protection, and records the hardware_attestation status in the evidence package.

**Parent Epic Tech Spec**: `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

---

## Acceptance Criteria Overview

| AC | Summary | Key Requirement |
|----|---------|-----------------|
| AC-1 | Assertion Decoding | Decode base64 CBOR assertion, extract authenticatorData and signature |
| AC-2 | Signature Verification | Verify EC P-256 signature against device's stored public_key |
| AC-3 | Nonce/Challenge Binding | Verify clientDataHash binds to photo_hash + captured_at |
| AC-4 | Counter Validation | Counter must be strictly greater than stored assertion_counter |
| AC-5 | Confidence Score Impact | Set hardware_attestation.status (pass/fail/unavailable) |
| AC-6 | Failure Handling | Log failures but continue processing, record in evidence |
| AC-7 | Upload Pipeline Integration | Run after S3 upload, complete within 500ms |

---

## Documentation Artifacts

### Epic Tech Spec (Primary Reference)

**File**: `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

**Relevant Sections**:
- **AC-4.4: Assertion Verification** (lines 750-755) - Authoritative acceptance criteria
- **Evidence Package Schema** (lines 126-161) - JSONB structure definition
- **Rust Types** (lines 165-250) - EvidencePackage, HardwareAttestation, CheckStatus, ConfidenceLevel definitions
- **Evidence Processing Pipeline** (lines 484-550) - Shows assertion verification step in workflow
- **Performance** (lines 587-605) - Assertion verification must complete in < 500ms
- **Security: Threat Mitigations** (lines 625-630) - Counter replay protection requirements

**Key Specifications from Tech Spec**:

```typescript
// Evidence Package Schema (TypeScript)
interface EvidencePackage {
  hardware_attestation: {
    status: 'pass' | 'fail' | 'unavailable';
    level: 'secure_enclave' | 'unverified';
    device_model: string;
    assertion_verified: boolean;
    counter_valid: boolean;
  };
  // ... other fields
}
```

```rust
// Rust Types from Tech Spec
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareAttestation {
    pub status: CheckStatus,
    pub level: AttestationLevel,
    pub device_model: String,
    pub assertion_verified: bool,
    pub counter_valid: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CheckStatus {
    Pass,
    Fail,
    Unavailable,
}

impl ConfidenceLevel {
    pub fn calculate(evidence: &EvidencePackage) -> Self {
        if evidence.hardware_attestation.status == CheckStatus::Fail
            || evidence.depth_analysis.status == CheckStatus::Fail
        {
            return ConfidenceLevel::Suspicious;
        }
        let hw_pass = evidence.hardware_attestation.status == CheckStatus::Pass;
        let depth_pass = evidence.depth_analysis.is_likely_real_scene;
        match (hw_pass, depth_pass) {
            (true, true) => ConfidenceLevel::High,
            (true, false) | (false, true) => ConfidenceLevel::Medium,
            (false, false) => ConfidenceLevel::Low,
        }
    }
}
```

### Shared Types

**File**: `packages/shared/src/types/evidence.ts`

```typescript
export type ConfidenceLevel = 'high' | 'medium' | 'low' | 'suspicious';
export type EvidenceStatus = 'pass' | 'fail' | 'unavailable';

export interface HardwareAttestation {
  status: EvidenceStatus;
  level: 'secure_enclave' | 'unverified';
  device_model: string;
}
```

---

## Existing Code Interfaces

### 1. Attestation Service - CBOR Parsing and Verification

**File**: `backend/src/services/attestation.rs`

**Purpose**: Device attestation verification service with CBOR parsing, certificate chain verification, and public key extraction. Contains reusable functions for assertion parsing.

**Reusable Functions**:

```rust
/// Parses authenticator data structure (REUSE for assertions)
/// Layout: rpIdHash(32) + flags(1) + counter(4) + [optional attested credential data]
pub fn parse_authenticator_data(data: &[u8]) -> Result<AuthenticatorData, AttestationError>

/// Decodes base64-encoded attestation/assertion object into CBOR structure
pub fn decode_attestation_object(base64_data: &str) -> Result<AttestationObject, AttestationError>

/// Extracts public key from COSE key structure (65-byte uncompressed EC point)
pub fn extract_public_key(cose_key_cbor: &[u8]) -> Result<Vec<u8>, AttestationError>
```

**Key Data Structures**:

```rust
pub struct AuthenticatorData {
    pub rp_id_hash: [u8; 32],      // SHA256 of App ID
    pub flags: u8,
    pub counter: u32,              // CRITICAL: For replay protection
    pub aaguid: [u8; 16],
    pub credential_id: Vec<u8>,
    pub public_key_cbor: Vec<u8>,
}

pub enum AttestationError {
    InvalidBase64,
    InvalidCbor(String),
    MissingField(&'static str),
    // ... other variants
}
```

**CBOR Helper Functions** (can be made public/reused):

```rust
fn find_text_value<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a str>
fn find_bytes_value<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a [u8]>
fn find_map_value<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a [(Value, Value)]>
```

### 2. Device Auth Middleware - Assertion Verification Pattern

**File**: `backend/src/middleware/device_auth.rs`

**Purpose**: Per-request assertion verification for API authentication. Contains the signature verification pattern to reuse.

**Key Function to Reference**:

```rust
/// Verifies device assertion signature - returns new counter if successful
fn verify_device_assertion(
    device: &Device,
    timestamp_ms: i64,
    body: &Bytes,
    signature_bytes: &[u8],
) -> Result<u32, ApiError> {
    // 1. Parse CBOR assertion
    let assertion = parse_cbor_assertion(signature_bytes)?;

    // 2. Parse authenticator data for counter
    let auth_data = parse_assertion_auth_data(&assertion.authenticator_data)?;

    // 3. Verify counter is strictly greater (replay protection)
    if auth_data.counter as i64 <= device.assertion_counter {
        return Err(ApiError::ReplayDetected);
    }

    // 4. Build client data hash
    let body_hash = Sha256::digest(body);
    let body_hash_hex = hex::encode(body_hash);
    let client_data = format!("{timestamp_ms}|{body_hash_hex}");
    let client_data_hash = Sha256::digest(client_data.as_bytes());

    // 5. Build message: authenticatorData || clientDataHash
    let mut message = assertion.authenticator_data.clone();
    message.extend_from_slice(&client_data_hash);

    // 6. Verify EC signature
    let verifying_key = VerifyingKey::from_sec1_bytes(public_key_bytes)?;
    let signature = parse_signature(&assertion.signature)?;
    verifying_key.verify(&message, &signature)?;

    Ok(auth_data.counter)
}
```

**CBOR Assertion Parsing**:

```rust
struct ParsedAssertion {
    authenticator_data: Vec<u8>,
    signature: Vec<u8>,
}

fn parse_cbor_assertion(data: &[u8]) -> Result<ParsedAssertion, ApiError> {
    let value: Value = ciborium::from_reader(data)?;
    let map = value.as_map()?;

    let authenticator_data = map.iter()
        .find(|(k, _)| k.as_text() == Some("authenticatorData"))
        .and_then(|(_, v)| v.as_bytes())
        .map(|b| b.to_vec())?;

    let signature = map.iter()
        .find(|(k, _)| k.as_text() == Some("signature"))
        .and_then(|(_, v)| v.as_bytes())
        .map(|b| b.to_vec())?;

    Ok(ParsedAssertion { authenticator_data, signature })
}
```

**Assertion Auth Data Parsing** (shorter than attestation - 37 bytes minimum):

```rust
struct AssertionAuthData {
    rp_id_hash: [u8; 32],
    flags: u8,
    counter: u32,
}

fn parse_assertion_auth_data(data: &[u8]) -> Result<AssertionAuthData, ApiError> {
    if data.len() < 37 {
        return Err(ApiError::Validation("Auth data too short".to_string()));
    }
    let rp_id_hash: [u8; 32] = data[0..32].try_into()?;
    let flags = data[32];
    let counter = u32::from_be_bytes(data[33..37].try_into()?);
    Ok(AssertionAuthData { rp_id_hash, flags, counter })
}
```

**Signature Parsing** (supports DER and raw r||s):

```rust
fn parse_signature(sig_bytes: &[u8]) -> Result<Signature, ApiError> {
    // Try DER format first
    if let Ok(sig) = Signature::from_der(sig_bytes) {
        return Ok(sig);
    }
    // Try raw r||s format (64 bytes for P-256)
    if sig_bytes.len() == 64 {
        if let Ok(sig) = Signature::from_slice(sig_bytes) {
            return Ok(sig);
        }
    }
    Err(ApiError::Validation("Invalid signature format".to_string()))
}
```

### 3. Captures Route Handler - Upload Endpoint to Extend

**File**: `backend/src/routes/captures.rs`

**Purpose**: Upload endpoint handler that needs to be extended with assertion verification.

**Current Upload Flow** (to be extended):

```rust
async fn upload_capture(
    State(pool): State<PgPool>,
    Extension(request_id): Extension<Uuid>,
    Extension(device_ctx): Extension<DeviceContext>,
    multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<CaptureUploadResponse>>), ApiErrorWithRequestId> {
    // 1. Parse multipart (photo, depth_map, metadata)
    let parsed = parse_multipart(multipart).await?;

    // 2. Upload to S3
    let (photo_s3_key, depth_map_s3_key) = storage.upload_capture_files(...).await?;

    // 3. Create database record (status: pending)
    let capture_id = insert_capture(&pool, params).await?;

    // TODO: Add assertion verification step here (Story 4-4)
    // - Call verify_capture_assertion(device, &parsed.metadata.assertion, photo_hash, captured_at)
    // - Build HardwareAttestation result
    // - Update capture.evidence with hardware_attestation

    // 4. Return response
    Ok((StatusCode::ACCEPTED, Json(response)))
}
```

**Metadata Contains Assertion**:

```rust
pub struct CaptureMetadataPayload {
    pub captured_at: String,
    pub device_model: String,
    pub photo_hash: String,  // Base64 SHA-256
    pub depth_map_dimensions: DepthMapDimensions,
    pub assertion: Option<String>,  // Base64 CBOR assertion - VERIFY THIS
    pub location: Option<CaptureLocation>,
}
```

### 4. Device Model - Public Key and Counter Storage

**File**: `backend/src/models/device.rs`

**Purpose**: Device entity with public key and assertion counter for verification.

```rust
pub struct Device {
    pub id: Uuid,
    pub attestation_level: String,  // "secure_enclave" or "unverified"
    pub attestation_key_id: String,
    pub attestation_chain: Option<Vec<u8>>,
    pub platform: String,
    pub model: String,
    pub has_lidar: bool,
    pub first_seen_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
    pub assertion_counter: i64,     // CRITICAL: Last verified counter
    pub public_key: Option<Vec<u8>>, // 65-byte uncompressed EC point (0x04 || x || y)
}
```

### 5. Capture Types - Request/Response

**File**: `backend/src/types/capture.rs`

**Purpose**: Type definitions for capture upload. CaptureMetadataPayload includes the assertion field.

```rust
pub struct CaptureMetadataPayload {
    pub captured_at: String,
    pub device_model: String,
    pub photo_hash: String,
    pub depth_map_dimensions: DepthMapDimensions,
    pub assertion: Option<String>,  // Per-capture assertion (base64 CBOR)
    pub location: Option<CaptureLocation>,
}
```

### 6. Capture Model - Evidence Storage

**File**: `backend/src/models/capture.rs`

```rust
pub struct Capture {
    pub id: Uuid,
    pub device_id: Uuid,
    pub target_media_hash: Vec<u8>,
    pub photo_s3_key: String,
    pub depth_map_s3_key: String,
    pub evidence: serde_json::Value,  // JSONB - store HardwareAttestation here
    pub confidence_level: String,
    pub status: String,
    // ...
}
```

### 7. Error Types

**File**: `backend/src/error.rs`

**Relevant Error Types**:

```rust
pub enum ApiError {
    Validation(String),
    SignatureInvalid,
    ReplayDetected,
    // ...
}
```

---

## Development Constraints

### Architecture Constraints

1. **Non-Blocking Verification**: Assertion verification failures MUST NOT reject the upload. Log and continue with `status: fail`.

2. **Counter Atomicity**: Counter update must be atomic with verification to prevent race conditions.

3. **JSONB Evidence Storage**: HardwareAttestation stored in `captures.evidence` as JSONB per ADR-006.

4. **Performance Budget**: Assertion verification must complete in < 500ms (per tech spec NFR).

### Key Technical Decisions

1. **Client Data Hash for Captures** (different from request auth):
   ```rust
   // Request auth uses: sha256(timestamp + "|" + sha256_hex(body))
   // Capture assertion uses: sha256(photo_hash + "|" + captured_at)
   fn compute_capture_client_data_hash(photo_hash: &str, captured_at: &str) -> [u8; 32] {
       let binding = format!("{photo_hash}|{captured_at}");
       sha2::Sha256::digest(binding.as_bytes()).into()
   }
   ```

2. **RP ID Hash Verification**: Must match SHA256 of `{APPLE_TEAM_ID}.{APPLE_BUNDLE_ID}`

3. **Counter Handling**:
   - Counter must be STRICTLY GREATER than stored `device.assertion_counter`
   - Update counter in database on successful verification only
   - Counter validation failure = `counter_valid: false`, `status: fail`

### Error Handling Requirements

| Condition | Action | Evidence Status |
|-----------|--------|-----------------|
| Assertion null/empty | Continue processing | `status: unavailable` |
| Invalid base64 | Log error, continue | `status: fail` |
| Invalid CBOR | Log error, continue | `status: fail` |
| Signature mismatch | Log warning, continue | `status: fail`, `assertion_verified: false` |
| Counter not increasing | Log warning, continue | `status: fail`, `counter_valid: false` |
| No public key on device | Log error, continue | `status: fail` |

---

## Dependencies

### Rust Crates (Already in Cargo.toml)

| Crate | Version | Purpose |
|-------|---------|---------|
| `p256` | 0.13 | EC P-256 signature verification (with `ecdsa` feature) |
| `sha2` | 0.10 | SHA-256 hashing |
| `ciborium` | 0.2 | CBOR parsing |
| `base64` | 0.22 | Base64 decoding |
| `hex` | 0.4 | Hex encoding for logging |

### Internal Dependencies

| Module | Purpose |
|--------|---------|
| `services/attestation.rs` | CBOR parsing functions (parse_authenticator_data, CBOR helpers) |
| `middleware/device_auth.rs` | Signature verification pattern (verify_device_assertion reference) |
| `models/device.rs` | Device with public_key and assertion_counter |
| `types/capture.rs` | CaptureMetadataPayload with assertion field |
| `routes/captures.rs` | Upload handler to extend |

---

## Testing Context

### Unit Test Requirements

1. **Assertion Decoding Tests**:
   - Valid CBOR assertion decoding
   - Invalid base64 handling
   - Invalid CBOR handling
   - Missing authenticatorData/signature fields

2. **Signature Verification Tests**:
   - Valid signature with known test key
   - Invalid signature rejection
   - Both DER and raw r||s signature formats

3. **Counter Validation Tests**:
   - Counter increasing (valid)
   - Counter equal (invalid - replay)
   - Counter decreasing (invalid - replay)

4. **Confidence Calculation Tests**:
   - hw pass + depth pass = HIGH
   - hw pass + depth fail = MEDIUM
   - hw fail + depth pass = MEDIUM
   - hw fail + depth fail = SUSPICIOUS
   - hw unavailable + depth pass = MEDIUM
   - hw unavailable + depth fail = LOW

### Integration Test Requirements

1. **Full Upload Flow with Valid Assertion**:
   - Upload with valid assertion -> `status: pass`
   - Counter updated in database
   - Evidence package contains `hardware_attestation`

2. **Upload Flow with Invalid Assertion**:
   - Upload continues (not rejected)
   - `hardware_attestation.status: fail`
   - Confidence set appropriately

3. **Upload Flow with Missing Assertion**:
   - Upload continues
   - `hardware_attestation.status: unavailable`

### Test Data Patterns

```rust
// Mock device with known public key
let test_device = Device {
    public_key: Some(vec![0x04, /* 64 bytes of known test key */]),
    assertion_counter: 5,  // Test counter > 5
    attestation_level: "secure_enclave".to_string(),
    // ...
};

// Sample assertion structure
let sample_assertion_cbor = json!({
    "authenticatorData": base64_bytes,  // 37+ bytes
    "signature": base64_signature,       // DER or raw r||s
});
```

---

## Implementation Notes

### Suggested Module Structure

```
backend/src/services/
  attestation.rs          # Existing - device attestation
  capture_attestation.rs  # NEW - capture assertion verification
```

### New Module: capture_attestation.rs

```rust
//! Capture assertion verification service (Story 4-4)
//!
//! Verifies per-capture assertions for upload requests.
//! Different from device_auth (request-level) in clientDataHash computation.

pub struct CaptureAssertionResult {
    pub status: CheckStatus,
    pub level: AttestationLevel,
    pub device_model: String,
    pub assertion_verified: bool,
    pub counter_valid: bool,
    pub new_counter: Option<u32>,
}

pub async fn verify_capture_assertion(
    device: &Device,
    assertion_b64: Option<&str>,
    photo_hash: &str,
    captured_at: &str,
    request_id: Uuid,
) -> CaptureAssertionResult {
    // Implementation per AC-1 through AC-6
}
```

### Integration Point in captures.rs

```rust
// After S3 upload, before database insert
let hw_attestation = verify_capture_assertion(
    &device,
    parsed.metadata.assertion.as_deref(),
    &parsed.metadata.photo_hash,
    &parsed.metadata.captured_at,
    request_id,
).await;

// Update counter if verification succeeded
if let Some(new_counter) = hw_attestation.new_counter {
    update_device_counter(&pool, device.id, new_counter as i64).await?;
}

// Include in evidence package
let evidence = json!({
    "hardware_attestation": hw_attestation,
    // depth_analysis, metadata will be added by later stories
});
```

---

## Warnings and Gaps

### Identified Gaps

1. **Evidence Model Not Created**: The `models/evidence.rs` file referenced in tech spec does not exist yet. Need to create `HardwareAttestation`, `CheckStatus`, `AttestationLevel` structs.

2. **Shared Types Incomplete**: `packages/shared/src/types/evidence.ts` `HardwareAttestation` is missing `assertion_verified` and `counter_valid` fields that are in the tech spec.

3. **Evidence Pipeline Not Implemented**: The evidence pipeline module (`services/evidence/pipeline.rs`) mentioned in tech spec doesn't exist. Story 4-4 implements the hardware attestation portion.

### Assumptions

1. Device lookup is already performed by DeviceAuthMiddleware and available via `DeviceContext`.
2. The `assertion` field in metadata is base64-encoded CBOR (not raw bytes).
3. Client data hash for capture assertions uses `photo_hash|captured_at` format (not request body hash).

---

## Quick Reference

### Files to Create

| File | Purpose |
|------|---------|
| `backend/src/services/capture_attestation.rs` | Capture assertion verification service |
| `backend/src/models/evidence.rs` | Evidence types (HardwareAttestation, CheckStatus, etc.) |

### Files to Modify

| File | Changes |
|------|---------|
| `backend/src/routes/captures.rs` | Add assertion verification step in upload handler |
| `backend/src/services/mod.rs` | Export capture_attestation module |
| `backend/src/models/mod.rs` | Export evidence module |

### Key Functions to Implement

1. `decode_capture_assertion(assertion_b64: &str)` - Base64 + CBOR decoding
2. `compute_capture_client_data_hash(photo_hash, captured_at)` - Hash binding
3. `verify_capture_assertion(device, assertion, photo_hash, captured_at)` - Main verification
4. `CaptureAssertionResult` struct with all evidence fields

---

_Context assembled by BMAD Story Context Workflow_
_Date: 2025-11-23_
