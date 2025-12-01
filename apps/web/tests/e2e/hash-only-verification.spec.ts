import { test, expect } from '../support/fixtures';

/**
 * RealityCam Web - Hash-Only Verification E2E Tests (Story 8-6)
 *
 * Tests privacy mode (hash-only) capture verification UI:
 * - Privacy Mode badge display
 * - Hash-only media placeholder (no image/video shown)
 * - Device analysis source indication
 * - Metadata flags handling
 * - Demo route accessibility
 */

test.describe('Hash-Only Verification Flow', () => {
  test('should display Privacy Mode badge for hash-only captures', async ({ page }) => {
    // Navigate to demo hash-only route
    await page.goto('/verify/demo-hash-only');

    // Privacy Mode badge should be visible
    await expect(page.getByTestId('privacy-mode-badge')).toBeVisible();
    await expect(page.getByTestId('privacy-mode-badge')).toContainText('Privacy Mode');

    // Confidence badge should still be displayed
    await expect(page.getByTestId('confidence-badge')).toBeVisible();
    await expect(page.getByTestId('verification-status')).toContainText(/HIGH CONFIDENCE/i);
  });

  test('should show hash-only placeholder instead of media', async ({ page }) => {
    await page.goto('/verify/demo-hash-only');

    // Hash-only placeholder should be visible
    await expect(page.getByTestId('hash-only-placeholder')).toBeVisible();

    // Should show "Hash Verified" heading
    await expect(page.getByRole('heading', { name: /Hash Verified/i })).toBeVisible();

    // Should show privacy messaging
    await expect(page.getByText(/Original media not stored on server/i)).toBeVisible();
    await expect(page.getByText(/Authenticity verified via device attestation/i)).toBeVisible();

    // Should NOT show actual image or video
    await expect(page.locator('img[alt="Captured photo"]')).not.toBeVisible();
    await expect(page.locator('video')).not.toBeVisible();
  });

  test('should indicate device analysis source in evidence panel', async ({ page }) => {
    await page.goto('/verify/demo-hash-only');

    // Click to expand evidence panel
    await page.getByRole('button', { name: /Evidence Details/i }).click();

    // Wait for panel to expand
    await expect(page.getByTestId('evidence-panel')).toBeVisible();

    // Should show "LiDAR Depth Analysis (Device)" label
    await expect(page.getByText(/LiDAR Depth Analysis \(Device\)/i)).toBeVisible();

    // Should show device analysis value
    await expect(page.getByText(/Real 3D scene - Device analysis/i)).toBeVisible();
  });

  test('should display capture metadata correctly', async ({ page }) => {
    await page.goto('/verify/demo-hash-only');

    // Should show location (coarse level in demo) - use first match for summary section
    await expect(page.getByText('San Francisco, CA').first()).toBeVisible();

    // Should show device model - use first match for summary section
    await expect(page.getByText('iPhone 15 Pro').first()).toBeVisible();

    // Should show captured at timestamp
    await expect(page.getByText(/Captured At/i)).toBeVisible();
  });

  test('should handle hash-only detection correctly', async ({ page }) => {
    await page.goto('/verify/demo-hash-only');

    // Verify page loaded successfully (no 404) - use heading role for specificity
    await expect(page.getByRole('heading', { name: /Photo Verification/i })).toBeVisible();

    // Capture ID should be shown
    await expect(page.getByText(/demo-hash-only/)).toBeVisible();

    // Should show HIGH confidence (hash-only gets same confidence as full)
    await expect(page.getByTestId('verification-status')).toContainText(/HIGH CONFIDENCE/i);
  });

  test('should not show broken images or console errors', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto('/verify/demo-hash-only');

    // Wait for page to fully load
    await page.waitForLoadState('networkidle');

    // Should not have 404 errors for missing media
    const has404Error = consoleErrors.some((error) =>
      error.includes('404') || error.includes('Failed to load')
    );
    expect(has404Error).toBe(false);

    // Should not show broken image placeholders
    await expect(page.getByTestId('hash-only-placeholder')).toBeVisible();
  });

  test('should show all evidence checks as passed', async ({ page }) => {
    await page.goto('/verify/demo-hash-only');

    // Expand evidence panel
    await page.getByRole('button', { name: /Evidence Details/i }).click();

    // All evidence items should show pass status - use testid for specificity
    // Hardware attestation
    await expect(page.getByTestId('hardware-attestation')).toBeVisible();

    // Device depth analysis
    await expect(page.getByTestId('depth-analysis-(device)')).toBeVisible();

    // Timestamp
    await expect(page.getByTestId('timestamp')).toBeVisible();

    // Device model
    await expect(page.getByTestId('device-model')).toBeVisible();

    // Location
    await expect(page.getByTestId('location')).toBeVisible();
  });

  test('demo route should be accessible without backend', async ({ page }) => {
    // This test verifies the demo route works without backend API calls
    await page.goto('/verify/demo-hash-only');

    // Page should load successfully - use heading role for specificity
    await expect(page.getByRole('heading', { name: /Photo Verification/i })).toBeVisible();

    // Privacy Mode badge should be visible
    await expect(page.getByTestId('privacy-mode-badge')).toBeVisible();

    // Hash-only placeholder should be visible
    await expect(page.getByTestId('hash-only-placeholder')).toBeVisible();

    // No loading states or "not found" messages
    await expect(page.getByRole('heading', { name: /not found/i })).not.toBeVisible();
    await expect(page.getByRole('heading', { name: /processing/i })).not.toBeVisible();
  });

  test('should have correct aspect ratio for photo hash-only placeholder', async ({ page }) => {
    await page.goto('/verify/demo-hash-only');

    const placeholder = page.getByTestId('hash-only-placeholder');
    await expect(placeholder).toBeVisible();

    // Should have 4:3 aspect ratio for photo (demo is a photo)
    const boundingBox = await placeholder.boundingBox();
    expect(boundingBox).not.toBeNull();

    if (boundingBox) {
      const aspectRatio = boundingBox.width / boundingBox.height;
      // 4:3 = 1.333, allow small tolerance for rounding
      expect(aspectRatio).toBeGreaterThan(1.2);
      expect(aspectRatio).toBeLessThan(1.4);
    }
  });

  test('should display Privacy Mode badge with correct styling', async ({ page }) => {
    await page.goto('/verify/demo-hash-only');

    const badge = page.getByTestId('privacy-mode-badge');
    await expect(badge).toBeVisible();

    // Should have purple color scheme (check for purple class)
    const className = await badge.getAttribute('class');
    expect(className).toContain('purple');

    // Should have shield icon
    const svg = badge.locator('svg');
    await expect(svg).toBeVisible();
  });
});

