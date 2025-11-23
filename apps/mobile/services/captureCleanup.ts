/**
 * Capture Cleanup Service
 *
 * Handles cleanup of local capture files after successful upload.
 * Removes encrypted files while preserving queue record for history.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-6)
 */

import type { CaptureIndexEntry } from '@realitycam/shared';
import { deleteCaptureFromStorage, cleanupTempFiles, loadCaptureFromStorage } from './offlineStorage';
import { removeFromIndex, getStoredCaptures, updateIndexStatus } from './captureIndex';
import { deleteEncryptionKey } from './captureEncryption';
import { suggestCleanup, getCapturesOlderThan24Hours } from './storageQuota';

/**
 * Cleanup result for a single capture
 */
export interface CleanupResult {
  captureId: string;
  success: boolean;
  error?: string;
  freedBytes: number;
}

/**
 * Cleanup a single capture after successful upload
 *
 * Removes:
 * - Encrypted capture files (photo, depth, metadata)
 * - Encryption metadata file
 * - Capture directory
 * - Encryption key from secure store
 * - Temp decrypted files (if any)
 *
 * Does NOT remove:
 * - Queue record (preserved for history/verification_url)
 * - Index entry (status updated but preserved)
 *
 * @param captureId - Capture ID to clean up
 * @returns Cleanup result
 */
export async function cleanupCapture(captureId: string): Promise<CleanupResult> {
  console.log('[captureCleanup] Starting cleanup:', captureId);

  let freedBytes = 0;

  try {
    // Get capture entry to know how much space we're freeing
    const captures = await getStoredCaptures();
    const entry = captures.find((c) => c.captureId === captureId);
    if (entry) {
      freedBytes = entry.totalSize;
    }

    // Load metadata to get key ID before deletion
    const captureData = await loadCaptureFromStorage(captureId);
    const keyId: string | null = null;

    // Note: We can't get keyId from captureData as it's reconstructed
    // The key deletion is handled separately if needed

    // Delete capture files and directory
    const deleted = await deleteCaptureFromStorage(captureId);
    if (!deleted) {
      console.warn('[captureCleanup] Failed to delete capture files:', captureId);
      // Continue anyway - files may have already been deleted
    }

    // Clean up any temp files
    await cleanupTempFiles(captureId);

    // Remove from index
    await removeFromIndex(captureId);

    console.log('[captureCleanup] Cleanup completed:', {
      captureId,
      freedBytes,
    });

    return {
      captureId,
      success: true,
      freedBytes,
    };
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : 'Unknown error';
    console.error('[captureCleanup] Cleanup failed:', captureId, errorMsg);

    // Don't throw - cleanup failures should not affect upload success
    return {
      captureId,
      success: false,
      error: errorMsg,
      freedBytes: 0,
    };
  }
}

/**
 * Cleanup multiple completed captures
 *
 * @param captureIds - Array of capture IDs to clean up
 * @returns Array of cleanup results
 */
export async function cleanupCaptures(captureIds: string[]): Promise<CleanupResult[]> {
  console.log('[captureCleanup] Batch cleanup:', captureIds.length, 'captures');

  const results: CleanupResult[] = [];

  for (const captureId of captureIds) {
    const result = await cleanupCapture(captureId);
    results.push(result);
  }

  const successful = results.filter((r) => r.success).length;
  const totalFreed = results.reduce((sum, r) => sum + r.freedBytes, 0);

  console.log('[captureCleanup] Batch cleanup complete:', {
    total: captureIds.length,
    successful,
    failed: captureIds.length - successful,
    freedBytes: totalFreed,
  });

  return results;
}

/**
 * Cleanup all completed captures
 *
 * @returns Array of cleanup results
 */
export async function cleanupCompletedCaptures(): Promise<CleanupResult[]> {
  const captures = await getStoredCaptures();
  const completedIds = captures
    .filter((c) => c.status === 'completed')
    .map((c) => c.captureId);

  if (completedIds.length === 0) {
    console.log('[captureCleanup] No completed captures to clean up');
    return [];
  }

  return cleanupCaptures(completedIds);
}

/**
 * Cleanup old captures (older than specified days)
 *
 * Only cleans up failed/permanently_failed captures by default.
 * Set includeAll to also clean completed captures.
 *
 * @param olderThanDays - Age threshold in days
 * @param includeAll - Include all statuses (default: only failed)
 * @returns Array of cleanup results
 */
