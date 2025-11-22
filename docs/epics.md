# RealityCam - Epic Breakdown

**Author:** Luca
**Date:** 2025-11-22
**Project Level:** medium complexity
**Target Scale:** Multi-component system (iOS App + Backend + Verification Web)

---

## Overview

This document provides the complete epic and story breakdown for RealityCam, decomposing the requirements from the [PRD](./prd.md) into implementable stories.

**Living Document Notice:** This is the initial version created from PRD v1.1 and Architecture v1.1. It will be updated after UX Design workflow adds interaction details to stories.

**Context Incorporated:**
- PRD v1.1 (46 MVP FRs)
- Architecture v1.1 (iPhone Pro only, LiDAR depth, DCAppAttest)

### Epic Summary

| Epic | Title | Stories | FRs Covered | User Value |
|------|-------|---------|-------------|------------|
| 1 | Foundation & Project Setup | 5 | Infrastructure | Development environment ready |
| 2 | Device Registration & Attestation | 6 | FR1-5, FR41-43 | Hardware trust established |
| 3 | Photo Capture with LiDAR | 6 | FR6-13 | Users can capture attested photos |
| 4 | Upload, Processing & Evidence | 8 | FR14-26, FR44-46 | Photos analyzed, evidence computed |
| 5 | C2PA & Verification Interface | 8 | FR27-40 | End-to-end verification flow |

**Total:** 33 stories covering all 46 FRs

---

## Functional Requirements Inventory

### MVP Scope (46 FRs)

| FR | Description | Category |
|----|-------------|----------|
| FR1 | App detects iPhone Pro device with LiDAR capability | Device & Attestation |
| FR2 | App generates cryptographic keys in Secure Enclave | Device & Attestation |
| FR3 | App requests DCAppAttest attestation from iOS | Device & Attestation |
| FR4 | Backend verifies DCAppAttest assertions against Apple's service | Device & Attestation |
| FR5 | System assigns attestation level: secure_enclave or unverified | Device & Attestation |
| FR6 | App displays camera view with LiDAR depth overlay | Capture Flow |
| FR7 | App captures photo via back camera | Capture Flow |
| FR8 | App simultaneously captures LiDAR depth map via ARKit | Capture Flow |
| FR9 | App records GPS coordinates if permission granted | Capture Flow |
| FR10 | App captures device attestation signature for the capture | Capture Flow |
| FR11 | App computes SHA-256 hash of photo before upload | Local Processing |
| FR12 | App compresses depth map (gzip float32 array) | Local Processing |
| FR13 | App constructs structured capture request with photo + depth + metadata | Local Processing |
| FR14 | App uploads capture via multipart POST (photo + depth_map + metadata JSON) | Upload & Sync |
| FR15 | App uses TLS 1.3 for all API communication | Upload & Sync |
| FR16 | App implements retry with exponential backoff on upload failure | Upload & Sync |
| FR17 | App stores captures in encrypted local storage when offline (Secure Enclave key) | Upload & Sync |
| FR18 | App auto-uploads pending captures when connectivity returns | Upload & Sync |
| FR19 | App displays pending upload status to user | Upload & Sync |
| FR20 | Backend verifies DCAppAttest attestation and records level | Evidence Generation |
| FR21 | Backend performs LiDAR depth analysis (variance, layers, edge coherence) | Evidence Generation |
| FR22 | Backend determines "is_likely_real_scene" from depth analysis | Evidence Generation |
| FR23 | Backend validates EXIF timestamp against server receipt time | Evidence Generation |
| FR24 | Backend validates device model is iPhone Pro (has LiDAR) | Evidence Generation |
| FR25 | Backend generates evidence package with all check results | Evidence Generation |
| FR26 | Backend calculates confidence level (HIGH/MEDIUM/LOW/SUSPICIOUS) | Evidence Generation |
| FR27 | Backend creates C2PA manifest with evidence summary | C2PA Integration |
| FR28 | Backend signs C2PA manifest with Ed25519 key (HSM-backed in production) | C2PA Integration |
| FR29 | Backend embeds C2PA manifest in photo file | C2PA Integration |
| FR30 | System stores both original and C2PA-embedded versions | C2PA Integration |
| FR31 | Users can view capture verification via shareable URL | Verification Interface |
| FR32 | Verification page displays confidence summary (HIGH/MEDIUM/LOW/SUSPICIOUS) | Verification Interface |
| FR33 | Verification page displays depth analysis visualization | Verification Interface |
| FR34 | Users can expand detailed evidence panel with per-check status | Verification Interface |
| FR35 | Each check displays pass/fail with relevant metrics | Verification Interface |
| FR36 | Users can upload file to verification endpoint | File Verification |
| FR37 | System computes hash and searches for matching capture | File Verification |
| FR38 | If match found: display linked capture evidence | File Verification |
| FR39 | If no match but C2PA manifest present: display manifest info with note | File Verification |
| FR40 | If no match and no manifest: display "No provenance record found" | File Verification |
| FR41 | System generates device-level pseudonymous ID (Secure Enclave backed) | Device Management |
| FR42 | Users can capture and verify without account (anonymous by default) | Device Management |
| FR43 | Device registration stores attestation key ID and capability flags | Device Management |
| FR44 | GPS stored at coarse level (city) by default in public view | Privacy Controls |
| FR45 | Users can opt-out of location (noted in evidence, not suspicious) | Privacy Controls |
| FR46 | Depth map stored but not publicly downloadable (only visualization) | Privacy Controls |

### Summary

