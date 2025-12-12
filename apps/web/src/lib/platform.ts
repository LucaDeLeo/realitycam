/**
 * Platform utility functions for extracting and formatting platform information
 * from evidence data for display in the verification UI.
 *
 * Story 11-3: Platform Indicator Badge
 */

import type { Platform, AttestationLevel, PlatformInfo } from '@realitycam/shared';
import type { ExtendedEvidenceStatus } from '@/components/Evidence/EvidenceRow';

/**
 * Evidence structure from API response
 * Using a flexible interface to handle various evidence formats
 */
interface EvidenceData {
  platform?: Platform;
  hardware_attestation?: {
    status?: string;
    level?: string;
    device_model?: string;
    security_level?: {
      attestation_level?: string;
      platform?: string;
    };
  };
  depth_analysis?: {
    status?: string;
    method?: string;
    is_likely_real_scene?: boolean;
  };
  metadata?: {
    model_name?: string;
    device_model?: string;
  };
}

/**
 * Check if a device model indicates LiDAR capability
 * iPhone Pro models have LiDAR: iPhone 12 Pro+, iPhone 13 Pro+, iPhone 14 Pro+, iPhone 15 Pro+
 */
function hasLiDARCapability(deviceModel?: string): boolean {
  if (!deviceModel) return false;
  const model = deviceModel.toLowerCase();
  // Pro models have LiDAR (Pro, Pro Max)
  return model.includes('pro');
}

/**
 * Extract platform info from evidence data
 *
 * Handles:
 * - New format with platform field at top level
 * - Legacy format defaulting to iOS
 * - Android security_level.attestation_level
 * - iOS hardware_attestation.level
 *
 * @param evidence - Evidence data from API response
 * @returns Extracted platform info for display
 */
export function extractPlatformInfo(evidence: EvidenceData): PlatformInfo {
  // Default to iOS for backward compatibility (all MVP captures are iOS)
  const platform: Platform = evidence.platform ?? 'ios';

  // Extract device model from multiple possible locations
  const deviceModel =
    evidence.hardware_attestation?.device_model ||
    evidence.metadata?.model_name ||
    evidence.metadata?.device_model;

  // Extract attestation level based on platform
  let attestationLevel: AttestationLevel;

  if (platform === 'android') {
    // Android uses security_level.attestation_level
    const androidLevel = evidence.hardware_attestation?.security_level?.attestation_level;
    if (androidLevel === 'strongbox' || androidLevel === 'tee') {
      attestationLevel = androidLevel;
    } else {
      attestationLevel = 'unverified';
    }
  } else {
    // iOS uses hardware_attestation.level
    const iosLevel = evidence.hardware_attestation?.level;
    if (iosLevel === 'secure_enclave' || iosLevel === 'full') {
      attestationLevel = 'secure_enclave';
    } else {
      attestationLevel = 'unverified';
    }
  }

  // Determine depth availability and method
  const depthStatus = evidence.depth_analysis?.status;
  const hasLidar = platform === 'ios' && hasLiDARCapability(deviceModel);

  // Determine depth method
  let depthMethod: 'lidar' | 'parallax' | null = null;
  if (depthStatus === 'pass' || evidence.depth_analysis?.is_likely_real_scene) {
    if (platform === 'ios' && hasLidar) {
      depthMethod = 'lidar';
    } else if (platform === 'android') {
      depthMethod = 'parallax';
    } else {
      depthMethod = 'lidar'; // Default for iOS even without explicit LiDAR detection
    }
  }

  return {
    platform,
    attestation_level: attestationLevel,
    device_model: deviceModel,
    has_lidar: platform === 'ios' ? hasLidar : undefined,
    depth_available: depthStatus === 'pass' || Boolean(evidence.depth_analysis?.is_likely_real_scene),
    depth_method: depthMethod,
  };
}

/**
 * Evidence item for EvidencePanel integration
 */
export interface EvidenceItem {
  label: string;
  status: ExtendedEvidenceStatus;
  value?: string;
}

/**
 * Create a platform evidence item for the EvidencePanel items array
 *
 * @param platformInfo - Extracted platform info
 * @returns Evidence item compatible with EvidencePanel
 */
export function createPlatformEvidenceItem(platformInfo: PlatformInfo): EvidenceItem {
  const { platform, attestation_level, device_model, has_lidar } = platformInfo;

  // Map attestation level to evidence status
  let status: ExtendedEvidenceStatus;
  switch (attestation_level) {
    case 'secure_enclave':
    case 'strongbox':
      status = 'pass';
      break;
    case 'tee':
      status = 'pass'; // TEE is still hardware-backed, just lower trust
      break;
    case 'unverified':
    default:
      status = 'unavailable';
      break;
  }

  // Format the display value
  const platformName = platform === 'ios' ? 'iOS' : 'Android';
  const attestationLabel = formatAttestationLabel(attestation_level);
  let value = `${platformName} - ${attestationLabel}`;

  // Add device model and LiDAR info if available
  const extras: string[] = [];
  if (device_model) {
    extras.push(device_model);
  }
  if (platform === 'ios' && has_lidar) {
    extras.push('LiDAR available');
  }
  if (extras.length > 0) {
    value += ` (${extras.join(', ')})`;
  }

  return {
    label: 'Platform & Attestation',
    status,
    value,
  };
}

/**
 * Format attestation level for display
 */
function formatAttestationLabel(level: AttestationLevel): string {
  switch (level) {
    case 'secure_enclave':
      return 'Secure Enclave';
    case 'strongbox':
      return 'StrongBox';
    case 'tee':
      return 'TEE';
    case 'unverified':
    default:
      return 'Unverified';
  }
}