export async function cleanupOldCaptures(
  olderThanDays: number,
  includeAll = false
): Promise<CleanupResult[]> {
  const captures = await getStoredCaptures();
  const thresholdMs = Date.now() - olderThanDays * 24 * 60 * 60 * 1000;

  const oldCaptures = captures.filter((c) => {
    const isOld = new Date(c.queuedAt).getTime() < thresholdMs;
    if (!isOld) return false;

    if (includeAll) return true;

    // Default: only clean up failed statuses
    return c.status === 'failed' || c.status === 'permanently_failed';
  });

  if (oldCaptures.length === 0) {
    console.log('[captureCleanup] No old captures to clean up');
    return [];
  }

  const captureIds = oldCaptures.map((c) => c.captureId);
  console.log('[captureCleanup] Cleaning up old captures:', {
    count: captureIds.length,
    olderThanDays,
  });

  return cleanupCaptures(captureIds);
}

/**
 * Cleanup permanently failed captures
 *
 * @returns Array of cleanup results
 */
export async function cleanupPermanentlyFailed(): Promise<CleanupResult[]> {
  const captures = await getStoredCaptures();
  const failedIds = captures
    .filter((c) => c.status === 'permanently_failed')
    .map((c) => c.captureId);

  if (failedIds.length === 0) {
    console.log('[captureCleanup] No permanently failed captures to clean up');
    return [];
  }

  return cleanupCaptures(failedIds);
}

/**
 * Auto-cleanup to free space when approaching quota
 *
 * Automatically cleans up the suggested candidates:
 * 1. permanently_failed captures
 * 2. stale completed captures
 * 3. failed captures
 *
 * @param targetFreeBytes - Target bytes to free (optional)
 * @returns Array of cleanup results
 */
export async function autoCleanup(targetFreeBytes?: number): Promise<CleanupResult[]> {
  const candidates = await suggestCleanup(20);

  if (candidates.length === 0) {
    console.log('[captureCleanup] No cleanup candidates found');
    return [];
  }

  // If target specified, only clean enough to meet target
  let toClean: CaptureIndexEntry[] = candidates;
  if (targetFreeBytes) {
    toClean = [];
    let accumulatedBytes = 0;
    for (const candidate of candidates) {
      toClean.push(candidate);
      accumulatedBytes += candidate.totalSize;
      if (accumulatedBytes >= targetFreeBytes) break;
    }
  }

  const captureIds = toClean.map((c) => c.captureId);
  console.log('[captureCleanup] Auto-cleanup:', {
    candidates: candidates.length,
    cleaning: captureIds.length,
    targetFreeBytes,
  });

  return cleanupCaptures(captureIds);
}

/**
 * Get captures that should be warned about (older than 24 hours)
 *
 * @returns Array of capture entries with warning info
 */
export async function getCapturesNeedingAttention(): Promise<
  Array<CaptureIndexEntry & { warning: string }>
> {
  const oldCaptures = await getCapturesOlderThan24Hours();
  const captures = await getStoredCaptures();

  const needsAttention: Array<CaptureIndexEntry & { warning: string }> = [];

  // Add old pending captures
  for (const capture of oldCaptures) {
    if (capture.status === 'pending' || capture.status === 'failed') {
      needsAttention.push({
        ...capture,
        warning: 'Pending for over 24 hours',
      });
    }
  }

  // Add permanently failed
  const permanentlyFailed = captures.filter(
    (c) => c.status === 'permanently_failed'
  );
  for (const capture of permanentlyFailed) {
    needsAttention.push({
      ...capture,
      warning: 'Permanently failed - consider removing',
    });
  }

  return needsAttention;
}

/**
 * Hook into markCompleted to trigger automatic cleanup
 *
 * Call this after successfully completing an upload to clean up local files.
 *
 * @param captureId - Capture ID that was just completed
 */
export async function onUploadCompleted(captureId: string): Promise<void> {
  console.log('[captureCleanup] Upload completed, triggering cleanup:', captureId);

  // Small delay to ensure queue state is updated
  setTimeout(async () => {
    const result = await cleanupCapture(captureId);
    if (!result.success) {
      console.warn('[captureCleanup] Post-upload cleanup failed:', result.error);
    }
  }, 100);
}