- **Total:** 46 Functional Requirements (MVP)
- **Device & Attestation:** FR1-FR5 (5)
- **Capture Flow:** FR6-FR10 (5)
- **Local Processing:** FR11-FR13 (3)
- **Upload & Sync:** FR14-FR19 (6)
- **Evidence Generation:** FR20-FR26 (7)
- **C2PA Integration:** FR27-FR30 (4)
- **Verification Interface:** FR31-FR35 (5)
- **File Verification:** FR36-FR40 (5)
- **Device Management:** FR41-FR43 (3)
- **Privacy Controls:** FR44-FR46 (3)

---

## FR Coverage Map

| FR | Epic | Story | Description |
|----|------|-------|-------------|
| FR1 | 2 | 2.1 | iPhone Pro detection |
| FR2 | 2 | 2.2 | Secure Enclave key generation |
| FR3 | 2 | 2.3 | DCAppAttest integration |
| FR4 | 2 | 2.4, 2.5 | Backend attestation verification |
| FR5 | 2 | 2.5 | Attestation level assignment |
| FR6 | 3 | 3.1 | Camera with depth overlay |
| FR7 | 3 | 3.2 | Photo capture |
| FR8 | 3 | 3.2 | LiDAR depth capture |
| FR9 | 3 | 3.3 | GPS recording |
| FR10 | 3 | 3.4 | Capture attestation signature |
| FR11 | 3 | 3.5 | SHA-256 hash |
| FR12 | 3 | 3.5 | Depth map compression |
| FR13 | 3 | 3.5 | Structured capture request |
| FR14 | 4 | 4.1 | Multipart upload |
| FR15 | 4 | 4.1 | TLS 1.3 |
| FR16 | 4 | 4.2 | Retry with backoff |
| FR17 | 4 | 4.3 | Encrypted offline storage |
| FR18 | 4 | 4.3 | Auto-upload on reconnect |
| FR19 | 4 | 4.2 | Pending status display |
| FR20 | 4 | 4.4 | Attestation verification |
| FR21 | 4 | 4.5 | Depth analysis |
| FR22 | 4 | 4.5 | is_likely_real_scene |
| FR23 | 4 | 4.6 | EXIF timestamp validation |
| FR24 | 4 | 4.6 | Device model validation |
| FR25 | 4 | 4.7 | Evidence package |
| FR26 | 4 | 4.7 | Confidence calculation |
| FR27 | 5 | 5.1 | C2PA manifest creation |
| FR28 | 5 | 5.2 | Ed25519 signing |
| FR29 | 5 | 5.3 | Manifest embedding |
| FR30 | 5 | 5.3 | Original + C2PA storage |
| FR31 | 5 | 5.4 | Verification URL |
| FR32 | 5 | 5.4 | Confidence display |
| FR33 | 5 | 5.4 | Depth visualization |
| FR34 | 5 | 5.5 | Evidence panel |
| FR35 | 5 | 5.5 | Per-check status |
| FR36 | 5 | 5.6 | File upload |
| FR37 | 5 | 5.6 | Hash search |
| FR38 | 5 | 5.7 | Match → show evidence |
| FR39 | 5 | 5.7 | No match + C2PA |
| FR40 | 5 | 5.7 | No match → no record |
| FR41 | 2 | 2.2 | Device pseudonymous ID |
| FR42 | 2 | 2.6 | Anonymous capture/verify |
| FR43 | 2 | 2.4 | Device registration storage |
| FR44 | 4 | 4.8 | Coarse GPS |
| FR45 | 4 | 4.8 | Location opt-out |
| FR46 | 4 | 4.8 | Depth map privacy |

---

## Epic 1: Foundation & Project Setup

**Goal:** Establish development infrastructure and project structure enabling all subsequent feature development.

**User Value:** Development team can iterate quickly with proper tooling, CI, and local environment.

**FRs Covered:** Infrastructure foundation for all FRs (no direct FR coverage)

---

### Story 1.1: Monorepo Structure & Development Environment

As a **developer**,
I want **a properly structured monorepo with all three components**,
So that **I can develop iOS app, backend, and web in a coordinated environment**.

**Acceptance Criteria:**

**Given** a fresh clone of the repository
**When** I run the setup commands
**Then** I have:
- `apps/mobile/` - Expo iOS app (SDK 53, TypeScript)
- `apps/web/` - Next.js 16 verification site
- `backend/` - Rust API server structure
- `packages/shared/` - Shared TypeScript types
- `infrastructure/docker-compose.yml` - Local services

**And** `docker-compose up -d` starts PostgreSQL and LocalStack (S3)
**And** each component has its own `package.json` or `Cargo.toml`

**Prerequisites:** None (first story)

**Technical Notes:**
- Use commands from Architecture doc: `bunx create-expo-app`, `npx create-next-app`, `cargo new`
- Expo prebuild for iOS only: `bunx expo prebuild --platform ios`
- Node.js 22+, Rust 1.82+, PostgreSQL 16

---

### Story 1.2: Database Schema & Migrations

As a **developer**,
I want **the core database schema defined with migrations**,
So that **device and capture data can be persisted**.

**Acceptance Criteria:**

**Given** PostgreSQL is running via docker-compose
**When** I run `sqlx migrate run`
**Then** the following tables exist:
- `devices` (id UUID, attestation_level TEXT, attestation_key_id TEXT UNIQUE, platform TEXT, model TEXT, has_lidar BOOLEAN, first_seen_at TIMESTAMPTZ, last_seen_at TIMESTAMPTZ)
- `captures` (id UUID, device_id UUID FK, target_media_hash BYTEA UNIQUE, evidence JSONB, confidence_level TEXT, status TEXT, captured_at TIMESTAMPTZ, uploaded_at TIMESTAMPTZ)

