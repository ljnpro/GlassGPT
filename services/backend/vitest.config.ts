import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    exclude: ['dist/**', 'node_modules/**'],
    coverage: {
      provider: 'v8',
      reporter: ['text-summary', 'json-summary'],
      reportsDirectory: '../../.local/build/ci/backend-coverage',
      thresholds: {
        branches: 64,
        functions: 87,
        lines: 79,
        statements: 79,
      },
    },
  },
});
