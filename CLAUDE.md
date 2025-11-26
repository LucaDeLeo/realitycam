# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RealityCam is a photo verification platform capturing authenticated photos with hardware attestation (DCAppAttest/Secure Enclave) and LiDAR depth analysis. iPhone Pro only (LiDAR required).

## Common Commands

### Monorepo (pnpm workspace)
```bash
pnpm install                     # Install all dependencies
pnpm dev:web                     # Start Next.js web app (localhost:3000)
pnpm lint                        # Lint all packages
pnpm typecheck                   # TypeScript check all packages
```

### iOS App (ios/Rial)
```bash
cd ios

# Build and run
xcodebuild -scheme Rial -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# Run unit tests
xcodebuild test -project Rial.xcodeproj -scheme Rial \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:RialTests

# Run UI tests
xcodebuild test -project Rial.xcodeproj -scheme Rial \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:RialUITests

# Open in Xcode
open Rial.xcodeproj
```

### Web App (apps/web)
```bash
cd apps/web
pnpm dev                         # Next.js dev with Turbopack
pnpm build                       # Production build
pnpm typecheck                   # TypeScript check
pnpm test                        # Run Playwright E2E tests
```

### Backend (Rust/Axum)
```bash
cd backend
cargo build                      # Build (first build is slow due to c2pa-rs)
cargo run                        # Run server (localhost:8080)
cargo test                       # Run all tests
cargo test <test_name>           # Run single test
cargo clippy                     # Lint
SQLX_OFFLINE=true cargo build    # Build with cached query metadata
```

### Docker Services (Local Dev)
```bash
pnpm docker:up                   # Start PostgreSQL + LocalStack S3
pnpm docker:down                 # Stop services
```

## Architecture

### Stack
- **iOS**: Native Swift, SwiftUI, ARKit, DCAppAttest, Combine
- **Web**: Next.js 16 (Turbopack), React 19, TailwindCSS 4
- **Backend**: Rust, Axum 0.8, SQLx 0.8, c2pa-rs 0.51
- **Database**: PostgreSQL 16
- **Storage**: S3 (LocalStack dev, AWS prod)