**And** hash index exists on `captures.target_media_hash`
**And** foreign key constraint links captures to devices

**Prerequisites:** Story 1.1

**Technical Notes:**
- SQLx 0.8 with compile-time checked queries
- JSONB for flexible evidence schema (ADR-006)
- TIMESTAMPTZ for all timestamps

---

### Story 1.3: Backend API Skeleton

As a **developer**,
I want **a basic Axum server with routing structure and middleware**,
So that **I have a foundation for implementing API endpoints**.

**Acceptance Criteria:**

**Given** the backend directory with Cargo.toml configured
**When** I run `cargo run`
**Then** the server starts on port 3000

**And** `GET /health` returns `{"status": "ok"}`
**And** all responses include `X-Request-Id` header
**And** CORS is configured for development origins
**And** tracing/logging is configured with JSON output

**Prerequisites:** Story 1.1

**Technical Notes:**
- Axum 0.8 with tower-http middleware
- Request ID middleware for tracing
- Error handling with thiserror
- Config via dotenvy (.env)

---

### Story 1.4: iOS App Shell with Navigation

As a **developer**,
I want **an Expo app with tab navigation and screen structure**,
So that **I have screens ready for capture and history features**.

**Acceptance Criteria:**

**Given** the mobile app directory
**When** I run `npx expo run:ios`
**Then** the app launches on iOS simulator or device

**And** bottom tab navigation shows "Capture" and "History" tabs
**And** Capture tab shows placeholder camera view
**And** History tab shows placeholder list
**And** Expo Router file-based routing is configured

**Prerequisites:** Story 1.1

**Technical Notes:**
- Expo Router for navigation (`app/` directory)
- Tab layout in `app/(tabs)/_layout.tsx`
- Zustand store scaffolding in `store/`

---

### Story 1.5: Verification Web Shell

As a **developer**,
I want **a Next.js app with verification page structure**,
So that **I have pages ready for verification features**.

**Acceptance Criteria:**

**Given** the web app directory
**When** I run `npm run dev`
**Then** the site is accessible at localhost:3001

**And** `/` shows landing page placeholder
**And** `/verify/[id]` shows verification page placeholder
**And** Tailwind CSS is configured
**And** TypeScript strict mode is enabled

**Prerequisites:** Story 1.1

**Technical Notes:**
- Next.js 16 with App Router and Turbopack
- React 19 features available
- API client in `lib/api.ts`

---

## Epic 2: Device Registration & Hardware Attestation

**Goal:** Establish hardware-rooted trust by implementing DCAppAttest and device registration.

**User Value:** Every subsequent capture is cryptographically tied to a verified, uncompromised iPhone Pro device. This is the foundation of RealityCam's trust model.

**FRs Covered:** FR1, FR2, FR3, FR4, FR5, FR41, FR42, FR43

---

### Story 2.1: iPhone Pro Detection & Capability Check

As a **user**,
I want **the app to detect if my device is a supported iPhone Pro**,
So that **I know whether I can use full attestation features**.

**Acceptance Criteria:**

**Given** the app is launched on an iOS device
**When** the app checks device capabilities
**Then** it detects if device is iPhone Pro (12 Pro through 17 Pro)

**And** it checks for LiDAR sensor availability via ARKit
**And** it checks for Secure Enclave capability
**And** non-Pro devices see "This app requires iPhone Pro with LiDAR" message
**And** capability flags are stored: `has_lidar`, `has_secure_enclave`

**Prerequisites:** Story 1.4

**Technical Notes:**
- Use `UIDevice.current.model` and model identifier mapping
- ARKit `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)` for LiDAR
- SecureEnclave availability check via Security framework
- Covers FR1

---

### Story 2.2: Secure Enclave Key Generation (Expo Module)

As a **device**,
I want **to generate a hardware-backed Ed25519 key pair**,
So that **my identity is cryptographically tied to the Secure Enclave**.

**Acceptance Criteria:**

**Given** a supported iPhone Pro device
**When** the app initializes for the first time
**Then** an Ed25519 key pair is generated in the Secure Enclave

**And** the private key is non-extractable (hardware-bound)
**And** the public key can be exported for registration
**And** a unique device ID (UUID) is derived from the key
**And** key generation only happens once (persisted)

**Prerequisites:** Story 2.1

**Technical Notes:**
- Create Expo Module: `modules/device-attestation/`
- Swift implementation in `ios/DeviceAttestationModule.swift`
- Use `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`
- Store key reference in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- Covers FR2, FR41

---

### Story 2.3: DCAppAttest Integration (Expo Module)

As a **device**,
I want **to request attestation from iOS DCAppAttest**,
So that **Apple can vouch for device integrity**.

**Acceptance Criteria:**

**Given** the device key pair exists in Secure Enclave
**When** attestation is requested
**Then** the app calls `DCAppAttestService.shared.attestKey()`

**And** receives CBOR attestation object from Apple
**And** receives key ID for the attested key
**And** attestation object contains certificate chain
**And** errors are handled (network, unsupported device)

**Prerequisites:** Story 2.2

**Technical Notes:**
- Extend Expo Module with attestation methods
- DCAppAttest requires iOS 14.0+
- Attestation object is CBOR-encoded
- Key ID is base64-encoded string
- Covers FR3

---

### Story 2.4: Backend Device Registration Endpoint

As a **device**,
I want **to register with the backend using my attestation**,
So that **the server knows my identity and can verify future requests**.

**Acceptance Criteria:**

