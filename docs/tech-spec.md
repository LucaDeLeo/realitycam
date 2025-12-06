# realitycam - Technical Specification

**Author:** Luca
**Date:** 2025-12-05
**Project Level:** Quick-Flow (Standalone)
**Change Type:** Feature - Cross-Stack Debug Observability
**Development Context:** Brownfield (adding to existing iOS + Backend + Web stack)

---

## Context

### Available Documents

| Document | Status | Notes |
|----------|--------|-------|
| Architecture | Loaded | v1.3 with Video support, 11 ADRs |
| Workflow Status | Loaded | Method track, Phase 4, 55 stories in backlog |
| Product Brief | Not found | N/A for this feature |
| Research | Not found | N/A for this feature |

### Project Stack

| Component | Framework | Version | Key Dependencies |
|-----------|-----------|---------|------------------|
| **iOS App** | Swift/SwiftUI | Swift 5.9+ | ARKit, DeviceCheck, CryptoKit, os.log |
| **Backend** | Rust/Axum | 0.8 | tracing 0.1, tower-http 0.6, sqlx 0.8 |
| **Web** | Next.js | 16.0.7 | React 19.2.1, TailwindCSS 4 |
| **Database** | PostgreSQL | 16 | SQLx with JSONB support |
| **Package Manager** | Bun | 1.x | Workspace monorepo |
| **Deployment** | Fly.io (backend), Vercel (web) | - | Docker-based |

### Existing Codebase Structure

**iOS Core Services (32 Swift files in `/ios/Rial/Core/`):**
- `Networking/APIClient.swift` - URLSession client with device auth, uses `os.log` Logger
- `Networking/DeviceSignature.swift` - Ed25519 request signing
- `Attestation/` - DCAppAttest integration
- `Capture/` - ARKit photo/video capture
- `Storage/` - Keychain, Core Data persistence

**Backend Structure (`/backend/src/`):**
- `main.rs` - Axum server with `x-request-id` middleware, tracing setup
- `routes/` - API endpoints (captures, devices, verify, health)
- `services/` - Business logic (c2pa, attestation, depth_analysis)
- `middleware/device_auth.rs` - Ed25519 signature verification

**Web Structure (`/apps/web/`):**
- `src/app/` - Next.js App Router pages
- `src/components/` - Evidence, Media, Upload components
- `src/lib/api.ts` - API client

**Existing Logging Patterns:**

| Layer | Implementation | Structured | Request ID |
|-------|----------------|------------|------------|
| Backend | `tracing` crate | Yes (JSON) | Yes (`x-request-id`) |
| iOS | `os.log` Logger | No | No |
| Web | `console.log` | No | No |

---

## The Change

### Problem Statement

**Current State:**
- iOS app logs stay on device (Xcode console only)
- No correlation between iOS requests and backend processing
- Web app has no structured logging
- Debugging cross-layer issues requires manual log correlation
- Claude cannot access iOS logs without Xcode

**Pain Points:**
1. Can't trace a capture from iOS → Backend → Response without manual effort
2. iOS debug info not accessible via CLI for Claude assistance
3. No unified view of system behavior during development
4. Adding features requires constant context-switching between Xcode, terminal, browser

**Impact:**
- Slower debugging cycles
- Harder to verify integrations work end-to-end
- Claude Code can't help debug iOS ↔ Backend communication effectively

### Proposed Solution

**Debug Observability System** - A cross-stack logging infrastructure for internal development:

1. **Structured Debug Log Format** - JSON schema with correlation IDs, timestamps, event types
2. **Backend Debug Endpoints** - Ingest (`POST /debug/logs`) and query (`GET /debug/logs`)
3. **iOS Debug Logger** - Intercepts network calls, captures request/response, ships to backend
4. **CLI Query Tool** - Bun scripts to tail, search, and filter logs
5. **Web Debug Integration** - Structured logging to same backend endpoint

**Key Design Decisions:**
- PostgreSQL storage with 7-day TTL (queryable, already have DB)
- Batch upload from iOS (POST every 30s) - simpler than WebSocket
- Bun scripts in monorepo (`bun debug:*`)
- Verbose by default in DEBUG builds
- DEBUG-only: no production exposure

