/**
 * RealityCam Mobile - Jest Configuration
 *
 * Minimal config for RN 0.81 + Expo SDK 54 + pnpm compatibility.
 * Avoids jest-expo preset issues with ESM in react-native/jest/setup.js.
 *
 * @see https://docs.expo.dev/develop/unit-testing/
 */

/** @type {import('jest').Config} */
module.exports = {
  // Use ts-jest for TypeScript transformation
  transform: {
    '^.+\\.(js|jsx|ts|tsx)$': 'babel-jest',
  },

  // Test file patterns - include both tests/ and __tests__/ directories
  testMatch: [
    '<rootDir>/tests/**/*.test.{ts,tsx}',
    '<rootDir>/tests/**/*.spec.{ts,tsx}',
    '<rootDir>/__tests__/**/*.test.{ts,tsx}',
    '<rootDir>/__tests__/**/*.spec.{ts,tsx}',
  ],

  // Setup files
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],

  // Module resolution
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',
  },

  // Transform ESM packages
  transformIgnorePatterns: [
    'node_modules/(?!(' +
      'react-native|' +
      '@react-native|' +
      '@react-native-community|' +
      'expo|' +
      '@expo|' +
      'expo-.*|' +
      '@expo/.*|' +
      'react-native-.*|' +
      'zustand|' +
      '@testing-library' +
      ')/)',
  ],

  // Ignore paths
  modulePathIgnorePatterns: ['<rootDir>/ios/', '<rootDir>/android/'],

  // Coverage
  collectCoverageFrom: [
    'hooks/**/*.{ts,tsx}',
    'services/**/*.{ts,tsx}',
    'store/**/*.{ts,tsx}',
    'components/**/*.{ts,tsx}',
    '!**/*.d.ts',
  ],

  // Test environment - use node for non-component tests
  testEnvironment: 'node',

  // Timeouts
  testTimeout: 10000,

  // Clean state - only clear call history, not mock implementations
  clearMocks: true,
  resetMocks: false,

  verbose: true,
};
