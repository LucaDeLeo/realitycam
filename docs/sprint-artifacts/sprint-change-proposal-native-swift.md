# Sprint Change Proposal: Native Swift Implementation

**Date:** 2025-11-25
**Author:** Luca + PM Agent (John)
**Change ID:** SCP-006
**Classification:** Major

---

## Section 1: Issue Summary

### Problem Statement
The current mobile app architecture (Expo/React Native) introduces multiple abstraction layers and JavaScript-to-Native bridge crossings for security-critical operations. For a photo verification platform where trust is the core value proposition, this architecture presents unnecessary attack surface.

### Trigger
User-initiated strategic decision to maximize security posture by eliminating all non-native code from the capture and attestation pipeline.

### Context
- Discovered during implementation planning phase
- Security-first mindset: "depend on external stuff the least"
- Need for compiled native code that calls iOS APIs directly
- Background upload capability (survives app termination) not available in React Native

### Evidence
Key security concerns with current Expo/RN architecture:
1. **JS Bridge Crossings**: Photo bytes, SHA-256 hashes, and encryption keys cross the JS↔Native bridge
2. **Timing Gaps**: Separate camera + LiDAR modules can have millisecond timing discrepancies
3. **Wrapper Layers**: `@expo/app-integrity` wraps DCAppAttest; `expo-crypto` wraps CryptoKit
4. **Background Limitations**: `fetch()` cannot continue uploads after app termination

---

## Section 2: Impact Analysis

### Epic Impact

| Epic | Impact | Description |
|------|--------|-------------|
| Epic 1 | None | Foundation (backend/web) unchanged |
| Epic 2 | Superseded | Native attestation in Epic 6 |
| Epic 3 | Superseded | Native capture in Epic 6 |
| Epic 4 | Partial | Upload stories superseded; backend stories unchanged |
| Epic 5 | None | C2PA/web verification unchanged |
| **Epic 6** | **NEW** | 16 stories for complete native Swift implementation |

### Story Impact
- **Existing Stories (Epics 2-4 mobile)**: Remain as-is for parallel development/testing
- **New Stories (Epic 6)**: 16 new stories covering all mobile functionality
- **After Validation**: Expo code can be archived; Epic 6 becomes primary mobile path

### Artifact Conflicts Resolved

| Artifact | Sections Updated | Status |
|----------|------------------|--------|
| PRD | Tech Stack, Platform Support, Project Classification | Updated |
| Architecture | Decision Summary, Project Structure, FR Mapping, Dependencies, ADRs, Setup Commands, Deployment Diagram | Updated |
| Epics | Epic Summary, Epic 6 (new), FR Coverage Matrix, Summary | Updated |

### Technical Impact
- **Code**: New `ios/Rial/` directory structure (parallel to `apps/mobile/`)
- **Infrastructure**: No changes (same backend API)
- **Deployment**: App Store submission as new native app
- **Testing**: XCTest + XCUITest for native; feature parity validation against Expo

---

## Section 3: Recommended Approach

### Path: Direct Adjustment (Add Epic to Existing Plan)

**Rationale:**
1. Epic 6 can be developed in parallel with Epics 1-5
2. No rework of existing code required initially
3. Feature parity validation (Story 6.16) gates deprecation decision
4. Backend API unchanged—native app is a new client

### Effort Estimate

| Phase | Stories | Estimated Effort |
|-------|---------|------------------|
| Security Foundation | 6.1-6.4 | Foundation work |
| Capture Core | 6.5-6.8 | Core functionality |
| Storage & Upload | 6.9-6.12 | Persistence layer |
| User Experience | 6.13-6.16 | UI + validation |

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Native Swift learning curve | Medium | Low | Swift is well-documented; ARKit examples abundant |
| Feature parity gaps | Low | Medium | Systematic validation in Story 6.16 |
| Parallel development overhead | Low | Low | Clear separation (ios/ vs apps/mobile/) |
| App Store review delays | Low | Medium | Standard app submission; no unusual capabilities |

### Timeline Impact
- Epic 6 is additive, not blocking
- Can start immediately parallel to other epics
- Deprecation of Expo code deferred until Story 6.16 complete

---

## Section 4: Detailed Change Proposals

### PRD Changes (3 edits applied)

**4.1 Tech Stack Update**
```
OLD: Expo SDK 54, React Native 0.81, expo-router
NEW: Swift 5.9+/SwiftUI, iOS 15.0+, native frameworks (DeviceCheck, CryptoKit, ARKit, Metal)
```

**4.2 Platform Support Update**
```
OLD: iOS 14.0 minimum
NEW: iOS 15.0 minimum (modern Swift concurrency, all LiDAR iPhones supported)
```

