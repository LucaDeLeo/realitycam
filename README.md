# RealityCam

> **Hackathon Note:** This repository has continued development after the hackathon deadline. The current version includes deployment to Fly.io/Vercel, a native Swift iOS rewrite, comprehensive CI, and various cleanups.
>
> **To view the code as it was at the hackathon deadline (~9pm Sunday, Nov 24, 2025 Argentina time), see commit [`2938e2e`](https://github.com/LucaDeLeo/realitycam/tree/2938e2e).**

---

Photo verification platform that captures authenticated photos with hardware attestation and LiDAR depth analysis.

## Live Demo

- **Web App**: [rial-web.vercel.app](https://rial-web.vercel.app)
- **Backend API**: [rial-api.fly.dev](https://rial-api.fly.dev) (Fly.io)

## Prerequisites

- **Bun** 1.3+
- **Rust** 1.82+
- **Docker** 24+ (for local development)
- **Xcode** 16+ (for iOS development)
- **iPhone Pro** or newer (LiDAR required for depth capture)

## Project Structure

```
realitycam/
  ios/                  # Native Swift iOS app (SwiftUI, ARKit, DCAppAttest)
    Rial/               # Main app target
    RialTests/          # XCTest unit tests
    RialUITests/        # XCTest UI tests
  apps/
    web/                # Next.js 16 + Turbopack + TailwindCSS
  packages/
    shared/             # TypeScript types shared across web app
  backend/              # Rust/Axum API server
  infrastructure/       # Docker Compose for local services
```

## Quick Start

### 1. Install Dependencies

```bash
# Install Bun if not already installed
# See https://bun.sh for installation options
curl -fsSL https://bun.sh/install | bash

# Install all workspace dependencies
bun install
```

### 2. Start Docker Services (Local Dev)

```bash
# Start PostgreSQL and LocalStack
bun docker:up

# Verify services are healthy
docker-compose -f infrastructure/docker-compose.yml ps
```

Services:
- **PostgreSQL**: localhost:5432 (database: realitycam)
- **LocalStack S3**: localhost:4566 (bucket: realitycam-media-dev)

### 3. Configure Environment

```bash
# Backend
cp backend/.env.example backend/.env

# Web
cp apps/web/.env.example apps/web/.env
```

### 4. Build and Run Backend

```bash
cd backend
cargo build
cargo run
```

The API server starts at http://localhost:8080

### 5. Run iOS App

> **Note:** The iOS app requires a **physical iPhone Pro** (or newer) with LiDAR for full functionality. Simulator works for UI testing but not LiDAR capture.

```bash
cd ios
open Rial.xcodeproj

# In Xcode:
# 1. Select your physical iPhone device (or simulator for UI testing)
# 2. Press Cmd+R to build and run
```

Configure the backend URL in `Rial/Core/Configuration/AppEnvironment.swift` for local development.

### 6. Run Web App

```bash
cd apps/web
bun dev
```

Opens at http://localhost:3000

## Development Scripts

| Command | Description |
|---------|-------------|
| `bun dev:web` | Start web development server |
| `bun docker:up` | Start Docker services |
| `bun docker:down` | Stop Docker services |
| `bun lint` | Run linters across all packages |
| `bun typecheck` | Run TypeScript type checking |

## CI/CD

GitHub Actions runs on every push/PR to main:

1. **Lint & Type Check** - ESLint, TypeScript, Clippy, rustfmt
2. **Unit Tests** (parallel with change detection):
   - Web (Vitest)
   - iOS (XCTest)
   - Backend (cargo test)
3. **Integration Tests** - Backend with PostgreSQL + LocalStack
4. **E2E Tests** - Playwright against production

**Deployment**:
- **Web**: Auto-deploys to Vercel on push to main
- **Backend**: Deploy to Fly.io with `fly deploy` from `backend/`

## Environment Variables

### Backend (`backend/.env`)

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgres://realitycam:localdev@localhost:5432/realitycam` |
| `S3_ENDPOINT` | S3-compatible endpoint | `http://localhost:4566` |
| `S3_BUCKET` | S3 bucket name | `realitycam-media-dev` |
| `RUST_LOG` | Logging level | `info,sqlx=warn` |
| `PORT` | Server port | `8080` |

### Web (`apps/web/.env`)

| Variable | Description | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_API_URL` | Backend API URL | `http://localhost:8080` |

## Hardware Attestation (Why captures show "Unverified")

In development builds, captures will display as **"Unverified"** on the verification page. This is expected and correct behavior.

### Why This Happens

RealityCam uses Apple's **DCAppAttest** (App Attest) for hardware-backed device verification. This cryptographic attestation:

1. Proves the capture came from a genuine Apple device with Secure Enclave
2. Binds each photo to the specific device that captured it
3. Prevents spoofing or tampering with device identity

**However, App Attest only works with App Store/TestFlight distribution:**

- Requires proper Apple provisioning profile (not development signing)
- Certificate chain must anchor to Apple's App Attest Root CA
- Development builds cannot generate valid attestation

### What This Means for Demo

| Build Type | Attestation Status | Captures Marked |
|------------|-------------------|-----------------|
| Development (Xcode) | Fails | "Unverified" |
| TestFlight | Works | "Verified" |
| App Store | Works | "Verified" |

The system is working correctly - it accurately identifies that hardware attestation is not available in development mode. In production with proper App Store distribution, captures would show as "Verified" with full cryptographic proof.

### Enabling Full Attestation

To see verified captures, distribute via TestFlight:

1. Archive the app in Xcode
2. Upload to App Store Connect
3. Enable TestFlight testing (~30 min processing)
4. Install TestFlight build on device

## Troubleshooting

### Docker Services Not Starting

```bash
# Check logs
docker-compose -f infrastructure/docker-compose.yml logs

# Restart services
docker-compose -f infrastructure/docker-compose.yml down
docker-compose -f infrastructure/docker-compose.yml up -d
```

### PostgreSQL Connection Issues

```bash
# Verify PostgreSQL is running
psql -h localhost -U realitycam -d realitycam -c "SELECT 1"
# Password: localdev
```

### LocalStack S3 Issues

```bash
# Verify bucket exists
aws --endpoint-url=http://localhost:4566 s3 ls s3://realitycam-media-dev
```

### Rust Build Errors

```bash
# Clean and rebuild
cd backend
cargo clean
cargo build
```

Note: First build will take several minutes due to c2pa-rs dependencies.

### Xcode Build Issues

```bash
# Clean build
cd ios && xcodebuild clean -scheme Rial

# Reset derived data (nuclear option)
rm -rf ~/Library/Developer/Xcode/DerivedData/Rial-*
```

### TypeScript Errors with Shared Types

```bash
# Rebuild shared package
bun run --filter @realitycam/shared typecheck
```

## Tech Stack

- **iOS**: Native Swift, SwiftUI, ARKit, DCAppAttest, Combine
- **Web**: Next.js 16, React 19, TailwindCSS 4
- **Backend**: Rust, Axum 0.8, SQLx, c2pa-rs
- **Database**: PostgreSQL 16
- **Storage**: S3 (LocalStack for dev, AWS for prod)
- **CI/CD**: GitHub Actions, Vercel, Fly.io

## License

Proprietary - All rights reserved
