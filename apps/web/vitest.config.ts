/// <reference types="vitest" />
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [
    tsconfigPaths(),
    react(),
  ],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    include: [
      'src/**/*.test.{ts,tsx}',
      'src/**/__tests__/**/*.{ts,tsx}',
    ],
    exclude: [
      'node_modules',
      'tests/e2e/**',
      '.next/**',
    ],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: [
        'src/lib/**/*.ts',
        'src/components/**/*.tsx',
        'src/app/**/*.tsx',
      ],
      exclude: [
        '**/*.test.{ts,tsx}',
        '**/__tests__/**',
      ],
    },
    // Inline deps that need transformation
    server: {
      deps: {
        inline: [
          '@testing-library/react',
        ],
      },
    },
  },
});
