/**
 * useLocation Hook
 *
 * Handles GPS location capture for photo evidence.
 * Location is always optional - capture proceeds without it if permission denied.
 *
 * Features:
 * - Permission request via expo-location
 * - getCurrentPositionAsync with Balanced accuracy
 * - 2-second timeout to prevent capture delays
 * - 10-second staleness rejection for fresh location
 * - Graceful handling when permission denied
 *
 * @see Story 3.3 - GPS Metadata Collection
 */

import { useState, useCallback, useEffect } from 'react';
import * as Location from 'expo-location';
import type { CaptureLocation, LocationError, LocationErrorCode } from '@realitycam/shared';

/**
 * Location request timeout in milliseconds
 */
const LOCATION_TIMEOUT_MS = 2000;

/**
 * Maximum age for cached location in milliseconds (10 seconds)
 */
const MAX_LOCATION_AGE_MS = 10000;

/**
 * Permission status values
 */
type PermissionStatus = 'undetermined' | 'granted' | 'denied';

/**
 * useLocation hook return type
 */
export interface UseLocationReturn {
  /** Request location permission from the user */
  requestPermission: () => Promise<boolean>;
  /** Get current GPS location (returns null if unavailable) */
  getCurrentLocation: () => Promise<CaptureLocation | null>;
  /** Whether location permission is granted */
  hasPermission: boolean;
  /** Detailed permission status */
  permissionStatus: PermissionStatus;
  /** Location fetch in progress */
  isLoading: boolean;
  /** Error from last operation (informational only) */
  error: LocationError | null;
  /** Clear the last error */
  clearError: () => void;
}

/**
 * Map expo-location permission status to our PermissionStatus type
 */
function mapPermissionStatus(status: Location.PermissionStatus): PermissionStatus {
  switch (status) {
    case Location.PermissionStatus.GRANTED:
      return 'granted';
    case Location.PermissionStatus.DENIED:
      return 'denied';
    case Location.PermissionStatus.UNDETERMINED:
    default:
      return 'undetermined';
  }
}

/**
 * Round number to 6 decimal places (~11cm precision)
 */
function roundTo6Decimals(value: number): number {
  return Math.round(value * 1000000) / 1000000;
}

/**
 * Map expo-location result to CaptureLocation
 */
function mapToCaptureLocation(location: Location.LocationObject): CaptureLocation {
  return {
    latitude: roundTo6Decimals(location.coords.latitude),
    longitude: roundTo6Decimals(location.coords.longitude),
    altitude: location.coords.altitude !== null
      ? Math.round(location.coords.altitude * 100) / 100  // 2 decimal places for altitude
      : null,
    accuracy: Math.round(location.coords.accuracy ?? 0),
    timestamp: new Date(location.timestamp).toISOString(),
  };
}

/**
 * Create a LocationError from an error code
 */
function createLocationError(code: LocationErrorCode, message: string): LocationError {
  return { code, message };
}

/**
 * Hook for GPS location capture
 *
 * @example
 * ```tsx
 * function CaptureWithLocation() {
 *   const {
 *     requestPermission,
 *     getCurrentLocation,
 *     hasPermission,
 *     permissionStatus,
 *   } = useLocation();
 *
 *   useEffect(() => {
 *     // Request permission on mount
 *     requestPermission();
 *   }, []);
 *
 *   const handleCapture = async () => {
 *     const location = hasPermission ? await getCurrentLocation() : null;
 *     // location is CaptureLocation | null
 *   };
 * }
 * ```
 */
