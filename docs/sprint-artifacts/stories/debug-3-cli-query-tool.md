# CLI Query Tool

**Story Key:** debug-3-cli-query-tool
**Epic:** Debug Observability System (Quick-Flow)
**Status:** complete

## Description

Create a CLI package (`packages/debug-cli/`) with three commands for querying and managing debug logs from the backend. The CLI enables developers to tail logs in real-time, search by correlation ID or event patterns, and clear old logs. Output is color-coded for readability with an optional `--json` flag for machine-readable output (Claude consumption).

## Acceptance Criteria

- [x] AC1: `bun debug:tail` displays recent logs in reverse chronological order with color-coded levels (red=error, yellow=warn, blue=info, gray=debug)
- [x] AC2: `bun debug:tail --source ios` filters logs to only iOS source; same for `--source backend` and `--source web`
- [x] AC3: `bun debug:tail --level error` filters to only error-level logs; supports all four levels
- [x] AC4: `bun debug:tail --follow` continuously polls backend every 2 seconds for new logs
- [x] AC5: `bun debug:tail -n 50` limits output to last 50 entries
- [x] AC6: `bun debug:search --correlation-id <uuid>` returns all logs matching that correlation ID across all sources
- [x] AC7: `bun debug:search --event <pattern>` returns logs where event field contains the pattern (case-insensitive substring match)
- [x] AC8: `bun debug:search --since "1 hour ago"` returns logs newer than the parsed time
- [x] AC9: `bun debug:search --json` outputs raw JSON array for machine consumption
- [x] AC10: `bun debug:clear` prompts for confirmation before deleting all logs
- [x] AC11: `bun debug:clear --older-than 1d` clears only logs older than 1 day; supports `h` (hours), `d` (days), `w` (weeks)
- [x] AC12: `bun debug:clear --source web` clears only logs from web source
- [x] AC13: `bun debug:clear --yes` skips confirmation prompt
- [x] AC14: All commands use `http://localhost:8080` by default with `--api-url` override option
- [x] AC15: Integration tests verify each command against mock API responses

## Tasks

- [x] Task 1: Create `packages/debug-cli/` directory with package.json (AC: 14)
  - [x] Add dependencies: commander ^11, chalk ^5
  - [x] Configure TypeScript with tsconfig.json
  - [x] Set up build script with Bun

- [x] Task 2: Create `src/lib/api.ts` - Backend API client (AC: 14)
  - [x] Implement `getDebugLogs(filters)` - GET /debug/logs with query params
  - [x] Implement `deleteDebugLogs(filters)` - DELETE /debug/logs
  - [x] Add configurable base URL via --api-url option
  - [x] Handle API errors gracefully with user-friendly messages

- [x] Task 3: Create `src/lib/formatters.ts` - Output formatting utilities (AC: 1, 9)
  - [x] Implement colorized log level display (red=error, yellow=warn, blue=info, gray=debug)
  - [x] Implement aligned column output for readability
  - [x] Implement JSON output mode (--json flag)
  - [x] Show correlation IDs prominently for copy-paste

- [x] Task 4: Implement `src/commands/tail.ts` (AC: 1-5)
  - [x] Parse --source, --level, -n, --follow options using commander
  - [x] Fetch logs from GET /debug/logs with appropriate filters
  - [x] Display with formatters; default descending order
  - [x] Implement --follow with 2-second polling interval
  - [x] Handle Ctrl+C gracefully to stop follow mode

- [x] Task 5: Implement `src/commands/search.ts` (AC: 6-9)
  - [x] Parse --correlation-id, --event, --since, --json options
  - [x] Parse human-readable time strings ("1 hour ago", "30 minutes ago", "2 days ago")
  - [x] Fetch logs with filters from GET /debug/logs
  - [x] Display with formatters or raw JSON based on --json flag

- [x] Task 6: Implement `src/commands/clear.ts` (AC: 10-13)
  - [x] Parse --older-than, --source, --yes options
  - [x] Parse duration strings (1d, 2h, 1w) to calculate timestamp
  - [x] Show confirmation prompt unless --yes provided
  - [x] Call DELETE /debug/logs with filters
  - [x] Display count of deleted logs

- [x] Task 7: Create `src/index.ts` - CLI entry point (AC: all)
  - [x] Register all three commands with commander
  - [x] Add global --api-url option
  - [x] Set up proper exit codes

- [x] Task 8: Add workspace scripts to root `package.json` (AC: all)
  - [x] Add "debug:tail": "bun run packages/debug-cli/src/index.ts tail"
  - [x] Add "debug:search": "bun run packages/debug-cli/src/index.ts search"
  - [x] Add "debug:clear": "bun run packages/debug-cli/src/index.ts clear"

- [x] Task 9: Write integration tests in `tests/` (AC: 15)
  - [x] Create mock API server or use msw for request interception
  - [x] Test tail command with various filter combinations
  - [x] Test search command with correlation ID, event pattern, time range
  - [x] Test clear command confirmation flow and --yes bypass

## Technical Details

### Package Structure

```
packages/debug-cli/
  package.json
  tsconfig.json
  src/
    index.ts          # CLI entry point, commander setup
    commands/
      tail.ts         # Live tail command
      search.ts       # Search command
      clear.ts        # Clear command
    lib/
      api.ts          # Backend API client
      formatters.ts   # Output formatting utilities
      time-parser.ts  # Human-readable time parsing
  tests/
    tail.test.ts
    search.test.ts
    clear.test.ts
```

