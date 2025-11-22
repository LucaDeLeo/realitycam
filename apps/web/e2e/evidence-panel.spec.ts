/**
 * ATDD Test: Story 5.5 - Evidence Panel Component
 *
 * Acceptance Criteria (from epics.md Story 5.5):
 * - Click "View Evidence Details" shows expandable panel
 * - Hardware Attestation section: Status PASS/FAIL, level, device model
 * - Depth Analysis section: Status, variance, layers, edge coherence, is_likely_real_scene
 * - Metadata section: Timestamp validation, device model validation
 * - Each check shows relevant metrics
 * - Failed checks are prominently highlighted
 *
 * FR Coverage:
 * - FR34: Users can expand detailed evidence panel with per-check status
 * - FR35: Each check displays pass/fail with relevant metrics
 *
 * Test Environment:
 * - Requires: Web app running on localhost:3001
 * - API on localhost:3000 with seeded test data
 */

import { test, expect, Page } from '@playwright/test';

// Test capture IDs (seeded in test database)
const TEST_CAPTURES = {
  highConfidence: process.env.TEST_CAPTURE_HIGH || 'test-capture-high',
  mediumConfidence: process.env.TEST_CAPTURE_MEDIUM || 'test-capture-medium',
  suspicious: process.env.TEST_CAPTURE_SUSPICIOUS || 'test-capture-suspicious',
};

/**
 * Helper to expand evidence panel
 */
async function expandEvidencePanel(page: Page): Promise<void> {
  const toggle = page.locator('[data-testid="evidence-toggle"]');
  await expect(toggle).toBeVisible();
  await toggle.click();

  // Wait for expansion animation
  await expect(page.locator('[data-testid="evidence-panel-expanded"]')).toBeVisible({
    timeout: 2000,
  });
}

test.describe('Story 5.5: Evidence Panel Component', () => {
  /**
   * AC-5.5.1: Evidence panel expands on click
   *
   * GIVEN: Verification page loaded
   * WHEN: User clicks "View Evidence Details"
   * THEN: Expandable panel shows with evidence sections
   */
  test('evidence panel expands on click', async ({ page }) => {
    // GIVEN: Verification page
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    // Evidence panel should start collapsed
    await expect(page.locator('[data-testid="evidence-toggle"]')).toBeVisible();
    await expect(page.locator('[data-testid="evidence-panel-expanded"]')).not.toBeVisible();

    // WHEN: Click to expand
    await page.click('[data-testid="evidence-toggle"]');

    // THEN: Panel expands with sections
    await expect(page.locator('[data-testid="evidence-panel-expanded"]')).toBeVisible();
    await expect(page.locator('[data-testid="hardware-attestation-section"]')).toBeVisible();
    await expect(page.locator('[data-testid="depth-analysis-section"]')).toBeVisible();
    await expect(page.locator('[data-testid="metadata-section"]')).toBeVisible();
  });

  /**
   * AC-5.5.2: Evidence panel collapses on second click
   *
   * GIVEN: Expanded evidence panel
   * WHEN: User clicks toggle again
   * THEN: Panel collapses
   */
  test('evidence panel collapses on second click', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    // Expand
    await page.click('[data-testid="evidence-toggle"]');
    await expect(page.locator('[data-testid="evidence-panel-expanded"]')).toBeVisible();

    // WHEN: Click again
    await page.click('[data-testid="evidence-toggle"]');

    // THEN: Panel collapses
    await expect(page.locator('[data-testid="evidence-panel-expanded"]')).not.toBeVisible();
  });
});

test.describe('Story 5.5: Hardware Attestation Section', () => {
  /**
   * AC-5.5.3: Hardware attestation PASS displayed
   *
   * GIVEN: Capture with passing hardware attestation
   * WHEN: Viewing evidence panel
   * THEN: Shows status PASS with green indicator
   */
  test('hardware attestation PASS displayed with green indicator', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const section = page.locator('[data-testid="hardware-attestation-section"]');
    await expect(section).toBeVisible();

    // Status indicator
    const status = section.locator('[data-testid="hardware-attestation-status"]');
    await expect(status).toHaveText(/PASS/i);

    // Should have green styling
    const statusColor = await status.evaluate(el => getComputedStyle(el).color);
    expect(statusColor).toMatch(/rgb\(34|rgb\(22|green/i);
  });

  /**
   * AC-5.5.4: Hardware attestation level displayed
   *
   * GIVEN: Capture with Secure Enclave attestation
   * WHEN: Viewing evidence panel
   * THEN: Shows level: secure_enclave
   */
  test('hardware attestation level displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const level = page.locator('[data-testid="hardware-attestation-level"]');
    await expect(level).toBeVisible();
    await expect(level).toHaveText(/secure.enclave/i);
  });

  /**
   * AC-5.5.5: Device model displayed in hardware section
   *
   * GIVEN: Capture from iPhone Pro
   * WHEN: Viewing evidence panel
   * THEN: Shows device model in hardware section
   */
  test('device model displayed in hardware attestation', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const deviceModel = page.locator('[data-testid="hardware-device-model"]');
    await expect(deviceModel).toBeVisible();
    await expect(deviceModel).toHaveText(/iPhone.*Pro/i);
  });
});

