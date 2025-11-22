# RealityCam Test Infrastructure

This document describes the test framework architecture for RealityCam.

## Directory Structure

```
realitycam/
├── tests/                         # Shared test infrastructure
│   ├── unit/                      # Cross-project unit tests
│   ├── integration/               # Cross-project integration tests
│   ├── e2e/                       # Cross-project E2E tests
│   └── support/
│       ├── factories/             # Test data factories (TypeScript)
│       │   ├── device.factory.ts
│       │   ├── capture.factory.ts
│       │   └── index.ts
│       └── helpers/               # Test utilities
│           ├── api.helper.ts
│           ├── assertions.helper.ts
│           └── index.ts
│
├── apps/
│   ├── web/                       # Next.js 16 verification site
│   │   ├── jest.config.js         # Unit test config
│   │   ├── jest.setup.js          # Test setup
│   │   ├── playwright.config.ts   # E2E test config
│   │   └── e2e/                   # Playwright E2E tests
│   │
│   └── mobile/                    # Expo/React Native app
│       ├── vitest.config.ts       # Unit test config
│       ├── vitest.setup.ts        # Test setup
│       └── modules/
│           └── device-attestation/
│               └── ios/
│                   └── DeviceAttestationModuleTests.swift  # XCTest
│
├── backend/                       # Rust API server
│   ├── Cargo.toml                 # Test dependencies
│   └── tests/
│       └── integration/           # Integration tests
│           ├── mod.rs
│           ├── common/
│           │   ├── mod.rs
│           │   ├── test_app.rs    # Test app with containers
│           │   ├── factories.rs   # Rust data factories
│           │   └── assertions.rs  # Custom assertions
│           ├── devices_test.rs
│           ├── captures_test.rs
│           ├── verify_test.rs
│           └── evidence_test.rs
│
└── infrastructure/
    ├── docker-compose.yml         # PostgreSQL + LocalStack
    ├── init-scripts/              # Database init
    └── localstack-init/           # S3 bucket setup
```

## Quick Start

### 1. Start Local Infrastructure

```bash
cd infrastructure
docker-compose up -d
```

This starts:
- PostgreSQL 16 on port 5432 (dev) and 5433 (test)
- LocalStack (S3) on port 4566
- pgAdmin on port 5050 (optional, use `--profile tools`)

### 2. Run Tests

**Web (Next.js) - Unit Tests:**
```bash
cd apps/web
npm install
npm test                # Run once
npm run test:watch      # Watch mode
npm run test:coverage   # With coverage
```

**Web (Next.js) - E2E Tests:**
```bash
cd apps/web
npx playwright install
npm run test:e2e        # Run E2E tests
npm run test:e2e:ui     # Interactive mode
```

**Mobile (Expo) - Unit Tests:**
```bash
cd apps/mobile
npm install
npm test                # Run once
npm run test:watch      # Watch mode
npm run test:coverage   # With coverage
```

**Mobile (Expo) - Native Tests (XCTest):**
```bash
cd apps/mobile
npx expo prebuild --platform ios
xcodebuild test -project ios/RealityCam.xcodeproj \
  -scheme RealityCam \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

**Backend (Rust) - Unit Tests:**
```bash
cd backend
cargo test --lib --bins
```

**Backend (Rust) - Integration Tests:**
```bash
cd backend
cargo test --test integration
```

**Backend (Rust) - Coverage:**
```bash
cd backend
cargo install cargo-tarpaulin
cargo tarpaulin --out Html
```

## Test Data Factories

### TypeScript Factories (Web/Mobile)

```typescript
import { deviceFactory, captureFactory } from '../support/factories';

// Create a device with secure enclave attestation
const device = deviceFactory.withSecureEnclave().build();

// Create a capture with realistic 3D scene depth
const capture = captureFactory
  .forDevice(device.id)
  .withRealSceneDepth()
  .build();

