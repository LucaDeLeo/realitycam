# Test Framework Setup Report

**Project:** RealityCam
**Date:** 2025-11-22
**Phase:** 3 (Implementation Ready)
**Author:** Test Architect Workflow (BMAD)

---

## Executive Summary

This document describes the production-ready test framework infrastructure created for RealityCam. The framework supports:

- **3 application targets:** iOS mobile (Expo), Rust backend, Next.js web
- **4 test frameworks:** Jest, Vitest, Cargo test, XCTest
- **Full CI/CD pipeline:** GitHub Actions with staged execution
- **Local development:** Docker Compose with PostgreSQL + LocalStack

---

## Directory Structure Created

```
realitycam/
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions CI pipeline
│
├── tests/                          # Shared test infrastructure
│   ├── unit/
│   ├── integration/
│   ├── e2e/
│   └── support/
│       ├── factories/
│       │   ├── device.factory.ts   # Device test data factory
│       │   ├── capture.factory.ts  # Capture test data factory
│       │   └── index.ts
│       └── helpers/
│           ├── api.helper.ts       # API testing utilities
│           ├── assertions.helper.ts # Custom assertions
│           └── index.ts
│
├── apps/
│   ├── web/                        # Next.js 16
│   │   ├── jest.config.js          # Jest configuration
│   │   ├── jest.setup.js           # Test environment setup
│   │   ├── playwright.config.ts    # E2E configuration
│   │   ├── package.json            # Test scripts
│   │   └── e2e/
│   │       └── verification.spec.ts # E2E test examples
│   │
│   └── mobile/                     # Expo/React Native
│       ├── vitest.config.ts        # Vitest configuration
│       ├── vitest.setup.ts         # Mock setup for RN/Expo
│       ├── package.json            # Test scripts
│       └── modules/
│           └── device-attestation/
│               ├── expo-module.config.json
│               └── ios/
│                   ├── DeviceAttestationModuleTests.swift
│                   └── Info.plist
│
├── backend/                        # Rust API
│   ├── Cargo.toml                  # Test dependencies
│   └── tests/
│       └── integration/
│           ├── mod.rs
│           ├── common/
│           │   ├── mod.rs
│           │   ├── test_app.rs     # Test container setup
│           │   ├── factories.rs    # Rust data factories
│           │   └── assertions.rs   # Custom assertions
│           ├── devices_test.rs
│           ├── captures_test.rs
│           ├── verify_test.rs
│           └── evidence_test.rs
│
└── infrastructure/
    ├── docker-compose.yml          # PostgreSQL + LocalStack
    ├── init-scripts/
    │   └── 01-extensions.sql       # Database initialization
    └── localstack-init/
        └── init-s3.sh              # S3 bucket creation
```

---

## Configuration Files Generated

### 1. Jest Configuration (Web)

**File:** `apps/web/jest.config.js`

| Setting | Value |
|---------|-------|
| Test Environment | jsdom |
| Coverage Threshold | 70% (branches, functions, lines, statements) |
| Test Timeout | 10,000ms |
| Transform | @swc/jest (fast TypeScript compilation) |
| Reporters | default, jest-junit |

### 2. Vitest Configuration (Mobile)

**File:** `apps/mobile/vitest.config.ts`

| Setting | Value |
|---------|-------|
| Test Environment | jsdom |
| Coverage Provider | v8 |
| Coverage Threshold | 70% |
| Test Timeout | 10,000ms |
| Pool | threads (parallel execution) |

Includes comprehensive mocks for:
- React Native core modules
- Expo modules (camera, crypto, secure-store, file-system, location)
- Custom device-attestation module
- Zustand store

### 3. Playwright Configuration (Web E2E)

**File:** `apps/web/playwright.config.ts`

| Setting | Value |
|---------|-------|
| Test Timeout | 60,000ms |
| Action Timeout | 15,000ms |
| Navigation Timeout | 30,000ms |
| Retries (CI) | 2 |
| Browsers | Chromium, Firefox, WebKit |
| Mobile Viewports | Pixel 5, iPhone 14 |
| Artifacts | trace, screenshot, video (on failure) |

### 4. Cargo Test Configuration (Backend)

**File:** `backend/Cargo.toml`

Dev dependencies include:
- `testcontainers` + `testcontainers-modules` (PostgreSQL, LocalStack)
- `fake` (test data generation)
- `wiremock` (HTTP mocking)
- `rstest` (parameterized tests)
- `pretty_assertions` (readable diffs)
- `cargo-tarpaulin` (coverage)

### 5. XCTest Harness (Native Module)

**File:** `apps/mobile/modules/device-attestation/ios/DeviceAttestationModuleTests.swift`

Tests for:
- DCAppAttest availability and key generation
- Secure Enclave key operations
- LiDAR depth capture
- Expo Module bridge exports

Hardware-dependent tests use `XCTSkipIf` to skip on simulator.

### 6. Docker Compose (Local Infrastructure)

**File:** `infrastructure/docker-compose.yml`

Services:
- **postgres**: Development database (port 5432)
- **postgres-test**: Isolated test database (port 5433, tmpfs)
- **localstack**: S3-compatible storage (port 4566)
- **pgadmin**: Database UI (port 5050, optional profile)

### 7. GitHub Actions CI Pipeline

**File:** `.github/workflows/ci.yml`

Stages:
1. **Lint & Type Check** - Fast feedback (clippy, eslint, tsc)
2. **Unit Tests** - Parallel execution (web, mobile, backend)
3. **Integration Tests** - Backend with service containers
4. **E2E Tests** - Playwright for web verification page
5. **CI Success** - Aggregated status check

