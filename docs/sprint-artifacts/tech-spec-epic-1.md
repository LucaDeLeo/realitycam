# Epic Technical Specification: Foundation & Project Setup

Date: 2025-11-22
Author: Luca
Epic ID: 1
Status: Draft

---

## Overview

Epic 1 establishes the complete development infrastructure for RealityCam, a cryptographically-attested, LiDAR-verified photo provenance system for iPhone Pro devices. This foundation epic creates the monorepo structure housing three interconnected applications (iOS mobile, Rust backend, Next.js verification web), configures local development services (PostgreSQL, S3-compatible storage), initializes the database schema for devices and captures, and scaffolds all API routes. The goal is to enable rapid development velocity across all subsequent epics by providing a fully operational development environment with working health checks and placeholder routes.

This epic directly supports the PRD's core architecture of iOS App (Expo/React Native) + Backend (Rust/Axum) + Verification Web (Next.js 16) and implements the technical decisions documented in the Architecture v1.1.

## Objectives and Scope

### In Scope

- Monorepo structure matching architecture specification (apps/mobile, apps/web, backend, packages/shared)
- Expo SDK 53 mobile app with TypeScript, file-based routing, and iOS-only prebuild
- Next.js 16 web app with App Router, Turbopack, TailwindCSS, and TypeScript
- Rust/Axum backend with all dependencies from architecture Cargo.toml
- Docker-based local development (PostgreSQL 16, LocalStack S3)
- Database schema with devices, captures, and verification_logs tables
- SQLx migrations with compile-time checked queries
- Health check endpoint with database connectivity verification
- API route stubs for all MVP endpoints (501 Not Implemented initially)
- Shared TypeScript types package for API contracts
- Environment configuration files for all components
- Basic tab navigation structure in mobile app
- Verification page route structure in web app

### Out of Scope

- DCAppAttest integration (Epic 2)
- LiDAR depth capture module (Epic 3)
- Actual API implementation (Epics 2-5)
- C2PA manifest generation (Epic 5)
- CI/CD pipeline configuration
- Production deployment infrastructure
- Certificate pinning
- HSM key management setup

## System Architecture Alignment

This epic implements the project structure defined in Architecture v1.1:

**Component Alignment:**
- `apps/mobile/` - Expo SDK 53 + React Native 0.79, iOS-only prebuild
- `apps/web/` - Next.js 16 with Turbopack, App Router, React 19.2
- `backend/` - Rust/Axum 0.8.x with SQLx 0.8, c2pa-rs 0.51.x
- `packages/shared/` - TypeScript types for evidence, capture, API contracts
- `infrastructure/` - docker-compose.yml for local services

**Architecture Constraints Acknowledged:**
- iPhone Pro only for MVP (iOS-only prebuild)
- PostgreSQL 16 with JSONB for evidence storage
- S3-compatible storage for media files
- SQLx with compile-time query checking
- TLS 1.3 requirement (backend configuration)

**ADRs Referenced:**
- ADR-001: iPhone Pro Only (MVP) - iOS-only prebuild
- ADR-003: Rust Backend with Axum - Framework choice
- ADR-006: JSONB for Evidence Storage - Schema design

## Detailed Design

### Services and Modules

| Service/Module | Responsibility | Inputs | Outputs | Owner |
|----------------|----------------|--------|---------|-------|
| `apps/mobile/` | iOS app shell with navigation | User interaction | Screen renders | Mobile team |
| `apps/mobile/app/(tabs)/` | Tab-based navigation (Capture, History) | Route changes | Screen transitions | Mobile team |
| `apps/mobile/store/` | Zustand state management setup | State updates | Persisted state | Mobile team |
| `apps/mobile/services/api.ts` | API client stub | Config | HTTP client | Mobile team |
| `apps/web/` | Verification site shell | HTTP requests | HTML/React | Web team |
| `apps/web/app/verify/[id]/` | Dynamic verification route | Capture ID | Verification page | Web team |
| `apps/web/lib/api.ts` | Backend API client | Config | Fetch wrapper | Web team |
| `backend/src/main.rs` | Application entry, server startup | Config | Running server | Backend team |
| `backend/src/config.rs` | Environment configuration | .env | Config struct | Backend team |
| `backend/src/routes/` | API route handlers | HTTP requests | JSON responses | Backend team |
| `backend/src/middleware/` | Request ID, logging | Requests | Enriched requests | Backend team |
| `backend/src/models/` | Database entity definitions | SQLx queries | Rust structs | Backend team |
| `backend/src/error.rs` | Error types and handling | Errors | HTTP error responses | Backend team |
| `packages/shared/` | TypeScript type definitions | None | Type exports | Shared |
| `infrastructure/docker-compose.yml` | Local service orchestration | Docker commands | Running containers | DevOps |

