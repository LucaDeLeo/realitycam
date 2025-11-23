# RealityCam

Photo verification platform that captures authenticated photos with hardware attestation and LiDAR depth analysis.

## Prerequisites

- **Node.js** 22+ (with pnpm 9+)
- **Rust** 1.82+
- **Docker** 24+
- **Xcode** 16+ (for iOS development)

## Project Structure

```
realitycam/
  apps/
    mobile/           # Expo SDK 54 + React Native 0.81 (iOS-only)
    web/              # Next.js 16 + Turbopack + TailwindCSS
  packages/
    shared/           # TypeScript types shared across apps
  backend/            # Rust/Axum API server
  infrastructure/     # Docker Compose for local services
  docs/               # Project documentation
```

## Quick Start

### 1. Install Dependencies

```bash
# Install pnpm if not already installed
npm install -g pnpm

# Install all workspace dependencies
pnpm install
```

### 2. Start Docker Services

```bash
# Start PostgreSQL and LocalStack
docker-compose -f infrastructure/docker-compose.yml up -d

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

# Mobile (optional for local dev)
cp apps/mobile/.env.example apps/mobile/.env

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

### 5. Run Mobile App (iOS)

```bash
cd apps/mobile
pnpm install

# Generate iOS project (first time only)
npx expo prebuild --platform ios

# Start Expo dev server
pnpm start
```

Press `i` to open in iOS Simulator or scan QR with Expo Go on device.

### 6. Run Web App

```bash
cd apps/web
pnpm dev
```

Opens at http://localhost:3000

## Development Scripts

| Command | Description |
|---------|-------------|
| `pnpm dev:web` | Start web development server |
| `pnpm dev:mobile` | Start mobile Expo server |
| `pnpm docker:up` | Start Docker services |
| `pnpm docker:down` | Stop Docker services |
| `pnpm lint` | Run linters across all packages |
| `pnpm typecheck` | Run TypeScript type checking |

## Environment Variables

### Backend (`backend/.env`)

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgres://realitycam:localdev@localhost:5432/realitycam` |
| `S3_ENDPOINT` | S3-compatible endpoint | `http://localhost:4566` |
| `S3_BUCKET` | S3 bucket name | `realitycam-media-dev` |
| `RUST_LOG` | Logging level | `info,sqlx=warn` |
| `PORT` | Server port | `8080` |

### Mobile (`apps/mobile/.env`)

| Variable | Description | Default |
|----------|-------------|---------|
| `API_URL` | Backend API URL | `http://localhost:8080` |

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

### Expo Prebuild Issues

```bash
cd apps/mobile
rm -rf ios/
npx expo prebuild --platform ios --clean
```

### TypeScript Errors with Shared Types

```bash
# Rebuild shared package
pnpm --filter @realitycam/shared typecheck
```

## Tech Stack

- **Mobile**: Expo SDK 54, React Native 0.81, expo-router
- **Web**: Next.js 16, React 19, TailwindCSS 4
- **Backend**: Rust, Axum 0.8, SQLx, c2pa-rs
- **Database**: PostgreSQL 16
- **Storage**: S3 (LocalStack for dev, AWS for prod)
- **Types**: TypeScript, shared via workspace

## License

Proprietary - All rights reserved
