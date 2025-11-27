# Story 7-13: Video Verification Page

Status: drafted

## Story

As a **video verification page user**,
I want **to view and verify video captures with their evidence packages**,
So that **I can assess the authenticity of video evidence through playback and comprehensive verification data**.

## Acceptance Criteria

### AC 1: Video Detection and Routing
**Given** user navigates to `/verify/{capture_id}`
**When** capture data is loaded
**Then**:
1. Detect if capture type is "video" (from evidence.type field)
2. Display video player instead of static image
3. Show video-specific evidence panel
4. Maintain same layout structure as photo verification

### AC 2: Video Player Component
**Given** video capture loaded
**When** page renders video section
**Then**:
1. Display HTML5 video player with native controls
2. Support play/pause, scrubbing, volume control
3. Video loaded from photo_url (or video_url if different)
4. Aspect ratio preserved (16:9 or 4:3)
5. Player responsive on mobile and desktop
6. Loading state while video fetches

### AC 3: Video-Specific Evidence Panel
**Given** video capture evidence loaded
**When** building evidence items
**Then** include:
1. **Hardware Attestation** - Same as photos (device model, status)
2. **Hash Chain Integrity** - Show chain_intact, verified_frames/total_frames
3. **Temporal Depth Analysis** - Show depth_consistency, motion_coherence, scene_stability
4. **Timestamp** - Same as photos (timestamp_valid, delta)
5. **Device Model** - Same as photos
6. **Location** - Same as photos

### AC 4: Hash Chain Evidence Display
**Given** video evidence includes hash_chain data
**When** rendering hash chain evidence row
**Then**:
- Status: "pass" if chain_intact=true, "fail" if false, "partial" if status=partial
- Value: "450/450 frames verified" (or actual counts)
- If broken_at_frame exists, show "Broken at frame {N}"
- If attestation_valid=false, indicate "Attestation invalid"

### AC 5: Temporal Depth Evidence Display
**Given** video evidence includes depth_analysis data
**When** rendering temporal depth row
**Then**:
- Status: "pass" if is_likely_real_scene=true, "fail" if false, "unavailable" if missing
- Value: "Consistency: 0.85, Coherence: 0.72, Stability: 0.95" (formatted metrics)
- Show "Real 3D scene detected" if is_likely_real_scene=true
- Handle missing depth_analysis gracefully (status="unavailable")

### AC 6: Partial Video Verification Display
**Given** video evidence with partial_attestation.is_partial=true
**When** rendering verification summary
**Then**:
1. Show banner: "Partial Verification: 10s of 12s verified"
2. Display verified_frames/total_frames in hash chain evidence
3. Show checkpoint_index if present: "Checkpoint 1 (10s)"
4. Confidence badge reflects partial verification (likely MEDIUM)
5. Evidence panel shows which checks were performed on verified portion

### AC 7: Video Metadata Display
**Given** video capture loaded
**When** rendering summary section
**Then** show:
1. Duration: "15.0s" or "10.0s of 12.0s (partial)" if partial
2. Frame count: "450 frames (30fps)"
3. Captured at timestamp (same as photos)
4. Location (same as photos)
5. Device model (same as photos)

### AC 8: C2PA Video Manifest Display (Future Enhancement)
**Given** video capture includes C2PA manifest
**When** rendering evidence panel
**Then**:
1. Add "C2PA Content Credentials" evidence row
2. Status: "pass" if manifest valid
3. Value: "Video manifest verified"
4. Link to manifest JSON or detailed view
**Note:** Manifest data will be available after Story 7-12 implementation

### AC 9: Mobile Responsive Video Player
**Given** user views verification page on mobile
**When** video player renders
**Then**:
1. Player fills available width
2. Controls touch-friendly (minimum 44x44px tap targets)
3. Orientation changes handled gracefully
4. Video can be viewed in fullscreen
5. Performance acceptable on iPhone 12 Pro and newer

### AC 10: Error States and Loading
**Given** various video loading scenarios
**When** page renders
**Then** handle:
1. Video file not found: Show placeholder with error message
2. Video still processing: Show "Video processing..." indicator
3. Network timeout: Show retry button
4. Unsupported format: Show format error message
5. Loading spinner while video fetches

