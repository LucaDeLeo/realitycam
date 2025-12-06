/**
 * Debug Logger for Web App
 *
 * Provides structured logging to backend /debug/logs endpoint.
 * Only active in development mode (NODE_ENV === 'development').
 * Uses fire-and-forget semantics - never blocks app functionality.
 */

// ============================================================================
// Types
// ============================================================================

export interface DebugLogEntry {
  id?: string;
  correlation_id: string;
  timestamp: string;
  source: 'ios' | 'backend' | 'web';
  level: 'debug' | 'info' | 'warn' | 'error';
  event: string;
  payload: Record<string, unknown>;
  device_id?: string;
  session_id?: string;
}

type LogLevel = DebugLogEntry['level'];

// ============================================================================
// Configuration
// ============================================================================

const DEBUG_ENDPOINT = `${process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080'}/api/v1/debug/logs`;

/** Session ID generated once per page session */
let sessionId: string | null = null;

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Check if debug logging is enabled (development mode only)
 */
export function isDebugEnabled(): boolean {
  return process.env.NODE_ENV === 'development';
}

/**
 * Generate a UUID v4 correlation ID for linking related logs
 */
export function generateCorrelationId(): string {
  return crypto.randomUUID();
}

/**
 * Get or create session ID for the current browser session
 */
function getSessionId(): string {
  if (!sessionId) {
    sessionId = generateCorrelationId();
  }
  return sessionId;
}

// ============================================================================
// Core Logging Functions
// ============================================================================

/**
 * Post a log entry to the backend (fire-and-forget)
 * Does not await the response - errors are silently ignored.
 */
export function postLog(entry: Omit<DebugLogEntry, 'id'>): void {
  if (!isDebugEnabled()) return;

  // Fire and forget - don't await, silently ignore errors
  fetch(DEBUG_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ entries: [entry] }),
  }).catch(() => {
    // Silently ignore errors - debug logging should never break the app
  });
}

/**
 * Core logging function - creates structured log entry and sends to backend
 */
function logDebugEvent(
  event: string,
  level: LogLevel,
  payload: Record<string, unknown>,
  correlationId?: string
): void {
  if (!isDebugEnabled()) return;

  const entry: Omit<DebugLogEntry, 'id'> = {
    correlation_id: correlationId ?? generateCorrelationId(),
    timestamp: new Date().toISOString(),
    source: 'web',
    level,
    event,
    payload,
    session_id: getSessionId(),
  };

  postLog(entry);
}

// ============================================================================
// Event-Specific Logging Functions
// ============================================================================

/**
 * Log PAGE_LOAD event on initial page load
 */
export function logPageLoad(path: string, referrer?: string): void {
  logDebugEvent('PAGE_LOAD', 'info', {
    path,
    referrer: referrer ?? null,
    user_agent: typeof navigator !== 'undefined' ? navigator.userAgent : null,
    timestamp: new Date().toISOString(),
  });
}

/**
 * Log API_REQUEST event before fetch call
 */
export function logApiRequest(
  url: string,
  method: string,
  correlationId: string
): void {
  logDebugEvent(
    'API_REQUEST',
    'info',
    {
      url,
      method,
    },
    correlationId
  );
}

/**
 * Log API_RESPONSE event after successful response
 */
export function logApiResponse(
  url: string,
  status: number,
  durationMs: number,
  correlationId: string
): void {
  logDebugEvent(
    'API_RESPONSE',
    'info',
    {
      url,
      status,
      duration_ms: durationMs,
    },
    correlationId
  );
}

/**
 * Log API_ERROR event on fetch failure or timeout
 */
export function logApiError(
  url: string,
  error: Error,
  correlationId: string
): void {
  logDebugEvent(
    'API_ERROR',
    'error',
    {
      url,
      error: error.message,
      error_name: error.name,
    },
    correlationId
  );
}
