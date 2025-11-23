# RealityCam Codebase Review (Nov 23, 2025)

## Critical
- **Capture authenticity not tied to uploaded bytes** — Server trusts `metadata.photo_hash` from the client, never hashes `parsed.photo_bytes`, and stores that unverified hash as `target_media_hash` and for assertion binding. An attacker can upload arbitrary content while claiming a different hash and still get a “verified” capture.  
  Evidence: `backend/src/routes/captures.rs:336-405,570-610`
- **DCAppAttest chain validation effectively disabled** — The Apple root CA is not embedded (`APPLE_CA_EMBEDDED = false`) and `verify_certificate_chain` only checks issuer/expiry, then returns `Ok(())`, so any self-signed chain passes. Device registration can be forged.  
  Evidence: `backend/src/services/attestation.rs:24-41,320-383`

## High
- **Device auth lets signature failures through for uploads** — Captures router sets `require_verified = false`, and middleware logs signature failures but still proceeds with `is_verified = false`. Unsigned or tampered requests can upload as long as they know a device UUID.  
  Evidence: `backend/src/routes/mod.rs:46-58`; `backend/src/middleware/device_auth.rs:272-324`

## Medium
- **Capture retrieval unimplemented while UI advertises it** — `GET /api/v1/captures/{id}` returns 501, yet upload responses include a verification URL and the web UI has a verify page that never loads real data.  
  Evidence: `backend/src/routes/captures.rs:653-667`; `apps/web/src/app/verify/[id]/page.tsx:6-118`
- **Verification base URL and rate limiting hard-coded, plus per-request S3 clients and redundant depth download** — Upload handler hardcodes `VERIFICATION_BASE_URL`, disables rate limiting, rebuilds config/S3 client each request, and depth analysis re-downloads the just-uploaded depth map instead of reusing in-memory bytes. This adds latency, resource cost, and DoS surface.  
  Evidence: `backend/src/routes/captures.rs:46-55,353-360`; `backend/src/services/depth_analysis.rs:499-520`

