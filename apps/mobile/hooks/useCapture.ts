/**
 * useCapture Hook
 *
 * Orchestrates synchronized photo + depth capture.
 * Manages capture state machine, camera ref, and integrates with useLiDAR.
 *
 * Features:
 * - Parallel photo and depth capture via Promise.all
 * - 100ms synchronization window validation
 * - State machine: idle -> capturing -> captured -> idle
 * - Error handling with typed CaptureError
 * - Camera ref management for expo-camera
 *
 * @see Story 3.2 - Photo Capture with Depth Map
 */

import { useCallback, useState, useRef } from 'react';
import { CameraView as ExpoCameraView } from 'expo-camera';
import * as Crypto from 'expo-crypto';
import { useLiDAR } from './useLiDAR';
import type { DepthFrame, RawCapture, CaptureError } from '@realitycam/shared';

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
  /** Initiate synchronized photo + depth capture */
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
  const { captureDepthFrame, isReady: isDepthReady } = useLiDAR();

  // Capture state machine
  const [state, setState] = useState<CaptureState>('idle');
  const [lastCapture, setLastCapture] = useState<RawCapture | null>(null);
  const [error, setError] = useState<CaptureError | null>(null);

  // Camera ref for expo-camera takePictureAsync
  const cameraRef = useRef<ExpoCameraView | null>(null);

  // Derived state
  const isCapturing = state === 'capturing';
  const isReady = cameraRef.current !== null && isDepthReady;

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

    if (!isDepthReady) {
      const captureError: CaptureError = {
        code: 'NOT_READY',
        message: 'Depth sensor not ready. Please wait and try again.',
      };
      setError(captureError);
      throw captureError;
    }

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
      const [photo, depthFrame] = await Promise.all([
        cameraRef.current.takePictureAsync({
          quality: 1,
          exif: true,
          base64: false,
        }),
        captureDepthFrame(),
      ]);

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

      // Calculate sync delta
      // Prefer EXIF timestamp if available, fallback to capture start time
      const photoTime = parseExifTimestamp(
        photo.exif?.DateTimeOriginal as string | undefined,
        captureStartTime
      );
      const syncDeltaMs = Math.abs(photoTime - depthFrame.timestamp);

      // Validate sync window
      if (syncDeltaMs > MAX_SYNC_DELTA_MS) {
        const captureError: CaptureError = {
          code: 'SYNC_TIMEOUT',
          message: `Photo and depth capture timing mismatch (${syncDeltaMs}ms). Please try again.`,
          syncDeltaMs,
        };
        setError(captureError);
        setState('idle');
        throw captureError;
      }

      // Construct RawCapture
      const rawCapture: RawCapture = {
        id: Crypto.randomUUID(),
        photoUri: photo.uri,
        photoWidth: photo.width,
        photoHeight: photo.height,
        depthFrame,
        capturedAt: new Date().toISOString(),
        syncDeltaMs,
      };

      // Update state
      setLastCapture(rawCapture);
      setState('captured');

      // Reset to idle after brief captured state (allows UI feedback)
      setTimeout(() => setState('idle'), 100);

      console.log(
        `[useCapture] Capture complete: id=${rawCapture.id}, syncDelta=${syncDeltaMs}ms`
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
      let captureError: CaptureError;

      if (errorMessage.toLowerCase().includes('depth')) {
        captureError = {
          code: 'DEPTH_CAPTURE_FAILED',
          message: 'Failed to capture depth data. Please try again.',
        };
      } else {
        captureError = {
          code: 'CAMERA_ERROR',
          message: 'Failed to capture photo. Please try again.',
        };
      }

      setError(captureError);
      setState('idle');
      throw captureError;
    }
  }, [isDepthReady, isCapturing, captureDepthFrame]);

  return {
    capture,
    isCapturing,
    isReady,
    lastCapture,
    error,
    setCameraRef,
    clearError,
  };
}
