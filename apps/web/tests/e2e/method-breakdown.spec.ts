import { test, expect } from '@playwright/test';

/**
 * E2E Tests for Method Breakdown Component (Story 11-1)
 *
 * Tests the detection method breakdown section on the verification page.
 * Uses demo routes which work without backend.
 */

test.describe('Method Breakdown Component', () => {
  test.describe('Demo Photo Route (/verify/demo)', () => {
    test('displays method breakdown section', async ({ page }) => {
      await page.goto('/verify/demo');

      // Wait for the method breakdown section to be visible
      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Verify section header shows "Detection Methods"
      await expect(section.getByText('Detection Methods')).toBeVisible();

      // Verify method count badge
      await expect(section.getByText('4 methods')).toBeVisible();
    });

    test('shows overall confidence summary', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Verify overall percentage is displayed
      await expect(section.getByText('95%')).toBeVisible();

      // Verify confidence badge
      await expect(section.getByTestId('confidence-badge')).toBeVisible();
      await expect(section.getByText('HIGH CONFIDENCE')).toBeVisible();

      // Verify primary signal status
      await expect(section.getByText('Primary:')).toBeVisible();
      await expect(section.getByText('PASS')).toBeVisible();

      // Verify supporting signals status
      await expect(section.getByText('Supporting:')).toBeVisible();
      await expect(section.getByText('AGREE')).toBeVisible();
    });

    test('renders all method score bars', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Verify LiDAR Depth method bar
      await expect(section.getByTestId('score-bar-lidar_depth')).toBeVisible();
      await expect(section.getByText('LiDAR Depth')).toBeVisible();

      // Verify Moire Detection method bar
      await expect(section.getByTestId('score-bar-moire')).toBeVisible();
      await expect(section.getByText('Moire Detection')).toBeVisible();

      // Verify Texture Analysis method bar
      await expect(section.getByTestId('score-bar-texture')).toBeVisible();
      await expect(section.getByText('Texture Analysis')).toBeVisible();

      // Verify Supporting Signals method bar
      await expect(section.getByTestId('score-bar-supporting')).toBeVisible();
      await expect(section.getByText('Supporting Signals')).toBeVisible();
    });

    test('shows tooltip on method click', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Click on LiDAR Depth method bar
      await section.getByTestId('score-bar-lidar_depth').click();

      // Verify tooltip appears
      const tooltip = section.getByTestId('tooltip-lidar_depth');
      await expect(tooltip).toBeVisible();

      // Verify tooltip contains expected information
      await expect(tooltip.getByText('LiDAR Depth')).toBeVisible();
      await expect(tooltip.getByText('Raw Score')).toBeVisible();
      await expect(tooltip.getByText('Weight')).toBeVisible();
      await expect(tooltip.getByText('Contribution')).toBeVisible();

      // Verify LiDAR-specific metrics are shown
      await expect(tooltip.getByText('LiDAR Metrics')).toBeVisible();
      await expect(tooltip.getByText('Depth Variance')).toBeVisible();
      await expect(tooltip.getByText('Depth Layers')).toBeVisible();
      await expect(tooltip.getByText('Edge Coherence')).toBeVisible();
    });

    test('closes tooltip on close button click', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Open tooltip
      await section.getByTestId('score-bar-lidar_depth').click();
      const tooltip = section.getByTestId('tooltip-lidar_depth');
      await expect(tooltip).toBeVisible();

      // Click close button
      await tooltip.getByLabel('Close tooltip').click();

      // Verify tooltip is hidden
      await expect(tooltip).not.toBeVisible();
    });

    test('collapses and expands section', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Section should be expanded by default
      const content = page.locator('#method-breakdown-content');
      await expect(content).toHaveClass(/max-h-\[1000px\]/);

      // Click header to collapse
      await section.getByRole('button', { name: /Detection Methods/i }).click();

      // Verify content is collapsed
      await expect(content).toHaveClass(/max-h-0/);

      // Click header to expand
      await section.getByRole('button', { name: /Detection Methods/i }).click();

      // Verify content is expanded
      await expect(content).toHaveClass(/max-h-\[1000px\]/);
    });

    test('shows "No patterns detected (good)" for moire method', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Moire with not_detected status should show positive message
      const moireBar = section.getByTestId('score-bar-moire');
      await expect(moireBar.getByText('No patterns detected (good)')).toBeVisible();
    });
  });

  test.describe('Demo Video Route (/verify/demo-video)', () => {
    test('displays method breakdown with unavailable method', async ({ page }) => {
      await page.goto('/verify/demo-video');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Verify artifacts method shows as unavailable
      const artifactsBar = section.getByTestId('score-bar-artifacts');
      await expect(artifactsBar).toBeVisible();
      await expect(artifactsBar.getByText('N/A')).toBeVisible();
      await expect(artifactsBar.getByText('Unavailable')).toBeVisible();
    });

    test('shows unavailable reason in tooltip', async ({ page }) => {
      await page.goto('/verify/demo-video');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Click on unavailable artifacts method
      await section.getByTestId('score-bar-artifacts').click();

      // Verify tooltip shows unavailable reason
      const tooltip = section.getByTestId('tooltip-artifacts');
      await expect(tooltip).toBeVisible();
      await expect(tooltip.getByText(/Model not loaded for video analysis/)).toBeVisible();
    });

    test('shows warning flags when present', async ({ page }) => {
      await page.goto('/verify/demo-video');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Verify flag badge is displayed
      await expect(section.getByText('artifacts_unavailable')).toBeVisible();
    });
  });

  test.describe('Responsive Layout', () => {
    test('shows single column on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 }); // iPhone SE
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Grid should have 1 column on mobile (grid-cols-1)
      const grid = section.locator('.grid');
      await expect(grid).toHaveClass(/grid-cols-1/);
    });

    test('shows two columns on tablet', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 }); // iPad
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      // Grid should have 2 columns on tablet (md:grid-cols-2)
      const grid = section.locator('.grid');
      await expect(grid).toHaveClass(/md:grid-cols-2/);
    });
  });

  test.describe('Accessibility', () => {
    test('section header has correct aria attributes', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      const headerButton = section.getByRole('button', { name: /Detection Methods/i });
      await expect(headerButton).toHaveAttribute('aria-expanded', 'true');
      await expect(headerButton).toHaveAttribute('aria-controls', 'method-breakdown-content');
    });

    test('progress bars have correct aria attributes', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      const lidarBar = section.getByTestId('score-bar-lidar_depth');
      const progressBar = lidarBar.getByRole('progressbar');
      await expect(progressBar).toHaveAttribute('aria-valuenow', '98');
      await expect(progressBar).toHaveAttribute('aria-valuemin', '0');
      await expect(progressBar).toHaveAttribute('aria-valuemax', '100');
    });

    test('method bars are keyboard accessible', async ({ page }) => {
      await page.goto('/verify/demo');

      const section = page.getByTestId('method-breakdown-section');
      await expect(section).toBeVisible({ timeout: 10000 });

      const lidarBar = section.getByTestId('score-bar-lidar_depth');

      // Focus the method bar
      await lidarBar.focus();

      // Press Enter to open tooltip
      await page.keyboard.press('Enter');

      // Verify tooltip is visible
      const tooltip = section.getByTestId('tooltip-lidar_depth');
      await expect(tooltip).toBeVisible();

      // Press Escape to close
      await page.keyboard.press('Escape');
      await expect(tooltip).not.toBeVisible();
    });
  });
});
