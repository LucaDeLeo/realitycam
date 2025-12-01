# rial. - Product Requirements Document

**Author:** Luca
**Date:** 2025-11-21
**Version:** 1.1 (MVP)

---

## Executive Summary

rial. is an iOS camera app providing cryptographically-attested, LiDAR-verified photo provenance for iPhone Pro devices. It shows viewers not just "this came from a camera" but "here's the strength of evidence that this was a real 3D scene captured by a genuine device."

The core insight: Provenance claims are only as strong as their weakest assumption. A software-only hash proves nothing if the software layer is compromised. Hardware attestation must be the foundation, not a later enhancement. LiDAR depth analysis provides the "real scene" signal that's prohibitively expensive to fake.

**What this is NOT:**
- Not an "AI detector" or "deepfake detector"
- Not a claim of absolute truth—we provide *evidence strength*, not binary verification
- Not a social platform
- Not cross-platform (MVP is iPhone Pro only)

**Standards alignment:** C2PA / Content Credentials for interoperability with ecosystem tools (Adobe, Google Photos, news organizations).

### What Makes This Special

**LiDAR as Authenticity Signal.** Real 3D scenes have depth variance, multiple layers, and edge coherence. Flat images (screenshots, screens, prints) have uniform depth at ~0.3-0.5m. This is captured simultaneously with the photo and is prohibitively expensive to fake.

**Hardware-Rooted Trust.** Every capture is attested by iOS Secure Enclave via DCAppAttest. The device identity key is generated in hardware, never extractable. Spoofing requires custom silicon.

**Transparency Over Security Theater.** We explicitly show what we CAN'T detect. When a check is unavailable, we say so. When evidence is weak, we communicate that. This honesty builds genuine trust.

**Why iPhone Pro Only (MVP):** LiDAR sensor is only on Pro models. Consistent hardware eliminates Android fragmentation. 50% less native code means faster iteration to a working demo.

---

## Project Classification

**Technical Type:** mobile_app
**Domain:** general (security/cryptography focus)
**Complexity:** medium
**Platform:** iPhone Pro only (MVP)

This is a multi-component system:
- **iOS App** (Native Swift/SwiftUI): Photo capture with LiDAR depth and hardware attestation
- **Backend** (Rust/Axum): Evidence processing, C2PA manifest generation
- **Verification Web** (Next.js 16): Public verification interface

The system requires deep integration with iOS Secure Enclave (DCAppAttest) and ARKit LiDAR APIs for depth-based authenticity verification. Native Swift chosen for direct OS framework access and minimal attack surface.

---

## Success Criteria

### MVP Success Indicators

1. **Hardware attestation adoption** - 100% of captures from Secure Enclave-attested devices (iPhone Pro only)
2. **Depth analysis completion** - >95% of captures have LiDAR depth data
3. **Verification engagement** - Verification page bounce rate <30%
4. **Evidence panel exploration** - >20% of viewers expand detailed evidence view
5. **"Real scene" detection accuracy** - >95% true positive rate for real 3D scenes vs flat images

### MVP (Demo-Ready) Success

- [ ] DCAppAttest hardware attestation working on iPhone Pro
- [ ] LiDAR depth capture and "real scene" analysis functional
- [ ] End-to-end flow: capture → verify URL → view evidence with depth visualization
- [ ] Demo-able in 5 minutes on real iPhone Pro device

### Long-term Success

- Adoption by at least one newsroom for verification workflow
- Cited in at least one published investigation
- C2PA conformance certification achieved
- Android expansion post-MVP validation

---

## Product Scope

### MVP - iPhone Pro Photo & Video Capture

**iOS App (MVP):**
- Photo capture with simultaneous LiDAR depth map
- Video capture (15s max) with 10fps depth keyframes
- DCAppAttest hardware attestation (Secure Enclave)
- Depth overlay visualization during capture (edge-only for video)
- SHA-256 hash computation (hash chain for video)
- Upload: photo/video + depth_map (gzipped float32) + metadata
- Receive and display verify URL
- Local encrypted storage for offline captures

**Backend (MVP):**
- `POST /devices`: device registration with DCAppAttest verification
- `POST /captures`: receive photo upload, verify attestation, analyze depth, store
- `POST /captures/video`: receive video upload with depth keyframes and hash chain
- `GET /captures/:id`: return capture data and evidence
- `POST /verify-file`: hash lookup
- Evidence package: Hardware Attestation + Depth Analysis + Metadata
- Video evidence: Hash chain verification + Temporal depth analysis
- C2PA manifest generation via c2pa-rs (photo and video)