### Scope

**In Scope:**

- Debug log schema design (JSON, correlation IDs)
- Backend debug endpoints (ingest + query + cleanup)
- iOS DebugLogger service (DEBUG builds only)
- iOS network interceptor for request/response capture
- CLI tools: `bun debug:tail`, `bun debug:search`, `bun debug:clear`
- Web debug logger (dev mode only)
- Database table for debug logs with TTL
- Integration with existing `x-request-id` header

**Out of Scope:**

- Production logging infrastructure
- Log aggregation services (Datadog, Logtail)
- Real-time WebSocket streaming (future enhancement)
- Android support (no Android app yet)
- UI-based log viewer (CLI only for MVP)
- Log export to file formats
- Performance profiling / APM

---

## Implementation Details

### Source Tree Changes

```
backend/src/
├── routes/
│   ├── mod.rs                         # MODIFY - Add debug routes
│   └── debug.rs                       # CREATE - Debug log endpoints
├── services/
│   ├── mod.rs                         # MODIFY - Export debug service
│   └── debug_logs.rs                  # CREATE - Log storage/query service
├── models/
│   ├── mod.rs                         # MODIFY - Export debug_log model
│   └── debug_log.rs                   # CREATE - DebugLog struct

backend/migrations/
└── YYYYMMDD_create_debug_logs.sql     # CREATE - Debug logs table

ios/Rial/
├── Core/
│   └── Debug/                         # CREATE - New directory
│       ├── DebugLogger.swift          # CREATE - Central debug logging
│       ├── DebugLogEntry.swift        # CREATE - Log entry model
│       ├── DebugLogShipper.swift      # CREATE - Batch upload service
│       └── NetworkDebugInterceptor.swift # CREATE - URLSession interceptor
├── Core/Networking/
│   └── APIClient.swift                # MODIFY - Add correlation ID header

apps/web/
├── src/lib/
│   └── debug-logger.ts                # CREATE - Debug logging utility
├── src/app/
│   └── layout.tsx                     # MODIFY - Initialize debug logger

packages/
└── debug-cli/                         # CREATE - Debug CLI package
    ├── package.json
    ├── src/
    │   ├── index.ts                   # CLI entry point
    │   ├── commands/
    │   │   ├── tail.ts                # Tail logs command
    │   │   ├── search.ts              # Search logs command
    │   │   └── clear.ts               # Clear logs command
    │   └── lib/
    │       └── api.ts                 # Backend API client

package.json                           # MODIFY - Add debug:* scripts
```

### Technical Approach

**Log Entry Schema (JSON):**

```typescript
interface DebugLogEntry {
  id: string;                    // UUID
  correlation_id: string;        // Traces request across layers
  timestamp: string;             // ISO 8601
  source: "ios" | "backend" | "web";
  level: "debug" | "info" | "warn" | "error";
  event: string;                 // e.g., "UPLOAD_REQUEST", "ATTESTATION_VERIFIED"
  payload: Record<string, any>;  // Structured event data
  device_id?: string;            // iOS device identifier (DEBUG builds)
  session_id?: string;           // App session for grouping
}
```

**Correlation ID Flow:**

```
iOS App                          Backend                         Response
   │                                │                                │
   ├─ Generate correlation_id ──────┼────────────────────────────────┤
   │  (UUID v4)                     │                                │
   │                                │                                │
   ├─ X-Correlation-ID header ──────►                                │
   │                                │                                │
   │                                ├─ Extract correlation_id        │
   │                                │                                │
   │                                ├─ Attach to all tracing spans   │
   │                                │                                │
   │                                ◄─ X-Correlation-ID in response ─┤
   │                                │                                │
   └─ Log with same correlation_id ─┴────────────────────────────────┘
```

