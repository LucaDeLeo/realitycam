-- Migration: Add attestation verification fields to devices table
-- Story: 2-5-dcappattest-verification-backend
-- Purpose: Support storing extracted public key and assertion counter for verified devices

-- Add assertion_counter column for replay protection (AC-8)
-- Starts at 0 for initial attestation, incremented with each assertion
ALTER TABLE devices
ADD COLUMN IF NOT EXISTS assertion_counter BIGINT NOT NULL DEFAULT 0;

-- Add public_key column for storing extracted COSE public key (AC-7)
-- Stored as uncompressed EC point: 0x04 || x (32 bytes) || y (32 bytes) = 65 bytes
-- NULL for unverified devices, populated on successful verification
ALTER TABLE devices
ADD COLUMN IF NOT EXISTS public_key BYTEA;

-- Add index on assertion_counter for efficient lookups during assertion verification
CREATE INDEX IF NOT EXISTS idx_devices_assertion_counter ON devices (attestation_key_id, assertion_counter);

-- Comment documenting the columns
COMMENT ON COLUMN devices.assertion_counter IS 'Counter for replay protection in assertion verification. Must be strictly increasing.';
COMMENT ON COLUMN devices.public_key IS 'ECDSA P-256 public key extracted from attestation. Uncompressed format (65 bytes).';
