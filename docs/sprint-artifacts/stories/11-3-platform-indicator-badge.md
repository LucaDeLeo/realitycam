# Story 11-3: Platform Indicator Badge

Status: done

## Story

As a **verification page viewer**,
I want **to see which platform captured the media (iOS or Android) and its attestation security level**,
So that **I understand the trust foundation for this capture and can appropriately assess confidence based on platform capabilities**.

## Context

This story implements FR78: "Verification page indicates platform (iOS/Android) and attestation method."

**Platform Trust Hierarchy (from PRD):**
| Platform | Attestation | Primary Depth | Max Confidence |
|----------|-------------|---------------|----------------|
| iOS Pro | Secure Enclave | LiDAR | HIGH/VERY HIGH |
| iOS Standard | Secure Enclave | Parallax (future) | HIGH |
| Android | StrongBox | Parallax | MEDIUM-HIGH |
| Android | TEE | Parallax | MEDIUM |
| Android | Software | N/A | REJECTED |

**Data Source:**
- Story 10-5 (Unified Evidence Schema) adds `platform` field to EvidencePackage
- The evidence response includes `evidence.platform` ("ios" or "android")
- For iOS: `hardware_attestation.level` is "secure_enclave" or "unverified"
- For Android: `hardware_attestation.security_level.attestation_level` is "strongbox", "tee", or "unverified"

**Dependencies:**
- Story 10-5: Unified Evidence Schema (ready-for-dev) - **BLOCKS THIS STORY** - adds `platform` field and Android attestation levels to evidence
- Story 11-1: MethodBreakdownSection (done) - shows detection method scores
- Story 11-2: CrossValidationSection (review) - shows method agreement status

**IMPORTANT:** This story cannot be implemented until Story 10-5 is completed. The platform field and Android attestation level types do not exist in the current codebase.

## Acceptance Criteria

### AC 1: Platform Badge in Evidence Summary
**Given** a capture with platform information in evidence
**When** viewing the verification page
**Then**:
1. A platform indicator badge appears prominently near the confidence badge
2. Badge shows platform icon + label: "iOS" or "Android"
3. Badge uses platform-appropriate styling (iOS: Apple icon, Android: Android icon)
4. Badge appears for all captures (photo and video)
5. Badge is hidden only if platform data is missing (legacy captures)

### AC 2: Attestation Level Display
**Given** a capture with hardware attestation information
**When** rendering the platform badge
**Then** displays attestation level:

**iOS:**
| Level | Badge Text | Color | Icon |
|-------|------------|-------|------|
| secure_enclave | "Secure Enclave" | Green | Shield with checkmark |
| unverified | "Unverified" | Yellow/Orange | Shield with warning |

**Android:**
| Level | Badge Text | Color | Icon |
|-------|------------|-------|------|
| strongbox | "StrongBox" | Green | Shield with checkmark |
| tee | "TEE" | Blue | Shield |
| unverified | "Unverified" | Yellow/Orange | Shield with warning |

### AC 3: Combined Platform + Attestation Badge
**Given** the platform and attestation data
**When** rendering the badge
**Then** displays combined information:
- Format: "[Platform Icon] [Platform] - [Attestation Level]"
- Examples:
  - Apple icon + "iOS - Secure Enclave" (green)
  - Android icon + "Android - StrongBox" (green)
  - Android icon + "Android - TEE" (blue)
  - Platform icon + "[Platform] - Unverified" (yellow/orange)

### AC 4: Platform Tooltip with Details
**Given** a platform badge
**When** hovering (desktop) or tapping (mobile)
**Then** tooltip displays:
1. Full platform name: "Apple iOS" or "Google Android"
2. Device model (if available): "iPhone 15 Pro" or "Pixel 8 Pro"
3. Attestation method explanation:
   - iOS Secure Enclave: "Hardware-backed key stored in dedicated security chip. Highest trust level."
   - Android StrongBox: "Hardware Security Module. Comparable to iOS Secure Enclave."
   - Android TEE: "Trusted Execution Environment. Hardware-isolated but less secure than StrongBox."
   - Unverified: "Device attestation could not be verified. Lower trust level."
