import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

/**
 * Vitest Configuration for RealityCam Mobile (Expo/React Native)
 *
 * Testing stack:
 * - Vitest for fast unit tests (TypeScript/React components)
 * - @testing-library/react-native for component tests
 * - Maestro for E2E on real devices (separate workflow)
 *
 * Note: Native modules (Swift) are tested via XCTest (see modules/device-attestation/ios/)
 */
export default defineConfig({
  plugins: [react()],

  test: {
    // Test environment
    environment: 'jsdom',

    // Setup files
    setupFiles: ['./vitest.setup.ts'],

    // Test patterns
    include: [
      '**/*.test.{ts,tsx}',
      '**/*.spec.{ts,tsx}',
    ],

    // Exclude patterns
    exclude: [
      '**/node_modules/**',
      '**/ios/**',
      '**/android/**',
      '**/.expo/**',
      '**/modules/**/*.swift', // Swift files tested via XCTest
    ],

    // Coverage configuration
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'html'],
      reportsDirectory: './coverage',
      include: [
        'components/**/*.{ts,tsx}',
        'hooks/**/*.{ts,tsx}',
        'store/**/*.{ts,tsx}',
        'services/**/*.{ts,tsx}',
      ],
      exclude: [
        '**/*.d.ts',
        '**/modules/**', // Native modules excluded
      ],
      thresholds: {
        global: {
          branches: 70,
          functions: 70,
          lines: 70,
          statements: 70,
        },
      },
    },

    // Timeouts
    testTimeout: 10000,
    hookTimeout: 10000,

    // Reporter
    reporters: ['default', 'junit'],
    outputFile: {
      junit: './test-results/junit.xml',
    },

    // Globals (describe, it, expect)
    globals: true,

    // Watch mode settings
    watch: false,

    // Pool settings for parallelism
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
      },
    },
  },

  resolve: {
    alias: {
      '@': path.resolve(__dirname, './'),
      '@/components': path.resolve(__dirname, './components'),
      '@/hooks': path.resolve(__dirname, './hooks'),
      '@/store': path.resolve(__dirname, './store'),
      '@/services': path.resolve(__dirname, './services'),
    },
  },
});