### Data Models and Contracts

#### Database Schema (PostgreSQL 16)

**Table: devices**
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attestation_level   TEXT NOT NULL DEFAULT 'unverified',
    attestation_key_id  TEXT NOT NULL UNIQUE,
    attestation_chain   BYTEA,
    platform            TEXT NOT NULL,
    model               TEXT NOT NULL,
    has_lidar           BOOLEAN NOT NULL DEFAULT false,
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_devices_attestation_key ON devices(attestation_key_id);
```

**Table: captures**
```sql
CREATE TABLE captures (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id           UUID NOT NULL REFERENCES devices(id),
    target_media_hash   BYTEA NOT NULL UNIQUE,
    depth_map_key       TEXT,
    evidence            JSONB NOT NULL DEFAULT '{}',
    confidence_level    TEXT NOT NULL DEFAULT 'low',
    status              TEXT NOT NULL DEFAULT 'pending',
    captured_at         TIMESTAMPTZ NOT NULL,
    uploaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_captures_hash ON captures USING hash(target_media_hash);
CREATE INDEX idx_captures_device ON captures(device_id);
CREATE INDEX idx_captures_status ON captures(status);
```

**Table: verification_logs**
```sql
CREATE TABLE verification_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capture_id  UUID REFERENCES captures(id),
    action      TEXT NOT NULL,
    client_ip   INET,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verification_logs_capture ON verification_logs(capture_id);
```

#### Rust Entity Models

```rust
// backend/src/models/device.rs
#[derive(Debug, sqlx::FromRow, Serialize)]
pub struct Device {
    pub id: Uuid,
    pub attestation_level: String,
    pub attestation_key_id: String,
    pub attestation_chain: Option<Vec<u8>>,
    pub platform: String,
    pub model: String,
    pub has_lidar: bool,
    pub first_seen_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
}

// backend/src/models/capture.rs
#[derive(Debug, sqlx::FromRow, Serialize)]
pub struct Capture {
    pub id: Uuid,
    pub device_id: Uuid,
    pub target_media_hash: Vec<u8>,
    pub depth_map_key: Option<String>,
    pub evidence: serde_json::Value,
    pub confidence_level: String,
    pub status: String,
    pub captured_at: DateTime<Utc>,
    pub uploaded_at: DateTime<Utc>,
}
```

#### TypeScript Types (packages/shared)

```typescript
// packages/shared/src/types/api.ts
export interface ApiResponse<T> {
  data: T;
  meta: {
    request_id: string;
    timestamp: string;
  };
}

export interface ApiError {
  error: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
  };
  meta: {
    request_id: string;
    timestamp: string;
  };
}

// packages/shared/src/types/evidence.ts
export type ConfidenceLevel = 'high' | 'medium' | 'low' | 'suspicious';
export type EvidenceStatus = 'pass' | 'fail' | 'unavailable';

export interface HardwareAttestation {
  status: EvidenceStatus;
  level: 'secure_enclave' | 'unverified';
  device_model: string;
}

export interface DepthAnalysis {
  status: EvidenceStatus;
  depth_variance: number;
  depth_layers: number;
  edge_coherence: number;
  min_depth: number;
  max_depth: number;
  is_likely_real_scene: boolean;
}

export interface Evidence {
  hardware_attestation: HardwareAttestation;
  depth_analysis: DepthAnalysis;
  metadata: {
    timestamp_valid: boolean;
    model_verified: boolean;
    location_available: boolean;
    location_coarse?: string;
  };
}

