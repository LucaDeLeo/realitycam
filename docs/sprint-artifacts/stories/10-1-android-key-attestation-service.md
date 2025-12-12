# Story 10-1: Android Key Attestation Service

Status: ready-for-dev

## Story

As a **backend service**,
I want **to verify Android Key Attestation certificate chains and extract attestation security levels**,
So that **Android devices can register with hardware-backed trust verification, enabling cross-platform capture support**.

## Acceptance Criteria

### AC 1: Android Attestation Certificate Chain Parsing
**Given** an Android device sends a Key Attestation certificate chain
**When** the backend parses the attestation
**Then**:
1. Decodes base64-encoded certificate chain (array of DER certificates)
2. Parses each certificate using x509-parser crate
3. Extracts leaf certificate (device key), intermediate(s), and root certificate
4. Validates minimum chain length of 2 certificates (leaf + root)
5. Returns structured AndroidAttestationObject with parsed components

### AC 2: Certificate Chain Verification to Google Root
**Given** a parsed Android attestation certificate chain
**When** certificate chain verification runs
**Then**:
1. Verifies chain hierarchy (leaf issued by intermediate, intermediate issued by root)
2. Validates certificate validity periods (not expired, not yet valid)
3. Verifies cryptographic signatures up the chain
4. Compares root certificate against embedded Google Hardware Attestation Root CA(s)
5. Supports both RSA and EC key types in the chain
6. Returns ChainVerificationResult with status and any error details
7. Reuses existing `strict_attestation` config flag from Config struct for strict/non-strict modes

**Google Root Certificates to embed:**
- Google Hardware Attestation Root 1 (RSA)
- Google Hardware Attestation Root 2 (EC)

### AC 3: Key Attestation Extension Parsing (OID 1.3.6.1.4.1.11129.2.1.17)
**Given** a leaf certificate with Android Key Attestation extension
**When** parsing the attestation extension
**Then** extracts KeyDescription ASN.1 structure (validates extension exists in x5c[0] (leaf) only):

```rust
#[derive(Debug, Clone)]
pub struct KeyDescription {
    pub attestation_version: i32,
    pub attestation_security_level: SecurityLevel,
    pub keymaster_version: i32,
    pub keymaster_security_level: SecurityLevel,
    pub attestation_challenge: Vec<u8>,
    pub unique_id: Vec<u8>,
    pub software_enforced: AuthorizationList,
    pub tee_enforced: AuthorizationList,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SecurityLevel {
    Software = 0,
    TrustedEnvironment = 1,  // TEE
    StrongBox = 2,           // Hardware Security Module
}
```

### AC 4: Attestation Security Level Extraction (FR71)
**Given** a parsed KeyDescription from the attestation extension
**When** extracting the security level
**Then**:
1. Reads `attestationSecurityLevel` field (primary indicator)
2. Maps to SecurityLevel enum: Software (0), TrustedEnvironment (1), StrongBox (2)
3. Also extracts `keymasterSecurityLevel` for additional context
4. Returns both levels in AndroidAttestationResult

**Security Level Mapping:**
| Value | Level | Trust | Action |
|-------|-------|-------|--------|
| 0 | Software | REJECTED | Reject registration (FR72) |
| 1 | TrustedEnvironment (TEE) | MEDIUM | Accept with TEE level |
| 2 | StrongBox | HIGH | Accept with StrongBox level |

### AC 5: Software-Only Attestation Rejection (FR72)
**Given** an Android attestation with `attestationSecurityLevel = 0` (Software)
**When** verification completes
**Then**:
1. Returns AndroidAttestationError::SoftwareOnlyAttestation
2. Logs rejection with device info for monitoring
3. Does NOT create device record
4. Returns 401 Unauthorized with error code `ANDROID_SOFTWARE_ONLY_ATTESTATION`
5. Error message: "Software-only attestation rejected. Device requires TEE or StrongBox."