### Deployment
- **Web**: Vercel (config: `vercel.json`) → [rial-web.vercel.app](https://rial-web.vercel.app)
- **Backend**: Fly.io (config: `backend/fly.toml`) → [rial-api.fly.dev](https://rial-api.fly.dev)

### Key Directories
```
ios/
  Rial/
    App/                      # SwiftUI entry (RialApp, ContentView, AppDelegate)
    Core/
      Attestation/            # DeviceAttestationService, CaptureAssertionService
      Capture/                # ARCaptureSession, FrameProcessor, DepthVisualizer
      Configuration/          # AppEnvironment
      Crypto/                 # CryptoService (Secure Enclave)
      Networking/             # APIClient, UploadService, DeviceSignature, RetryManager
      Storage/                # KeychainService, CaptureStore, OfflineQueue, CaptureEncryption
    Features/
      Capture/                # CaptureView, CaptureViewModel, ARViewContainer
      History/                # HistoryView, HistoryViewModel
      Result/                 # ResultDetailView, EvidenceSummaryView
    Models/                   # CaptureData
  RialTests/                  # XCTest unit tests
  RialUITests/                # XCTest UI tests

apps/web/
  src/app/                    # Next.js App Router
  src/components/             # Evidence/, Media/, Upload/
  tests/                      # Playwright E2E tests + fixtures

backend/
  src/routes/                 # API endpoints (captures, devices, verify, health, test)
  src/services/               # c2pa, attestation, depth_analysis, storage
  src/middleware/             # device_auth (Ed25519 signature verification)
  src/models/                 # SQLx models (capture, device, evidence)
  migrations/                 # SQLx migrations

packages/shared/              # TypeScript types shared across apps
```

### iOS App Flow
1. Device attestation via DCAppAttest
2. Secure Enclave key generation for signing
3. Photo capture with synchronized LiDAR depth map (ARKit)
4. Local processing (hash, compress, metadata collection)
5. Per-capture attestation signature
6. Upload with device signature auth
7. Offline queue with encrypted storage

### Backend Flow
1. Device registration with attestation verification
2. Capture upload with signature verification
3. Attestation validation (capture-level)
4. LiDAR depth analysis service
5. Metadata validation
6. Evidence package generation with confidence score
7. C2PA manifest generation and signing (Ed25519)

### Auth Pattern
No tokens. Device auth uses Ed25519 signatures from Secure Enclave keys. Each request signed with device private key, verified via registered public key.

## Important Notes

- **LiDAR requires physical device**: Simulator doesn't support LiDAR depth capture
- **First Rust build is slow**: c2pa-rs compiles many dependencies
- **SQLx offline mode**: Run `cargo sqlx prepare` after schema changes to update `.sqlx/` cache
- **Environment files**: Copy `.env.example` to `.env` in backend/, apps/web/

## Database

PostgreSQL 16 with SQLx. Migrations in `backend/migrations/`. Connection via `DATABASE_URL` env var.

```bash
# Create new migration
cd backend
sqlx migrate add <name>

# Run migrations (happens on server start too)
sqlx migrate run
```

## CI/CD

### GitHub Actions (`.github/workflows/ci.yml`)

**Triggers**: Push/PR to main

**Stages**:
1. **Lint & Type Check** - ESLint, TypeScript, Clippy, rustfmt
2. **Unit Tests** (parallel, with change detection):
   - Web (Vitest) - runs if `apps/web/**` changed
   - iOS (XCTest) - runs if `ios/**` changed
   - Backend (cargo test) - runs if `backend/**` changed
3. **Integration Tests** - Backend with PostgreSQL + LocalStack containers
4. **E2E Tests** - Playwright (Chromium) against production

**Change Detection**: Uses `dorny/paths-filter` to skip unchanged components.

### Deployment
- **Vercel**: Auto-deploys web app on push to main
- **Fly.io**: Deploy backend with `cd backend && fly deploy`

## Testing

### Backend (Rust)
```bash
cd backend
cargo test                       # Run all unit/integration tests
cargo test <test_name>           # Run specific test
```

### Web App (Vitest + Playwright)
```bash
cd apps/web
pnpm test:unit                   # Run Vitest unit tests (lib functions)
pnpm test:unit:watch             # Watch mode for unit tests
pnpm test:unit:coverage          # Unit tests with coverage
pnpm test                        # Run all E2E tests (Chromium, Firefox, WebKit, Mobile)
pnpm test -- --project=chromium  # Run Chromium only (faster)
pnpm exec playwright install     # Install browsers (first time)
```

**Test Infrastructure:**
- **Unit Tests**: Vitest with jsdom for lib utilities and React components
- **Component Tests**: React Testing Library with Next.js mocks
- **E2E Tests**: Playwright with multi-browser support
- **Browsers**: Chromium, Firefox, WebKit, Mobile Chrome
- **Data Factories**: `EvidenceFactory` for API-based test data seeding
- **Test Endpoints**: Backend has `/api/v1/test/evidence` endpoints (only enabled with `ENABLE_TEST_ENDPOINTS=true`)

**Test Files:**
```
apps/web/
  src/lib/__tests__/            # Unit tests for lib utilities (status.ts, api.ts)
  src/app/**/__tests__/         # Component tests (error.tsx, not-found.tsx)
  tests/e2e/                    # E2E test specs
  tests/support/fixtures/       # Playwright fixtures
  vitest.config.ts              # Vitest configuration
  vitest.setup.ts               # Next.js mocks and test utilities
```

### iOS App (XCTest)
```bash
cd ios

# Run all unit tests
xcodebuild test -project Rial.xcodeproj -scheme Rial \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:RialTests

# Run specific test class
xcodebuild test -project Rial.xcodeproj -scheme Rial \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:RialTests/CryptoServiceTests
```

**Test Files:**
```
ios/
  RialTests/
    Attestation/              # DeviceAttestationServiceTests, CaptureAssertionServiceTests
    Capture/                  # ARCaptureSessionTests, FrameProcessorTests, DepthVisualizerTests
    Crypto/                   # CryptoServiceTests
    Networking/               # RetryManagerTests, UploadServiceTests
    Storage/                  # KeychainServiceTests, CaptureStoreTests, CaptureEncryptionTests
  RialUITests/                # UI automation tests
```

## Running Everything (Full Stack)

### 1. Start Infrastructure (Local Dev)
```bash
# From repo root
docker-compose -f infrastructure/docker-compose.yml up -d

# Verify services
docker-compose -f infrastructure/docker-compose.yml ps
# Should show: postgres (5432), localstack (4566)
```

### 2. Start Backend
```bash
cd backend
cargo run
# Server at http://localhost:8080
# First run auto-runs migrations
```

### 3. Start Web App
```bash
cd apps/web
pnpm dev
# Server at http://localhost:3000
```

### 4. Run iOS App
```bash
cd ios
open Rial.xcodeproj
# Select your device (physical for LiDAR, simulator for UI testing)
# Cmd+R to build and run
```

### 5. Configure iOS API URL
Update `AppEnvironment.swift` or use environment configuration for the backend URL.

## When to Rebuild / Refresh

| Change Type | Action Required |
|-------------|-----------------|
| **Swift code** | Cmd+R in Xcode (automatic rebuild) |
| **TypeScript/JS in web** | Hot reload (automatic) |
| **Rust backend code** | Restart `cargo run` |
| **Database schema** | Add migration, restart backend |
| **Environment variables** | Restart affected service |

### Quick Troubleshooting
```bash
# Kill stuck backend process
lsof -ti:8080 | xargs kill -9

# Clean Xcode build
cd ios && xcodebuild clean -scheme Rial

# Reset derived data (nuclear option)
rm -rf ~/Library/Developer/Xcode/DerivedData/Rial-*
```