// Create a capture simulating photo of screen (flat depth)
const fakeCapture = captureFactory
  .withFlatDepth()
  .build();
```

### Rust Factories (Backend)

```rust
use tests::common::{DeviceFactory, CaptureFactory};

// Create a device
let device = DeviceFactory::new()
    .with_model("iPhone 15 Pro")
    .build_request();

// Create a capture with real scene depth
let capture = CaptureFactory::new()
    .with_device_id(device_id)
    .with_real_scene_depth();
```

## Custom Assertions

### TypeScript

```typescript
import { assertRealScene, assertDepthVarianceAbove } from '../support/helpers';

// Assert depth analysis detected real scene
assertRealScene(evidence);

// Assert specific metrics
assertDepthVarianceAbove(evidence, 0.5);
```

### Rust

```rust
use tests::common::assertions::*;

// Assert confidence level
assert_confidence_level(&evidence, "high");

// Assert real scene detected
assert_real_scene(&evidence);
```

## CI Pipeline

The GitHub Actions workflow runs in stages:

1. **Lint & Type Check** - Fast feedback on code quality
2. **Unit Tests** - Parallel execution for web, mobile, backend
3. **Integration Tests** - Backend tests with real containers
4. **E2E Tests** - Playwright tests for web verification page

See `.github/workflows/ci.yml` for details.

## Configuration Reference

### Jest (Web)

| Config | Value |
|--------|-------|
| Test Environment | jsdom |
| Coverage Threshold | 70% (all metrics) |
| Test Timeout | 10s |
| Reporters | default, jest-junit |

### Vitest (Mobile)

| Config | Value |
|--------|-------|
| Test Environment | jsdom |
| Coverage Provider | v8 |
| Coverage Threshold | 70% (all metrics) |
| Test Timeout | 10s |

### Playwright (Web E2E)

| Config | Value |
|--------|-------|
| Test Timeout | 60s |
| Action Timeout | 15s |
| Navigation Timeout | 30s |
| Browsers | Chromium, Firefox, WebKit |
| Retries (CI) | 2 |

### Cargo Test (Backend)

| Config | Value |
|--------|-------|
| Test Profile | opt-level = 1 |
| Coverage Tool | cargo-tarpaulin |
| Integration Tests | testcontainers |

## Native Module Testing (XCTest)

The Swift code for DCAppAttest, Secure Enclave, and LiDAR capture is tested via XCTest:

- **DeviceAttestationModuleTests.swift** - Tests for native module

Tests that require real hardware (Secure Enclave, LiDAR) use `XCTSkipIf` to skip on simulator.

## Test Isolation

### Database Isolation (Backend)

Each integration test gets its own PostgreSQL schema:
- Schema created before test
- Migrations run in schema
- Schema dropped after test

### Mock Isolation (Frontend)

- Jest/Vitest mocks reset between tests
- Factory instances cleaned up via `cleanup()` method
- LocalStorage/AsyncStorage cleared

## Environment Variables

### Local Development

```bash
# apps/web/.env.local
NEXT_PUBLIC_API_URL=http://localhost:3001/api
NEXT_PUBLIC_CDN_URL=http://localhost:4566

# apps/mobile/.env
EXPO_PUBLIC_API_URL=http://localhost:3001/api

# backend/.env
DATABASE_URL=postgres://realitycam:realitycam_dev@localhost:5432/realitycam_dev
S3_ENDPOINT=http://localhost:4566
S3_BUCKET=realitycam-media-dev
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_REGION=us-east-1
```

### CI Environment

Environment variables are set in the GitHub Actions workflow.

## Coverage Requirements

| Component | Target |
|-----------|--------|
| Backend Evidence Module | >= 85% |
| Web Components | >= 70% |
| Mobile Hooks/Store | >= 70% |

## Next Steps

1. Run `docker-compose up -d` to start infrastructure
2. Install dependencies in each app directory
3. Run `npm test` or `cargo test` to verify setup
4. Write tests alongside implementation
