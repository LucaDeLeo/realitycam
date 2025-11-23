-- Migration: Create captures table
-- Description: Creates the captures table for storing photo captures and their verification evidence
-- Each capture is linked to a device and contains hash, depth map, and evidence data

CREATE TABLE captures (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id           UUID NOT NULL REFERENCES devices(id),
    target_media_hash   BYTEA NOT NULL UNIQUE,
    depth_map_key       TEXT,
    evidence            JSONB NOT NULL DEFAULT '{}',
    confidence_level    TEXT NOT NULL DEFAULT 'low',
    status              TEXT NOT NULL DEFAULT 'pending',
    captured_at         TIMESTAMPTZ NOT NULL,
    uploaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Hash index for O(1) exact match lookups during file verification
CREATE INDEX idx_captures_hash ON captures USING hash(target_media_hash);

-- B-tree index for device lookup and foreign key joins
CREATE INDEX idx_captures_device ON captures(device_id);

-- B-tree index for filtering captures by processing status
CREATE INDEX idx_captures_status ON captures(status);

COMMENT ON TABLE captures IS 'Photo captures with verification evidence and confidence scores';
COMMENT ON COLUMN captures.target_media_hash IS 'SHA-256 hash of the original media file';
COMMENT ON COLUMN captures.depth_map_key IS 'S3 object key for stored LiDAR depth map';
COMMENT ON COLUMN captures.evidence IS 'JSONB containing verification evidence (attestation, depth, metadata checks)';
COMMENT ON COLUMN captures.confidence_level IS 'Computed confidence: low, medium, high, or verified';
COMMENT ON COLUMN captures.status IS 'Processing status: pending, processing, completed, failed';