**Verification Web (MVP):**
- Summary view with confidence level (HIGH/MEDIUM/LOW/SUSPICIOUS)
- Depth analysis visualization (depth map preview for photos, scrubber for video)
- Hardware attestation status display
- Expandable evidence panel with per-check details
- Video playback with evidence overlay and hash chain status
- Partial attestation display for interrupted videos
- File upload for hash verification

**MVP Scope Constraints:**
- iPhone Pro only (12 Pro through 17 Pro)
- Photo and video (video limited to 15 seconds max)
- Device-based auth (no user accounts)
- LiDAR required (no fallback for non-Pro devices)

### Deferred Features (Post-MVP)

| Feature | Reason for Deferral |
|---------|---------------------|
| Android support | Adds 50% native code, StrongBox fragmentation |
| Extended video (>15s) | Thermal throttling, larger file sizes, UX complexity |
| Delta depth compression | Optimization for v2 (simpler keyframe approach for MVP) |
| 360° environment scan | Complex UX, parallax computation |
| Sun angle verification | Requires solar position API integration |
| Barometric pressure | Requires weather/altitude correlation |
| Gyro × optical flow | Cross-modal correlation complexity |
| User accounts | Device-only auth sufficient for MVP |
| Multi-camera lighting | Complexity vs. value for photos |
| Expert raw data download | Nice-to-have, not core value prop |

### Vision (Future)

**Post-MVP Expansion:**
- Android support (Pixel 8+ with StrongBox)
- Video capture with motion correlation checks
- Open source release (transparency)
- Browser extension for inline verification
- Integration with news org verification workflows
- Formal security audit

### Out of Scope

The following are explicitly **not** part of this product:

**Content Analysis:**
- AI/ML deepfake detection (we provide provenance evidence, not content analysis)
- Semantic truth verification (we prove capture authenticity, not that depicted events are "true")
- Pre-capture manipulation detection (staged physical scenes are outside our threat model)

**Platform Features:**
- Social sharing/feed functionality (we are not a social platform)
- Gallery import with full confidence (only in-app captures receive full attestation)
- Cloud storage/backup service (we store evidence, not user media libraries)
- Editing tools (post-capture editing invalidates provenance)

**MVP Platform Constraints:**
- Android devices (deferred to post-MVP)
- Non-Pro iPhones (no LiDAR)
- Video capture (photo only for MVP)

---

## User Experience Principles

### Target Personas

**Citizen Journalist "Alex"**
- Documents protests, police actions, disasters
- Needs credible evidence that survives scrutiny
- Technical sophistication: medium

**Human Rights Worker "Sam"**
- Collects testimonies in conflict zones
- Needs offline-first, exportable evidence packages
- Often on low bandwidth, hostile networks

**Everyday User "Jordan"**
- Proving authenticity for insurance claims, marketplace listings
- Needs simple "this is trustworthy" signal
- Technical sophistication: low

**Forensic Analyst "Riley"**
- Receives captures for investigation
- Needs raw data, methodology transparency, reproducibility
- Technical sophistication: high

### Key Interactions

**UC1: Photo Capture with Depth**
1. User opens app, enters capture mode
2. App shows camera with depth overlay (LiDAR visualization)
3. User frames subject, taps capture button
4. App simultaneously captures: photo + LiDAR depth map + device attestation
5. Upload includes all evidence; user receives shareable verify link

**UC2: Video Capture with Depth**
1. User switches to video mode in capture screen
2. App shows camera with edge-detection depth overlay
3. User presses and holds record button
4. Timer shows elapsed time (max 15 seconds)
5. User releases or timer reaches limit
6. App signs hash chain with device attestation
7. If interrupted: checkpoint attestation preserves partial evidence

**UC3: View Capture Result**
1. After capture, app shows preview with depth visualization (photo) or playback (video)
2. User sees preliminary confidence indicator
3. User can share verify link or capture another

**UC4: Verify Received Media**
1. Recipient opens verification link
2. Sees confidence summary (HIGH/MEDIUM/LOW/SUSPICIOUS)
3. Sees depth analysis visualization (proof of real 3D scene)
4. For video: playback with hash chain status and temporal analysis
5. Can expand detailed evidence panel

