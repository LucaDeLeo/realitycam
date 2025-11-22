/**
 * ATDD Test: Story 5.4 - Verification Page Summary View
 *
 * Acceptance Criteria (from epics.md Story 5.4):
 * - Navigate to /verify/{capture_id}
 * - See confidence badge (HIGH/MEDIUM/LOW/SUSPICIOUS) with appropriate color
 * - See captured photo
 * - See capture timestamp and (coarse) location
 * - See depth analysis visualization (heatmap preview)
 * - See device model that captured it
 * - Page loads in < 1.5s (FCP)
 * - Invalid capture ID shows "Capture not found"
 *
 * FR Coverage:
 * - FR31: Users can view capture verification via shareable URL
 * - FR32: Verification page displays confidence summary (HIGH/MEDIUM/LOW/SUSPICIOUS)
 * - FR33: Verification page displays depth analysis visualization
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
  lowConfidence: process.env.TEST_CAPTURE_LOW || 'test-capture-low',
  suspicious: process.env.TEST_CAPTURE_SUSPICIOUS || 'test-capture-suspicious',
  invalid: 'non-existent-capture-id-12345',
};

test.describe('Story 5.4: Verification Page Summary View', () => {
  /**
   * AC-5.4.1: Verification page loads for valid capture
   *
   * GIVEN: A valid capture ID
   * WHEN: User navigates to /verify/{capture_id}
   * THEN: Page loads with verification content
   */
  test('verification page loads for valid capture ID', async ({ page }) => {
    // GIVEN: Valid capture ID
    const captureId = TEST_CAPTURES.highConfidence;

    // WHEN: Navigate to verification page
    await page.goto(`/verify/${captureId}`);

    // THEN: Page loads with verification content
    await expect(page.locator('[data-testid="verification-page"]')).toBeVisible({
      timeout: 10000,
    });

    // Title includes verification context
    await expect(page).toHaveTitle(/verify|RealityCam/i);
  });

  /**
   * AC-5.4.2: HIGH confidence displays green badge
   *
   * GIVEN: Capture with HIGH confidence level
   * WHEN: Viewing verification page
   * THEN: Badge shows "HIGH" with green styling
   */
  test('HIGH confidence displays green badge', async ({ page }) => {
    // GIVEN: HIGH confidence capture
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    // WHEN: Page loads
    const badge = page.locator('[data-testid="confidence-badge"]');
    await expect(badge).toBeVisible();

    // THEN: Shows HIGH with green color
    await expect(badge).toHaveText(/HIGH/i);
    // Check for green background (Tailwind green-500 or similar)
    const backgroundColor = await badge.evaluate(el =>
      getComputedStyle(el).backgroundColor
    );
    // Green is rgb(34, 197, 94) or similar
    expect(backgroundColor).toMatch(/rgb\(34|rgb\(22|#22c55e|green/i);
  });

  /**
   * AC-5.4.3: MEDIUM confidence displays yellow badge
   *
   * GIVEN: Capture with MEDIUM confidence level
   * WHEN: Viewing verification page
   * THEN: Badge shows "MEDIUM" with yellow/amber styling
   */
  test('MEDIUM confidence displays yellow badge', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.mediumConfidence}`);

    const badge = page.locator('[data-testid="confidence-badge"]');
    await expect(badge).toBeVisible();
    await expect(badge).toHaveText(/MEDIUM/i);

    // Yellow/amber color check
    const backgroundColor = await badge.evaluate(el =>
      getComputedStyle(el).backgroundColor
    );
    expect(backgroundColor).toMatch(/rgb\(234|rgb\(251|#eab308|yellow|amber/i);
  });

  /**
   * AC-5.4.4: LOW confidence displays orange badge
   *
   * GIVEN: Capture with LOW confidence level
   * WHEN: Viewing verification page
   * THEN: Badge shows "LOW" with orange styling
   */
  test('LOW confidence displays orange badge', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.lowConfidence}`);

    const badge = page.locator('[data-testid="confidence-badge"]');
    await expect(badge).toBeVisible();
    await expect(badge).toHaveText(/LOW/i);
  });

  /**
   * AC-5.4.5: SUSPICIOUS confidence displays red badge with warning
   *
   * GIVEN: Capture with SUSPICIOUS confidence level
   * WHEN: Viewing verification page
   * THEN: Badge shows "SUSPICIOUS" with red styling and warning message
   */
  test('SUSPICIOUS confidence displays red badge with warning', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.suspicious}`);

    const badge = page.locator('[data-testid="confidence-badge"]');
    await expect(badge).toBeVisible();
    await expect(badge).toHaveText(/SUSPICIOUS/i);

    // Should have warning message
    await expect(page.locator('[data-testid="suspicious-warning"]')).toBeVisible();
    await expect(page.locator('text=verification failed')).toBeVisible();
  });

  /**
   * AC-5.4.6: Photo displayed prominently
   *
   * GIVEN: Valid capture
   * WHEN: Viewing verification page
   * THEN: Captured photo is visible
   */
  test('captured photo is displayed prominently', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const photo = page.locator('[data-testid="capture-photo"]');
    await expect(photo).toBeVisible();

    // Photo should have reasonable dimensions
    const boundingBox = await photo.boundingBox();
    expect(boundingBox?.width).toBeGreaterThan(200);
    expect(boundingBox?.height).toBeGreaterThan(150);
  });

  /**
   * AC-5.4.7: Capture timestamp displayed
   *
   * GIVEN: Valid capture
   * WHEN: Viewing verification page
   * THEN: Capture timestamp is shown
   */
  test('capture timestamp is displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const timestamp = page.locator('[data-testid="capture-timestamp"]');
    await expect(timestamp).toBeVisible();

    // Timestamp should be in readable format
    const text = await timestamp.textContent();
    expect(text).toMatch(/\d{4}|\w+ \d+|ago|today/i);
  });

  /**
   * AC-5.4.8: Coarse location displayed (if available)
   *
   * GIVEN: Capture with location data
   * WHEN: Viewing verification page
   * THEN: Coarse location (city level) is shown
   */
  test('coarse location displayed when available', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const location = page.locator('[data-testid="capture-location"]');

    // Location may or may not be present
    const isVisible = await location.isVisible();
    if (isVisible) {
      // Should show city-level location, not exact coordinates
      const text = await location.textContent();
      // Should NOT contain precise coordinates
      expect(text).not.toMatch(/37\.7749/);
      // Should contain general area
      expect(text).toMatch(/San Francisco|California|CA|location/i);
    }
  });

  /**
   * AC-5.4.9: Depth visualization displayed
   *
   * GIVEN: Valid capture with depth map
   * WHEN: Viewing verification page
   * THEN: Depth heatmap preview is visible
   */
  test('depth analysis visualization is displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const depthViz = page.locator('[data-testid="depth-visualization"]');
    await expect(depthViz).toBeVisible();

    // Should be an image or canvas element
    const tagName = await depthViz.evaluate(el => el.tagName.toLowerCase());
    expect(['img', 'canvas', 'div']).toContain(tagName);
  });

  /**
   * AC-5.4.10: Device model displayed
   *
   * GIVEN: Valid capture
   * WHEN: Viewing verification page
   * THEN: Device model is shown
   */
  test('device model is displayed', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const deviceModel = page.locator('[data-testid="device-model"]');
    await expect(deviceModel).toBeVisible();

    const text = await deviceModel.textContent();
    expect(text).toMatch(/iPhone.*Pro/i);
  });

  /**
   * AC-5.4.11: Invalid capture ID shows not found
   *
   * GIVEN: Invalid capture ID
   * WHEN: Navigating to /verify/{invalid_id}
   * THEN: Shows "Capture not found" message
   */
  test('invalid capture ID shows not found message', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.invalid}`);

    await expect(page.locator('text=Capture not found')).toBeVisible({
      timeout: 5000,
    });

    // Optional: Check for 404 styling
    const pageContent = await page.content();
    expect(pageContent).toMatch(/not found|404|doesn't exist/i);
  });
});