4. LiDAR status for iOS Pro: "LiDAR depth sensor available" or "No LiDAR sensor"
5. Depth method for Android: "Multi-camera parallax depth" (future) or "No depth analysis"

### AC 5: Platform Info in Evidence Panel Items
**Given** the existing EvidencePanel component (data-driven items array)
**When** platform data is available
**Then**:
1. A new "Platform & Attestation" item is added as first entry in EvidencePanel items array
2. Item shows platform name + attestation level in the value field (e.g., "iOS - Secure Enclave")
3. Item status (pass/warn/unavailable) reflects attestation verification status
4. More detailed platform info available via PlatformBadge component placed near ConfidenceBadge

**Note:** EvidencePanel uses an items array pattern (not children). Platform info is added via the items prop from page.tsx, not via a custom child component.

### AC 6: Platform Badge in Method Breakdown Header
**Given** the MethodBreakdownSection component (Story 11-1)
**When** platform data is available
**Then**:
1. Platform badge appears in the section header next to "Detection Methods"
2. Provides quick platform context for method scores
3. Shows abbreviated format: "[Icon] iOS" or "[Icon] Android"
4. Full details available in EvidencePanel row

### AC 7: Backward Compatibility
**Given** legacy captures without platform field
**When** rendering platform indicator
**Then**:
1. Platform defaults to "ios" (all MVP captures are iOS)
2. Attestation level extracted from existing `hardware_attestation.level`
3. No visual errors or missing component issues
4. Badge renders correctly with inferred platform

### AC 8: Responsive Design
**Given** the platform badge
**When** viewed on different screen sizes
**Then**:
1. **Mobile (<640px)**: Stacked layout, icon + short label ("iOS", "Android")
2. **Tablet (768-1024px)**: Badge with icon + attestation level
3. **Desktop (>1024px)**: Full badge with icon + platform + attestation level
4. Touch-friendly tap targets on mobile (min 44x44px)

### AC 9: TypeScript Types
**Given** the frontend codebase
**When** implementing the component
**Then** types are properly defined:

```typescript
// In packages/shared/src/types/evidence.ts (extend existing)

/** Platform identifier for capture source */
export type Platform = 'ios' | 'android';

/** iOS attestation levels */
export type iOSAttestationLevel = 'secure_enclave' | 'unverified';

/** Android attestation levels (from Story 10-2) */
export type AndroidAttestationLevel = 'strongbox' | 'tee' | 'unverified';

/** Combined attestation level for display purposes */
export type AttestationLevel = iOSAttestationLevel | AndroidAttestationLevel;

/** Platform info extracted from evidence for display */
export interface PlatformInfo {
  /** Platform: "ios" or "android" */
  platform: Platform;
  /** Attestation level */
  attestation_level: AttestationLevel;
  /** Device model (if available) */
  device_model?: string;
  /** Whether LiDAR is available (iOS Pro only) */
  has_lidar?: boolean;
  /** Whether depth analysis is available */
  depth_available: boolean;
  /** Depth analysis method */
  depth_method?: 'lidar' | 'parallax' | null;
}
```

### AC 10: Demo Data Integration
**Given** the existing demo routes (/verify/demo, /verify/demo-video)
**When** viewing demo captures
**Then**:
1. DEMO_CAPTURE shows iOS platform with Secure Enclave attestation
2. DEMO_VIDEO_CAPTURE shows iOS platform with Secure Enclave attestation
3. Demo data includes device_model and has_lidar fields
4. Future: Add demo-android route showing Android capture example

### AC 11: Accessibility Requirements
**Given** the platform badge component
**When** rendering with assistive technologies
**Then**:
1. Icon has `aria-hidden="true"` (decorative)
2. Badge has `aria-label` describing platform and attestation
3. Tooltip content accessible via keyboard focus
4. Color is not the only differentiator (icons + text)
5. Contrast meets WCAG AA standards

## Tasks / Subtasks

