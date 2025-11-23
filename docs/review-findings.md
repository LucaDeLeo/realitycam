# RealityCam Codebase Review (Nov 23, 2025)

## Security Status: All Vulnerabilities Addressed

All critical and high security vulnerabilities have been addressed through code implementation and configuration options.

---

## Implemented Security Controls

### 1. Server-side Photo Hash Verification
- Upload path computes SHA-256 of uploaded bytes
- Compares to client-provided hash, rejects mismatches
- Prevents hash spoofing attacks
- **Evidence:** `backend/src/routes/captures.rs:317-355`

### 2. DCAppAttest Certificate Chain Validation
- Apple App Attestation Root CA embedded (`certs/apple_app_attest_root_ca.der`)
- Cryptographic signature verification via x509-parser
- Validates: validity periods, issuer hierarchy, root CA signature
- **Evidence:** `backend/src/services/attestation.rs:28,312-430,722`

### 3. Device Signature Verification
- Per-request signature verification for SecureEnclave devices
- Counter-based replay protection
- **Evidence:** `backend/src/middleware/device_auth.rs:273-324`

### 4. Confidence Capping for Unverified Devices
- Devices without verified signatures capped at Medium confidence
- Cannot achieve High confidence without cryptographic proof
- **Evidence:** `backend/src/routes/captures.rs:597-613`

### 5. Rate Limiting
- Per-IP token bucket rate limiting via tower_governor
- Configurable rate and burst size
- **Evidence:** `backend/src/routes/mod.rs:60-90`

### 6. Capture Retrieval Access Control
- `GET /api/v1/captures/{id}` enforces device ownership
- Only creating device can retrieve its captures
- **Evidence:** `backend/src/routes/captures.rs:658-757`

---

## Production Configuration

To enable **full security enforcement**, set these environment variables:

```bash
# REQUIRED for production - reject invalid certificate chains
STRICT_ATTESTATION=true

# REQUIRED for production - reject devices with failed signature verification
REQUIRE_VERIFIED_DEVICES=true
```

### Security Mode Comparison

| Mode | `STRICT_ATTESTATION` | `REQUIRE_VERIFIED_DEVICES` | Behavior |
|------|---------------------|---------------------------|----------|
| **MVP (default)** | `false` | `false` | Invalid chains logged, unverified allowed (capped at Medium) |
| **Production** | `true` | `true` | Invalid chains rejected, unverified rejected |
| **Gradual rollout** | `true` | `false` | Invalid chains rejected, unverified capped at Medium |

---

## Full Configuration Reference

| Feature | Env Var | Default | Production |
|---------|---------|---------|------------|
| Strict attestation | `STRICT_ATTESTATION` | `false` | `true` |
| Require verified devices | `REQUIRE_VERIFIED_DEVICES` | `false` | `true` |
| Rate limit (per second) | `RATE_LIMIT_PER_SECOND` | `10` | `10` |
| Rate limit (burst) | `RATE_LIMIT_BURST` | `30` | `30` |
| Verification URL | `VERIFICATION_BASE_URL` | `https://realitycam.app/verify` | Set to production URL |

---

## Outstanding (Low Priority)

### Public Verification Endpoint
- Capture retrieval is device-authenticated only
- Web `/verify/[id]` page remains placeholder
- **Recommendation:** Add public endpoint returning sanitized evidence subset
- **Evidence:** `apps/web/src/app/verify/[id]/page.tsx`

---

## Security Flow Summary

```
Device Registration:
  └─> parse attestation object
  └─> verify certificate chain (STRICT_ATTESTATION controls enforcement)
  └─> verify challenge binding
  └─> verify app identity
  └─> extract public key
  └─> store device with attestation_level

Capture Upload:
  └─> verify device signature (REQUIRE_VERIFIED_DEVICES controls enforcement)
  └─> set is_verified = true/false based on verification result
  └─> compute SHA256 of uploaded photo
  └─> compare to client hash (reject if mismatch)
  └─> process evidence pipeline
  └─> cap confidence to Medium if !is_verified
  └─> store capture with evidence
```