**Given** the device has attestation object and key ID
**When** `POST /api/v1/devices/register` is called with:
```json
{
  "platform": "ios",
  "model": "iPhone 15 Pro",
  "attestation": {
    "key_id": "base64...",
    "attestation_object": "base64...",
    "public_key": "base64..."
  },
  "capabilities": {
    "has_lidar": true,
    "has_secure_enclave": true
  }
}
```
**Then** the server stores the device record

**And** returns `{ "device_id": "uuid", "attestation_level": "...", "has_lidar": true }`
**And** device ID is stored locally for future requests
**And** duplicate registrations (same key_id) return existing device

**Prerequisites:** Story 1.2, Story 1.3, Story 2.3

**Technical Notes:**
- Route in `backend/src/routes/devices.rs`
- Store public key for signature verification
- Covers FR4 (partial), FR43

---

### Story 2.5: DCAppAttest Verification (Backend)

As a **backend service**,
I want **to verify DCAppAttest attestation objects**,
So that **I can confirm device integrity before trusting it**.

**Acceptance Criteria:**

**Given** a device registration request with attestation object
**When** the backend verifies the attestation
**Then** it parses the CBOR attestation object

**And** extracts and validates the X.509 certificate chain
**And** verifies chain roots to Apple's App Attest root CA
**And** verifies the attestation was for this app's App ID
**And** assigns attestation level: `secure_enclave` (verified) or `unverified` (failed)
**And** logs verification result for audit

**Prerequisites:** Story 2.4

**Technical Notes:**
- Use `x509-parser` crate for certificate parsing
- Apple App Attest root CA must be embedded or fetched
- Verify `credCert` and intermediate certificates
- Extract and verify `receipt` field
- Covers FR4, FR5

---

### Story 2.6: Device Authentication Middleware

As a **backend service**,
I want **to verify device signatures on every authenticated request**,
So that **only registered devices can upload captures**.

**Acceptance Criteria:**

**Given** a request to a protected endpoint (e.g., POST /captures)
**When** the middleware extracts authentication headers:
- `X-Device-Id`: device UUID
- `X-Device-Timestamp`: Unix milliseconds
- `X-Device-Signature`: Ed25519 signature

**Then** it verifies timestamp is within 5 minutes of server time
**And** it looks up device public key by ID
**And** it verifies signature over `timestamp + sha256(body)`
**And** valid requests proceed; invalid return 401

**Prerequisites:** Story 2.4

**Technical Notes:**
- Middleware in `backend/src/middleware/device_auth.rs`
- Use `ed25519-dalek` for signature verification
- No bearer tokens needed (ADR-005)
- Covers FR42

---

## Epic 3: Photo Capture with LiDAR Depth

**Goal:** Enable users to capture photos with simultaneous LiDAR depth data and device attestation signature.

**User Value:** Users can take photos that include depth proof, demonstrating the scene was real 3D space (not a flat screen or printed image).

**FRs Covered:** FR6, FR7, FR8, FR9, FR10, FR11, FR12, FR13

---

### Story 3.1: Camera View with LiDAR Depth Overlay

As a **user**,
I want **to see a camera preview with depth visualization**,
So that **I can see the LiDAR is working before I capture**.

**Acceptance Criteria:**

**Given** I'm on the Capture screen
**When** the camera view loads
**Then** I see the back camera preview

**And** I see a depth overlay visualization (heatmap or gradient)
**And** closer objects appear in warmer colors (red/orange)
**And** farther objects appear in cooler colors (blue/green)
**And** the overlay updates in real-time (~15-30 fps)
**And** I can toggle the overlay on/off

**Prerequisites:** Story 2.2 (device attestation module exists)

**Technical Notes:**
- Extend Expo Module with ARKit depth streaming
- Use `ARSession` with `ARWorldTrackingConfiguration`
- Access `ARFrame.sceneDepth` for LiDAR depth
- Render depth as semi-transparent overlay on camera view
- Covers FR6

---

### Story 3.2: Photo Capture with Depth Map

As a **user**,
I want **to capture a photo with its corresponding depth map**,
So that **I have proof of the 3D scene structure**.

**Acceptance Criteria:**

**Given** the camera view with depth overlay is active
**When** I tap the capture button
**Then** the app captures a high-resolution photo

**And** simultaneously captures the LiDAR depth map
**And** depth map is aligned with the photo
**And** both are stored temporarily in memory
**And** capture timestamp is recorded
**And** haptic feedback confirms capture

**Prerequisites:** Story 3.1

**Technical Notes:**
- Use `AVCaptureSession` for photo capture
- Synchronize with ARKit frame for depth
- Depth map format: float32 array (width × height)
- Photo format: JPEG with EXIF
- Covers FR7, FR8

---

### Story 3.3: GPS and Metadata Collection

As a **user**,
I want **my location recorded with my capture (if I permit)**,
So that **geographic context is part of the evidence**.

**Acceptance Criteria:**

**Given** a capture is being taken
**When** location permission is granted
**Then** GPS coordinates (lat/lon) are recorded

**And** accuracy level is recorded
**And** if permission denied, capture proceeds without location
**And** device metadata is collected: model, OS version, capture time

**Prerequisites:** Story 3.2

**Technical Notes:**
- Use `expo-location` for GPS
- Request permission on first capture attempt
- Store location with capture metadata
- Covers FR9

---

### Story 3.4: Capture Attestation Signature

As a **device**,
I want **to sign each capture with my Secure Enclave key**,
So that **the capture is cryptographically bound to this device**.

**Acceptance Criteria:**

**Given** a capture has been taken (photo + depth + metadata)
**When** preparing for upload
**Then** the app computes SHA-256 hash of the photo

