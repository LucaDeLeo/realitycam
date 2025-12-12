# Story 11-2: Cross-Validation Status Display

Status: review

## Story

As a **verification page viewer**,
I want **to see the cross-validation status showing whether detection methods agree or disagree**,
So that **I understand how consistent the evidence is across different analysis techniques and can identify potential anomalies**.

## Acceptance Criteria

### AC 1: Cross-Validation Section in Method Breakdown
**Given** a capture with cross-validation data from iOS (Story 9-5)
**When** viewing the verification page with MethodBreakdownSection
**Then**:
1. A new "Cross-Validation" subsection appears below the method score bars
2. Section only renders when `detection.cross_validation` or `detection.aggregated_confidence.cross_validation` exists
3. Section is visually distinct from method scores (different background or border)
4. Hidden gracefully for captures without cross-validation data (backward compatible)

### AC 2: Validation Status Badge
**Given** cross-validation results are available
**When** rendering the cross-validation section header
**Then** displays validation status badge:
| Status | Color | Icon | Text |
|--------|-------|------|------|
| "pass" | Green | Checkmark | "Methods Agree" |
| "warn" | Yellow | Warning | "Minor Inconsistencies" |
| "fail" | Red | X | "Methods Disagree" |

Badge uses same styling patterns as existing `ConfidenceBadge` component.

### AC 3: Pairwise Consistency Visualization
**Given** cross-validation includes pairwise consistency checks
**When** rendering the details
**Then** displays:
1. Compact grid/list of method pairs with agreement indicators
2. Each pair shows: Method A <-> Method B, agreement score, anomaly flag
3. Visual indicator for anomalous pairs (red/yellow highlight)
4. Example: "LiDAR <-> Moire: 0.87 agreement" with green dot
5. Example: "LiDAR <-> Texture: 0.23 agreement (anomaly)" with red dot
6. Tooltip on hover/tap explains expected relationship (positive/negative/neutral)

### AC 4: Anomaly Summary Display
**Given** cross-validation detected anomalies
**When** rendering the anomaly section
**Then** displays:
1. Count badge: "2 anomalies detected" (or "No anomalies" if empty)
2. Expandable list of anomaly reports with:
   - Anomaly type: "Contradictory Signals", "Too Perfect", "Isolated Disagreement", "Boundary Cluster", "Correlation Anomaly"
   - Severity indicator: Low (yellow dot), Medium (orange dot), High (red dot)
   - Affected methods list
   - Human-readable description
   - Confidence impact (e.g., "-15% penalty")
3. Collapsed by default if >2 anomalies (prevent overwhelming UI)

### AC 5: Confidence Interval Display
**Given** cross-validation includes confidence intervals
**When** rendering interval information
**Then** displays:
1. Overall confidence shown as range: "91% (87%-95%)"
2. Visual representation (error bar or range indicator)
3. Tooltip explaining: "95% confidence the true score is within this range"
4. High uncertainty warning if interval width > 0.3: "High uncertainty - results may vary"

### AC 6: Temporal Consistency (Video Only)
**Given** cross-validation includes temporal consistency data (video captures)
**When** rendering for video captures
**Then** displays:
1. "Temporal Stability" indicator with overall score (0-100%)
2. Frame count analyzed: "30 frames analyzed"
3. Per-method stability scores (mini bars or text)
4. Temporal anomalies if present: "Frame 15: Sudden jump in Moire detection"
5. Hidden entirely for single-frame (photo) captures

### AC 7: Overall Penalty Display
**Given** cross-validation applied confidence penalties
**When** penalty > 0
**Then** displays:
1. Penalty amount: "Cross-validation penalty: -12%"
2. Explanation: "Applied due to detected inconsistencies"
3. Links to affected anomalies
4. Hidden if penalty = 0 (no issues)

