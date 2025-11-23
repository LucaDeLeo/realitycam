-- Migration: Add S3 storage fields to captures table (Story 4.1)
-- Description: Adds separate fields for photo and depth map S3 keys,
--              thumbnail support, and location data storage

-- Add photo S3 key (required for new captures)
ALTER TABLE captures ADD COLUMN photo_s3_key TEXT;

-- Add depth_map_s3_key (replacing the old depth_map_key column)
ALTER TABLE captures ADD COLUMN depth_map_s3_key TEXT;

-- Add thumbnail S3 key (optional, generated later)
ALTER TABLE captures ADD COLUMN thumbnail_s3_key TEXT;

-- Add location fields
ALTER TABLE captures ADD COLUMN location_precise JSONB;
ALTER TABLE captures ADD COLUMN location_coarse TEXT;

-- Migrate existing depth_map_key values to depth_map_s3_key
UPDATE captures SET depth_map_s3_key = depth_map_key WHERE depth_map_key IS NOT NULL;

-- Note: We keep depth_map_key for backward compatibility during migration
-- A future migration can drop it once all code is updated

-- Add comments for new columns
COMMENT ON COLUMN captures.photo_s3_key IS 'S3 object key for stored photo (captures/{id}/photo.jpg)';
COMMENT ON COLUMN captures.depth_map_s3_key IS 'S3 object key for stored depth map (captures/{id}/depth.gz)';
COMMENT ON COLUMN captures.thumbnail_s3_key IS 'S3 object key for generated thumbnail';
COMMENT ON COLUMN captures.location_precise IS 'JSONB containing precise GPS coordinates {latitude, longitude, altitude, accuracy}';
COMMENT ON COLUMN captures.location_coarse IS 'Coarse location (city/region) for privacy-preserving display';
