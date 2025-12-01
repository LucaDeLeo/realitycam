# Sprint Change Proposal: Privacy-First Capture Mode

**Proposal ID:** SCP-008
**Date:** 2025-12-01
**Author:** John (PM Agent)
**Requestor:** Luca
**Status:** Pending Approval

---

## 1. Issue Summary

### Problem Statement

Current rial. requires full media upload for evidence generation. Users with sensitive/confidential data (legal, medical, corporate, journalism) need proof of authenticity without exposing raw media to any server.

### Change Request

Add two related privacy features:

1. **Hash-Only Verification Mode** — Users upload cryptographic hash of media instead of raw bytes. Server verifies authenticity without ever touching actual image/video data.

2. **Granular Metadata Controls** — Users can selectively choose what metadata accompanies each capture (location precision, timestamp granularity, device info level).

### Discovery Context

- **Trigger:** Post-MVP feature request (all 7 epics complete)
- **Type:** New requirement for privacy-conscious market segment
- **Strategic Value:** Competitive differentiation through "zero-knowledge provenance"

### Evidence

- Use cases: Journalists protecting sources, lawyers with privileged materials, HR investigations, medical documentation
- Market gap: No existing solution offers attested capture without server-side media storage
- Technical feasibility: Client-side depth analysis validated via hardware attestation

---

## 2. Impact Analysis

### Epic Impact

| Epic | Impact | Details |
|------|--------|---------|
| Epic 1-5 | None | Infrastructure unchanged |
| Epic 6 (Native iOS) | Minor | Add client-side depth analysis, privacy settings |
| Epic 7 (Video) | Minor | Same pattern for video hash-only mode |
| **Epic 8 (NEW)** | New | Privacy-First Capture Mode (8 stories) |

### Artifact Conflicts

| Artifact | Impact | Changes Required |
|----------|--------|------------------|
| PRD | Extend | Add FR56-FR62, extend FR44-FR46 |
| Architecture | Extend | Add ADR-011, update schemas/APIs |
| Database | Extend | Add capture_mode, media_stored, metadata_flags |
| API | Extend | Hash-only capture endpoint mode |
| iOS App | Extend | DepthAnalysisService, PrivacySettingsView |
| Web | Extend | Hash-only verification display |

### Technical Impact

- **iOS:** New `DepthAnalysisService` for on-device depth computation
- **Backend:** Accept pre-computed analysis, trust via attestation verification
- **Database:** New columns for capture mode and metadata flags
- **Web:** New verification messaging for hash-only captures

---

## 3. Recommended Approach

### Selected Path: Direct Adjustment (Add Epic 8)

| Factor | Assessment |
|--------|------------|
| Approach | Add new Epic 8 with 8 stories |
| Effort | Medium (~8 stories, 2-3 weeks) |
| Risk | Low — isolated feature, no rework |
| Timeline Impact | Extends scope, parallel development possible |

### Rationale

1. **Additive, not destructive** — Existing full-upload mode unchanged
2. **High strategic value** — Creates competitive moat
3. **Technically sound** — Client-side analysis trusted via hardware attestation
4. **Low risk** — Well-isolated from existing functionality

### Alternatives Rejected

| Option | Reason for Rejection |
|--------|---------------------|
| Deferral | Loses first-mover advantage in privacy-first provenance |
| Rollback | Not applicable (no work to undo) |

---

## 4. Detailed Change Proposals

### 4.1 PRD Updates

**Add FR56-FR62:**
```
FR56: App provides "Privacy Mode" toggle in capture settings
FR57: In Privacy Mode, app performs depth analysis locally
FR58: In Privacy Mode, app uploads only: hash + depth_analysis + attestation
FR59: Backend accepts pre-computed depth analysis signed by attested device
FR60: Backend stores hash + evidence without raw media
FR61: Verification page displays "Hash Verified" messaging
FR62: Users can configure per-capture metadata granularity
```

**Extend FR44-FR46 with granular controls:**
- Location: none / coarse / precise
- Timestamp: none / day / exact
- Device: none / model / full

### 4.2 Architecture Updates

**New ADR-011: Client-Side Depth Analysis**
- Device performs depth analysis locally (same algorithm as server)
- DCAppAttest signs: hash(media) + depth_analysis + timestamp
- Server trusts analysis because only attested device could sign it
- Trade-off: Cannot re-analyze if algorithm improves

**Database Schema:**
```sql
ALTER TABLE captures ADD COLUMN capture_mode TEXT DEFAULT 'full';
ALTER TABLE captures ADD COLUMN media_stored BOOLEAN DEFAULT TRUE;
ALTER TABLE captures ADD COLUMN metadata_flags JSONB;
```

**API Contract:**
- `POST /api/v1/captures` accepts `mode: "hash_only"`
- Request includes pre-computed `depth_analysis` object
- Assertion signature verified to cover entire payload

### 4.3 Epic 8 Stories

| Story | Title | Component |
|-------|-------|-----------|
| 8.1 | Client-Side Depth Analysis Service | iOS |
| 8.2 | Privacy Mode Settings UI | iOS |
| 8.3 | Hash-Only Capture Payload | iOS |
| 8.4 | Backend Hash-Only Capture Endpoint | Backend |
| 8.5 | Hash-Only Evidence Package | Backend |
| 8.6 | Verification Page Hash-Only Display | Web |
| 8.7 | File Verification for Hash-Only | Web |
| 8.8 | Video Privacy Mode Support | iOS/Backend |

### 4.4 Confidence Calculation Update

Hash-only captures can achieve HIGH confidence when:
- Hardware attestation passes (device is genuine)
- Device-computed depth analysis indicates real scene

Key insight: If the device is attested, its analysis is trustworthy.

---

## 5. Implementation Handoff

### Scope Classification: **Moderate**

Requires backlog reorganization and coordinated implementation across iOS, backend, and web.

### Handoff Recipients

| Role | Responsibility |
|------|----------------|
| **PM** | Finalize PRD updates, approve epic scope |
| **Architect** | Review ADR-011, validate technical approach |
| **SM** | Create Epic 8 tech spec, draft stories |
| **Dev Team** | Implement stories across all components |

### Implementation Sequence

1. **Phase 1: Foundation**
   - Story 8.1: Client-Side Depth Analysis Service
   - Story 8.4: Backend Hash-Only Endpoint

2. **Phase 2: iOS Integration**
   - Story 8.2: Privacy Mode Settings UI
   - Story 8.3: Hash-Only Capture Payload

3. **Phase 3: Backend & Web**
   - Story 8.5: Hash-Only Evidence Package
   - Story 8.6: Verification Page Display
   - Story 8.7: File Verification

4. **Phase 4: Video**
   - Story 8.8: Video Privacy Mode Support

### Success Criteria

- [ ] Privacy Mode toggle functional in iOS app
- [ ] Hash-only captures upload < 10KB (vs ~5MB full)
- [ ] Server never receives raw media in Privacy Mode
- [ ] Verification page displays correct messaging
- [ ] File upload verification works for hash-only captures
- [ ] Video hash-only mode functional

---

## 6. Approval

**Approval Required From:** Luca (Product Owner)

| Decision | Status |
|----------|--------|
| PRD Updates (FR56-FR62) | Pending |
| Architecture (ADR-011) | Pending |
| Epic 8 Creation | Pending |
| Implementation Priority | Pending |

---

*Generated by Correct Course Workflow*
*Date: 2025-12-01*
*For: Luca*
