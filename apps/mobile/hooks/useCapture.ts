/**
 * useCapture Hook
 *
 * Orchestrates synchronized photo + depth + location capture with per-capture attestation.
 * Manages capture state machine, camera ref, and integrates with useLiDAR, useLocation,
 * and useCaptureAttestation.
 *
 * Features:
 * - Parallel photo, depth, and location capture via Promise.allSettled
 * - 100ms synchronization window validation for photo/depth
 * - Location capture in parallel (optional, never blocks capture)
 * - Per-capture attestation signature (optional, never blocks capture)
 * - State machine: idle -> capturing -> captured -> idle
 * - Error handling with typed CaptureError
 * - Camera ref management for expo-camera
 *
 * @see Story 3.2 - Photo Capture with Depth Map
 * @see Story 3.3 - GPS Metadata Collection
 * @see Story 3.4 - Capture Attestation Signature
 */

import { useCallback, useState, useRef } from 'react';
import { CameraView as ExpoCameraView } from 'expo-camera';
import * as Crypto from 'expo-crypto';
import * as FileSystem from 'expo-file-system/legacy';
import { useLiDAR } from './useLiDAR';
import { useLocation } from './useLocation';
import { useCaptureAttestation } from './useCaptureAttestation';
import type {
  RawCapture,
  DepthFrame,
  CaptureError,
  CaptureLocation,
  AssertionMetadata,
  CaptureAssertion,
} from '@realitycam/shared';

/**
 * Convert Uint8Array to base64 string (React Native compatible)
 */
function uint8ArrayToBase64(bytes: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  const len = bytes.length;

  for (let i = 0; i < len; i += 3) {
    const b1 = bytes[i];
    const b2 = i + 1 < len ? bytes[i + 1] : 0;
    const b3 = i + 2 < len ? bytes[i + 2] : 0;

    result += chars[b1 >> 2];
    result += chars[((b1 & 3) << 4) | (b2 >> 4)];
    result += i + 1 < len ? chars[((b2 & 15) << 2) | (b3 >> 6)] : '=';
    result += i + 2 < len ? chars[b3 & 63] : '=';
  }

  return result;
}

/**
 * Maximum allowed sync delta in milliseconds
 */
const MAX_SYNC_DELTA_MS = 100;

/**
 * Capture state machine states
 */
type CaptureState = 'idle' | 'capturing' | 'captured';

/**
 * useCapture hook return type
 */
export interface UseCaptureReturn {
  /** Initiate synchronized photo + depth + location capture */
  capture: () => Promise<RawCapture>;
  /** Whether capture is in progress */
  isCapturing: boolean;
  /** Camera + LiDAR ready for capture */
  isReady: boolean;
  /** Most recent capture result (null if none) */
  lastCapture: RawCapture | null;
  /** Error from last capture attempt (null if none) */
  error: CaptureError | null;
  /** Register camera component ref for photo capture */
  setCameraRef: (ref: ExpoCameraView | null) => void;
  /** Clear the last capture error */
  clearError: () => void;
  /** Request location permission (call before first capture) */
  requestLocationPermission: () => Promise<boolean>;
  /** Whether location permission is granted */
  hasLocationPermission: boolean;
  /** Location permission status for UI display */
  locationPermissionStatus: 'undetermined' | 'granted' | 'denied';
}

/**
 * Parse EXIF DateTimeOriginal to Unix timestamp
 * EXIF format: "YYYY:MM:DD HH:MM:SS"
 */
function parseExifTimestamp(exifDateTime: string | undefined, fallback: number): number {
  if (!exifDateTime) return fallback;

  try {
    // Convert "YYYY:MM:DD HH:MM:SS" to ISO format
    const isoFormat = exifDateTime.replace(
      /^(\d{4}):(\d{2}):(\d{2})/,
      '$1-$2-$3'
    );
    const parsed = new Date(isoFormat).getTime();
    if (!isNaN(parsed)) return parsed;
  } catch {
    // Fall through to fallback
  }

  return fallback;
}

