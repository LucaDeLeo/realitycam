# RealityCam - Product Requirements Document

**Author:** Luca
**Date:** 2025-11-21
**Version:** 1.0

---

## Executive Summary

RealityCam is a mobile camera app providing cryptographically-attested, physics-verified media provenance. It shows viewers not just "this came from a camera" but "here's the strength of evidence that this came from THIS environment at THIS moment."

The core insight: Provenance claims are only as strong as their weakest assumption. A software-only hash proves nothing if the software layer is compromised. Hardware attestation must be the foundation, not a later enhancement.

**What this is NOT:**
- Not an "AI detector" or "deepfake detector"
- Not a claim of absolute truth—we provide *evidence strength*, not binary verification
- Not a social platform

**Standards alignment:** C2PA / Content Credentials for interoperability with ecosystem tools (Adobe, Google Photos, news organizations).

### What Makes This Special

**Graduated Evidence, Not Binary Trust.** Unlike competitors offering simple "verified/not verified" stamps, RealityCam provides a layered evidence hierarchy—from hardware-rooted attestation down to metadata consistency. Users see exactly WHY they should trust content and at what confidence level.

**Physics as Proof.** We don't just sign files; we cross-check sun angles against GPS/timestamp, verify 3D scene depth with LiDAR, and correlate sensor data with optical flow. Faking our evidence requires manipulating physical reality, not just software.

**Transparency Over Security Theater.** We explicitly show what we CAN'T detect. When a check is unavailable, we say so. When evidence is weak, we communicate that. This honesty builds genuine trust.

---

## Project Classification

**Technical Type:** mobile_app
**Domain:** general (security/cryptography focus)
**Complexity:** medium

This is a multi-component system:
- **Mobile App** (React Native/Expo): Secure capture with hardware attestation
- **Backend** (Rust/Axum): Evidence processing, C2PA manifest generation
- **Verification Web** (Next.js): Public verification interface

The system requires deep integration with platform-specific security features (Android StrongBox, iOS Secure Enclave) and implements novel physics-based verification algorithms.

---

## Success Criteria

### Primary Success Indicators

1. **Hardware attestation adoption** - >80% of captures from hardware-attested devices
2. **Evidence completeness** - >50% of captures include environment scan (360° pan)
3. **Verification engagement** - Verification page bounce rate <30%
4. **Evidence panel exploration** - >20% of viewers expand detailed evidence view
5. **Expert adoption** - >1% download raw evidence packages

### Phase 0 (Hackathon) Success

- [ ] Hardware attestation working on Pixel 6+
- [ ] End-to-end flow: capture → verify URL → view evidence
- [ ] Verification page clearly shows attestation status
- [ ] Demo-able in 5 minutes

### Long-term Success

- Adoption by at least one newsroom for verification workflow
- Cited in at least one published investigation
- C2PA conformance certification achieved

---

## Product Scope

### MVP - Minimum Viable Product

**Mobile App (Phase 0):**
- Basic camera capture (single photo)
- SHA-256 hash computation
- Android Key Attestation for Pixel 6+ (native module)
- Upload with attestation data
- Receive and display verify URL

**Backend (Phase 0):**
- `POST /captures`: receive upload, verify attestation, store
- `GET /captures/:id`: return capture data and evidence
- `POST /verify-file`: hash lookup
- Basic evidence package with Tier 1 (attestation) + Tier 4 (EXIF)
- JWS-signed certificate

**Verification Web (Phase 0):**
- Summary view with confidence level
- Basic evidence panel
- Hardware attestation status display

**Explicit Phase 0 Limitations:**
- "Phase 0 prototype—limited evidence checks"
- "No environment scan—3D verification unavailable"

### Growth Features (Post-MVP)

**Phase 0.5 Additions:**
- iOS DCAppAttest support
- Scan mode UX (360° pan)
- Gyro × optical flow consistency check (Tier 3)
- Sun angle verification (Tier 2)
- Context video storage and viewer
- Full confidence level logic