**And** signs `capture_hash + timestamp` with device private key
**And** signature is Ed25519 format
**And** signature is included in capture request

**Prerequisites:** Story 2.2, Story 3.3

**Technical Notes:**
- Signing happens in Expo Module (Swift)
- Use Secure Enclave key created in Story 2.2
- Signature proves this device created this capture
- Covers FR10

---

### Story 3.5: Local Processing Pipeline

As a **device**,
I want **to prepare the capture for upload**,
So that **data is efficiently packaged for transmission**.

**Acceptance Criteria:**

**Given** a capture with photo, depth map, metadata, and signature
**When** the processing pipeline runs
**Then** SHA-256 hash of photo is computed

**And** depth map is compressed (gzip of float32 array)
**And** structured capture request is constructed:
```json
{
  "photo_hash": "sha256...",
  "captured_at": "ISO8601",
  "location": { "lat": 0.0, "lon": 0.0 } | null,
  "device_model": "iPhone 15 Pro",
  "signature": "base64..."
}
```
**And** estimated upload size is calculated (~3-4 MB total)

**Prerequisites:** Story 3.4

**Technical Notes:**
- Use `expo-crypto` for SHA-256
- Gzip compression via native module or JS library
- Typical sizes: photo ~3MB, depth ~1MB compressed
- Covers FR11, FR12, FR13

---

### Story 3.6: Capture Preview Screen

As a **user**,
I want **to preview my capture before uploading**,
So that **I can confirm it's the photo I want to submit**.

**Acceptance Criteria:**

**Given** a capture has been processed
**When** I navigate to the preview screen
**Then** I see the captured photo

**And** I see the depth map overlay (toggleable)
**And** I see capture metadata (time, location if available)
**And** I can tap "Upload" to proceed
**And** I can tap "Retake" to discard and return to camera
**And** if offline, "Upload" shows "Save for later"

**Prerequisites:** Story 3.5

**Technical Notes:**
- Screen at `app/preview.tsx`
- Store capture in Zustand before upload decision
- Show depth overlay using same visualization as camera
- No direct FR, but completes capture flow

---

## Epic 4: Upload, Processing & Evidence Generation

**Goal:** Upload captures to backend, verify attestation, analyze depth data, and generate evidence packages with confidence levels.

**User Value:** Captures are professionally analyzed and assigned confidence levels based on hardware attestation and depth analysis. Users know how trustworthy their evidence is.

**FRs Covered:** FR14, FR15, FR16, FR17, FR18, FR19, FR20, FR21, FR22, FR23, FR24, FR25, FR26, FR44, FR45, FR46

---

### Story 4.1: Capture Upload Endpoint

As a **device**,
I want **to upload my capture to the backend**,
So that **it can be processed and stored**.

**Acceptance Criteria:**

**Given** a prepared capture with photo, depth map, and metadata
**When** `POST /api/v1/captures` is called with multipart form data:
- Part `photo`: JPEG binary
- Part `depth_map`: gzipped float32 binary
- Part `metadata`: JSON with capture info

**Then** the server receives and validates all parts
**And** verifies device signature via middleware
**And** stores photo and depth map to S3
**And** creates capture record with `status: "processing"`
**And** returns `{ "capture_id": "uuid", "status": "processing" }`

**Prerequisites:** Story 2.6, Story 3.5

**Technical Notes:**
- Route in `backend/src/routes/captures.rs`
- Use `axum::extract::Multipart` for parsing
- S3 paths: `captures/{id}/original.jpg`, `captures/{id}/depth.gz`
- TLS 1.3 enforced at infrastructure level
- Covers FR14, FR15

---

### Story 4.2: Upload Queue with Retry

As a **user**,
I want **failed uploads to automatically retry**,
So that **temporary network issues don't lose my captures**.

**Acceptance Criteria:**

**Given** an upload fails due to network error
**When** the retry logic activates
**Then** it waits with exponential backoff (1s, 2s, 4s, 8s, max 60s)

**And** retries up to 5 times
**And** upload status is updated in local state
**And** I can see pending uploads in the History tab
**And** I can manually trigger retry

**Prerequisites:** Story 4.1

**Technical Notes:**
- Upload queue in `hooks/useUploadQueue.ts`
- Persist queue state with Zustand + AsyncStorage
- Show upload progress percentage
- Covers FR16, FR19

---

### Story 4.3: Offline Storage & Auto-Upload

As a **user**,
I want **captures saved securely when offline**,
So that **I never lose evidence even without connectivity**.

**Acceptance Criteria:**

**Given** I capture a photo while offline
**When** the upload attempt fails
**Then** the capture is stored in encrypted local storage

**And** encryption key is Secure Enclave-backed
**And** capture is marked as "pending upload"
**And** when connectivity returns, upload automatically starts
**And** I see a warning: "Evidence timestamping delayed"

**Prerequisites:** Story 4.2

**Technical Notes:**
- Use `expo-secure-store` for encryption key storage
- Use `expo-file-system` for encrypted file storage
- Network state detection via `NetInfo`
- Covers FR17, FR18

---

### Story 4.4: Attestation Verification on Upload

As a **backend service**,
I want **to verify the device's attestation status on each upload**,
So that **evidence includes current device trust level**.

**Acceptance Criteria:**

**Given** a capture upload from a registered device
**When** processing the capture
**Then** the backend retrieves device attestation level

**And** verifies device signature is valid
**And** records attestation verification result in evidence:
```json
{
  "hardware_attestation": {
    "status": "pass",
    "level": "secure_enclave",
    "device_model": "iPhone 15 Pro",
    "key_id": "..."
  }
}
```
**And** if attestation verification fails, status is "fail"

