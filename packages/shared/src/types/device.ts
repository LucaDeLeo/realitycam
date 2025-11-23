/**
 * Device capability types for RealityCam
 * Used across mobile app and shared package
 */

export type Platform = 'ios';

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