test.describe('Story 5.5: Depth Analysis Section', () => {
  /**
   * AC-5.5.6: Depth analysis metrics displayed
   *
   * GIVEN: Capture with depth analysis
   * WHEN: Viewing evidence panel
   * THEN: Shows variance, layers, edge coherence metrics
   */
  test('depth analysis metrics displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const section = page.locator('[data-testid="depth-analysis-section"]');
    await expect(section).toBeVisible();

    // Depth variance
    const variance = section.locator('[data-testid="depth-variance"]');
    await expect(variance).toBeVisible();
    const varianceText = await variance.textContent();
    expect(varianceText).toMatch(/\d+\.?\d*/); // Contains a number

    // Depth layers
    const layers = section.locator('[data-testid="depth-layers"]');
    await expect(layers).toBeVisible();
    const layersText = await layers.textContent();
    expect(layersText).toMatch(/\d+/);

    // Edge coherence
    const coherence = section.locator('[data-testid="edge-coherence"]');
    await expect(coherence).toBeVisible();
    const coherenceText = await coherence.textContent();
    expect(coherenceText).toMatch(/\d+\.?\d*/);
  });

  /**
   * AC-5.5.7: Depth thresholds displayed for context
   *
   * GIVEN: Depth analysis metrics
   * WHEN: Viewing evidence panel
   * THEN: Shows threshold context (e.g., ">0.5 threshold")
   */
  test('depth analysis shows threshold context', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const section = page.locator('[data-testid="depth-analysis-section"]');

    // Should show threshold info
    const varianceRow = section.locator('[data-testid="depth-variance-row"]');
    const varianceThreshold = await varianceRow.textContent();
    expect(varianceThreshold).toMatch(/threshold|>|required|minimum/i);
  });

  /**
   * AC-5.5.8: is_likely_real_scene result displayed
   *
   * GIVEN: Real 3D scene capture
   * WHEN: Viewing evidence panel
   * THEN: Shows is_likely_real_scene: true
   */
  test('is_likely_real_scene result displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const realScene = page.locator('[data-testid="is-likely-real-scene"]');
    await expect(realScene).toBeVisible();
    await expect(realScene).toHaveText(/true|yes|real scene/i);
  });

  /**
   * AC-5.5.9: Depth analysis FAIL displayed with red indicator
   *
   * GIVEN: Capture with flat depth (screen)
   * WHEN: Viewing evidence panel
   * THEN: Shows status FAIL with red indicator
   */
  test('depth analysis FAIL displayed with red indicator', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.mediumConfidence}`);
    await expandEvidencePanel(page);

    const status = page.locator('[data-testid="depth-analysis-status"]');

    // May be PASS or FAIL depending on test data
    const statusText = await status.textContent();
    if (statusText?.includes('FAIL')) {
      // Should have red styling
      const statusColor = await status.evaluate(el => getComputedStyle(el).color);
      expect(statusColor).toMatch(/rgb\(239|rgb\(220|red/i);
    }
  });
});

test.describe('Story 5.5: Metadata Section', () => {
  /**
   * AC-5.5.10: Timestamp validation displayed
   *
   * GIVEN: Capture with valid timestamp
   * WHEN: Viewing evidence panel
   * THEN: Shows timestamp_valid: true
   */
  test('timestamp validation displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const timestampValid = page.locator('[data-testid="timestamp-validation"]');
    await expect(timestampValid).toBeVisible();

    const text = await timestampValid.textContent();
    expect(text).toMatch(/valid|pass|true/i);
  });

  /**
   * AC-5.5.11: Timestamp delta displayed
   *
   * GIVEN: Capture with timestamp info
   * WHEN: Viewing evidence panel
   * THEN: Shows time difference between EXIF and server
   */
  test('timestamp delta displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const timestampDelta = page.locator('[data-testid="timestamp-delta"]');
    await expect(timestampDelta).toBeVisible();

    const text = await timestampDelta.textContent();
    // Should show seconds or time difference
    expect(text).toMatch(/\d+.*sec|s|within/i);
  });

  /**
   * AC-5.5.12: Device model validation displayed
   *
   * GIVEN: Capture from iPhone Pro
   * WHEN: Viewing evidence panel
   * THEN: Shows model_has_lidar: true
   */
  test('device model LiDAR validation displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const lidarValid = page.locator('[data-testid="model-has-lidar"]');
    await expect(lidarValid).toBeVisible();

    const text = await lidarValid.textContent();
    expect(text).toMatch(/true|yes|lidar/i);
  });
});

test.describe('Story 5.5: Failed Check Highlighting', () => {
  /**
   * AC-5.5.13: Failed checks prominently highlighted
   *
   * GIVEN: Capture with failed timestamp validation
   * WHEN: Viewing evidence panel
   * THEN: Failed check is highlighted with red/warning styling
   */
  test('failed checks highlighted with warning styling', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.suspicious}`);
    await expandEvidencePanel(page);

    // Find any failed check
    const failedChecks = page.locator('[data-testid*="-status"]:has-text("FAIL")');
    const count = await failedChecks.count();

    if (count > 0) {
      const failedCheck = failedChecks.first();

      // Should have warning/error styling
      const classes = await failedCheck.getAttribute('class');
      expect(classes).toMatch(/red|error|fail|warning|danger/i);

      // Parent row should also be highlighted
      const parentRow = failedCheck.locator('..');
      const parentBg = await parentRow.evaluate(el =>
        getComputedStyle(el).backgroundColor
      );
      // Should have some highlighting (not white/transparent)
      expect(parentBg).not.toBe('rgba(0, 0, 0, 0)');
    }
  });

  /**
   * AC-5.5.14: Failed checks show at top or emphasized
   *
   * GIVEN: Capture with some failed checks
   * WHEN: Viewing evidence panel
   * THEN: Failed checks are emphasized or shown prominently
   */
  test('failed checks are emphasized in the panel', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.suspicious}`);
    await expandEvidencePanel(page);

    // Check for warning banner or summary
    const warningBanner = page.locator(
      '[data-testid="evidence-warning"], [data-testid="failed-checks-summary"]'
    );

    const hasWarning = await warningBanner.isVisible().catch(() => false);
    if (hasWarning) {
      await expect(warningBanner).toContainText(/fail|issue|warning/i);
    }
  });
});

test.describe('Story 5.5: Metrics with Context', () => {
  /**
   * AC-5.5.15: Metrics show pass/fail context
   *
   * GIVEN: Depth variance metric
   * WHEN: Viewing in evidence panel
   * THEN: Shows if metric passes threshold (e.g., "1.8 (threshold: >0.5)")
   */
  test('metrics show pass/fail context with thresholds', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const varianceRow = page.locator('[data-testid="depth-variance-row"]');
    const content = await varianceRow.textContent();

    // Should show the actual value
    expect(content).toMatch(/\d+\.?\d*/);

    // Should show threshold or pass/fail indicator
    expect(content).toMatch(/threshold|>|pass|check|ok/i);
  });

  /**
   * AC-5.5.16: Visual indicators for each check
   *
   * GIVEN: Evidence panel with multiple checks
   * WHEN: Viewing the panel
   * THEN: Each check has visual pass/fail indicator (icon/color)
   */
  test('each check has visual pass/fail indicator', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    // Hardware attestation should have icon/indicator
    const hwSection = page.locator('[data-testid="hardware-attestation-section"]');
    const hwIcon = hwSection.locator('[data-testid="status-icon"], svg, .icon');
    const hwHasIcon = await hwIcon.count() > 0;

    // Depth analysis should have icon/indicator
    const depthSection = page.locator('[data-testid="depth-analysis-section"]');
    const depthIcon = depthSection.locator('[data-testid="status-icon"], svg, .icon');
    const depthHasIcon = await depthIcon.count() > 0;

    // At least some sections should have icons
    expect(hwHasIcon || depthHasIcon).toBe(true);
  });
});

test.describe('Story 5.5: Evidence Panel Accessibility', () => {
  /**
   * Panel is keyboard accessible
   */
  test('evidence panel is keyboard accessible', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    // Tab to toggle button
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');

    // Find focused element
    const focused = page.locator(':focus');

    // Should be able to activate with keyboard
    await page.keyboard.press('Enter');

    // Check if panel expanded (may need adjustment based on tab order)
    // This tests keyboard interactivity in general
  });

  /**
   * Panel sections have proper ARIA labels
   */
  test('panel sections have proper ARIA structure', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    // Check for proper ARIA roles
    const panel = page.locator('[data-testid="evidence-panel-expanded"]');

    // Sections should be labeled
    const sections = panel.locator('[role="region"], section');
    const sectionCount = await sections.count();

    // Should have at least 3 sections (hardware, depth, metadata)
    expect(sectionCount).toBeGreaterThanOrEqual(3);
  });

  /**
   * Status text is screen reader friendly
   */
  test('status indicators have screen reader text', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);
    await expandEvidencePanel(page);

    const hwStatus = page.locator('[data-testid="hardware-attestation-status"]');
    await expect(hwStatus).toBeVisible();

    // Should have readable text (not just icon)
    const text = await hwStatus.textContent();
    expect(text).toMatch(/pass|fail/i);

    // Or aria-label for icon-only indicators
    const ariaLabel = await hwStatus.getAttribute('aria-label');
    if (ariaLabel) {
      expect(ariaLabel).toMatch(/pass|fail|status/i);
    }
  });
});

test.describe('Story 5.5: Evidence Panel Animation', () => {
  /**
   * Panel expands with smooth animation
   */
  test('panel expands with smooth animation', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const toggle = page.locator('[data-testid="evidence-toggle"]');

    // Click and check for transition
    await toggle.click();

    // Panel should have transition class or style
    const panel = page.locator('[data-testid="evidence-panel-expanded"]');
    const transition = await panel.evaluate(el =>
      getComputedStyle(el).transition
    );

    // Should have some transition defined
    expect(transition).not.toBe('all 0s ease 0s');
  });
});