// packages/shared/src/types/capture.ts
export interface Capture {
  id: string;
  confidence_level: ConfidenceLevel;
  captured_at: string;
  media_url: string;
  evidence: Evidence;
  c2pa_manifest_url?: string;
  depth_visualization_url?: string;
}
```

### APIs and Interfaces

#### Backend API Routes (Stubs)

| Method | Path | Purpose | Request | Response | Status |
|--------|------|---------|---------|----------|--------|
| GET | `/health` | Health check | None | HealthResponse | Implemented |
| GET | `/api/v1/devices/challenge` | Get attestation challenge | None | ChallengeResponse | Stub (501) |
| POST | `/api/v1/devices/register` | Register device | DeviceRegisterRequest | DeviceResponse | Stub (501) |
| POST | `/api/v1/captures` | Upload capture | Multipart | CaptureResponse | Stub (501) |
| GET | `/api/v1/captures/{id}` | Get capture with evidence | None | CaptureDetailResponse | Stub (501) |
| POST | `/api/v1/verify-file` | Verify file by hash | File upload | VerifyResponse | Stub (501) |

**Health Check Response:**
```json
{
  "status": "ok",
  "database": "connected",
  "version": "0.1.0",
  "timestamp": "2025-11-22T10:00:00Z"
}
```

**Error Response Format (all endpoints):**
```json
{
  "error": {
    "code": "NOT_IMPLEMENTED",
    "message": "This endpoint is not yet implemented"
  },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-11-22T10:00:00Z"
  }
}
```

#### Mobile App API Client Interface

```typescript
// apps/mobile/services/api.ts
export interface ApiClient {
  baseUrl: string;
  health(): Promise<HealthResponse>;
  // Stubs for future implementation
  getChallenge(): Promise<ChallengeResponse>;
  registerDevice(request: DeviceRegisterRequest): Promise<DeviceResponse>;
  uploadCapture(data: FormData): Promise<CaptureResponse>;
  getCapture(id: string): Promise<CaptureDetailResponse>;
}
```

#### Web App API Client Interface

```typescript
// apps/web/lib/api.ts
export interface WebApiClient {
  baseUrl: string;
  getCapture(id: string): Promise<CaptureDetailResponse>;
  verifyFile(file: File): Promise<VerifyResponse>;
}
```

### Workflows and Sequencing

#### Local Development Setup Workflow

```
Developer → Clone repo
    │
    ├─→ docker-compose -f infrastructure/docker-compose.yml up -d
    │       │
    │       ├─→ PostgreSQL 16 starts (localhost:5432)
    │       └─→ LocalStack S3 starts (localhost:4566)
    │
    ├─→ Backend setup
    │       │
    │       ├─→ cp .env.example .env
    │       ├─→ sqlx migrate run
    │       └─→ cargo run → Server on :8080
    │
    ├─→ Mobile setup
    │       │
    │       ├─→ npm install
    │       ├─→ npx expo prebuild --platform ios
    │       └─→ npx expo start → Expo DevTools
    │
    └─→ Web setup
            │
            ├─→ npm install
            └─→ npm run dev → localhost:3000
```

#### Health Check Flow

```
Client → GET /health
    │
    ├─→ Backend checks database connection
    │       │
    │       ├─→ SELECT 1 (connection test)
    │       └─→ Return connection status
    │
    └─→ Return HealthResponse {
            status: "ok",
            database: "connected" | "disconnected",
            version: "0.1.0"
        }
```

#### Mobile App Navigation Flow

```
App Launch
    │
    └─→ (tabs)/_layout.tsx
            │
            ├─→ capture.tsx (Capture tab)
            │       └─→ Placeholder: "Capture screen coming soon"
            │
            └─→ history.tsx (History tab)
                    └─→ Placeholder: "History screen coming soon"
```

#### Web App Routing Flow

```
Request
    │
    ├─→ / (Landing page)
    │       └─→ Placeholder: "RealityCam - Verify photo authenticity"
    │
    └─→ /verify/[id] (Verification page)
            └─→ Placeholder: "Verifying capture: {id}"
