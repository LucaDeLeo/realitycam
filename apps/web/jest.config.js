/**
 * Jest Configuration for RealityCam Web (Next.js 16)
 *
 * Testing stack:
 * - Jest + @testing-library/react for component tests
 * - Playwright for E2E tests (separate config)
 */

const nextJest = require('next/jest');

const createJestConfig = nextJest({
  // Provide the path to your Next.js app to load next.config.js and .env files
  dir: './',
});

/** @type {import('jest').Config} */
const customJestConfig = {
  // Test environment
  testEnvironment: 'jsdom',

  // Setup files
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],

  // Module path aliases (match tsconfig paths)
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^@/components/(.*)$': '<rootDir>/components/$1',
    '^@/lib/(.*)$': '<rootDir>/lib/$1',
  },

  // Test patterns
  testMatch: [
    '<rootDir>/**/*.test.{ts,tsx}',
    '<rootDir>/**/*.spec.{ts,tsx}',
  ],

  // Coverage configuration
  collectCoverageFrom: [
    'components/**/*.{ts,tsx}',
    'lib/**/*.{ts,tsx}',
    'app/**/*.{ts,tsx}',
    '!**/*.d.ts',
    '!**/node_modules/**',
    '!**/.next/**',
  ],
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 70,
      lines: 70,
      statements: 70,
    },
  },
  coverageReporters: ['text', 'lcov', 'html'],
  coverageDirectory: '<rootDir>/coverage',

  // Timeouts
  testTimeout: 10000,

  // Transform configuration
  transform: {
    '^.+\\.(ts|tsx)$': ['@swc/jest'],
  },

  // Ignore patterns
  testPathIgnorePatterns: [
    '<rootDir>/node_modules/',
    '<rootDir>/.next/',
    '<rootDir>/e2e/', // Playwright tests
  ],

  // Module file extensions
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json'],

  // Reporter configuration
  reporters: [
    'default',
    ['jest-junit', {
      outputDirectory: '<rootDir>/test-results',
      outputName: 'junit.xml',
    }],
  ],

  // Clear mocks between tests
  clearMocks: true,

  // Verbose output in CI
  verbose: process.env.CI === 'true',
};

module.exports = createJestConfig(customJestConfig);
