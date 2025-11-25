/**
 * Vitest Setup for Next.js 16
 *
 * Configures test environment with:
 * - jest-dom matchers for DOM assertions
 * - Next.js module mocks (Link, Image, navigation, router)
 * - React 19 compatibility
 */

import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';
import React from 'react';

// ============================================================================
// Next.js Module Mocks
// ============================================================================

/**
 * Mock next/link
 * Renders as a simple anchor tag for testing
 */
vi.mock('next/link', () => ({
  default: ({ children, href, ...props }: { children: React.ReactNode; href: string; [key: string]: unknown }) => {
    return React.createElement('a', { href, ...props }, children);
  },
}));

/**
 * Mock next/image
 * Renders as a simple img tag for testing
 */
vi.mock('next/image', () => ({
  default: ({ src, alt, ...props }: { src: string; alt: string; [key: string]: unknown }) => {
    return React.createElement('img', { src, alt, ...props });
  },
}));

/**
 * Mock next/navigation (App Router)
 * Provides mock implementations for navigation hooks
 */
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
    back: vi.fn(),
    forward: vi.fn(),
    refresh: vi.fn(),
  }),
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
  useParams: () => ({}),
  notFound: vi.fn(),
  redirect: vi.fn(),
}));

/**
 * Mock next/router (Pages Router - for backwards compatibility)
 */
vi.mock('next/router', () => ({
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
    back: vi.fn(),
    pathname: '/',
    query: {},
    asPath: '/',
    events: {
      on: vi.fn(),
      off: vi.fn(),
      emit: vi.fn(),
    },
  }),
}));

/**
 * Mock next/headers (App Router server utilities)
 */
vi.mock('next/headers', () => ({
  cookies: () => ({
    get: vi.fn(),
    set: vi.fn(),
    delete: vi.fn(),
    has: vi.fn(),
    getAll: vi.fn(() => []),
  }),
  headers: () => new Headers(),
}));

// ============================================================================
// Global Test Utilities
// ============================================================================

/**
 * Suppress React 19 act() warnings in tests
 * React 19 is stricter about act() usage
 */
(globalThis as unknown as Record<string, unknown>).IS_REACT_ACT_ENVIRONMENT = true;

/**
 * Mock window.matchMedia for responsive tests
 */
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

/**
 * Mock IntersectionObserver for lazy loading tests
 */
class MockIntersectionObserver {
  readonly root: Element | null = null;
  readonly rootMargin: string = '';
  readonly thresholds: ReadonlyArray<number> = [];

  constructor() {}
  disconnect() {}
  observe() {}
  unobserve() {}
  takeRecords(): IntersectionObserverEntry[] {
    return [];
  }
}

globalThis.IntersectionObserver = MockIntersectionObserver;

/**
 * Mock ResizeObserver for responsive component tests
 */
class MockResizeObserver {
  constructor() {}
  disconnect() {}
  observe() {}
  unobserve() {}
}

globalThis.ResizeObserver = MockResizeObserver;

// ============================================================================
// Console Noise Suppression (Optional)
// ============================================================================

/**
 * Suppress specific console warnings during tests
 * Uncomment if needed to reduce noise
 */
// const originalError = console.error;
// console.error = (...args) => {
//   if (
//     typeof args[0] === 'string' &&
//     args[0].includes('Warning: ReactDOM.render is no longer supported')
//   ) {
//     return;
//   }
//   originalError.call(console, ...args);
// };
