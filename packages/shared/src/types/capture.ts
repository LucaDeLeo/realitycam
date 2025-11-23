import { ConfidenceLevel, Evidence } from './evidence';

export interface Capture {
  id: string;
  confidence_level: ConfidenceLevel;
  captured_at: string;
  media_url: string;
  evidence: Evidence;
  c2pa_manifest_url?: string;
  depth_visualization_url?: string;
}

// ============================================================================
// LiDAR Depth Types (Story 3.1)
// ============================================================================

/**
 * Camera intrinsics for depth-to-3D conversion
 * Extracted from ARFrame.camera.intrinsics matrix
 */
export interface CameraIntrinsics {
  /** Focal length X */
  fx: number;
  /** Focal length Y */
  fy: number;
  /** Principal point X */
  cx: number;
  /** Principal point Y */
  cy: number;
}

/**
 * Depth frame data from LiDAR sensor
 * Contains depth map and metadata for overlay visualization and storage
 */
export interface DepthFrame {
  /** Base64-encoded Float32Array of depth values in meters */
  depthMap: string;
  /** Width of depth map (typically 256) */
  width: number;
  /** Height of depth map (typically 192) */
  height: number;
  /** Unix timestamp in milliseconds */
  timestamp: number;
  /** Camera intrinsics for depth-to-3D conversion */
  intrinsics: CameraIntrinsics;
}

/**
 * Colormap configuration for depth visualization
 */
export interface DepthColormap {
  /** Colormap style */
  name: 'viridis' | 'plasma' | 'thermal';
  /** Minimum depth in meters (default 0) */
  minDepth: number;
  /** Maximum depth in meters (default 5) */
  maxDepth: number;
  /** Overlay opacity 0-1 (default 0.4) */
  opacity: number;
}

/**
 * Configuration for depth overlay display
 */
export interface DepthOverlayConfig {
  /** Whether overlay is visible */
  enabled: boolean;
  /** Colormap settings */
  colormap: DepthColormap;
  /** Show numeric depth value on tap */
  showDepthValues: boolean;
}

// ============================================================================
// Raw Capture Types (Story 3.2)
// ============================================================================

/**
 * Raw capture data from photo + depth capture
 * Created immediately after synchronized capture completes
 */
export interface RawCapture {
  /** UUID for this capture (expo-crypto randomUUID) */
  id: string;
  /** Local file URI to captured JPEG */
  photoUri: string;
  /** Photo width in pixels */
  photoWidth: number;
  /** Photo height in pixels */
  photoHeight: number;
  /** Depth frame from useLiDAR.captureDepthFrame() */
  depthFrame: DepthFrame;
  /** ISO timestamp of capture */
  capturedAt: string;
  /** Time delta between photo and depth timestamps (must be < 100ms) */
  syncDeltaMs: number;
}

/**
 * Error codes for capture failures
 */
export type CaptureErrorCode =
  | 'CAMERA_ERROR'
  | 'DEPTH_CAPTURE_FAILED'
  | 'SYNC_TIMEOUT'
  | 'NOT_READY';

/**
 * Structured error for capture failures
 */
export interface CaptureError {
  /** Error classification */
  code: CaptureErrorCode;
  /** User-friendly error message */
  message: string;
  /** Present for SYNC_TIMEOUT errors - actual sync delta */
  syncDeltaMs?: number;
}