**UC5: Upload External File for Hash Lookup**
1. User uploads file to verification page
2. System checks if hash matches any registered capture
3. If match: show evidence. If no match: "No record found"

### Evidence Legibility Scales with Viewer Expertise

- **Casual viewer:** confidence summary + primary evidence type
- **Journalist:** expandable panel with pass/fail/unavailable per check
- **Forensic analyst:** raw data export, methodology documentation

---

## iOS App Requirements

### Platform Support (MVP)

**iPhone Pro Only:**

| Model | Released | LiDAR | Secure Enclave | Status |
|-------|----------|-------|----------------|--------|
| iPhone 17 Pro / Pro Max | 2025 | ✅ | ✅ | Current |
| iPhone 16 Pro / Pro Max | 2024 | ✅ | ✅ | Supported |
| iPhone 15 Pro / Pro Max | 2023 | ✅ | ✅ | Supported |
| iPhone 14 Pro / Pro Max | 2022 | ✅ | ✅ | Supported |
| iPhone 13 Pro / Pro Max | 2021 | ✅ | ✅ | Supported |
| iPhone 12 Pro / Pro Max | 2020 | ✅ | ✅ | Supported |

- Minimum iOS version: iOS 15.0 (required for modern Swift concurrency and improved ARKit depth APIs)
- LiDAR required for MVP (primary evidence signal)
- Non-Pro iPhones: Not supported in MVP (no LiDAR)
- All supported devices can run iOS 15+ (iPhone 12 Pro released with iOS 14, updated to iOS 15+)

**Why No Android (MVP):**
- StrongBox availability varies by manufacturer
- No LiDAR equivalent on Android devices
- 50% less native code to maintain
- Faster iteration to working demo

### Device Capabilities

**Required:**
- LiDAR sensor (depth capture)
- Secure Enclave (DCAppAttest)
- Camera (back camera, wide lens)
- GPS (for location metadata)

**Optional (captured if available):**
- Gyroscope, accelerometer (for future video support)
- Barometer (for future altitude verification)

### Offline Mode

- Store photo + depth map in encrypted local storage
- Encryption key: Secure Enclave backed
- Mark as "Pending upload"
- Auto-upload when connectivity returns
- Display warning: "Evidence timestamping delayed—server receipt time will differ from capture time"

---

## Innovation & Novel Patterns

### Evidence Architecture (MVP)

The MVP focuses on two high-value evidence dimensions plus basic metadata:

**Primary Evidence: Hardware Attestation**
- Device identity attested by iOS Secure Enclave via DCAppAttest
- Key generated in hardware, never extractable
- Proves: Photo originated from a real, uncompromised iPhone Pro
- Spoofing cost: Custom silicon or firmware exploit (~impossible for attacker)

**Primary Evidence: LiDAR Depth Analysis**
- Depth map captured simultaneously with photo using ARKit
- Analyze: depth variance, edge coherence, 3D structure
- Proves: Camera pointed at real 3D scene, not flat image/screen
- Spoofing cost: Building physical 3D replica of scene

**Depth Analysis Algorithm:**
```
DepthAnalysis:
  depth_variance: f32    // High = real scene, Low = flat
  edge_coherence: f32    // Depth edges align with RGB edges
  min_depth: f32         // Nearest point (screens are ~0.3-0.5m)
  depth_layers: u32      // Distinct depth planes detected

is_likely_real_scene:
  depth_variance > 0.5 AND
  depth_layers >= 3 AND
  edge_coherence > 0.7
```

**Secondary Evidence: Metadata Consistency**
- EXIF timestamp within tolerance of server time
- Device model matches iPhone Pro (has LiDAR)
- Resolution matches device capability
- Spoofing cost: Low (EXIF editor), but adds friction

### Evidence Status Values

| Status | Meaning | Visual | Implication |
|--------|---------|--------|-------------|
| **PASS** | Check performed, evidence consistent | ✓ Green | Positive signal |
| **FAIL** | Check performed, evidence inconsistent | ✗ Red | Red flag—possible manipulation |
| **UNAVAILABLE** | Check not possible (device/conditions) | — Gray | Reduces confidence ceiling, not suspicious |

### Confidence Calculation (MVP)

