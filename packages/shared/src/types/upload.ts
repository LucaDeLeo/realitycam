/**
 * Upload Queue Types
 *
 * Types for the upload queue system with exponential backoff retry logic.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic
 */

import type { ProcessedCapture } from './capture';

// ============================================================================
// Upload Status Types
// ============================================================================

/**
 * Upload queue item status lifecycle
 *
 * State machine:
 * pending -> uploading -> processing -> completed
 *                |            |
 *                v            v
 *              failed ------> (retry) -> pending
 *                |
 *                v (max retries)
 *          permanently_failed
 */
export type QueuedCaptureStatus =
  | 'pending'           // Waiting in queue
  | 'uploading'         // Currently uploading
  | 'processing'        // Server processing after upload
  | 'completed'         // Upload successful
  | 'failed'            // Failed, can retry
  | 'permanently_failed'; // Failed after max retries

// ============================================================================
// Error Types
// ============================================================================

/**
 * Error classification for retry logic
 *
 * - NETWORK_ERROR: No connectivity - wait for network, then retry
 * - SERVER_ERROR: 5xx response - exponential backoff retry
 * - VALIDATION_ERROR: 400 - don't retry, user action needed
 * - AUTH_ERROR: 401 - don't retry, device may need re-registration
 * - NOT_FOUND: 404 - don't retry, device not registered
 * - PAYLOAD_TOO_LARGE: 413 - don't retry, file too large
 * - RATE_LIMITED: 429 - retry with Retry-After header
 * - TIMEOUT: Request timed out - retry
 * - UNKNOWN: Unknown error - retry with caution
 */
export type UploadErrorCode =
  | 'NETWORK_ERROR'
  | 'SERVER_ERROR'
  | 'VALIDATION_ERROR'
  | 'AUTH_ERROR'
  | 'NOT_FOUND'
  | 'PAYLOAD_TOO_LARGE'
  | 'RATE_LIMITED'
  | 'TIMEOUT'
  | 'UNKNOWN';

/**
 * Structured upload error with retry information
 */
export interface UploadError {
  /** Error classification for retry logic */
  code: UploadErrorCode;
  /** Human-readable error message */
  message: string;
  /** HTTP status code (if applicable) */
  statusCode?: number;
  /** Seconds to wait before retry (from 429 Retry-After header) */
  retryAfter?: number;
}

// ============================================================================
// Queue Item Types
// ============================================================================

/**
 * Queue item wrapping a processed capture
 * Contains all state needed for upload lifecycle management
 */
export interface QueuedCapture {
  /** Original processed capture data */
  capture: ProcessedCapture;
  /** Current queue status */
  status: QueuedCaptureStatus;
  /** Number of upload attempts (starts at 0) */
  retryCount: number;
  /** ISO timestamp when added to queue */
  queuedAt: string;
  /** ISO timestamp of last upload attempt */
  lastAttemptAt?: string;
  /** ISO timestamp when completed successfully */
  completedAt?: string;
  /** Error from last failed attempt */
  error?: UploadError;
  /** Server-assigned capture ID after successful upload */
  captureId?: string;
  /** Verification URL from server (for sharing) */
  verificationUrl?: string;
  /** Upload progress 0-100 (during uploading status only) */
  progress?: number;
}

// ============================================================================
// Queue Store Types
// ============================================================================

/**
 * Upload queue store state
 * Managed by Zustand with AsyncStorage persistence
 */
export interface UploadQueueState {
  /** All queued items */
  items: QueuedCapture[];
  /** Whether queue processor is currently running */
  isProcessing: boolean;
  /** ID of currently uploading item (null if none) */
  currentUploadId: string | null;
}

/**
 * Upload queue store actions
 */
export interface UploadQueueActions {
  /** Add a processed capture to the queue */
  enqueue: (capture: ProcessedCapture) => void;
  /** Remove the front item from queue */
  dequeue: () => void;
  /** Mark an item as completed with server response */
  markCompleted: (id: string, captureId: string, verificationUrl: string) => void;
  /** Mark an item as failed with error */
  markFailed: (id: string, error: UploadError) => void;
  /** Mark an item as permanently failed (max retries exceeded) */
  markPermanentlyFailed: (id: string) => void;
  /** Update upload progress for an item */
  updateProgress: (id: string, progress: number) => void;
  /** Set item status to uploading */
  setUploading: (id: string) => void;
  /** Set item status to processing (server-side) */
  setProcessing: (id: string) => void;
  /** Retry a failed item (moves to front of queue) */
  retry: (id: string) => void;
  /** Cancel and remove an item from queue */
  cancel: (id: string) => void;
  /** Set processing flag */
  setIsProcessing: (isProcessing: boolean) => void;
  /** Set current upload ID */
  setCurrentUploadId: (id: string | null) => void;
  /** Get next pending item in queue */
  getNextPending: () => QueuedCapture | undefined;
  /** Clear all completed items from queue */
  clearCompleted: () => void;
}

