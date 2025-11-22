/**
 * Jest Setup for RealityCam Web
 *
 * Configures testing-library and global mocks
 */

import '@testing-library/jest-dom';

// Mock Next.js router
jest.mock('next/navigation', () => ({
  useRouter: () => ({
    push: jest.fn(),
    replace: jest.fn(),
    prefetch: jest.fn(),
    back: jest.fn(),
    forward: jest.fn(),
  }),
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
}));

// Mock environment variables for tests
process.env.NEXT_PUBLIC_API_URL = 'http://localhost:3001/api';
process.env.NEXT_PUBLIC_CDN_URL = 'http://localhost:4566'; // LocalStack S3

// Suppress console errors during tests (optional, remove for debugging)
const originalError = console.error;
beforeAll(() => {
  console.error = (...args) => {
    // Suppress known React testing-library warnings
    if (
      typeof args[0] === 'string' &&
      args[0].includes('Warning: ReactDOM.render is no longer supported')
    ) {
      return;
    }
    originalError.call(console, ...args);
  };
});

afterAll(() => {
  console.error = originalError;
});

// Reset all mocks between tests
afterEach(() => {
  jest.clearAllMocks();
});