```
if any_check_failed:
    return SUSPICIOUS

match (hardware_pass, depth_pass):
    (true, true)  => HIGH      // Both pass = strong
    (true, false) => MEDIUM    // Hardware only
    (false, true) => MEDIUM    // Depth only (shouldn't happen on Pro)
    (false, false) => LOW
```

### Deferred Evidence Checks (Post-MVP)

These add value but require more implementation effort:
- **Sun angle:** Compare computed solar position to shadow direction
- **Barometric pressure:** Match reported pressure to GPS altitude
- **Gyro × optical flow:** Correlate device rotation with image motion (video)
- **360° environment scan:** Require user to pan device for parallax proof

---

## Functional Requirements

### Device & Attestation (MVP)

- FR1: App detects iPhone Pro device with LiDAR capability
- FR2: App generates cryptographic keys in Secure Enclave via `@expo/app-integrity`
- FR3: App requests DCAppAttest attestation from iOS (one-time device registration)
- FR4: Backend verifies DCAppAttest attestation object against Apple's service
- FR5: System assigns attestation level: secure_enclave or unverified

**Implementation Note:** DCAppAttest has two operations:
1. **Attestation** (one-time): `attestKeyAsync()` on first launch → registers device with backend
2. **Assertion** (per-capture): `generateAssertionAsync()` for each photo → proves capture came from attested device

### Capture Flow (MVP)

- FR6: App displays camera view with LiDAR depth overlay
- FR7: App captures photo via back camera
- FR8: App simultaneously captures LiDAR depth map via ARKit
- FR9: App records GPS coordinates if permission granted
- FR10: App captures device attestation signature for the capture

### Local Processing (MVP)

- FR11: App computes SHA-256 hash of photo before upload
- FR12: App compresses depth map (gzip float32 array)
- FR13: App constructs structured capture request with photo + depth + metadata

### Upload & Sync (MVP)

- FR14: App uploads capture via multipart POST (photo + depth_map + metadata JSON)
- FR15: App uses TLS 1.3 for all API communication
- FR16: App implements retry with exponential backoff on upload failure
- FR17: App stores captures in encrypted local storage when offline (Secure Enclave key)
- FR18: App auto-uploads pending captures when connectivity returns
- FR19: App displays pending upload status to user

### Evidence Generation (MVP)

- FR20: Backend verifies DCAppAttest attestation and records level
- FR21: Backend performs LiDAR depth analysis (variance, layers, edge coherence)
- FR22: Backend determines "is_likely_real_scene" from depth analysis
- FR23: Backend validates EXIF timestamp against server receipt time
- FR24: Backend validates device model is iPhone Pro (has LiDAR)
- FR25: Backend generates evidence package with all check results
- FR26: Backend calculates confidence level (HIGH/MEDIUM/LOW/SUSPICIOUS)

### C2PA Integration (MVP)

- FR27: Backend creates C2PA manifest with evidence summary
- FR28: Backend signs C2PA manifest with Ed25519 key (HSM-backed in production)
- FR29: Backend embeds C2PA manifest in photo file
- FR30: System stores both original and C2PA-embedded versions

### Verification Interface (MVP)

- FR31: Users can view capture verification via shareable URL
- FR32: Verification page displays confidence summary (HIGH/MEDIUM/LOW/SUSPICIOUS)
- FR33: Verification page displays depth analysis visualization
- FR34: Users can expand detailed evidence panel with per-check status
- FR35: Each check displays pass/fail with relevant metrics

### File Verification (MVP)

- FR36: Users can upload file to verification endpoint
- FR37: System computes hash and searches for matching capture
- FR38: If match found: display linked capture evidence
- FR39: If no match but C2PA manifest present: display manifest info with note
- FR40: If no match and no manifest: display "No provenance record found"

### Device Management (MVP)

- FR41: System generates device-level pseudonymous ID (Secure Enclave backed)
- FR42: Users can capture and verify without account (anonymous by default)
- FR43: Device registration stores attestation key ID and capability flags

### Privacy Controls (MVP)

- FR44: GPS stored at coarse level (city) by default in public view
- FR45: Users can opt-out of location (noted in evidence, not suspicious)
- FR46: Depth map stored but not publicly downloadable (only visualization)

#### Granular Metadata Controls

Users can configure what metadata accompanies each capture:

