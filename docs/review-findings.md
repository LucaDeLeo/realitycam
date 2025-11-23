# RealityCam Codebase Review (Nov 23, 2025)

## Fixed since last review
- **Server-side photo hash verification added** — Upload path now computes SHA-256 of the uploaded photo, compares to the client claim, and rejects mismatches before storage/evidence use. Evidence: `backend/src/routes/captures.rs:317-355`
- **Rate limiting & shared resources** — Capture routes now use `tower_governor` per-IP limits and reuse shared `Config`/`StorageService`; depth analysis operates on in-memory bytes instead of re-downloading from S3. Evidence: `backend/src/routes/mod.rs:65-90`; `backend/src/routes/captures.rs:360-375,490-505`; `backend/src/services/depth_analysis.rs:450-520`
- **Capture retrieval implemented with access control** — `GET /api/v1/captures/{id}` now returns evidence and enforces ownership by device_id. Evidence: `backend/src/routes/captures.rs:691-748`

## Outstanding Critical
- **DCAppAttest chain validation still not enforced** — Apple root CA remains unembedded (`APPLE_CA_EMBEDDED = false`); `verify_certificate_chain` only checks issuer/expiry and skips root signature verification, so forged chains can pass. Evidence: `backend/src/services/attestation.rs:24-41,320-383`

## Outstanding High
- **Device auth still permissive for uploads** — Router keeps `require_verified = false`; middleware logs signature failures but continues the request with `is_verified = false`, so uploads can proceed if a device UUID is known even when signatures fail. Evidence: `backend/src/routes/mod.rs:46-59`; `backend/src/middleware/device_auth.rs:272-314`

## Outstanding Medium
- **No public verification path** — New capture retrieval is device-authenticated only; the web `/verify/[id]` page remains static/placeholder, so external users still cannot view evidence via the verification URL returned on upload. Evidence: `backend/src/routes/captures.rs:691-748`; `apps/web/src/app/verify/[id]/page.tsx:6-118`
