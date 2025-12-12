# Story 11-4: Methodology Explainer Page

Status: done

## Story

As a **verification page viewer or curious user**,
I want **a dedicated page explaining HOW rial.'s verification methodology works**,
So that **I understand the technical basis for confidence scores and can assess the trustworthiness of the verification approach**.

## Context

This story implements FR79: "Verification page explains confidence calculation methodology."

This is the final story in Epic 11 (Detection Transparency), which focuses on helping users understand HOW confidence scores are calculated. The previous stories implemented:
- Story 11-1: MethodBreakdownSection - shows individual detection method scores
- Story 11-2: CrossValidationSection - shows method agreement status
- Story 11-3: PlatformBadge - shows platform and attestation level

This story creates a dedicated methodology page that explains:
1. The overall verification philosophy (attestation-first trust model)
2. Each detection method in detail (LiDAR, Moire, Texture, Artifacts)
3. How cross-validation works
4. Platform-specific attestation (iOS Secure Enclave, Android TEE/StrongBox)
5. Confidence calculation methodology
6. Known limitations and threat model

**Target Personas:**
- **Casual viewer (Jordan):** Wants quick understanding of what "HIGH confidence" means
- **Journalist (Alex):** Needs to explain verification methodology to editors/readers
- **Forensic analyst (Riley):** Wants detailed technical information and threat model

## Acceptance Criteria

### AC 1: Methodology Page Route
**Given** a user viewing any verification page
**When** they want to learn about the methodology
**Then**:
1. Route exists at `/methodology` (static page)
2. Page is accessible without authentication
3. Page loads quickly (no backend dependency for content)
4. SEO-optimized with appropriate meta tags
5. Shareable URL for linking in articles/reports

### AC 2: "How does this work?" Link from Verification Pages
**Given** a verification page (/verify/[id])
**When** rendering the page
**Then**:
1. A "How does this work?" or "Learn more" link appears prominently
2. Link opens methodology page (same tab or new tab based on user preference)
3. Link placement: near MethodBreakdownSection header or below confidence badge
4. Link uses subtle but discoverable styling (not distracting from verification content)

### AC 3: Page Structure - Progressive Disclosure
**Given** the methodology page
**When** rendering for different user expertise levels
**Then** uses progressive disclosure:
1. **Top Section:** Executive summary (2-3 sentences) explaining the core approach
2. **Quick Overview:** Visual diagram showing evidence flow
3. **Method Cards:** Expandable sections for each detection method
4. **Deep Dive:** Technical details for forensic analysts (collapsible)
5. **FAQ Section:** Common questions and answers
6. Smooth scroll navigation between sections

### AC 4: Attestation-First Trust Model Section
**Given** the methodology page
**When** rendering the trust model explanation
**Then** displays:
1. Clear statement: "Hardware attestation is the PRIMARY signal, detection algorithms are SUPPORTING evidence"
2. Trust hierarchy diagram:
   - Level 1: Hardware Attestation (Secure Enclave, TEE/StrongBox)
   - Level 2: Physical Signals (LiDAR depth, Parallax)
   - Level 3: Detection Algorithms (Moire, Texture, Artifacts)
3. Explanation of why this ordering matters (Chimera attack reference)
4. What "attestation" means in practical terms

### AC 5: LiDAR Depth Detection Explanation
**Given** the LiDAR section of the methodology page
**When** expanded/viewed
**Then** displays:
1. What LiDAR is and how it works (1-2 paragraphs)
2. Why LiDAR is valuable for verification:
   - Real 3D scenes have depth variance, multiple layers
   - Flat images (screens, prints) have uniform depth (~0.3-0.5m)
3. Visual diagram showing real scene vs flat surface depth
4. Key metrics explained: depth_variance, depth_layers, edge_coherence
5. Limitations: Cannot detect 3D physical replicas
6. Device support: iPhone Pro only (12 Pro through 17 Pro)

