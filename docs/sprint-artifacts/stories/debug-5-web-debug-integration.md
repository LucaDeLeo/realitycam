# Web Debug Integration

**Story Key:** debug-5-web-debug-integration
**Epic:** Debug Observability System (Quick-Flow)
**Status:** ready-for-review

## Description

Create a debug logging utility for the Next.js web app that sends structured logs to the backend debug endpoint. The logger captures page loads, API requests/responses, and errors with correlation IDs for cross-stack tracing. Unlike iOS (which batches logs), web logs are sent immediately via POST to `/debug/logs`. The logger is only active in development mode (`process.env.NODE_ENV === 'development'`).

## Acceptance Criteria

- [x] AC1: `debug-logger.ts` exports functions to log events with structured payloads to the backend `/debug/logs` endpoint
- [x] AC2: `generateCorrelationId()` creates UUID v4 correlation IDs for linking related logs across web and backend
- [x] AC3: API requests in `api.ts` include `X-Correlation-ID` header and log `API_REQUEST`, `API_RESPONSE`, and `API_ERROR` events
- [x] AC4: `PAGE_LOAD` events are logged on initial page load with path, referrer, and timestamp
- [x] AC5: All debug logging code is gated by `process.env.NODE_ENV === 'development'` for zero production impact
- [x] AC6: Logs are sent immediately (not batched) with fire-and-forget semantics (errors silently ignored)

## Tasks

- [x] Task 1: Create `/apps/web/src/lib/debug-logger.ts` with core logging interface and `logDebugEvent()` function
- [x] Task 2: Implement `generateCorrelationId()` utility returning UUID v4 strings
- [x] Task 3: Implement `DebugLogEntry` interface matching the backend schema (correlation_id, timestamp, source: "web", level, event, payload)
- [x] Task 4: Implement `logPageLoad(path: string, referrer?: string)` for page load tracking
- [x] Task 5: Implement `logApiRequest(url: string, method: string, correlationId: string)` for outgoing API calls
- [x] Task 6: Implement `logApiResponse(url: string, status: number, durationMs: number, correlationId: string)` for successful responses
- [x] Task 7: Implement `logApiError(url: string, error: Error, correlationId: string)` for failed requests
- [x] Task 8: Modify `ApiClient` methods in `/apps/web/src/lib/api.ts` to generate correlation IDs, add `X-Correlation-ID` header, and call debug logger functions
- [x] Task 9: Initialize debug logger in `/apps/web/src/app/layout.tsx` with client component that logs `PAGE_LOAD` on mount (dev only)
- [ ] Task 10: Test in development mode: verify logs appear in backend via `bun debug:search --source web`

## Technical Details

### DebugLogEntry Interface

```typescript
interface DebugLogEntry {
  id?: string;                    // Optional - backend generates if not provided
  correlation_id: string;         // UUID linking related events
  timestamp: string;              // ISO 8601 timestamp
  source: 'web';                  // Always 'web' for this logger
  level: 'debug' | 'info' | 'warn' | 'error';
  event: string;                  // e.g., 'PAGE_LOAD', 'API_REQUEST'
  payload: Record<string, unknown>;  // Event-specific data
  session_id?: string;            // Optional browser session ID
}
```

### Debug Logger Implementation

```typescript
// /apps/web/src/lib/debug-logger.ts

const DEBUG_ENDPOINT = `${process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080'}/debug/logs`;

export function generateCorrelationId(): string {
  return crypto.randomUUID();
}

export async function logDebugEvent(
  event: string,
  level: 'debug' | 'info' | 'warn' | 'error',
  payload: Record<string, unknown>,
  correlationId?: string
): Promise<void> {
  // Only log in development
  if (process.env.NODE_ENV !== 'development') return;

  const entry: DebugLogEntry = {
    correlation_id: correlationId ?? generateCorrelationId(),
    timestamp: new Date().toISOString(),
    source: 'web',
    level,
    event,
    payload,
  };

  // Fire and forget - don't await, don't throw
  fetch(DEBUG_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ entries: [entry] }),
  }).catch(() => {
    // Silently ignore errors - debug logging should never break the app
  });
}

export function logPageLoad(path: string, referrer?: string): void {
  logDebugEvent('PAGE_LOAD', 'info', {
    path,
    referrer: referrer ?? null,
    user_agent: typeof navigator !== 'undefined' ? navigator.userAgent : null,
    timestamp: new Date().toISOString(),
  });
}

export function logApiRequest(
  url: string,
  method: string,
  correlationId: string
): void {
  logDebugEvent('API_REQUEST', 'info', {
    url,
    method,
    correlation_id: correlationId,
  }, correlationId);
}

export function logApiResponse(
  url: string,
  status: number,
  durationMs: number,
  correlationId: string
): void {
  logDebugEvent('API_RESPONSE', 'info', {
    url,
    status,
    duration_ms: durationMs,
    correlation_id: correlationId,
  }, correlationId);
}