**Backend Debug Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/debug/logs` | POST | Ingest batch of log entries |
| `/debug/logs` | GET | Query logs with filters |
| `/debug/logs/{id}` | GET | Get single log entry |
| `/debug/logs` | DELETE | Clear logs (with optional filters) |
| `/debug/logs/stats` | GET | Get log counts by source/level |

**Query Parameters (GET /debug/logs):**

| Param | Type | Description |
|-------|------|-------------|
| `correlation_id` | string | Filter by correlation ID |
| `source` | string | Filter by source (ios, backend, web) |
| `level` | string | Filter by level (debug, info, warn, error) |
| `event` | string | Filter by event type (substring match) |
| `since` | string | ISO timestamp, logs after this time |
| `limit` | number | Max results (default 100, max 1000) |
| `order` | string | "asc" or "desc" (default "desc") |

### Existing Patterns to Follow

**Backend (Rust):**
- Follow `routes/captures.rs` pattern for endpoint structure
- Use `services/` pattern for business logic separation
- SQLx query macros for compile-time checked SQL
- `tracing::info!` / `tracing::debug!` for internal logging
- Return `Result<Json<T>, AppError>` from handlers

**iOS (Swift):**
- Follow `APIClient.swift` pattern for network code
- Use `Logger(subsystem: "app.rial", category: "debug")` for os.log
- Actor-based concurrency for thread safety
- `#if DEBUG` preprocessor for debug-only code
- Codable structs for JSON encoding

**Web (TypeScript):**
- Follow `src/lib/api.ts` pattern for API calls
- Use environment checks for dev-only code
- TypeScript interfaces for type safety

### Integration Points

**iOS → Backend:**
- `POST /debug/logs` - Batch upload every 30 seconds
- `X-Correlation-ID` header on all API requests
- Device ID from `DeviceRegistrationService`

**Web → Backend:**
- `POST /debug/logs` - Immediate send (dev mode only)
- `X-Correlation-ID` header on all API requests

**CLI → Backend:**
- `GET /debug/logs` - Query with filters
- `DELETE /debug/logs` - Clear logs

**Backend Internal:**
- Extend existing `x-request-id` to also use `x-correlation-id` if provided
- Log correlation ID in all tracing spans

---

## Development Context

### Relevant Existing Code

| File | Relevance | Lines |
|------|-----------|-------|
| `backend/src/main.rs` | Request ID middleware pattern | 94-132 |
| `backend/src/routes/captures.rs` | Route handler pattern | All |
| `ios/Rial/Core/Networking/APIClient.swift` | Network client pattern | All |
| `ios/Rial/Core/Networking/UploadService.swift` | Background upload pattern | All |

### Dependencies

**Framework/Libraries (all already in project):**

| Dependency | Version | Purpose |
|------------|---------|---------|
| tracing | 0.1 | Backend structured logging |
| sqlx | 0.8 | Database queries |
| axum | 0.8 | HTTP endpoints |
| serde_json | 1 | JSON serialization |
| uuid | 1 | Correlation ID generation |
| chrono | 0.4 | Timestamp handling |

**New Dependencies:**

| Dependency | Version | Purpose |
|------------|---------|---------|
| None | - | All required deps already in Cargo.toml |

**iOS:** No new dependencies (uses Foundation, os.log)

**Web CLI:**
| Dependency | Version | Purpose |
|------------|---------|---------|
| commander | ^11 | CLI argument parsing |
| chalk | ^5 | Terminal colors |

### Internal Modules

**Backend:**
- `services::debug_logs` - New module for log storage
- `routes::debug` - New module for endpoints
- `models::debug_log` - New model

**iOS:**
- `Core/Debug/DebugLogger` - Central logger
- `Core/Debug/DebugLogShipper` - Upload service

### Configuration Changes

**Backend `.env`:**
```env
# Debug logging (optional, defaults shown)
DEBUG_LOGS_ENABLED=true        # Enable debug log endpoints
DEBUG_LOGS_TTL_DAYS=7          # Auto-cleanup after N days
DEBUG_LOGS_MAX_BATCH=100       # Max entries per POST
```

**Backend `config.rs`:**
```rust
pub struct Config {
    // ... existing fields ...
    pub debug_logs_enabled: bool,
    pub debug_logs_ttl_days: u32,
    pub debug_logs_max_batch: usize,
}
```

### Existing Conventions (Brownfield)