### AC 6: Moire Pattern Detection Explanation
**Given** the Moire section of the methodology page
**When** expanded/viewed
**Then** displays:
1. What Moire patterns are (interference patterns from screen pixel grids)
2. How 2D FFT (Fast Fourier Transform) detects them
3. Visual example of Moire patterns on screens
4. Why "not_detected" is GOOD (means no screen patterns found)
5. Detection capabilities: LCD, OLED, high-refresh displays
6. Limitations: Chimera-style attacks can bypass (hence SUPPORTING not PRIMARY)
7. Weight in confidence: 15%

### AC 7: Texture Classification Explanation
**Given** the Texture section of the methodology page
**When** expanded/viewed
**Then** displays:
1. What texture classification does (ML model distinguishes materials)
2. Classifications: real_scene, lcd_screen, oled_screen, printed_paper
3. How CoreML/TFLite model was trained (high-level)
4. Confidence threshold for classification
5. Limitations: Vulnerable to adversarial examples
6. Weight in confidence: 15%

### AC 8: Artifact Detection Explanation
**Given** the Artifacts section of the methodology page
**When** expanded/viewed
**Then** displays:
1. What artifacts are detected:
   - PWM flicker (screen backlight modulation)
   - Specular reflection patterns
   - Halftone patterns (printed material)
2. How each is detected (brief technical explanation)
3. Why "not_detected" is GOOD
4. Limitations and false positive scenarios
5. Weight in confidence: 15%

### AC 9: Cross-Validation Explanation
**Given** the Cross-Validation section of the methodology page
**When** expanded/viewed
**Then** displays:
1. Why cross-validation matters (consistency check)
2. Expected relationships between methods:
   - LiDAR vs Moire: Negative (if LiDAR passes, Moire should not detect screen)
   - LiDAR vs Texture: Positive (both should indicate real scene)
3. What "agreement" vs "disagreement" means
4. Anomaly types and their implications
5. Confidence penalty calculation
6. Temporal consistency for video (frame-by-frame stability)

### AC 10: Platform & Attestation Explanation
**Given** the Platform section of the methodology page
**When** expanded/viewed
**Then** displays:
1. **iOS Secure Enclave:**
   - What it is (dedicated security chip)
   - How DCAppAttest works (key generation, attestation, assertion)
   - Why it's the highest trust level
   - Device support (all iPhone Pro 12+)
2. **Android StrongBox:**
   - What it is (Hardware Security Module)
   - How Key Attestation works
   - Trust level: Comparable to iOS Secure Enclave
3. **Android TEE:**
   - What it is (Trusted Execution Environment)
   - Difference from StrongBox (hardware-isolated but weaker)
   - Why it's MEDIUM trust level
4. **Unverified:**
   - What it means (attestation failed)
   - Captures still possible but lower confidence

### AC 11: Confidence Calculation Explanation
**Given** the Confidence Calculation section of the methodology page
**When** expanded/viewed
**Then** displays:
1. Formula/algorithm overview:
   - iOS Pro: LiDAR (55%) + Moire (15%) + Texture (15%) + Supporting (15%)
   - Android: Attestation (20%) + Parallax (30%) + Detection (50%)
2. Confidence level thresholds:
   - HIGH: 85%+ with attestation pass
   - MEDIUM: 60-85% OR attestation issues
   - LOW: Below 60%
   - SUSPICIOUS: Any check explicitly FAIL
3. Cross-validation penalty application
4. Why method weights differ (primary vs supporting signals)

### AC 12: Known Limitations & Threat Model
**Given** the Limitations section of the methodology page
**When** expanded/viewed
**Then** displays:
1. **What we CAN detect:**
   - Screenshots/photos of screens
   - Photos of printed images
   - Device compromise (jailbreak/root)
   - Timestamp manipulation
2. **What we CANNOT detect:**
   - Perfectly constructed 3D physical replicas
   - Nation-state hardware attacks
   - Semantic truth (staged physical scenes)
   - Pre-capture manipulation
3. **Threat model assumptions:**
   - Secure Enclave is trustworthy
   - App binary is not modified
4. **Chimera attack note:** Link to academic research, explanation of mitigation