**Phase 1 Additions:**
- LiDAR depth analysis (iPhone Pro)
- Multi-camera lighting consistency
- Full C2PA manifest embedding via c2pa-rs
- Expert panel with raw data download
- User accounts and capture management
- Barometric pressure check
- Certificate pinning in mobile app

### Vision (Future)

**Phase 2 - Ecosystem & Hardening:**
- Open source release (transparency)
- Third-party verification tool (independent hash/signature check)
- Browser extension for inline verification
- Integration with news org verification workflows
- Advanced ML-based checks (active research)
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

**Enterprise/B2B:**
- White-label licensing (Phase 2+ consideration)
- Self-hosted backend deployment
- SLA-backed enterprise support tiers

**Hardware:**
- Custom hardware devices or camera modules
- Support for devices without TEE/Secure Enclave (software-only attestation is allowed but flagged)

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

**UC1: Capture with Environmental Context**
1. User opens app, enters "capture mode"
2. App prompts: "Scan your environment" — user does slow 360° pan (10-15s)
3. User "locks" on subject, takes photo/video
4. App computes: target capture + environment context + sensor traces
5. Upload includes all evidence; user receives shareable link

**UC2: Quick Capture (Degraded Evidence)**
1. User takes photo without environment scan
2. Evidence tier reduced (no 3D-ness proof)
3. Clear indication: "Environment scan: not performed"

**UC3: Verify Received Media**
1. Recipient opens verification link
2. Sees confidence summary + expandable evidence panel
3. Can download raw evidence package for independent analysis

**UC4: Upload External File for Hash Lookup**
1. User uploads file to verification page
2. System checks if hash matches any registered capture
3. If match: show evidence. If no match: "No record found"

### Evidence Legibility Scales with Viewer Expertise

- **Casual viewer:** confidence summary + primary evidence type
- **Journalist:** expandable panel with pass/fail/unavailable per check
- **Forensic analyst:** raw data export, methodology documentation

---

## mobile_app Specific Requirements

### Platform Support

**iOS:**
- iPhone SE 2+ for DCAppAttest support
- iPhone Pro/iPad Pro for LiDAR depth analysis
- Minimum iOS version: iOS 14.0 (DCAppAttest introduced August 2020)

**Android:**
- Pixel 6+ for StrongBox hardware attestation
- Samsung Knox devices supported
- Minimum Android API level: 28 (Android 9.0+, StrongBox introduced)

### Device Capabilities

Required sensors and features:
- Camera (back, front; wide/tele where available)
- Gyroscope (100Hz minimum sampling)
- Accelerometer (100Hz minimum sampling)
- Magnetometer (compass)
- GPS (optional, but enables physics checks)
- Barometer (optional, enables altitude verification)
- LiDAR (optional, iPhone Pro only)

### Offline Mode

- Store media + metadata in encrypted local storage
- Encryption key: hardware-backed if attestation available
- Mark as "Pending upload"
- Auto-upload when connectivity returns
- Display warning: "Evidence timestamping delayed—server receipt time will differ from capture time"

---

## Innovation & Novel Patterns

### The Evidence Hierarchy

This is the core innovation—evidence tiers ordered by cost-to-spoof:

**Tier 1: Hardware-Rooted (highest)**
- Device identity attested by TEE (Android StrongBox) or Secure Enclave (iOS)
- Key generated in HSM
- Spoofing cost: Custom silicon / firmware exploit

**Tier 2: Physics-Constrained**
- Sun angle consistency (computed vs observed shadow direction)
- LiDAR depth (3D geometry vs flat surface)
- Barometric pressure (matches GPS altitude)
- Environment 3D-ness (360° scan parallax)
- Spoofing cost: Building physical 3D scene, pressure chamber

**Tier 3: Cross-Modal Consistency**
- Gyroscope × optical flow correlation
- Multi-camera lighting consistency
- Audio reverb × room geometry (video)
- Accelerometer × motion blur
- Spoofing cost: Coordinated synthetic data generation

**Tier 4: Metadata Consistency (lowest)**
- EXIF timestamp within tolerance
- Device model string verification
- Resolution/lens capability match
- App integrity signature
- Spoofing cost: EXIF editor, API hooking

### Evidence Status Values