**Code Style - Rust:**
- 4-space indentation
- snake_case for functions/variables
- PascalCase for types
- `///` doc comments for public items
- Clippy-clean code

**Code Style - Swift:**
- 4-space indentation
- camelCase for functions/variables
- PascalCase for types
- `///` doc comments for public items
- `#if DEBUG` for debug-only code

**Code Style - TypeScript:**
- 2-space indentation
- camelCase for functions/variables
- PascalCase for types/interfaces
- ESLint + Prettier enforced

### Test Framework & Standards

| Layer | Framework | Pattern | Coverage Target |
|-------|-----------|---------|-----------------|
| Backend | cargo test | `#[cfg(test)]` modules | Core logic |
| iOS | XCTest | `/RialTests/` directory | Services |
| Web | Vitest + Playwright | `__tests__/` + `/tests/e2e/` | CLI commands |

---

## Implementation Stack

| Layer | Technology | Version |
|-------|------------|---------|
| Runtime (Backend) | Rust | 1.82+ |
| Runtime (CLI) | Bun | 1.x |
| Runtime (iOS) | Swift | 5.9+ |
| Framework (Backend) | Axum | 0.8 |
| Framework (Web) | Next.js | 16.0.7 |
| Database | PostgreSQL | 16 |
| ORM | SQLx | 0.8 |
| Logging (Backend) | tracing | 0.1 |
| Logging (iOS) | os.log | Native |

---

## Technical Details

### Database Schema

```sql
-- migrations/YYYYMMDDHHMMSS_create_debug_logs.sql

CREATE TABLE debug_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    correlation_id  UUID NOT NULL,
    timestamp       TIMESTAMPTZ NOT NULL,
    source          TEXT NOT NULL CHECK (source IN ('ios', 'backend', 'web')),
    level           TEXT NOT NULL CHECK (level IN ('debug', 'info', 'warn', 'error')),
    event           TEXT NOT NULL,
    payload         JSONB NOT NULL DEFAULT '{}',
    device_id       UUID,
    session_id      UUID,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX idx_debug_logs_correlation ON debug_logs(correlation_id);
CREATE INDEX idx_debug_logs_timestamp ON debug_logs(timestamp DESC);
CREATE INDEX idx_debug_logs_source ON debug_logs(source);
CREATE INDEX idx_debug_logs_event ON debug_logs(event);

-- Partial index for errors (often queried)
CREATE INDEX idx_debug_logs_errors ON debug_logs(timestamp DESC)
    WHERE level = 'error';
```

### iOS DebugLogger Architecture

```swift
/// Central debug logging service for iOS app.
/// DEBUG builds only - completely compiled out in Release.
#if DEBUG
@MainActor
public final class DebugLogger {
    public static let shared = DebugLogger()

    private var buffer: [DebugLogEntry] = []
    private let shipper: DebugLogShipper
    private var currentSessionId = UUID()

    /// Log a debug event
    public func log(
        event: String,
        level: LogLevel = .info,
        payload: [String: Any] = [:],
        correlationId: UUID? = nil
    ) {
        let entry = DebugLogEntry(
            id: UUID(),
            correlationId: correlationId ?? UUID(),
            timestamp: Date(),
            source: .ios,
            level: level,
            event: event,
            payload: payload,
            deviceId: DeviceRegistrationService.shared.deviceId,
            sessionId: currentSessionId
        )
        buffer.append(entry)

        // Ship if buffer exceeds threshold
        if buffer.count >= 50 {
            Task { await shipper.ship(buffer) }
            buffer.removeAll()
        }
    }

    /// Force immediate ship (called on app background)
    public func flush() async {
        guard !buffer.isEmpty else { return }
        await shipper.ship(buffer)
        buffer.removeAll()
    }
}
#endif
```

### CLI Commands

**`bun debug:tail`** - Live tail of debug logs
```bash
bun debug:tail                    # All logs, newest first
bun debug:tail --source ios       # iOS only
bun debug:tail --level error      # Errors only
bun debug:tail --follow           # Continuous polling (2s interval)
bun debug:tail -n 50              # Last 50 entries
```

