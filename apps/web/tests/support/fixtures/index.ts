/* eslint-disable react-hooks/rules-of-hooks */
// Note: This file uses Playwright's `use` fixture function, not React hooks.
// The eslint-disable is needed because the linter incorrectly flags `use` as a React hook.

import { test as base, mergeTests } from '@playwright/test';
import { EvidenceFactory } from './factories/evidence-factory';

/**
 * RealityCam Test Fixtures
 *
 * Composable fixture architecture using mergeTests pattern.
 * Each fixture provides one isolated concern with auto-cleanup.
 *
 * @see fixture-architecture.md knowledge base
 */

// Type definitions for custom fixtures
type TestFixtures = {
  evidenceFactory: EvidenceFactory;
  apiHelper: {
    get: (endpoint: string) => Promise<unknown>;
    post: (endpoint: string, data: unknown) => Promise<unknown>;
    delete: (endpoint: string) => Promise<void>;
  };
};

// Evidence factory fixture
const evidenceFixture = base.extend<Pick<TestFixtures, 'evidenceFactory'>>({
  evidenceFactory: async ({ request }, use) => {
    const factory = new EvidenceFactory(request);
    await use(factory);
    // Auto-cleanup created resources
    await factory.cleanup();
  },
});

// API helper fixture
const apiHelperFixture = base.extend<Pick<TestFixtures, 'apiHelper'>>({
  apiHelper: async ({ request }, use) => {
    const baseURL = process.env.API_URL || 'http://localhost:8080';

    const apiHelper = {
      get: async (endpoint: string) => {
        const response = await request.get(`${baseURL}${endpoint}`);
        if (!response.ok()) {
          throw new Error(`GET ${endpoint} failed: ${response.status()}`);
        }
        return response.json();
      },

      post: async (endpoint: string, data: unknown) => {
        const response = await request.post(`${baseURL}${endpoint}`, {
          data,
          headers: { 'Content-Type': 'application/json' },
        });
        if (!response.ok()) {
          throw new Error(`POST ${endpoint} failed: ${response.status()}`);
        }
        return response.json();
      },

      delete: async (endpoint: string) => {
        const response = await request.delete(`${baseURL}${endpoint}`);
        if (!response.ok()) {
          throw new Error(`DELETE ${endpoint} failed: ${response.status()}`);
        }
      },
    };

    await use(apiHelper);
  },
});

// Merge all fixtures using composition (not inheritance)
export const test = mergeTests(base, evidenceFixture, apiHelperFixture);

// Re-export expect for convenience
export { expect } from '@playwright/test';