| Status | Meaning | Visual | Implication |
|--------|---------|--------|-------------|
| **PASS** | Check performed, evidence consistent | ✓ Green | Positive signal |
| **FAIL** | Check performed, evidence inconsistent | ✗ Red | Red flag—possible manipulation |
| **UNAVAILABLE** | Check not possible (device/conditions) | — Gray | Reduces confidence ceiling, not suspicious |
| **SKIPPED** | User chose not to perform (e.g., no env scan) | ○ Yellow | User choice, noted in evidence |

### Validation Approach

Confidence level logic:
- **HIGH**: Tier 1 pass + at least 2 Tier 2 passes + no fails
- **MEDIUM**: Tier 1 pass OR 2+ Tier 2 passes, no fails
- **LOW**: Only Tier 3-4 passes, no Tier 1-2
- **INSUFFICIENT**: Major checks failed or almost all unavailable
- **SUSPICIOUS**: Any check FAILED (not unavailable—actually inconsistent)

---

## Functional Requirements

### Device & Attestation

- FR1 `[Phase 0]`: App can detect device hardware attestation capability (StrongBox/Secure Enclave/none)
- FR2 `[Phase 0]`: App can generate cryptographic keys in hardware-backed storage
- FR3 `[Phase 0]`: App can request attestation certificate chain from platform
- FR4 `[Phase 0]`: Backend can verify Android Key Attestation certificate chains against Google's root
- FR5 `[Phase 0.5]`: Backend can verify iOS DCAppAttest assertions against Apple's service
- FR6 `[Phase 0]`: System assigns attestation level to each device (hardware_strongbox, hardware_secure_enclave, software_only, unknown)

### Capture Flow

- FR7 `[Phase 0.5]`: Users can enter scan mode to record 360° environmental context
- FR8 `[Phase 0.5]`: App records video stream from all available cameras during scan
- FR9 `[Phase 0.5]`: App records gyroscope trace at 100Hz minimum during scan
- FR10 `[Phase 0.5]`: App records accelerometer trace at 100Hz minimum during scan
- FR11 `[Phase 0.5]`: App records magnetometer readings during scan
- FR12 `[Phase 0]`: App records GPS coordinates if permission granted
- FR13 `[Phase 1]`: App records barometric pressure if sensor available
- FR14 `[Phase 1]`: App records LiDAR depth frames if sensor available
- FR15 `[Phase 0.5]`: Users can "lock" to end scan phase and frame target subject
- FR16 `[Phase 0]`: Users can capture target photo or video after scan
- FR17 `[Phase 0.5]`: App records sensor burst during target capture
- FR18 `[Phase 0]`: Users can perform quick capture without environment scan (degraded evidence)

### Local Processing

- FR19 `[Phase 0]`: App computes SHA-256 hash of target media before upload
- FR20 `[Phase 0.5]`: App computes SHA-256 hash of context package before upload
- FR21 `[Phase 0.5]`: App computes local gyro × optical flow consistency estimate
- FR22 `[Phase 1]`: App computes local LiDAR flatness analysis if available
- FR23 `[Phase 0]`: App constructs structured capture request with device, capture, and local check data

### Upload & Sync

- FR24 `[Phase 0]`: App uploads capture via multipart POST (target media + context + JSON request)
- FR25 `[Phase 0]`: App uses TLS 1.3 for all API communication
- FR26 `[Phase 0]`: App implements retry with exponential backoff on upload failure
- FR27 `[Phase 0]`: App stores captures in encrypted local storage when offline
- FR28 `[Phase 0]`: App auto-uploads pending captures when connectivity returns
- FR29 `[Phase 0]`: App displays pending upload status to user

### Evidence Generation (Backend)

