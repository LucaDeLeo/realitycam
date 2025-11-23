# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RealityCam is a photo verification platform capturing authenticated photos with hardware attestation (DCAppAttest/Secure Enclave) and LiDAR depth analysis. iPhone Pro only (LiDAR required).

## Common Commands

### Monorepo (pnpm workspace)
```bash
pnpm install                     # Install all dependencies
pnpm dev:web                     # Start Next.js web app (localhost:3000)
pnpm dev:mobile                  # Start Expo mobile server
pnpm lint                        # Lint all packages
pnpm typecheck                   # TypeScript check all packages
```

### Mobile App (apps/mobile)
```bash
cd apps/mobile
pnpm start                       # Start Expo dev server
npx expo prebuild --platform ios # Generate iOS project (first time or after native changes)
npx expo run:ios --device        # Run on physical device (required for camera/LiDAR)
pnpm typecheck                   # TypeScript check
```

### Web App (apps/web)
```bash
cd apps/web
pnpm dev                         # Next.js dev with Turbopack
pnpm build                       # Production build
pnpm typecheck                   # TypeScript check
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

### Docker Services
```bash
pnpm docker:up                   # Start PostgreSQL + LocalStack S3
pnpm docker:down                 # Stop services
```

## Architecture

### Stack
- **Mobile**: Expo SDK 54, React Native 0.81, expo-router, react-native-vision-camera, Zustand
- **Web**: Next.js 16 (Turbopack), React 19, TailwindCSS 4
- **Backend**: Rust, Axum 0.8, SQLx 0.8, c2pa-rs 0.51
- **Database**: PostgreSQL 16
- **Storage**: S3 (LocalStack dev, AWS prod)

### Key Directories
```
apps/mobile/
  app/                    # expo-router file-based routing
  hooks/                  # useCapture, useLiDAR, useDeviceAttestation, etc.
  services/               # api.ts, offlineStorage, uploadService
  store/                  # Zustand stores (deviceStore, uploadQueueStore)
  components/Camera/      # CameraView, DepthOverlay, CaptureButton

apps/web/
  src/app/                # Next.js App Router
  src/components/         # Evidence/, Media/, Upload/

backend/
  src/routes/             # API endpoints (captures, devices, verify, health)
  src/services/           # c2pa, attestation, depth_analysis, storage
  src/middleware/         # device_auth (Ed25519 signature verification)
  src/models/             # SQLx models (capture, device, evidence)
  migrations/             # SQLx migrations

packages/shared/          # TypeScript types shared across apps
```

### Mobile App Flow
1. Device attestation via `@expo/app-integrity` (DCAppAttest)
2. Secure Enclave key generation for signing
3. Photo capture with synchronized LiDAR depth map
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

- **Camera requires physical device**: Simulator doesn't support multi-lens or LiDAR. Use `npx expo run:ios --device`
- **Expo Go not supported for camera**: Must use development build after `expo prebuild`
- **First Rust build is slow**: c2pa-rs compiles many dependencies
- **SQLx offline mode**: Run `cargo sqlx prepare` after schema changes to update `.sqlx/` cache
- **Environment files**: Copy `.env.example` to `.env` in backend/, apps/mobile/, apps/web/

## Database

PostgreSQL 16 with SQLx. Migrations in `backend/migrations/`. Connection via `DATABASE_URL` env var.

```bash
# Create new migration
cd backend
sqlx migrate add <name>

# Run migrations (happens on server start too)
sqlx migrate run
```

## Testing

Mobile/Web tests not yet configured. Backend uses `cargo test` with testcontainers for integration tests.