- [x] Task 1: Add TypeScript types for platform info (AC: #9)
  - [x] Add `Platform` type to packages/shared
  - [x] Add `iOSAttestationLevel` and `AndroidAttestationLevel` types
  - [x] Add `AttestationLevel` union type
  - [x] Add `PlatformInfo` interface
  - [x] Export types from shared package

- [x] Task 2: Create PlatformIcon component (AC: #1, #2)
  - [x] Create `apps/web/src/components/Evidence/PlatformIcon.tsx`
  - [x] Implement Apple icon (SF Symbol style or simple apple)
  - [x] Implement Android icon (robot head)
  - [x] Add size prop (sm, md, lg)
  - [x] Ensure icons are accessible (aria-hidden)

- [x] Task 3: Create AttestationLevelBadge component (AC: #2)
  - [x] Create `apps/web/src/components/Evidence/AttestationLevelBadge.tsx`
  - [x] Implement color coding per attestation level
  - [x] Add shield icon variants (checkmark, warning)
  - [x] Support all attestation levels (secure_enclave, strongbox, tee, unverified)

- [x] Task 4: Create PlatformBadge composite component (AC: #1, #3)
  - [x] Create `apps/web/src/components/Evidence/PlatformBadge.tsx`
  - [x] Compose PlatformIcon + AttestationLevelBadge
  - [x] Support compact/full variants for responsive design
  - [x] Add tooltip trigger integration

- [x] Task 5: Create PlatformTooltip component (AC: #4)
  - [x] Create `apps/web/src/components/Evidence/PlatformTooltip.tsx`
  - [x] Display full platform details
  - [x] Show device model if available
  - [x] Include attestation method explanation
  - [x] Show depth capability status

- [x] Task 6: Create platform evidence item helper (AC: #5)
  - [x] Create helper function `createPlatformEvidenceItem(platformInfo): EvidenceItem` in `apps/web/src/lib/platform.ts`
  - [x] Returns EvidenceItem compatible with EvidencePanel items array
  - [x] Label: "Platform & Attestation"
  - [x] Value: formatted string e.g., "iOS - Secure Enclave"
  - [x] Status: maps attestation verification to pass/warn/unavailable

- [x] Task 7: Helper function to extract platform info (AC: #7)
  - [x] Create `extractPlatformInfo(evidence)` utility in `apps/web/src/lib/platform.ts`
  - [x] Handle missing platform field (default to "ios")
  - [x] Extract attestation level from appropriate source
  - [x] Determine depth availability and method
  - [x] Return `PlatformInfo` object

- [x] Task 8: Update verification page with platform item in EvidencePanel (AC: #5)
  - [x] Modify `apps/web/src/app/verify/[id]/page.tsx`
  - [x] Use `createPlatformEvidenceItem()` to generate platform item
  - [x] Prepend platform item to evidence items array passed to EvidencePanel
  - [x] Ensure backward compatibility with legacy captures (skip if no platform info)

- [x] Task 9: Update MethodBreakdownSection header (AC: #6)
  - [x] Modify `apps/web/src/components/Evidence/MethodBreakdownSection.tsx`
  - [x] Add compact PlatformBadge to section header
  - [x] Accept platform prop
  - [x] Show only when platform data available

- [x] Task 10: Update verification page to extract/pass platform (AC: #1, #7)
  - [x] Update `apps/web/src/app/verify/[id]/page.tsx`
  - [x] Add platform extraction from evidence response
  - [x] Pass platformInfo to EvidencePanel
  - [x] Pass platformInfo to MethodBreakdownSection
  - [x] Handle missing platform gracefully

- [x] Task 11: Implement responsive design (AC: #8)
  - [x] Add Tailwind responsive classes for mobile layout
  - [x] Test compact badge on small screens
  - [x] Test full badge on desktop
  - [x] Ensure touch targets are adequate

- [x] Task 12: Add demo data with platform info (AC: #10)
  - [x] Update DEMO_CAPTURE with explicit platform field and device info
  - [x] Update DEMO_VIDEO_CAPTURE similarly
  - [x] Verify demo routes render correctly
  - [ ] Consider adding demo-android route for testing Android display (deferred)

- [x] Task 13: Unit tests (AC: #1-#11)
  - [x] Test PlatformIcon renders both platform icons
  - [x] Test AttestationLevelBadge color coding
  - [x] Test PlatformBadge composition
  - [x] Test PlatformTooltip content
  - [x] Test extractPlatformInfo utility with various inputs
  - [x] Test backward compatibility (missing platform -> ios)
  - [x] Test responsive variants

- [x] Task 14: Accessibility verification (AC: #11)
  - [x] Add aria-labels to all interactive elements
  - [x] Verify keyboard navigation
  - [ ] Test with VoiceOver/NVDA (manual testing required)
  - [x] Check color contrast ratios

## Dev Notes

### Critical Patterns - MUST READ

**BLOCKING DEPENDENCY - Story 10-5:**
This story CANNOT be implemented until Story 10-5 (Unified Evidence Schema) is completed. Story 10-5 adds:
- `platform` field to evidence package ("ios" or "android")
- `security_level` object with `attestation_level` field
- Extended `HardwareAttestation` types for Android levels

If 10-5 is not done, use backward compatibility fallback (platform defaults to "ios", attestation to "secure_enclave").

**Platform field location:**
The `platform` field is at the TOP LEVEL of the evidence object per Story 10-5:
```json
{
  "evidence": {
    "platform": "ios",
    "hardware_attestation": { "level": "secure_enclave", ... },
    ...
  }
}
```

**Attestation level extraction:**
- iOS: `evidence.hardware_attestation.level` -> "secure_enclave" | "unverified"
- Android: `evidence.hardware_attestation.security_level.attestation_level` -> "strongbox" | "tee" | "unverified"
- Fallback: If `security_level` not present, use `level` field

**Backward compatibility:**
All existing captures are iOS with Secure Enclave. If `platform` field is missing:
```typescript
const platform = evidence.platform ?? 'ios';
const attestation = evidence.hardware_attestation?.level ?? 'secure_enclave';
```

**Reuse existing components:**
- `ConfidenceBadge` from `@/components/Evidence/ConfidenceBadge.tsx` - for badge styling reference
- `EvidenceRow` from `@/components/Evidence/EvidenceRow.tsx` - for row pattern
- `MethodTooltip` from Story 11-1 - for tooltip pattern

### Component Architecture

```
VerifyPage
  |-- ConfidenceBadge (existing)
  |-- PlatformBadge (NEW - near confidence badge, with PlatformTooltip on click)
  |-- EvidencePanel (existing)
  |     |-- EvidenceRow (platform item added via items array - first row)
  |     |-- EvidenceRow (existing, repeated for other evidence)
  |-- MethodBreakdownSection (existing)
        |-- PlatformBadge (in header, compact)
        |-- MethodScoreBar (existing)
        |-- CrossValidationSection (existing)
```

**Note:** EvidencePanel is data-driven (items array). Platform info is added to items via `createPlatformEvidenceItem()` helper, not a custom child component.

### Display Name Mappings

```typescript
const PLATFORM_DISPLAY: Record<Platform, { label: string; icon: string }> = {
  'ios': { label: 'iOS', icon: 'apple' },
  'android': { label: 'Android', icon: 'android' },
};

const ATTESTATION_DISPLAY: Record<AttestationLevel, { label: string; color: string; description: string }> = {
  'secure_enclave': {
    label: 'Secure Enclave',
    color: 'green',
    description: 'Hardware-backed key stored in dedicated security chip. Highest trust level.',
  },
  'strongbox': {
    label: 'StrongBox',
    color: 'green',
    description: 'Hardware Security Module. Comparable to iOS Secure Enclave.',
  },
  'tee': {
    label: 'TEE',
    color: 'blue',
    description: 'Trusted Execution Environment. Hardware-isolated but less secure than StrongBox.',
  },
  'unverified': {
    label: 'Unverified',
    color: 'yellow',
    description: 'Device attestation could not be verified. Lower trust level.',
  },
};
```

### Color Tokens (Tailwind)

**Platform badge backgrounds:**
- iOS: `bg-zinc-800 dark:bg-zinc-200` (neutral, lets attestation color show)
- Android: `bg-zinc-800 dark:bg-zinc-200` (neutral)

**Attestation level colors:**
- Secure Enclave / StrongBox: `bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300`
- TEE: `bg-blue-100 text-blue-800 dark:bg-blue-900/50 dark:text-blue-300`
- Unverified: `bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300`

### Icon Implementation

**Option 1: SVG inline icons (Recommended)**
```tsx
// Apple icon (simplified)
const AppleIcon = () => (
  <svg viewBox="0 0 24 24" className="w-4 h-4" aria-hidden="true">
    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
  </svg>
);

// Android icon (robot head)
const AndroidIcon = () => (
  <svg viewBox="0 0 24 24" className="w-4 h-4" aria-hidden="true">
    <path d="M6 18c0 .55.45 1 1 1h1v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h2v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h1c.55 0 1-.45 1-1V8H6v10zM3.5 8C2.67 8 2 8.67 2 9.5v7c0 .83.67 1.5 1.5 1.5S5 17.33 5 16.5v-7C5 8.67 4.33 8 3.5 8zm17 0c-.83 0-1.5.67-1.5 1.5v7c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5v-7c0-.83-.67-1.5-1.5-1.5zm-4.97-5.84l1.3-1.3c.2-.2.2-.51 0-.71-.2-.2-.51-.2-.71 0l-1.48 1.48C13.85 1.23 12.95 1 12 1c-.96 0-1.86.23-2.66.63L7.85.15c-.2-.2-.51-.2-.71 0-.2.2-.2.51 0 .71l1.31 1.31C6.97 3.26 6 5.01 6 7h12c0-1.99-.97-3.75-2.47-4.84zM10 5H9V4h1v1zm5 0h-1V4h1v1z"/>
  </svg>
);
```

**Option 2: Lucide icons (if already using)**
Check if project uses `lucide-react`. If so, may need custom SVG since Lucide doesn't have platform-specific icons.

### Project Structure Notes

**New Files:**
- `apps/web/src/components/Evidence/PlatformIcon.tsx`
- `apps/web/src/components/Evidence/AttestationLevelBadge.tsx`
- `apps/web/src/components/Evidence/PlatformBadge.tsx`
- `apps/web/src/components/Evidence/PlatformTooltip.tsx`
- `apps/web/src/lib/platform.ts` - extractPlatformInfo() and createPlatformEvidenceItem() helpers
- `apps/web/src/components/Evidence/__tests__/PlatformIcon.test.tsx`
- `apps/web/src/components/Evidence/__tests__/AttestationLevelBadge.test.tsx`
- `apps/web/src/components/Evidence/__tests__/PlatformBadge.test.tsx`
- `apps/web/src/components/Evidence/__tests__/PlatformTooltip.test.tsx`
- `apps/web/src/lib/__tests__/platform.test.ts`

**Modified Files:**
- `packages/shared/src/types/evidence.ts` - Add platform types
- `packages/shared/src/index.ts` - Export new types
- `apps/web/src/components/Evidence/MethodBreakdownSection.tsx` - Add platform badge to header
- `apps/web/src/app/verify/[id]/page.tsx` - Extract platform info, add platform item to EvidencePanel items, update demo data

### Testing Standards

**Component Tests (Vitest + Testing Library):**
```typescript
// PlatformBadge.test.tsx
describe('PlatformBadge', () => {
  it('renders iOS badge with Secure Enclave', () => {
    render(<PlatformBadge platform="ios" attestationLevel="secure_enclave" />);
    expect(screen.getByText(/iOS/i)).toBeInTheDocument();
    expect(screen.getByText(/Secure Enclave/i)).toBeInTheDocument();
    expect(screen.getByTestId('platform-badge')).toHaveClass('bg-green');
  });

  it('renders Android badge with TEE', () => {
    render(<PlatformBadge platform="android" attestationLevel="tee" />);
    expect(screen.getByText(/Android/i)).toBeInTheDocument();
    expect(screen.getByText(/TEE/i)).toBeInTheDocument();
    expect(screen.getByTestId('platform-badge')).toHaveClass('bg-blue');
  });

  it('handles unverified attestation', () => {
    render(<PlatformBadge platform="ios" attestationLevel="unverified" />);
    expect(screen.getByText(/Unverified/i)).toBeInTheDocument();
    expect(screen.getByTestId('platform-badge')).toHaveClass('bg-yellow');
  });
});

// platform.test.ts
describe('extractPlatformInfo', () => {
  it('extracts iOS platform info', () => {
    const evidence = {
      platform: 'ios',
      hardware_attestation: { level: 'secure_enclave', device_model: 'iPhone 15 Pro' },
      depth_analysis: { method: 'lidar', status: 'pass' },
    };
    const info = extractPlatformInfo(evidence);
    expect(info.platform).toBe('ios');
    expect(info.attestation_level).toBe('secure_enclave');
    expect(info.device_model).toBe('iPhone 15 Pro');
    expect(info.has_lidar).toBe(true);
  });

  it('defaults to iOS when platform missing', () => {
    const evidence = {
      hardware_attestation: { level: 'secure_enclave' },
    };
    const info = extractPlatformInfo(evidence);
    expect(info.platform).toBe('ios');
  });
});
```

**E2E Tests (Playwright):**
```typescript
// platform-badge.spec.ts
test('shows iOS platform badge for demo capture', async ({ page }) => {
  await page.goto('/verify/demo');
  await expect(page.getByText('iOS')).toBeVisible();
  await expect(page.getByText('Secure Enclave')).toBeVisible();
});

test('shows platform details in tooltip', async ({ page }) => {
  await page.goto('/verify/demo');
  await page.click('[data-testid="platform-badge"]');
  await expect(page.getByRole('tooltip')).toContainText('iPhone 15 Pro');
  await expect(page.getByRole('tooltip')).toContainText('LiDAR depth sensor available');
});

test('platform row appears in evidence panel', async ({ page }) => {
  await page.goto('/verify/demo');
  await expect(page.getByText('Platform & Attestation')).toBeVisible();
});
```

### References

- [Source: docs/prd.md#FR78] - "Verification page indicates platform (iOS/Android) and attestation method"
- [Source: docs/prd.md#Multi-Signal-Detection-Architecture] - Platform trust hierarchy
- [Source: docs/prd.md#Android-Platform-Requirements] - Android attestation levels
- [Source: backend/src/models/evidence.rs] - EvidencePackage with platform field (Story 10-5)
- [Source: apps/web/src/components/Evidence/ConfidenceBadge.tsx] - Badge styling reference
- [Source: apps/web/src/components/Evidence/EvidenceRow.tsx] - Row pattern reference
- [Source: apps/web/src/components/Evidence/MethodBreakdownSection.tsx] - Integration target

### Related Stories

- **Story 10-5: Unified Evidence Schema - READY-FOR-DEV** - **BLOCKS THIS STORY** - adds platform field to evidence
- Story 11-1: Method Breakdown Component - DONE (provides method scores display)
- Story 11-2: Cross-Validation Status Display - REVIEW (provides cross-validation display)
- Story 11-4: Methodology Explainer Page - BACKLOG (will link to detailed explanations)

### API Response Format

The backend returns evidence with platform data (from Story 10-5):

```json
{
  "data": {
    "id": "uuid",
    "confidence_level": "high",
    "evidence": {
      "platform": "ios",
      "hardware_attestation": {
        "status": "pass",
        "level": "secure_enclave",
        "device_model": "iPhone 15 Pro",
        "assertion_verified": true,
        "counter_valid": true,
        "security_level": {
          "attestation_level": "secure_enclave",
          "keymaster_level": null,
          "platform": "ios"
        }
      },
      "depth_analysis": {
        "status": "pass",
        "method": "lidar",
        "is_likely_real_scene": true,
        "depth_variance": 2.4,
        "depth_layers": 5,
        "edge_coherence": 0.87
      },
      "metadata": { ... },
      "processing": { ... }
    }
  }
}
```

### Design Mockup (ASCII)

**Verification Page Header:**
```
+----------------------------------------------------------+
| rial.                                                     |
+----------------------------------------------------------+
|                                                           |
|  [Photo/Video Preview]                                   |
|                                                           |
|  [HIGH CONFIDENCE]  [Apple iOS - Secure Enclave]         |
|                                                           |
|  Captured: Dec 11, 2025 at 2:30 PM                       |
|  Location: San Francisco, CA                              |
+----------------------------------------------------------+
```

**Evidence Panel with Platform Row:**
```
+----------------------------------------------------------+
| Evidence Summary                                    [^]   |
+----------------------------------------------------------+
| Platform & Attestation                                    |
|   [Apple] iOS - Secure Enclave                    [PASS]  |
|   iPhone 15 Pro | LiDAR available                        |
+----------------------------------------------------------+
| Hardware Attestation                                      |
|   Device key verified via Secure Enclave          [PASS]  |
+----------------------------------------------------------+
| Depth Analysis                                            |
|   LiDAR confirms real 3D scene                    [PASS]  |
+----------------------------------------------------------+
| ...                                                       |
+----------------------------------------------------------+
```

**Method Breakdown Header with Platform:**
```
+----------------------------------------------------------+
| Detection Methods                     [Apple iOS] [5 methods] |
+----------------------------------------------------------+
| Overall Confidence: 95% (87%-98%)                        |
| ...                                                       |
+----------------------------------------------------------+
```

---

_Story created: 2025-12-12_
_Epic: 11 - Detection Transparency_
_FR Coverage: FR78 (Verification page indicates platform (iOS/Android) and attestation method)_
_Depends on: **Story 10-5 (BLOCKS - ready-for-dev)**, Story 11-1 (done), Story 11-2 (review)_
_Enables: Story 11-4 (Methodology Explainer Page)_

## Dev Agent Record

### Context Reference

Created from:
- docs/prd.md - FR78 "Verification page indicates platform (iOS/Android) and attestation method"
- docs/epics.md - Epic 11 Detection Transparency definition
- docs/sprint-artifacts/stories/11-1-method-breakdown-component.md - Existing detection UI patterns
- docs/sprint-artifacts/stories/11-2-cross-validation-status-display.md - Cross-validation UI patterns
- docs/sprint-artifacts/stories/10-5-unified-evidence-schema.md - Platform field in evidence
- apps/web/src/components/Evidence/ConfidenceBadge.tsx - Badge styling reference
- apps/web/src/app/verify/[id]/page.tsx - Verification page structure
- packages/shared/src/types/evidence.ts - Existing evidence types

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

**Implementation completed 2025-12-12**

1. Added TypeScript types to `packages/shared/src/types/device.ts`:
   - `Platform` type extended to support 'android'
   - `iOSAttestationLevel`, `AndroidAttestationLevel`, `AttestationLevel` types
   - `PlatformInfo` interface for extracted platform data

2. Created 4 new React components:
   - `PlatformIcon.tsx` - Apple/Android SVG icons with size variants
   - `AttestationLevelBadge.tsx` - Color-coded attestation level display
   - `PlatformBadge.tsx` - Combined platform + attestation with tooltip
   - `PlatformTooltip.tsx` - Detailed platform information panel

3. Created `apps/web/src/lib/platform.ts` with:
   - `extractPlatformInfo()` - Extracts platform info from evidence data
   - `createPlatformEvidenceItem()` - Creates EvidencePanel-compatible item

4. Updated verification page (`apps/web/src/app/verify/[id]/page.tsx`):
   - Extracts platform info from evidence
   - Adds PlatformBadge next to ConfidenceBadge
   - Prepends platform item to EvidencePanel items array
   - Updated all 6 demo captures with explicit platform field

5. Updated MethodBreakdownSection to accept `platform` prop and show compact badge in header

6. Added 92 new unit tests across 5 test files:
   - PlatformIcon.test.tsx (11 tests)
   - AttestationLevelBadge.test.tsx (15 tests)
   - PlatformBadge.test.tsx (27 tests)
   - PlatformTooltip.test.tsx (19 tests)
   - platform.test.ts (19 tests)

**All 350 unit tests pass. TypeScript check passes. Lint passes (1 pre-existing warning unrelated to this story).**

### File List

**To Create:**
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/PlatformIcon.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/AttestationLevelBadge.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/PlatformBadge.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/PlatformTooltip.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/lib/platform.ts`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/__tests__/PlatformIcon.test.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/__tests__/AttestationLevelBadge.test.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/__tests__/PlatformBadge.test.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/__tests__/PlatformTooltip.test.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/lib/__tests__/platform.test.ts`

**To Modify:**
- `/Users/luca/dev/realitycam/packages/shared/src/types/evidence.ts` - Add platform types
- `/Users/luca/dev/realitycam/packages/shared/src/index.ts` - Export new types
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/MethodBreakdownSection.tsx` - Add platform badge to header
- `/Users/luca/dev/realitycam/apps/web/src/app/verify/[id]/page.tsx` - Extract platform info, add platform item to EvidencePanel items, update demo data
