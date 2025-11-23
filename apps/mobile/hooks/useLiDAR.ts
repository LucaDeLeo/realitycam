/**
 * useLiDAR Hook
 *
 * React hook for managing LiDAR depth capture lifecycle.
 * Wraps the native LiDARDepth module with React state management.
 *
 * Features:
 * - Automatic availability check on mount
 * - ARSession lifecycle management (start/stop)
 * - App state handling (pause on background)
 * - Event subscription for depth frame updates
 * - Error handling with user-friendly messages
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 */

import { useEffect, useRef, useCallback, useState } from 'react';
import { AppState, AppStateStatus } from 'react-native';
import type { DepthFrame } from '@realitycam/shared';
import LiDARDepthModule, { DepthFrameEvent } from '../modules/lidar-depth';

/**
 * Error messages for different failure scenarios
 */
export const LIDAR_ERROR_MESSAGES = {
  NOT_AVAILABLE: 'This device does not have LiDAR capability',
  SESSION_FAILED: 'Failed to start depth capture session',
  NO_DEPTH_DATA: 'No depth data available',
  CAPTURE_FAILED: 'Failed to capture depth frame',
} as const;

/**
 * LiDAR capture state
 */
type LiDARState = 'idle' | 'initializing' | 'ready' | 'capturing' | 'error';

/**
 * Hook return type
 */
export interface UseLiDARReturn {
  /** LiDAR hardware present on device */
  isAvailable: boolean;
  /** ARSession active and streaming depth */
  isReady: boolean;
  /** Whether capture session is actively running */
  isCapturing: boolean;
  /** Start ARSession and begin depth capture */
  startDepthCapture: () => Promise<void>;
  /** Stop ARSession and release resources */
  stopDepthCapture: () => Promise<void>;
  /** Capture single depth frame for photo */
  captureDepthFrame: () => Promise<DepthFrame>;
  /** Latest frame for real-time overlay */
  currentFrame: DepthFrame | null;
  /** Current error state if any */
  error: string | null;
  /** Internal state for debugging */
  state: LiDARState;
}

/**
 * Hook for LiDAR depth capture management
 *
 * @example
 * ```tsx
 * function CaptureScreen() {
 *   const {
 *     isAvailable,
 *     isReady,
 *     startDepthCapture,
 *     stopDepthCapture,
 *     currentFrame,
 *     error,
 *   } = useLiDAR();
 *
 *   useEffect(() => {
 *     if (isAvailable) {
 *       startDepthCapture();
 *     }
 *     return () => stopDepthCapture();
 *   }, [isAvailable]);
 *
 *   if (!isAvailable) return <LiDARUnavailable />;
 *   if (!isReady) return <Loading />;
 *
 *   return <DepthOverlay frame={currentFrame} />;
 * }
 * ```
 */
