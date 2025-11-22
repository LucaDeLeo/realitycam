# RealityCam - Epic Breakdown

**Author:** Luca
**Date:** 2025-11-21
**Project Level:** medium complexity
**Target Scale:** Multi-component system (Mobile App + Backend + Verification Web)

---

## Overview

This document provides the complete epic and story breakdown for RealityCam, decomposing the requirements from the [PRD](./prd.md) into implementable stories.

**Living Document Notice:** This is the initial version. It will be updated after UX Design and Architecture workflows add interaction and technical details to stories.

<!-- Epics summary will be added after Step 2 -->

---

## Functional Requirements Inventory

### Phase 0 (MVP - Hackathon Target)

| FR | Description | Category |
|----|-------------|----------|
| FR1 | App can detect device hardware attestation capability (StrongBox/Secure Enclave/none) | Device & Attestation |
| FR2 | App can generate cryptographic keys in hardware-backed storage | Device & Attestation |
| FR3 | App can request attestation certificate chain from platform | Device & Attestation |
| FR4 | Backend can verify Android Key Attestation certificate chains against Google's root | Device & Attestation |
| FR6 | System assigns attestation level to each device | Device & Attestation |
| FR12 | App records GPS coordinates if permission granted | Capture Flow |
| FR16 | Users can capture target photo or video after scan | Capture Flow |
| FR18 | Users can perform quick capture without environment scan (degraded evidence) | Capture Flow |
| FR19 | App computes SHA-256 hash of target media before upload | Local Processing |
| FR23 | App constructs structured capture request with device, capture, and local check data | Local Processing |
| FR24 | App uploads capture via multipart POST | Upload & Sync |
| FR25 | App uses TLS 1.3 for all API communication | Upload & Sync |
| FR26 | App implements retry with exponential backoff on upload failure | Upload & Sync |
| FR27 | App stores captures in encrypted local storage when offline | Upload & Sync |
| FR28 | App auto-uploads pending captures when connectivity returns | Upload & Sync |
| FR29 | App displays pending upload status to user | Upload & Sync |
| FR30 | Backend verifies attestation claims and downgrades level if verification fails | Evidence Generation |
| FR37 | Backend validates EXIF timestamp against server receipt time | Evidence Generation |
| FR38 | Backend validates device model across EXIF, platform API, and capabilities | Evidence Generation |
| FR39 | Backend generates comprehensive evidence package with all check results | Evidence Generation |
| FR40 | Backend creates C2PA manifest with claim generator, capture actions, evidence summary | C2PA Integration |
| FR41 | Backend signs C2PA manifest with Ed25519 key (HSM-backed in production) | C2PA Integration |
| FR43 | System stores both original and C2PA-embedded versions | C2PA Integration |
| FR44 | Users can view capture verification via shareable URL | Verification Interface |
| FR45 | Verification page displays confidence summary (HIGH/MEDIUM/LOW/INSUFFICIENT/SUSPICIOUS) | Verification Interface |
| FR46 | Verification page displays primary evidence type and captured metadata | Verification Interface |
| FR47 | Users can expand detailed evidence panel with per-check status | Verification Interface |
| FR48 | Each check displays pass/fail/unavailable/skipped with relevant metrics | Verification Interface |
| FR54 | Users can upload file to verification endpoint | File Verification |
| FR55 | System computes hash and searches for matching capture | File Verification |
| FR56 | If match found: display linked capture evidence | File Verification |
| FR57 | If no match but C2PA manifest present: display manifest info with note | File Verification |
| FR58 | If no match and no manifest: display "No provenance record found" | File Verification |
| FR59 | System generates device-level pseudonymous ID (hardware-attested or random UUID) | User & Device Management |
| FR60 | Users can capture and verify without account (anonymous by default) | User & Device Management |
| FR66 | GPS stored at coarse level (city) by default in public view | Privacy Controls |
| FR67 | Users can opt-out of location (reduces confidence, not suspicious) | Privacy Controls |
| FR68 | Environment context stored locally until explicit capture action | Privacy Controls |

### Phase 0.5 (Post-Hackathon Enhancements)

| FR | Description | Category |
|----|-------------|----------|
| FR5 | Backend can verify iOS DCAppAttest assertions against Apple's service | Device & Attestation |
| FR7 | Users can enter scan mode to record 360° environmental context | Capture Flow |
| FR8 | App records video stream from all available cameras during scan | Capture Flow |
| FR9 | App records gyroscope trace at 100Hz minimum during scan | Capture Flow |
| FR10 | App records accelerometer trace at 100Hz minimum during scan | Capture Flow |
| FR11 | App records magnetometer readings during scan | Capture Flow |
| FR15 | Users can "lock" to end scan phase and frame target subject | Capture Flow |
| FR17 | App records sensor burst during target capture | Capture Flow |
| FR20 | App computes SHA-256 hash of context package before upload | Local Processing |
| FR21 | App computes local gyro × optical flow consistency estimate | Local Processing |
| FR31 | Backend computes sun angle verification (expected vs observed shadow direction) | Evidence Generation |
| FR34 | Backend analyzes 360° scan for parallax (environment 3D-ness) | Evidence Generation |
| FR35 | Backend performs gyro × optical flow consistency check | Evidence Generation |
| FR52 | Users can scrub through 360° context video if environment scan performed | Verification Interface |
| FR53 | Context viewer shows parallax visualization highlighting depth cues | Verification Interface |

### Phase 1 (Growth Features)

| FR | Description | Category |
|----|-------------|----------|
| FR13 | App records barometric pressure if sensor available | Capture Flow |
| FR14 | App records LiDAR depth frames if sensor available | Capture Flow |
| FR22 | App computes local LiDAR flatness analysis if available | Local Processing |
| FR32 | Backend performs LiDAR depth analysis for flatness detection | Evidence Generation |
| FR33 | Backend performs barometric consistency check against GPS altitude | Evidence Generation |
| FR36 | Backend performs multi-camera lighting consistency check | Evidence Generation |
| FR42 | Backend embeds C2PA manifest in media file | C2PA Integration |
| FR49 | Users can access expert panel for raw sensor data download | Verification Interface |
| FR50 | Users can download evidence computation logs and methodology documentation | Verification Interface |
| FR51 | Users can view raw C2PA manifest (JUMBF) | Verification Interface |
| FR61 | Users can create optional account with passkey-based authentication | User & Device Management |
| FR62 | Users can link multiple devices to account | User & Device Management |
| FR63 | Users can view gallery of their captures | User & Device Management |
| FR64 | Users can revoke/withdraw captures | User & Device Management |
| FR65 | Withdrawn captures display revocation notice on verification page | User & Device Management |
| FR69 | Users can export all their data | Privacy Controls |
| FR70 | Users can delete account and all associated captures | Privacy Controls |

### Summary

- **Phase 0 (MVP):** 38 FRs - Core capture, attestation, verification flow
- **Phase 0.5:** 15 FRs - Environment scan, physics checks, iOS support
- **Phase 1:** 17 FRs - Advanced checks, user accounts, expert features

**Total:** 70 Functional Requirements

---

## FR Coverage Map

<!-- Coverage map will be added after Step 2 -->

---

<!-- Epic content will follow -->
