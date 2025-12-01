# rial. - Epic Breakdown

**Author:** Luca
**Date:** 2025-11-22
**Project Level:** MVP
**Target Scale:** iPhone Pro Only

---

## Overview

This document provides the complete epic and story breakdown for rial., decomposing the requirements from the [PRD](./prd.md) into implementable stories.

**Living Document Notice:** This is the initial version. It will be updated after UX Design and Architecture workflows add interaction and technical details to stories.

## Epic Summary

| Epic | Title | User Value | FRs Covered |
|------|-------|------------|-------------|
| 1 | Foundation & Project Setup | Development infrastructure ready | Setup for all FRs |
| 2 | Device Registration & Attestation | Device can securely register with hardware attestation | FR1-FR5, FR41-FR43 |
| 3 | Photo Capture with LiDAR Depth | User can capture attested photos with depth data | FR6-FR13 |
| 4 | Upload & Evidence Processing | Captured photos are processed with full evidence pipeline | FR14-FR26, FR44-FR46 |
| 5 | C2PA & Verification Experience | Users can verify photos via shareable links | FR27-FR40 |
| 6 | Native Swift Implementation | Maximum security via native iOS with zero JS bridge | FR1-FR19, FR41-FR46 (native) |
| 7 | Video Capture with LiDAR Depth | Attested video with frame-by-frame depth verification | FR47-FR55 |
| 8 | Privacy-First Capture Mode | Zero-knowledge provenance with client-side analysis | FR56-FR62 |

---

## Functional Requirements Inventory

### Device & Attestation (FR1-FR5)
- **FR1:** App detects iPhone Pro device with LiDAR capability
- **FR2:** App generates cryptographic keys in Secure Enclave via @expo/app-integrity
- **FR3:** App requests DCAppAttest attestation from iOS (one-time device registration)
- **FR4:** Backend verifies DCAppAttest attestation object against Apple's service
- **FR5:** System assigns attestation level: secure_enclave or unverified

### Capture Flow (FR6-FR10)
- **FR6:** App displays camera view with LiDAR depth overlay
- **FR7:** App captures photo via back camera
- **FR8:** App simultaneously captures LiDAR depth map via ARKit
- **FR9:** App records GPS coordinates if permission granted
- **FR10:** App captures device attestation signature for the capture

### Local Processing (FR11-FR13)
- **FR11:** App computes SHA-256 hash of photo before upload
- **FR12:** App compresses depth map (gzip float32 array)
- **FR13:** App constructs structured capture request with photo + depth + metadata

### Upload & Sync (FR14-FR19)
- **FR14:** App uploads capture via multipart POST (photo + depth_map + metadata JSON)
- **FR15:** App uses TLS 1.3 for all API communication
- **FR16:** App implements retry with exponential backoff on upload failure
- **FR17:** App stores captures in encrypted local storage when offline (Secure Enclave key)
- **FR18:** App auto-uploads pending captures when connectivity returns
- **FR19:** App displays pending upload status to user

### Evidence Generation (FR20-FR26)
- **FR20:** Backend verifies DCAppAttest attestation and records level
- **FR21:** Backend performs LiDAR depth analysis (variance, layers, edge coherence)
- **FR22:** Backend determines "is_likely_real_scene" from depth analysis
- **FR23:** Backend validates EXIF timestamp against server receipt time
- **FR24:** Backend validates device model is iPhone Pro (has LiDAR)
- **FR25:** Backend generates evidence package with all check results
- **FR26:** Backend calculates confidence level (HIGH/MEDIUM/LOW/SUSPICIOUS)

### C2PA Integration (FR27-FR30)
- **FR27:** Backend creates C2PA manifest with evidence summary
- **FR28:** Backend signs C2PA manifest with Ed25519 key (HSM-backed in production)
- **FR29:** Backend embeds C2PA manifest in photo file
- **FR30:** System stores both original and C2PA-embedded versions

### Verification Interface (FR31-FR35)
- **FR31:** Users can view capture verification via shareable URL
- **FR32:** Verification page displays confidence summary (HIGH/MEDIUM/LOW/SUSPICIOUS)
- **FR33:** Verification page displays depth analysis visualization
- **FR34:** Users can expand detailed evidence panel with per-check status
- **FR35:** Each check displays pass/fail with relevant metrics

### File Verification (FR36-FR40)
- **FR36:** Users can upload file to verification endpoint
- **FR37:** System computes hash and searches for matching capture
- **FR38:** If match found: display linked capture evidence
- **FR39:** If no match but C2PA manifest present: display manifest info with note
- **FR40:** If no match and no manifest: display "No provenance record found"

### Device Management (FR41-FR43)
- **FR41:** System generates device-level pseudonymous ID (Secure Enclave backed)
- **FR42:** Users can capture and verify without account (anonymous by default)
- **FR43:** Device registration stores attestation key ID and capability flags

### Privacy Controls (FR44-FR46)
- **FR44:** GPS stored at coarse level (city) by default in public view
- **FR45:** Users can opt-out of location (noted in evidence, not suspicious)
- **FR46:** Depth map stored but not publicly downloadable (only visualization)

### Video Capture (FR47-FR55)
- **FR47:** App records video up to 15 seconds with LiDAR depth at 10fps
- **FR48:** App displays real-time edge-detection depth overlay during recording
- **FR49:** App computes frame hash chain (each frame hashes with previous)
- **FR50:** App generates attestation for complete or interrupted videos
- **FR51:** App collects same metadata for video as photos
- **FR52:** Backend verifies video hash chain integrity
- **FR53:** Backend analyzes depth consistency across video frames
- **FR54:** Backend generates C2PA manifest for video files
- **FR55:** Verification page displays video with playback and evidence

### Privacy-First Capture (FR56-FR62)
- **FR56:** App provides "Privacy Mode" toggle in capture settings
- **FR57:** In Privacy Mode, app performs depth analysis locally (variance, layers, edge coherence)
- **FR58:** In Privacy Mode, app uploads only: hash(media) + depth_analysis_result + attestation_signature
- **FR59:** Backend accepts pre-computed depth analysis signed by attested device
- **FR60:** Backend stores hash + evidence without raw media (media never touches server)
- **FR61:** Verification page displays "Hash Verified" with note about device attestation
- **FR62:** Users can configure per-capture metadata: location, timestamp, device info granularity

---

## Epic 1: Foundation & Project Setup

**Goal:** Establish development infrastructure enabling all subsequent work. Creates monorepo structure, local dev environment, and deployment pipeline basics.

**User Value:** Foundation epic (necessary exception) - enables development velocity for all subsequent epics.

**FRs Covered:** Infrastructure foundation for all FRs

### Story 1.1: Initialize Monorepo Structure

As a **developer**,
I want **the project scaffolded with all three components (mobile, web, backend)**,
So that **I can begin implementing features across the stack**.

**Acceptance Criteria:**

**Given** a fresh development environment with Node.js 22+, Rust 1.82+, and Xcode 16+
**When** I clone the repository and run setup commands
**Then** I have:
- Expo app created at `apps/mobile/` with TypeScript blank template
- Next.js 16 app created at `apps/web/` with App Router, TypeScript, Tailwind
- Rust project created at `backend/` with Axum dependencies configured
- Shared types package at `packages/shared/`
- Root-level scripts for running all services

**And** the folder structure matches the architecture document:
```
realitycam/
├── apps/
│   ├── mobile/          # Expo SDK 53 + React Native 0.79
│   └── web/             # Next.js 16 + Turbopack
├── packages/
│   └── shared/          # TypeScript types
├── backend/             # Rust/Axum
├── infrastructure/
│   └── docker-compose.yml
└── docs/
```

**Prerequisites:** None (first story)

**Technical Notes:**
- Use `bunx create-expo-app@latest` for mobile
- Use `npx create-next-app@latest` with `--turbopack` for web
- Use `cargo new` for backend with Cargo.toml per architecture doc
- Configure Expo for iOS-only prebuild (`npx expo prebuild --platform ios`)

---

### Story 1.2: Configure Local Development Environment

As a **developer**,
I want **local services (Postgres, S3-compatible storage) running via Docker**,
So that **I can develop and test without external dependencies**.

**Acceptance Criteria:**

**Given** Docker is installed and running
**When** I run `docker-compose up -d` from project root
**Then** the following services are available:
- PostgreSQL 16 on localhost:5432
- LocalStack S3 on localhost:4566
- Health checks pass for both services

**And** environment files exist with local defaults:
- `backend/.env.example` with `DATABASE_URL`, `S3_ENDPOINT`, `S3_BUCKET`
- `apps/mobile/.env.example` with `API_URL`
- `apps/web/.env.example` with `API_URL`

**Prerequisites:** Story 1.1

**Technical Notes:**
- Use `docker-compose.yml` in `infrastructure/`
- PostgreSQL should have `realitycam` database pre-created
- LocalStack bucket `realitycam-media-dev` auto-created on startup
- Document setup in README.md

---

### Story 1.3: Initialize Database Schema

As a **developer**,
I want **the database schema created with migrations**,
So that **I can store devices, captures, and evidence**.

**Acceptance Criteria:**

**Given** PostgreSQL is running and accessible
**When** I run `sqlx migrate run` from backend directory
**Then** the following tables exist:
- `devices` table with columns: id (UUID), attestation_level, attestation_key_id, attestation_chain, platform, model, has_lidar, first_seen_at, last_seen_at
- `captures` table with columns: id (UUID), device_id (FK), target_media_hash, evidence (JSONB), confidence_level, status, captured_at, uploaded_at
- `verification_logs` table with columns: id, capture_id, action, client_ip, timestamp

**And** indexes are created:
- Hash index on `captures.target_media_hash` for O(1) lookups
- B-tree index on `captures.device_id`

**Prerequisites:** Story 1.2

**Technical Notes:**
- Use SQLx migrations in `backend/migrations/`
- Enable `uuid-ossp` extension for `gen_random_uuid()`
- Use `TIMESTAMPTZ` for all timestamps
- JSONB for evidence allows flexible schema evolution

---

### Story 1.4: Backend API Skeleton with Health Check

As a **developer**,
I want **a running Axum server with basic routing and health endpoint**,
So that **I can verify the backend is operational and start adding routes**.

**Acceptance Criteria:**

**Given** the database is running and migrations applied
**When** I run `cargo run` from backend directory
**Then** the server starts on port 8080

**And** `GET /health` returns:
```json
{
  "status": "ok",
  "database": "connected",
  "version": "0.1.0"
}
```

**And** the following route stubs exist (returning 501 Not Implemented):
- `POST /api/v1/devices/register`
- `POST /api/v1/captures`
- `GET /api/v1/captures/{id}`
- `POST /api/v1/verify-file`

**And** request logging is enabled with tracing

**Prerequisites:** Story 1.3

**Technical Notes:**
- Use `tower-http` for CORS, tracing, request-id middleware
- Configure CORS to allow localhost origins for dev
- Use `dotenvy` for environment variable loading
- Structure routes in `src/routes/` per architecture

---

### Story 1.5: Mobile App Skeleton with Navigation

As a **developer**,
I want **the Expo app running with tab navigation structure**,
So that **I can start implementing capture and history screens**.

**Acceptance Criteria:**

**Given** Xcode is installed and iOS simulator available
**When** I run `npx expo start` and open in iOS simulator
**Then** the app displays with two tabs:
- "Capture" tab (placeholder screen)
- "History" tab (placeholder screen)

**And** navigation works between tabs

**And** the app can be prebuilt for iOS with `npx expo prebuild --platform ios`

**Prerequisites:** Story 1.1

**Technical Notes:**
- Use Expo Router with file-based routing in `app/` directory
- Tab layout in `app/(tabs)/_layout.tsx`
- Install expo-camera, expo-crypto, expo-secure-store for later stories
- Configure `app.config.ts` with bundle identifier for iOS

---

### Story 1.6: Web App Skeleton with Verification Route

As a **developer**,
I want **the Next.js app running with verification page route**,
So that **I can start implementing the verification UI**.

**Acceptance Criteria:**

**Given** Node.js 22+ is installed
**When** I run `npm run dev` from apps/web directory
**Then** the app starts with Turbopack on localhost:3000

**And** the following routes exist:
- `/` - Landing page (placeholder)
- `/verify/[id]` - Verification page (placeholder showing "Verifying capture: {id}")

**And** Tailwind CSS is configured and working

**Prerequisites:** Story 1.1

**Technical Notes:**
- Use App Router (`app/` directory)
- Configure Turbopack (default in Next.js 16)
- Create API client stub in `lib/api.ts`
- Set up TypeScript path aliases for imports