**`bun debug:search`** - Search logs
```bash
bun debug:search --correlation-id abc123   # Find by correlation ID
bun debug:search --event UPLOAD            # Events containing "UPLOAD"
bun debug:search --since "1 hour ago"      # Time-based filter
bun debug:search --json                    # Raw JSON output (for Claude)
```

**`bun debug:clear`** - Clear logs
```bash
bun debug:clear                   # Clear all (with confirmation)
bun debug:clear --older-than 1d   # Clear logs older than 1 day
bun debug:clear --source web      # Clear web logs only
bun debug:clear --yes             # Skip confirmation
```

### Security Considerations

1. **DEBUG builds only** - All iOS debug code wrapped in `#if DEBUG`
2. **No sensitive data** - Logs should not contain auth tokens, passwords, or PII
3. **Endpoint protection** - Debug endpoints only enabled via `DEBUG_LOGS_ENABLED=true`
4. **TTL cleanup** - Automatic deletion after 7 days prevents unbounded growth
5. **Local dev only** - CLI tools use localhost by default, requires explicit `--api-url` for prod

### Performance Considerations

1. **Batch uploads** - iOS buffers logs, ships every 30s or 50 entries
2. **Async logging** - Never blocks UI thread
3. **Index optimization** - PostgreSQL indexes on common query patterns
4. **Pagination** - GET endpoint limits to 1000 results max
5. **Background task** - iOS ships logs when app enters background

---

## Development Setup

```bash
# Backend
cd backend
cargo run  # Debug endpoints enabled by default in dev

# iOS (Xcode)
# Build with DEBUG scheme - debug logging enabled automatically

# CLI
cd packages/debug-cli
bun install
bun run build

# Run CLI commands from repo root
bun debug:tail
bun debug:search --event UPLOAD
```

---

## Implementation Guide

### Setup Steps

1. Create feature branch: `git checkout -b feat/debug-observability`
2. Verify dev environment running: `bun docker:up && cd backend && cargo run`
3. Review existing code references (APIClient.swift, main.rs)

### Implementation Steps

**Story 1: Backend Debug Endpoints**
1. Add migration for `debug_logs` table
2. Create `models/debug_log.rs` with structs
3. Create `services/debug_logs.rs` with storage/query logic
4. Create `routes/debug.rs` with endpoints
5. Wire up in `routes/mod.rs`
6. Add config options for debug logging
7. Write tests for endpoints

**Story 2: iOS Debug Logger**
1. Create `Core/Debug/` directory structure
2. Implement `DebugLogEntry` model
3. Implement `DebugLogger` actor
4. Implement `DebugLogShipper` for batch uploads
5. Add correlation ID to `APIClient` requests
6. Wire up app lifecycle hooks (background flush)
7. Write unit tests

**Story 3: CLI Query Tool**
1. Create `packages/debug-cli/` package
2. Implement `tail` command
3. Implement `search` command
4. Implement `clear` command
5. Add workspace scripts to root `package.json`
6. Write integration tests

**Story 4: iOS Network Interceptor**
1. Create `NetworkDebugInterceptor`
2. Hook into `APIClient` perform methods
3. Capture request/response details
4. Log with correlation ID
5. Test with real API calls

**Story 5: Web Debug Integration**
1. Create `src/lib/debug-logger.ts`
2. Add correlation ID to API requests
3. Initialize logger in layout.tsx (dev only)
4. Log key events (page loads, API calls)
5. Test in development mode

### Testing Strategy

| Layer | Test Type | Coverage |
|-------|-----------|----------|
| Backend endpoints | Integration | All CRUD operations |
| iOS DebugLogger | Unit | Log buffering, serialization |
| iOS DebugLogShipper | Unit | Batch upload, error handling |
| CLI commands | Integration | All commands with mock API |
| Web logger | Unit | Event capture, correlation IDs |

### Acceptance Criteria

1. **Given** iOS app makes an API request **When** I run `bun debug:search --correlation-id <id>` **Then** I see both iOS and backend log entries with matching correlation ID

2. **Given** iOS app is in DEBUG build **When** app enters background **Then** buffered logs are shipped to backend

3. **Given** debug logs exist **When** I run `bun debug:tail --source ios` **Then** I see only iOS logs in reverse chronological order