- FR30 `[Phase 0]`: Backend verifies attestation claims and downgrades level if verification fails *(depends: FR3, FR4)*
- FR31 `[Phase 0.5]`: Backend computes sun angle verification (expected vs observed shadow direction) *(depends: FR12)*
- FR32 `[Phase 1]`: Backend performs LiDAR depth analysis for flatness detection *(depends: FR14)*
- FR33 `[Phase 1]`: Backend performs barometric consistency check against GPS altitude *(depends: FR12, FR13)*
- FR34 `[Phase 0.5]`: Backend analyzes 360° scan for parallax (environment 3D-ness) *(depends: FR7, FR8)*
- FR35 `[Phase 0.5]`: Backend performs gyro × optical flow consistency check *(depends: FR9, FR21)*
- FR36 `[Phase 1]`: Backend performs multi-camera lighting consistency check if multiple cameras used
- FR37 `[Phase 0]`: Backend validates EXIF timestamp against server receipt time
- FR38 `[Phase 0]`: Backend validates device model across EXIF, platform API, and capabilities
- FR39 `[Phase 0]`: Backend generates comprehensive evidence package with all check results *(depends: FR30, FR37, FR38)*

### C2PA Integration

- FR40 `[Phase 0]`: Backend creates C2PA manifest with claim generator, capture actions, evidence summary *(depends: FR39)*
- FR41 `[Phase 0]`: Backend signs C2PA manifest with Ed25519 key (HSM-backed in production) *(depends: FR40)*
- FR42 `[Phase 1]`: Backend embeds C2PA manifest in media file *(depends: FR41)*
- FR43 `[Phase 0]`: System stores both original and C2PA-embedded versions

### Verification Interface

- FR44 `[Phase 0]`: Users can view capture verification via shareable URL
- FR45 `[Phase 0]`: Verification page displays confidence summary (HIGH/MEDIUM/LOW/INSUFFICIENT/SUSPICIOUS)
- FR46 `[Phase 0]`: Verification page displays primary evidence type and captured metadata
- FR47 `[Phase 0]`: Users can expand detailed evidence panel with per-check status
- FR48 `[Phase 0]`: Each check displays pass/fail/unavailable/skipped with relevant metrics
- FR49 `[Phase 1]`: Users can access expert panel for raw sensor data download
- FR50 `[Phase 1]`: Users can download evidence computation logs and methodology documentation
- FR51 `[Phase 1]`: Users can view raw C2PA manifest (JUMBF)
- FR52 `[Phase 0.5]`: Users can scrub through 360° context video if environment scan performed *(depends: FR7)*
- FR53 `[Phase 0.5]`: Context viewer shows parallax visualization highlighting depth cues *(depends: FR34)*

### File Verification

- FR54 `[Phase 0]`: Users can upload file to verification endpoint
- FR55 `[Phase 0]`: System computes hash and searches for matching capture
- FR56 `[Phase 0]`: If match found: display linked capture evidence
- FR57 `[Phase 0]`: If no match but C2PA manifest present: display manifest info with note
- FR58 `[Phase 0]`: If no match and no manifest: display "No provenance record found"

### User & Device Management

- FR59 `[Phase 0]`: System generates device-level pseudonymous ID (hardware-attested or random UUID) *(depends: FR1, FR2)*
- FR60 `[Phase 0]`: Users can capture and verify without account (anonymous by default)
- FR61 `[Phase 1]`: Users can create optional account with passkey-based authentication *(depends: FR59)*
- FR62 `[Phase 1]`: Users can link multiple devices to account *(depends: FR61)*
- FR63 `[Phase 1]`: Users can view gallery of their captures *(depends: FR61)*
- FR64 `[Phase 1]`: Users can revoke/withdraw captures *(depends: FR61)*
- FR65 `[Phase 1]`: Withdrawn captures display revocation notice on verification page *(depends: FR64)*

### Privacy Controls

- FR66 `[Phase 0]`: GPS stored at coarse level (city) by default in public view
- FR67 `[Phase 0]`: Users can opt-out of location (reduces confidence, not suspicious)
- FR68 `[Phase 0]`: Environment context stored locally until explicit capture action
- FR69 `[Phase 1]`: Users can export all their data *(depends: FR61)*
- FR70 `[Phase 1]`: Users can delete account and all associated captures *(depends: FR61)*

---

## Non-Functional Requirements

### Performance