---

## Epic 2: Device Registration & Attestation

**Goal:** Enable iPhone Pro devices to securely register with hardware-rooted trust via DCAppAttest and Secure Enclave.

**User Value:** Device owner can register their iPhone Pro and receive cryptographic attestation that proves their device is genuine and uncompromised.

**FRs Covered:** FR1-FR5, FR41-FR43

### Story 2.1: Detect iPhone Pro and LiDAR Capability

As a **user**,
I want **the app to verify my device is an iPhone Pro with LiDAR**,
So that **I know whether I can use the full attestation features**.

**Acceptance Criteria:**

**Given** a user launches the app on an iOS device
**When** the app initializes
**Then** it detects:
- Device model (e.g., "iPhone 15 Pro")
- iOS version (must be 14.0+)
- LiDAR availability (via ARKit `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)`)
- Secure Enclave availability

**And** if device is NOT iPhone Pro (no LiDAR):
- Display clear message: "rial. requires iPhone Pro with LiDAR sensor"
- Explain why: "LiDAR enables real 3D scene verification"
- Block access to capture features

**And** if device IS iPhone Pro:
- Proceed to device registration flow
- Store device capabilities in local state

**Prerequisites:** Story 1.5

**Technical Notes:**
- Use `expo-device` for model detection
- Check ARKit configuration support for LiDAR
- Store capabilities in Zustand store for later use
- Device model list: iPhone 12/13/14/15/16/17 Pro and Pro Max

---

### Story 2.2: Generate Secure Enclave Key Pair

As a **user**,
I want **my device to generate a hardware-backed cryptographic key**,
So that **my captures can be cryptographically signed by my device**.

**Acceptance Criteria:**

**Given** the app determines this is a first launch (no existing key)
**When** the app requests key generation
**Then** `@expo/app-integrity` generates a key pair in Secure Enclave:
- Key ID is returned and stored in `expo-secure-store`
- Key is Ed25519 compatible
- Key is hardware-bound (cannot be extracted)

**And** on subsequent launches:
- Existing key ID is retrieved from secure storage
- No new key generation occurs

**And** key generation failure (e.g., jailbroken device) results in:
- Clear error message to user
- App remains functional but captures marked "unverified"

**Prerequisites:** Story 2.1

**Technical Notes:**
- Use `AppIntegrity.generateKeyAsync()` from `@expo/app-integrity`
- Store key ID in `expo-secure-store` with key `attestation_key_id`
- Key generation is one-time per device install
- Handle jailbreak detection gracefully (attestation will fail but app should work)

---

### Story 2.3: Request DCAppAttest Attestation

As a **user**,
I want **my device to obtain an attestation certificate from Apple**,
So that **the backend can verify my device is genuine**.

**Acceptance Criteria:**

**Given** a key pair exists in Secure Enclave
**When** the app requests attestation (on first registration)
**Then** the following flow executes:
1. App requests a challenge from backend (`GET /api/v1/devices/challenge`)
2. Backend returns a random 32-byte challenge (nonce)
3. App calls `AppIntegrity.attestKeyAsync(keyId, challenge)`
4. iOS returns attestation object (base64 string) containing:
   - Certificate chain (Secure Enclave → Apple CA)
   - Device integrity assertion
   - Challenge binding

**And** attestation object is ready to send to backend

**And** if attestation fails (compromised device):
- User sees: "Device attestation failed - captures will be marked unverified"
- App continues with degraded functionality

**Prerequisites:** Story 2.2, Story 1.4

**Technical Notes:**
- Challenge must be fresh (single-use, expires in 5 minutes)
- `attestKeyAsync()` returns base64 string for server verification
- Attestation is ONE-TIME per key - don't re-attest unnecessarily
- Store attestation status in device state

---

### Story 2.4: Backend Challenge Endpoint

As a **mobile app**,
I want **to request a fresh challenge from the backend**,
So that **the attestation is bound to a recent server interaction**.

**Acceptance Criteria:**

**Given** the backend is running
**When** mobile app calls `GET /api/v1/devices/challenge`
**Then** backend returns:
```json
{
  "data": {
    "challenge": "base64-encoded-32-bytes",
    "expires_at": "2025-11-22T10:35:00Z"
  }
}
```

**And** challenge is:
- Cryptographically random (32 bytes)
- Stored server-side with 5-minute expiry
- Single-use (invalidated after verification)

**Prerequisites:** Story 1.4

**Technical Notes:**
- Use in-memory store for MVP (Redis for production)
- Challenge format: base64-encoded 32 random bytes
- Include rate limiting: 10 challenges/minute/IP
- Clean up expired challenges periodically

---

### Story 2.5: Backend DCAppAttest Verification

As a **backend service**,
I want **to verify DCAppAttest attestation objects against Apple's servers**,
So that **I can trust the device identity is hardware-backed**.

**Acceptance Criteria:**

**Given** a device sends attestation object with challenge
**When** backend receives `POST /api/v1/devices/register`:
```json
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
```

**Then** backend performs verification:
1. Decode CBOR attestation object
2. Extract certificate chain
3. Verify chain roots to Apple's App Attest CA
4. Verify challenge matches stored challenge
5. Verify counter and app identity

**And** on successful verification:
- Create device record with `attestation_level: "secure_enclave"`
- Store `attestation_key_id` and certificate chain
- Return device ID to app

**And** on failed verification:
- Create device record with `attestation_level: "unverified"`
- Log failure reason for debugging
- Return device ID (device can still capture, but marked unverified)

**Prerequisites:** Story 2.4

**Technical Notes:**
- Use `x509-parser` crate for certificate parsing
- Apple App Attest root cert embedded in binary
- Verify app ID matches your Team ID + Bundle ID
- Store attestation chain for audit purposes
- Endpoint: `POST /api/v1/devices/register`

---

### Story 2.6: Complete Device Registration Flow

As a **user**,
I want **to complete device registration and see my attestation status**,
So that **I understand the trust level of my captures**.

**Acceptance Criteria:**

**Given** attestation has completed (success or failure)
**When** the app receives the device registration response
**Then** the app:
1. Stores device ID in secure storage
2. Stores attestation level in local state
3. Shows registration success screen with:
   - Device ID (truncated for display)
   - Attestation level badge (✓ Secure Enclave / ⚠ Unverified)
   - Explanation of what this means

**And** the user can proceed to capture screen

**And** device ID persists across app restarts

**Prerequisites:** Story 2.5

**Technical Notes:**
- Store `device_id` in `expo-secure-store`
- Store `attestation_level` in Zustand (persisted)
- Registration is one-time; skip on subsequent launches
- If attestation_level is "unverified", show subtle warning on capture screen

---

### Story 2.7: Device Signature for API Requests

As a **mobile app**,
I want **to sign every API request with my device key**,
So that **the backend can verify requests came from a registered device**.

**Acceptance Criteria:**

**Given** a device is registered and has a key in Secure Enclave
**When** the app makes any authenticated API request
**Then** the request includes:
```
X-Device-Id: {device_uuid}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {ed25519_signature}
```

**And** signature is computed over:
```
message = timestamp + "|" + sha256(request_body)
signature = sign(message, device_key)
```

**And** backend verifies:
1. Device ID exists in database
2. Timestamp within 5-minute window
3. Signature valid against stored public key

**Prerequisites:** Story 2.6

**Technical Notes:**
- Use `AppIntegrity.generateAssertionAsync()` for per-request signing
- Include assertion in request body or custom header
- Backend middleware validates before route handlers
- Cache device public key in memory for performance

---

## Epic 3: Photo Capture with LiDAR Depth

**Goal:** Enable users to capture photos with simultaneous LiDAR depth maps, providing the primary evidence signal for authenticity verification.

**User Value:** User can capture photos that include 3D depth data proving they photographed a real scene (not a screen or flat image).

**FRs Covered:** FR6-FR13

### Story 3.1: Create Custom LiDAR Depth Module (Swift)

As a **developer**,
I want **a custom Expo Module that captures LiDAR depth data via ARKit**,
So that **the app can simultaneously capture depth maps with photos**.

**Acceptance Criteria:**

**Given** Xcode and the Expo prebuild environment
**When** the custom module is built and installed
**Then** the module provides the following TypeScript API:
```typescript
interface LiDARModule {
  isLiDARAvailable(): Promise<boolean>;
  startDepthCapture(): Promise<void>;
  stopDepthCapture(): Promise<void>;
  captureDepthFrame(): Promise<DepthFrame>;
  getRealtimeDepthData(): Observable<DepthData>; // For overlay
}

interface DepthFrame {
  depthMap: Float32Array;  // Width × Height float32 values (meters)
  width: number;
  height: number;
  timestamp: number;
  intrinsics: CameraIntrinsics;
}
```

**And** the Swift implementation:
- Uses `ARSession` with `ARWorldTrackingConfiguration` and `.sceneDepth`
- Extracts `ARFrame.sceneDepth.depthMap` as `CVPixelBuffer`
- Converts to `Float32Array` for JavaScript consumption
- Provides real-time depth updates for overlay at 30fps

**Prerequisites:** Story 1.5

**Technical Notes:**
- Create module at `apps/mobile/modules/lidar-depth/`
- Use Expo Modules API for Swift ↔ JS bridge
- ~400 lines of Swift code
- Handle ARSession lifecycle (pause on background, resume on foreground)
- Depth map resolution typically 256×192 on iPhone Pro

---

### Story 3.2: Basic Camera View with Photo Capture

As a **user**,
I want **to see a camera viewfinder and take photos**,
So that **I can capture images for attestation**.

**Acceptance Criteria:**

**Given** the user is on the Capture tab and has granted camera permission
**When** the camera view loads
**Then** the user sees:
- Full-screen camera preview (back camera, wide lens)
- Capture button at bottom center
- Shutter animation on capture

**And** when user taps capture button:
- Photo is captured at full resolution
- Haptic feedback confirms capture
- Photo preview appears briefly

**And** camera permission is requested if not granted

**Prerequisites:** Story 1.5

**Technical Notes:**
- Use `expo-camera` with `Camera` component
- Configure for back camera, photo mode
- Use highest available resolution (4032×3024 on recent Pro models)
- Store photo temporarily in app cache

---

### Story 3.3: LiDAR Depth Overlay on Camera View

As a **user**,
I want **to see a real-time depth visualization overlaid on the camera**,
So that **I understand the LiDAR is capturing depth data**.

**Acceptance Criteria:**

**Given** the camera view is active and LiDAR is available
**When** the depth overlay is enabled
**Then** the user sees:
- Semi-transparent depth heatmap overlaid on camera preview
- Near objects appear in warm colors (red/orange)
- Far objects appear in cool colors (blue/purple)
- Overlay updates at ~30fps
- Toggle button to show/hide depth overlay

**And** depth visualization:
- Uses colormap (e.g., viridis or plasma)
- Scales depth values from 0-5 meters
- Has transparency (~40%) to see underlying photo

**Prerequisites:** Story 3.1, Story 3.2

**Technical Notes:**
- Use `getRealtimeDepthData()` from LiDAR module
- Render depth as colored overlay using React Native canvas or GL view
- Consider `react-native-skia` for performant rendering
- Overlay should not significantly impact camera frame rate

---

### Story 3.4: Synchronized Photo + Depth Capture

As a **user**,
I want **my photo and depth map captured at the exact same moment**,
So that **the depth data accurately represents the photo content**.

**Acceptance Criteria:**

**Given** the user is viewing camera with depth overlay active
**When** the user taps the capture button
**Then** the app simultaneously captures:
1. Full-resolution photo from camera
2. Depth map from LiDAR (closest frame to photo timestamp)
3. Capture timestamp (device time, UTC)

**And** both captures are:
- Within 100ms of each other (synchronized)
- Stored together as a capture unit
- Ready for local processing

**And** the preview screen shows:
- The captured photo
- Depth visualization overlay option
- "Processing..." indicator

**Prerequisites:** Story 3.3

**Technical Notes:**
- ARKit provides synchronized depth with video frames
- Use ARFrame.capturedImage + ARFrame.sceneDepth for sync
- May need to trigger ARKit capture directly rather than expo-camera
- Store both in temporary directory pending upload

---

### Story 3.5: GPS Location Capture

As a **user**,
I want **my photo's location recorded (if I grant permission)**,
So that **location can be part of the evidence package**.

**Acceptance Criteria:**

**Given** the user has granted location permission
**When** a photo is captured
**Then** GPS coordinates are recorded:
- Latitude and longitude (6 decimal places, ~11cm precision)
- Altitude (if available)
- Accuracy estimate
- Timestamp of GPS fix