### AC 6: Challenge Freshness Validation (FR73)
**Given** an Android attestation with challenge bytes
**When** validating challenge freshness
**Then**:
1. Extracts `attestationChallenge` from KeyDescription
2. Compares against server-issued challenge (from challenge store)
3. Validates challenge was issued within 5-minute window
4. Validates challenge is single-use (marks as consumed)
5. Returns AndroidAttestationError::ChallengeMismatch or ::ChallengeExpired on failure

**Challenge Flow:** Android client requests challenge via existing `/api/v1/devices/challenge` endpoint, includes it in `setAttestationChallenge()`, backend extracts from attestation and validates against ChallengeStore.

### AC 7: AuthorizationList Parsing
**Given** the teeEnforced and softwareEnforced sections of KeyDescription
**When** parsing authorization lists
**Then** extracts relevant tagged fields:

```rust
#[derive(Debug, Clone, Default)]
pub struct AuthorizationList {
    // Key properties
    pub purpose: Option<Vec<i32>>,          // Tag 1
    pub algorithm: Option<i32>,              // Tag 2
    pub key_size: Option<i32>,               // Tag 3
    pub origin: Option<i32>,                 // Tag 702

    // Device identity (for logging/debugging)
    pub attestation_id_brand: Option<Vec<u8>>,        // Tag 710
    pub attestation_id_device: Option<Vec<u8>>,       // Tag 711
    pub attestation_id_product: Option<Vec<u8>>,      // Tag 712
    pub attestation_id_serial: Option<Vec<u8>>,       // Tag 713
    pub attestation_id_manufacturer: Option<Vec<u8>>, // Tag 716
    pub attestation_id_model: Option<Vec<u8>>,        // Tag 717

    // Security properties
    pub os_version: Option<i32>,             // Tag 705
    pub os_patch_level: Option<i32>,         // Tag 706
    pub vendor_patch_level: Option<i32>,     // Tag 718
    pub boot_patch_level: Option<i32>,       // Tag 719
    pub root_of_trust: Option<RootOfTrust>,  // Tag 704
}

#[derive(Debug, Clone)]
pub struct RootOfTrust {
    pub verified_boot_key: Vec<u8>,
    pub device_locked: bool,
    pub verified_boot_state: VerifiedBootState,
    pub verified_boot_hash: Option<Vec<u8>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerifiedBootState {
    Verified = 0,
    SelfSigned = 1,
    Unverified = 2,
    Failed = 3,
}
```

### AC 8: Public Key Extraction
**Given** a valid Android attestation certificate chain
**When** extracting the public key
**Then**:
1. Extracts public key from leaf certificate
2. Supports EC (P-256) and RSA key types
3. Returns key in standard format for storage
4. Key can be used for subsequent request signature verification

### AC 9: AndroidAttestationResult Structure
**Given** successful attestation verification
**When** returning the result
**Then** returns:

```rust
#[derive(Debug, Clone)]
pub struct AndroidAttestationResult {
    pub public_key: Vec<u8>,
    pub attestation_security_level: SecurityLevel,
    pub keymaster_security_level: SecurityLevel,
    pub attestation_version: i32,
    pub keymaster_version: i32,
    pub certificate_chain: Vec<Vec<u8>>,
    pub device_info: AndroidDeviceInfo,
    pub root_of_trust: Option<RootOfTrust>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AndroidDeviceInfo {
    pub brand: Option<String>,
    pub device: Option<String>,
    pub product: Option<String>,
    pub manufacturer: Option<String>,
    pub model: Option<String>,
    pub os_version: Option<i32>,
    pub os_patch_level: Option<i32>,
}
```

### AC 10: Error Types and Logging
**Given** any attestation verification failure
**When** returning error
**Then** uses typed errors with detailed logging:

