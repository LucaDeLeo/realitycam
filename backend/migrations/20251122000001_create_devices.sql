-- Migration: Create devices table
-- Description: Creates the devices table for storing device registration and attestation data
-- Table tracks iPhone devices that have registered with the system and their attestation status

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

-- Index for fast lookup by attestation key during device authentication
CREATE INDEX idx_devices_attestation_key ON devices(attestation_key_id);

COMMENT ON TABLE devices IS 'Registered devices with their attestation status and hardware capabilities';
COMMENT ON COLUMN devices.attestation_level IS 'Device attestation status: unverified, basic, or full';
COMMENT ON COLUMN devices.attestation_key_id IS 'Unique identifier from DeviceCheck App Attest';
COMMENT ON COLUMN devices.attestation_chain IS 'X.509 certificate chain from attestation';
COMMENT ON COLUMN devices.has_lidar IS 'Whether device has LiDAR sensor capability';
