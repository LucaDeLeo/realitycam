# Story Debug-1: Backend Debug Endpoints

Status: drafted

## Story

As a **developer debugging cross-stack issues**,
I want **backend endpoints to ingest, query, and manage debug log entries**,
so that **I can store and retrieve structured debug logs from iOS, web, and backend sources with correlation ID tracing**.

## Acceptance Criteria

1. **AC-1: Debug Logs Database Table**
   - Given the backend is started
   - When migrations are applied
   - Then a `debug_logs` table exists with columns: id, correlation_id, timestamp, source, level, event, payload (JSONB), device_id, session_id, created_at
   - And appropriate indexes exist for correlation_id, timestamp, source, and event queries
   - And a partial index exists for error-level logs

2. **AC-2: POST /debug/logs - Batch Ingest**
   - Given DEBUG_LOGS_ENABLED=true in config
   - When a POST request is made to `/api/v1/debug/logs` with an array of log entries
   - Then each valid entry is inserted into the debug_logs table
   - And the response returns a count of inserted entries
   - And entries exceeding DEBUG_LOGS_MAX_BATCH (default 100) are rejected with 400
   - And malformed entries are rejected with validation error

3. **AC-3: GET /debug/logs - Query with Filters**
   - Given debug logs exist in the database
   - When a GET request is made to `/api/v1/debug/logs` with optional query params (correlation_id, source, level, event, since, limit, order)
   - Then matching logs are returned in JSON format
   - And results are limited to `limit` param (default 100, max 1000)
   - And results are ordered by timestamp (default desc)
   - And event filter performs substring match

4. **AC-4: GET /debug/logs/{id} - Single Entry**
   - Given a debug log entry exists with a specific ID
   - When a GET request is made to `/api/v1/debug/logs/{id}`
   - Then the full log entry is returned
   - And 404 is returned for non-existent IDs

5. **AC-5: DELETE /debug/logs - Clear Logs**
   - Given debug logs exist in the database
   - When a DELETE request is made to `/api/v1/debug/logs` with optional filters (source, older_than)
   - Then matching logs are deleted
   - And a count of deleted entries is returned

6. **AC-6: GET /debug/logs/stats - Aggregated Stats**
   - Given debug logs exist in the database
   - When a GET request is made to `/api/v1/debug/logs/stats`
   - Then counts are returned grouped by source and level
   - And total count is included
   - And oldest/newest timestamps are included

7. **AC-7: Configuration Options**
   - Given the backend config
   - When DEBUG_LOGS_ENABLED=false
   - Then all debug endpoints return 404
   - And when DEBUG_LOGS_TTL_DAYS is set (default 7)
   - Then logs older than TTL are eligible for cleanup
   - And when DEBUG_LOGS_MAX_BATCH is set (default 100)
   - Then batch inserts exceeding the limit are rejected

## Tasks / Subtasks

- [ ] Task 1: Create Database Migration
  - [ ] 1.1: Create migration file `YYYYMMDDHHMMSS_create_debug_logs.sql`
  - [ ] 1.2: Define debug_logs table with all columns (id UUID, correlation_id UUID, timestamp TIMESTAMPTZ, source TEXT, level TEXT, event TEXT, payload JSONB, device_id UUID, session_id UUID, created_at TIMESTAMPTZ)
  - [ ] 1.3: Add CHECK constraints for source (ios, backend, web) and level (debug, info, warn, error)
  - [ ] 1.4: Create indexes: correlation_id, timestamp DESC, source, event
  - [ ] 1.5: Create partial index for error-level logs

- [ ] Task 2: Create Debug Log Model
  - [ ] 2.1: Create `models/debug_log.rs` with DebugLog struct
  - [ ] 2.2: Add DebugLogEntry struct for API input (without id, created_at)
  - [ ] 2.3: Implement Serialize/Deserialize derives
  - [ ] 2.4: Add validation methods for source/level enums
  - [ ] 2.5: Export from `models/mod.rs`

