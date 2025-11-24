# RealityCam Web - Test Suite

End-to-end and integration tests for the RealityCam verification web application using [Playwright](https://playwright.dev/).

## Quick Start

```bash
# Install dependencies (from repo root)
pnpm install

# Install Playwright browsers
cd apps/web && npx playwright install

# Run tests
pnpm test

# Run tests with UI
pnpm test:ui
```

## Test Commands

| Command | Description |
|---------|-------------|
| `pnpm test` | Run all tests headless |
| `pnpm test:ui` | Open interactive UI mode |
| `pnpm test:headed` | Run tests in headed browser |
| `pnpm test:debug` | Debug mode with inspector |
| `pnpm test:ci` | CI mode with JUnit + HTML reports |
| `pnpm test:report` | View last HTML report |

## Test Structure

```
tests/
├── e2e/                          # E2E test files
│   └── example.spec.ts           # Sample tests (replace with real)
└── support/                      # Test infrastructure
    ├── fixtures/                 # Playwright fixtures
    │   ├── index.ts              # Merged fixtures (import from here)
    │   └── factories/            # Data factories
    │       └── evidence-factory.ts
    └── helpers/                  # Pure utility functions
        └── api-helper.ts
```

## Architecture

### Fixture Pattern

Tests use a composable fixture architecture (not inheritance). Import fixtures from `tests/support/fixtures`:

```typescript
import { test, expect } from '../support/fixtures';

test('verify evidence display', async ({ page, evidenceFactory, apiHelper }) => {
  // evidenceFactory - creates test data with auto-cleanup
  // apiHelper - HTTP utilities for API interaction
  const evidence = await evidenceFactory.createVerified();
  await page.goto(`/evidence/${evidence.id}`);
  await expect(page.getByTestId('verification-status')).toHaveText(/verified/i);
});
```

### Data Factories

Factories create test data via API with automatic cleanup:

```typescript
// Create with defaults
const evidence = await evidenceFactory.create();

// Override specific fields
const suspicious = await evidenceFactory.create({
  confidenceScore: 0.35,
  signatureValid: false,
});

// Convenience methods
const verified = await evidenceFactory.createVerified();
const pending = await evidenceFactory.createPending();
```

### Selectors

Always use `data-testid` attributes:

```typescript
// Good
await page.getByTestId('upload-button').click();

// Avoid
await page.click('.btn-primary');  // Brittle CSS
await page.click('text=Upload');   // Locale-dependent
```

## Configuration

### Environment Variables

Copy `.env.test.example` to `.env.test`:

```bash
TEST_ENV=local           # local | staging | production
BASE_URL=http://localhost:3000
API_URL=http://localhost:8080
```

### Timeouts

Standardized per TEA knowledge base:

| Type | Timeout | Config Key |
|------|---------|------------|
| Action | 15s | `actionTimeout` |
| Navigation | 30s | `navigationTimeout` |
| Assertion | 10s | `expect.timeout` |
| Test | 60s | `timeout` |

### Artifacts

Captured on failure only:

- **Screenshots**: `test-results/`
- **Videos**: `test-results/` (retained on failure)
- **Traces**: `test-results/` (on first retry)
- **HTML Report**: `playwright-report/`

## Running Against Environments

```bash
# Local (default)
pnpm test

# Staging
TEST_ENV=staging pnpm test

# Production (smoke tests)
TEST_ENV=production pnpm test --grep @smoke
```

## CI Integration

Tests run in CI with:

```bash
pnpm test:ci
```

Artifacts uploaded on failure:
- `test-results/junit.xml` - JUnit report
- `playwright-report/` - HTML report

### GitHub Actions Example

```yaml
- name: Install Playwright
  run: npx playwright install --with-deps

- name: Run E2E Tests
  run: pnpm test:ci
  env:
    TEST_ENV: staging

- name: Upload Results
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: playwright-report
    path: apps/web/playwright-report/
```

## Best Practices

1. **API setup, UI verify** - Create data via API (fast), assert via UI (user-centric)
2. **Network-first** - Intercept before navigate to avoid race conditions
3. **Auto-cleanup** - Factories handle cleanup; don't leave test data
4. **No hard waits** - Use `expect` assertions, not `waitForTimeout`
5. **Failure-only artifacts** - Saves storage, maintains debuggability

## Knowledge Base References

- [fixture-architecture.md](../../../.bmad/bmm/testarch/knowledge/fixture-architecture.md) - Composable fixtures
- [data-factories.md](../../../.bmad/bmm/testarch/knowledge/data-factories.md) - Factory patterns
- [playwright-config.md](../../../.bmad/bmm/testarch/knowledge/playwright-config.md) - Configuration
- [test-quality.md](../../../.bmad/bmm/testarch/knowledge/test-quality.md) - Test design principles

## Next Steps

1. **Replace sample tests** - Run `*test-design` workflow to generate real test scenarios
2. **Add test IDs** - Ensure components have `data-testid` attributes
3. **Backend test endpoints** - Implement `/api/test/*` routes for data factories
4. **CI pipeline** - Integrate with GitHub Actions

---

*Generated by TEA (Test Architect) - Framework Workflow v4.0*