**Prerequisites:** Story 2.5, Story 4.1

**Technical Notes:**
- Service in `backend/src/services/evidence/hardware.rs`
- Covers FR20

---

### Story 4.5: LiDAR Depth Analysis Service

As a **backend service**,
I want **to analyze the depth map for authenticity signals**,
So that **I can determine if the scene was real 3D space**.

**Acceptance Criteria:**

**Given** a capture with depth map
**When** depth analysis runs
**Then** it decompresses the gzipped depth data

**And** calculates depth variance (std dev of depth values)
**And** counts distinct depth layers (clustering)
**And** calculates edge coherence (depth edges vs RGB edges)
**And** determines `is_likely_real_scene`:
  - `true` if: variance > 0.5 AND layers >= 3 AND coherence > 0.7
  - `false` otherwise

**And** records analysis in evidence:
```json
{
  "depth_analysis": {
    "status": "pass",
    "depth_variance": 2.4,
    "depth_layers": 5,
    "edge_coherence": 0.87,
    "min_depth": 0.8,
    "is_likely_real_scene": true
  }
}
```

**Prerequisites:** Story 4.1

**Technical Notes:**
- Service in `backend/src/services/evidence/depth.rs`
- Use image crate for RGB processing
- Thresholds from Architecture doc (may need tuning)
- Covers FR21, FR22

---

### Story 4.6: Metadata Validation

As a **backend service**,
I want **to validate capture metadata for consistency**,
So that **obvious manipulation attempts are flagged**.

**Acceptance Criteria:**

**Given** a capture with EXIF metadata
**When** validation runs
**Then** it compares EXIF timestamp to server receipt time

**And** allows tolerance of ±5 minutes (clock drift)
**And** validates device model is iPhone Pro (has LiDAR)
**And** validates resolution matches device capability
**And** records validation in evidence:
```json
{
  "metadata": {
    "timestamp_valid": true,
    "timestamp_delta_seconds": 3,
    "model_valid": true,
    "model_has_lidar": true
  }
}
```

**Prerequisites:** Story 4.1

**Technical Notes:**
- Service in `backend/src/services/evidence/metadata.rs`
- EXIF parsing with `kamadak-exif` or similar
- iPhone Pro model list from PRD
- Covers FR23, FR24

---

### Story 4.7: Evidence Package & Confidence Calculation

As a **backend service**,
I want **to aggregate all checks and calculate confidence level**,
So that **captures have a clear trust assessment**.

**Acceptance Criteria:**

**Given** all evidence checks have completed
**When** aggregation runs
**Then** it combines hardware, depth, and metadata evidence

**And** calculates confidence level:
- `SUSPICIOUS`: Any check failed
- `HIGH`: Hardware pass AND depth pass (is_likely_real_scene)
- `MEDIUM`: Hardware pass XOR depth pass
- `LOW`: Neither pass (but none failed)

**And** stores complete evidence package as JSONB
**And** updates capture status to "complete"
**And** records processing duration for metrics

**Prerequisites:** Story 4.4, Story 4.5, Story 4.6

**Technical Notes:**
- Service in `backend/src/services/evidence/mod.rs`
- Confidence algorithm from Architecture doc
- Covers FR25, FR26

---

### Story 4.8: Privacy Controls Implementation

As a **user**,
I want **control over what location data is shown publicly**,
So that **my privacy is protected while evidence remains valid**.

**Acceptance Criteria:**

**Given** a capture with GPS coordinates
**When** the capture is stored and processed
**Then** GPS is stored at full precision in database (private)

**And** public view shows coarse location (city level only)
**And** if user opted out of location, evidence notes "location_opted_out: true"
**And** opted-out location reduces confidence ceiling but isn't marked suspicious
**And** depth map is stored but not publicly downloadable
**And** only depth visualization (heatmap image) is public

**Prerequisites:** Story 4.7

**Technical Notes:**
- Coarse location: round to ~0.1 degree (~10km precision)
- Generate depth visualization image during processing
- Store original depth, expose only visualization
- Covers FR44, FR45, FR46

---

## Epic 5: C2PA Integration & Verification Interface

**Goal:** Generate C2PA manifests for interoperability and provide public verification interface.

**User Value:** Complete end-to-end flow where anyone can verify a capture via URL or by uploading a file. Evidence is embedded in industry-standard C2PA format.

**FRs Covered:** FR27, FR28, FR29, FR30, FR31, FR32, FR33, FR34, FR35, FR36, FR37, FR38, FR39, FR40

---

### Story 5.1: C2PA Manifest Generation

As a **backend service**,
I want **to create C2PA manifests with evidence summary**,
So that **captures are interoperable with Content Credentials ecosystem**.

**Acceptance Criteria:**

**Given** a capture with complete evidence package
**When** C2PA generation runs
**Then** it creates a C2PA manifest with:
- Claim generator: "RealityCam/1.0"
- Capture action: "c2pa.created"
- Assertions including evidence summary
- Ingredient (original photo)

**And** manifest follows C2PA 2.0 specification
**And** manifest includes custom assertions for RealityCam evidence

**Prerequisites:** Story 4.7

**Technical Notes:**
- Use `c2pa-rs` 0.51.x crate
- Service in `backend/src/services/c2pa.rs`
- Custom assertion namespace for depth analysis
- Covers FR27

---

### Story 5.2: C2PA Signing with Ed25519

As a **backend service**,
I want **to sign C2PA manifests with our server key**,
So that **manifests are cryptographically verifiable**.

**Acceptance Criteria:**

**Given** a C2PA manifest ready for signing
**When** signing is performed
**Then** manifest is signed with Ed25519 key

