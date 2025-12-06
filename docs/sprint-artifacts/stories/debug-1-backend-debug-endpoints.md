# Story: Backend Debug Endpoints

## Story Information
- **Story ID:** debug-1-backend-debug-endpoints
- **Epic:** Quick-Flow: Debug Observability System
- **Priority:** High
- **Estimate:** M (Medium)

## Description

Implement the backend debug logging infrastructure including database schema, Rust models, services, and REST API endpoints for ingesting, querying, and managing debug logs. This forms the foundation of the cross-stack debug observability system, enabling iOS, web, and CLI clients to ship and retrieve structured debug logs with correlation IDs for tracing requests across the entire stack.

## Acceptance Criteria

- [ ] AC1: Database migration creates `debug_logs` table with correct schema including columns: id (UUID PK), correlation_id (UUID), timestamp (TIMESTAMPTZ), source (TEXT with CHECK constraint for 'ios'|'backend'|'web'), level (TEXT with CHECK constraint for 'debug'|'info'|'warn'|'error'), event (TEXT), payload (JSONB), device_id (UUID nullable), session_id (UUID nullable), created_at (TIMESTAMPTZ)
- [ ] AC2: Database indexes are created for common query patterns: correlation_id, timestamp DESC, source, event, and partial index for errors
- [ ] AC3: POST /debug/logs endpoint accepts batch of log entries (up to DEBUG_LOGS_MAX_BATCH, default 100) and returns 201 with count of inserted entries
- [ ] AC4: GET /debug/logs endpoint supports query parameters: correlation_id, source, level, event (substring match), since (ISO timestamp), limit (default 100, max 1000), order (asc/desc, default desc)
- [ ] AC5: GET /debug/logs/{id} endpoint returns single log entry by UUID or 404 if not found
- [ ] AC6: DELETE /debug/logs endpoint clears logs with optional filters (source, level, older_than timestamp) and returns count of deleted entries
- [ ] AC7: GET /debug/logs/stats endpoint returns aggregated counts grouped by source and level
- [ ] AC8: Config struct includes debug_logs_enabled (bool), debug_logs_ttl_days (u32, default 7), debug_logs_max_batch (usize, default 100)
- [ ] AC9: All debug endpoints return 404 when DEBUG_LOGS_ENABLED=false
- [ ] AC10: Integration tests cover all CRUD operations and query parameter combinations

## Technical Notes

### Log Entry Schema (JSON)
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

### Query Parameters (GET /debug/logs)
| Param | Type | Description |
|-------|------|-------------|
| correlation_id | string | Filter by correlation ID |
| source | string | Filter by source (ios, backend, web) |
| level | string | Filter by level (debug, info, warn, error) |
| event | string | Filter by event type (substring match) |
| since | string | ISO timestamp, logs after this time |
| limit | number | Max results (default 100, max 1000) |
| order | string | "asc" or "desc" (default "desc") |

### Existing Patterns to Follow
- Follow `routes/captures.rs` pattern for endpoint structure
- Use `services/` pattern for business logic separation
- SQLx query macros for compile-time checked SQL
- `tracing::info!` / `tracing::debug!` for internal logging
- Return `Result<Json<T>, AppError>` from handlers

### Database Schema
```sql
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

CREATE INDEX idx_debug_logs_correlation ON debug_logs(correlation_id);
CREATE INDEX idx_debug_logs_timestamp ON debug_logs(timestamp DESC);
CREATE INDEX idx_debug_logs_source ON debug_logs(source);
CREATE INDEX idx_debug_logs_event ON debug_logs(event);
CREATE INDEX idx_debug_logs_errors ON debug_logs(timestamp DESC) WHERE level = 'error';
```

### Configuration
```rust
pub struct Config {
    // ... existing fields ...
    pub debug_logs_enabled: bool,      // DEBUG_LOGS_ENABLED env var
    pub debug_logs_ttl_days: u32,      // DEBUG_LOGS_TTL_DAYS env var, default 7
    pub debug_logs_max_batch: usize,   // DEBUG_LOGS_MAX_BATCH env var, default 100
}
```

## Tasks

- [ ] Task 1: Add migration for `debug_logs` table with schema and indexes
- [ ] Task 2: Create `models/debug_log.rs` with DebugLog, CreateDebugLog, DebugLogQuery, and DebugLogStats structs
- [ ] Task 3: Create `services/debug_logs.rs` with insert_batch, query, get_by_id, delete, and get_stats functions
- [ ] Task 4: Create `routes/debug.rs` with POST /debug/logs, GET /debug/logs, GET /debug/logs/{id}, DELETE /debug/logs, GET /debug/logs/stats endpoints
- [ ] Task 5: Wire up debug routes in `routes/mod.rs` with conditional enablement based on config
- [ ] Task 6: Add debug_logs_enabled, debug_logs_ttl_days, debug_logs_max_batch to config.rs
- [ ] Task 7: Write integration tests for all endpoints and query parameter combinations

## Files to Create

- `backend/migrations/20251206003000_create_debug_logs.sql` - Database migration
- `backend/src/models/debug_log.rs` - DebugLog model and related structs
- `backend/src/services/debug_logs.rs` - Debug log service with storage/query logic
- `backend/src/routes/debug.rs` - Debug API endpoints

## Files to Modify

- `backend/src/routes/mod.rs` - Add debug routes registration
- `backend/src/services/mod.rs` - Export debug_logs module
- `backend/src/models/mod.rs` - Export debug_log module
- `backend/src/config.rs` - Add debug logging configuration options

## Dependencies

- None (this is the first story in the Debug Observability epic)

## Testing Requirements

### Unit Tests
- DebugLogQuery parameter validation
- Config parsing for debug options

### Integration Tests
- POST /debug/logs with valid batch returns 201
- POST /debug/logs with oversized batch returns 400
- POST /debug/logs when disabled returns 404
- GET /debug/logs returns entries in correct order
- GET /debug/logs with each query parameter filters correctly
- GET /debug/logs with combined filters works correctly
- GET /debug/logs respects limit and max limit
- GET /debug/logs/{id} returns entry or 404
- DELETE /debug/logs removes matching entries
- DELETE /debug/logs with filters removes only matching entries
- GET /debug/logs/stats returns correct aggregations

### Test Location
- `backend/src/routes/debug.rs` (inline `#[cfg(test)]` module)

---

## Dev Agent Record

_This section will be populated during implementation._
