/**
 * useDeviceCapabilities Hook
 *
 * Detects device capabilities on mount and updates the device store.
 * Checks for iPhone Pro with LiDAR, Secure Enclave, and DCAppAttest support.
 */

import { useEffect, useRef } from 'react';
import * as Device from 'expo-device';
import type { DeviceCapabilities } from '@realitycam/shared';
import { useDeviceStore } from '../store/deviceStore';
import { checkLiDARAvailability } from '../utils/lidarDetection';

// Safe import of AppIntegrity module (handles Expo Go case)
let AppIntegrity: typeof import('@expo/app-integrity') | null = null;
try {
  AppIntegrity = require('@expo/app-integrity');
} catch {
  // Module not available - likely Expo Go
}

/**
 * Minimum iOS version required for DCAppAttest
 */
const MIN_IOS_VERSION = 14.0;

/**
 * Detects all device capabilities
 * Handles edge cases gracefully (simulator, missing APIs, etc.)
 */
async function detectCapabilities(): Promise<DeviceCapabilities> {
  try {
    // Get device model and OS version
    const model = Device.modelName ?? 'Unknown';
    const iosVersion = Device.osVersion ?? '0.0';
    const isPhysicalDevice = Device.isDevice;

    // Parse iOS version for comparison
    const iosVersionNumber = parseFloat(iosVersion) || 0;
    const hasMinimumIOSVersion = iosVersionNumber >= MIN_IOS_VERSION;

    // Check LiDAR availability via model string matching
    const hasLiDAR = checkLiDARAvailability(model);

    // Secure Enclave is present on all physical iOS devices since iPhone 5s
    // For MVP, we use isDevice as proxy (simulators don't have Secure Enclave)
    const hasSecureEnclave = isPhysicalDevice;

    // Check DCAppAttest support
    // AppIntegrity.isSupported is a boolean constant (not a function)
    // It indicates whether DCAppAttest service is available on this device
    let hasDCAppAttest = false;
    try {
      if (AppIntegrity && typeof AppIntegrity.isSupported !== 'undefined') {
        hasDCAppAttest = AppIntegrity.isSupported;
      }
    } catch (error) {
      // DCAppAttest check can fail on simulator or unsupported devices
      console.warn('DCAppAttest check failed, assuming false:', error);
      hasDCAppAttest = false;
    }

    // Compute aggregate support status
    const isSupported =
      hasMinimumIOSVersion &&
      hasLiDAR &&
      hasSecureEnclave &&
      hasDCAppAttest;

    // Determine unsupported reason (first failing check)
    let unsupportedReason: string | undefined;
    if (!isSupported) {
      if (!hasMinimumIOSVersion) {
        unsupportedReason = 'iOS 14.0 or later required';
      } else if (!hasLiDAR) {
        unsupportedReason = 'LiDAR sensor not detected - iPhone Pro required';
      } else if (!hasSecureEnclave) {
        unsupportedReason = 'Secure Enclave not available';
      } else if (!hasDCAppAttest) {
        unsupportedReason = 'Device attestation not supported';
      }
    }

    return {
      model,
      iosVersion,
      hasLiDAR,
      hasSecureEnclave,
      hasDCAppAttest,
      isSupported,
      unsupportedReason,
    };
  } catch (error) {
    // Fail safe - return unsupported on detection failure
    console.error('Device capability detection failed:', error);
    return {
      model: 'Unknown',
      iosVersion: '0.0',
      hasLiDAR: false,
      hasSecureEnclave: false,
      hasDCAppAttest: false,
      isSupported: false,
      unsupportedReason: 'Failed to detect device capabilities',
    };
  }
}

/**
 * Hook to detect device capabilities on mount
 *
 * Automatically detects capabilities when:
 * 1. No cached capabilities exist
 * 2. Hydration from AsyncStorage is complete
 *
 * Results are stored in deviceStore and persisted across sessions.
 *
 * @returns Object with capabilities, loading state, and hasHydrated flag
 *
 * @example
 * ```tsx
 * function App() {
 *   const { capabilities, isLoading, hasHydrated } = useDeviceCapabilities();
 *
 *   if (!hasHydrated || isLoading) return <LoadingScreen />;
 *   if (!capabilities?.isSupported) return <UnsupportedDeviceScreen />;
 *
 *   return <MainApp />;
 * }
 * ```
 */
export function useDeviceCapabilities() {
  const { capabilities, isLoading, hasHydrated, setCapabilities } =
    useDeviceStore();
  const detectionStarted = useRef(false);

  useEffect(() => {
    // Wait for hydration to complete
    if (!hasHydrated) {
      return;
    }

    // Skip if we already have capabilities or detection already started
    if (capabilities !== null || detectionStarted.current) {
      // If we have cached capabilities, ensure loading is false
      if (capabilities !== null && isLoading) {
        setCapabilities(capabilities);
      }
      return;
    }

    // Start detection
    detectionStarted.current = true;

    const performDetection = async () => {
      const detected = await detectCapabilities();
      setCapabilities(detected);
    };

    performDetection();
  }, [hasHydrated, capabilities, isLoading, setCapabilities]);

  return { capabilities, isLoading, hasHydrated };
}
