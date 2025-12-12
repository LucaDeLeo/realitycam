/**
 * Device capability types for RealityCam
 * Used across mobile app and shared package
 */

/** Platform identifier for capture source */
export type Platform = 'ios' | 'android';

/** iOS attestation levels */
export type iOSAttestationLevel = 'secure_enclave' | 'unverified';

/** Android attestation levels (StrongBox > TEE > unverified) */
export type AndroidAttestationLevel = 'strongbox' | 'tee' | 'unverified';

/** Combined attestation level for display purposes */
export type AttestationLevel = iOSAttestationLevel | AndroidAttestationLevel;

/** Platform info extracted from evidence for display */
export interface PlatformInfo {
  /** Platform: "ios" or "android" */
  platform: Platform;
  /** Attestation level */
  attestation_level: AttestationLevel;
  /** Device model (if available) */
  device_model?: string;
  /** Whether LiDAR is available (iOS Pro only) */
  has_lidar?: boolean;
  /** Whether depth analysis is available */
  depth_available: boolean;
  /** Depth analysis method */
  depth_method?: 'lidar' | 'parallax' | null;
}

/**
 * Device capabilities detected on app launch
 * Used to determine if device supports RealityCam attestation features
 */
export interface DeviceCapabilities {
  /** Device model name (e.g., "iPhone 15 Pro", "iPhone 14 Pro Max") */
  model: string;
  /** iOS version string (e.g., "17.1", "16.4") */
  iosVersion: string;
  /** Whether device has LiDAR sensor (Pro models only) */
  hasLiDAR: boolean;
  /** Whether device has Secure Enclave (all modern iPhones) */
  hasSecureEnclave: boolean;
  /** Whether device supports DCAppAttest API (iOS 14.0+) */
  hasDCAppAttest: boolean;
  /** Aggregate check - true only if ALL requirements are met */
  isSupported: boolean;
  /** Reason device is not supported (if isSupported is false) */
  unsupportedReason?: string;
}

/**
 * Device registration state for Epic 2 Story 2.2+
 * Tracks device registration with backend
 */
export interface DeviceRegistrationState {
  deviceId: string | null;
  keyId: string | null;
  attestationLevel: 'secure_enclave' | 'unverified' | null;
  isRegistered: boolean;
  registrationError?: string;
}

/**
 * Key generation lifecycle states
 * Used to track Secure Enclave key generation progress
 *
 * State transitions:
 * - idle: Initial state, no key generation attempted yet
 * - checking: Checking SecureStore for existing key
 * - generating: Creating new key in Secure Enclave via generateKeyAsync()
 * - ready: Key is available (either found in storage or newly generated)
 * - failed: Key generation failed (device unsupported, jailbroken, etc.)
 */
export type KeyGenerationStatus =
  | 'idle'
  | 'checking'
  | 'generating'
  | 'ready'
  | 'failed';

/**
 * Attestation lifecycle states
 * Used to track DCAppAttest attestation progress
 *
 * State transitions:
 * - idle: Initial state, attestation not started
 * - fetching_challenge: Requesting challenge from backend
 * - attesting: Calling attestKeyAsync with challenge
 * - attested: Successfully completed DCAppAttest attestation
 * - failed: Attestation failed (may retry or continue unverified)
 */
export type AttestationStatus =
  | 'idle'
  | 'fetching_challenge'
  | 'attesting'
  | 'attested'
  | 'failed';

/**
 * Challenge response from backend GET /api/v1/devices/challenge
 * Used for DCAppAttest attestation
 */
export interface ChallengeResponse {
  data: {
    /** Base64-encoded 32-byte challenge nonce */
    challenge: string;
    /** ISO timestamp when challenge expires (5 minutes from creation) */
    expires_at: string;
  };
  meta: {
    /** Unique request identifier for tracing */
    request_id: string;
    /** ISO timestamp of response */
    timestamp: string;
  };
}
