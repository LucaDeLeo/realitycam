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
  /** Optional GPS location data (undefined if permission denied or unavailable) */
  location?: CaptureLocation;
  /** Optional per-capture attestation (undefined if device not attested or assertion failed) */
  assertion?: CaptureAssertion;
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

// ============================================================================
// Location Types (Story 3.3)
// ============================================================================

/**
 * GPS location data captured with photo
 * Location is always optional - capture proceeds without it if permission denied
 */
export interface CaptureLocation {
  /** Latitude with 6 decimal places (~11cm precision) */
  latitude: number;
  /** Longitude with 6 decimal places */
  longitude: number;
  /** Meters above sea level (null if unavailable) */
  altitude: number | null;
  /** Horizontal accuracy in meters */
  accuracy: number;
  /** ISO timestamp of GPS fix */
  timestamp: string;
}

/**
 * Error codes for location failures (informational only - never blocks capture)
 */
export type LocationErrorCode =
  | 'PERMISSION_DENIED'   // User denied permission
  | 'TIMEOUT'             // Location request timed out
  | 'UNAVAILABLE'         // Location services unavailable
  | 'STALE_LOCATION'      // Location too old (> 10 seconds)
  | 'UNKNOWN';            // Unknown error

/**
 * Location error (informational - does not prevent capture)
 */
export interface LocationError {
  /** Error classification */
  code: LocationErrorCode;
  /** User-friendly error message */
  message: string;
}

// ============================================================================
// Capture Attestation Types (Story 3.4)
// ============================================================================

/**
 * Metadata included in per-capture assertion hash
 * This data is hashed and signed to bind capture to attested device
 */
export interface AssertionMetadata {
  /** SHA-256 hash of photo bytes (base64) */
  photoHash: string;
  /** SHA-256 hash of depth map bytes (base64) */
  depthHash: string;
  /** ISO timestamp of capture */
  timestamp: string;
  /** SHA-256 hash of location string (if available) */
  locationHash?: string;
}

/**
 * Per-capture device attestation assertion
 * Cryptographically binds capture to attested device
 */
export interface CaptureAssertion {
  /** Base64-encoded assertion from @expo/app-integrity generateAssertionAsync */
  assertion: string;
  /** Base64-encoded SHA-256 hash of AssertionMetadata JSON */
  clientDataHash: string;
  /** ISO timestamp when assertion was generated */
  timestamp: string;
}

/**
 * Error codes for capture assertion failures (informational only)
 */
export type CaptureAssertionErrorCode =
  | 'NOT_ATTESTED'       // Device not attested (keyId missing)
  | 'ASSERTION_FAILED'   // generateAssertionAsync threw
  | 'HASH_FAILED'        // SHA-256 computation failed
  | 'UNKNOWN';           // Unknown error

/**
 * Capture assertion error (informational - does not prevent capture)
 */
export interface CaptureAssertionError {
  /** Error classification */
  code: CaptureAssertionErrorCode;
  /** User-friendly error message */
  message: string;
}

// ============================================================================
// Local Processing Types (Story 3.5)
// ============================================================================

/**
 * Capture status lifecycle
 * Tracks capture from initial photo through upload completion
 */
export type CaptureStatus =
  | 'capturing'    // Photo + depth being taken
  | 'processing'   // Local processing (hash, compress)
  | 'ready'        // Ready for upload
  | 'uploading'    // Upload in progress (Epic 4)
  | 'completed'    // Upload successful
  | 'failed';      // Upload failed

/**
 * Metadata for upload payload
 * Assembled during local processing for backend consumption
 */
export interface CaptureMetadata {
  /** ISO timestamp of capture */
  captured_at: string;
  /** Device model string (e.g., "iPhone 15 Pro") */
  device_model: string;
  /** SHA-256 base64 hash of photo bytes */
  photo_hash: string;
  /** Depth map dimensions */
  depth_map_dimensions: {
    width: number;
    height: number;
  };
  /** Optional GPS location data */
  location?: CaptureLocation;
  /** Base64 per-capture assertion (if device is attested) */
  assertion?: string;
}

/**
 * Processed capture ready for upload
 * Contains compressed depth, hashes, and assembled metadata
 */
export interface ProcessedCapture {
  /** UUID for this capture */
  id: string;
  /** Local file URI to captured JPEG */
  photoUri: string;
  /** SHA-256 base64 hash of photo bytes */
  photoHash: string;
  /** Base64-encoded gzipped depth map (Float32Array compressed with pako) */
  compressedDepthMap: string;
  /** Depth map dimensions */
  depthDimensions: {
    width: number;
    height: number;
  };
  /** Assembled metadata for backend */
  metadata: CaptureMetadata;
  /** Base64 device assertion (if available) */
  assertion?: string;
  /** Processing lifecycle status */
  status: CaptureStatus;
  /** ISO timestamp when capture was created */
  createdAt: string;
}

/**
 * Error codes for processing failures
 */
export type ProcessingErrorCode =
  | 'HASH_FAILED'       // SHA-256 computation failed
  | 'COMPRESSION_FAILED' // Gzip compression failed
  | 'FILE_READ_FAILED'  // Failed to read photo file
  | 'UNKNOWN';          // Unknown error

/**
 * Processing error
 */
export interface ProcessingError {
  /** Error classification */
  code: ProcessingErrorCode;
  /** User-friendly error message */
  message: string;
}