export function useLiDAR(): UseLiDARReturn {
  // State
  const [state, setState] = useState<LiDARState>('idle');
  const [isAvailable, setIsAvailable] = useState<boolean>(false);
  const [currentFrame, setCurrentFrame] = useState<DepthFrame | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Refs to prevent duplicate initialization and track capture state
  const hasInitialized = useRef(false);
  const isCapturingRef = useRef(false);
  const appStateRef = useRef<AppStateStatus>(AppState.currentState);

  /**
   * Check LiDAR availability on mount
   */
  useEffect(() => {
    if (hasInitialized.current) return;
    hasInitialized.current = true;

    const checkAvailability = async () => {
      try {
        setState('initializing');
        const available = await LiDARDepthModule.isLiDARAvailable();
        setIsAvailable(available);
        setState(available ? 'idle' : 'error');
        if (!available) {
          setError(LIDAR_ERROR_MESSAGES.NOT_AVAILABLE);
        }
        console.log(`[useLiDAR] LiDAR available: ${available}`);
      } catch (err) {
        console.error('[useLiDAR] Availability check failed:', err);
        setIsAvailable(false);
        setError(LIDAR_ERROR_MESSAGES.NOT_AVAILABLE);
        setState('error');
      }
    };

    checkAvailability();
  }, []);

  /**
   * Start depth capture session
   */
  const startDepthCapture = useCallback(async () => {
    if (!isAvailable) {
      console.warn('[useLiDAR] Cannot start - LiDAR not available');
      return;
    }

    if (isCapturingRef.current) {
      console.log('[useLiDAR] Already capturing');
      return;
    }

    try {
      console.log('[useLiDAR] Starting depth capture...');
      setState('capturing');
      setError(null);

      await LiDARDepthModule.startDepthCapture();
      isCapturingRef.current = true;

      console.log('[useLiDAR] Depth capture started');
    } catch (err) {
      console.error('[useLiDAR] Failed to start capture:', err);
      setError(LIDAR_ERROR_MESSAGES.SESSION_FAILED);
      setState('error');
      isCapturingRef.current = false;
    }
  }, [isAvailable]);

  /**
   * Stop depth capture session
   */
  const stopDepthCapture = useCallback(async () => {
    if (!isCapturingRef.current) {
      console.log('[useLiDAR] Not capturing, nothing to stop');
      return;
    }

    try {
      console.log('[useLiDAR] Stopping depth capture...');
      await LiDARDepthModule.stopDepthCapture();
      isCapturingRef.current = false;
      setCurrentFrame(null);
      setState('ready');
      console.log('[useLiDAR] Depth capture stopped');
    } catch (err) {
      console.error('[useLiDAR] Failed to stop capture:', err);
      // Still mark as stopped to allow retry
      isCapturingRef.current = false;
    }
  }, []);

  /**
   * Capture single depth frame
   */
  const captureDepthFrame = useCallback(async (): Promise<DepthFrame> => {
    if (!isCapturingRef.current) {
      throw new Error(LIDAR_ERROR_MESSAGES.NOT_AVAILABLE);
    }

    try {
      const frame = await LiDARDepthModule.captureDepthFrame();
      return frame;
    } catch (err) {
      console.error('[useLiDAR] Failed to capture frame:', err);
      throw new Error(LIDAR_ERROR_MESSAGES.CAPTURE_FAILED);
    }
  }, []);

  /**
   * Handle depth frame events from native module
   */
  useEffect(() => {
    const handleDepthFrame = async (event: DepthFrameEvent) => {
      if (event.hasDepth && isCapturingRef.current) {
        try {
          // Fetch full depth frame data
          const frame = await LiDARDepthModule.captureDepthFrame();
          setCurrentFrame(frame);
          // Update state to ready once we have first frame
          if (state === 'capturing') {
            setState('ready');
          }
        } catch {
          // Ignore frame fetch errors during streaming
          // This can happen if frame is stale
        }
      }
    };

    // Subscribe to depth frame events
    LiDARDepthModule.addListener('onDepthFrame', handleDepthFrame);

    return () => {
      LiDARDepthModule.removeListener('onDepthFrame', handleDepthFrame);
    };
  }, [state]);

  /**
   * Handle app state changes (pause on background)
   */
  useEffect(() => {
    const handleAppStateChange = async (nextAppState: AppStateStatus) => {
      const prevState = appStateRef.current;
      appStateRef.current = nextAppState;

      // App going to background - pause capture
      if (
        prevState === 'active' &&
        (nextAppState === 'background' || nextAppState === 'inactive')
      ) {
        if (isCapturingRef.current) {
          console.log('[useLiDAR] App backgrounded, pausing capture');
          await stopDepthCapture();
        }
      }

      // App coming to foreground - resume if was capturing
      // Note: We don't auto-resume - let the component decide
    };

    const subscription = AppState.addEventListener('change', handleAppStateChange);

    return () => {
      subscription.remove();
    };
  }, [stopDepthCapture]);

  /**
   * Cleanup on unmount
   */
  useEffect(() => {
    return () => {
      if (isCapturingRef.current) {
        console.log('[useLiDAR] Unmounting, stopping capture');
        LiDARDepthModule.stopDepthCapture().catch(() => {});
        isCapturingRef.current = false;
      }
    };
  }, []);

  return {
    isAvailable,
    isReady: state === 'ready',
    isCapturing: isCapturingRef.current,
    startDepthCapture,
    stopDepthCapture,
    captureDepthFrame,
    currentFrame,
    error,
    state,
  };
}
