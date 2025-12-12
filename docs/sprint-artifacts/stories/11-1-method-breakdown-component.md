# Story 11-1: Method Breakdown Component

Status: done

## Story

As a **verification page viewer**,
I want **to see a visual breakdown of individual detection methods with their scores**,
So that **I understand exactly HOW the confidence score was calculated and can assess the strength of each evidence type**.

## Acceptance Criteria

### AC 1: Method Breakdown Section in Evidence Panel
**Given** a capture with multi-signal detection data (Epic 9)
**When** viewing the verification page
**Then**:
1. A new "Detection Methods" section appears in the evidence panel below existing checks
2. Section is collapsible/expandable (default: expanded for captures with detection)
3. Section header shows "Detection Methods" with method count badge (e.g., "5 methods")
4. Section is hidden for captures without detection data (backward compatible)

### AC 2: Individual Method Score Bars
**Given** detection results with method breakdown data
**When** rendering the Detection Methods section
**Then** each available method displays:
1. Method name (human-readable): "LiDAR Depth", "Moire Detection", "Texture Analysis", "Artifact Detection"
2. Horizontal progress bar showing score (0-100%)
3. Score value displayed as percentage (e.g., "92%")
4. Status indicator: pass (green), warn (yellow), fail (red), unavailable (gray)
5. Weight indicator showing contribution to overall score (e.g., "55% weight")

### AC 3: Method Status Colors
**Given** a method result
**When** determining visual status
**Then** colors are determined by `status` string (not score):
| Status String | Color | Meaning |
|---------------|-------|---------|
| "pass" | Green | Method passed validation |
| "not_detected" | Green | Detection method found nothing suspicious (good for moire/artifacts) |
| "warn" | Yellow | Borderline result, needs attention |
| "fail" | Red | Method failed or detected recapture indicators |
| "unavailable" | Gray | Method was not available/executed |

**Progress bar fill width** uses numeric score (0-100%), independent of color.

**Special case - Moire/Artifact detection:** A score of 0.0 with status "not_detected" is GOOD (means no screen/print patterns found). Display as green with text "No patterns detected (good)".

### AC 4: Method Tooltips with Details
**Given** a method score bar
**When** hovering (desktop) or tapping (mobile)
**Then** tooltip displays:
1. Full method name and description
2. Raw score value (0.0-1.0)
3. Weight in confidence calculation
4. Contribution to final score (score * weight)
5. Method-specific details:
   - **LiDAR**: depth_variance, depth_layers, edge_coherence
   - **Moire**: detected (yes/no), screen_type if detected
   - **Texture**: classification, material_confidence
   - **Artifacts**: PWM/specular/halftone detected flags

### AC 5: Unavailable Method Display
**Given** a method that was not available
**When** rendering the method row
**Then**:
1. Shows method name with "Unavailable" status
2. Progress bar shows empty/gray state
3. Tooltip explains why unavailable (e.g., "Model not loaded", "Analysis timeout")
4. Does not negatively impact overall confidence display

### AC 6: Overall Confidence Summary
**Given** aggregated confidence results
**When** rendering the breakdown section
**Then** displays at top:
1. Overall confidence score as large number (e.g., "95%")
2. Confidence level badge using existing `ConfidenceBadge` component (High/Medium/Low/Suspicious)
3. Primary signal status indicator (LiDAR valid: yes/no)
4. Supporting signals agreement indicator (agree/disagree)

**IMPORTANT:** Reuse the existing `ConfidenceBadge` component from `@/components/Evidence/ConfidenceBadge.tsx`. The backend maps iOS 5-level confidence (`very_high` -> `high`) so frontend only sees 4 levels.

### AC 7: Responsive Design
**Given** the method breakdown component
**When** viewed on different screen sizes
**Then**:
1. **Mobile (<640px)**: Stacked layout, full-width bars, touch-friendly tooltips
2. **Tablet (640-1024px)**: 2-column layout for method rows
3. **Desktop (>1024px)**: Full horizontal bars with inline details
4. All interactions are accessible (keyboard navigation, screen readers)