### AC 13: FAQ Section
**Given** the FAQ section of the methodology page
**When** expanded/viewed
**Then** displays common questions:
1. "What does HIGH confidence actually mean?"
2. "Can this be fooled?"
3. "Why does my capture show MEDIUM confidence?"
4. "What is LiDAR and why does it matter?"
5. "Why is the Moire score 0% but still green?"
6. "How is this different from AI deepfake detection?"
7. "Can I trust captures from Android devices?"
8. "What happens if I capture a photo of a screen?"

### AC 14: Visual Design Requirements
**Given** the methodology page
**When** rendering
**Then**:
1. Uses existing rial. design system (Tailwind, zinc colors, etc.)
2. Includes visual diagrams/illustrations for key concepts
3. Uses expandable/collapsible sections for progressive disclosure
4. Responsive design (mobile, tablet, desktop)
5. Dark mode support
6. Accessible (WCAG AA compliant)
7. Smooth scroll navigation
8. Table of contents sidebar (desktop only)

### AC 15: Demo/Interactive Elements (Optional Enhancement)
**Given** the methodology page
**When** viewing detection method sections
**Then** optionally displays:
1. Interactive comparison: real scene vs screen capture depth
2. Sample Moire pattern visualization
3. Confidence calculation simulator (input scores, see result)
4. Link to demo captures (/verify/demo, /verify/demo-video)

### AC 16: TypeScript Types
**Given** the frontend codebase
**When** implementing the page
**Then** minimal new types needed (mostly static content):

```typescript
// If using structured content model
interface MethodologySection {
  id: string;
  title: string;
  summary: string;
  content: React.ReactNode;
  icon?: React.ReactNode;
  expandedByDefault?: boolean;
}

interface FAQItem {
  question: string;
  answer: string;
  category?: 'general' | 'technical' | 'trust';
}
```

## Tasks / Subtasks

