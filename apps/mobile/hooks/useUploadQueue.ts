/**
 * useUploadQueue Hook
 *
 * Queue processing hook with network awareness and automatic retry.
 * Handles the upload lifecycle from queue entry to completion/failure.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic (AC-1, AC-2, AC-4, AC-6)
 */

import { useEffect, useCallback, useRef } from 'react';
import type { ProcessedCapture, QueuedCapture } from '@realitycam/shared';
import { useUploadQueueStore, selectQueueCounts, selectCurrentUpload } from '../store/uploadQueueStore';
import { useNetworkStatus } from './useNetworkStatus';
import { uploadCapture } from '../services/uploadService';
import {
  calculateDelayWithRetryAfter,
  shouldRetry,
  isMaxRetriesExceeded,
} from '../utils/retryStrategy';
import { cleanupCapture } from '../services/captureCleanup';

/**
 * useUploadQueue hook return type
 */
export interface UseUploadQueueReturn {
  /** Add a capture to the upload queue */
  enqueue: (capture: ProcessedCapture) => void;
  /** Retry a failed upload */
  retry: (id: string) => void;
  /** Cancel a pending/failed upload */
  cancel: (id: string) => void;
  /** Clear all completed uploads */
  clearCompleted: () => void;
  /** All items in queue */
  items: QueuedCapture[];
  /** Currently uploading item (if any) */
  currentUpload: QueuedCapture | null;
  /** Count of items by status */
  counts: {
    pending: number;
    uploading: number;
    processing: number;
    completed: number;
    failed: number;
    permanentlyFailed: number;
    total: number;
  };
  /** Whether queue processor is running */
  isProcessing: boolean;
  /** Whether network is available for uploads */
  isNetworkAvailable: boolean;
}

/**
 * Hook for managing upload queue with network-aware processing
 *
 * Features:
 * - Automatic queue processing when network available
 * - Exponential backoff retry on failures
 * - Progress tracking for active uploads
 * - Manual retry and cancel support
 * - Automatic resume on app foreground
 *
 * @example
 * ```tsx
 * const {
 *   enqueue,
 *   retry,
 *   cancel,
 *   items,
 *   currentUpload,
 *   counts,
 *   isNetworkAvailable,
 * } = useUploadQueue();
 *
 * // Add capture to queue
 * enqueue(processedCapture);
 *
 * // Show queue status
 * console.log(`${counts.pending} pending, ${counts.uploading} uploading`);
 *
 * // Retry failed item
 * if (failedItem) retry(failedItem.capture.id);
 * ```
 */