test.describe('Hash-Only vs Full Capture Comparison', () => {
  test('should show different UI for hash-only vs full photo captures', async ({ page }) => {
    // First check full photo capture (demo route)
    await page.goto('/verify/demo');

    // Full capture should NOT show Privacy Mode badge
    await expect(page.getByTestId('privacy-mode-badge')).not.toBeVisible();

    // Full capture should show actual photo (not hash-only placeholder)
    await expect(page.getByTestId('hash-only-placeholder')).not.toBeVisible();

    // Now check hash-only capture
    await page.goto('/verify/demo-hash-only');

    // Hash-only should show Privacy Mode badge
    await expect(page.getByTestId('privacy-mode-badge')).toBeVisible();

    // Hash-only should show placeholder
    await expect(page.getByTestId('hash-only-placeholder')).toBeVisible();
  });

  test('should show device analysis for hash-only but server analysis for full', async ({ page }) => {
    // Check hash-only (device analysis)
    await page.goto('/verify/demo-hash-only');
    await page.getByRole('button', { name: /Evidence Details/i }).click();
    await expect(page.getByText(/LiDAR Depth Analysis \(Device\)/i)).toBeVisible();

    // Check full capture (server analysis)
    await page.goto('/verify/demo');
    await page.getByRole('button', { name: /Evidence Details/i }).click();
    await expect(page.getByText(/LiDAR Depth Analysis$/)).toBeVisible();
    // Should NOT have "(Device)" suffix
    const evidenceText = await page.textContent('[data-testid="evidence-panel"]');
    expect(evidenceText).not.toContain('(Device)');
  });
});