| Metric | Target | Notes |
|--------|--------|-------|
| Capture → processing complete | < 30s | Includes evidence computation |
| Verification page load | < 1.5s FCP | Cached media via CDN |
| Upload throughput | 10 MB/s minimum | Typical capture + context ~5-15 MB |
| Evidence computation | < 10s | Parallelized across tiers |

### Security

**Cryptographic Choices:**
| Component | Algorithm | Rationale |
|-----------|-----------|-----------|
| Media hash | SHA-256 | Industry standard, collision-resistant |
| Certificate signing | Ed25519 | Fast, small signatures, no ECDSA pitfalls |
| C2PA manifest | Per C2PA spec | Interoperability |
| Server key storage | HSM-backed | Private key never in memory |
| Device attestation | Platform-native | Hardware root of trust |

**Key Management:**
- Server signing key: Generate in HSM, never export, rotate yearly
- Device attestation keys: Generated per-device in hardware, not extractable
- Certificate revocation list maintained, embedded in C2PA manifest

**Transport Security:**
- TLS 1.3 required for all API endpoints
- Certificate pinning in mobile app (Phase 1)
- Signed URLs for media access, expire in 1 hour

**Threat Model Summary:**

| Attack | Defense | Tier |
|--------|---------|------|
| Screenshot AI image | Only in-app captures accepted | App |
| Frida/Xposed hook | Hardware attestation detects rooted/hooked | Tier 1 |
| Physical replay | 360 scan reveals flat surface; LiDAR no depth | Tier 2 |
| Time/location spoof | Sun angle + GPS + timestamp cross-check | Tier 2 |
| Coordinated sensor spoof | Hardware attestation + cross-modal checks | Tier 1+3 |
| MITM | TLS 1.3 + cert pinning + hash verification | Transport |

**Acknowledged Limitations:**
- Cannot detect perfectly constructed physical scenes
- Cannot defeat nation-state hardware attacks
- Cannot prove semantic truth (what depicted actually happened)
- Cannot detect pre-capture manipulation (staged scenes)

### Scalability

- **Phase 0:** Single backend instance, vertical scaling
- **Phase 1+:** Horizontal scaling, read replicas for Postgres, CDN for media

### Reliability

| Metric | Target |
|--------|--------|
| API availability | 99.5% (hackathon), 99.9% (production) |
| Data durability | 99.999999999% (11 nines, via S3) |
| Offline capture | Must not lose captures |

### Integration

**C2PA Ecosystem:**
- Uses c2pa-rs and CAI SDK for manifest generation
- Interoperable with Content Credentials ecosystem (Adobe, Google Photos, news orgs)
- Publishable methodology (security through robust design, not obscurity)

---

## Technical Reference

### Data Model

**Core Entities:**
- `devices`: id, user_id, platform, model, attestation_level, attestation_key_id
- `captures`: id, device_id, target_media_hash, context_package_key, evidence_package (JSONB), confidence_level, status
- `users`: id, email, passkey_credential_id (optional, Phase 1)
- `verification_logs`: capture_id, action, client_ip, timestamp (analytics)

### API Endpoints

- `POST /api/v1/captures` - Create capture (multipart: media + context + JSON)
- `GET /api/v1/captures/:id` - Get capture with evidence
- `POST /api/v1/verify-file` - Hash lookup for uploaded file
- `GET /api/v1/captures/:id/evidence/raw` - Download raw evidence package (ZIP)

### Authentication Model

**Phase 0: Device-Based Identity (Anonymous)**
- Device generates hardware-attested keypair on first launch
- All API requests signed with device key (JWT or similar)
- No user accounts required; device ID is pseudonymous
- Captures linked to device, not user identity
- Rate limiting by device ID + IP

**Phase 1: Optional User Accounts (Passkey-Based)**
- WebAuthn/Passkey registration and authentication
- No passwords stored; relies on platform authenticators (Face ID, fingerprint, security keys)
- Account creation optional; users can continue anonymously
- Account linking enables:
  - Multi-device capture gallery
  - Capture revocation
  - Data export (GDPR compliance)
  - Account deletion

**API Authentication Flow:**