### AC 8: Responsive Design
**Given** the cross-validation section
**When** viewed on different screen sizes
**Then**:
1. **Mobile (<640px)**: Stacked layout, collapsed details by default, touch-friendly expand
2. **Tablet (768-1024px)**: 2-column for pairwise grid
3. **Desktop (>1024px)**: Full horizontal layout with inline details
4. Matches responsive patterns from Story 11-1 MethodBreakdownSection

### AC 9: TypeScript Types
**Given** the frontend codebase
**When** implementing the component
**Then** types extend existing detection types:

```typescript
// In packages/shared/src/types/evidence.ts (extend existing)

// ============================================================
// IMPORTANT: This story EXTENDS existing types from Story 11-1
// ============================================================

// 1. ADD to existing DetectionResults interface:
export interface DetectionResults {
  // ... existing fields (moire, texture, artifacts, lidar, aggregated_confidence, computed_at, total_processing_time_ms)
  /** Cross-validation results (may be top-level or nested in aggregated_confidence) */
  cross_validation?: CrossValidationResult;
}

// 2. ADD to existing AggregatedConfidence interface:
export interface AggregatedConfidence {
  // ... existing fields (overall_confidence, confidence_level, method_breakdown, etc.)
  /** Cross-validation result (alternative location - check both) */
  cross_validation?: CrossValidationResult;
  /** Confidence interval bounds */
  confidence_interval?: ConfidenceInterval;
}

// 3. NEW TYPES to add:

/** Cross-validation result between detection methods */
export interface CrossValidationResult {
  /** Overall validation status */
  validation_status: 'pass' | 'warn' | 'fail';
  /** Pairwise consistency checks */
  pairwise_consistencies: PairwiseConsistency[];
  /** Temporal consistency (video only) */
  temporal_consistency?: TemporalConsistency;
  /** Per-method confidence intervals (keys: lidar_depth, moire, texture, artifacts) */
  confidence_intervals: Record<string, ConfidenceInterval>;
  /** Aggregated confidence interval */
  aggregated_interval: ConfidenceInterval;
  /** Detected anomalies */
  anomalies: AnomalyReport[];
  /** Overall penalty applied to confidence */
  overall_penalty: number;
  /** Analysis time in milliseconds */
  analysis_time_ms: number;
  /** Algorithm version */
  algorithm_version: string;
  /** When computed (ISO 8601) */
  computed_at: string;
}

/** Pairwise consistency between two methods */
export interface PairwiseConsistency {
  method_a: string;
  method_b: string;
  expected_relationship: 'positive' | 'negative' | 'neutral';
  actual_agreement: number;
  anomaly_score: number;
  is_anomaly: boolean;
}

/** Temporal consistency for video captures */
export interface TemporalConsistency {
  frame_count: number;
  stability_scores: Record<string, number>;
  anomalies: TemporalAnomaly[];
  overall_stability: number;
}

/** Temporal anomaly in video analysis */
export interface TemporalAnomaly {
  frame_index: number;
  method: string;
  delta_score: number;
  anomaly_type: 'sudden_jump' | 'oscillation' | 'drift';
}

/** Confidence interval bounds (matches backend ConfidenceInterval) */
export interface ConfidenceInterval {
  lower_bound: number;
  point_estimate: number;
  upper_bound: number;
}

/** Anomaly report from cross-validation */
export interface AnomalyReport {
  anomaly_type: 'contradictory_signals' | 'too_high_agreement' | 'isolated_disagreement' | 'boundary_cluster' | 'correlation_anomaly';
  severity: 'low' | 'medium' | 'high';
  affected_methods: string[];
  details: string;
  confidence_impact: number;
}
```

### AC 10: Demo Data Integration
**Given** the existing demo routes (/verify/demo, /verify/demo-video)
**When** viewing demo captures
**Then**:
1. DEMO_CAPTURE includes cross_validation with pass status, no anomalies
2. DEMO_VIDEO_CAPTURE includes cross_validation with temporal_consistency data
3. At least one demo shows warn status with minor anomaly for testing
4. Demo works without backend (static data)