**And** if location permission is denied:
- Capture proceeds without location
- Evidence will note "location unavailable"
- User is not blocked from capturing

**And** location is stored with the capture metadata

**Prerequisites:** Story 3.4

**Technical Notes:**
- Use `expo-location` for GPS access
- Request permission on first capture (not app launch)
- Store coordinates in capture metadata JSON
- Privacy coarsening (to city level) happens server-side per FR44

---

### Story 3.6: Generate Capture Assertion (Per-Photo Signature)

As a **user**,
I want **each photo signed by my device's hardware key**,
So that **the backend can verify this specific capture came from my attested device**.

**Acceptance Criteria:**

**Given** a photo + depth capture is complete
**When** the capture is being prepared for upload
**Then** the app generates an assertion:
1. Compute SHA-256 hash of photo JPEG
2. Create clientDataHash from capture metadata (timestamp, location, device model)
3. Call `AppIntegrity.generateAssertionAsync(keyId, clientDataHash)`
4. Receive assertion object (base64)

**And** the assertion is:
- Bound to this specific capture's data
- Signed by Secure Enclave key
- Included in upload payload

**Prerequisites:** Story 3.4, Story 2.7

**Technical Notes:**
- `generateAssertionAsync()` is per-capture (unlike attestation which is one-time)
- clientDataHash binds assertion to specific data
- Backend will verify assertion against registered device key
- Assertion proves capture came from THIS attested device

---

### Story 3.7: Local Processing Pipeline

As a **user**,
I want **my capture processed locally before upload**,
So that **the upload package is complete and efficient**.

**Acceptance Criteria:**

**Given** a synchronized photo + depth capture exists
**When** local processing runs
**Then** the following are computed:
1. **Photo hash:** SHA-256 of JPEG bytes (32 bytes)
2. **Compressed depth map:** gzip-compressed Float32Array (~1MB)
3. **Capture metadata JSON:**
   ```json
   {
     "captured_at": "2025-11-22T10:30:00.123Z",
     "device_model": "iPhone 15 Pro",
     "photo_hash": "base64...",
     "location": { "lat": 37.7749, "lng": -122.4194 },
     "depth_map_dimensions": { "width": 256, "height": 192 },
     "assertion": "base64..."
   }
   ```

**And** all components are stored locally awaiting upload

**And** progress indicator shows processing status

**Prerequisites:** Story 3.5, Story 3.6

**Technical Notes:**
- Use `expo-crypto` for SHA-256 hashing
- Use pako or similar for gzip compression in JS
- Store in app's document directory with capture ID
- Total upload size: ~3MB photo + ~1MB depth + ~1KB metadata

---

### Story 3.8: Capture Preview with Depth Visualization

As a **user**,
I want **to preview my capture with depth visualization before upload**,
So that **I can verify the capture looks correct**.

**Acceptance Criteria:**

**Given** a capture has completed local processing
**When** the preview screen displays
**Then** the user sees:
- Full-resolution photo
- Toggle to overlay depth visualization
- Capture metadata summary (time, location if available)
- Device attestation badge (✓ or ⚠)

**And** the user can:
- Tap "Upload" to proceed with upload
- Tap "Discard" to delete the capture
- Tap "Capture Another" to return to camera

**And** the depth overlay shows:
- Color-coded depth heatmap
- Transparency slider (0-100%)

**Prerequisites:** Story 3.7

**Technical Notes:**
- Route to `preview.tsx` after capture
- Pass capture ID as route param
- Load photo and depth from local storage
- Render depth overlay similar to camera view

---

## Epic 4: Upload & Evidence Processing

**Goal:** Process uploaded captures through the evidence generation pipeline, including depth analysis, attestation verification, and metadata validation.

**User Value:** User's captured photos are analyzed and assigned a confidence level based on hardware attestation, LiDAR depth analysis, and metadata consistency.

**FRs Covered:** FR14-FR26, FR44-FR46

### Story 4.1: Multipart Upload Endpoint

As a **mobile app**,
I want **to upload photos with depth maps and metadata in a single request**,
So that **all capture data is submitted atomically**.

**Acceptance Criteria:**

**Given** a registered device with a processed capture
**When** the app calls `POST /api/v1/captures` with multipart/form-data:
- Part `photo`: JPEG binary (~3MB)
- Part `depth_map`: gzipped float32 array (~1MB)
- Part `metadata`: JSON with captured_at, location, device_model, assertion

**Then** the backend:
1. Validates device signature headers (X-Device-Id, X-Device-Timestamp, X-Device-Signature)
2. Verifies device exists and is registered
3. Stores photo and depth_map to S3
4. Creates pending capture record in database
5. Returns capture ID and "processing" status

**And** response format:
```json
{
  "data": {
    "capture_id": "uuid",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/{uuid}"
  }
}
```

**Prerequisites:** Story 1.4, Story 2.7

**Technical Notes:**
- Use `axum-extra` multipart handling
- Stream parts directly to S3 (avoid loading 4MB into memory)
- Generate presigned upload URLs if needed for large files
- Apply rate limiting: 10 captures/hour/device

---

### Story 4.2: Mobile Upload Queue with Retry

As a **user**,
I want **my captures to upload reliably with automatic retry**,
So that **I don't lose captures due to network issues**.

**Acceptance Criteria:**

**Given** a capture is ready for upload
**When** the user initiates upload (or auto-upload from queue)
**Then** the upload queue:
1. Adds capture to persistent queue (survives app restart)
2. Attempts upload via TLS 1.3
3. Shows progress indicator (0-100%)
4. On success: removes from queue, shows verification URL
5. On failure: implements exponential backoff (1s, 2s, 4s, 8s, max 5 minutes)

**And** the user can:
- See pending uploads in History tab
- Cancel a pending upload
- Retry a failed upload manually

**And** auto-retry continues in background (with user consent)

**Prerequisites:** Story 4.1, Story 3.8

**Technical Notes:**
- Store queue in `expo-secure-store` or SQLite
- Use `expo-background-fetch` for background uploads
- Show notification when upload completes in background
- Track retry count; mark as "failed" after 10 attempts

---

### Story 4.3: Offline Storage with Encryption

As a **user**,
I want **my captures stored securely when offline**,
So that **they remain private until uploaded**.

**Acceptance Criteria:**

**Given** a capture is taken while device is offline
**When** the capture is stored locally
**Then** storage is:
- Encrypted using Secure Enclave-backed key
- Stored in app's document directory
- Marked as "pending upload" in local database

**And** the user sees:
- "Offline" badge on capture in History
- "Will upload when online" message
- Warning: "Timestamp verification will differ from capture time"

**And** when connectivity returns:
- Captures automatically queue for upload
- Upload order preserves capture chronology

**Prerequisites:** Story 4.2

**Technical Notes:**
- Use `expo-secure-store` for encryption key management
- Encrypt photo, depth map, and metadata together
- Store offline captures in separate directory
- Check connectivity via `@react-native-community/netinfo`

---

### Story 4.4: Backend Assertion Verification

As a **backend service**,
I want **to verify the per-capture assertion from the mobile app**,
So that **I can confirm this capture came from a registered, attested device**.

**Acceptance Criteria:**

**Given** an upload includes an assertion in metadata
**When** backend processes the capture
**Then** assertion verification:
1. Extracts assertion from metadata JSON
2. Looks up device by X-Device-Id header
3. Retrieves device's attestation public key
4. Decodes CBOR assertion object
5. Verifies signature over clientDataHash
6. Verifies counter increment (replay protection)

**And** on successful verification:
- Record attestation check as "pass" in evidence
- Update device counter in database

