-- Migration: Add detection_results column (Story 9-7)
-- Stores multi-signal detection data from iOS capture uploads
-- Enables JSONB queries for detection-based filtering and analysis

-- Add detection_results JSONB column to captures table
ALTER TABLE captures
ADD COLUMN detection_results JSONB;

-- GIN index for efficient JSONB queries on detection fields
-- Enables queries like: WHERE detection_results->'aggregated_confidence'->>'confidence_level' = 'high'
CREATE INDEX idx_captures_detection_results ON captures USING GIN(detection_results) WHERE detection_results IS NOT NULL;

-- Add documentation comments
COMMENT ON COLUMN captures.detection_results IS 'Multi-signal detection results from iOS client (moire, texture, artifacts, aggregated_confidence, cross_validation). JSON structure matches iOS DetectionResults payload. Null for captures without detection data (backward compatible).';