### AC 8: Demo Route Support
**Given** the existing demo routes (/verify/demo, /verify/demo-video)
**When** viewing demo captures
**Then**:
1. Demo data includes sample detection results with varied scores
2. All method types represented in demo data
3. At least one method shows "unavailable" state for testing
4. Demo works without backend (static data)

### AC 9: TypeScript Types
**Given** the frontend codebase
**When** implementing the component
**Then** types are properly defined:

```typescript
// In packages/shared/src/types/evidence.ts (extend existing)
// NOTE: Backend maps iOS 5-level confidence to 4-level for storage/display
// So frontend uses existing ConfidenceLevel type ('high' | 'medium' | 'low' | 'suspicious')

export interface DetectionMethodResult {
  available: boolean;
  score: number | null;  // 0.0-1.0, null if unavailable
  weight: number;        // 0.0-1.0
  contribution: number;  // score * weight
  status: string;        // "pass", "fail", "not_detected", "unavailable"
}

export interface AggregatedConfidence {
  overall_confidence: number;
  confidence_level: ConfidenceLevel;  // Uses existing 4-level type (backend maps very_high -> high)
  method_breakdown: Record<string, DetectionMethodResult>;
  primary_signal_valid: boolean;
  supporting_signals_agree: boolean;
  flags: string[];
}

export interface MoireDetectionResult {
  detected: boolean;
  confidence: number;
  screen_type?: 'lcd' | 'oled' | 'high_refresh' | 'unknown';
  status: 'completed' | 'unavailable' | 'failed';
}

export interface TextureClassificationResult {
  classification: 'real_scene' | 'lcd_screen' | 'oled_screen' | 'printed_paper' | 'unknown';
  confidence: number;
  is_likely_recaptured: boolean;
  status: 'success' | 'unavailable' | 'error';
}

export interface ArtifactAnalysisResult {
  pwm_flicker_detected: boolean;
  specular_pattern_detected: boolean;
  halftone_detected: boolean;
  overall_confidence: number;
  is_likely_artificial: boolean;
  status: 'success' | 'unavailable' | 'error';
}

export interface DetectionResults {
  moire?: MoireDetectionResult;
  texture?: TextureClassificationResult;
  artifacts?: ArtifactAnalysisResult;
  aggregated_confidence?: AggregatedConfidence;
  computed_at: string;
  total_processing_time_ms: number;
}
```

### AC 10: Integration with Existing Evidence Panel
**Given** the existing EvidencePanel component
**When** detection data is available
**Then**:
1. Method breakdown appears as new expandable section
2. Existing evidence rows (Hardware Attestation, Depth Analysis, etc.) remain unchanged
3. Clear visual separation between "Verification Checks" and "Detection Methods"
4. Smooth expand/collapse animations consistent with existing panel behavior

## Tasks / Subtasks