**And** in development: key loaded from file
**And** in production: key stored in HSM (AWS KMS)
**And** certificate chain is included in manifest
**And** signing timestamp is recorded

**Prerequisites:** Story 5.1

**Technical Notes:**
- Ed25519 via `ed25519-dalek`
- HSM integration via `aws-sdk-kms` for production
- Certificate renewal process documented
- Covers FR28

---

### Story 5.3: C2PA Embedding & Storage

As a **backend service**,
I want **to embed the manifest in the photo and store both versions**,
So that **users get standard-compliant media files**.

**Acceptance Criteria:**

**Given** a signed C2PA manifest and original photo
**When** embedding runs
**Then** manifest is embedded in photo as JUMBF

**And** original photo stored at `captures/{id}/original.jpg`
**And** C2PA photo stored at `captures/{id}/c2pa.jpg`
**And** standalone manifest stored at `captures/{id}/manifest.c2pa`
**And** all files accessible via presigned URLs (1 hour expiry)

**Prerequisites:** Story 5.2

**Technical Notes:**
- Use c2pa-rs `embed_file` function
- S3 structure from Architecture doc
- CloudFront CDN for media delivery
- Covers FR29, FR30

---

### Story 5.4: Verification Page - Summary View

As a **viewer**,
I want **to see a capture's verification summary**,
So that **I can quickly assess its trustworthiness**.

**Acceptance Criteria:**

**Given** I navigate to `/verify/{capture_id}`
**When** the page loads
**Then** I see:
- Confidence badge (HIGH/MEDIUM/LOW/SUSPICIOUS) with appropriate color
- Captured photo
- Capture timestamp and (coarse) location
- Depth analysis visualization (heatmap preview)
- Device model that captured it

**And** page loads in < 1.5s (FCP)
**And** media served via CDN with presigned URLs
**And** invalid capture ID shows "Capture not found"

**Prerequisites:** Story 1.5, Story 4.7

**Technical Notes:**
- Page at `apps/web/app/verify/[id]/page.tsx`
- API: `GET /api/v1/captures/{id}`
- Confidence colors: HIGH=green, MEDIUM=yellow, LOW=orange, SUSPICIOUS=red
- Covers FR31, FR32, FR33

---

### Story 5.5: Evidence Panel Component

As a **viewer**,
I want **to see detailed evidence breakdown**,
So that **I can understand exactly what was verified**.

**Acceptance Criteria:**

**Given** I'm on the verification page
**When** I click "View Evidence Details"
**Then** an expandable panel shows:

**Hardware Attestation:**
- Status: PASS/FAIL with icon
- Level: secure_enclave
- Device model verified

**Depth Analysis:**
- Status: PASS/FAIL with icon
- Depth variance: X.XX (threshold: >0.5)
- Depth layers: N (threshold: >=3)
- Edge coherence: X.XX (threshold: >0.7)
- is_likely_real_scene: true/false

**Metadata:**
- Timestamp validation: PASS/FAIL
- Device model validation: PASS/FAIL

**And** each check shows relevant metrics
**And** failed checks are prominently highlighted

**Prerequisites:** Story 5.4

**Technical Notes:**
- Component at `apps/web/components/Evidence/EvidencePanel.tsx`
- Collapsible sections for each evidence type
- Covers FR34, FR35

---

### Story 5.6: File Upload Verification

As a **viewer**,
I want **to upload a file to check if it's verified**,
So that **I can verify media I received from elsewhere**.

**Acceptance Criteria:**

**Given** I'm on the verification page (or home page)
**When** I drag/drop or select a file
**Then** the file is hashed client-side (SHA-256)

**And** hash is sent to `POST /api/v1/verify-file`
**And** I see a loading indicator during lookup
**And** supported formats: JPEG, PNG (image files)

**Prerequisites:** Story 1.5

**Technical Notes:**
- Component at `apps/web/components/Upload/FileDropzone.tsx`
- Use Web Crypto API for client-side hashing
- Max file size: 25MB
- Covers FR36, FR37

---

### Story 5.7: File Verification Results Display

As a **viewer**,
I want **to see results after uploading a file**,
So that **I know if the file has provenance records**.

**Acceptance Criteria:**

**Given** I've uploaded a file for verification
**When** the lookup completes
**Then** one of three results is displayed:

**Match Found:**
- "This file matches a verified capture"
- Link to full verification page
- Summary of evidence

**No Match, Has C2PA:**
- "No RealityCam record, but file has Content Credentials"
- Display C2PA manifest info (issuer, timestamp)
- Note: "Verify with original issuer"

**No Match, No C2PA:**
- "No provenance record found"
- Explanation that file wasn't captured with RealityCam
- Not necessarily suspicious, just unverified

**Prerequisites:** Story 5.6

**Technical Notes:**
- C2PA manifest detection using c2pa-rs
- Clear visual distinction between three states
- Covers FR38, FR39, FR40

---

### Story 5.8: Capture Result Screen (Mobile)

As a **user**,
I want **to see my verification URL after upload completes**,
So that **I can share proof of my capture**.

**Acceptance Criteria:**

**Given** my capture has been uploaded and processed
**When** I navigate to the result screen
**Then** I see:
- "Capture Verified" confirmation
- Confidence level badge
- Shareable verification URL
- "Copy Link" button
- "Share" button (native share sheet)
- "Capture Another" button

**And** the URL format is `https://realitycam.app/verify/{id}`
**And** I can view this capture in my History tab later

**Prerequisites:** Story 4.7, Story 3.6