export function logApiError(
  url: string,
  error: string,
  correlationId: string
): void {
  logDebugEvent('API_ERROR', 'error', {
    url,
    error,
    correlation_id: correlationId,
  }, correlationId);
}
```

### API Client Integration

Modify `ApiClient` methods to include correlation IDs and debug logging:

```typescript
// In api.ts - example modification for getCapture method
async getCapture(id: string): Promise<CaptureResponse | null> {
  const correlationId = generateCorrelationId();
  const startTime = Date.now();
  const url = `${this.baseUrl}/api/v1/captures/${id}`;

  // Log request (dev only - function handles the check)
  logApiRequest(url, 'GET', correlationId);

  const { controller, timeoutId } = createTimeoutController();
  try {
    const response = await fetch(url, {
      cache: 'no-store',
      signal: controller.signal,
      headers: {
        'X-Correlation-ID': correlationId,
      },
    });

    clearTimeout(timeoutId);
    const durationMs = Date.now() - startTime;

    // Log response
    logApiResponse(url, response.status, durationMs, correlationId);

    if (!response.ok) {
      if (response.status === 404) return null;
      throw new Error(`API error: ${response.status}`);
    }

    return response.json();
  } catch (error) {
    clearTimeout(timeoutId);
    const errorMsg = error instanceof Error ? error.message : 'Unknown error';
    logApiError(url, errorMsg, correlationId);
    // ... rest of error handling
  }
}
```

### Layout Initialization

Create a client component for page load logging:

```typescript
// /apps/web/src/components/DebugInitializer.tsx
'use client';

import { useEffect } from 'react';
import { logPageLoad } from '@/lib/debug-logger';

export function DebugInitializer() {
  useEffect(() => {
    if (process.env.NODE_ENV === 'development') {
      logPageLoad(window.location.pathname, document.referrer || undefined);
    }
  }, []);

  return null;
}
```

Then import in layout.tsx:

```typescript
// In layout.tsx
import { DebugInitializer } from '@/components/DebugInitializer';

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>
        {process.env.NODE_ENV === 'development' && <DebugInitializer />}
        {children}
      </body>
    </html>
  );
}
```

### Events Logged

| Event | Payload Fields | When Logged |
|-------|----------------|-------------|
| `PAGE_LOAD` | path, referrer, user_agent, timestamp | Initial page mount |
| `API_REQUEST` | url, method, correlation_id | Before fetch call |
| `API_RESPONSE` | url, status, duration_ms, correlation_id | After successful response |
| `API_ERROR` | url, error, correlation_id | On fetch failure or timeout |

### File Locations

**Create:**
- `/apps/web/src/lib/debug-logger.ts` - Debug logging utility
- `/apps/web/src/components/DebugInitializer.tsx` - Client component for page load logging (optional)

**Modify:**
- `/apps/web/src/lib/api.ts` - Add correlation ID headers and debug logging calls
- `/apps/web/src/app/layout.tsx` - Initialize debug logger (dev only)

### Integration with Existing Code

- **Backend Debug Endpoints** (story 1): POST to `/debug/logs` with `{ entries: [...] }` format
- **CLI Query Tool** (story 3): Query with `bun debug:search --source web`
- **Correlation ID**: Same header (`X-Correlation-ID`) used by iOS for cross-stack tracing

## Dev Agent Record

### Context Reference
`docs/sprint-artifacts/story-contexts/debug-5-web-debug-integration-context.xml`

### File List
**Created:**
- `apps/web/src/lib/debug-logger.ts` - Debug logging utility with postLog, generateCorrelationId, logPageLoad, logApiRequest, logApiResponse, logApiError
- `apps/web/src/components/DebugInitializer.tsx` - Client component for PAGE_LOAD logging on mount

**Modified:**
- `apps/web/src/lib/api.ts` - Added debug logging imports, correlation ID generation, X-Correlation-ID headers, and API event logging to getCapture, getCapturePublic, verifyFile methods
- `apps/web/src/app/layout.tsx` - Added DebugInitializer component (dev mode only)

### Completion Notes
Implementation follows the story spec with a few minor refinements:
- `logApiError` accepts an `Error` object instead of string for richer error info (captures name + message)
- Added `isDebugEnabled()` as exported function for consistency
- DebugInitializer uses `usePathname()` from next/navigation instead of `window.location.pathname` for better Next.js integration
- Session ID is generated once per page session and included in all log entries
- All logging functions check `isDebugEnabled()` to ensure zero production impact

## Source References

- Tech Spec: Section "Story 5: Web Debug Integration" (lines 587-593)
- Tech Spec: Log Entry Schema (lines 180-193)
- Tech Spec: Web Debug Integration description (lines 264-266)
- Tech Spec: Source Tree Changes - Web (lines 156-160)
- Existing Code: `/apps/web/src/lib/api.ts` - API client pattern to follow
- Existing Code: `/apps/web/src/app/layout.tsx` - Root layout for initialization
