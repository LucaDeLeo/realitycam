# RealityCam Mobile - Test Suite

Unit tests (Jest) and E2E tests (Maestro) for the RealityCam mobile application.

## Quick Start

```bash
# Install dependencies (from repo root)
pnpm install

# Run unit tests
cd apps/mobile && pnpm test

# Run E2E tests (requires device)
pnpm test:e2e
```

## Test Commands

| Command | Description |
|---------|-------------|
| `pnpm test` | Run all unit tests |
| `pnpm test:watch` | Watch mode for development |
| `pnpm test:coverage` | Generate coverage report |
| `pnpm test:ci` | CI mode with JUnit output |
| `pnpm test:e2e` | Run Maestro E2E flows |
| `pnpm test:e2e:debug` | Maestro debug mode |

## Test Structure

```
tests/
├── setup.ts                      # Jest setup & global mocks
├── __mocks__/                    # Manual mocks
│   └── react-native-vision-camera.ts
└── unit/                         # Unit tests
    └── example.test.ts           # Sample tests (replace with real)

.maestro/
├── flows/                        # Maestro E2E flows
│   └── example-flow.yaml         # Sample flow
└── README.md                     # Maestro documentation
```

## Unit Testing (Jest)

### What to Unit Test

| Component Type | Testable | Notes |
|---------------|----------|-------|
| Hooks (useCapture, useLiDAR) | ✅ | Mock hardware dependencies |
| Zustand stores | ✅ | Direct state manipulation |
| Services (API, storage) | ✅ | Mock fetch/filesystem |
| Components (non-camera) | ✅ | Use RNTL |
| Camera capture | ❌ | Use Maestro E2E instead |
| LiDAR hardware | ❌ | Use Maestro E2E instead |

### Writing Tests

```typescript
import { renderHook, act } from '@testing-library/react-native';

describe('useCapture', () => {
  test('should capture photo with depth map', async () => {
    const { result } = renderHook(() => useCapture());

    await act(async () => {
      await result.current.capture();
    });

    expect(result.current.photo).toBeDefined();
    expect(result.current.depthMap).toBeDefined();
  });
});
```

### Mocks

Pre-configured mocks in `tests/setup.ts`:

- `react-native-vision-camera` - Camera/device mocks
- `expo-secure-store` - Secure storage
- `expo-crypto` - Cryptographic functions
- `expo-file-system` - File operations
- `expo-location` - GPS location
- `@expo/app-integrity` - Attestation
- `@react-native-async-storage/async-storage` - Storage
- `@react-native-community/netinfo` - Network info

### Custom Mock Behavior

```typescript
import { __setMockPhoto } from './__mocks__/react-native-vision-camera';

test('handles low-resolution capture', async () => {
  __setMockPhoto({ width: 640, height: 480 });
  // Test with custom mock
});
```

### Global Test Utilities

```typescript
const { createMockPhoto, createMockDepthMap, waitForNextTick } = global.testUtils;

test('processes depth map', () => {
  const depthMap = createMockDepthMap({ width: 128, height: 96 });
  expect(depthMap.data.length).toBe(128 * 96);
});
```

## E2E Testing (Maestro)

See [.maestro/README.md](../.maestro/README.md) for detailed Maestro documentation.

### Prerequisites

1. **Install Maestro**: `curl -Ls "https://get.maestro.mobile.dev" | bash`
2. **Physical device**: Camera/LiDAR require hardware
3. **Development build**: `npx expo run:ios --device`

### Running Flows

```bash
# Single flow
maestro test .maestro/flows/example-flow.yaml

# All flows
pnpm test:e2e

# Debug mode
pnpm test:e2e:debug
```

### Writing Flows

```yaml
appId: com.realitycam.app
---
- launchApp:
    clearState: true

- tapOn:
    id: "capture-button"

- assertVisible:
    id: "photo-preview"
```

## Coverage

Target thresholds (in `jest.config.js`):

| Metric | Target |
|--------|--------|
| Branches | 50% |
| Functions | 50% |
| Lines | 50% |
| Statements | 50% |

Covered directories:
- `hooks/`
- `services/`
- `store/`
- `components/`

## CI Integration

```bash
pnpm test:ci
```

Outputs:
- `coverage/` - Coverage report
- `junit.xml` - JUnit report (via jest-junit)

### GitHub Actions Example

```yaml
- name: Run Unit Tests
  run: |
    cd apps/mobile
    pnpm test:ci

- name: Upload Coverage
  uses: actions/upload-artifact@v4
  with:
    name: coverage-report
    path: apps/mobile/coverage/
```

## Best Practices

1. **Mock hardware** - Camera/LiDAR require physical device; mock for unit tests
2. **Test stores directly** - `useStore.getState()` and `useStore.setState()` for Zustand
3. **Use testID** - Add `testID` prop to components for Maestro
4. **Isolate tests** - Each test should be independent
5. **Hardware → E2E** - Camera capture flows belong in Maestro, not Jest

## Knowledge Base References

- [test-levels-framework.md](../../../.bmad/bmm/testarch/knowledge/test-levels-framework.md) - When to use unit vs E2E
- [data-factories.md](../../../.bmad/bmm/testarch/knowledge/data-factories.md) - Factory patterns
- [test-quality.md](../../../.bmad/bmm/testarch/knowledge/test-quality.md) - Test design principles

## Next Steps

1. **Replace sample tests** - Run `*test-design` workflow for real scenarios
2. **Add hook tests** - Test useCapture, useLiDAR, useDeviceAttestation
3. **Add store tests** - Test deviceStore, uploadQueueStore
4. **Add Maestro flows** - Capture, upload, preview flows
5. **CI integration** - Add to GitHub Actions workflow

---

*Generated by TEA (Test Architect) - Framework Workflow v4.0*