**And** on failed verification:
- Record attestation check as "fail" in evidence
- Log failure reason
- Continue processing (don't reject capture)

**Prerequisites:** Story 4.1, Story 2.5

**Technical Notes:**
- Assertion verification similar to attestation but simpler
- Use same `x509-parser` and crypto libraries
- Counter must be strictly increasing per device
- Store last-seen counter to detect replays

---

### Story 4.5: LiDAR Depth Analysis Service

As a **backend service**,
I want **to analyze depth maps and detect flat vs. real scenes**,
So that **I can determine if the photo shows a real 3D environment**.

**Acceptance Criteria:**

**Given** an uploaded capture with depth_map
**When** depth analysis runs
**Then** the service computes:
```rust
DepthAnalysis {
    depth_variance: f32,      // Std dev of depth values
    edge_coherence: f32,      // Correlation of depth edges with RGB edges
    min_depth: f32,           // Nearest point in meters
    max_depth: f32,           // Farthest point in meters
    depth_layers: u32,        // Number of distinct depth planes
    is_likely_real_scene: bool
}
```

**And** "is_likely_real_scene" is true when:
- `depth_variance > 0.5`
- `depth_layers >= 3`
- `edge_coherence > 0.7`

**And** depth analysis runs in < 5 seconds

**And** results are stored in evidence package

**Prerequisites:** Story 4.1

**Technical Notes:**
- Decompress gzipped depth map
- Use Canny edge detection on RGB for edge coherence
- Depth layer detection: histogram peaks in depth distribution
- Flat images (screens): variance ~0.02, layers = 1-2, min_depth ~0.3-0.5m
- Real scenes: variance > 0.5, layers >= 3, varying depths

---

### Story 4.6: Metadata Consistency Checks

As a **backend service**,
I want **to validate capture metadata for consistency**,
So that **I can detect obvious manipulation attempts**.

**Acceptance Criteria:**

**Given** an uploaded capture with metadata
**When** metadata validation runs
**Then** the following checks are performed:

| Check | Criteria | Status |
|-------|----------|--------|
| Timestamp validity | EXIF time within 15 min of server receipt | pass/fail |
| Device model | Model is iPhone Pro with LiDAR | pass/fail |
| Resolution | Matches device capability | pass/unavailable |
| Location plausibility | If provided, coords are on Earth | pass/fail/unavailable |

**And** each check result is recorded in evidence package

**And** failures don't reject the capture, but lower confidence

**Prerequisites:** Story 4.1

**Technical Notes:**
- Parse EXIF from JPEG using `kamadak-exif` crate
- Device model whitelist: iPhone 12-17 Pro/Pro Max
- Resolution check: compare to known device resolutions
- Location: lat -90 to 90, lng -180 to 180

---

### Story 4.7: Privacy Coarsening for Location

As a **privacy-conscious system**,
I want **to coarsen GPS coordinates before public display**,
So that **exact locations are not exposed**.

**Acceptance Criteria:**

**Given** a capture with full-precision GPS coordinates
**When** evidence is prepared for public display
**Then** location is coarsened:
- Coordinates rounded to 2 decimal places (~1.1km precision)
- Displayed as city-level (reverse geocode to city name)
- Full precision stored but marked "not publicly accessible"

**And** if user opted out of location:
- Evidence notes "location not provided"
- Status is "unavailable" (not suspicious)

**Prerequisites:** Story 4.6

**Technical Notes:**
- Store both: `location_precise` (internal) and `location_coarse` (public)
- Reverse geocoding via external API or offline database
- Per FR45: opt-out noted but not penalized in confidence

---

### Story 4.8: Evidence Package Assembly

As a **backend service**,
I want **to assemble all check results into a unified evidence package**,
So that **the verification page has complete evidence to display**.

**Acceptance Criteria:**

**Given** all evidence checks have completed
**When** evidence package is assembled
**Then** the package contains:
```json
{
  "hardware_attestation": {
    "status": "pass|fail|unavailable",
    "level": "secure_enclave|unverified",
    "device_model": "iPhone 15 Pro"
  },
  "depth_analysis": {
    "status": "pass|fail",
    "depth_variance": 2.4,
    "depth_layers": 5,
    "edge_coherence": 0.87,
    "min_depth": 0.8,
    "max_depth": 4.2,
    "is_likely_real_scene": true
  },
  "metadata": {
    "timestamp_valid": true,
    "model_verified": true,
    "location_available": true,
    "location_coarse": "San Francisco, CA"
  }
}
```

**And** evidence is stored as JSONB in captures table

**Prerequisites:** Story 4.4, Story 4.5, Story 4.6, Story 4.7

**Technical Notes:**
- All checks must complete before package is final
- Use database transaction for consistency
- Evidence structure supports future check additions

---

### Story 4.9: Confidence Level Calculation

As a **backend service**,
I want **to calculate overall confidence from evidence checks**,
So that **users get a clear trust signal**.

**Acceptance Criteria:**

**Given** a complete evidence package
**When** confidence is calculated
**Then** the algorithm is:
```
if any_check_status == "fail":
    return SUSPICIOUS

hardware_pass = hardware_attestation.status == "pass"
depth_pass = depth_analysis.is_likely_real_scene

match (hardware_pass, depth_pass):
    (true, true)   => HIGH
    (true, false)  => MEDIUM  // Hardware OK, depth suspicious
    (false, true)  => MEDIUM  // Depth OK, hardware unverified
    (false, false) => LOW
```

**And** confidence level is stored with capture

**And** capture status changes from "processing" to "complete"

**Prerequisites:** Story 4.8

**Technical Notes:**
- Confidence levels: HIGH, MEDIUM, LOW, SUSPICIOUS
- "unavailable" status doesn't cause SUSPICIOUS
- Future: weights per check type for nuanced scoring

---

### Story 4.10: Upload Result Display in App

As a **user**,
I want **to see my capture's verification result after upload**,
So that **I know the evidence strength and can share the verify link**.

**Acceptance Criteria:**

**Given** an upload has completed processing
**When** the result screen displays
**Then** the user sees:
- Confidence badge (HIGH/MEDIUM/LOW with color coding)
- Brief explanation of what each evidence type found
- Shareable verification URL
- "Share" button (native share sheet)
- "View Details" to see full evidence breakdown

**And** the verification URL is:
- Short and memorable: `https://realitycam.app/v/{short_id}`
- Copyable with one tap

**Prerequisites:** Story 4.9, Story 3.8

**Technical Notes:**
- Poll backend for completion (or use WebSocket)
- Navigate to `result.tsx` when processing complete
- Store verification URL in local history
- Short ID: base62 encoding of UUID prefix (8 chars)

---

## Epic 5: C2PA & Verification Experience

**Goal:** Generate C2PA manifests for interoperability and provide a public verification interface for recipients to verify photo authenticity.

**User Value:** Recipients can verify photos via shareable links, see confidence levels, explore evidence details, and verify files by uploading them.

**FRs Covered:** FR27-FR40

### Story 5.1: C2PA Manifest Generation

As a **backend service**,
I want **to create C2PA manifests containing our evidence summary**,
So that **photos are interoperable with the Content Credentials ecosystem**.

**Acceptance Criteria:**

**Given** a capture with completed evidence package
**When** C2PA manifest generation runs
**Then** the manifest contains:
- **Claim Generator:** "rial./1.0.0"
- **Actions:** "c2pa.created" with timestamp
- **Assertions:**
  - Hardware attestation level
  - Depth analysis summary (real_scene: true/false)
  - Confidence level (HIGH/MEDIUM/LOW/SUSPICIOUS)
  - Device model
- **Signature:** Ed25519, certificate chain embedded

**And** manifest is valid per C2PA spec 2.0

**And** manifest is stored as separate file (captures/{id}/manifest.c2pa)

**Prerequisites:** Story 4.9

**Technical Notes:**
- Use `c2pa-rs` crate version 0.51.x
- Ed25519 signing key from AWS KMS (HSM-backed)
- Include our CA cert in certificate chain
- Custom assertion schema for depth analysis

---

### Story 5.2: C2PA Manifest Embedding

As a **backend service**,
I want **to embed the C2PA manifest into the photo file**,
So that **the photo carries its provenance metadata**.

**Acceptance Criteria:**

**Given** a C2PA manifest has been generated
**When** embedding runs
**Then**:
- Original photo preserved at `captures/{id}/original.jpg`
- C2PA-embedded photo created at `captures/{id}/c2pa.jpg`
- Manifest embedded in JUMBF box per C2PA spec
- Photo remains valid JPEG, viewable in any viewer

**And** both versions are accessible via API

**Prerequisites:** Story 5.1

**Technical Notes:**
- `c2pa-rs` handles JUMBF embedding
- Embedded photo slightly larger (~5-10KB for manifest)
- Preserve original for hash verification
- CDN serves both versions

---

### Story 5.3: Verification Page - Confidence Summary

As a **verification page visitor**,
I want **to see a clear confidence summary when I open a verify link**,
So that **I immediately understand the trust level of this photo**.

**Acceptance Criteria:**

**Given** a user opens `https://realitycam.app/verify/{id}`
**When** the page loads
**Then** the user sees:
- **Hero section:** Photo thumbnail with confidence badge overlay
- **Confidence badge:** Large, color-coded (GREEN=HIGH, YELLOW=MEDIUM, ORANGE=LOW, RED=SUSPICIOUS)
- **One-line summary:** "This photo has HIGH confidence" or similar
- **Captured timestamp:** "Captured Nov 22, 2025 at 10:30 AM"
- **Location:** City-level if available, "Location not provided" if opted out

**And** the page loads in < 1.5s (FCP)

**And** meta tags support social sharing (OG image, title, description)

**Prerequisites:** Story 1.6

**Technical Notes:**
- Next.js App Router with server components for SEO
- Fetch capture data from backend API
- Generate OG image dynamically with confidence badge
- CDN caching for static assets

---

### Story 5.4: Verification Page - Depth Analysis Visualization

As a **verification page visitor**,
I want **to see a visualization of the depth analysis**,
So that **I can understand the 3D scene verification evidence**.

**Acceptance Criteria:**

**Given** the verification page is displaying a capture
**When** the user views the depth section
**Then** the user sees:
- **Depth heatmap overlay:** Toggle-able over the photo
- **Depth metrics:**
  - "Depth Variance: 2.4" (with explanation: "Higher = more 3D structure")
  - "Depth Layers: 5" (with explanation: "Number of distinct distances detected")
  - "Edge Coherence: 87%" (with explanation: "Depth boundaries match photo edges")
- **Verdict:** "✓ Real 3D Scene Detected" or "⚠ Flat Surface Detected"

**And** tooltip explanations help non-technical users understand

**Prerequisites:** Story 5.3

**Technical Notes:**
- Pre-render depth visualization server-side (PNG) for performance
- Store depth preview at `captures/{id}/depth-preview.png`
- Interactive toggle for overlay on client
- Consider 3D point cloud view for forensic users (post-MVP)

---

### Story 5.5: Verification Page - Evidence Panel

As a **verification page visitor**,
I want **to expand a detailed evidence panel**,
So that **I can see the status of each individual check**.

**Acceptance Criteria:**

**Given** the verification page is displaying a capture
**When** the user clicks "View Full Evidence"
**Then** an expandable panel shows:

| Check | Status | Details |
|-------|--------|---------|
| Hardware Attestation | ✓ PASS | Secure Enclave, iPhone 15 Pro |
| LiDAR Depth Analysis | ✓ PASS | Real 3D scene, 5 depth layers |
| Timestamp | ✓ PASS | Captured Nov 22, 2025 10:30:00 UTC |
| Device Model | ✓ PASS | iPhone 15 Pro (has LiDAR) |
| Location | — UNAVAILABLE | User opted out |

**And** each status has appropriate icon:
- ✓ (green) for PASS
- ✗ (red) for FAIL
- — (gray) for UNAVAILABLE

**And** "UNAVAILABLE" is explained: "This check could not be performed but is not suspicious"

**Prerequisites:** Story 5.3

**Technical Notes:**
- Collapsible accordion component
- Color-coded status badges
- Link to methodology documentation for transparency
- Future: raw data download for forensic analysts

---

### Story 5.6: Verification Page - C2PA Manifest Display

As a **verification page visitor**,
I want **to see and download the C2PA manifest**,
So that **I can verify the photo in other C2PA-compatible tools**.

**Acceptance Criteria:**

**Given** the verification page is displaying a capture
**When** the user scrolls to the C2PA section
**Then** the user sees:
- C2PA / Content Credentials logo
- "This photo includes Content Credentials"
- Link to download C2PA-embedded photo
- Link to download standalone manifest (.c2pa)
- "Verify with Content Authenticity" link (to verify.contentauthenticity.org)

**And** downloads use presigned URLs that expire in 1 hour

**Prerequisites:** Story 5.2, Story 5.3

**Technical Notes:**
- Presigned S3 URLs for downloads
- Include SHA-256 hash of files for integrity
- Link to external C2PA verify tools for third-party validation

---

### Story 5.7: File Upload Verification Endpoint

As a **backend service**,
I want **to verify uploaded files against our capture database**,
So that **users can verify photos they received externally**.

**Acceptance Criteria:**

**Given** a user has a photo file they want to verify
**When** they call `POST /api/v1/verify-file` with the file
**Then** the backend:
1. Computes SHA-256 hash of uploaded file
2. Searches captures table for matching `target_media_hash`
3. Returns one of three responses:

**Match found:**
```json
{
  "data": {
    "status": "verified",
    "capture_id": "uuid",
    "confidence_level": "high",
    "verification_url": "https://realitycam.app/verify/{uuid}"
  }
}
```

**No match but C2PA manifest present:**
```json
{
  "data": {
    "status": "c2pa_only",
    "manifest_info": { "generator": "...", "assertions": [...] },
    "note": "This file has Content Credentials but was not captured with rial."
  }
}
```

**No match and no manifest:**
```json
{
  "data": {
    "status": "no_record",
    "note": "No provenance record found for this file"
  }
}
```

**Prerequisites:** Story 1.4

**Technical Notes:**
- Hash lookup via `idx_captures_hash` index (O(1))
- Parse C2PA manifest using `c2pa-rs` if hash not found
- Rate limit: 100 verifications/hour/IP
- Max file size: 20MB

---

### Story 5.8: File Upload UI on Verification Page

As a **verification page visitor**,
I want **to upload a file and check if it's in the rial. database**,
So that **I can verify photos I received without a verify link**.

**Acceptance Criteria:**

**Given** the user is on the verification page landing
**When** the user drops a file or clicks to upload
**Then** the UI:
1. Shows file preview and "Checking..." indicator
2. Uploads file to `POST /api/v1/verify-file`
3. Displays result:

**If verified:**
- "✓ Verified! This photo is in our database"
- Shows confidence badge and link to full verification page

**If C2PA only:**
- "This photo has Content Credentials but wasn't captured with rial."
- Shows parsed C2PA info

**If no record:**
- "No provenance record found"
- Explains what this means (not necessarily fake, just not in our system)

**Prerequisites:** Story 5.7, Story 1.6

**Technical Notes:**
- Use react-dropzone or similar for drag-drop
- Client-side hash computation for instant feedback (optional)
- Show upload progress for large files
- Accept JPEG, PNG, HEIC

---

### Story 5.9: Capture History in Mobile App

As a **user**,
I want **to see my capture history in the app**,
So that **I can access verify links for past captures**.

**Acceptance Criteria:**

**Given** the user has captured photos
**When** the user opens the History tab
**Then** they see:
- Chronological list of captures (newest first)
- Each item shows:
  - Thumbnail
  - Confidence badge
  - Capture date/time
  - Status (uploaded, pending, failed)
- Tap to open full capture details

**And** the user can:
- Share verify link from any completed capture
- Delete local capture data (note: server record remains)
- Re-attempt failed uploads

**Prerequisites:** Story 4.10

**Technical Notes:**
- Store history in local SQLite or Zustand persisted store
- Sync with backend for uploaded captures
- Offline-first: show local data immediately, sync when online
- Pagination for users with many captures

---

### Story 5.10: Landing Page and Documentation

As a **visitor**,
I want **to understand what rial. does on the landing page**,
So that **I can decide to download the app or learn about the methodology**.

**Acceptance Criteria:**

**Given** a user visits `https://realitycam.app/`
**When** the page loads
**Then** the user sees:
- **Hero:** "Prove your photos are real" with value prop
- **How it works:** 3-step visual (Capture → Attest → Verify)
- **Evidence types:** Hardware attestation + LiDAR depth explained simply
- **App Store link:** Download for iPhone Pro
- **File verification:** Drop zone for checking received photos
- **Methodology:** Link to transparent documentation

**And** the page is:
- Mobile-responsive
- Fast loading (< 2s LCP)
- SEO optimized

**Prerequisites:** Story 1.6

**Technical Notes:**
- Static generation for landing page (maximum performance)
- App Store badge with deep link
- Reuse file verification component from Story 5.8
- Create `/methodology` page explaining evidence types

---

## Epic 6: Native Swift Implementation

**Goal:** Re-implement the iOS mobile app in pure native Swift/SwiftUI, eliminating React Native and achieving maximum security posture through direct OS framework access.

**User Value:** Captures are processed entirely within compiled native code with no JavaScript bridge crossings for sensitive data. Direct Secure Enclave access, unified RGB+depth capture, and background uploads that survive app termination.

**FRs Covered:** FR1-FR19, FR41-FR46 (native re-implementation of all mobile FRs)

**Parallel Development:** This epic can be developed alongside Epics 1-5. The existing Expo/RN code remains in `apps/mobile/` for feature parity comparison until Story 6.16 validates the native implementation.

**Security Improvements:**
- No JS↔Native bridge crossings for photo bytes, hashes, or keys
- Direct DCAppAttest API (no @expo/app-integrity wrapper)
- Unified ARFrame provides RGB + depth in single instant (no timing gaps)
- CryptoKit hardware-accelerated cryptography
- URLSession background uploads survive app termination
- Certificate pinning at URLSession delegate level

---

### Phase 1: Security Foundation

---

### Story 6.1: Initialize Native iOS Project

As a **developer**,
I want **the Rial iOS project created with proper Swift structure**,
So that **I can implement native security features without React Native overhead**.

**Acceptance Criteria:**

**Given** Xcode 16+ is installed with Swift 5.9+
**When** I create the iOS project following architecture guidelines
**Then** I have:
- Xcode project at `ios/Rial/` with SwiftUI app lifecycle
- Minimum deployment target iOS 15.0
- Bundle identifier configured (e.g., `app.rial.ios`)
- Development team configured for device deployment
- Test targets: RialTests (unit), RialUITests (UI)
- Folder structure: App/, Core/, Features/, Models/, Shaders/, Resources/

**And** the project is configured with:
- Required capabilities: App Attest, Keychain Sharing
- Info.plist with camera, location, photo library usage descriptions
- .gitignore updated for Xcode build artifacts

**Prerequisites:** None (can start parallel to Epics 1-5)

**Technical Notes:**
- File → New → Project → iOS App (SwiftUI, Swift)
- Do NOT use Core Data template (added manually in Story 6.9)
- Create folder groups matching architecture: Core/Attestation/, Core/Capture/, Core/Crypto/, Core/Networking/, Core/Storage/
- Enable "App Attest" capability in Signing & Capabilities

---

### Story 6.2: DCAppAttest Direct Integration

As a **security-conscious user**,
I want **my device to prove it's genuine using Apple's hardware attestation**,
So that **my captures have cryptographic proof of authentic origin**.

**Acceptance Criteria:**

**Given** the app is running on an iPhone with Secure Enclave
**When** the device registers with the backend
**Then**:
- DCAppAttestService.generateKey() creates key in Secure Enclave
- DCAppAttestService.attestKey() produces attestation object
- Attestation key ID is persisted in Keychain
- Backend can verify attestation against Apple's servers

**And** for subsequent captures:
- generateAssertion() creates per-capture proof
- Assertion includes capture hash as clientData
- Assertion generation completes in < 50ms

**And** error handling:
- Unsupported devices get graceful degradation message
- Network failures queue attestation for retry

**Prerequisites:** Story 6.1, Story 6.4

**Technical Notes:**
```swift
let service = DCAppAttestService.shared
guard service.isSupported else { throw AttestationError.unsupported }
let keyId = try await service.generateKey()
let attestation = try await service.attestKey(keyId, clientDataHash: challenge)
// attestKey() once per device, generateAssertion() per capture
```

**FR Coverage:** FR2, FR3, FR10

---

### Story 6.3: CryptoKit Integration

As a **developer**,
I want **native cryptographic operations using CryptoKit**,
So that **all hashing and encryption happens in hardware-accelerated native code**.

**Acceptance Criteria:**

**Given** CryptoService.swift exists in Core/Crypto/
**When** I call cryptographic functions
**Then** the following operations are available:
- `sha256(data: Data) -> String` — hex digest
- `sha256Stream(url: URL) -> String` — streaming for large files
- `encrypt(data: Data, key: SymmetricKey) -> Data` — AES-GCM
- `decrypt(data: Data, key: SymmetricKey) -> Data`
- `generateEncryptionKey() -> SymmetricKey` — 256-bit

**And** Secure Enclave key operations:
- `createSigningKey() -> SecKey`
- `sign(data: Data, key: SecKey) -> Data` — P256 signature

**And** performance:
- SHA-256 of 10MB file completes in < 100ms
- All operations use hardware acceleration on A-series chips

**Prerequisites:** Story 6.1

**Technical Notes:**
```swift
import CryptoKit

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func encrypt(_ data: Data, key: SymmetricKey) throws -> Data {
    try AES.GCM.seal(data, using: key).combined!
}
```

**FR Coverage:** FR11, FR17 (encryption)

---

### Story 6.4: Keychain Services Integration

As a **security-conscious user**,
I want **my cryptographic keys stored in hardware-backed Keychain**,
So that **keys are protected even if the device is compromised**.

**Acceptance Criteria:**

**Given** KeychainService.swift exists in Core/Storage/
**When** I store and retrieve sensitive data
**Then** the following operations work:
- `save(data: Data, key: String)` — stores with hardware protection
- `load(key: String) -> Data?` — retrieves if available
- `delete(key: String)` — removes from Keychain
- `saveSecureEnclaveKey(tag: String) -> SecKey`
- `loadSecureEnclaveKey(tag: String) -> SecKey?`

**And** security configuration:
- Default accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- Keychain access group configured in entitlements
- Secure Enclave keys use `kSecAttrTokenIDSecureEnclave`

**And** error handling:
- Typed `KeychainError` enum for all failure modes
- Unit tests verify save/load/delete cycle

**Prerequisites:** Story 6.1

**Technical Notes:**
```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: key,
    kSecValueData as String: data,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
]
SecItemAdd(query as CFDictionary, nil)
```

**FR Coverage:** FR2, FR17, FR41

---

### Phase 2: Capture Core

---

### Story 6.5: ARKit Unified Capture Session

As a **user**,
I want **to capture photos with synchronized RGB and LiDAR depth**,
So that **depth data is perfectly aligned with the photo for authenticity verification**.

**Acceptance Criteria:**

**Given** ARCaptureSession.swift exists in Core/Capture/
**When** the capture session starts
**Then**:
- ARWorldTrackingConfiguration with `.sceneDepth` frame semantics
- ARSessionDelegate receives ARFrame updates at 30fps+
- Each ARFrame contains both `capturedImage` (RGB) and `sceneDepth` (depth)

**And** the session handles:
- LiDAR availability check before starting
- Interruptions (phone calls, backgrounding) gracefully
- Proper cleanup on deinit (no memory leaks)

**Prerequisites:** Story 6.1

**Technical Notes:**
```swift
let config = ARWorldTrackingConfiguration()
config.frameSemantics.insert(.sceneDepth)
session.run(config)

func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let rgb = frame.capturedImage           // CVPixelBuffer
    let depth = frame.sceneDepth?.depthMap  // CVPixelBuffer (Float32)
    // SAME INSTANT - this is the key security improvement
}
```

**FR Coverage:** FR6, FR7, FR8

---

### Story 6.6: Frame Processing Pipeline

As a **developer**,
I want **ARFrame data converted to uploadable formats**,
So that **captures can be packaged for backend processing**.

**Acceptance Criteria:**

**Given** FrameProcessor.swift exists in Core/Capture/
**When** I process an ARFrame for capture
**Then** I get a CaptureData struct containing:
- JPEG data from `capturedImage` (CVPixelBuffer → CGImage → JPEG)
- Float32 array from `sceneDepth.depthMap` (gzip compressed)
- Camera intrinsics and transform matrix
- EXIF metadata (timestamp, device model, GPS if permitted)

**And** processing is efficient:
- Runs on background queue (not blocking UI)
- No full-frame copies held longer than necessary
- Total processing time < 200ms per capture

**Prerequisites:** Story 6.5

**Technical Notes:**
```swift
func processFrame(_ frame: ARFrame) async throws -> CaptureData {
    let jpeg = try await convertToJPEG(frame.capturedImage)
    let depth = try compressDepth(frame.sceneDepth?.depthMap)
    let metadata = extractMetadata(frame)
    return CaptureData(jpeg: jpeg, depth: depth, metadata: metadata)
}
```

**FR Coverage:** FR7, FR8, FR9, FR12, FR13

---

### Story 6.7: Metal Depth Visualization

As a **user**,
I want **to see a real-time depth overlay while composing my shot**,
So that **I can verify LiDAR is capturing the scene before taking the photo**.

**Acceptance Criteria:**

**Given** DepthVisualizer.swift and Metal shaders exist
**When** depth overlay is enabled
**Then**:
- Depth map renders as color gradient (near=warm, far=cool)
- Rendering at 60fps with < 2ms per frame
- Overlay opacity adjustable (0-100%)
- Toggle on/off without restarting ARSession

**And** the overlay:
- Works in portrait and landscape orientations
- Uses configurable near/far plane distances
- Handles missing depth gracefully (shows nothing, no crash)

**Prerequisites:** Story 6.5

**Technical Notes:**
```metal
// Shaders/DepthVisualization.metal
fragment float4 depthFragment(VertexOut in [[stage_in]],
                               texture2d<float> depthTex [[texture(0)]]) {
    float depth = depthTex.sample(sampler, in.texCoord).r;
    float norm = saturate((depth - near) / (far - near));
    return mix(nearColor, farColor, norm);
}
```

**FR Coverage:** FR6

---

### Story 6.8: Per-Capture Assertion Signing

As a **user**,
I want **each capture signed with my device's Secure Enclave key**,
So that **the backend can verify this specific capture came from my attested device**.

**Acceptance Criteria:**

**Given** CaptureAssertion.swift exists in Core/Attestation/
**When** a capture is taken
**Then**:
- SHA-256 hash computed from JPEG + depth data
- DCAppAttestService.generateAssertion() called with hash as clientData
- Assertion data attached to upload payload
- Assertion generation completes in < 50ms

**And** error handling:
- Assertion failure doesn't block capture (queued for retry)
- Backend logs assertion verification result per capture

**Prerequisites:** Story 6.2, Story 6.3, Story 6.6

**Technical Notes:**
```swift
func createAssertion(for capture: CaptureData) async throws -> Data {
    let hash = CryptoService.sha256(capture.jpeg + capture.depth)
    let hashData = Data(SHA256.hash(data: hash.data(using: .utf8)!))
    return try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hashData)
}
```

**FR Coverage:** FR10

---

### Phase 3: Storage & Upload

---

### Story 6.9: CoreData Capture Queue

As a **user**,
I want **my captures stored locally until upload succeeds**,
So that **I don't lose photos if I'm offline or upload fails**.

**Acceptance Criteria:**

**Given** CoreData model with CaptureEntity
**When** a capture is taken
**Then** it's persisted with:
- id (UUID), jpeg (Binary), depth (Binary), metadata (Transformable)
- status: pending | uploading | uploaded | failed
- createdAt, attemptCount, lastAttemptAt
- assertion (Binary, nullable)

**And** storage management:
- Automatic cleanup of uploaded captures after 7 days
- Storage quota warning at 500MB
- Prevent new captures at 1GB quota
- Migration support for future schema changes

**Prerequisites:** Story 6.1

**Technical Notes:**
- Use NSPersistentContainer with automatic lightweight migration
- Binary data with "Allows External Storage" for large files
- @FetchRequest in SwiftUI for reactive updates
- Background context for save operations

**FR Coverage:** FR17, FR18, FR19

---

### Story 6.10: iOS Data Protection Encryption

As a **security-conscious user**,
I want **my queued captures encrypted when my device is locked**,
So that **sensitive photos are protected if my device is stolen**.

**Acceptance Criteria:**

**Given** captures are stored in CoreData
**When** the device is locked
**Then**:
- CoreData store uses `NSFileProtectionCompleteUntilFirstUserAuthentication`
- Capture data additionally encrypted with AES-GCM before storage
- Encryption key stored in Keychain (hardware-backed)

**And** the encryption:
- Decryption happens lazily on access
- Data remains encrypted in device backups
- Unit tests verify encryption/decryption round-trip

**Prerequisites:** Story 6.3, Story 6.4, Story 6.9

**Technical Notes:**
```swift
let desc = NSPersistentStoreDescription(url: storeURL)
desc.setOption(
    FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
    forKey: NSPersistentStoreFileProtectionKey
)
```

**FR Coverage:** FR17

---

### Story 6.11: URLSession Background Uploads

As a **user**,
I want **uploads to continue even if I close the app**,
So that **my captures are uploaded reliably without keeping the app open**.

**Acceptance Criteria:**

**Given** UploadService.swift uses background URLSession
**When** I capture a photo and close the app
**Then**:
- Upload continues in background
- App is woken on completion to update status
- Incomplete uploads resume on app relaunch

**And** the upload:
- Uses multipart form-data (photo + depth + metadata + assertion)
- Progress tracked via URLSessionTaskDelegate
- Background completion handler signals iOS properly

**Prerequisites:** Story 6.1, Story 6.9

**Technical Notes:**
```swift
let config = URLSessionConfiguration.background(withIdentifier: "app.rial.upload")
config.isDiscretionary = false
config.sessionSendsLaunchEvents = true

// AppDelegate
func application(_ app: UIApplication,
                 handleEventsForBackgroundURLSession id: String,
                 completionHandler: @escaping () -> Void) {
    uploadService.backgroundCompletionHandler = completionHandler
}
```

**FR Coverage:** FR14, FR16, FR18

---

### Story 6.12: Certificate Pinning & Retry Logic

As a **security-conscious user**,
I want **API connections verified against known certificates**,
So that **man-in-the-middle attacks cannot intercept my uploads**.

**Acceptance Criteria:**

**Given** URLSessionDelegate implements certificate validation
**When** connecting to the backend
**Then**:
- Server certificate's public key verified against pinned key
- Pinning failure = connection rejected, capture stays queued
- TLS 1.3 minimum enforced

**And** retry logic:
- Exponential backoff: 1s, 2s, 4s, 8s, 16s
- Max 5 attempts before marking as failed
- Network reachability change triggers retry of queued items
- User can manually retry failed uploads

**Prerequisites:** Story 6.11

**Technical Notes:**
```swift
func urlSession(_ session: URLSession,
                didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard let trust = challenge.protectionSpace.serverTrust,
          let cert = SecTrustGetCertificateAtIndex(trust, 0),
          let serverKey = SecCertificateCopyKey(cert) else {
        completionHandler(.cancelAuthenticationChallenge, nil)
        return
    }
    // Compare serverKey against pinned public key
}
```

**FR Coverage:** FR15, FR16

---

### Phase 4: User Experience

---

### Story 6.13: SwiftUI Capture Screen

As a **user**,
I want **a clean camera interface with depth preview**,
So that **I can easily capture attested photos**.

**Acceptance Criteria:**

**Given** CaptureView.swift displays the camera
**When** I open the app
**Then** I see:
- Full-screen ARView with live camera preview
- Depth overlay toggle button (SF Symbol: eye/eye.slash)
- Large capture button with haptic feedback
- Flash toggle (if available)
- Flip camera disabled (back only for LiDAR)

**And** capture flow:
- Capture button triggers flash animation
- Preview shows captured photo with "Use" / "Retake"
- "Use" saves to queue, navigates to history
- Handles camera/location permission requests

**Prerequisites:** Story 6.5, Story 6.6, Story 6.7

**Technical Notes:**
- UIViewRepresentable to wrap ARView in SwiftUI
- @StateObject for ARCaptureSession
- NavigationStack for flow management
- SF Symbols for consistent iOS appearance

**FR Coverage:** FR6, FR7

---

### Story 6.14: Capture History View

As a **user**,
I want **to see my capture history and upload status**,
So that **I can track what's been verified and share links**.

**Acceptance Criteria:**

**Given** HistoryView.swift displays captures
**When** I navigate to history
**Then** I see:
- Grid of capture thumbnails (LazyVGrid, 3 columns)
- Each item: thumbnail, status badge, date
- Status badges: ✓ Uploaded (green), ↑ Uploading (blue), ⏳ Pending (gray), ✗ Failed (red)
- Sorted by date (newest first)
- Empty state: "No captures yet" with capture CTA

**And** interactions:
- Tap → navigate to detail view
- Pull-to-refresh → retry failed uploads
- Efficient thumbnail caching

**Prerequisites:** Story 6.9, Story 6.11

**Technical Notes:**
- @FetchRequest with NSSortDescriptor for reactive updates
- Thumbnails generated once, cached alongside capture
- NavigationLink to ResultDetailView

**FR Coverage:** FR19

---

### Story 6.15: Result Detail View

As a **user**,
I want **to see the verification result and share the verify link**,
So that **I can prove my photo's authenticity to others**.

**Acceptance Criteria:**

**Given** ResultDetailView.swift shows a capture
**When** I tap a capture in history
**Then** I see:
- Full photo with pinch-to-zoom
- Confidence badge (HIGH/MEDIUM/LOW) if uploaded
- Evidence summary (attestation ✓, depth ✓, timestamp ✓)
- Verify link: `https://rial.app/verify/{id}`
- Copy link button
- Share button (iOS share sheet with photo + link)

**And** for pending/failed:
- Upload status indicator
- Retry button for failed uploads
- "Uploading..." progress for in-flight

**Prerequisites:** Story 6.14, Story 6.11

**Technical Notes:**
```swift
ShareLink(
    item: verifyURL,
    preview: SharePreview("Verified photo from rial.", image: thumbnail)
)
```

**FR Coverage:** FR19, FR31

---

### Story 6.16: Feature Parity Validation

As a **developer**,
I want **to verify the native app matches Expo app functionality**,
So that **we can confidently deprecate the React Native version**.

**Acceptance Criteria:**

**Given** both apps installed on same test device
**When** performing side-by-side testing
**Then** the following pass:
- [ ] Device registration produces valid attestation (both apps)
- [ ] Capture produces valid JPEG + depth (hashes match format)
- [ ] Backend accepts uploads from both apps
- [ ] Assertion verification passes for both
- [ ] History displays same server-side captures
- [ ] Share links work identically

**And** performance comparison documented:
- Capture latency (native should be faster)
- Memory usage (native should be lower)
- Upload reliability (native has background support)
- Battery impact

**And** automation:
- XCUITest covers critical flows
- Backend logs client version per upload

**Prerequisites:** Stories 6.1-6.15

**Technical Notes:**
- Same Apple ID / device for both apps
- Document intentional differences (native improvements)
- Create migration guide for Expo → native transition
- After validation, Expo code can be archived/removed

**FR Coverage:** All mobile FRs (validation)

---

## FR Coverage Matrix

| FR | Description | Epic | Story | Native (Epic 6) |
|----|-------------|------|-------|-----------------|
| FR1 | Detect iPhone Pro with LiDAR | 2 | 2.1 | 6.5 |
| FR2 | Generate Secure Enclave keys | 2 | 2.2 | 6.2, 6.4 |
| FR3 | Request DCAppAttest attestation | 2 | 2.3 | 6.2 |
| FR4 | Backend verifies attestation | 2 | 2.5 | — |
| FR5 | Assign attestation level | 2 | 2.5 | — |
| FR6 | Camera view with depth overlay | 3 | 3.2, 3.3 | 6.5, 6.7, 6.13 |
| FR7 | Capture photo | 3 | 3.2 | 6.5, 6.6, 6.13 |
| FR8 | Capture LiDAR depth map | 3 | 3.1, 3.4 | 6.5, 6.6 |
| FR9 | Record GPS coordinates | 3 | 3.5 | 6.6 |
| FR10 | Capture attestation signature | 3 | 3.6 | 6.8 |
| FR11 | Compute SHA-256 hash | 3 | 3.7 | 6.3 |
| FR12 | Compress depth map | 3 | 3.7 | 6.6 |
| FR13 | Construct capture request | 3 | 3.7 | 6.6 |
| FR14 | Upload via multipart POST | 4 | 4.1 | 6.11 |
| FR15 | TLS 1.3 for API | 4 | 4.1, 4.2 | 6.12 |
| FR16 | Retry with exponential backoff | 4 | 4.2 | 6.12 |
| FR17 | Encrypted offline storage | 4 | 4.3 | 6.3, 6.9, 6.10 |
| FR18 | Auto-upload when online | 4 | 4.2, 4.3 | 6.11 |
| FR19 | Pending upload status | 4 | 4.2 | 6.9, 6.14 |
| FR20 | Verify attestation | 4 | 4.4 | — |
| FR21 | Depth analysis | 4 | 4.5 | — |
| FR22 | Determine real scene | 4 | 4.5 | — |
| FR23 | Validate EXIF timestamp | 4 | 4.6 | — |
| FR24 | Validate device model | 4 | 4.6 | — |
| FR25 | Generate evidence package | 4 | 4.8 | — |
| FR26 | Calculate confidence level | 4 | 4.9 | — |
| FR27 | Create C2PA manifest | 5 | 5.1 | — |
| FR28 | Sign C2PA manifest | 5 | 5.1 | — |
| FR29 | Embed C2PA manifest | 5 | 5.2 | — |
| FR30 | Store both versions | 5 | 5.2 | — |
| FR31 | Shareable verify URL | 5 | 5.3 | 6.15 |
| FR32 | Confidence summary | 5 | 5.3 | — |
| FR33 | Depth visualization | 5 | 5.4 | — |
| FR34 | Expandable evidence panel | 5 | 5.5 | — |
| FR35 | Per-check status display | 5 | 5.5 | — |
| FR36 | File upload verification | 5 | 5.7, 5.8 | — |
| FR37 | Hash lookup | 5 | 5.7 | — |
| FR38 | Match found display | 5 | 5.8 | — |
| FR39 | C2PA-only display | 5 | 5.8 | — |
| FR40 | No record display | 5 | 5.8 | — |
| FR41 | Device pseudonymous ID | 2 | 2.5 | 6.4 |
| FR42 | Anonymous capture | 2 | 2.6 | 6.2 |
| FR43 | Device registration storage | 2 | 2.5 | 6.4 |
| FR44 | Coarse GPS in public view | 4 | 4.7 | 6.6 |
| FR45 | Location opt-out | 3, 4 | 3.5, 4.7 | 6.6 |
| FR46 | Depth map not downloadable | 4, 5 | 4.5, 5.4 | — |
| FR47 | Video with LiDAR depth at 10fps | 7 | 7.1, 7.2 | 7.1, 7.2 |
| FR48 | Real-time edge depth overlay | 7 | 7.3 | 7.3 |
| FR49 | Frame hash chain | 7 | 7.4 | 7.4 |
| FR50 | Video attestation with checkpoints | 7 | 7.5 | 7.5 |
| FR51 | Video metadata collection | 7 | 7.6 | 7.6 |
| FR52 | Hash chain verification | 7 | 7.10 | — |
| FR53 | Video depth analysis | 7 | 7.9 | — |
| FR54 | C2PA video manifest | 7 | 7.12 | — |
| FR55 | Video verification page | 7 | 7.13 | — |

**Note:** Epic 6 "Native" column shows Swift story alternatives for mobile-side FRs. Backend/web FRs (FR4-5, FR20-30, FR32-40, FR52-55) have no native equivalent as they remain Rust/Next.js. Epic 7 is entirely native Swift for mobile functionality.

---

## Epic 7: Video Capture with LiDAR Depth

**Goal:** Extend the photo capture system to record authenticated video with continuous frame-by-frame LiDAR depth data, enabling verification of dynamic real-world events.

**User Value:** Users can capture short video clips (up to 15 seconds) with the same hardware attestation and depth verification as photos, proving they recorded a real 3D scene unfolding over time. Ideal for documenting incidents, proving chain of events, and detecting manipulation that single-frame analysis might miss.

**FRs Covered:** FR47-FR55 (Video Capture)

**Technical Foundation:**
- Builds on Epic 6 native Swift implementation (ARKit unified capture)
- Reuses attestation infrastructure from Epic 2
- Extends evidence processing from Epic 4
- Integrates with C2PA video manifest support from Epic 5

---

### Story 7.1: ARKit Video Recording Session

As a **user**,
I want **to record video with synchronized RGB and depth streams**,
So that **every frame has corresponding LiDAR depth data for verification**.

**Acceptance Criteria:**

**Given** the user is on the capture screen with video mode selected
**When** the user presses and holds the record button
**Then**:
- ARSession records at 30fps with `.sceneDepth` frame semantics
- Each ARFrame contains both `capturedImage` (RGB) and `sceneDepth` (depth)
- Recording continues until button release or 15-second limit
- Visual timer shows remaining recording time
- Haptic feedback on start and stop

**And** the recording:
- Stops automatically at 15-second maximum
- Can be stopped early by user
- Shows "Recording..." indicator with elapsed time

**Prerequisites:** Story 6.5 (ARKit Unified Capture Session)

**Technical Notes:**
- Use AVAssetWriter for video encoding (H.264/HEVC)
- ARSession provides synchronized RGB+depth per frame
- Store depth keyframes at 10fps (every 3rd ARFrame)
- Video resolution: 1920x1080 or 3840x2160 based on device capability

---

### Story 7.2: Depth Keyframe Extraction (10fps)

As a **developer**,
I want **to capture depth data at 10fps during video recording**,
So that **file sizes are manageable while maintaining forensic value**.

**Acceptance Criteria:**

**Given** video recording is in progress at 30fps
**When** depth keyframes are extracted
**Then**:
- Depth captured every 3rd frame (10fps from 30fps video)
- 15 seconds × 10fps = 150 depth frames maximum
- Each depth frame stored as Float32 array (256×192 pixels)
- Depth frames indexed by video timestamp

**And** the storage format:
- Depth frames stored as binary blob (gzip compressed)
- Frame index maps timestamp → offset in blob
- Total depth size: ~15MB uncompressed, ~10MB compressed (typical)

**Prerequisites:** Story 7.1

**Technical Notes:**
```swift
// Extract depth at 10fps
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    frameCount += 1
    if frameCount % 3 == 0 { // Every 3rd frame = 10fps
        guard let depth = frame.sceneDepth?.depthMap else { return }
        depthBuffer.append(extractDepthData(depth), timestamp: frame.timestamp)
    }
}
```

---

### Story 7.3: Real-time Edge Depth Overlay

As a **user**,
I want **to see a real-time depth edge overlay while recording**,
So that **I can verify LiDAR is capturing the scene without obscuring my view**.

**Acceptance Criteria:**

**Given** video recording mode is active
**When** the depth overlay toggle is enabled
**Then**:
- Edge-detection overlay shows depth boundaries (not full colormap)
- Overlay renders at 30fps with < 3ms per frame
- Edges appear as white/colored lines on transparent background
- Toggle button shows overlay state (eye/eye.slash SF Symbol)

**And** performance:
- CPU impact < 15% additional
- GPU impact < 25% additional
- No visible frame drops in recorded video
- Overlay does NOT appear in recorded video (preview only)

**Prerequisites:** Story 6.7 (Metal Depth Visualization)

**Technical Notes:**
- Sobel or Canny edge detection on depth buffer
- Render edges only (much faster than full colormap)
- Metal shader for real-time processing
- Separate preview layer from recording pipeline

---

### Story 7.4: Frame Hash Chain

As a **security-conscious user**,
I want **each video frame cryptographically chained to previous frames**,
So that **frames cannot be reordered, removed, or inserted without detection**.

**Acceptance Criteria:**

**Given** video recording is in progress
**When** each frame is captured
**Then** hash chain is computed:
```
H1 = SHA256(frame1 + depth1 + timestamp1)
H2 = SHA256(frame2 + depth2 + timestamp2 + H1)
H3 = SHA256(frame3 + depth3 + timestamp3 + H2)
...
Hn = SHA256(frameN + ... + Hn-1)
```

**And** the hash chain:
- Uses video frame pixels + depth data + timestamp
- Chains every frame (30fps), not just depth keyframes
- Final hash (Hn) is signed by attestation
- Intermediate hashes stored every 5 seconds (checkpoints)

**Prerequisites:** Story 6.3 (CryptoKit Integration)

**Technical Notes:**
- CryptoKit SHA256 for performance
- Hash on background queue to avoid blocking
- Store checkpoint hashes: [H150, H300, H450] for 5s, 10s, 15s
- If interrupted, attest last checkpoint

---

### Story 7.5: Video Attestation with Checkpoints

As a **user**,
I want **my video attested even if recording is interrupted**,
So that **partial evidence is still verifiable**.

**Acceptance Criteria:**

**Given** video recording is in progress
**When** recording completes (normal or interrupted)
**Then**:
- On normal completion: Final hash signed with DCAppAttest assertion
- On interruption: Last checkpoint hash signed instead
- Assertion includes: video duration, frame count, checkpoint index

**And** checkpoint attestation:
- Checkpoints saved every 5 seconds
- Each checkpoint contains: hash, timestamp, frame count
- Interrupted at 12 seconds → attestation covers first 10 seconds
- Verification shows "Verified: 10s of 12s recorded"

**Prerequisites:** Story 7.4, Story 6.2 (DCAppAttest)

**Technical Notes:**
```swift
struct VideoAttestation {
    let finalHash: Data           // Hash of final or checkpoint
    let assertion: Data           // DCAppAttest signature
    let durationMs: Int64         // Attested duration
    let frameCount: Int           // Attested frame count
    let isPartial: Bool           // True if interrupted
    let checkpointIndex: Int?     // Which checkpoint (0=5s, 1=10s, 2=15s)
}
```

---

### Story 7.6: Video Metadata Collection

As a **user**,
I want **the same metadata captured for video as for photos**,
So that **location, device info, and timestamps are part of the evidence**.

**Acceptance Criteria:**

**Given** video recording starts
**When** metadata is collected
**Then** the following are captured:
- GPS coordinates at recording start (if permitted)
- Device model and iOS version
- Recording start and end timestamps (UTC)
- Video resolution and codec
- Depth frame count and resolution
- Attestation level (secure_enclave/unverified)

**And** the metadata structure:
```json
{
  "type": "video",
  "started_at": "ISO timestamp",
  "ended_at": "ISO timestamp",
  "duration_ms": 12500,
  "frame_count": 375,
  "depth_keyframe_count": 125,
  "resolution": { "width": 1920, "height": 1080 },
  "codec": "hevc",
  "device_model": "iPhone 15 Pro",
  "location": { "lat": 37.7749, "lng": -122.4194 },
  "attestation_level": "secure_enclave",
  "hash_chain_final": "base64...",
  "assertion": "base64..."
}
```

**Prerequisites:** Story 7.1, Story 6.6 (Frame Processing)

---

### Story 7.7: Video Local Processing Pipeline

As a **developer**,
I want **video captures processed for upload**,
So that **all components are packaged correctly for backend verification**.

**Acceptance Criteria:**

**Given** video recording has completed
**When** local processing runs
**Then** the following are prepared:
1. Video file (H.264/HEVC, ~10-30MB for 15s 1080p)
2. Depth data blob (gzip compressed, ~10MB)
3. Hash chain data (all intermediate hashes)
4. Checkpoint hashes (for partial verification)
5. Metadata JSON with attestation
6. Thumbnail image (first frame)

**And** processing completes in < 5 seconds

**Prerequisites:** Story 7.4, Story 7.5, Story 7.6

**Technical Notes:**
- Video already encoded during recording (AVAssetWriter)
- Depth compression on background thread
- Store in CoreData with same queue as photos (Story 6.9)
- Total upload size: ~30-45MB for 15s video

---

### Story 7.8: Video Upload Endpoint

As a **mobile app**,
I want **to upload video captures with depth and attestation data**,
So that **the backend can verify and process them**.

**Acceptance Criteria:**

**Given** a processed video capture is ready
**When** the app calls `POST /api/v1/captures/video` with multipart/form-data:
- Part `video`: MP4/MOV binary (~20MB)
- Part `depth_data`: gzipped depth keyframes (~10MB)
- Part `hash_chain`: checkpoint hashes
- Part `metadata`: JSON with attestation

**Then** the backend:
1. Validates device signature headers
2. Verifies device exists and is registered
3. Stores video and depth data to S3
4. Creates pending capture record with type="video"
5. Returns capture ID and "processing" status

**And** response format:
```json
{
  "data": {
    "capture_id": "uuid",
    "type": "video",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/{uuid}"
  }
}
```

**Prerequisites:** Story 4.1 (extended for video), Story 7.7

**Technical Notes:**
- Support chunked upload for larger files
- URLSession background upload (survives app termination)
- Rate limiting: 5 videos/hour/device

---

### Story 7.9: Video Depth Analysis Service

As a **backend service**,
I want **to analyze video depth data across multiple frames**,
So that **I can detect manipulation attempts that single-frame analysis would miss**.

**Acceptance Criteria:**

**Given** a video capture with depth keyframes
**When** depth analysis runs
**Then** the service computes:
```rust
VideoDepthAnalysis {
    // Per-frame metrics (sampled)
    frame_analyses: Vec<FrameDepthAnalysis>,

    // Temporal metrics
    depth_consistency: f32,    // Depth values consistent across frames
    motion_coherence: f32,     // Depth changes match RGB motion
    scene_stability: f32,      // No impossible depth jumps

    // Aggregate
    is_likely_real_scene: bool,
    suspicious_frames: Vec<FrameIndex>,
}
```

**And** "is_likely_real_scene" is true when:
- `depth_consistency > 0.8` (depth doesn't randomly change)
- `motion_coherence > 0.7` (depth motion matches visual motion)
- `scene_stability > 0.9` (no teleporting objects)
- At least 80% of sampled frames pass individual depth analysis

**Prerequisites:** Story 4.5 (extended for video)

**Technical Notes:**
- Analyze every 10th depth keyframe (1 per second)
- Compare depth deltas to optical flow
- Flag frames with inconsistent depth motion

---

### Story 7.10: Video Hash Chain Verification

As a **backend service**,
I want **to verify the video hash chain**,
So that **I can confirm no frames were added, removed, or reordered**.

**Acceptance Criteria:**

**Given** a video with hash chain data
**When** hash chain verification runs
**Then**:
- Recompute hash chain from video frames + depth data
- Compare to submitted chain
- Verify final/checkpoint hash matches attested hash
- Report any discrepancies

**And** verification result:
```rust
HashChainVerification {
    status: Pass | Fail | Partial,
    verified_frames: u32,
    total_frames: u32,
    chain_intact: bool,
    attestation_valid: bool,

    // For partial attestation
    partial_reason: Option<String>,  // "Recording interrupted at 12s"
    verified_duration_ms: u32,
}
```

**Prerequisites:** Story 7.8

**Technical Notes:**
- Stream video frames for recomputation (memory efficient)
- Checkpoint verification allows early success
- Log any chain breaks for forensic analysis

---

### Story 7.11: Video Evidence Package

As a **backend service**,
I want **to assemble video evidence into a unified package**,
So that **verification page has complete evidence to display**.

**Acceptance Criteria:**

**Given** all video evidence checks have completed
**When** evidence package is assembled
**Then** the package contains:
```json
{
  "type": "video",
  "duration_ms": 12500,
  "frame_count": 375,

  "hardware_attestation": {
    "status": "pass|fail|unavailable",
    "level": "secure_enclave|unverified",
    "device_model": "iPhone 15 Pro"
  },

  "hash_chain": {
    "status": "pass|fail|partial",
    "verified_frames": 375,
    "chain_intact": true
  },

  "depth_analysis": {
    "status": "pass|fail",
    "depth_consistency": 0.92,
    "motion_coherence": 0.85,
    "scene_stability": 0.97,
    "is_likely_real_scene": true,
    "suspicious_frames": []
  },

  "metadata": {
    "timestamp_valid": true,
    "model_verified": true,
    "location_available": true,
    "location_coarse": "San Francisco, CA"
  },

  "partial_attestation": {
    "is_partial": false,
    "verified_duration_ms": 12500
  }
}
```

**Prerequisites:** Story 7.9, Story 7.10, Story 4.8

---

### Story 7.12: C2PA Video Manifest Generation

As a **backend service**,
I want **to create C2PA manifests for video files**,
So that **videos are interoperable with the Content Credentials ecosystem**.

**Acceptance Criteria:**

**Given** a video capture with completed evidence package
**When** C2PA manifest generation runs
**Then** the manifest contains:
- **Claim Generator:** "rial./1.0.0"
- **Actions:** "c2pa.created" with start/end timestamps
- **Assertions:**
  - Hardware attestation level
  - Hash chain verification result
  - Video depth analysis summary
  - Duration and frame count
  - Confidence level
- **Signature:** Ed25519, certificate chain embedded

**And** manifest is valid per C2PA spec 2.0 for video
**And** manifest embedded in MP4 per ISO Base Media File Format

**Prerequisites:** Story 5.1 (extended for video)

**Technical Notes:**
- c2pa-rs supports video (MP4) embedding
- Use XMP metadata for video-specific assertions
- Store both original and C2PA-embedded versions

---

### Story 7.13: Video Verification Page

As a **verification page visitor**,
I want **to verify video captures with playback and evidence display**,
So that **I can understand the trust level of recorded events**.

**Acceptance Criteria:**

**Given** a user opens a video verification URL
**When** the page loads
**Then** the user sees:
- Video player with playback controls
- Confidence badge overlay (HIGH/MEDIUM/LOW/SUSPICIOUS)
- Duration and "Verified X of Y seconds" (if partial)
- "Recorded Nov 26, 2025 at 10:30 AM"
- Location (city-level if available)

**And** the evidence panel shows:
- Hash chain status: "All 375 frames verified" / "Chain break at frame 200"
- Depth analysis: temporal metrics + frame-by-frame viewer
- Attestation status
- Partial attestation explanation (if applicable)

**And** depth visualization:
- Toggle to overlay depth on video during playback
- Scrubber to view depth at any timestamp

**Prerequisites:** Story 5.3 (extended for video)

**Technical Notes:**
- Use native HTML5 video player with custom controls
- Pre-render depth previews at 1fps for scrubber thumbnails
- Lazy-load depth overlay for performance

---

### Story 7.14: Video Capture UI

As a **user**,
I want **a clear interface to switch between photo and video modes**,
So that **I can choose the right capture type for my needs**.

**Acceptance Criteria:**

**Given** the capture screen is displayed
**When** the user views mode options
**Then**:
- Toggle or segmented control shows Photo | Video
- Video mode shows record button (hold to record)
- Visual timer shows "0:00 / 0:15" with fill animation
- Depth overlay toggle available in both modes

**And** recording interaction:
- Press and hold record button to start
- Release to stop (or auto-stop at 15s)
- Haptic feedback on start, 5s warning, and stop
- Cannot switch modes while recording

**And** preview after recording:
- Video playback with play/pause
- Depth overlay toggle
- "Use" / "Retake" / "Photo Mode" buttons

**Prerequisites:** Story 6.13 (SwiftUI Capture Screen)

**Technical Notes:**
- Shared ARSession between photo and video modes
- Mode switch pauses/resumes depth capture
- Recording state in captureStore

---

## Video Capture - Functional Requirements

| FR | Description | Story |
|----|-------------|-------|
| FR47 | App records video up to 15 seconds with LiDAR depth at 10fps | 7.1, 7.2 |
| FR48 | App displays real-time edge-detection depth overlay during recording | 7.3 |
| FR49 | App computes frame hash chain (each frame hashes with previous) | 7.4 |
| FR50 | App generates attestation for complete or interrupted videos | 7.5 |
| FR51 | App collects same metadata for video as photos | 7.6 |
| FR52 | Backend verifies video hash chain integrity | 7.10 |
| FR53 | Backend analyzes depth consistency across video frames | 7.9 |
| FR54 | Backend generates C2PA manifest for video files | 7.12 |
| FR55 | Verification page displays video with playback and evidence | 7.13 |

---

## Epic 8: Privacy-First Capture Mode

**Goal:** Enable users to capture attested photos/videos without uploading raw media, using client-side depth analysis and granular metadata controls.

**User Value:** Privacy-conscious users (journalists, lawyers, HR, medical) can prove capture authenticity without any server touching their sensitive media.

**FRs Covered:** FR56-FR62

**Technical Approach:**
- Client-side depth analysis (same algorithm as server)
- DCAppAttest signs hash + analysis results
- Backend stores evidence package without raw media
- Granular metadata toggles per capture

### Story 8.1: Client-Side Depth Analysis Service

As a **privacy-conscious user**,
I want **my device to analyze depth data locally**,
So that **I can prove my capture is a real 3D scene without uploading the depth map**.

**Acceptance Criteria:**

**Given** a photo or video capture with depth data
**When** Privacy Mode is enabled
**Then** the app:
- Computes depth variance (std dev of depth values)
- Counts depth layers (distinct depth planes)
- Calculates edge coherence (correlation with RGB edges)
- Determines `is_likely_real_scene` using same thresholds as server

**And** analysis completes in < 500ms

**And** results are identical to server-side computation (deterministic algorithm)

**Prerequisites:** Story 6.6 (Frame Processing Pipeline)

**Technical Notes:**
- Port depth analysis algorithm from Rust to Swift
- Use Metal for GPU-accelerated computation if needed
- Thresholds: variance > 0.5, layers >= 3, coherence > 0.7
- Store analysis in `DepthAnalysisResult` struct

---

### Story 8.2: Privacy Mode Settings UI

As a **user**,
I want **to toggle Privacy Mode in capture settings**,
So that **I can choose between full upload and hash-only capture**.

**Acceptance Criteria:**

**Given** the Settings screen is displayed
**When** the user views privacy options
**Then** they see:
- Privacy Mode toggle (off by default)
- Explanation: "When enabled, only a hash of your capture is uploaded. The actual photo/video never leaves your device."

**And** when Privacy Mode is enabled:
- Shows granular metadata controls
- Location: None / Coarse (city) / Precise
- Timestamp: None / Day only / Exact
- Device: None / Model only / Full

**And** settings persist across app launches (stored in UserDefaults)

**Prerequisites:** Story 6.13 (SwiftUI Capture Screen)

**Technical Notes:**
- Use `@AppStorage` for persistence
- Group under "Privacy & Security" section
- Include "Learn More" link explaining trust model

---

### Story 8.3: Hash-Only Capture Payload

As a **privacy-conscious user**,
I want **my capture to upload only hash and evidence**,
So that **the server never receives my raw media**.

**Acceptance Criteria:**

**Given** Privacy Mode is enabled
**When** user captures and uploads
**Then** the payload contains only:
- `media_hash`: SHA-256 of photo/video bytes
- `depth_analysis`: Client-computed analysis results
- `metadata`: Per user settings (location, timestamp, device)
- `metadata_flags`: What was included/excluded
- `assertion`: DCAppAttest signature over entire payload

**And** raw photo/video bytes are NOT included

**And** upload size is < 10KB (vs ~5MB for full capture)

**And** full media remains in local storage (user's device only)

**Prerequisites:** Story 8.1, Story 8.2

**Technical Notes:**
- Create `HashOnlyCapturePayload` struct
- Sign payload hash with DCAppAttest assertion
- Include `capture_mode: "hash_only"` in request

---

### Story 8.4: Backend Hash-Only Capture Endpoint

As a **backend service**,
I want **to accept hash-only captures with pre-computed analysis**,
So that **I can generate evidence without raw media**.

**Acceptance Criteria:**

**Given** a POST to `/api/v1/captures` with `mode: "hash_only"`
**When** the request is processed
**Then** backend:
- Validates DCAppAttest assertion covers the payload
- Extracts `media_hash`, `depth_analysis`, `metadata`
- Stores capture with `media_stored: false`
- Generates verification URL

**And** if assertion verification fails:
- Returns 401 with error: "Attestation signature invalid"

**And** no media files are stored in S3

**Prerequisites:** Story 4.1 (Capture Upload Endpoint)

**Technical Notes:**
- Add `mode` field to capture request schema
- Verify assertion signature matches payload hash
- Store `capture_mode` and `media_stored` in DB

---

### Story 8.5: Hash-Only Evidence Package

As a **backend service**,
I want **to generate evidence for hash-only captures**,
So that **verification works without stored media**.

**Acceptance Criteria:**

**Given** a hash-only capture is stored
**When** evidence package is assembled
**Then** it includes:
- Hardware attestation: status from assertion verification
- Depth analysis: values from client payload (marked "computed on device")
- Metadata checks: per provided metadata
- Confidence level: calculated per standard algorithm

**And** evidence notes:
- "Depth analysis performed on attested device"
- "Original media not stored on server"

**Prerequisites:** Story 4.8 (Evidence Package Assembly)

**Technical Notes:**
- Add `analysis_source: "device" | "server"` to evidence
- Confidence calculation unchanged (trusts attested device)
- Add `media_stored: false` flag to response

---

### Story 8.6: Verification Page Hash-Only Display

As a **verifier**,
I want **to see clear indication when viewing hash-only capture**,
So that **I understand the media is not stored but hash is verified**.

**Acceptance Criteria:**

**Given** a verification URL for a hash-only capture
**When** the page loads
**Then** the user sees:
- "Hash Verified" badge (instead of media preview)
- Confidence level badge (HIGH/MEDIUM/LOW/SUSPICIOUS)
- Message: "Original media not stored on server"
- Message: "Authenticity verified via device attestation"
- Capture timestamp and location (per metadata flags)

**And** evidence panel shows:
- All check statuses with source indicator
- "Depth analysis: Pass (computed on device)"
- Hardware attestation status

**And** no "Download" or "View Full Size" options (no media to view)

**Prerequisites:** Story 5.4 (Verification Page)

**Technical Notes:**
- Check `media_stored` field from API
- Use different layout for hash-only vs full captures
- Emphasize trust model explanation

---

### Story 8.7: File Verification for Hash-Only

As a **user with the original file**,
I want **to verify my hash-only capture by uploading the file**,
So that **I can prove this file matches the registered hash**.

**Acceptance Criteria:**

**Given** a hash-only capture exists
**When** user uploads the original file to verification page
**Then** system:
- Computes SHA-256 of uploaded file
- Compares to stored `media_hash`
- If match: displays full evidence with "File matches registered hash"
- If no match: displays "This file does not match any registered capture"

**And** uploaded file is not stored (hashed in memory, discarded)

**Prerequisites:** Story 5.6 (File Upload Verification)

**Technical Notes:**
- Reuse existing file verification flow
- Add messaging specific to hash-only mode
- Consider: show media preview only during verification session

---

### Story 8.8: Video Privacy Mode Support

As a **privacy-conscious user**,
I want **Privacy Mode to work for video captures**,
So that **I can hash-only verify videos too**.

**Acceptance Criteria:**

**Given** Privacy Mode is enabled for video capture
**When** user records and uploads video
**Then**:
- Video hash chain is computed locally
- Temporal depth analysis is performed on-device
- Upload contains: `hash_chain` + `depth_analysis` + `assertion`
- No video bytes uploaded

**And** verification shows:
- "Video Hash Verified"
- Frame count and duration
- Depth analysis summary (temporal)
- Hash chain integrity status

**Prerequisites:** Story 7.7 (Video Local Processing), Story 8.3

**Technical Notes:**
- Reuse video hash chain from Epic 7
- Add temporal depth analysis to client
- Same verification UX as photo hash-only

---

## Privacy-First Capture - Functional Requirements

| FR | Description | Story |
|----|-------------|-------|
| FR56 | App provides "Privacy Mode" toggle in capture settings | 8.2 |
| FR57 | In Privacy Mode, app performs depth analysis locally | 8.1 |
| FR58 | In Privacy Mode, app uploads only hash + analysis + attestation | 8.3 |
| FR59 | Backend accepts pre-computed depth analysis signed by attested device | 8.4 |
| FR60 | Backend stores hash + evidence without raw media | 8.4, 8.5 |
| FR61 | Verification page displays "Hash Verified" messaging | 8.6 |
| FR62 | Users can configure per-capture metadata granularity | 8.2 |

---

## Summary

**Total: 8 Epics, 79 Stories**

| Epic | Stories | FRs Covered |
|------|---------|-------------|
| Epic 1: Foundation & Project Setup | 6 | Infrastructure |
| Epic 2: Device Registration & Attestation | 7 | FR1-FR5, FR41-FR43 |
| Epic 3: Photo Capture with LiDAR Depth | 8 | FR6-FR13 |
| Epic 4: Upload & Evidence Processing | 10 | FR14-FR26, FR44-FR46 |
| Epic 5: C2PA & Verification Experience | 10 | FR27-FR40 |
| Epic 6: Native Swift Implementation | 16 | FR1-FR19, FR41-FR46 (native) |
| Epic 7: Video Capture with LiDAR Depth | 14 | FR47-FR55 |
| Epic 8: Privacy-First Capture Mode | 8 | FR56-FR62 |

**Context Incorporated:**
- ✅ PRD requirements (all 62 FRs mapped)
- ✅ Architecture technical decisions (tech stack, API contracts, patterns)
- ✅ Native Swift re-implementation for maximum security posture
- ✅ Video capture with frame-by-frame depth and hash chain integrity
- ✅ Privacy-first capture with client-side depth analysis (ADR-011)

**Epic 6 Note:** Provides native Swift alternatives to Epics 2-4 mobile functionality. Can be developed in parallel. After Story 6.16 validation, Expo/RN code can be deprecated.

**Epic 7 Note:** Video capture extends the native Swift implementation. Builds on Epic 6 ARKit foundations. Adds temporal depth analysis and hash chain verification for video-specific manipulation detection.

**Epic 8 Note:** Privacy-first mode enables zero-knowledge provenance. Client-side depth analysis trusted via hardware attestation. Added via Sprint Change Proposal SCP-008 (2025-12-01).

**Status:** Epic 8 added - Ready for implementation!

---

_For implementation: Use the `create-story` workflow to generate individual story implementation plans from this epic breakdown._

_This document will be updated after UX Design workflow to incorporate interaction details and mockup references._

