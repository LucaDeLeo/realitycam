-- Migration: Add privacy mode fields (Story 8-4)
-- Enables hash-only captures where media is not uploaded to the server

-- Add privacy mode columns to captures table
ALTER TABLE captures
ADD COLUMN capture_mode TEXT NOT NULL DEFAULT 'full',
ADD COLUMN media_stored BOOLEAN NOT NULL DEFAULT TRUE,
ADD COLUMN analysis_source TEXT NOT NULL DEFAULT 'server',
ADD COLUMN metadata_flags JSONB;

-- Index for filtering by capture mode
CREATE INDEX idx_captures_mode ON captures(capture_mode);

-- Partial hash index for efficient hash-only lookups
-- Uses hash index for O(1) equality lookups on hash-only captures
CREATE INDEX idx_captures_hash_only_lookup ON captures USING hash(target_media_hash)
WHERE capture_mode = 'hash_only';

-- Add comments for documentation
COMMENT ON COLUMN captures.capture_mode IS 'Capture mode: full (with media upload) or hash_only (privacy mode)';
COMMENT ON COLUMN captures.media_stored IS 'Whether raw media files are stored on server (false for hash_only mode)';
COMMENT ON COLUMN captures.analysis_source IS 'Source of depth analysis: server (computed on backend) or device (client-provided)';
COMMENT ON COLUMN captures.metadata_flags IS 'JSON flags indicating which metadata fields were included per privacy settings';