**4.3 Project Classification Update**
```
Updated to reflect native architecture with direct OS framework usage
```

### Architecture Changes (13 edits applied)

**4.4 Decision Summary Table**
- Mobile Framework: React Native → Native Swift/SwiftUI
- State Management: Zustand → SwiftUI + Keychain
- Attestation: @expo/app-integrity → DeviceCheck (DCAppAttest)
- Cryptography: expo-crypto → CryptoKit
- Depth Capture: react-native-vision-camera → ARKit
- Depth Visualization: JS Canvas → Metal
- Networking: fetch() → URLSession

**4.5 Project Structure**
```
NEW: ios/Rial/ hierarchy with:
- App/ (RialApp.swift, AppDelegate.swift)
- Core/ (Attestation/, Capture/, Crypto/, Networking/, Storage/)
- Features/ (Capture/, Preview/, History/, Result/)
- Models/, Shaders/, Resources/
- Test targets: RialTests/, RialUITests/
```

**4.6 FR Category Mapping**
- Updated to reference native file locations (Core/Attestation/DeviceAttestation.swift, etc.)

**4.7 Mobile Dependencies**
- Changed from npm packages to zero external dependencies (native iOS frameworks only)

**4.8 Local Storage Encryption**
- Updated from AES-256 workaround to CryptoKit AES-GCM with code examples

**4.9 Architecture Decision Records**
- Deprecated: ADR-002 (Expo Modules), ADR-007 (@expo/app-integrity), ADR-008 (react-native-vision-camera)
- Added: ADR-009 (Native Swift Architecture) with comprehensive rationale and comparison table

**4.10 Setup Commands**
- Prerequisites: Xcode 16+ first, Node.js for web only
- iOS App: Xcode project workflow instead of Expo commands

**4.11-4.13 Header, Init Section, Deployment Diagram**
- Updated all references from Expo/RN to native Swift

### Epics Changes (Epic 6 added)

**4.14 Epic 6: Native Swift Implementation**
- 16 stories across 4 phases
- Full FR coverage for mobile functionality
- Security improvements documented
- Parallel development strategy

**4.15 FR Coverage Matrix**
- Added "Native (Epic 6)" column showing Swift story mappings

### Branding Update (all documents)

**4.16 Rename: RealityCam → rial.**
- All document titles, references, and UI strings updated

---

## Section 5: Implementation Handoff

### Change Scope Classification: **Major**

This is a fundamental architectural change introducing a new epic with 16 stories. Requires PM/Architect coordination for prioritization and resource allocation.

### Handoff Recipients

| Recipient | Responsibility |
|-----------|----------------|
| **Development Team** | Begin Epic 6 Story 6.1 (Xcode project setup) |
| **Product Owner** | Prioritize Epic 6 in backlog alongside Epics 1-5 |
| **Scrum Master** | Coordinate parallel development tracks |
| **Solution Architect** | Review native architecture decisions |

### Deliverables Produced

1. **Updated PRD** (`docs/prd.md`)
   - Native Swift tech stack
   - iOS 15.0 minimum
   - "rial." branding

2. **Updated Architecture** (`docs/architecture.md`)
   - Comprehensive native architecture
   - ADR-009 documenting decision rationale
   - Native project structure and setup

3. **Updated Epics** (`docs/epics.md`)
   - Epic 6 with 16 detailed stories
   - FR Coverage Matrix with native mappings
   - Updated totals: 6 Epics, 57 Stories

4. **This Sprint Change Proposal** (`docs/sprint-artifacts/sprint-change-proposal-native-swift.md`)

### Success Criteria

1. Epic 6 stories can be executed independently of Epics 2-4
2. Native app achieves feature parity with Expo app (validated in Story 6.16)
3. Backend accepts uploads from both app versions during transition
4. Security improvements demonstrated (no JS bridge for sensitive data)
5. Background upload capability verified (survives app termination)

### Next Steps

1. **Immediate**: Review and approve this Sprint Change Proposal
2. **Next**: Begin Story 6.1 (Initialize Native iOS Project)
3. **Parallel**: Continue Epics 1-5 development
4. **Milestone**: Story 6.16 feature parity validation
5. **Decision Point**: Archive Expo code after successful validation

---

## Approval

- [x] User approval received (2025-11-25)
- [x] Routed to appropriate recipients
- [x] Implementation initiated

**Approved by:** Luca
**Date:** 2025-11-25
**Next Action:** Begin Story 6.1 - Initialize Native iOS Project

---

_Generated by PM Agent (John) via BMAD Correct Course Workflow_