// ============================================================================
// API Response Types
// ============================================================================

/**
 * Upload success response from backend POST /api/v1/captures
 * Returns 202 Accepted with processing status
 */
export interface CaptureUploadResponse {
  data: {
    /** Server-assigned UUID for this capture */
    capture_id: string;
    /** Server processing status */
    status: 'processing' | 'complete';
    /** URL for verification/sharing */
    verification_url: string;
  };
  meta: {
    /** Request ID for tracing */
    request_id: string;
    /** ISO timestamp of response */
    timestamp: string;
  };
}

// ============================================================================
// Retry Strategy Types
// ============================================================================

/**
 * Retry strategy configuration
 */
export interface RetryConfig {
  /** Maximum number of retry attempts (default: 10) */
  maxAttempts: number;
  /** Maximum backoff delay in milliseconds (default: 300000 = 5 minutes) */
  maxBackoffMs: number;
  /** Base delay multiplier in milliseconds (default: 1000 = 1 second) */
  baseDelayMs: number;
}

/**
 * Default retry configuration per tech spec
 * - Attempt 1: immediate (0ms)
 * - Attempt 2: 1s delay
 * - Attempt 3: 2s delay
 * - Attempt 4: 4s delay
 * - Attempt 5: 8s delay
 * - Attempts 6-10: 5 minutes (300s) cap
 */
export const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxAttempts: 10,
  maxBackoffMs: 300_000, // 5 minutes
  baseDelayMs: 1_000,    // 1 second
};

// ============================================================================
// Offline Storage Types (Story 4.3)
// ============================================================================

/**
 * Storage location for queued captures
 * - memory: Capture data held in Zustand store (default for online captures)
 * - disk: Capture data encrypted and stored on disk (for offline captures)
 */
export type CaptureStorageLocation = 'memory' | 'disk';

/**
 * Storage quota status thresholds
 * - ok: Below warning threshold
 * - warning: At or above 80% of quota
 * - exceeded: At or above 100% of quota (cannot save more)
 */
export type StorageQuotaStatus = 'ok' | 'warning' | 'exceeded';

/**
 * Encryption metadata stored with each offline capture
 * Contains all info needed to decrypt capture files
 */
export interface OfflineCaptureEncryption {
  /** Reference to encryption key in expo-secure-store */
  keyId: string;
  /** Base64-encoded initialization vector for AES-GCM */
  iv: string;
  /** Encryption algorithm used */
  algorithm: 'aes-256-gcm';
  /** ISO timestamp when encryption was applied */
  createdAt: string;
}

/**
 * Metadata for an offline-stored capture
 * Stored in encryption.json alongside encrypted capture files
 */
export interface OfflineCaptureMetadata {
  /** Capture UUID */
  captureId: string;
  /** Encryption details */
  encryption: OfflineCaptureEncryption;
  /** Size of encrypted photo file in bytes */
  photoSize: number;
  /** Size of encrypted depth map file in bytes */
  depthSize: number;
  /** Size of encrypted metadata file in bytes */
  metadataSize: number;
  /** Total storage used by this capture in bytes */
  totalSize: number;
  /** ISO timestamp when capture was queued */
  queuedAt: string;
}

/**
 * Storage quota information and status
 */
export interface StorageQuotaInfo {
  /** Current quota status */
  status: StorageQuotaStatus;
  /** Number of offline captures stored */
  captureCount: number;
  /** Maximum captures allowed */
  maxCaptures: number;
  /** Bytes used by offline captures */
  storageUsedBytes: number;
  /** Maximum storage in bytes */
  maxStorageBytes: number;
  /** Usage percentage (0-100) */
  usagePercent: number;
  /** Age of oldest capture in hours (if any) */
  oldestCaptureAgeHours?: number;
}

/**
 * Quota configuration constants
 */
export const STORAGE_QUOTA_CONFIG = {
  /** Maximum number of offline captures */
  MAX_CAPTURES: 50,
  /** Maximum storage in bytes (500MB) */
  MAX_STORAGE_BYTES: 500 * 1024 * 1024,
  /** Warning threshold (80%) */
  WARNING_THRESHOLD: 0.8,
  /** Days after which captures are considered stale */
  STALE_CAPTURE_DAYS: 7,
} as const;

/**
 * Index entry for a stored capture
 * Used for tracking captures without loading full data
 */
export interface CaptureIndexEntry {
  /** Capture UUID */
  captureId: string;
  /** ISO timestamp when queued */
  queuedAt: string;
  /** Total bytes used by this capture */
  totalSize: number;
  /** Current queue status */
  status: QueuedCaptureStatus;
  /** Whether this was captured offline */
  isOfflineCapture: boolean;
}

/**
 * Extended QueuedCapture with offline storage fields
 */
export interface OfflineQueuedCapture extends QueuedCapture {
  /** Where capture data is stored */
  storageLocation: CaptureStorageLocation;
  /** True if capture was created while offline */
  isOfflineCapture: boolean;
}