export function useUploadQueue(): UseUploadQueueReturn {
  // Queue store state and actions
  const items = useUploadQueueStore((state) => state.items);
  const isProcessing = useUploadQueueStore((state) => state.isProcessing);
  const hasHydrated = useUploadQueueStore((state) => state.hasHydrated);
  const counts = useUploadQueueStore(selectQueueCounts);
  const currentUpload = useUploadQueueStore(selectCurrentUpload);

  // Store actions
  const enqueue = useUploadQueueStore((state) => state.enqueue);
  const retry = useUploadQueueStore((state) => state.retry);
  const cancel = useUploadQueueStore((state) => state.cancel);
  const clearCompleted = useUploadQueueStore((state) => state.clearCompleted);
  const getNextPending = useUploadQueueStore((state) => state.getNextPending);
  const setIsProcessing = useUploadQueueStore((state) => state.setIsProcessing);
  const setUploading = useUploadQueueStore((state) => state.setUploading);
  const setProcessing = useUploadQueueStore((state) => state.setProcessing);
  const updateProgress = useUploadQueueStore((state) => state.updateProgress);
  const markCompleted = useUploadQueueStore((state) => state.markCompleted);
  const markFailed = useUploadQueueStore((state) => state.markFailed);
  const markPermanentlyFailed = useUploadQueueStore((state) => state.markPermanentlyFailed);

  // Network status
  const { isConnected, isInternetReachable } = useNetworkStatus();
  const isNetworkAvailable = isConnected === true && isInternetReachable === true;

  // Processing state refs
  const isProcessingRef = useRef(false);
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const processingLockRef = useRef(false);

  /**
   * Process a single upload
   */
  const processUpload = useCallback(async (item: QueuedCapture) => {
    const captureId = item.capture.id;
    console.log('[useUploadQueue] Processing upload:', captureId);

    // Mark as uploading
    setUploading(captureId);

    // Perform upload with progress tracking
    const result = await uploadCapture(item.capture, (progress) => {
      updateProgress(captureId, progress);
    });

    if (result.success) {
      // Upload succeeded
      const { capture_id, verification_url, status } = result.data.data;

      if (status === 'processing') {
        // Server is processing - mark as processing
        setProcessing(captureId);
        // For now, mark complete after processing status
        // Future: Poll for completion or use webhooks
        markCompleted(captureId, capture_id, verification_url);
      } else {
        // Completed immediately
        markCompleted(captureId, capture_id, verification_url);
      }

      console.log('[useUploadQueue] Upload completed:', {
        captureId,
        serverCaptureId: capture_id,
      });

      // Clean up local files after successful upload (deferred to avoid blocking)
      setTimeout(async () => {
        try {
          const result = await cleanupCapture(captureId);
          if (result.success) {
            console.log('[useUploadQueue] Cleanup completed:', {
              captureId,
              freedBytes: result.freedBytes,
            });
          } else {
            console.warn('[useUploadQueue] Cleanup failed:', result.error);
          }
        } catch (err) {
          console.warn('[useUploadQueue] Cleanup error:', err);
        }
      }, 100);
    } else {
      // Upload failed
      const { error } = result;
      console.log('[useUploadQueue] Upload failed:', {
        captureId,
        error: error.code,
        retryCount: item.retryCount,
      });

      // Check if we should retry
      if (shouldRetry(error, item.retryCount + 1)) {
        // Mark as failed (increments retry count)
        markFailed(captureId, error);

        // Schedule retry with backoff
        const delay = calculateDelayWithRetryAfter(error, item.retryCount + 1);
        console.log('[useUploadQueue] Scheduling retry in', delay, 'ms');

        if (retryTimerRef.current) {
          clearTimeout(retryTimerRef.current);
        }
        retryTimerRef.current = setTimeout(() => {
          // Move back to pending for retry
          const store = useUploadQueueStore.getState();
          const failedItem = store.items.find((i) => i.capture.id === captureId);
          if (failedItem && failedItem.status === 'failed') {
            store.retry(captureId);
          }
        }, delay);
      } else if (isMaxRetriesExceeded(item.retryCount + 1)) {
        // Max retries exceeded
        markFailed(captureId, error);
        markPermanentlyFailed(captureId);
        console.log('[useUploadQueue] Max retries exceeded, permanently failed:', captureId);
      } else {
        // Non-retryable error
        markFailed(captureId, error);
        console.log('[useUploadQueue] Non-retryable error:', captureId, error.code);
      }
    }
  }, [
    setUploading,
    updateProgress,
    setProcessing,
    markCompleted,
    markFailed,
    markPermanentlyFailed,
  ]);

  /**
   * Process queue - handle next pending item
   */
  const processQueue = useCallback(async () => {
    // Prevent concurrent processing
    if (processingLockRef.current) {
      console.log('[useUploadQueue] Queue processing already in progress');
      return;
    }

    // Check network availability
    if (!isNetworkAvailable) {
      console.log('[useUploadQueue] Network not available, pausing queue');
      setIsProcessing(false);
      return;
    }

    // Get next pending item
    const nextItem = getNextPending();
    if (!nextItem) {
      console.log('[useUploadQueue] No pending items in queue');
      setIsProcessing(false);
      return;
    }

    // Acquire processing lock
    processingLockRef.current = true;
    setIsProcessing(true);

    try {
      await processUpload(nextItem);
    } finally {
      // Release lock
      processingLockRef.current = false;
    }

    // Continue processing if there are more items
    const store = useUploadQueueStore.getState();
    const hasMorePending = store.items.some((item) => item.status === 'pending');
    if (hasMorePending && isNetworkAvailable) {
      // Small delay to prevent tight loop
      setTimeout(() => {
        processQueue();
      }, 100);
    } else {
      setIsProcessing(false);
    }
  }, [isNetworkAvailable, getNextPending, setIsProcessing, processUpload]);

  // Start processing when network becomes available
  useEffect(() => {
    if (!hasHydrated) {
      console.log('[useUploadQueue] Waiting for store hydration');
      return;
    }

    if (isNetworkAvailable && counts.pending > 0 && !isProcessing) {
      console.log('[useUploadQueue] Network available, starting queue processing');
      processQueue();
    }
  }, [isNetworkAvailable, counts.pending, isProcessing, hasHydrated, processQueue]);

  // Start processing when new item is enqueued
  useEffect(() => {
    if (!hasHydrated) return;

    if (counts.pending > 0 && isNetworkAvailable && !isProcessing) {
      processQueue();
    }
  }, [counts.pending, isNetworkAvailable, isProcessing, hasHydrated, processQueue]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (retryTimerRef.current) {
        clearTimeout(retryTimerRef.current);
      }
    };
  }, []);

  return {
    enqueue,
    retry,
    cancel,
    clearCompleted,
    items,
    currentUpload: currentUpload ?? null,
    counts,
    isProcessing,
    isNetworkAvailable,
  };
}

/**
 * Lightweight hook for just reading queue status
 * Use when you don't need queue manipulation functions
 */
export function useUploadQueueStatus() {
  const items = useUploadQueueStore((state) => state.items);
  const isProcessing = useUploadQueueStore((state) => state.isProcessing);
  const counts = useUploadQueueStore(selectQueueCounts);
  const currentUpload = useUploadQueueStore(selectCurrentUpload);
  const { isConnected, isInternetReachable } = useNetworkStatus();

  return {
    items,
    counts,
    currentUpload,
    isProcessing,
    isNetworkAvailable: isConnected === true && isInternetReachable === true,
  };
}