| Endpoint | Phase 0 Auth | Phase 1 Auth |
|----------|--------------|--------------|
| `POST /captures` | Device signature | Device signature |
| `GET /captures/:id` | None (public) | None (public) |
| `POST /verify-file` | None (public) | None (public) |
| `GET /captures/:id/evidence/raw` | None (public) | None (public) |
| `POST /auth/passkey/register` | N/A | Device signature + WebAuthn |
| `POST /auth/passkey/authenticate` | N/A | WebAuthn assertion |
| `GET /user/captures` | N/A | Session token |
| `DELETE /user/captures/:id` | N/A | Session token |

**Security Considerations:**
- Device keys bound to hardware attestation level
- Session tokens: short-lived (15 min), refresh via passkey re-auth
- No OAuth/social login (reduces attack surface, maintains privacy)
- Rate limiting: 10 captures/hour/device, 100 verifications/hour/IP

### Tech Stack

**Mobile App:**
- React Native (Expo prebuild)
- react-native-vision-camera v4
- expo-sensors, expo-crypto
- Native modules for Key Attestation (Kotlin/Swift)

**Backend:**
- Rust + Axum 0.8
- SQLx 0.8 + Postgres
- c2pa-rs 0.35
- Tokio, Serde
- aws-sdk-s3 or rust-s3

**Verification Frontend:**
- Next.js 14 (App Router)
- React, TailwindCSS, TypeScript

**Infrastructure:**
- Postgres 16, Redis, S3-compatible storage
- AWS KMS or HashiCorp Vault (production keys)
- Cloudflare CDN

---

## Open Questions

### Technical
- Q1: Sun angle verification robustness for indoor/overcast scenes
- Q2: LiDAR storage/bandwidth trade-off (subsample? compress?)
- Q3: Gyro × optical flow false positive/negative rates

### Product
- Q4: Acceptable UX friction for scan mode vs user abandonment
- Q5: Gallery import with degraded confidence (v1: No)
- Q6: Liability for "HIGH confidence" assessments (need legal review)

### Strategic
- Q7: Become C2PA CA or rely on existing?
- Q8: Open source timing and methodology transparency

---

_This PRD captures the essence of RealityCam - cryptographically-attested, physics-verified media provenance that provides graduated evidence strength rather than false binary certainty._

_Created through collaborative discovery between Luca and AI facilitator._

---

## References

### Platform Documentation

1. **Apple DCAppAttest** - [Establishing Your App's Integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) - iOS 14.0+ hardware attestation using Secure Enclave
2. **Apple DeviceCheck Framework** - [DeviceCheck](https://developer.apple.com/documentation/devicecheck/) - Device integrity and app attestation services
3. **Android Key Attestation** - [Verifying hardware-backed key pairs](https://developer.android.com/privacy-and-security/security-key-attestation) - Hardware-backed key attestation for Android
4. **Android StrongBox Keymaster** - [Hardware Security Module](https://source.android.com/docs/security/best-practices/hardware) - Dedicated secure processor for key storage (API 28+)

### Standards & Specifications

5. **C2PA Specification** - [Coalition for Content Provenance and Authenticity](https://c2pa.org/specifications/specifications/2.0/specs/C2PA_Specification.html) - Open technical standard for content provenance
6. **Content Credentials** - [Content Authenticity Initiative](https://contentcredentials.org/) - Implementation guidance and ecosystem tools
7. **c2pa-rs** - [Rust SDK for C2PA](https://github.com/contentauth/c2pa-rs) - Reference implementation for manifest creation/verification

### Security Research

8. **OWASP Mobile Security** - [Mobile Application Security](https://owasp.org/www-project-mobile-app-security/) - Security best practices for mobile applications
9. **Sun Position Algorithm** - [NOAA Solar Calculator](https://gml.noaa.gov/grad/solcalc/) - Reference for sun angle verification calculations

### Competitive Landscape

10. **Truepic** - [Controlled Capture](https://truepic.com/) - Competitor in authenticated media capture space
11. **ProofMode** - [Guardian Project](https://guardianproject.info/apps/org.witness.proofmode/) - Open-source provenance for human rights documentation
12. **Serelay** - [Image Authentication](https://www.serelay.com/) - Enterprise media authentication platform