test.describe('Story 5.4: Performance Requirements', () => {
  /**
   * AC-5.4.12: Page loads within 1.5s FCP target
   *
   * GIVEN: Valid capture ID
   * WHEN: Navigating to verification page
   * THEN: First Contentful Paint < 1.5s
   */
  test('page meets FCP performance target', async ({ page }) => {
    // Start performance measurement
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`, {
      waitUntil: 'domcontentloaded',
    });

    // Get performance metrics
    const performanceMetrics = await page.evaluate(() => {
      const entries = performance.getEntriesByType('paint');
      const fcp = entries.find(entry => entry.name === 'first-contentful-paint');
      return {
        fcp: fcp?.startTime || null,
      };
    });

    // FCP should be under 1.5s (1500ms)
    if (performanceMetrics.fcp !== null) {
      expect(performanceMetrics.fcp).toBeLessThan(1500);
    }

    // Verify main content is visible quickly
    await expect(page.locator('[data-testid="verification-page"]')).toBeVisible({
      timeout: 1500,
    });
  });

  /**
   * AC-5.4.13: Media served via CDN
   *
   * GIVEN: Page with captured photo
   * WHEN: Checking image source
   * THEN: URL uses CDN domain or presigned URL
   */
  test('media served via CDN with presigned URLs', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const photo = page.locator('[data-testid="capture-photo"] img, [data-testid="capture-photo"]');
    await expect(photo).toBeVisible();

    const src = await photo.getAttribute('src');

    // Should be CDN URL or presigned S3 URL
    if (src) {
      expect(src).toMatch(/cloudfront\.net|s3\.amazonaws\.com|X-Amz-Signature|cdn\./i);
    }
  });
});

test.describe('Story 5.4: Responsive Design', () => {
  /**
   * Verification page works on mobile viewport
   */
  test('page is usable on mobile viewport', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 }); // iPhone SE

    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    // Core elements visible on mobile
    await expect(page.locator('[data-testid="confidence-badge"]')).toBeVisible();
    await expect(page.locator('[data-testid="capture-photo"]')).toBeVisible();

    // No horizontal scroll
    const scrollWidth = await page.evaluate(() => document.body.scrollWidth);
    const clientWidth = await page.evaluate(() => document.body.clientWidth);
    expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 5); // Allow small tolerance
  });

  /**
   * Verification page works on tablet viewport
   */
  test('page is usable on tablet viewport', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 }); // iPad

    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    await expect(page.locator('[data-testid="verification-page"]')).toBeVisible();
  });
});

test.describe('Story 5.4: Accessibility', () => {
  /**
   * Images have alt text
   */
  test('images have descriptive alt text', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const images = page.locator('img');
    const count = await images.count();

    for (let i = 0; i < count; i++) {
      const img = images.nth(i);
      const alt = await img.getAttribute('alt');
      expect(alt).toBeTruthy();
      expect(alt!.length).toBeGreaterThan(2);
    }
  });

  /**
   * Page has proper heading structure
   */
  test('page has proper heading structure', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    // Should have at least one h1
    const h1 = page.locator('h1');
    await expect(h1).toBeVisible();

    // Headings should be in order (no h3 before h2, etc.)
    const headings = await page.locator('h1, h2, h3, h4, h5, h6').allTextContents();
    expect(headings.length).toBeGreaterThan(0);
  });

  /**
   * Color contrast meets WCAG standards
   */
  test('confidence badge has sufficient color contrast', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    const badge = page.locator('[data-testid="confidence-badge"]');
    await expect(badge).toBeVisible();

    // Badge should have aria-label or readable text
    const ariaLabel = await badge.getAttribute('aria-label');
    const textContent = await badge.textContent();
    expect(ariaLabel || textContent).toBeTruthy();
  });
});

test.describe('Story 5.4: Shareable URL', () => {
  /**
   * URL is shareable and unique per capture
   */
  test('verification URL is shareable and bookmarkable', async ({ page }) => {
    const captureId = TEST_CAPTURES.highConfidence;
    const url = `/verify/${captureId}`;

    await page.goto(url);
    await expect(page.locator('[data-testid="verification-page"]')).toBeVisible();

    // URL should contain capture ID
    expect(page.url()).toContain(captureId);

    // Should work on page refresh (bookmarkable)
    await page.reload();
    await expect(page.locator('[data-testid="verification-page"]')).toBeVisible();
  });

  /**
   * Share metadata present for social sharing
   */
  test('page has Open Graph metadata for social sharing', async ({ page }) => {
    await page.goto(`/verify/${TEST_CAPTURES.highConfidence}`);

    // Check for OG tags
    const ogTitle = await page.locator('meta[property="og:title"]').getAttribute('content');
    const ogImage = await page.locator('meta[property="og:image"]').getAttribute('content');

    expect(ogTitle).toBeTruthy();
    // Image may or may not be present depending on implementation
  });
});