```

## Non-Functional Requirements

### Performance

| Metric | Target | Implementation |
|--------|--------|----------------|
| Health check latency | < 100ms | Simple DB ping, no complex queries |
| Backend cold start | < 3s | Minimal dependency initialization |
| Web FCP | < 1s | Static placeholder pages |
| Mobile app launch | < 2s | Minimal initial bundle |
| Docker services startup | < 30s | Optimized compose configuration |

### Security

| Requirement | Implementation |
|-------------|----------------|
| TLS 1.3 preparation | Backend configured for HTTPS (cert handling in future stories) |
| CORS configuration | Allow localhost origins for development |
| Environment secrets | .env files gitignored, .env.example provided |
| Database credentials | Environment variables, not hardcoded |
| S3 credentials | Environment variables for LocalStack in dev |

### Reliability/Availability

| Requirement | Implementation |
|-------------|----------------|
| Database connection pooling | SQLx with configurable pool size (default: 10) |
| Graceful shutdown | Axum graceful shutdown handler |
| Health check endpoint | Database connectivity verification |
| Error handling | Proper error types with thiserror |

### Observability

| Requirement | Implementation |
|-------------|----------------|
| Request logging | tower-http tracing middleware |
| Request IDs | UUID per request in X-Request-Id header |
| Structured logging | tracing-subscriber with JSON format option |
| Database query logging | SQLx query logging at debug level |

## Dependencies and Integrations

### Backend Dependencies (Cargo.toml)

| Dependency | Version | Purpose |
|------------|---------|---------|
| axum | 0.8.x | Web framework |
| axum-extra | 0.10.x | Typed headers, multipart |
| tower | 0.5.x | Service traits |
| tower-http | 0.6.x | CORS, tracing, request-id |
| tokio | 1.x | Async runtime (full features) |
| sqlx | 0.8.x | Database with postgres, uuid, chrono, json |
| c2pa | 0.51.x | C2PA SDK (file_io feature) |
| ed25519-dalek | 2.x | Cryptography |
| sha2 | 0.10.x | Hashing |
| x509-parser | 0.16.x | Certificate parsing |
| serde | 1.x | Serialization |
| serde_json | 1.x | JSON handling |
| aws-sdk-s3 | 1.x | S3 operations |
| aws-config | 1.x | AWS configuration |
| uuid | 1.x | UUID generation (v4, serde) |
| chrono | 0.4.x | Date/time (serde) |
| thiserror | 2.x | Error handling |
| tracing | 0.1.x | Instrumentation |
| tracing-subscriber | 0.3.x | Logging (json feature) |
| dotenvy | 0.15.x | Environment loading |

### Mobile Dependencies (package.json)

| Dependency | Version | Purpose |
|------------|---------|---------|
| expo | ~53.0.0 | Framework |
| expo-router | ^4.0.0 | File-based routing |
| expo-camera | ~17.0.0 | Camera access (future) |
| expo-crypto | ~15.0.0 | Cryptography (future) |
| expo-secure-store | ~15.0.0 | Secure storage (future) |
| expo-file-system | ~19.0.0 | File operations (future) |
| zustand | ^5.0.0 | State management |
| react-native | 0.79.x | React Native core |
| typescript | ^5.x | Type checking |

### Web Dependencies (package.json)

| Dependency | Version | Purpose |
|------------|---------|---------|
| next | ^16.0.0 | Framework |
| react | ^19.2.0 | UI library |
| react-dom | ^19.2.0 | React DOM rendering |
| tailwindcss | ^4.x | Styling |
| typescript | ^5.x | Type checking |

### Infrastructure Dependencies

| Service | Version | Purpose |
|---------|---------|---------|
| PostgreSQL | 16 | Primary database |
| LocalStack | 3.8.x | S3-compatible storage (dev) |
| Docker | 24+ | Container runtime |
| Node.js | 22+ | JS runtime |
| Rust | 1.82+ | Backend language |
| Xcode | 16+ | iOS development |

## Acceptance Criteria (Authoritative)

### AC-1.1: Monorepo Structure Initialized
**Given** a fresh clone of the repository
**When** the developer inspects the directory structure
**Then** the following paths exist:
- `apps/mobile/` with Expo SDK 53 configuration
- `apps/web/` with Next.js 16 configuration
- `backend/` with Cargo.toml matching architecture spec
- `packages/shared/src/types/` with evidence.ts, capture.ts, api.ts
- `infrastructure/docker-compose.yml`

### AC-1.2: Docker Services Operational
**Given** Docker is installed and running
**When** the developer runs `docker-compose up -d` from project root
**Then**:
- PostgreSQL 16 is accessible on localhost:5432
- LocalStack S3 is accessible on localhost:4566
- Both services pass health checks within 30 seconds
- `realitycam` database exists in PostgreSQL
- `realitycam-media-dev` bucket exists in LocalStack

### AC-1.3: Database Schema Applied
**Given** PostgreSQL is running
**When** the developer runs `sqlx migrate run` from backend directory
**Then**:
- `devices` table exists with all specified columns
- `captures` table exists with all specified columns and foreign key
- `verification_logs` table exists
- Hash index on `captures.target_media_hash` is created
- B-tree indexes on `captures.device_id` and `devices.attestation_key_id` are created

### AC-1.4: Backend Health Check Operational
**Given** database migrations are applied
**When** the developer runs `cargo run` and calls `GET http://localhost:8080/health`
**Then** the response is:
```json
{
  "status": "ok",
  "database": "connected",
  "version": "0.1.0",
  "timestamp": "2025-11-22T10:00:00Z"
}
```
**And** the response status code is 200

