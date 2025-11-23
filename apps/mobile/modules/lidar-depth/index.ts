/**
 * LiDAR Depth Module
 *
 * Custom Expo module for ARKit LiDAR depth capture on iOS.
 * Provides real-time depth sensing for RealityCam photo authentication.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 * @see docs/architecture.md#ADR-002
 */

import { NativeModule, requireNativeModule } from 'expo-modules-core';
import type { DepthFrame, CameraIntrinsics } from '@realitycam/shared';

// Re-export shared types for convenience
export type { DepthFrame, CameraIntrinsics };

/**
 * Error types that can occur during LiDAR operations
 */
export type LiDARError =
  | 'NOT_AVAILABLE'
  | 'NO_DEPTH_DATA'
  | 'SESSION_FAILED'
  | 'PERMISSION_DENIED';

/**
 * Event data emitted on each depth frame
 */
export interface DepthFrameEvent {
  /** Unix timestamp in milliseconds */
  timestamp: number;
  /** Whether depth data is available in this frame */
  hasDepth: boolean;
}

/**
 * Native module interface for LiDAR depth capture
 */
interface LiDARDepthModuleInterface extends NativeModule {
  /**
   * Check if LiDAR hardware is available on this device
   * Uses ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
   */
  isLiDARAvailable(): Promise<boolean>;

  /**
   * Start ARKit depth capture session
   * Configures ARSession with sceneDepth frameSemantics
   */
  startDepthCapture(): Promise<void>;

  /**
   * Stop ARKit depth capture session
   * Pauses ARSession and releases resources
   */
  stopDepthCapture(): Promise<void>;

  /**
   * Capture a single depth frame for photo attachment
   * Returns full depth map data for storage/processing
   */
  captureDepthFrame(): Promise<DepthFrame>;

  /**
   * Event subscription for real-time depth frame updates
   * Emits at ~30fps when capture is active
   */
  addListener(eventName: 'onDepthFrame', listener: (event: DepthFrameEvent) => void): void;
  removeListener(eventName: 'onDepthFrame', listener: (event: DepthFrameEvent) => void): void;
}

// Require the native module - will throw if not available
// On non-iOS platforms or simulator, this will be a mock
let LiDARDepthModule: LiDARDepthModuleInterface;

try {
  LiDARDepthModule = requireNativeModule<LiDARDepthModuleInterface>('LiDARDepth');
} catch {
  // Provide a mock for non-iOS platforms or when native module is not available
  // This allows TypeScript compilation and basic testing on simulator
  LiDARDepthModule = {
    isLiDARAvailable: async () => false,
    startDepthCapture: async () => {
      console.warn('[LiDARDepth] Native module not available');
    },
    stopDepthCapture: async () => {
      console.warn('[LiDARDepth] Native module not available');
    },
    captureDepthFrame: async () => {
      throw new Error('LiDAR not available on this device');
    },
    addListener: () => {
      console.warn('[LiDARDepth] Event listeners not available');
    },
    removeListener: () => {},
  } as unknown as LiDARDepthModuleInterface;
}

export { LiDARDepthModule };
export default LiDARDepthModule;