export function useLocation(): UseLocationReturn {
  const [permissionStatus, setPermissionStatus] = useState<PermissionStatus>('undetermined');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<LocationError | null>(null);

  // Derived state
  const hasPermission = permissionStatus === 'granted';

  /**
   * Check current permission status on mount
   */
  useEffect(() => {
    const checkPermission = async () => {
      try {
        const { status } = await Location.getForegroundPermissionsAsync();
        setPermissionStatus(mapPermissionStatus(status));
      } catch (err) {
        console.warn('[useLocation] Failed to check permission status:', err);
        // Don't set error - this is just an initial check
      }
    };

    checkPermission();
  }, []);

  /**
   * Clear error state
   */
  const clearError = useCallback(() => {
    setError(null);
  }, []);

  /**
   * Request location permission
   * @returns true if permission granted, false otherwise
   */
  const requestPermission = useCallback(async (): Promise<boolean> => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      const mappedStatus = mapPermissionStatus(status);
      setPermissionStatus(mappedStatus);

      if (mappedStatus === 'denied') {
        setError(createLocationError(
          'PERMISSION_DENIED',
          'Location permission denied. Photos will be captured without location data.'
        ));
      } else {
        setError(null);
      }

      console.log(`[useLocation] Permission request result: ${mappedStatus}`);
      return mappedStatus === 'granted';
    } catch (err) {
      console.error('[useLocation] Permission request failed:', err);
      setError(createLocationError(
        'UNKNOWN',
        'Failed to request location permission.'
      ));
      return false;
    }
  }, []);

  /**
   * Get current GPS location
   * @returns CaptureLocation if successful, null otherwise
   */
  const getCurrentLocation = useCallback(async (): Promise<CaptureLocation | null> => {
    // Early return if no permission
    if (!hasPermission) {
      console.log('[useLocation] No permission, returning null');
      return null;
    }

    setIsLoading(true);
    setError(null);

    try {
      // Create a timeout promise
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => {
          reject(new Error('TIMEOUT'));
        }, LOCATION_TIMEOUT_MS);
      });

      // Race location fetch against timeout
      const location = await Promise.race([
        Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        }),
        timeoutPromise,
      ]);

      // Check if location is stale (> 10 seconds old)
      const locationAge = Date.now() - location.timestamp;
      if (locationAge > MAX_LOCATION_AGE_MS) {
        console.log(`[useLocation] Location is stale (${locationAge}ms old), requesting fresh fix`);

        // Try to get a fresh location with a shorter timeout
        const freshTimeoutPromise = new Promise<never>((_, reject) => {
          setTimeout(() => {
            reject(new Error('FRESH_TIMEOUT'));
          }, LOCATION_TIMEOUT_MS);
        });

        try {
          const freshLocation = await Promise.race([
            Location.getCurrentPositionAsync({
              accuracy: Location.Accuracy.Balanced,
            }),
            freshTimeoutPromise,
          ]);

          const captureLocation = mapToCaptureLocation(freshLocation);
          console.log('[useLocation] Fresh location acquired:', {
            lat: captureLocation.latitude,
            lng: captureLocation.longitude,
            accuracy: captureLocation.accuracy,
          });
          setIsLoading(false);
          return captureLocation;
        } catch {
          // Fresh location failed, use the stale one with warning
          console.warn('[useLocation] Fresh location failed, using stale location');
          setError(createLocationError(
            'STALE_LOCATION',
            'Using cached location (may be less accurate).'
          ));
          const captureLocation = mapToCaptureLocation(location);
          setIsLoading(false);
          return captureLocation;
        }
      }

      const captureLocation = mapToCaptureLocation(location);
      console.log('[useLocation] Location acquired:', {
        lat: captureLocation.latitude,
        lng: captureLocation.longitude,
        accuracy: captureLocation.accuracy,
      });
      setIsLoading(false);
      return captureLocation;

    } catch (err) {
      setIsLoading(false);

      const errorMessage = err instanceof Error ? err.message : String(err);

      if (errorMessage === 'TIMEOUT' || errorMessage === 'FRESH_TIMEOUT') {
        console.warn('[useLocation] Location request timed out');
        setError(createLocationError(
          'TIMEOUT',
          'Location request timed out. Photo captured without location.'
        ));
        return null;
      }

      // Check for location services disabled
      if (errorMessage.toLowerCase().includes('unavailable') ||
          errorMessage.toLowerCase().includes('disabled')) {
        console.warn('[useLocation] Location services unavailable');
        setError(createLocationError(
          'UNAVAILABLE',
          'Location services are unavailable.'
        ));
        return null;
      }

      console.error('[useLocation] Location capture failed:', err);
      setError(createLocationError(
        'UNKNOWN',
        'Failed to get location.'
      ));
      return null;
    }
  }, [hasPermission]);

  return {
    requestPermission,
    getCurrentLocation,
    hasPermission,
    permissionStatus,
    isLoading,
    error,
    clearError,
  };
}