### AC-1.5: Backend Route Stubs Return 501
**Given** the backend is running
**When** the developer calls any of:
- `GET /api/v1/devices/challenge`
- `POST /api/v1/devices/register`
- `POST /api/v1/captures`
- `GET /api/v1/captures/test-id`
- `POST /api/v1/verify-file`
**Then** each returns HTTP 501 with error body:
```json
{
  "error": {
    "code": "NOT_IMPLEMENTED",
    "message": "This endpoint is not yet implemented"
  }
}
```

### AC-1.6: Request Logging and IDs Active
**Given** the backend is running
**When** any request is made
**Then**:
- Request is logged with method, path, and duration
- Response includes `X-Request-Id` header with UUID
- Logs are structured (JSON parseable in production mode)

### AC-1.7: Mobile App Runs with Tab Navigation
**Given** Xcode is installed and iOS simulator available
**When** the developer runs `npx expo start` and opens in iOS simulator
**Then**:
- App displays with bottom tab bar
- "Capture" tab shows placeholder content
- "History" tab shows placeholder content
- Navigation between tabs works

### AC-1.8: Mobile App Prebuilds for iOS Only
**Given** the mobile app is configured
**When** the developer runs `npx expo prebuild --platform ios`
**Then**:
- iOS project is generated in `ios/` directory
- Android project is NOT generated
- Build configuration targets iOS 14.0+

### AC-1.9: Web App Runs with Verification Route
**Given** Node.js 22+ is installed
**When** the developer runs `npm run dev` from apps/web
**Then**:
- Development server starts with Turbopack
- `http://localhost:3000/` shows landing placeholder
- `http://localhost:3000/verify/test-123` shows "Verifying capture: test-123"
- TailwindCSS styles are applied

### AC-1.10: Environment Files Configured
**Given** the project is set up
**When** the developer inspects environment configuration
**Then**:
- `backend/.env.example` contains DATABASE_URL, S3_ENDPOINT, S3_BUCKET, RUST_LOG
- `apps/mobile/.env.example` contains API_URL
- `apps/web/.env.example` contains NEXT_PUBLIC_API_URL
- All .env files are in .gitignore

### AC-1.11: Shared Types Package Importable
**Given** the shared package is built
**When** mobile or web imports from `@realitycam/shared`
**Then**:
- TypeScript types are available
- No runtime dependencies required
- Types match API contract specifications

## Traceability Mapping