```rust
#[derive(Debug, Clone)]
pub enum AndroidAttestationError {
    // Certificate parsing
    InvalidBase64,
    InvalidCertificate(String),
    IncompleteCertChain,

    // Chain verification
    CertificateExpired,
    ChainVerificationFailed(String),
    RootCaMismatch,

    // Attestation extension
    MissingAttestationExtension,
    InvalidAttestationExtension(String),

    // Security level
    SoftwareOnlyAttestation,

    // Challenge
    ChallengeMismatch,
    ChallengeExpired,
    ChallengeNotFound,

    // Key extraction
    InvalidPublicKey(String),
    UnsupportedKeyType(String),
}
```

## Tasks / Subtasks

- [ ] Task 1: Create android_attestation module structure (AC: #1, #10)
  - [ ] Create `backend/src/services/android_attestation.rs`
  - [ ] Define AndroidAttestationError enum with Display impl
  - [ ] Define public types (SecurityLevel, VerifiedBootState)
  - [ ] Export from services/mod.rs

- [ ] Task 2: Embed Google root certificates (AC: #2)
  - [ ] Download Google Hardware Attestation Root 1 (RSA) - DER format from https://developer.android.com/privacy-and-security/security-key-attestation#root_certificate
  - [ ] Download Google Hardware Attestation Root 2 (EC) - DER format from https://developer.android.com/privacy-and-security/security-key-attestation#root_certificate
  - [ ] Create `backend/certs/google_hardware_attestation_root_1.der`
  - [ ] Create `backend/certs/google_hardware_attestation_root_2.der`
  - [ ] Use include_bytes! macro for embedding

- [ ] Task 3: Implement certificate chain parsing (AC: #1)
  - [ ] Parse base64-encoded certificate array
  - [ ] Parse each certificate with x509-parser
  - [ ] Validate minimum chain length
  - [ ] Return AndroidAttestationObject struct

- [ ] Task 4: Implement certificate chain verification (AC: #2)
  - [ ] Verify certificate hierarchy (issuer/subject matching)
  - [ ] Verify validity periods with chrono
  - [ ] Verify cryptographic signatures (RSA and EC)
  - [ ] Compare root against embedded Google roots
  - [ ] Support strict and non-strict modes (like iOS attestation)

- [ ] Task 5: Implement Key Attestation extension parsing (AC: #3)
  - [ ] Define ASN.1 OID constant: 1.3.6.1.4.1.11129.2.1.17
  - [ ] Find extension in leaf certificate (x5c[0] only)
  - [ ] Parse KeyDescription SEQUENCE using der-parser and asn1-rs
  - [ ] Extract attestation_version, security levels, challenge
  - [ ] Handle optional fields gracefully

- [ ] Task 6: Implement AuthorizationList parsing (AC: #7)
  - [ ] Parse tagged ASN.1 fields from teeEnforced and softwareEnforced
  - [ ] Extract device identity fields (brand, model, etc.)
  - [ ] Parse RootOfTrust structure (tag 704)
  - [ ] Extract security patch levels

- [ ] Task 7: Implement security level extraction and validation (AC: #4, #5)
  - [ ] Extract attestationSecurityLevel from KeyDescription
  - [ ] Map to SecurityLevel enum
  - [ ] Implement software-only rejection logic
  - [ ] Return appropriate error for software attestation

- [ ] Task 8: Implement challenge validation (AC: #6)
  - [ ] Extract attestationChallenge from KeyDescription
  - [ ] Integrate with existing ChallengeStore
  - [ ] Validate challenge freshness (5-minute window)
  - [ ] Mark challenge as consumed (single-use)

- [ ] Task 9: Implement public key extraction (AC: #8)
  - [ ] Extract public key from leaf certificate
  - [ ] Handle EC P-256 keys (primary)
  - [ ] Handle RSA keys (fallback)
  - [ ] Return in standard byte format

- [ ] Task 10: Implement main verification pipeline (AC: #9)
  - [ ] Create verify_android_attestation() async function
  - [ ] Orchestrate all verification steps
  - [ ] Build AndroidAttestationResult on success
  - [ ] Log each verification step with request_id

- [ ] Task 11: Unit tests
  - [ ] Test certificate parsing with test vectors
  - [ ] Test chain verification (valid and invalid chains)
  - [ ] Test attestation extension parsing
  - [ ] Test security level extraction
  - [ ] Test software-only rejection
  - [ ] Test challenge validation
  - [ ] Test error cases
  - [ ] Reference Google's sample attestation data from https://github.com/nickelote/android-key-attestation or use openssl to generate self-signed test chains with manually constructed KeyDescription extensions

- [ ] Task 12: Integration test preparation
  - [ ] Create test attestation certificate chain (mock)
  - [ ] Document how to generate test attestations
  - [ ] Prepare for Story 10-2 (device registration endpoint)

## Dev Notes

### Technical Approach

**Android Key Attestation Overview:**
Android Key Attestation proves a key was generated in secure hardware (TEE/StrongBox). When an Android app generates a key pair with `setAttestationChallenge()`, Android creates a certificate chain where:
1. Leaf certificate contains the device public key
2. Leaf contains extension OID 1.3.6.1.4.1.11129.2.1.17 with KeyDescription
3. Chain roots to Google's Hardware Attestation Root CA

**ASN.1 Structure (KeyDescription):**
```asn1
KeyDescription ::= SEQUENCE {
    attestationVersion         INTEGER,
    attestationSecurityLevel   SecurityLevel,
    keymasterVersion          INTEGER,
    keymasterSecurityLevel    SecurityLevel,
    attestationChallenge      OCTET STRING,
    uniqueId                  OCTET STRING,
    softwareEnforced          AuthorizationList,
    teeEnforced               AuthorizationList,
}

SecurityLevel ::= ENUMERATED {
    Software  (0),
    TrustedEnvironment  (1),
    StrongBox  (2),
}

AuthorizationList ::= SEQUENCE {
    purpose     [1] EXPLICIT SET OF INTEGER OPTIONAL,
    algorithm   [2] EXPLICIT INTEGER OPTIONAL,
    keySize     [3] EXPLICIT INTEGER OPTIONAL,
    -- ... many more tagged fields ...
    rootOfTrust [704] EXPLICIT RootOfTrust OPTIONAL,
    osVersion   [705] EXPLICIT INTEGER OPTIONAL,
    osPatchLevel [706] EXPLICIT INTEGER OPTIONAL,
    -- ... device identity fields 710-717 ...
}
```

**Google Root Certificates:**
Download from: https://developer.android.com/privacy-and-security/security-key-attestation#root_certificate

Two roots exist:
1. RSA root (older devices)
2. EC root (newer devices, including Pixel)

**Comparison with iOS DCAppAttest:**
| Aspect | iOS DCAppAttest | Android Key Attestation |
|--------|-----------------|------------------------|
| Format | CBOR | X.509 + ASN.1 extension |
| Root CA | Apple App Attest Root CA | Google Hardware Attestation Root |
| Security Levels | secure_enclave only | Software/TEE/StrongBox |
| Challenge | In CBOR nonce extension | In attestationChallenge field |
| Parsing | ciborium + coset | x509-parser + der-parser |

### Dependencies

**Existing (reuse):**
- `x509-parser` - Already used for iOS attestation
- `der-parser` - Already available via x509-parser
- `sha2` - For challenge hashing
- `base64` - For decoding certificate chain

**New dependency (required):**
- `asn1-rs = "0.6"` - For complex ASN.1 parsing (AuthorizationList has many tagged fields that require explicit handling)

### Project Structure Notes

**New Files:**
- `backend/src/services/android_attestation.rs` - Main attestation service
- `backend/certs/google_hardware_attestation_root_1.der` - RSA root
- `backend/certs/google_hardware_attestation_root_2.der` - EC root

**Modified Files:**
- `backend/src/services/mod.rs` - Export android_attestation module
- `backend/src/config.rs` - Add android attestation config (strict mode flag)

**Pattern to follow:**
- Reference `backend/src/services/attestation.rs` (iOS) for structure
- Similar verification pipeline with logging
- Reuse ChallengeStore from `backend/src/services/challenge_store.rs`

### Security Considerations

**Software-Only Rejection is Critical:**
Software attestation can be trivially spoofed on rooted devices. Per FR72, we MUST reject:
- Any attestation with `attestationSecurityLevel = 0`
- This is a hard security boundary, not a warning

**Challenge Freshness:**
- 5-minute window prevents replay attacks
- Single-use prevents challenge reuse
- Reuse existing ChallengeStore infrastructure

**RootOfTrust Verification:**
- `verifiedBootState` indicates device boot integrity
- `deviceLocked` indicates bootloader lock status
- Consider logging for monitoring but don't reject (user may have unlocked bootloader)

**Trust Hierarchy (per PRD):**
```
Android attestation is WEAKER than iOS DCAppAttest:
- Play Integrity bypass modules exist
- Chimera-style attacks possible
- TEE = MEDIUM trust, StrongBox = HIGH trust
- Still stronger than no attestation
```

### Testing Strategy

**Unit Test Vectors:**
Create test certificates that simulate:
1. Valid StrongBox attestation
2. Valid TEE attestation
3. Software-only attestation (should reject)
4. Expired certificate chain
5. Invalid root (not Google)
6. Missing attestation extension
7. Challenge mismatch

**Mock Certificate Generation:**
Reference the Go code from Exa research for generating test attestation certificates:
- Use openssl or ring to create test chains
- Manually construct KeyDescription extension
- Sign with test root (not Google root - test mode only)

### References

- [Android Key Attestation Docs](https://developer.android.com/privacy-and-security/security-key-attestation)
- [Google Root Certificates](https://developer.android.com/privacy-and-security/security-key-attestation#root_certificate)
- [KeyMint Rust Reference](https://fuchsia.googlesource.com/third_party/android.googlesource.com/platform/system/keymint) - ASN.1 schema reference
- [Source: docs/prd.md#Phase-2-Backend-Platform-Expansion] - FR70-FR75 requirements
- [Source: docs/epics.md#Epic-10-Cross-Platform-Foundation] - Epic context
- [Source: backend/src/services/attestation.rs] - iOS attestation pattern
- [Source: backend/src/services/challenge_store.rs] - Challenge management

### Related Stories

- Story 10-2: Android Device Registration Endpoint - BACKLOG (uses this service)
- Story 10-3: Platform-Aware Capture Endpoint - BACKLOG (unified iOS/Android)
- Story 10-4: Evidence Model Expansion - BACKLOG (unified evidence schema)
- Story 10-5: Database Migration for Android - BACKLOG (platform field)
- Story 10-6: Backward Compatibility - BACKLOG (existing iOS captures)

---

_Story created: 2025-12-11_
_Epic: 10 - Cross-Platform Foundation_
_FR Coverage: FR70 (Android Key Attestation verification), FR71 (Security level extraction), FR72 (Software-only rejection), FR73 (Challenge freshness)_
_Depends on: Epic 2 stories (device registration infrastructure), Challenge store_
_Enables: Story 10-2 (Android device registration endpoint), Epic 12 (Android app)_

## Dev Agent Record

### Context Reference

Created from:
- docs/epics.md - Epic 10 definition and FR70-FR75 mapping
- docs/prd.md - Android Platform Requirements section, FR70-FR75 detailed requirements
- docs/architecture.md - Existing attestation patterns and tech stack
- backend/src/services/attestation.rs - iOS attestation implementation pattern
- Exa research - Android Key Attestation ASN.1 structure and implementation patterns

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story not yet implemented

### File List

**To Create:**
- `/Users/luca/dev/realitycam/backend/src/services/android_attestation.rs`
- `/Users/luca/dev/realitycam/backend/certs/google_hardware_attestation_root_1.der`
- `/Users/luca/dev/realitycam/backend/certs/google_hardware_attestation_root_2.der`

**To Modify:**
- `/Users/luca/dev/realitycam/backend/src/services/mod.rs`
- `/Users/luca/dev/realitycam/backend/src/config.rs`