- [ ] Task 3: Create Debug Logs Service
  - [ ] 3.1: Create `services/debug_logs.rs` module
  - [ ] 3.2: Implement `insert_batch()` - bulk insert log entries
  - [ ] 3.3: Implement `query_logs()` - filtered query with pagination
  - [ ] 3.4: Implement `get_by_id()` - single log lookup
  - [ ] 3.5: Implement `delete_logs()` - filtered deletion
  - [ ] 3.6: Implement `get_stats()` - aggregated counts by source/level
  - [ ] 3.7: Export from `services/mod.rs`

- [ ] Task 4: Create Debug Routes
  - [ ] 4.1: Create `routes/debug.rs` module
  - [ ] 4.2: Implement POST /debug/logs handler with batch validation
  - [ ] 4.3: Implement GET /debug/logs handler with query param parsing
  - [ ] 4.4: Implement GET /debug/logs/{id} handler
  - [ ] 4.5: Implement DELETE /debug/logs handler
  - [ ] 4.6: Implement GET /debug/logs/stats handler
  - [ ] 4.7: Create router() function with conditional mounting

- [ ] Task 5: Wire Up Routes and Config
  - [ ] 5.1: Add debug routes to `routes/mod.rs` with feature flag check
  - [ ] 5.2: Add config fields to Config struct: debug_logs_enabled, debug_logs_ttl_days, debug_logs_max_batch
  - [ ] 5.3: Add environment variable parsing in config.rs
  - [ ] 5.4: Update .env.example with DEBUG_LOGS_* variables

- [ ] Task 6: Write Tests
  - [ ] 6.1: Unit test for DebugLogEntry validation
  - [ ] 6.2: Unit test for query parameter parsing
  - [ ] 6.3: Integration test for POST /debug/logs batch insert
  - [ ] 6.4: Integration test for GET /debug/logs with filters
  - [ ] 6.5: Integration test for DELETE /debug/logs
  - [ ] 6.6: Integration test for GET /debug/logs/stats
  - [ ] 6.7: Test endpoints return 404 when DEBUG_LOGS_ENABLED=false

## Dev Notes

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

### API Request/Response Examples

**POST /api/v1/debug/logs**
```json
{
  "entries": [
    {
      "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
      "timestamp": "2025-12-05T10:30:00Z",
      "source": "ios",
      "level": "info",
      "event": "UPLOAD_REQUEST",
      "payload": { "capture_id": "abc123", "size_bytes": 1024000 },
      "device_id": "660e8400-e29b-41d4-a716-446655440001",
      "session_id": "770e8400-e29b-41d4-a716-446655440002"
    }
  ]
}
```

Response: `{ "inserted": 1 }`

**GET /api/v1/debug/logs?source=ios&level=error&limit=50**
```json
{
  "logs": [...],
  "count": 50,
  "has_more": true
}
```

**GET /api/v1/debug/logs/stats**
```json
{
  "total": 1234,
  "by_source": { "ios": 800, "backend": 400, "web": 34 },
  "by_level": { "debug": 500, "info": 600, "warn": 100, "error": 34 },
  "oldest": "2025-12-01T00:00:00Z",
  "newest": "2025-12-05T10:30:00Z"
}
```

### Config Defaults

| Variable | Default | Description |
|----------|---------|-------------|
| DEBUG_LOGS_ENABLED | true | Enable debug log endpoints |
| DEBUG_LOGS_TTL_DAYS | 7 | Auto-cleanup after N days |
| DEBUG_LOGS_MAX_BATCH | 100 | Max entries per POST request |

### Patterns to Follow

- Follow `routes/captures.rs` for endpoint structure and error handling
- Use `services/` pattern for business logic separation
- Use SQLx query macros for compile-time checked SQL
- Return `Result<Json<T>, ApiError>` from handlers
- Use tracing::info!/debug! for internal logging

### Security Notes

- Debug endpoints should only be enabled in development
- No authentication required (dev-only endpoints)
- Endpoints return 404 when disabled (not 403) to avoid leaking feature presence

## Dev Agent Record

### Context Reference

- Tech Spec: `docs/tech-spec.md` (Lines 399-424 for schema, 214-234 for endpoints)
- Architecture: `docs/architecture.md`
- Pattern Reference: `backend/src/routes/captures.rs`

### File List

(populated during implementation)

### Completion Notes

(populated during implementation)

---

_Story created for Debug Observability System (Quick-Flow)_
_Date: 2025-12-06_
_Parent: Debug Observability Epic_