**Technical Notes:**
- Screen at `apps/mobile/app/result.tsx`
- Use `expo-sharing` for native share
- Store capture reference in local history
- Completes mobile capture flow

---

## FR Coverage Matrix

| FR | Description | Epic | Story |
|----|-------------|------|-------|
| FR1 | App detects iPhone Pro device with LiDAR capability | 2 | 2.1 |
| FR2 | App generates cryptographic keys in Secure Enclave | 2 | 2.2 |
| FR3 | App requests DCAppAttest attestation from iOS | 2 | 2.3 |
| FR4 | Backend verifies DCAppAttest assertions against Apple's service | 2 | 2.4, 2.5 |
| FR5 | System assigns attestation level: secure_enclave or unverified | 2 | 2.5 |
| FR6 | App displays camera view with LiDAR depth overlay | 3 | 3.1 |
| FR7 | App captures photo via back camera | 3 | 3.2 |
| FR8 | App simultaneously captures LiDAR depth map via ARKit | 3 | 3.2 |
| FR9 | App records GPS coordinates if permission granted | 3 | 3.3 |
| FR10 | App captures device attestation signature for the capture | 3 | 3.4 |
| FR11 | App computes SHA-256 hash of photo before upload | 3 | 3.5 |
| FR12 | App compresses depth map (gzip float32 array) | 3 | 3.5 |
| FR13 | App constructs structured capture request with photo + depth + metadata | 3 | 3.5 |
| FR14 | App uploads capture via multipart POST (photo + depth_map + metadata JSON) | 4 | 4.1 |
| FR15 | App uses TLS 1.3 for all API communication | 4 | 4.1 |
| FR16 | App implements retry with exponential backoff on upload failure | 4 | 4.2 |
| FR17 | App stores captures in encrypted local storage when offline (Secure Enclave key) | 4 | 4.3 |
| FR18 | App auto-uploads pending captures when connectivity returns | 4 | 4.3 |
| FR19 | App displays pending upload status to user | 4 | 4.2 |
| FR20 | Backend verifies DCAppAttest attestation and records level | 4 | 4.4 |
| FR21 | Backend performs LiDAR depth analysis (variance, layers, edge coherence) | 4 | 4.5 |
| FR22 | Backend determines "is_likely_real_scene" from depth analysis | 4 | 4.5 |
| FR23 | Backend validates EXIF timestamp against server receipt time | 4 | 4.6 |
| FR24 | Backend validates device model is iPhone Pro (has LiDAR) | 4 | 4.6 |
| FR25 | Backend generates evidence package with all check results | 4 | 4.7 |
| FR26 | Backend calculates confidence level (HIGH/MEDIUM/LOW/SUSPICIOUS) | 4 | 4.7 |
| FR27 | Backend creates C2PA manifest with evidence summary | 5 | 5.1 |
| FR28 | Backend signs C2PA manifest with Ed25519 key (HSM-backed in production) | 5 | 5.2 |
| FR29 | Backend embeds C2PA manifest in photo file | 5 | 5.3 |
| FR30 | System stores both original and C2PA-embedded versions | 5 | 5.3 |
| FR31 | Users can view capture verification via shareable URL | 5 | 5.4 |
| FR32 | Verification page displays confidence summary (HIGH/MEDIUM/LOW/SUSPICIOUS) | 5 | 5.4 |
| FR33 | Verification page displays depth analysis visualization | 5 | 5.4 |
| FR34 | Users can expand detailed evidence panel with per-check status | 5 | 5.5 |
| FR35 | Each check displays pass/fail with relevant metrics | 5 | 5.5 |
| FR36 | Users can upload file to verification endpoint | 5 | 5.6 |
| FR37 | System computes hash and searches for matching capture | 5 | 5.6 |
| FR38 | If match found: display linked capture evidence | 5 | 5.7 |
| FR39 | If no match but C2PA manifest present: display manifest info with note | 5 | 5.7 |
| FR40 | If no match and no manifest: display "No provenance record found" | 5 | 5.7 |
| FR41 | System generates device-level pseudonymous ID (Secure Enclave backed) | 2 | 2.2 |
| FR42 | Users can capture and verify without account (anonymous by default) | 2 | 2.6 |
| FR43 | Device registration stores attestation key ID and capability flags | 2 | 2.4 |
| FR44 | GPS stored at coarse level (city) by default in public view | 4 | 4.8 |
| FR45 | Users can opt-out of location (noted in evidence, not suspicious) | 4 | 4.8 |
| FR46 | Depth map stored but not publicly downloadable (only visualization) | 4 | 4.8 |

---

## Summary

**5 Epics, 33 Stories, 46 FRs covered**

| Epic | Goal | Stories | Key Deliverable |
|------|------|---------|-----------------|
| 1 | Foundation | 5 | Dev environment ready |
| 2 | Device Registration | 6 | Hardware trust established |
| 3 | Photo Capture | 6 | Attested photos with depth |
| 4 | Upload & Evidence | 8 | Evidence computation pipeline |
| 5 | C2PA & Verification | 8 | End-to-end verification flow |

**Implementation Order:** Epics 1→2→3→4→5 (sequential, no parallel tracks needed for MVP)

**After Completing All Epics:**
- Users can capture photos with LiDAR depth on iPhone Pro
- Every capture is hardware-attested via Secure Enclave
- Evidence is computed: depth analysis + attestation + metadata
- Captures receive confidence levels (HIGH/MEDIUM/LOW/SUSPICIOUS)
- Anyone can verify via URL or file upload
- C2PA manifests enable ecosystem interoperability

---

_Generated by BMAD Epic Decomposition Workflow_
_Date: 2025-11-22_
_For: Luca_
