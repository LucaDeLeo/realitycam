-- Migration: Create verification_logs table
-- Description: Creates the verification_logs table for tracking verification requests
-- Logs all verification actions for audit trail and analytics

CREATE TABLE verification_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capture_id  UUID REFERENCES captures(id),
    action      TEXT NOT NULL,
    client_ip   INET,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- B-tree index for looking up verification history by capture
CREATE INDEX idx_verification_logs_capture ON verification_logs(capture_id);

COMMENT ON TABLE verification_logs IS 'Audit log of all verification requests and actions';
COMMENT ON COLUMN verification_logs.capture_id IS 'Associated capture (nullable for non-capture actions)';
COMMENT ON COLUMN verification_logs.action IS 'Action type: verify, upload, check, etc.';
COMMENT ON COLUMN verification_logs.client_ip IS 'IP address of the requesting client';
