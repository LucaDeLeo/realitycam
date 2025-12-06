-- Migration: Create debug_logs table
-- Description: Creates the debug_logs table for storing cross-stack debug log entries
-- with correlation IDs for tracing requests across iOS, backend, and web layers.
-- SECURITY: This table should ONLY be populated when DEBUG_LOGS_ENABLED=true

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

-- Index for correlation ID lookups (tracing requests across layers)
CREATE INDEX idx_debug_logs_correlation ON debug_logs(correlation_id);

-- Index for time-based queries (most recent first)
CREATE INDEX idx_debug_logs_timestamp ON debug_logs(timestamp DESC);

-- Index for filtering by source (ios, backend, web)
CREATE INDEX idx_debug_logs_source ON debug_logs(source);

-- Index for filtering by event type
CREATE INDEX idx_debug_logs_event ON debug_logs(event);

-- Partial index for error-level logs (frequently queried)
CREATE INDEX idx_debug_logs_errors ON debug_logs(timestamp DESC) WHERE level = 'error';

COMMENT ON TABLE debug_logs IS 'Cross-stack debug log entries with correlation IDs for request tracing';
COMMENT ON COLUMN debug_logs.correlation_id IS 'UUID that traces a single request across iOS, backend, and web layers';
COMMENT ON COLUMN debug_logs.timestamp IS 'When the log event occurred (from source)';
COMMENT ON COLUMN debug_logs.source IS 'Origin of the log entry: ios, backend, or web';
COMMENT ON COLUMN debug_logs.level IS 'Log severity: debug, info, warn, or error';
COMMENT ON COLUMN debug_logs.event IS 'Event type identifier, e.g., UPLOAD_REQUEST, ATTESTATION_VERIFIED';
COMMENT ON COLUMN debug_logs.payload IS 'Structured event data as JSONB';
COMMENT ON COLUMN debug_logs.device_id IS 'iOS device identifier (DEBUG builds only)';
COMMENT ON COLUMN debug_logs.session_id IS 'App session ID for grouping related logs';