4. **Given** logs older than 7 days exist **When** cleanup job runs **Then** old logs are deleted

5. **Given** production build **When** app runs **Then** no debug logging code is included (verified by binary size)

---

## Developer Resources

### File Paths Reference

**Backend (Create):**
- `/backend/src/routes/debug.rs`
- `/backend/src/services/debug_logs.rs`
- `/backend/src/models/debug_log.rs`
- `/backend/migrations/YYYYMMDDHHMMSS_create_debug_logs.sql`

**Backend (Modify):**
- `/backend/src/routes/mod.rs`
- `/backend/src/services/mod.rs`
- `/backend/src/models/mod.rs`
- `/backend/src/config.rs`

**iOS (Create):**
- `/ios/Rial/Core/Debug/DebugLogger.swift`
- `/ios/Rial/Core/Debug/DebugLogEntry.swift`
- `/ios/Rial/Core/Debug/DebugLogShipper.swift`
- `/ios/Rial/Core/Debug/NetworkDebugInterceptor.swift`

**iOS (Modify):**
- `/ios/Rial/Core/Networking/APIClient.swift`
- `/ios/Rial/App/RialApp.swift` (background flush)

**Web/CLI (Create):**
- `/packages/debug-cli/package.json`
- `/packages/debug-cli/src/index.ts`
- `/packages/debug-cli/src/commands/tail.ts`
- `/packages/debug-cli/src/commands/search.ts`
- `/packages/debug-cli/src/commands/clear.ts`
- `/apps/web/src/lib/debug-logger.ts`

**Root (Modify):**
- `/package.json` (add debug:* scripts)

### Key Code Locations

| Code | File | Line (approx) |
|------|------|---------------|
| Request ID middleware | `backend/src/main.rs` | 94-132 |
| APIClient perform | `ios/Rial/Core/Networking/APIClient.swift` | 155-174 |
| Route registration | `backend/src/routes/mod.rs` | router setup |

### Testing Locations

| Layer | Directory |
|-------|-----------|
| Backend | `/backend/src/routes/debug.rs` (inline tests) |
| iOS | `/ios/RialTests/Debug/` |
| CLI | `/packages/debug-cli/tests/` |

### Documentation to Update

- `CLAUDE.md` - Add debug CLI commands section
- `README.md` - Add Debug Observability section (optional)

---

## UX/UI Considerations

**No UI impact** - This is a developer tooling feature. All interaction is via CLI.

**CLI Output Formatting:**
- Use colors for log levels (red=error, yellow=warn, blue=info, gray=debug)
- Align columns for readability
- Support `--json` flag for machine-readable output (Claude consumption)
- Show correlation IDs prominently for easy copy-paste

---

## Testing Approach

**Test Framework:**
- Backend: `cargo test` with inline `#[cfg(test)]` modules
- iOS: XCTest in `/RialTests/Debug/`
- CLI: Vitest with mock API responses

**Test Strategy:**

1. **Unit Tests:**
   - DebugLogger buffering logic
   - Log entry serialization
   - Query parameter parsing

2. **Integration Tests:**
   - Full CRUD on debug logs endpoint
   - Batch upload from iOS simulator
   - CLI commands against test backend

3. **Manual Testing:**
   - Trigger capture in iOS app
   - Run `bun debug:search --correlation-id <id>`
   - Verify end-to-end trace visibility

---

## Deployment Strategy

### Deployment Steps

1. Merge backend changes, deploy to Fly.io (`fly deploy`)
2. Build iOS DEBUG scheme for development devices
3. Install CLI package (`bun install` in monorepo)
4. Verify with `bun debug:tail`

### Rollback Plan

1. Set `DEBUG_LOGS_ENABLED=false` in Fly.io env
2. Redeploy backend (endpoints return 404)
3. iOS/Web continue to work (POST fails silently)

### Monitoring

- Backend logs show debug endpoint usage via existing tracing
- PostgreSQL table size can be monitored for growth
- No production impact (DEBUG builds only)

---

_Generated by BMAD Tech-Spec Workflow_
_Date: 2025-12-05_
_For: Luca_