| Field | Options | Default |
|-------|---------|---------|
| Location | None / Coarse (city) / Precise | Coarse |
| Timestamp | None / Day only / Exact | Exact |
| Device Info | None / Model only / Full | Model only |
| Depth Map | Exclude / Include (Privacy Mode: analysis only) | Include |

**Evidence Impact:** Excluded fields are noted in evidence as "User opted out" (not marked suspicious). Confidence calculation adjusts based on available signals.

### Video Capture (MVP)

- FR47: App records video up to 15 seconds with LiDAR depth at 10fps
- FR48: App displays real-time edge-detection depth overlay during recording
- FR49: App computes frame hash chain (each frame hashes with previous)
- FR50: App generates attestation for complete or interrupted videos (checkpoint attestation)
- FR51: App collects same metadata for video as photos (GPS, device, timestamp)
- FR52: Backend verifies video hash chain integrity
- FR53: Backend analyzes depth consistency across video frames (temporal analysis)
- FR54: Backend generates C2PA manifest for video files
- FR55: Verification page displays video with playback and evidence

**Video Capture Technical Details:**
- **Duration:** Maximum 15 seconds (thermal and UX considerations)
- **Depth capture:** 10fps keyframes (every 3rd frame from 30fps video)
- **Hash chain:** Every frame (30fps) chained with previous frame's hash
- **Checkpoints:** Attestation checkpoints every 5 seconds for partial recovery
- **Overlay:** Edge-detection only (performance optimized vs full colormap)
- **File size:** ~30-45MB per 15s video (video + depth + chain + metadata)

### Privacy-First Capture (FR56-FR62)

- FR56: App provides "Privacy Mode" toggle in capture settings
- FR57: In Privacy Mode, app performs depth analysis locally (variance, layers, edge coherence)
- FR58: In Privacy Mode, app uploads only: hash(media) + depth_analysis_result + attestation_signature
- FR59: Backend accepts pre-computed depth analysis signed by attested device
- FR60: Backend stores hash + evidence without raw media (media never touches server)
- FR61: Verification page displays "Hash Verified" with note: "Original media not stored - verified by device attestation"
- FR62: Users can configure per-capture metadata: location (none/coarse/precise), timestamp (none/day/exact), device info (none/model/full)

