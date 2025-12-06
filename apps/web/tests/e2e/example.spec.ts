import { test, expect } from '../support/fixtures';

/**
 * RealityCam Web - Example E2E Tests
 *
 * Demonstrates patterns for verification UI testing.
 * Replace these with real tests after running *test-design workflow.
 */

// Skip tests that require backend test endpoints when running against production
// Production doesn't have ENABLE_TEST_ENDPOINTS=true for security
const isProduction = process.env.TEST_ENV === 'production';

test.describe('Verification Flow', () => {
  test('should display homepage with verification option', async ({ page }) => {
    // Navigate to homepage
    await page.goto('/');

    // Verify key elements are visible
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    // Look for the "View Demo Verification" link
    await expect(page.getByText('View Demo Verification')).toBeVisible();
  });

  test('should navigate to verification page', async ({ page }) => {
    await page.goto('/');

    // Click the demo verification link
    await page.getByText('View Demo Verification').click();

    // Should be on verify page
    await expect(page).toHaveURL(/.*verify/);
  });

  test('should show file upload component on homepage', async ({ page }) => {
    await page.goto('/');

    // File upload should be visible on homepage
    await expect(page.getByTestId('file-upload')).toBeVisible();
  });

  test.describe('Evidence Display', () => {
    // These tests require backend test endpoints (not available in production)
    test.skip(() => isProduction, 'Requires test endpoints - skipped in production');

    test('should display evidence panel after verification', async ({ page, evidenceFactory }) => {
      // Create test evidence via API
      const evidence = await evidenceFactory.createVerified();

      // Navigate to verify page
      await page.goto(`/verify/${evidence.id}`);

      // Verify evidence panel displays correctly
      await expect(page.getByTestId('evidence-panel')).toBeVisible();
      await expect(page.getByTestId('confidence-score')).toBeVisible();
      // ConfidenceBadge shows labels like "HIGH CONFIDENCE" for high confidence scores
      await expect(page.getByTestId('verification-status')).toHaveText(/HIGH CONFIDENCE|MEDIUM CONFIDENCE/i);
    });

    test('should show warning for suspicious photos', async ({ page, evidenceFactory }) => {
      // Create suspicious evidence (confidence 0.35 maps to "low" level)
      const evidence = await evidenceFactory.createSuspicious();

      await page.goto(`/verify/${evidence.id}`);

      // Should show low confidence or suspicious indicator
      // Note: Confidence 0.35 maps to "low" level, not "suspicious" (which requires < 0.3)
      await expect(page.getByTestId('verification-status')).toHaveText(/LOW CONFIDENCE|SUSPICIOUS/i);
    });

    test('should show processing state for pending evidence', async ({ page, evidenceFactory }) => {
      // Create pending evidence
      const evidence = await evidenceFactory.createPending();

      await page.goto(`/verify/${evidence.id}`);

      // Should show processing indicator
      await expect(page.getByTestId('processing-indicator')).toBeVisible();
    });
  });

  test.describe('Hardware Attestation Display', () => {
    test.skip(() => isProduction, 'Requires test endpoints - skipped in production');

    test('should display hardware attestation information', async ({ page, evidenceFactory }) => {
      const evidence = await evidenceFactory.createVerified();

      await page.goto(`/verify/${evidence.id}`);

      // Hardware attestation row should be visible in evidence panel
      await expect(page.getByTestId('hardware-attestation')).toBeVisible();
    });
  });

  test.describe('Depth Analysis Display', () => {
    test.skip(() => isProduction, 'Requires test endpoints - skipped in production');

    test('should display depth analysis for LiDAR photos', async ({ page, evidenceFactory }) => {
      const evidence = await evidenceFactory.create({
        hasDepth: true,
        depthLayers: 5,
      });

      await page.goto(`/verify/${evidence.id}`);

      // Depth analysis row should be visible in evidence panel
      await expect(page.getByTestId('depth-analysis')).toBeVisible();
    });

    test('should show unavailable status for photos without LiDAR', async ({ page, evidenceFactory }) => {
      const evidence = await evidenceFactory.create({
        hasDepth: false,
        depthLayers: 0,
      });

      await page.goto(`/verify/${evidence.id}`);

      // Depth analysis row should show unavailable status
      await expect(page.getByTestId('depth-analysis')).toBeVisible();
      await expect(page.getByText(/unavailable/i)).toBeVisible();
    });
  });
});

test.describe('API Health', () => {
  // Uses apiHelper which requires correct API_URL env var
  test.skip(() => isProduction, 'Requires test endpoints - skipped in production');

  test('should verify backend is reachable', async ({ apiHelper }) => {
    const health = (await apiHelper.get('/health')) as { status: string };
    expect(health.status).toBe('ok');
  });
});