- [x] Task 1: Define TypeScript types for detection data (AC: #9)
  - [x] Add DetectionMethodResult interface to packages/shared
  - [x] Add AggregatedConfidence interface
  - [x] Add individual detection result interfaces (Moire, Texture, Artifacts)
  - [x] Add DetectionResults container interface
  - [x] Export types from shared package

- [x] Task 2: Create MethodScoreBar component (AC: #2, #3, #5)
  - [x] Create `apps/web/src/components/Evidence/MethodScoreBar.tsx`
  - [x] Implement horizontal progress bar with score
  - [x] Add color coding based on score thresholds
  - [x] Handle unavailable state with gray styling
  - [x] Add weight indicator display
  - [x] Implement accessible progress bar semantics (role="progressbar")

- [x] Task 3: Create MethodTooltip component (AC: #4)
  - [x] Create `apps/web/src/components/Evidence/MethodTooltip.tsx`
  - [x] Implement hover tooltip for desktop
  - [x] Implement tap/press tooltip for mobile
  - [x] Display method-specific details based on method type
  - [x] Add smooth fade-in animation

- [x] Task 4: Create MethodBreakdownSection component (AC: #1, #6, #10)
  - [x] Create `apps/web/src/components/Evidence/MethodBreakdownSection.tsx`
  - [x] Add collapsible section with header
  - [x] Display overall confidence summary at top
  - [x] Render list of MethodScoreBar components for each method
  - [x] Add primary/supporting signal status indicators
  - [x] Handle empty/no detection data gracefully

- [x] Task 5: Implement responsive design (AC: #7)
  - [x] Add Tailwind responsive classes for mobile layout
  - [x] Implement 2-column grid for tablet
  - [x] Full-width horizontal bars for desktop
  - [x] Test touch interactions on mobile viewport

- [x] Task 6: Update verification page (AC: #1, #10)
  - [x] Modify `apps/web/src/app/verify/[id]/page.tsx`
  - [x] **Update local `CapturePublicData` interface** to include detection fields (lines 344-401 in current file)
  - [x] Parse detection data from capture response
  - [x] Conditionally render MethodBreakdownSection when `detection_available` is true
  - [x] Integrate with existing EvidencePanel layout

- [x] Task 7: Add demo data with detection (AC: #8)
  - [x] Update DEMO_CAPTURE with detection results
  - [x] Update DEMO_VIDEO_CAPTURE with detection results
  - [x] Include varied scores to demonstrate different states
  - [x] Include one unavailable method for testing

- [x] Task 8: Unit tests
  - [x] Test MethodScoreBar renders correctly for all states
  - [x] Test color thresholds are applied correctly
  - [x] Test MethodTooltip displays correct details
  - [x] Test MethodBreakdownSection handles empty detection
  - [x] Test responsive breakpoint behavior

- [x] Task 9: Visual polish and accessibility
  - [x] Add keyboard navigation for expandable section
  - [x] Add aria-labels for screen readers
  - [x] Ensure color contrast meets WCAG AA
  - [x] Test with VoiceOver/NVDA

## Dev Notes

### Critical Patterns - MUST READ

**Reuse existing components:**
- `ConfidenceBadge` from `@/components/Evidence/ConfidenceBadge.tsx` - for confidence level badge
- `mapToEvidenceStatus()` from `@/lib/status.ts` - for status string mapping
- `getStatusText()` from `@/lib/status.ts` - for status display text

**Type alignment:**
- Backend `AggregatedConfidenceLevel` has 5 values but `to_backend_level()` maps `very_high` -> `"high"`
- Frontend `ConfidenceLevel` in shared package has 4 values: `'high' | 'medium' | 'low' | 'suspicious'`
- Use existing `ConfidenceLevel` type - no need to add `very_high`

**Moire/Artifact "not_detected" is GOOD:**
- score=0, status="not_detected" means NO screen/print patterns found
- This is a PASS condition - display green, not red
- Text: "No patterns detected (good)"

### Component Architecture

```
EvidencePanel (existing)
  |-- EvidenceRow (existing) - Hardware Attestation, Depth Analysis, etc.
  |-- MethodBreakdownSection (new)
        |-- ConfidenceBadge (EXISTING - reuse for confidence level)
        |-- MethodScoreBar (repeated for each method)
              |-- MethodTooltip (on hover/tap)
```

**Detection Data Flow:**
1. Backend includes `detection_results` in capture response (Story 9-7)
2. API response includes top-level fields: `detection_available`, `detection`, `detection_confidence_level`, `detection_primary_valid`, `detection_signals_agree`, `detection_method_count`
3. If `detection_available: true`, render MethodBreakdownSection
4. Component maps `detection.aggregated_confidence.method_breakdown` object to MethodScoreBar components

**CapturePublicData interface update required:**
Add these fields to the local interface in `page.tsx`:
```typescript
// Detection fields (Story 9-7)
detection_available?: boolean;
detection?: DetectionResults;  // Full detection payload
detection_confidence_level?: string;
detection_primary_valid?: boolean;
detection_signals_agree?: boolean;
detection_method_count?: number;
```

**Method Display Names:**
```typescript
const METHOD_DISPLAY_NAMES: Record<string, string> = {
  'lidar_depth': 'LiDAR Depth',
  'moire': 'Moire Detection',
  'texture': 'Texture Analysis',
  'artifacts': 'Artifact Detection',
  'supporting': 'Supporting Signals',
};
```

**Score Bar Visualization:**
- Use CSS gradient or Tailwind progress bar utilities
- Width percentage = score * 100 (or 0 if score is null)
- Background: `bg-zinc-200 dark:bg-zinc-700`
- Fill color based on STATUS STRING (not score threshold):
  - "pass" / "not_detected" -> `bg-green-500 dark:bg-green-400`
  - "warn" -> `bg-yellow-500 dark:bg-yellow-400`
  - "fail" -> `bg-red-500 dark:bg-red-400`
  - "unavailable" -> `bg-zinc-400 dark:bg-zinc-500`
- Add subtle animation on initial render (grow from 0 to score)

**Status-to-Color Helper:**
```typescript
function getMethodStatusColor(status: string): string {
  switch (status) {
    case 'pass':
    case 'not_detected':  // Good for moire/artifacts
      return 'bg-green-500 dark:bg-green-400';
    case 'warn':
      return 'bg-yellow-500 dark:bg-yellow-400';
    case 'fail':
      return 'bg-red-500 dark:bg-red-400';
    default:
      return 'bg-zinc-400 dark:bg-zinc-500';
  }
}
```

**Tooltip Implementation:**
- Option 1: Use `@radix-ui/react-tooltip` for consistent behavior (requires `bun add @radix-ui/react-tooltip`)
- Option 2: Implement custom with `useState` + absolute positioning (no new dependency)
- Mobile: tap to show, tap elsewhere to dismiss
- Desktop: hover with 200ms delay before showing
- Recommend Option 2 (custom) to avoid new dependency unless project already uses radix

### Project Structure Notes

**New Files:**
- `apps/web/src/components/Evidence/MethodScoreBar.tsx`
- `apps/web/src/components/Evidence/MethodTooltip.tsx`
- `apps/web/src/components/Evidence/MethodBreakdownSection.tsx`
- `packages/shared/src/types/detection.ts` (if separating from evidence.ts)

**Modified Files:**
- `packages/shared/src/types/evidence.ts` - Add detection types
- `packages/shared/src/index.ts` - Export new detection types
- `apps/web/src/app/verify/[id]/page.tsx` - Update `CapturePublicData` interface AND integrate breakdown section
- `apps/web/src/components/Evidence/EvidencePanel.tsx` - May need wrapper adjustments

### Testing Standards

**Component Tests (Vitest + Testing Library):**
```typescript
// MethodScoreBar.test.tsx
describe('MethodScoreBar', () => {
  it('renders green bar for high score', () => {
    render(<MethodScoreBar method="lidar_depth" score={0.95} weight={0.55} />);
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '95');
    expect(screen.getByTestId('score-bar-fill')).toHaveClass('bg-green-500');
  });

  it('renders gray bar for unavailable method', () => {
    render(<MethodScoreBar method="texture" score={null} weight={0.15} available={false} />);
    expect(screen.getByText('Unavailable')).toBeInTheDocument();
  });
});
```

**E2E Tests (Playwright):**
```typescript
// method-breakdown.spec.ts
test('shows method breakdown for demo capture', async ({ page }) => {
  await page.goto('/verify/demo');
  await expect(page.getByText('Detection Methods')).toBeVisible();
  await expect(page.getByText('LiDAR Depth')).toBeVisible();
  await page.hover('[data-testid="score-bar-lidar"]');
  await expect(page.getByRole('tooltip')).toContainText('Weight: 55%');
});
```

### Styling Guidelines

**Color Tokens (Tailwind):**
- Pass: `bg-green-500 dark:bg-green-400`
- Warn: `bg-yellow-500 dark:bg-yellow-400`
- Fail: `bg-red-500 dark:bg-red-400`
- Unavailable: `bg-zinc-400 dark:bg-zinc-500`
- Track: `bg-zinc-200 dark:bg-zinc-700`

**Typography:**
- Method name: `text-sm font-medium`
- Score: `text-sm font-semibold`
- Weight: `text-xs text-zinc-500`

**Spacing:**
- Gap between method rows: `gap-3`
- Internal padding: `px-4 py-3`
- Progress bar height: `h-2` (8px)

### References

- [Source: docs/prd.md#Phase-3-Verification-UI-Enhancement] - FR76-FR79 requirements
- [Source: docs/epics.md#Epic-11-Detection-Transparency] - Epic overview
- [Source: backend/src/types/detection.rs] - Backend detection types (for type alignment)
- [Source: backend/src/models/evidence.rs] - Evidence package with platform/method fields
- [Source: apps/web/src/components/Evidence/EvidencePanel.tsx] - Existing panel component
- [Source: apps/web/src/components/Evidence/EvidenceRow.tsx] - Existing row component
- [Source: apps/web/src/app/verify/[id]/page.tsx] - Verification page to modify

### Related Stories

- Story 9-7: Backend Multi-Signal Storage - DONE (provides detection data in API)
- Story 9-8: Multi-Signal Integration Testing - DONE (validates end-to-end flow)
- Story 10-5: Unified Evidence Schema - DONE (platform field for iOS/Android)
- Story 11-2: Cross-Validation Status Display - BACKLOG (depends on this story)
- Story 11-3: Platform Indicator Badge - BACKLOG
- Story 11-4: Methodology Explainer Page - BACKLOG

### API Response Format

The backend returns detection data in this format (from Story 9-7):

```json
{
  "capture_id": "uuid",
  "confidence_level": "high",
  "evidence": {
    "platform": "ios",
    "hardware_attestation": { ... },
    "depth_analysis": { "method": "lidar", ... },
    "metadata": { ... },
    "processing": { ... }
  },
  "detection_available": true,
  "detection": {
    "moire": {
      "detected": false,
      "confidence": 0.0,
      "status": "completed"
    },
    "texture": {
      "classification": "real_scene",
      "confidence": 0.92,
      "status": "success"
    },
    "artifacts": {
      "pwm_flicker_detected": false,
      "specular_pattern_detected": false,
      "halftone_detected": false,
      "overall_confidence": 0.0,
      "status": "success"
    },
    "aggregated_confidence": {
      "overall_confidence": 0.95,
      "confidence_level": "high",
      "method_breakdown": {
        "lidar_depth": { "available": true, "score": 0.98, "weight": 0.55, "contribution": 0.539, "status": "pass" },
        "moire": { "available": true, "score": 0.0, "weight": 0.15, "contribution": 0.0, "status": "not_detected" },
        "texture": { "available": true, "score": 0.92, "weight": 0.15, "contribution": 0.138, "status": "pass" },
        "supporting": { "available": true, "score": 0.79, "weight": 0.15, "contribution": 0.118, "status": "pass" }
      },
      "primary_signal_valid": true,
      "supporting_signals_agree": true,
      "flags": []
    },
    "computed_at": "2025-12-11T10:30:00.123Z",
    "total_processing_time_ms": 85
  }
}
```

### Design Mockup (ASCII)

```
+--------------------------------------------------+
| Detection Methods                        [5 methods] |
+--------------------------------------------------+
| Overall Confidence                                |
|  ============================================ 95% |
|  [HIGH] Primary: PASS | Supporting: AGREE        |
+--------------------------------------------------+
| LiDAR Depth (55% weight)                         |
|  [============================================] 98% |
|                                                  |
| Moire Detection (15% weight)                     |
|  [                                          ] 0%  |
|  Not detected (good)                             |
|                                                  |
| Texture Analysis (15% weight)                    |
|  [========================================  ] 92% |
|  Classification: Real Scene                      |
|                                                  |
| Artifact Detection (15% weight)                  |
|  [                                          ] 0%  |
|  No artifacts detected (good)                    |
+--------------------------------------------------+
```

---

_Story created: 2025-12-12_
_Epic: 11 - Detection Transparency_
_FR Coverage: FR76 (Verification page displays detection method breakdown with scores)_
_Depends on: Epic 9 Stories (iOS multi-signal detection), Story 9-7 (Backend storage)_
_Enables: Story 11-2 (Cross-Validation Status Display)_

## Dev Agent Record

### Context Reference

N/A - Story created from epic requirements and existing code analysis.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

**Implementation completed 2025-12-12:**
- Added 9 new TypeScript types for detection data (DetectionMethodStatus, DetectionMethodResult, AggregatedConfidence, MoireScreenType, MoireDetectionResult, TextureClassification, TextureClassificationResult, ArtifactAnalysisResult, DetectionResults)
- Created MethodScoreBar component with status-based color coding (pass/not_detected=green, warn=yellow, fail=red, unavailable=gray)
- Created MethodTooltip component with method-specific details for moire, texture, and artifacts
- Created MethodBreakdownSection with collapsible header, overall confidence summary, primary/supporting signal indicators
- Integrated with verification page - section renders when detection_available is true
- Added detection demo data to both DEMO_CAPTURE (all methods pass) and DEMO_VIDEO_CAPTURE (artifacts unavailable)
- Added 70 unit tests for the 3 new components (all passing)
- Added accessibility features: aria-labels, role attributes, keyboard navigation, screen reader support

**Key Implementation Decisions:**
- Used click-to-toggle tooltips instead of hover for better mobile support
- Color coding is based on status string (not score threshold) per AC3 requirements
- "not_detected" status is treated as GOOD (green) for moire/artifacts per story requirements
- LiDAR is sorted first in method breakdown as primary signal

**Code Review Fixes (2025-12-12):**
- HIGH #1: Added `lidar` field to methodDetails prop to pass LiDAR details (depth_variance, depth_layers, edge_coherence) to tooltip
- HIGH #2: Added `unavailable_reason` field to DetectionMethodResult type and display in tooltip
- MEDIUM #3: Changed responsive breakpoint from `lg:grid-cols-2` to `md:grid-cols-2` per AC7 tablet spec (768px+)
- MEDIUM #4: Added clarifying comment that `confidence` field serves same purpose as story's `material_confidence`
- MEDIUM #5: Added comprehensive E2E tests for method breakdown component (`method-breakdown.spec.ts`)
- LOW #6: Cleaned up extra blank line after countAvailableMethods function
- LOW #7: Updated tooltip docstring to accurately describe click-to-toggle behavior
- Added `LidarDepthDetails` interface to shared types package
- Updated demo data to include lidar details and unavailable_reason examples

### File List

**Created:**
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/MethodScoreBar.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/MethodTooltip.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/MethodBreakdownSection.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/__tests__/MethodScoreBar.test.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/__tests__/MethodTooltip.test.tsx`
- `/Users/luca/dev/realitycam/apps/web/src/components/Evidence/__tests__/MethodBreakdownSection.test.tsx`
- `/Users/luca/dev/realitycam/apps/web/tests/e2e/method-breakdown.spec.ts` - E2E tests for method breakdown component

**Modified:**
- `/Users/luca/dev/realitycam/packages/shared/src/types/evidence.ts` - Added detection type interfaces, LidarDepthDetails, unavailable_reason field
- `/Users/luca/dev/realitycam/packages/shared/src/index.ts` - Exported new detection types including LidarDepthDetails
- `/Users/luca/dev/realitycam/apps/web/src/app/verify/[id]/page.tsx` - Added MethodBreakdownSection integration, detection fields to CapturePublicData, detection demo data with lidar details
