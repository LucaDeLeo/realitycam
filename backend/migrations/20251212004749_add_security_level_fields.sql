-- Migration: Add security level fields to devices table
-- Story: 10-2-attestation-security-level-extraction
-- Purpose: Track hardware security level for Android (StrongBox/TEE) and iOS (Secure Enclave) devices

-- Add security_level column for primary hardware security indicator
-- Values: "strongbox" (Android HSM), "tee" (Android TEE), "secure_enclave" (iOS)
-- NULL for unverified devices (backward compatibility)
ALTER TABLE devices
ADD COLUMN IF NOT EXISTS security_level TEXT;

-- Add keymaster_security_level column for Android-specific KeyMaster security level
-- May differ from attestation level in some Android devices
-- NULL for iOS devices and unverified devices
ALTER TABLE devices
ADD COLUMN IF NOT EXISTS keymaster_security_level TEXT;

-- Add column comments for documentation
COMMENT ON COLUMN devices.security_level IS 'Hardware security level: strongbox (Android HSM), tee (Android TEE), secure_enclave (iOS). NULL for unverified devices.';
COMMENT ON COLUMN devices.keymaster_security_level IS 'Android KeyMaster security level (may differ from attestation level). NULL for iOS devices.';