### AC 11: Integration with MethodBreakdownSection
**Given** the existing MethodBreakdownSection component (Story 11-1)
**When** cross-validation data is available
**Then**:
1. CrossValidationSection renders as child within MethodBreakdownSection
2. Appears after method score bars, before processing info footer
3. Visually separated with border-top or divider
4. Collapse/expand state is independent from parent section
5. Smooth animation consistent with existing expand/collapse behavior

## Tasks / Subtasks

- [x] Task 1: Add TypeScript types for cross-validation (AC: #9)
  - [x] **EXTEND existing DetectionResults interface** - add `cross_validation?: CrossValidationResult` field
  - [x] **EXTEND existing AggregatedConfidence interface** - add `cross_validation?: CrossValidationResult` and `confidence_interval?: ConfidenceInterval` fields
  - [x] Add CrossValidationResult interface to packages/shared
  - [x] Add PairwiseConsistency interface
  - [x] Add TemporalConsistency and TemporalAnomaly interfaces
  - [x] Add ConfidenceInterval interface (matches backend naming)
  - [x] Add AnomalyReport interface
  - [x] Export types from shared package

- [x] Task 2: Create ValidationStatusBadge component (AC: #2)
  - [x] Create `apps/web/src/components/Evidence/ValidationStatusBadge.tsx`
  - [x] Implement pass/warn/fail variants with appropriate colors/icons
  - [x] Add accessible labels and aria attributes
  - [x] Match ConfidenceBadge styling patterns

- [x] Task 3: Create PairwiseConsistencyGrid component (AC: #3)
  - [x] Create `apps/web/src/components/Evidence/PairwiseConsistencyGrid.tsx`
  - [x] Display method pairs in compact grid
  - [x] Add agreement score and anomaly indicator per pair
  - [x] Implement tooltip with expected relationship explanation
  - [x] Handle responsive layout (1-col mobile, 2-col tablet+)

- [x] Task 4: Create AnomalyList component (AC: #4)
  - [x] Create `apps/web/src/components/Evidence/AnomalyList.tsx`
  - [x] Display anomaly count badge
  - [x] Implement expandable list of anomaly reports
  - [x] Add severity indicators (colored dots)
  - [x] Display confidence impact per anomaly
  - [x] Collapse by default if >2 anomalies

- [x] Task 5: Create ConfidenceIntervalDisplay component (AC: #5)
  - [x] Create `apps/web/src/components/Evidence/ConfidenceIntervalDisplay.tsx`
  - [x] Display point estimate with range (e.g., "91% (87%-95%)")
  - [x] Add visual error bar or range indicator
  - [x] Show high uncertainty warning when width > 0.3
  - [x] Add tooltip explaining confidence intervals

- [x] Task 6: Create TemporalConsistencyDisplay component (AC: #6)
  - [x] Create `apps/web/src/components/Evidence/TemporalConsistencyDisplay.tsx`
  - [x] Display overall stability score
  - [x] Show frame count analyzed
  - [x] Display per-method stability mini-bars
  - [x] Show temporal anomalies if present
  - [x] Conditionally render (video only, not for photos)

- [x] Task 7: Create CrossValidationSection composite component (AC: #1, #7, #11)
  - [x] Create `apps/web/src/components/Evidence/CrossValidationSection.tsx`
  - [x] Compose ValidationStatusBadge, PairwiseConsistencyGrid, AnomalyList
  - [x] Add ConfidenceIntervalDisplay and TemporalConsistencyDisplay
  - [x] Display overall penalty when > 0
  - [x] Implement collapse/expand with independent state
  - [x] Add visual separator from method scores

- [x] Task 8: Integrate with MethodBreakdownSection (AC: #11)
  - [x] Update MethodBreakdownSection to accept and render CrossValidationSection
  - [x] Pass cross_validation data from detection prop
  - [x] Handle both top-level cross_validation and nested in aggregated_confidence
  - [x] Ensure proper conditional rendering when data unavailable

- [x] Task 9: Implement responsive design (AC: #8)
  - [x] Add Tailwind responsive classes for mobile layout
  - [x] Implement 2-column grid for tablet
  - [x] Full horizontal layout for desktop
  - [x] Test touch interactions on mobile viewport

- [x] Task 10: Add demo data with cross-validation (AC: #10)
  - [x] Update DEMO_CAPTURE with cross_validation (pass, no anomalies)
  - [x] Update DEMO_VIDEO_CAPTURE with cross_validation including temporal_consistency
  - [x] Add DEMO_WARN_CAPTURE constant with warn status and anomaly for /verify/demo-warn route
  - [x] Add route handling for 'demo-warn' ID in page.tsx
  - [x] Verify demo routes render correctly without backend

- [x] Task 11: Unit tests (AC: #1-#11)
  - [x] Test ValidationStatusBadge renders all three states
  - [x] Test PairwiseConsistencyGrid displays pairs correctly
  - [x] Test AnomalyList handles empty and populated states
  - [x] Test ConfidenceIntervalDisplay formatting
  - [x] Test TemporalConsistencyDisplay video-only rendering
  - [x] Test CrossValidationSection composition
  - [x] Test responsive breakpoints

- [x] Task 12: Visual polish and accessibility
  - [x] Add keyboard navigation for expandable sections
  - [x] Add aria-labels for screen readers
  - [x] Ensure color contrast meets WCAG AA
  - [x] Test with VoiceOver/NVDA

## Dev Notes

### Critical Patterns - MUST READ

**TYPE EXTENSION REQUIRED (Task 1 - CRITICAL):**
This story EXTENDS existing types from Story 11-1. Do NOT create new separate interfaces:
1. Add `cross_validation?: CrossValidationResult` to existing `DetectionResults` interface
2. Add `cross_validation?: CrossValidationResult` to existing `AggregatedConfidence` interface
3. Add `confidence_interval?: ConfidenceInterval` to existing `AggregatedConfidence` interface
4. Then add the new types (CrossValidationResult, PairwiseConsistency, etc.)

**Reuse existing components:**
- `ConfidenceBadge` from `@/components/Evidence/ConfidenceBadge.tsx` - for styling reference
- `mapToEvidenceStatus()` from `@/lib/status.ts` - if needed for status mapping
- `MethodBreakdownSection` from Story 11-1 - parent component to integrate with

**Data source locations:**
Cross-validation data may appear in two places in the API response:
1. `detection.cross_validation` - top-level in DetectionResults
2. `detection.aggregated_confidence.cross_validation` - nested in aggregated

Component should check both locations and use whichever is present:
```typescript
const crossValidation = detection.cross_validation
  ?? detection.aggregated_confidence?.cross_validation;
```

**iOS CrossValidationResult structure:**
Reference `ios/Rial/Models/CrossValidationResult.swift` for exact field names and types.
Backend mirrors this in `backend/src/types/detection.rs` with snake_case.

### Component Architecture

```
MethodBreakdownSection (existing, Story 11-1)
  |-- ConfidenceBadge (existing)
  |-- MethodScoreBar (existing, repeated for each method)
  |-- CrossValidationSection (NEW - this story)
        |-- ValidationStatusBadge (NEW)
        |-- ConfidenceIntervalDisplay (NEW)
        |-- PairwiseConsistencyGrid (NEW)
        |-- AnomalyList (NEW)
        |-- TemporalConsistencyDisplay (NEW, video only)
        |-- PenaltyDisplay (inline, if penalty > 0)
```

### Display Name Mappings

```typescript
const VALIDATION_STATUS_DISPLAY: Record<string, { label: string; color: string; icon: string }> = {
  'pass': { label: 'Methods Agree', color: 'green', icon: 'check' },
  'warn': { label: 'Minor Inconsistencies', color: 'yellow', icon: 'warning' },
  'fail': { label: 'Methods Disagree', color: 'red', icon: 'x' },
};

const ANOMALY_TYPE_DISPLAY: Record<string, string> = {
  'contradictory_signals': 'Contradictory Signals',
  'too_high_agreement': 'Too Perfect Agreement',
  'isolated_disagreement': 'Isolated Disagreement',
  'boundary_cluster': 'Boundary Clustering',
  'correlation_anomaly': 'Correlation Anomaly',
};

const SEVERITY_COLORS: Record<string, string> = {
  'low': 'bg-yellow-500 dark:bg-yellow-400',
  'medium': 'bg-orange-500 dark:bg-orange-400',
  'high': 'bg-red-500 dark:bg-red-400',
};

const EXPECTED_RELATIONSHIP_DISPLAY: Record<string, string> = {
  'positive': 'Expected to correlate (both high or both low)',
  'negative': 'Expected to be inverse (one high, one low)',
  'neutral': 'No strong expected relationship',
};
```

### Method Pair Display Names

```typescript
const METHOD_DISPLAY_NAMES: Record<string, string> = {
  'lidar_depth': 'LiDAR',
  'lidar': 'LiDAR',
  'moire': 'Moire',
  'texture': 'Texture',
  'artifacts': 'Artifacts',
  'supporting': 'Supporting',
};
```

### Project Structure Notes

**New Files:**
- `apps/web/src/components/Evidence/ValidationStatusBadge.tsx`
- `apps/web/src/components/Evidence/PairwiseConsistencyGrid.tsx`
- `apps/web/src/components/Evidence/AnomalyList.tsx`
- `apps/web/src/components/Evidence/ConfidenceIntervalDisplay.tsx`
- `apps/web/src/components/Evidence/TemporalConsistencyDisplay.tsx`
- `apps/web/src/components/Evidence/CrossValidationSection.tsx`
- `apps/web/src/components/Evidence/__tests__/ValidationStatusBadge.test.tsx`
- `apps/web/src/components/Evidence/__tests__/PairwiseConsistencyGrid.test.tsx`
- `apps/web/src/components/Evidence/__tests__/AnomalyList.test.tsx`
- `apps/web/src/components/Evidence/__tests__/ConfidenceIntervalDisplay.test.tsx`
- `apps/web/src/components/Evidence/__tests__/TemporalConsistencyDisplay.test.tsx`
- `apps/web/src/components/Evidence/__tests__/CrossValidationSection.test.tsx`

**Modified Files:**
- `packages/shared/src/types/evidence.ts` - Add cross-validation types
- `packages/shared/src/index.ts` - Export new types
- `apps/web/src/components/Evidence/MethodBreakdownSection.tsx` - Integrate CrossValidationSection
- `apps/web/src/app/verify/[id]/page.tsx` - Update demo data with cross_validation

### Testing Standards

**Component Tests (Vitest + Testing Library):**
```typescript
// ValidationStatusBadge.test.tsx
describe('ValidationStatusBadge', () => {
  it('renders green badge for pass status', () => {
    render(<ValidationStatusBadge status="pass" />);
    expect(screen.getByText('Methods Agree')).toBeInTheDocument();
    expect(screen.getByTestId('validation-badge')).toHaveClass('bg-green');
  });

  it('renders yellow badge for warn status', () => {
    render(<ValidationStatusBadge status="warn" />);
    expect(screen.getByText('Minor Inconsistencies')).toBeInTheDocument();
  });

  it('renders red badge for fail status', () => {
    render(<ValidationStatusBadge status="fail" />);
    expect(screen.getByText('Methods Disagree')).toBeInTheDocument();
  });
});

// AnomalyList.test.tsx
describe('AnomalyList', () => {
  it('shows "No anomalies" when list is empty', () => {
    render(<AnomalyList anomalies={[]} />);
    expect(screen.getByText('No anomalies')).toBeInTheDocument();
  });

  it('collapses by default when more than 2 anomalies', () => {
    const anomalies = createManyAnomalies(5);
    render(<AnomalyList anomalies={anomalies} />);
    expect(screen.getByRole('button', { name: /expand/i })).toBeInTheDocument();
  });
});
```

**E2E Tests (Playwright):**
```typescript
// cross-validation.spec.ts
test('shows cross-validation for demo capture', async ({ page }) => {
  await page.goto('/verify/demo');
  await expect(page.getByText('Methods Agree')).toBeVisible();
});

test('shows temporal consistency for video demo', async ({ page }) => {
  await page.goto('/verify/demo-video');
  await expect(page.getByText('Temporal Stability')).toBeVisible();
  await expect(page.getByText(/frames analyzed/i)).toBeVisible();
});

test('shows anomaly details on expand', async ({ page }) => {
  // NOTE: Task 10 must add DEMO_WARN_CAPTURE and 'demo-warn' route handling
  await page.goto('/verify/demo-warn');
  await page.click('[data-testid="expand-anomalies"]');
  await expect(page.getByText('Contradictory Signals')).toBeVisible();
});
```

### Styling Guidelines

**Color Tokens (Tailwind):**
- Pass: `bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300`
- Warn: `bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300`
- Fail: `bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-300`
- Anomaly indicator: Same dot colors as MethodScoreBar status indicators
- Section background: `bg-zinc-50 dark:bg-zinc-900/50`

**Typography:**
- Section header: `text-sm font-semibold`
- Method names: `text-sm font-medium`
- Score values: `text-sm font-semibold`
- Descriptions: `text-xs text-zinc-500`

**Spacing:**
- Section padding: `px-4 sm:px-6 py-4`
- Grid gap: `gap-3`
- Item spacing: `space-y-2`

### API Response Format

The backend returns cross-validation data in this format (from Story 9-7):

```json
{
  "detection": {
    "cross_validation": {
      "validation_status": "pass",
      "pairwise_consistencies": [
        {
          "method_a": "lidar_depth",
          "method_b": "moire",
          "expected_relationship": "negative",
          "actual_agreement": 0.87,
          "anomaly_score": 0.05,
          "is_anomaly": false
        },
        {
          "method_a": "lidar_depth",
          "method_b": "texture",
          "expected_relationship": "positive",
          "actual_agreement": 0.92,
          "anomaly_score": 0.02,
          "is_anomaly": false
        }
      ],
      "temporal_consistency": null,
      "confidence_intervals": {
        "lidar_depth": { "lower_bound": 0.93, "point_estimate": 0.98, "upper_bound": 1.0 },
        "moire": { "lower_bound": 0.0, "point_estimate": 0.0, "upper_bound": 0.1 },
        "texture": { "lower_bound": 0.85, "point_estimate": 0.92, "upper_bound": 0.97 }
      },
      "aggregated_interval": { "lower_bound": 0.87, "point_estimate": 0.95, "upper_bound": 0.98 },
      "anomalies": [],
      "overall_penalty": 0.0,
      "analysis_time_ms": 3,
      "algorithm_version": "1.0",
      "computed_at": "2025-12-12T10:30:00.123Z"
    },
    "aggregated_confidence": { ... }
  }
}
```

### Design Mockup (ASCII)

```
+--------------------------------------------------+
| Cross-Validation                    [Methods Agree] |
+--------------------------------------------------+
| Overall Confidence: 95% (87%-98%)                |
|                                                  |
| Pairwise Consistency                             |
| +----------------------------------------------+ |
| | LiDAR <-> Moire    0.87  [*]                | |
| | LiDAR <-> Texture  0.92  [*]                | |
| | LiDAR <-> Artifacts 0.85  [*]               | |
| | Moire <-> Texture  0.78  [*]                | |
| +----------------------------------------------+ |
|                                                  |
| Anomalies: None                                  |
|                                                  |
| Analysis: 3ms (v1.0)                            |
+--------------------------------------------------+
```

For warn status with anomalies:

```
+--------------------------------------------------+
| Cross-Validation              [Minor Inconsistencies] |
+--------------------------------------------------+
| Overall Confidence: 82% (70%-90%)                |
| ! High uncertainty in results                    |
|                                                  |
| Pairwise Consistency                             |
| +----------------------------------------------+ |
| | LiDAR <-> Moire    0.87  [*]                | |
| | LiDAR <-> Texture  0.23  [!] ANOMALY        | |
| | ...                                          | |
| +----------------------------------------------+ |
|                                                  |
| Anomalies: 1 detected                           |
| +----------------------------------------------+ |
| | [!!] Contradictory Signals         -15%     | |
| |     LiDAR, Texture                          | |
| |     LiDAR indicates flat but texture        | |
| |     classification suggests real material   | |
| +----------------------------------------------+ |
|                                                  |
| Penalty applied: -15%                            |
+--------------------------------------------------+
```

---

_Story created: 2025-12-12_
_Epic: 11 - Detection Transparency_
_FR Coverage: FR77 (Verification page shows cross-validation status - agree/disagree/partial)_
_Depends on: Story 11-1 (MethodBreakdownSection), Story 9-5 (CrossValidationLogic on iOS)_
_Enables: Story 11-3 (Platform Indicator Badge)_

## Dev Agent Record

### Context Reference

N/A - Story created from epic requirements, PRD, and existing code analysis.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

### Completion Notes List

- All 12 tasks completed with passing unit tests (259 tests total)
- TypeScript typecheck passes across all packages
- Cross-validation data displays correctly in demo routes (/verify/demo, /verify/demo-video, /verify/demo-warn)
- Responsive design implemented with mobile, tablet, and desktop layouts
- Accessibility features include keyboard navigation, aria-labels, and role attributes

### File List

**New Files Created:**
- `apps/web/src/components/Evidence/ValidationStatusBadge.tsx` - Pass/warn/fail status badge
- `apps/web/src/components/Evidence/PairwiseConsistencyGrid.tsx` - Method pair agreement grid
- `apps/web/src/components/Evidence/AnomalyList.tsx` - Expandable anomaly list with severity indicators
- `apps/web/src/components/Evidence/ConfidenceIntervalDisplay.tsx` - Confidence range with error bar
- `apps/web/src/components/Evidence/TemporalConsistencyDisplay.tsx` - Video temporal stability (video only)
- `apps/web/src/components/Evidence/CrossValidationSection.tsx` - Composite component
- `apps/web/src/components/Evidence/__tests__/ValidationStatusBadge.test.tsx` - 11 tests
- `apps/web/src/components/Evidence/__tests__/PairwiseConsistencyGrid.test.tsx` - 14 tests
- `apps/web/src/components/Evidence/__tests__/AnomalyList.test.tsx` - 21 tests
- `apps/web/src/components/Evidence/__tests__/ConfidenceIntervalDisplay.test.tsx` - 15 tests
- `apps/web/src/components/Evidence/__tests__/TemporalConsistencyDisplay.test.tsx` - 22 tests
- `apps/web/src/components/Evidence/__tests__/CrossValidationSection.test.tsx` - 26 tests

**Modified Files:**
- `packages/shared/src/types/evidence.ts` - Added cross-validation types (CrossValidationResult, PairwiseConsistency, TemporalConsistency, TemporalAnomaly, ConfidenceInterval, AnomalyReport)
- `packages/shared/src/index.ts` - Exported new types
- `apps/web/src/components/Evidence/MethodBreakdownSection.tsx` - Integrated CrossValidationSection
- `apps/web/src/app/verify/[id]/page.tsx` - Added cross_validation demo data and demo-warn route
