-- PostgreSQL initialization script for RealityCam
-- Creates required extensions

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pg_crypto for hashing functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Grant permissions to app user
GRANT ALL PRIVILEGES ON DATABASE realitycam_dev TO realitycam;