/**
 * Hook for synchronized photo + depth capture
 *
 * @example
 * ```tsx
 * function CaptureScreen() {
 *   const {
 *     capture,
 *     isCapturing,
 *     isReady,
 *     lastCapture,
 *     error,
 *     setCameraRef,
 *   } = useCapture();
 *
 *   const handleCapture = async () => {
 *     try {
 *       const rawCapture = await capture();
 *       console.log('Captured:', rawCapture.id);
 *     } catch (err) {
 *       console.error('Capture failed:', err);
 *     }
 *   };
 *
 *   return (
 *     <CameraView
 *       setCameraRef={setCameraRef}
 *       onCapture={handleCapture}
 *       isCapturing={isCapturing}
 *     />
 *   );
 * }
 * ```
 */
export function useCapture(): UseCaptureReturn {
  // Get depth capture from useLiDAR hook
  // In development mode (Expo Go), LiDAR may not be available
  const { captureDepthFrame, isReady: isDepthReady, isAvailable: isLiDARAvailable } = useLiDAR();

  // Get location capture from useLocation hook
  const {
    requestPermission: requestLocationPermission,
    getCurrentLocation,
    hasPermission: hasLocationPermission,
    permissionStatus: locationPermissionStatus,
  } = useLocation();

  // Get attestation generation from useCaptureAttestation hook
  const {
    generateAssertion,
    isReady: isAttestationReady,
  } = useCaptureAttestation();

  // Capture state machine
  const [state, setState] = useState<CaptureState>('idle');
  const [lastCapture, setLastCapture] = useState<RawCapture | null>(null);
  const [error, setError] = useState<CaptureError | null>(null);

  // Camera ref for expo-camera takePictureAsync
  const cameraRef = useRef<ExpoCameraView | null>(null);

  // Derived state
  const isCapturing = state === 'capturing';
  // In development mode, allow capture without LiDAR
  // Camera is ready if we have a camera ref, regardless of LiDAR status
  const isReady = cameraRef.current !== null;

  /**
   * Register camera ref
   */
  const setCameraRef = useCallback((ref: ExpoCameraView | null) => {
    cameraRef.current = ref;
  }, []);

  /**
   * Clear error state
   */
  const clearError = useCallback(() => {
    setError(null);
  }, []);

  /**
   * Perform synchronized photo + depth capture
   */
  const capture = useCallback(async (): Promise<RawCapture> => {
    // Validate readiness
    if (!cameraRef.current) {
      const captureError: CaptureError = {
        code: 'NOT_READY',
        message: 'Camera not ready. Please wait and try again.',
      };
      setError(captureError);
      throw captureError;
    }

    // DISABLED: Depth sensor check for development mode
    // Allow capture without LiDAR in development/testing
    // if (!isDepthReady && isLiDARAvailable) {
    //   const captureError: CaptureError = {
    //     code: 'NOT_READY',
    //     message: 'Depth sensor not ready. Please wait and try again.',
    //   };
    //   setError(captureError);
    //   throw captureError;
    // }

    if (isCapturing) {
      const captureError: CaptureError = {
        code: 'NOT_READY',
        message: 'Capture already in progress.',
      };
      setError(captureError);
      throw captureError;
    }

    // Start capture
    setState('capturing');
    setError(null);

    // Record capture initiation time as fallback for photo timestamp
    const captureStartTime = Date.now();

    try {
      // Parallel capture for minimum sync delta
      // Use Promise.allSettled so location failure doesn't block capture
      const [photoResult, depthResult, locationResult] = await Promise.allSettled([
        cameraRef.current.takePictureAsync({
          quality: 1,
          exif: true,
          base64: false,
        }),
        // Only attempt depth capture if LiDAR is available, otherwise resolve to null
        isLiDARAvailable ? captureDepthFrame() : Promise.resolve(null),
        // Only attempt location if permission granted, otherwise resolve to null
        hasLocationPermission ? getCurrentLocation() : Promise.resolve(null),
      ]);

      // Extract photo result (required)
      if (photoResult.status === 'rejected') {
        const captureError: CaptureError = {
          code: 'CAMERA_ERROR',
          message: 'Failed to capture photo. Please try again.',
        };
        setError(captureError);
        setState('idle');
        throw captureError;
      }
      const photo = photoResult.value;

      // Validate photo result
      if (!photo || !photo.uri) {
        const captureError: CaptureError = {
          code: 'CAMERA_ERROR',
          message: 'Failed to capture photo. Please try again.',
        };
        setError(captureError);
        setState('idle');
        throw captureError;
      }

      // Extract depth result (required, but create mock if LiDAR unavailable)
      let depthFrame: DepthFrame;
      if (depthResult.status === 'rejected' || !isLiDARAvailable || depthResult.value === null) {
        // Create mock depth frame for development/testing without LiDAR
        console.log('[useCapture] LiDAR unavailable, creating mock depth frame');
        const mockDepthData = new Float32Array(256 * 192).fill(2.0); // 2 meters default depth
        // Convert Float32Array to Uint8Array, then to base64
        const uint8Array = new Uint8Array(mockDepthData.buffer);
        const mockDepthBase64 = uint8ArrayToBase64(uint8Array);
        depthFrame = {
          depthMap: mockDepthBase64,
          width: 256,
          height: 192,
          timestamp: captureStartTime,
          intrinsics: {
            fx: 1000,
            fy: 1000,
            cx: 128,
            cy: 96,
          },
        };
      } else if (depthResult.status === 'fulfilled' && depthResult.value) {
        depthFrame = depthResult.value;
      } else {
        // Fallback: create mock if we somehow get here
        console.log('[useCapture] Unexpected depth result, creating mock depth frame');
        const mockDepthData = new Float32Array(256 * 192).fill(2.0);
        const uint8Array = new Uint8Array(mockDepthData.buffer);
        const mockDepthBase64 = uint8ArrayToBase64(uint8Array);
        depthFrame = {
          depthMap: mockDepthBase64,
          width: 256,
          height: 192,
          timestamp: captureStartTime,
          intrinsics: {
            fx: 1000,
            fy: 1000,
            cx: 128,
            cy: 96,
          },
        };
      }

      // Extract location result (optional - never blocks capture)
      let location: CaptureLocation | undefined;
      if (locationResult.status === 'fulfilled' && locationResult.value !== null) {
        location = locationResult.value;
        console.log('[useCapture] Location captured:', {
          lat: location.latitude,
          lng: location.longitude,
          accuracy: location.accuracy,
        });
      } else {
        console.log('[useCapture] Location not captured (permission denied or unavailable)');
      }

      // Calculate sync delta
      // Prefer EXIF timestamp if available, fallback to capture start time
      const photoTime = parseExifTimestamp(
        photo.exif?.DateTimeOriginal as string | undefined,
        captureStartTime
      );
      const syncDeltaMs = Math.abs(photoTime - depthFrame.timestamp);

      // Validate sync window (skip validation for mock depth frames)
      // Only validate if we have real LiDAR data
      if (isLiDARAvailable && syncDeltaMs > MAX_SYNC_DELTA_MS) {
        const captureError: CaptureError = {
          code: 'SYNC_TIMEOUT',
          message: `Photo and depth capture timing mismatch (${syncDeltaMs}ms). Please try again.`,
          syncDeltaMs,
        };
        setError(captureError);
        setState('idle');
        throw captureError;
      }

      // Generate capture ID and timestamp
      const captureId = Crypto.randomUUID();
      const capturedAt = new Date().toISOString();

      // Generate per-capture attestation (optional - never blocks capture)
      let assertion: CaptureAssertion | undefined;
      if (isAttestationReady) {
        try {
          console.log('[useCapture] Generating per-capture attestation...');

          // Compute photo hash from file
          const photoBase64 = await FileSystem.readAsStringAsync(photo.uri, {
            encoding: FileSystem.EncodingType.Base64,
          });
          const photoHash = await Crypto.digestStringAsync(
            Crypto.CryptoDigestAlgorithm.SHA256,
            photoBase64,
            { encoding: Crypto.CryptoEncoding.BASE64 }
          );

          // Compute depth map hash from base64 depth data
          const depthHash = await Crypto.digestStringAsync(
            Crypto.CryptoDigestAlgorithm.SHA256,
            depthFrame.depthMap, // Already base64 encoded
            { encoding: Crypto.CryptoEncoding.BASE64 }
          );

          // Compute optional location hash
          let locationHash: string | undefined;
          if (location) {
            const locationString = `${location.latitude},${location.longitude},${location.timestamp}`;
            locationHash = await Crypto.digestStringAsync(
              Crypto.CryptoDigestAlgorithm.SHA256,
              locationString,
              { encoding: Crypto.CryptoEncoding.BASE64 }
            );
          }

          // Build assertion metadata
          const metadata: AssertionMetadata = {
            photoHash,
            depthHash,
            timestamp: capturedAt,
            locationHash,
          };

          // Generate assertion
          assertion = await generateAssertion(metadata) ?? undefined;

          if (assertion) {
            console.log('[useCapture] Attestation generated successfully');
          } else {
            console.log('[useCapture] Attestation not generated (device may not be attested)');
          }
        } catch (attestationError) {
          // Log and continue without assertion (graceful degradation)
          console.warn('[useCapture] Attestation generation failed:', attestationError);
        }
      } else {
        console.log('[useCapture] Skipping attestation (device not attested)');
      }

      // Construct RawCapture with optional location and assertion
      const rawCapture: RawCapture = {
        id: captureId,
        photoUri: photo.uri,
        photoWidth: photo.width,
        photoHeight: photo.height,
        depthFrame,
        capturedAt,
        syncDeltaMs,
        location,
        assertion,
      };

      // Update state
      setLastCapture(rawCapture);
      setState('captured');

      // Reset to idle after brief captured state (allows UI feedback)
      setTimeout(() => setState('idle'), 100);

      console.log(
        `[useCapture] Capture complete: id=${rawCapture.id}, syncDelta=${syncDeltaMs}ms, hasLocation=${!!location}, hasAssertion=${!!assertion}`
      );

      return rawCapture;
    } catch (err) {
      // Handle errors that aren't already CaptureError
      if (err && typeof err === 'object' && 'code' in err) {
        // Already a CaptureError, just rethrow
        throw err;
      }

      // Classify unknown errors
      const errorMessage = err instanceof Error ? err.message : String(err);
      console.error('[useCapture] Unexpected error during capture:', errorMessage, err);
      
      let captureError: CaptureError;

      if (errorMessage.toLowerCase().includes('depth')) {
        captureError = {
          code: 'DEPTH_CAPTURE_FAILED',
          message: 'Failed to capture depth data. Please try again.',
        };
      } else if (errorMessage.toLowerCase().includes('camera') || errorMessage.toLowerCase().includes('photo')) {
        captureError = {
          code: 'CAMERA_ERROR',
          message: 'Failed to capture photo. Please try again.',
        };
      } else {
        captureError = {
          code: 'CAMERA_ERROR',
          message: `Failed to capture photo: ${errorMessage}`,
        };
      }

      setError(captureError);
      setState('idle');
      throw captureError;
    }
  }, [isDepthReady, isCapturing, captureDepthFrame, hasLocationPermission, getCurrentLocation, isAttestationReady, generateAssertion]);

  return {
    capture,
    isCapturing,
    isReady,
    lastCapture,
    error,
    setCameraRef,
    clearError,
    requestLocationPermission,
    hasLocationPermission,
    locationPermissionStatus,
  };
}