---

## Setup Commands

### Initial Setup

```bash
# Start local infrastructure
cd infrastructure
docker-compose up -d

# Verify containers are running
docker-compose ps
```

### Web App

```bash
cd apps/web
npm install

# Run tests
npm test                    # Unit tests
npm run test:watch          # Watch mode
npm run test:coverage       # Coverage report
npm run test:e2e            # E2E tests
npm run test:e2e:ui         # Interactive E2E
```

### Mobile App

```bash
cd apps/mobile
npm install

# Run tests
npm test                    # Unit tests
npm run test:watch          # Watch mode
npm run test:coverage       # Coverage report

# Native tests (requires Xcode)
npx expo prebuild --platform ios
xcodebuild test -project ios/RealityCam.xcodeproj \
  -scheme RealityCam \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

### Backend

```bash
cd backend

# Run tests
cargo test --lib --bins     # Unit tests
cargo test --test integration # Integration tests

# Coverage
cargo install cargo-tarpaulin
cargo tarpaulin --out Html
open tarpaulin-report.html
```

---

## CI Pipeline Stages

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CI PIPELINE                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Stage 1: LINT & TYPE CHECK                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ - ESLint (web, mobile)                                           │   │
│  │ - TypeScript type checking                                       │   │
│  │ - Clippy (Rust linting)                                          │   │
│  │ - Rustfmt (format check)                                         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  Stage 2: UNIT TESTS (Parallel)                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐              │
│  │  Web (Jest)   │  │Mobile (Vitest)│  │Backend (Cargo)│              │
│  │  + Coverage   │  │  + Coverage   │  │  + Coverage   │              │
│  └───────────────┘  └───────────────┘  └───────────────┘              │
│           │                  │                  │                       │
│           └──────────────────┼──────────────────┘                       │
│                              ▼                                          │
│  Stage 3: INTEGRATION TESTS                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Backend integration tests with:                                  │   │
│  │ - PostgreSQL 16 (service container)                              │   │
│  │ - LocalStack S3 (service container)                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  Stage 4: E2E TESTS                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Playwright E2E tests for web verification page                   │   │
│  │ - Chromium, Firefox, WebKit                                      │   │
│  │ - Mobile viewports                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ✅ CI SUCCESS                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Test Data Factories

### TypeScript (Frontend)

```typescript
import { deviceFactory, captureFactory } from '@tests/support/factories';

// Create attested device
const device = deviceFactory.withSecureEnclave().build();

// Create capture with real 3D scene
const capture = captureFactory
  .forDevice(device.id)
  .withRealSceneDepth()
  .build();

// Create flat depth capture (screen photo simulation)
const fakeCapture = captureFactory.withFlatDepth().build();
```

### Rust (Backend)

```rust
use tests::common::{DeviceFactory, CaptureFactory};

let device = DeviceFactory::new().build_request();
let capture = CaptureFactory::new()
    .with_device_id(device_id)
    .with_real_scene_depth();
```

---

## Next Steps for Phase 1

### Week 1: Infrastructure Validation
1. [ ] Run `docker-compose up -d` and verify all services start
2. [ ] Run `npm test` in apps/web and apps/mobile
3. [ ] Run `cargo test` in backend
4. [ ] Verify CI pipeline runs on GitHub

### Week 2: Evidence Pipeline Tests
1. [ ] Implement depth analysis unit tests with mock data
2. [ ] Implement evidence JSONB structure tests
3. [ ] Implement C2PA manifest generation tests

### Week 3: Native Module Tests
1. [ ] Set up XCTest target in Xcode project
2. [ ] Implement Keychain cleanup between tests
3. [ ] Create MockARKit for simulator depth testing

### Week 4: Baseline Validation
1. [ ] Collect LiDAR baseline dataset (50 real scenes)
2. [ ] Manual ground truth labeling
3. [ ] Empirical threshold tuning
4. [ ] Integrate baseline validation into CI

---

## Coverage Targets

| Component | Target | Status |
|-----------|--------|--------|
| Backend Evidence Module | >= 85% | To do |
| Web Components | >= 70% | To do |
| Mobile Hooks/Store | >= 70% | To do |
| Native Modules (XCTest) | Manual testing | To do |

---

## Files Created Summary

| Category | Count | Files |
|----------|-------|-------|
| Configuration | 6 | jest.config.js, vitest.config.ts, playwright.config.ts, Cargo.toml, docker-compose.yml, ci.yml |
| Setup Files | 3 | jest.setup.js, vitest.setup.ts, init-s3.sh |
| Factories | 4 | device.factory.ts, capture.factory.ts, factories.rs, index.ts |
| Helpers | 3 | api.helper.ts, assertions.helper.ts, assertions.rs |
| Test Files | 6 | devices_test.rs, captures_test.rs, verify_test.rs, evidence_test.rs, verification.spec.ts, DeviceAttestationModuleTests.swift |
| Documentation | 2 | tests/README.md, docs/framework-setup.md |

**Total: 24 files created**

---

## Related Documents

- **System Test Design:** `/docs/test-design-system.md`
- **Architecture:** `/docs/architecture.md`
- **PRD:** `/docs/prd.md`
- **Test README:** `/tests/README.md`

---

_Generated by BMAD Test Architecture Framework Workflow_
_RealityCam Project - Luca_
_Phase 3 (Implementation Ready)_
