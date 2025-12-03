import { defineConfig, devices } from '@playwright/test';
import path from 'path';

/**
 * RealityCam Web - Playwright Configuration
 *
 * Timeouts: action 15s, navigation 30s, expect 10s, test 60s
 * Artifacts: failure-only capture (screenshots, video, trace)
 * Reporters: HTML + JUnit XML for CI integration
 *
 * @see https://playwright.dev/docs/test-configuration
 */

// Environment configuration map
const envConfigMap = {
  local: {
    baseURL: 'http://localhost:3000',
    apiURL: 'http://localhost:8080',
  },
  staging: {
    baseURL: process.env.STAGING_URL || 'https://staging.realitycam.app',
    apiURL: process.env.STAGING_API_URL || 'https://api.staging.realitycam.app',
  },
  production: {
    baseURL: process.env.PROD_URL || 'https://realitycam.app',
    apiURL: process.env.PROD_API_URL || 'https://api.realitycam.app',
  },
} as const;

const environment = (process.env.TEST_ENV || 'local') as keyof typeof envConfigMap;

// Fail fast if environment not supported
if (!Object.keys(envConfigMap).includes(environment)) {
  console.error(`No configuration found for environment: ${environment}`);
  console.error(`Available environments: ${Object.keys(envConfigMap).join(', ')}`);
  process.exit(1);
}

const envConfig = envConfigMap[environment];

export default defineConfig({
  testDir: path.resolve(__dirname, './tests/e2e'),
  outputDir: path.resolve(__dirname, './test-results'),

  // Parallel execution
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,

  // Timeouts (standardized per knowledge base)
  timeout: 60 * 1000, // Test timeout: 60s
  expect: {
    timeout: 10 * 1000, // Assertion timeout: 10s
  },

  use: {
    baseURL: envConfig.baseURL,
    actionTimeout: 15 * 1000, // Action timeout: 15s
    navigationTimeout: 30 * 1000, // Navigation timeout: 30s

    // Failure-only artifact capture (saves storage)
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',

    // Extra HTTP headers for API URL
    extraHTTPHeaders: {
      'X-Test-Environment': environment,
    },
  },

  // Reporters: HTML for visual debugging, JUnit for CI
  reporter: [
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
    ['list'],
  ],

  // Browser projects
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
    // Mobile viewport for responsive testing
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 5'] },
    },
  ],

  // Web server configuration for local development
  // Disabled by default - start dev server manually before running tests:
  //   bun dev (in another terminal)
  //   bun test
  // Enable webServer when ready for CI integration
  webServer: undefined,
  // webServer: environment === 'local' ? {
  //   command: 'bun dev',
  //   url: 'http://localhost:3000',
  //   reuseExistingServer: !process.env.CI,
  //   timeout: 120 * 1000,
  // } : undefined,
});

// Export environment config for use in tests
export { envConfig, environment };