- [x] Task 1: Create methodology page route (AC: #1)
  - [x] Create `apps/web/src/app/methodology/page.tsx`
  - [x] Add page metadata (title, description, OpenGraph)
  - [x] Configure static generation (no dynamic data)
  - [x] Add canonical URL and structured data

- [x] Task 2: Add "How does this work?" link to verification page (AC: #2)
  - [x] Update `apps/web/src/app/verify/[id]/page.tsx`
  - [x] Add link below MethodBreakdownSection or near confidence badge
  - [x] Style link to be discoverable but not distracting
  - [x] Consider icon (question mark, info circle)

- [x] Task 3: Create page layout with progressive disclosure (AC: #3)
  - [x] Create `apps/web/src/components/Methodology/ExpandableSection.tsx`
  - [x] Add executive summary section at top
  - [x] Create expandable section component
  - [x] Add smooth scroll navigation
  - [x] Add table of contents sidebar (desktop only)

- [x] Task 4: Create attestation-first trust model section (AC: #4)
  - [x] Create `apps/web/src/components/Methodology/TrustModelSection.tsx`
  - [x] Add trust hierarchy diagram (SVG or component)
  - [x] Write clear explanation of attestation-first approach
  - [x] Reference Chimera attack (with external link)

- [x] Task 5: Create LiDAR depth explanation (AC: #5)
  - [x] Create `apps/web/src/components/Methodology/LidarSection.tsx`
  - [x] Add depth comparison diagram (real scene vs flat)
  - [x] Explain metrics (variance, layers, coherence)
  - [x] List supported devices (iPhone Pro models)
  - [x] Document limitations

- [x] Task 6: Create Moire detection explanation (AC: #6)
  - [x] Create `apps/web/src/components/Methodology/MoireSection.tsx`
  - [x] Add Moire pattern visual example
  - [x] Explain FFT detection approach
  - [x] Clarify "not_detected = good"
  - [x] Document limitations (Chimera vulnerability)

- [x] Task 7: Create texture classification explanation (AC: #7)
  - [x] Create `apps/web/src/components/Methodology/TextureSection.tsx`
  - [x] Explain ML classification categories
  - [x] Show confidence thresholds
  - [x] Document limitations

- [x] Task 8: Create artifact detection explanation (AC: #8)
  - [x] Create `apps/web/src/components/Methodology/ArtifactsSection.tsx`
  - [x] Explain PWM, specular, halftone detection
  - [x] Clarify "not_detected = good"
  - [x] Document limitations

- [x] Task 9: Create cross-validation explanation (AC: #9)
  - [x] Create `apps/web/src/components/Methodology/CrossValidationMethodSection.tsx`
  - [x] Show expected relationships table/diagram
  - [x] Explain anomaly types
  - [x] Document penalty calculation

- [x] Task 10: Create platform & attestation explanation (AC: #10)
  - [x] Create `apps/web/src/components/Methodology/PlatformSection.tsx`
  - [x] Explain iOS Secure Enclave
  - [x] Explain Android StrongBox and TEE
  - [x] Show platform comparison table
  - [x] Document what "unverified" means

- [x] Task 11: Create confidence calculation explanation (AC: #11)
  - [x] Create `apps/web/src/components/Methodology/ConfidenceSection.tsx`
  - [x] Show weight formulas (iOS vs Android)
  - [x] Explain confidence level thresholds
  - [x] Document cross-validation impact

- [x] Task 12: Create limitations & threat model section (AC: #12)
  - [x] Create `apps/web/src/components/Methodology/LimitationsSection.tsx`
  - [x] List what CAN vs CANNOT be detected
  - [x] Document threat model assumptions
  - [x] Add Chimera attack reference with mitigation

- [x] Task 13: Create FAQ section (AC: #13)
  - [x] Create `apps/web/src/components/Methodology/FAQSection.tsx`
  - [x] Add FAQ data structure with questions/answers
  - [x] Implement expandable FAQ items
  - [x] Cover all specified questions

- [x] Task 14: Visual design and diagrams (AC: #14)
  - [x] Create or source trust hierarchy diagram
  - [x] Create or source depth comparison diagram
  - [x] Create or source Moire pattern example
  - [x] Ensure responsive layout works
  - [x] Verify dark mode support
  - [x] Test accessibility (keyboard nav, screen reader)

- [ ] Task 15: Unit tests (deferred)
  - [ ] Test methodology page renders
  - [ ] Test section expand/collapse behavior
  - [ ] Test FAQ accordion behavior
  - [ ] Test responsive layout breakpoints
  - [ ] Test link from verification page

- [ ] Task 16: E2E tests (Playwright) (deferred)
  - [ ] Test methodology page loads at /methodology
  - [ ] Test navigation from verification page
  - [ ] Test section interactions
  - [ ] Test FAQ interactions

## Dev Notes

### Critical Patterns - MUST READ

**This is primarily a CONTENT story:**
Unlike Stories 11-1/11-2/11-3 which were component-heavy, this story is content-heavy. The main work is writing clear, accurate explanations of the methodology. Component development is secondary.

**Technology Stack:**
- **Next.js 16** with App Router (use `export const metadata` for SEO)
- **React 19** - use Server Components by default, 'use client' only for interactivity
- **TailwindCSS 4** - existing design tokens in codebase

**Reuse existing components:**
- Expandable sections: Copy pattern from `apps/web/src/components/Evidence/MethodBreakdownSection.tsx` (lines 99-140) - includes `aria-expanded`, `aria-controls`, keyboard handling
- FAQ accordion: Copy pattern from `apps/web/src/components/Evidence/AnomalyList.tsx`
- Platform visuals: Reuse `PlatformBadge`, `AttestationLevelBadge` from Story 11-3 in Platform Section (AC #10)
- Use existing Tailwind design tokens (zinc colors, spacing, typography)

**Content sources (with specific line references):**
All technical content should be derived from these source documents:
- `docs/prd.md`:
  - Multi-Signal Detection Architecture (lines 312-467) - detection methods, weights, trust hierarchy
  - Evidence Architecture (lines 609-682) - depth analysis algorithm, confidence calculation
  - Threat Model (lines 910-950) - what can/cannot be detected
  - FR76-FR79 (lines 839-845) - Phase 3 verification UI requirements
- `docs/architecture.md` - Evidence Architecture, Security Architecture
- `docs/epics.md` - Epic 11 definition (lines 3250-3268)
- Completed stories: 11-1, 11-2, 11-3 - for component patterns and type definitions

**Diagrams:**
Consider using:
- Tailwind CSS diagrams (divs/borders for simple hierarchies)
- SVG for more complex diagrams
- Mermaid for flowcharts (if build supports)
- Or simple ASCII art converted to visual component

**SEO considerations (Next.js App Router pattern):**
```tsx
// apps/web/src/app/methodology/page.tsx
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'How rial. Verification Works | Methodology',
  description: 'Learn how rial. verifies photo and video authenticity using LiDAR depth analysis, hardware attestation, and multi-signal detection.',
  openGraph: {
    title: 'How rial. Verification Works',
    description: 'Understanding rial.\'s attestation-first trust model for photo and video authenticity.',
    type: 'article',
  },
};
```

### Component Architecture

```
/methodology page
  |-- MethodologyLayout (wrapper with TOC sidebar)
        |-- ExecutiveSummary (top, always visible)
        |-- TrustModelSection (expandable)
        |-- Detection Methods (group of expandable sections)
        |     |-- LidarSection
        |     |-- MoireSection
        |     |-- TextureSection
        |     |-- ArtifactsSection
        |-- CrossValidationSection (expandable)
        |-- PlatformSection (expandable)
        |-- ConfidenceSection (expandable)
        |-- LimitationsSection (expandable)
        |-- FAQSection (accordion)
```

### Page Navigation

```typescript
// Table of contents structure
const METHODOLOGY_SECTIONS = [
  { id: 'overview', label: 'Overview' },
  { id: 'trust-model', label: 'Trust Model' },
  { id: 'detection-methods', label: 'Detection Methods' },
  { id: 'lidar', label: 'LiDAR Depth', indent: true },
  { id: 'moire', label: 'Moire Detection', indent: true },
  { id: 'texture', label: 'Texture Analysis', indent: true },
  { id: 'artifacts', label: 'Artifact Detection', indent: true },
  { id: 'cross-validation', label: 'Cross-Validation' },
  { id: 'platforms', label: 'Platforms & Attestation' },
  { id: 'confidence', label: 'Confidence Calculation' },
  { id: 'limitations', label: 'Limitations' },
  { id: 'faq', label: 'FAQ' },
];
```

### Expandable Section Pattern

**Reference implementation:** Copy pattern from `apps/web/src/components/Evidence/MethodBreakdownSection.tsx` (lines 99-140)

Key requirements:
- `'use client'` directive for interactivity
- `aria-expanded` and `aria-controls` attributes
- `onKeyDown` handler for Enter/Space keys
- Chevron rotation animation on expand/collapse
- `max-h-0`/`max-h-[2000px]` transition for smooth animation

### FAQ Data Structure

```typescript
// FAQ content defined in AC #13 - implement as structured array:
interface FAQItem {
  question: string;
  answer: string;
  category: 'general' | 'technical' | 'trust';
}

// See AC #13 for the 8 required FAQ questions and answers
const FAQ_ITEMS: FAQItem[] = [
  // Implement all 8 questions from AC #13
];
```

### Content Writing Guidelines

1. **Accuracy:** All technical claims must be verifiable from PRD/architecture docs
2. **Clarity:** Write for intelligent non-experts; avoid jargon without explanation
3. **Honesty:** Be explicit about limitations; don't oversell capabilities
4. **Structure:** Use bullet points, tables, and diagrams to aid scanning
5. **Tone:** Professional but approachable; this builds trust

### Project Structure Notes

**New Files:**
- `apps/web/src/app/methodology/page.tsx` - Main page (Server Component)
- `apps/web/src/components/Methodology/` directory:
  - `index.ts` - Barrel export for all components
  - `MethodologyLayout.tsx` - Wrapper with TOC sidebar ('use client')
  - `ExpandableSection.tsx` - Reusable collapsible section ('use client')
  - `TableOfContents.tsx` - Desktop sidebar navigation ('use client')
  - `TrustModelSection.tsx` - Trust hierarchy content (Server Component)
  - `LidarSection.tsx` - LiDAR explanation (Server Component)
  - `MoireSection.tsx` - Moire detection explanation (Server Component)
  - `TextureSection.tsx` - Texture classification (Server Component)
  - `ArtifactsSection.tsx` - Artifact detection (Server Component)
  - `CrossValidationSection.tsx` - Cross-validation explanation (Server Component)
  - `PlatformSection.tsx` - Platform & attestation (Server Component, uses PlatformBadge from 11-3)
  - `ConfidenceSection.tsx` - Confidence calculation (Server Component)
  - `LimitationsSection.tsx` - Known limitations (Server Component)
  - `FAQSection.tsx` - FAQ accordion ('use client')

**Modified Files:**
- `apps/web/src/app/verify/[id]/page.tsx` - Add "How does this work?" link (CRITICAL - see AC #2)

### Testing Standards

**Component Tests (Vitest + Testing Library):**
```typescript
// MethodologyPage.test.tsx
describe('MethodologyPage', () => {
  it('renders executive summary', () => {
    render(<MethodologyPage />);
    expect(screen.getByText(/attestation-first/i)).toBeInTheDocument();
  });

  it('expands section on click', async () => {
    render(<MethodologyPage />);
    const lidarSection = screen.getByRole('button', { name: /lidar/i });
    await userEvent.click(lidarSection);
    expect(screen.getByText(/depth variance/i)).toBeVisible();
  });

  it('FAQ accordion works', async () => {
    render(<MethodologyPage />);
    const faqButton = screen.getByRole('button', { name: /what does high confidence/i });
    await userEvent.click(faqButton);
    expect(screen.getByText(/hardware attestation verified/i)).toBeVisible();
  });
});
```

**WCAG AA Accessibility Requirements:**
- Heading hierarchy: h1 (page title) > h2 (section headers) > h3 (subsections)
- Focus indicators: visible on all interactive elements
- Color contrast: 4.5:1 minimum for normal text, 3:1 for large text
- Expandable sections: `aria-expanded`, `aria-controls` attributes
- Icons: `aria-hidden="true"` for decorative icons

**E2E Tests (Playwright):**
```typescript
// methodology.spec.ts
test('methodology page loads', async ({ page }) => {
  await page.goto('/methodology');
  await expect(page).toHaveTitle(/methodology/i);
  await expect(page.getByRole('heading', { name: /how rial/i })).toBeVisible();
});

test('link from verification page works', async ({ page }) => {
  await page.goto('/verify/demo');
  await page.click('[data-testid="methodology-link"]');
  await expect(page).toHaveURL('/methodology');
});

test('table of contents navigation works', async ({ page }) => {
  await page.goto('/methodology');
  await page.click('[data-testid="toc-lidar"]');
  await expect(page.locator('#lidar')).toBeInViewport();
});
```

### Styling Guidelines

**Typography:**
- Page title: `text-3xl font-bold`
- Section headers: `text-xl font-semibold`
- Subsection headers: `text-lg font-medium`
- Body text: `text-base leading-relaxed`
- Captions/notes: `text-sm text-zinc-500`

**Section backgrounds:**
- Default: `bg-white dark:bg-zinc-900`
- Highlighted: `bg-zinc-50 dark:bg-zinc-800/50`
- Callout: `bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-500`

**Spacing:**
- Section padding: `py-6 px-4 sm:px-6 lg:px-8`
- Between sections: `space-y-8`
- Within sections: `space-y-4`

### References

- [Source: docs/prd.md#Multi-Signal-Detection-Architecture] - Detection methods, weights, trust hierarchy
- [Source: docs/prd.md#Evidence-Architecture-MVP] - Evidence checks, confidence calculation
- [Source: docs/prd.md#Threat-Model-Summary] - What can/cannot be detected
- [Source: docs/prd.md#FR76-FR79] - Phase 3 verification UI requirements
- [Source: docs/architecture.md#Evidence-Architecture] - Depth analysis algorithm, confidence calculation
- [Source: docs/architecture.md#Security-Architecture] - Attestation flow, key management
- [Source: docs/epics.md#Epic-11] - Detection Transparency goal and approach
- [Source: apps/web/src/components/Evidence/MethodBreakdownSection.tsx] - Component patterns
- [Source: apps/web/src/components/Evidence/CrossValidationSection.tsx] - Expandable section pattern

### Related Stories

- **Story 11-1: Method Breakdown Component** - DONE - displays method scores
- **Story 11-2: Cross-Validation Status Display** - REVIEW - displays agreement status
- **Story 11-3: Platform Indicator Badge** - DONE - displays platform and attestation
- Epic 9 Stories - iOS multi-signal detection (provides data for methodology explanation)
- Epic 10 Stories - Cross-platform foundation (Android attestation explanation)

### Content Outline (Draft)

#### Executive Summary (Always Visible)
> rial. verifies photo and video authenticity using an **attestation-first trust model**. Hardware attestation (iOS Secure Enclave, Android TEE/StrongBox) proves the capture device is genuine. LiDAR depth analysis proves the camera was pointed at a real 3D scene, not a screen or print. Supporting detection methods (Moire, texture, artifacts) provide defense-in-depth.

#### Trust Model Diagram
```
                    TRUST HIERARCHY

    +-----------------------------------+
    |    HARDWARE ATTESTATION           |  PRIMARY
    |    (Secure Enclave / StrongBox)   |  Highest Trust
    +-----------------------------------+
                    |
    +-----------------------------------+
    |    PHYSICAL DEPTH SIGNALS         |  STRONG
    |    (LiDAR / Multi-Camera Parallax)|  Supporting
    +-----------------------------------+
                    |
    +-----------------------------------+
    |    DETECTION ALGORITHMS           |  SUPPORTING
    |    (Moire / Texture / Artifacts)  |  Vulnerable to adversarial
    +-----------------------------------+
```

---

_Story created: 2025-12-12_
_Epic: 11 - Detection Transparency_
_FR Coverage: FR79 (Verification page explains confidence calculation methodology)_
_Depends on: Story 11-1 (done), Story 11-2 (review), Story 11-3 (done)_
_Completes: Epic 11 (Detection Transparency)_

## Dev Agent Record

### Context Reference

Created from:
- docs/prd.md - FR79, Multi-Signal Detection Architecture, Threat Model
- docs/architecture.md - Evidence Architecture, Security Architecture
- docs/epics.md - Epic 11 Detection Transparency definition
- docs/sprint-artifacts/stories/11-1-method-breakdown-component.md
- docs/sprint-artifacts/stories/11-2-cross-validation-status-display.md
- docs/sprint-artifacts/stories/11-3-platform-indicator-badge.md

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

### File List

**To Create:**
- `/Users/luca/dev/realitycam/apps/web/src/app/methodology/page.tsx` - Main page (Server Component)
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/index.ts` - Barrel exports
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/MethodologyLayout.tsx` - Layout wrapper ('use client')
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/ExpandableSection.tsx` - Reusable collapsible ('use client')
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/TableOfContents.tsx` - Desktop sidebar ('use client')
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/TrustModelSection.tsx` - Trust hierarchy
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/LidarSection.tsx` - LiDAR explanation
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/MoireSection.tsx` - Moire explanation
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/TextureSection.tsx` - Texture explanation
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/ArtifactsSection.tsx` - Artifact detection
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/CrossValidationSection.tsx` - Cross-validation
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/PlatformSection.tsx` - Platform & attestation
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/ConfidenceSection.tsx` - Confidence calculation
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/LimitationsSection.tsx` - Known limitations
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/FAQSection.tsx` - FAQ accordion ('use client')
- `/Users/luca/dev/realitycam/apps/web/src/components/Methodology/__tests__/*.test.tsx` - Unit tests
- `/Users/luca/dev/realitycam/apps/web/tests/e2e/methodology.spec.ts` - E2E tests

**To Modify:**
- `/Users/luca/dev/realitycam/apps/web/src/app/verify/[id]/page.tsx` - Add "How does this work?" link (AC #2)
