/**
 * Storage Quota Service
 *
 * Manages offline storage quota tracking, warnings, and enforcement.
 * Enforces limits: 50 captures max OR 500MB max, warning at 80%.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-5)
 */

import type {
  StorageQuotaStatus,
  StorageQuotaInfo,
  CaptureIndexEntry,
} from '@realitycam/shared';
import { STORAGE_QUOTA_CONFIG } from '@realitycam/shared';
import { getStoredCaptures, getIndexedStorageUsed } from './captureIndex';

const { MAX_CAPTURES, MAX_STORAGE_BYTES, WARNING_THRESHOLD, STALE_CAPTURE_DAYS } =
  STORAGE_QUOTA_CONFIG;

/**
 * Calculate current storage usage and quota status
 *
 * @returns Storage quota information
 */
export async function getStorageUsage(): Promise<StorageQuotaInfo> {
  const captures = await getStoredCaptures();
  const captureCount = captures.length;
  const storageUsedBytes = await getIndexedStorageUsed();

  // Calculate percentages
  const countPercent = (captureCount / MAX_CAPTURES) * 100;
  const storagePercent = (storageUsedBytes / MAX_STORAGE_BYTES) * 100;

  // Use the higher percentage for status calculation
  const usagePercent = Math.max(countPercent, storagePercent);

  // Determine status
  let status: StorageQuotaStatus;
  if (captureCount >= MAX_CAPTURES || storageUsedBytes >= MAX_STORAGE_BYTES) {
    status = 'exceeded';
  } else if (usagePercent >= WARNING_THRESHOLD * 100) {
    status = 'warning';
  } else {
    status = 'ok';
  }

  // Calculate oldest capture age
  let oldestCaptureAgeHours: number | undefined;
  if (captures.length > 0) {
    const oldestQueuedAt = captures[0].queuedAt;
    const ageMs = Date.now() - new Date(oldestQueuedAt).getTime();
    oldestCaptureAgeHours = ageMs / (60 * 60 * 1000);
  }

  return {
    status,
    captureCount,
    maxCaptures: MAX_CAPTURES,
    storageUsedBytes,
    maxStorageBytes: MAX_STORAGE_BYTES,
    usagePercent,
    oldestCaptureAgeHours,
  };
}

/**
 * Check if storage quota allows adding a new capture
 *
 * @param estimatedSize - Estimated size of new capture in bytes (optional)
 * @returns Object with canSave boolean and reason if cannot
 */
export async function checkQuotaForNewCapture(
  estimatedSize?: number
): Promise<{ canSave: boolean; reason?: string }> {
  const usage = await getStorageUsage();

  // Check capture count
  if (usage.captureCount >= MAX_CAPTURES) {
    return {
      canSave: false,
      reason: `Maximum capture limit reached (${MAX_CAPTURES})`,
    };
  }

  // Check storage bytes
  if (usage.storageUsedBytes >= MAX_STORAGE_BYTES) {
    return {
      canSave: false,
      reason: `Storage limit reached (${formatBytes(MAX_STORAGE_BYTES)})`,
    };
  }

  // Check if new capture would exceed storage
  if (estimatedSize && usage.storageUsedBytes + estimatedSize > MAX_STORAGE_BYTES) {
    return {
      canSave: false,
      reason: `Adding this capture would exceed storage limit`,
    };
  }

  return { canSave: true };
}

/**
 * Get quota status only (quick check)
 *
 * @returns Current quota status
 */
export async function checkQuotaStatus(): Promise<StorageQuotaStatus> {
  const usage = await getStorageUsage();
  return usage.status;
}

/**
 * Get cleanup candidates - captures that can be deleted to free space
 *
 * Priority order:
 * 1. permanently_failed captures (oldest first)
 * 2. completed captures older than stale threshold
 * 3. failed captures (oldest first)
 *
 * @param maxResults - Maximum number of candidates to return
 * @returns Array of capture entries that are candidates for cleanup
 */