### API Integration

**GET /debug/logs** query parameters:
- `correlation_id` - Filter by correlation ID (UUID)
- `source` - Filter by source (ios, backend, web)
- `level` - Filter by level (debug, info, warn, error)
- `event` - Filter by event type (substring match)
- `since` - ISO timestamp, logs after this time
- `limit` - Max results (default 100, max 1000)
- `order` - "asc" or "desc" (default "desc")

**DELETE /debug/logs** query parameters:
- `source` - Delete only specific source logs
- `before` - Delete logs older than timestamp

### Output Format Examples

**Colored output (default):**
```
2024-12-05T10:30:15Z  [ERROR]  ios      UPLOAD_FAILED    correlation: abc-123
2024-12-05T10:30:14Z  [INFO]   backend  CAPTURE_STORED   correlation: abc-123
2024-12-05T10:30:12Z  [DEBUG]  ios      UPLOAD_REQUEST   correlation: abc-123
```

**JSON output (--json):**
```json
[
  {"id": "...", "correlation_id": "abc-123", "timestamp": "...", "source": "ios", ...}
]
```

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| commander | ^11 | CLI argument parsing |
| chalk | ^5 | Terminal colors |

### Root package.json Scripts

```json
{
  "scripts": {
    "debug:tail": "bun run packages/debug-cli/src/index.ts tail",
    "debug:search": "bun run packages/debug-cli/src/index.ts search",
    "debug:clear": "bun run packages/debug-cli/src/index.ts clear"
  }
}
```

## Dev Notes

- Follow existing `apps/web/src/lib/api.ts` pattern for API client structure
- Use Bun's native test runner or Vitest for integration tests
- commander v11 supports ES modules; use named exports
- chalk v5 is ESM-only; ensure package.json has "type": "module"
- Time parsing should handle: "X minutes ago", "X hours ago", "X days ago", "Xm", "Xh", "Xd"
- Duration parsing for --older-than: "1d" = 1 day, "2h" = 2 hours, "1w" = 1 week

### Previous Story Context

Story debug-2-ios-debug-logger established:
- Backend endpoint POST /debug/logs for ingestion
- Log entry schema with correlation_id, source, level, event, payload
- This story queries the same endpoint via GET and DELETE methods

### Project Structure Notes

- New package at `packages/debug-cli/` follows monorepo conventions
- Scripts added to root package.json integrate with Bun workspace

### References

- [Source: docs/tech-spec.md#CLI Commands (lines 477-502)]
- [Source: docs/tech-spec.md#CLI Output Formatting (lines 680-687)]
- [Source: docs/tech-spec.md#Story 3: CLI Query Tool (lines 572-579)]
- [Source: docs/tech-spec.md#Dependencies - Web CLI (lines 311-315)]
- [Source: docs/tech-spec.md#Backend Debug Endpoints (lines 214-235)]

## Dev Agent Record

### Context Reference
`docs/sprint-artifacts/story-contexts/debug-3-cli-query-tool-context.xml`

### Agent Model Used
Claude claude-opus-4-5-20251101

### Debug Log References
N/A - CLI package implementation

### Completion Notes List
- Created CLI package using commander v11 and chalk v5 for CLI parsing and terminal colors
- API client follows same pattern as apps/web/src/lib/api.ts with timeout handling
- Time parser supports both shorthand (1h, 30m, 2d, 1w) and long format ("1 hour ago")
- Formatters use chalk for color-coded log levels per AC1 requirements
- Follow mode polls every 2 seconds with proper SIGINT/SIGTERM handling
- Tests use Bun's native test runner with mock fetch for API testing
- All commands support --api-url override and default to localhost:8080

### File List
- `/Users/luca/dev/realitycam/packages/debug-cli/package.json` - Package configuration
- `/Users/luca/dev/realitycam/packages/debug-cli/tsconfig.json` - TypeScript configuration
- `/Users/luca/dev/realitycam/packages/debug-cli/src/index.ts` - CLI entry point
- `/Users/luca/dev/realitycam/packages/debug-cli/src/lib/api.ts` - Backend API client
- `/Users/luca/dev/realitycam/packages/debug-cli/src/lib/formatters.ts` - Output formatters
- `/Users/luca/dev/realitycam/packages/debug-cli/src/lib/time-parser.ts` - Time parsing utilities
- `/Users/luca/dev/realitycam/packages/debug-cli/src/commands/tail.ts` - Tail command
- `/Users/luca/dev/realitycam/packages/debug-cli/src/commands/search.ts` - Search command
- `/Users/luca/dev/realitycam/packages/debug-cli/src/commands/clear.ts` - Clear command
- `/Users/luca/dev/realitycam/packages/debug-cli/tests/api.test.ts` - API client tests
- `/Users/luca/dev/realitycam/packages/debug-cli/tests/formatters.test.ts` - Formatter tests
- `/Users/luca/dev/realitycam/packages/debug-cli/tests/time-parser.test.ts` - Time parser tests
- `/Users/luca/dev/realitycam/package.json` - Root package.json (modified - added debug:* scripts)