| AC | Spec Section | Component(s) | Test Approach |
|----|--------------|--------------|---------------|
| AC-1.1 | Services and Modules | All apps, packages | Directory structure verification, package.json/Cargo.toml validation |
| AC-1.2 | Dependencies/Integrations | infrastructure/ | Docker health check verification, port connectivity tests |
| AC-1.3 | Data Models | backend/migrations | SQLx migrate status, schema introspection |
| AC-1.4 | APIs/Interfaces | backend/routes | HTTP integration test for /health |
| AC-1.5 | APIs/Interfaces | backend/routes | HTTP integration tests returning 501 |
| AC-1.6 | Observability | backend/middleware | Log output verification, header inspection |
| AC-1.7 | Workflows | apps/mobile | Maestro E2E test or manual verification |
| AC-1.8 | Architecture Alignment | apps/mobile | Prebuild output inspection |
| AC-1.9 | Workflows | apps/web | Playwright E2E test or manual verification |
| AC-1.10 | Security | All components | File existence check, gitignore verification |
| AC-1.11 | Data Models | packages/shared | TypeScript compilation test |

## Risks, Assumptions, Open Questions

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|------------|--------|------------|
| R1 | Expo SDK 53 / React Native 0.79 compatibility issues | Medium | High | Pin exact versions, test early |
| R2 | Next.js 16 is bleeding edge, may have bugs | Medium | Medium | Can fallback to 15.x if needed |
| R3 | LocalStack S3 behavior differs from real AWS | Low | Medium | Document differences, test critical flows |
| R4 | SQLx compile-time checking requires running database | Low | Low | Document in setup instructions |
| R5 | c2pa-rs 0.51 requires Rust 1.82+ | Low | Low | Document Rust version requirement |

### Assumptions

| ID | Assumption | Validation |
|----|------------|------------|
| A1 | Developer has Docker Desktop installed | Document in README |
| A2 | macOS with Xcode 16+ for iOS development | Document in README |
| A3 | Node.js 22+ available for web/mobile | Document in README |
| A4 | Rust 1.82+ available for backend | Document in README |
| A5 | iPhone Pro device available for later testing | Can use simulator for Epic 1 |

### Open Questions

| ID | Question | Impact | Resolution Path |
|----|----------|--------|-----------------|
| Q1 | Should we use pnpm/bun workspaces for monorepo? | Medium | Decide during implementation, npm works |
| Q2 | Do we need turborepo for build orchestration? | Low | Defer to post-MVP |
| Q3 | Should web use Next.js 15 for stability? | Medium | Test 16, fallback if issues |

## Test Strategy Summary

### Unit Tests

| Component | Framework | Coverage Target | ACs Covered |
|-----------|-----------|-----------------|-------------|
| Backend routes | cargo test | Health endpoint, error responses | AC-1.4, AC-1.5, AC-1.6 |
| Shared types | tsc --noEmit | Type correctness | AC-1.11 |
| Mobile components | Jest | Component rendering | AC-1.7 |
| Web components | Vitest | Component rendering | AC-1.9 |

### Integration Tests

| Scenario | Tool | Description | ACs Covered |
|----------|------|-------------|-------------|
| Database connectivity | testcontainers | Verify SQLx pool creation, migrations | AC-1.3 |
| Health endpoint | reqwest | HTTP test against running server | AC-1.4 |
| S3 connectivity | aws-sdk | Verify LocalStack bucket operations | AC-1.2 |

### End-to-End Tests

| Scenario | Tool | Description | ACs Covered |
|----------|------|-------------|-------------|
| Mobile tab navigation | Maestro | Verify tab switching works | AC-1.7, AC-1.8 |
| Web route rendering | Playwright | Verify pages render correctly | AC-1.9 |

### Manual Verification

| Scenario | Steps | ACs Covered |
|----------|-------|-------------|
| Full local setup | Follow README, verify all services start | AC-1.1, AC-1.2, AC-1.10 |
| Health check | curl localhost:8080/health | AC-1.4 |
| Mobile app launch | Run in iOS simulator, verify tabs | AC-1.7, AC-1.8 |
| Web app launch | Open localhost:3000, navigate routes | AC-1.9 |

### Test Commands

```bash
# Backend tests
cd backend && cargo test

# Mobile tests
cd apps/mobile && npm test

# Web tests
cd apps/web && npm test

# Integration (requires docker)
cd backend && cargo test --features integration
```
