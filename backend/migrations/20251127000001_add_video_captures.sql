-- Story 7-8: Add video capture support to captures table
-- Extends the captures table with video-specific columns while maintaining
-- backward compatibility with existing photo captures.

-- Add capture type discriminator (default 'photo' for existing records)
ALTER TABLE captures ADD COLUMN IF NOT EXISTS capture_type VARCHAR(16) DEFAULT 'photo' NOT NULL;

-- Add video-specific S3 storage keys
ALTER TABLE captures ADD COLUMN IF NOT EXISTS video_s3_key VARCHAR(255);
ALTER TABLE captures ADD COLUMN IF NOT EXISTS hash_chain_s3_key VARCHAR(255);

-- Add video metadata fields
ALTER TABLE captures ADD COLUMN IF NOT EXISTS duration_ms BIGINT;
ALTER TABLE captures ADD COLUMN IF NOT EXISTS frame_count INTEGER;
ALTER TABLE captures ADD COLUMN IF NOT EXISTS is_partial BOOLEAN DEFAULT FALSE;
ALTER TABLE captures ADD COLUMN IF NOT EXISTS checkpoint_index INTEGER;

-- Create index on capture_type for filtering queries
CREATE INDEX IF NOT EXISTS idx_captures_type ON captures(capture_type);

-- Create index on device_id + capture_type + uploaded_at for rate limiting queries
CREATE INDEX IF NOT EXISTS idx_captures_device_video_rate_limit
ON captures(device_id, capture_type, uploaded_at)
WHERE capture_type = 'video';

-- Add comment explaining the capture_type values
COMMENT ON COLUMN captures.capture_type IS 'Type of capture: photo (default) or video';
COMMENT ON COLUMN captures.video_s3_key IS 'S3 key for video file (video captures only)';
COMMENT ON COLUMN captures.hash_chain_s3_key IS 'S3 key for hash chain JSON (video captures only)';
COMMENT ON COLUMN captures.duration_ms IS 'Video duration in milliseconds (video captures only)';
COMMENT ON COLUMN captures.frame_count IS 'Total video frames captured (video captures only)';
COMMENT ON COLUMN captures.is_partial IS 'True if recording was interrupted (video captures only)';
COMMENT ON COLUMN captures.checkpoint_index IS 'Latest checkpoint index verified (video captures only)';