**Privacy Mode Technical Details:**
- **Client-side analysis:** Same depth algorithm as server (variance, layers, coherence)
- **Trust model:** DCAppAttest signs hash + analysis; server trusts attested device
- **Upload size:** < 10KB (vs ~5MB for full capture)
- **Confidence:** HIGH achievable when hardware attestation + depth analysis both pass
- **Local storage:** Full media retained on device (user's control)

### Deferred Functional Requirements (Post-MVP)

| FR | Feature | Reason |
|----|---------|--------|
| D1 | Android Key Attestation verification | No Android in MVP |
| D2 | 360° environment scan capture | Complex UX |
| D3 | Gyro × optical flow analysis | Needs video |
| D4 | Sun angle verification | Solar API integration |
| D5 | Barometric pressure check | Weather API correlation |
| D6 | User accounts (passkey auth) | Device auth sufficient |
| D7 | Capture revocation | Needs user accounts |
| D8 | Raw sensor data download | Nice-to-have |

---

## Non-Functional Requirements

### Performance (MVP)

| Metric | Target | Notes |
|--------|--------|-------|
| Capture → processing complete | < 15s | Photo + depth analysis |
| Verification page load | < 1.5s FCP | Cached media via CDN |
| Upload throughput | 10 MB/s minimum | Photo (~3MB) + depth map (~1MB compressed) |
| Depth analysis computation | < 5s | Variance, layers, edge coherence |

### Security

**Cryptographic Choices:**
| Component | Algorithm | Rationale |
|-----------|-----------|-----------|
| Photo hash | SHA-256 | Industry standard, collision-resistant |
| Device signing | Ed25519 | Fast, small signatures, Secure Enclave compatible |
| C2PA manifest | Per C2PA spec | Interoperability |
| Server key storage | HSM-backed | Private key never in memory |
| Device attestation | DCAppAttest | iOS Secure Enclave root of trust |

**Key Management (MVP):**
- Server signing key: Generate in HSM, never export, rotate yearly
- Device attestation keys: Generated in iOS Secure Enclave, not extractable
- Certificate revocation list maintained, embedded in C2PA manifest

**Transport Security:**
- TLS 1.3 required for all API endpoints
- Certificate pinning in mobile app (post-MVP)
- Signed URLs for media access, expire in 1 hour

**Threat Model Summary (MVP):**

| Attack | Defense | Evidence Type |
|--------|---------|---------------|
| Screenshot AI image | Only in-app captures accepted | App integrity |
| Frida/jailbreak hook | DCAppAttest detects compromised devices | Hardware |
| Photo of screen/print | LiDAR shows flat uniform depth | Depth Analysis |
| Photo of flat image | LiDAR shows single depth layer | Depth Analysis |
| EXIF manipulation | Server timestamp comparison | Metadata |
| MITM | TLS 1.3 + hash verification | Transport |

**Acknowledged Limitations:**
- Cannot detect perfectly constructed physical 3D scenes
- Cannot defeat nation-state hardware attacks
- Cannot prove semantic truth (what depicted actually happened)
- Cannot detect pre-capture manipulation (staged physical scenes)
- LiDAR can be fooled by real 3D replicas (prohibitively expensive)

### Scalability

- **MVP:** Single backend instance, vertical scaling
- **Post-MVP:** Horizontal scaling, read replicas for Postgres, CDN for media

### Reliability

| Metric | Target |
|--------|--------|
| API availability | 99.5% (MVP), 99.9% (production) |
| Data durability | 99.999999999% (11 nines, via S3) |
| Offline capture | Must not lose captures |

### Integration

**C2PA Ecosystem:**
- Uses c2pa-rs and CAI SDK for manifest generation
- Interoperable with Content Credentials ecosystem (Adobe, Google Photos, news orgs)
- Publishable methodology (security through robust design, not obscurity)

---

## Technical Reference

### Data Model (MVP)

**Core Entities:**
- `devices`: id, platform (ios), model, attestation_level, attestation_key_id, has_lidar
- `captures`: id, device_id, photo_hash, depth_map_key, evidence_package (JSONB), confidence_level, status
- `verification_logs`: capture_id, action, client_ip, timestamp (analytics)

**Note:** User accounts deferred to post-MVP.

### API Endpoints (MVP)

- `POST /api/v1/devices` - Register device with DCAppAttest
- `POST /api/v1/captures` - Create capture (multipart: photo + depth_map + metadata JSON)
- `GET /api/v1/captures/:id` - Get capture with evidence and depth visualization
- `POST /api/v1/verify-file` - Hash lookup for uploaded file

### Authentication Model (MVP)

**Device-Based Identity (Anonymous)**
- Device generates Secure Enclave-backed keypair on first launch
- All API requests signed with device key (Ed25519)
- No user accounts required; device ID is pseudonymous
- Captures linked to device, not user identity
- Rate limiting by device ID + IP

**API Authentication Flow (MVP):**

| Endpoint | Auth |
|----------|------|
| `POST /devices` | DCAppAttest attestation object |
| `POST /captures` | Device signature (Ed25519) |
| `GET /captures/:id` | None (public) |
| `POST /verify-file` | None (public) |

**Security Considerations:**
- Device keys bound to Secure Enclave (hardware-backed)
- No session tokens needed (stateless device auth)
- No OAuth/social login (reduces attack surface, maintains privacy)
- Rate limiting: 10 captures/hour/device, 100 verifications/hour/IP

**Deferred (Post-MVP):** User accounts with passkey authentication for multi-device gallery, capture revocation, data export.

### Tech Stack

**iOS App (Native Swift):**
- Swift 5.9+ / SwiftUI
- Minimum iOS 15.0 (all iPhone Pro with LiDAR support this)
- Direct OS framework usage for maximum security posture:
  - **DeviceCheck**: DCAppAttest for hardware attestation
  - **CryptoKit**: SHA-256 hashing, AES-GCM encryption, Secure Enclave keys
  - **ARKit**: Unified RGB + LiDAR depth capture (single ARFrame)
  - **Metal**: Real-time depth visualization (60fps GPU-native)
  - **Foundation/URLSession**: Background uploads with certificate pinning
  - **Security/Keychain**: Hardware-backed key storage

**Note:** Native architecture chosen over React Native for:
- Smaller attack surface (no JS bridge, no third-party native modules)
- Direct Secure Enclave access (signing keys never leave hardware boundary)
- Perfect camera/depth synchronization (ARKit provides both in single frame)
- Background upload reliability (iOS continues even if app terminated)
- Auditable security (single language, direct OS API calls)

**Swift Package Dependencies:**
| Package | Purpose | Notes |
|---------|---------|-------|
| None required | Direct OS frameworks | Minimal dependency footprint |

**Reference Implementation:** Expo/React Native code retained in `apps/mobile/` for feature parity testing during development.

**Backend:**
- Rust 1.82+ + Axum 0.8.x
- SQLx 0.8 + PostgreSQL 16
- c2pa-rs 0.51.x (official C2PA SDK)
- Tokio, Serde, ed25519-dalek
- aws-sdk-s3 for storage

**Verification Frontend:**
- Next.js 16 (Turbopack, App Router, React 19)
- TailwindCSS, TypeScript

**Infrastructure:**
- PostgreSQL 16, S3-compatible storage
- AWS KMS or HashiCorp Vault (production keys)
- CloudFront CDN

---

## Open Questions

### Technical (MVP)
- Q1: LiDAR depth map storage format and compression (gzip float32 baseline, ~1MB compressed?)
- Q2: Depth analysis thresholds tuning (variance > 0.5, layers >= 3, coherence > 0.7)
- Q3: ARKit depth capture API specifics (AVDepthData vs ARFrame.sceneDepth)

### Product (MVP)
- Q4: Non-Pro iPhone user messaging ("This app requires iPhone Pro for LiDAR")
- Q5: Depth visualization UX on verification page (heatmap? point cloud? overlay?)
- Q6: Liability for "HIGH confidence" assessments (need legal review)

### Strategic
- Q7: Become C2PA CA or rely on existing?
- Q8: When to expand to Android (post-MVP validation metrics?)
- Q9: Open source timing and methodology transparency

---

_This PRD captures the essence of rial. MVP - cryptographically-attested, LiDAR-verified photo provenance for iPhone Pro devices. Hardware trust + depth analysis provides graduated evidence strength rather than false binary certainty._

_Created through collaborative discovery between Luca and AI facilitator. Updated for MVP scope (iPhone Pro only, photo only, LiDAR depth as primary signal)._

---

## References

### Platform Documentation (MVP Focus)

1. **Apple DCAppAttest** - [Establishing Your App's Integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) - iOS 14.0+ hardware attestation using Secure Enclave
2. **Apple DeviceCheck Framework** - [DeviceCheck](https://developer.apple.com/documentation/devicecheck/) - Device integrity and app attestation services
3. **ARKit Depth API** - [Capturing Depth Using the LiDAR Camera](https://developer.apple.com/documentation/arkit/arkit_in_ios/environmental_analysis/capturing_depth_using_the_lidar_camera) - LiDAR depth capture on iPhone Pro
4. **AVDepthData** - [AVDepthData](https://developer.apple.com/documentation/avfoundation/avdepthdata) - Depth data from camera capture

### Standards & Specifications

5. **C2PA Specification** - [Coalition for Content Provenance and Authenticity](https://c2pa.org/specifications/specifications/2.0/specs/C2PA_Specification.html) - Open technical standard for content provenance
6. **Content Credentials** - [Content Authenticity Initiative](https://contentcredentials.org/) - Implementation guidance and ecosystem tools
7. **c2pa-rs** - [Rust SDK for C2PA](https://github.com/contentauth/c2pa-rs) - Reference implementation for manifest creation/verification

### Security Research

8. **OWASP Mobile Security** - [Mobile Application Security](https://owasp.org/www-project-mobile-app-security/) - Security best practices for mobile applications

### Competitive Landscape

9. **Truepic** - [Controlled Capture](https://truepic.com/) - Competitor in authenticated media capture space
10. **ProofMode** - [Guardian Project](https://guardianproject.info/apps/org.witness.proofmode/) - Open-source provenance for human rights documentation
11. **Serelay** - [Image Authentication](https://www.serelay.com/) - Enterprise media authentication platform

### Deferred Platform Documentation (Post-MVP)

12. **Android Key Attestation** - [Verifying hardware-backed key pairs](https://developer.android.com/privacy-and-security/security-key-attestation) - For Android expansion
13. **Android StrongBox Keymaster** - [Hardware Security Module](https://source.android.com/docs/security/best-practices/hardware) - For Android expansion