export async function suggestCleanup(maxResults = 10): Promise<CaptureIndexEntry[]> {
  const captures = await getStoredCaptures();
  const candidates: CaptureIndexEntry[] = [];

  // Priority 1: permanently_failed (oldest first - already sorted)
  const permanentlyFailed = captures.filter(
    (c) => c.status === 'permanently_failed'
  );
  candidates.push(...permanentlyFailed);

  // Priority 2: completed captures older than stale threshold
  const staleThreshold = Date.now() - STALE_CAPTURE_DAYS * 24 * 60 * 60 * 1000;
  const staleCompleted = captures.filter(
    (c) =>
      c.status === 'completed' &&
      new Date(c.queuedAt).getTime() < staleThreshold
  );
  candidates.push(...staleCompleted);

  // Priority 3: failed captures (oldest first)
  const failed = captures.filter((c) => c.status === 'failed');
  candidates.push(...failed);

  // Return up to maxResults, maintaining priority order
  return candidates.slice(0, maxResults);
}

/**
 * Get captures that are stale (older than warning threshold)
 *
 * @returns Array of stale capture entries with their age in hours
 */
export async function getStaleCaptures(): Promise<
  Array<CaptureIndexEntry & { ageHours: number }>
> {
  const captures = await getStoredCaptures();
  const staleThreshold = STALE_CAPTURE_DAYS * 24; // hours
  const now = Date.now();

  return captures
    .map((capture) => {
      const ageMs = now - new Date(capture.queuedAt).getTime();
      const ageHours = ageMs / (60 * 60 * 1000);
      return { ...capture, ageHours };
    })
    .filter((c) => c.ageHours >= staleThreshold);
}

/**
 * Get captures older than 24 hours (for UI warning)
 *
 * @returns Array of old capture entries
 */
export async function getCapturesOlderThan24Hours(): Promise<CaptureIndexEntry[]> {
  const captures = await getStoredCaptures();
  const threshold = Date.now() - 24 * 60 * 60 * 1000;

  return captures.filter(
    (c) => new Date(c.queuedAt).getTime() < threshold
  );
}

/**
 * Calculate storage that would be freed by cleanup
 *
 * @param candidates - Capture entries to consider for cleanup
 * @returns Total bytes that would be freed
 */
export function calculateCleanupSavings(candidates: CaptureIndexEntry[]): number {
  return candidates.reduce((total, entry) => total + entry.totalSize, 0);
}

/**
 * Format bytes as human-readable string
 *
 * @param bytes - Number of bytes
 * @returns Formatted string (e.g., "12.5 MB")
 */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes';

  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

/**
 * Format hours as human-readable duration
 *
 * @param hours - Number of hours
 * @returns Formatted string (e.g., "2 hours ago", "3 days ago")
 */
export function formatAge(hours: number): string {
  if (hours < 1) {
    return 'less than an hour ago';
  } else if (hours < 24) {
    const h = Math.floor(hours);
    return `${h} hour${h === 1 ? '' : 's'} ago`;
  } else {
    const days = Math.floor(hours / 24);
    return `${days} day${days === 1 ? '' : 's'} ago`;
  }
}

/**
 * Get quota config values (for UI display)
 */
export function getQuotaConfig() {
  return {
    maxCaptures: MAX_CAPTURES,
    maxStorageBytes: MAX_STORAGE_BYTES,
    maxStorageFormatted: formatBytes(MAX_STORAGE_BYTES),
    warningThreshold: WARNING_THRESHOLD,
    staleDays: STALE_CAPTURE_DAYS,
  };
}

/**
 * Check if user should be warned about quota
 *
 * @returns Warning info if user should be warned, null otherwise
 */
export async function getQuotaWarning(): Promise<{
  type: 'approaching' | 'exceeded' | 'stale';
  message: string;
} | null> {
  const usage = await getStorageUsage();

  if (usage.status === 'exceeded') {
    return {
      type: 'exceeded',
      message: `Storage limit reached. Delete some captures to continue.`,
    };
  }

  if (usage.status === 'warning') {
    const remaining = MAX_CAPTURES - usage.captureCount;
    const remainingStorage = MAX_STORAGE_BYTES - usage.storageUsedBytes;
    return {
      type: 'approaching',
      message: `Approaching storage limit. ${remaining} captures or ${formatBytes(remainingStorage)} remaining.`,
    };
  }

  // Check for stale captures (older than 24 hours)
  const staleCaptures = await getCapturesOlderThan24Hours();
  if (staleCaptures.length > 0) {
    return {
      type: 'stale',
      message: `${staleCaptures.length} capture${staleCaptures.length === 1 ? '' : 's'} pending upload for over 24 hours.`,
    };
  }

  return null;
}