## Tasks / Subtasks

- [ ] Task 1: Extend verify page to detect video captures (AC: #1)
  - [ ] Add type detection logic in page component
  - [ ] Route to video player vs static image based on type
  - [ ] Update TypeScript interfaces for video evidence

- [ ] Task 2: Create VideoPlayer component (AC: #2, #9)
  - [ ] Create `apps/web/src/components/Media/VideoPlayer.tsx`
  - [ ] Implement HTML5 video element with controls
  - [ ] Add responsive sizing and aspect ratio handling
  - [ ] Add loading state and error handling
  - [ ] Test on mobile devices

- [ ] Task 3: Update evidence panel for video data (AC: #3)
  - [ ] Extend `buildEvidenceItems()` logic in verify page
  - [ ] Add hash chain evidence mapping
  - [ ] Add temporal depth evidence mapping
  - [ ] Reuse existing EvidenceRow component
  - [ ] Handle optional video-specific fields

- [ ] Task 4: Implement hash chain evidence display (AC: #4)
  - [ ] Map hash_chain.status to evidence status
  - [ ] Format verified_frames/total_frames display
  - [ ] Handle broken_at_frame display
  - [ ] Handle attestation_valid flag

- [ ] Task 5: Implement temporal depth evidence display (AC: #5)
  - [ ] Map depth_analysis to evidence status
  - [ ] Format metric values (consistency, coherence, stability)
  - [ ] Show "Real 3D scene" indicator
  - [ ] Handle missing depth_analysis gracefully

- [ ] Task 6: Implement partial video UI (AC: #6)
  - [ ] Create PartialVideoBanner component
  - [ ] Display verified vs total duration
  - [ ] Show checkpoint information
  - [ ] Update evidence panel for partial verification

- [ ] Task 7: Add video metadata display (AC: #7)
  - [ ] Display duration (with partial notation if applicable)
  - [ ] Display frame count and fps
  - [ ] Reuse existing timestamp/location/device display
  - [ ] Format duration as seconds with 1 decimal place

- [ ] Task 8: Add error states and loading (AC: #10)
  - [ ] Create VideoPlaceholder component
  - [ ] Add loading spinner for video fetch
  - [ ] Handle video not found
  - [ ] Handle processing state
  - [ ] Add retry mechanism

- [ ] Task 9: Update TypeScript types (AC: #1, #3)
  - [ ] Extend CapturePublicData interface for video fields
  - [ ] Add VideoEvidence type definitions
  - [ ] Add HashChainVerification type
  - [ ] Add VideoDepthAnalysis type
  - [ ] Add PartialAttestationInfo type

- [ ] Task 10: Write tests (AC: All)
  - [ ] Unit tests for evidence mapping functions
  - [ ] Component tests for VideoPlayer
  - [ ] Component tests for PartialVideoBanner
  - [ ] E2E test for video verification page
  - [ ] Test partial video display
  - [ ] Test error states

## Dev Notes

### Technical Approach

**Video Detection:**
Check `evidence.type === "video"` to determine if capture is video. This field is set by VideoEvidenceService (Story 7-11).

**Player Implementation:**
Use native HTML5 `<video>` element with `controls` attribute. This provides cross-browser compatibility and accessibility. Avoid third-party players for MVP to minimize dependencies.

**Evidence Mapping:**
Extend existing `buildEvidenceItems()` function with video-specific branches:
```typescript
// Photo evidence (existing)
if (!evidence.type || evidence.type === "photo") {
  return buildPhotoEvidenceItems(evidence);
}

// Video evidence (new)
if (evidence.type === "video") {
  return buildVideoEvidenceItems(evidence);
}
```

**Partial Video Banner:**
Display prominently above evidence panel when `partial_attestation.is_partial === true`. Use info-style styling (blue background, not error red) since partial verification is valid.

**TypeScript Types:**
Define video-specific types matching backend VideoEvidence structure from Story 7-11. Use optional fields (`?`) for data that may be unavailable.

**Reuse Existing Components:**
- `ConfidenceBadge` - Works for video confidence levels
- `EvidencePanel` - Works with extended evidence items
- `EvidenceRow` - Handles video-specific evidence types
- Layout structure - Same grid layout as photo verification

### Project Structure Notes

**New Files:**
- `apps/web/src/components/Media/VideoPlayer.tsx` - Video player component
- `apps/web/src/components/Evidence/PartialVideoBanner.tsx` - Partial attestation banner
- `apps/web/src/lib/video-evidence.ts` - Video evidence mapping helpers

**Modified Files:**
- `apps/web/src/app/verify/[id]/page.tsx` - Add video detection and rendering
- `apps/web/src/lib/api.ts` - Extend types for video evidence
- `apps/web/tests/e2e/verify.spec.ts` - Add video verification tests

**Component Hierarchy:**
```
VerifyPage
├── VideoPlayer (new, if type=video)
│   ├── HTML5 video element
│   ├── Loading spinner
│   └── Error placeholder
├── PartialVideoBanner (new, if is_partial=true)
├── ConfidenceBadge (existing, reused)
├── Metadata display (existing, extended)
└── EvidencePanel (existing, extended items)
    ├── Hardware Attestation (existing)
    ├── Hash Chain Integrity (new)
    ├── Temporal Depth Analysis (new)
    ├── Timestamp (existing)
    ├── Device Model (existing)
    └── Location (existing)
```

### Architecture Alignment

**Next.js App Router:**
Extend existing `/app/verify/[id]/page.tsx` server component. Video detection happens server-side, VideoPlayer is client component.

**API Integration:**
No new endpoints needed. Existing `GET /api/v1/captures/{id}/public` returns video evidence from Story 7-11.

**Evidence Structure:**
Backend VideoEvidence structure (Story 7-11) includes:
- `type: "video"`
- `hardware_attestation` (shared with photos)
- `hash_chain: HashChainVerification` (video-specific)
- `depth_analysis: VideoDepthAnalysis` (video-specific, optional)
- `metadata` (shared with photos)
- `partial_attestation: PartialAttestationInfo` (video-specific)

**Performance:**
Video files may be large (~20MB for 15s). Use streaming video delivery from S3. Consider adding video poster image for faster initial render.

### Testing Standards

**Unit Tests (Vitest):**
- Video evidence mapping functions
- Type guards for video detection
- Evidence item builders

**Component Tests (React Testing Library):**
- VideoPlayer with mock video URL
- PartialVideoBanner with various checkpoint scenarios
- Evidence panel with video-specific items

**E2E Tests (Playwright):**
- Full video verification flow
- Partial video display
- Error states (video not found, processing)
- Mobile responsive video player

**Test Fixtures:**
Create test data in `apps/web/tests/fixtures/video-evidence.json`:
- Complete video evidence (high confidence)
- Partial video evidence (medium confidence)
- Suspicious video evidence (chain broken)

### References

**Backend Types (Story 7-11):**
- `VideoEvidence` struct
- `HashChainVerification` struct
- `VideoDepthAnalysis` struct
- `PartialAttestationInfo` struct

**Existing Components:**
- `apps/web/src/app/verify/[id]/page.tsx` (photo verification reference)
- `apps/web/src/components/Evidence/EvidencePanel.tsx` (reuse for videos)
- `apps/web/src/components/Evidence/ConfidenceBadge.tsx` (reuse for videos)

**API Response:**
- `GET /api/v1/captures/{id}/public` returns CapturePublicData with evidence field

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- To be filled by dev agent -->

### Debug Log References

<!-- To be filled by dev agent -->

### Completion Notes List

<!-- To be filled by dev agent -->

### File List

<!-- To be filled by dev agent -->

---

## Source Document References

- **Epic:** [Source: docs/epics.md - Epic 7: Video Capture with LiDAR Depth]
- **Tech Spec:** [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-7.md]
  - Section: AC-7.12 (Video Verification Page)
  - Section: Components > Video Verification Page
  - Section: Data Models > VideoEvidence
- **Architecture:** [Source: docs/architecture.md]
  - Web application structure
  - Next.js App Router patterns
  - Component design patterns
- **Previous Stories:**
  - [Source: docs/sprint-artifacts/stories/7-11-video-evidence-package.md] (VideoEvidence structure)
  - [Source: docs/sprint-artifacts/stories/7-12-c2pa-video-manifest-generation.md] (C2PA manifest integration)
  - [Source: docs/sprint-artifacts/stories/5-4-verification-page-summary-view.md] (Photo verification patterns)
  - [Source: docs/sprint-artifacts/stories/5-5-evidence-panel-component.md] (Evidence panel reuse)
- **Existing Code:**
  - [Source: apps/web/src/app/verify/[id]/page.tsx] (Photo verification reference)
  - [Source: apps/web/src/components/Evidence/EvidencePanel.tsx] (Component to reuse)
  - [Source: apps/web/src/components/Evidence/ConfidenceBadge.tsx] (Component to reuse)

---

## Learnings from Previous Stories

Based on review of Stories 5-4 (Photo Verification Page), 7-11 (Video Evidence), and 7-12 (C2PA Video Manifest):

1. **Reuse Photo Verification Structure (Story 5-4):** The video verification page follows the same layout as photo verification: header, results card (image/video + summary), evidence panel, footer. Only the media section changes.

2. **Evidence Panel Extensibility (Story 5-5):** EvidencePanel component accepts an array of items with `{label, status, value}`. Extend with video-specific items (hash chain, temporal depth) without modifying the component.

3. **Type Detection Pattern:** Check `evidence.type` field to determine photo vs video. This field is set by backend evidence services (PhotoEvidenceService, VideoEvidenceService).

4. **Confidence Badge Reuse:** ConfidenceBadge component works for both photo and video captures. Video confidence calculation (Story 7-11) uses same levels: high, medium, low, suspicious.

5. **Partial Video Transparency (Story 7-11):** Partial videos are valid evidence. Display clearly with verified/total metrics. Don't show as error state - use info styling.

6. **Video Evidence Structure (Story 7-11):** VideoEvidence includes hardware_attestation (shared), hash_chain (video), depth_analysis (video), metadata (shared), partial_attestation (video). Map each to evidence rows.

7. **Hash Chain Display (Story 7-10):** Hash chain verification provides chain_intact (boolean), verified_frames (int), total_frames (int), status (enum). Display as "450/450 frames verified" with pass/fail status.

8. **Temporal Depth Metrics (Story 7-9):** Depth analysis provides depth_consistency, motion_coherence, scene_stability (0.0-1.0 floats). Format as percentages or 2-decimal values. Show "Real 3D scene" if is_likely_real_scene=true.

9. **Mobile Video Players (Web Best Practices):** HTML5 video element with `controls` attribute provides good mobile UX. Use `playsinline` attribute to prevent fullscreen on iOS. Set `preload="metadata"` for faster initial render.

10. **Error Handling (Story 5-4):** Show graceful error states for missing video, processing state, network errors. Don't show 404 page - inline error messages.

11. **TypeScript Types (Story 7-11):** Define frontend types matching backend VideoEvidence structure. Use optional fields for data that may be unavailable (depth_analysis, location).

12. **Testing Video Components (Web Best Practices):** Mock video URL in component tests. Use data URLs or test fixtures. E2E tests verify video player rendering, not playback (Playwright limitation).

13. **C2PA Manifest Integration (Story 7-12):** C2PA manifest stored separately (not embedded in MVP). Future enhancement can display manifest link or detailed view. Defer to post-MVP.

14. **Demo Route Pattern (Existing Code):** Photo verification has `/verify/demo` route with hardcoded data. Add video demo data for development/testing.

15. **Responsive Grid Layout (Story 5-4):** Two-column grid on desktop (media | summary), single column on mobile. Video player should fill column width and maintain aspect ratio.

---

_Story created: 2025-11-27_
_Depends on: Story 7-12 (C2PA Video Manifest Generation) - provides manifest data_
_Enables: Complete video capture and verification flow (Epic 7 completion)_
