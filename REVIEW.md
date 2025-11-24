# RealityCam Repo Review (2025-11-24)

Key inconsistencies and blockers identified across the codebase, with pointers to evidence and suggested next steps.

## 1) Hash contract mismatch (uploads vs. verification)
- **What**: Capture upload stores `target_media_hash` as SHA-256 of the **base64 string** of the photo, while `/verify-file` hashes the **raw bytes**. Verified photos will never match database records.
- **Evidence**:
  - Server uses base64-string hashing on upload: `backend/src/routes/captures.rs:318-353`.
  - Verifier hashes raw bytes: `backend/src/routes/verify.rs:167-205`.
- **Fix**: Standardize on hashing raw bytes end-to-end. Until mobile is fixed, either (a) change upload to hash raw bytes and migrate existing records, or (b) temporarily make `/verify-file` hash base64 strings for compatibility.

## 2) Device auth flow incompatible with mobile uploader
- **What**: API middleware expects a registered device and a CBOR assertion signature. Mobile uploader hardcodes a fake device ID and sends a SHA-256 string as “signature”, with no registration flow, so uploads will be rejected (DeviceNotFound/Invalid CBOR).
- **Evidence**:
  - Middleware requirements and signature verification: `backend/src/middleware/device_auth.rs:205-341,475-569`.
  - Mobile hardcoded headers and non-CBOR “signature”: `apps/mobile/services/uploadService.ts:117-151`.
  - No device registration call in mobile codebase.
- **Fix**: Implement real device registration + DCAppAttest assertion in mobile, passing backend-assigned device ID and CBOR assertion; or temporarily disable/relax `DeviceAuthLayer` for uploads during bring-up.

## 3) Hardcoded verification and media URLs
- **What**: Public verification endpoints embed fixed URLs that ignore environment/config, breaking non-matching networks.
- **Evidence**:
  - Hardcoded verification base: `backend/src/routes/verify.rs:34-39,196-204`.
  - Hardcoded LocalStack photo URL with static LAN IP: `backend/src/routes/verify.rs:362-379`.
- **Fix**: Drive verification links from `Config.verification_base_url`; build photo/depth URLs via configured S3 endpoint/bucket or presigned URLs; make LocalStack host overridable.

## 4) Evidence type drift between backend and shared package
- **What**: Backend emits richer metadata fields (`timestamp_delta_seconds`, `model_name`, `resolution_valid`, `location_opted_out`, etc.) that aren’t in shared `Evidence` types. Consumers must polyfill or ignore fields.
- **Evidence**:
  - Backend evidence shape: `backend/src/models/evidence.rs:96-161`.
  - Shared types missing fields: `packages/shared/src/types/evidence.ts:1-25`.
  - Web code manually accesses backend-only fields: `apps/web/src/app/verify/[id]/page.tsx:20-54`.
- **Fix**: Align shared types to backend schema and update web/mobile imports; bump package version to propagate.

## 5) Branding/domain inconsistency
- **What**: Web UI is branded “rial.” while README, backend defaults, and envs use “RealityCam”.
- **Evidence**:
  - Web branding: `apps/web/src/app/layout.tsx:15-18`, `apps/web/src/app/page.tsx:11-40`, `apps/web/src/app/verify/[id]/page.tsx:63-72`.
  - Project/docs/backend use “RealityCam”: `README.md`, `backend/.env.example`.
- **Fix**: Choose canonical product name and update UI copy, metadata, and environment defaults accordingly.

## 6) Next.js route params typing issue
- **What**: `params` is typed as a `Promise` and awaited in the verify page, diverging from Next App Router conventions (should be a plain object). Works at runtime but harms type inference.
- **Evidence**: `apps/web/src/app/verify/[id]/page.tsx:8-14`.
- **Fix**: Change signature to `{ params: { id: string } }` and remove `await`.

---

If you want, I can prioritize a quick compatibility patch (e.g., switch `/verify-file` to match the current upload hashing and relax device auth for demos) or start implementing the proper device registration + attestation flow. 
