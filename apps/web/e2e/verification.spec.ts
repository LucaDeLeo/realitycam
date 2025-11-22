import { test, expect } from '@playwright/test';

/**
 * E2E Tests for RealityCam Verification Page
 *
 * Tests the public verification interface that displays
 * capture evidence and confidence levels.
 */

test.describe('Verification Page', () => {
  test('should load homepage', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/RealityCam/i);
  });

  test('should display verification for valid capture ID', async ({ page }) => {
    // TODO: Replace with actual capture ID from test data
    const captureId = 'test-capture-id';

    await page.goto(`/verify/${captureId}`);

    // Wait for content to load
    await page.waitForSelector('[data-testid="verification-page"]', {
      state: 'visible',
      timeout: 10000,
    });

    // Should display confidence level
    await expect(page.locator('[data-testid="confidence-badge"]')).toBeVisible();

    // Should display evidence panel
    await expect(page.locator('[data-testid="evidence-panel"]')).toBeVisible();
  });

  test('should show 404 for invalid capture ID', async ({ page }) => {
    await page.goto('/verify/invalid-id-that-does-not-exist');

    // Should show not found message
    await expect(page.locator('text=Capture not found')).toBeVisible();
  });

  test('should expand evidence details on click', async ({ page }) => {
    const captureId = 'test-capture-id';
    await page.goto(`/verify/${captureId}`);

    // Click to expand evidence details
    await page.click('[data-testid="evidence-toggle"]');

    // Should show detailed checks
    await expect(page.locator('[data-testid="hardware-attestation-detail"]')).toBeVisible();
    await expect(page.locator('[data-testid="depth-analysis-detail"]')).toBeVisible();
  });

  test('should display depth visualization', async ({ page }) => {
    const captureId = 'test-capture-id';
    await page.goto(`/verify/${captureId}`);

    // Should show depth heatmap
    await expect(page.locator('[data-testid="depth-visualization"]')).toBeVisible();
  });
});

test.describe('File Upload Verification', () => {
  test('should allow file upload for hash verification', async ({ page }) => {
    await page.goto('/');

    // Find upload dropzone
    const dropzone = page.locator('[data-testid="file-dropzone"]');
    await expect(dropzone).toBeVisible();

    // Upload a test file
    const testFile = Buffer.from('test-file-content');
    await dropzone.setInputFiles({
      name: 'test-photo.jpg',
      mimeType: 'image/jpeg',
      buffer: testFile,
    });

    // Should show processing state
    await expect(page.locator('[data-testid="upload-processing"]')).toBeVisible();
  });

  test('should show no match message for unknown file', async ({ page }) => {
    await page.goto('/');

    const dropzone = page.locator('[data-testid="file-dropzone"]');
    const randomContent = Buffer.from(Date.now().toString());

    await dropzone.setInputFiles({
      name: 'random-file.jpg',
      mimeType: 'image/jpeg',
      buffer: randomContent,
    });

    // Wait for result
    await page.waitForSelector('[data-testid="no-match-result"]', {
      state: 'visible',
      timeout: 10000,
    });

    await expect(page.locator('text=No provenance record found')).toBeVisible();
  });
});

test.describe('Confidence Level Display', () => {
  test.describe('HIGH confidence', () => {
    test('should display green HIGH badge', async ({ page }) => {
      // TODO: Use test data factory to create HIGH confidence capture
      await page.goto('/verify/high-confidence-capture-id');

      const badge = page.locator('[data-testid="confidence-badge"]');
      await expect(badge).toHaveText(/HIGH/i);
      await expect(badge).toHaveCSS('background-color', /green|rgb\(34, 197, 94\)/i);
    });
  });

  test.describe('MEDIUM confidence', () => {
    test('should display yellow MEDIUM badge', async ({ page }) => {
      await page.goto('/verify/medium-confidence-capture-id');

      const badge = page.locator('[data-testid="confidence-badge"]');
      await expect(badge).toHaveText(/MEDIUM/i);
    });
  });

  test.describe('SUSPICIOUS confidence', () => {
    test('should display red SUSPICIOUS badge with warning', async ({ page }) => {
      await page.goto('/verify/suspicious-capture-id');

      const badge = page.locator('[data-testid="confidence-badge"]');
      await expect(badge).toHaveText(/SUSPICIOUS/i);

      // Should show warning message
      await expect(page.locator('[data-testid="suspicious-warning"]')).toBeVisible();
    });
  });
});

test.describe('Accessibility', () => {
  test('should have no accessibility violations on verification page', async ({ page }) => {
    await page.goto('/verify/test-capture-id');

    // Basic accessibility check - ensure main landmarks exist
    await expect(page.locator('main')).toBeVisible();

    // Check that images have alt text
    const images = page.locator('img');
    const count = await images.count();
    for (let i = 0; i < count; i++) {
      const img = images.nth(i);
      const alt = await img.getAttribute('alt');
      expect(alt).toBeTruthy();
    }
  });

  test('should be keyboard navigable', async ({ page }) => {
    await page.goto('/verify/test-capture-id');

    // Tab through interactive elements
    await page.keyboard.press('Tab');
    const focusedElement = page.locator(':focus');
    await expect(focusedElement).toBeVisible();
  });
});
