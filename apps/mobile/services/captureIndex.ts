/**
 * Capture Index Service
 *
 * Tracks stored offline captures using AsyncStorage for fast lookup.
 * Provides CRUD operations and integrity validation.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-3)
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import type { CaptureIndexEntry, QueuedCaptureStatus } from '@realitycam/shared';
import { getStoredCaptureIds, loadCaptureFromStorage, validateCaptureIntegrity } from './offlineStorage';

/**
 * AsyncStorage key for the capture index
 */
const INDEX_STORAGE_KEY = 'realitycam-capture-index';

/**
 * In-memory cache of the index for faster reads
 */
let indexCache: CaptureIndexEntry[] | null = null;

/**
 * Load index from AsyncStorage
 */
async function loadIndex(): Promise<CaptureIndexEntry[]> {
  if (indexCache !== null) {
    return indexCache;
  }

  try {
    const stored = await AsyncStorage.getItem(INDEX_STORAGE_KEY);
    if (stored) {
      indexCache = JSON.parse(stored) as CaptureIndexEntry[];
      return indexCache;
    }
  } catch (error) {
    console.warn('[captureIndex] Failed to load index:', error);
  }

  indexCache = [];
  return indexCache;
}

/**
 * Save index to AsyncStorage
 */
async function saveIndex(index: CaptureIndexEntry[]): Promise<void> {
  indexCache = index;

  try {
    await AsyncStorage.setItem(INDEX_STORAGE_KEY, JSON.stringify(index));
  } catch (error) {
    console.error('[captureIndex] Failed to save index:', error);
    throw error;
  }
}

/**
 * Add a capture to the index
 *
 * @param entry - Index entry to add
 */
export async function addToIndex(entry: CaptureIndexEntry): Promise<void> {
  const index = await loadIndex();

  // Check for duplicates
  const existingIdx = index.findIndex((e) => e.captureId === entry.captureId);
  if (existingIdx !== -1) {
    // Update existing entry
    index[existingIdx] = entry;
    console.log('[captureIndex] Updated existing entry:', entry.captureId);
  } else {
    // Add new entry
    index.push(entry);
    console.log('[captureIndex] Added new entry:', entry.captureId);
  }

  await saveIndex(index);
}

/**
 * Remove a capture from the index
 *
 * @param captureId - Capture ID to remove
 */
export async function removeFromIndex(captureId: string): Promise<void> {
  const index = await loadIndex();
  const newIndex = index.filter((entry) => entry.captureId !== captureId);

  if (newIndex.length !== index.length) {
    await saveIndex(newIndex);
    console.log('[captureIndex] Removed entry:', captureId);
  }
}

/**
 * Update status of a capture in the index
 *
 * @param captureId - Capture ID to update
 * @param status - New status
 */
export async function updateIndexStatus(
  captureId: string,
  status: QueuedCaptureStatus
): Promise<void> {
  const index = await loadIndex();
  const entry = index.find((e) => e.captureId === captureId);

  if (entry) {
    entry.status = status;
    await saveIndex(index);
    console.log('[captureIndex] Updated status:', captureId, status);
  }
}

/**
 * Get all stored captures from index
 *
 * @returns Array of index entries sorted by queuedAt (oldest first)
 */
export async function getStoredCaptures(): Promise<CaptureIndexEntry[]> {
  const index = await loadIndex();

  // Sort by queuedAt (oldest first - FIFO)
  return [...index].sort(
    (a, b) => new Date(a.queuedAt).getTime() - new Date(b.queuedAt).getTime()
  );
}

/**
 * Get pending captures from index
 *
 * @returns Array of pending index entries sorted by queuedAt
 */
export async function getPendingCaptures(): Promise<CaptureIndexEntry[]> {
  const captures = await getStoredCaptures();
  return captures.filter((entry) => entry.status === 'pending');
}

/**
 * Get capture by ID from index
 *
 * @param captureId - Capture ID
 * @returns Index entry or undefined
 */
export async function getCaptureFromIndex(captureId: string): Promise<CaptureIndexEntry | undefined> {
  const index = await loadIndex();
  return index.find((entry) => entry.captureId === captureId);
}

/**
 * Check if a capture exists in the index
 *
 * @param captureId - Capture ID
 * @returns True if capture is indexed
 */
export async function isInIndex(captureId: string): Promise<boolean> {
  const entry = await getCaptureFromIndex(captureId);
  return entry !== undefined;
}

/**
 * Get count of captures by status
 *
 * @returns Object with counts per status
 */
export async function getIndexCounts(): Promise<Record<QueuedCaptureStatus, number>> {
  const index = await loadIndex();

  const counts: Record<QueuedCaptureStatus, number> = {
    pending: 0,
    uploading: 0,
    processing: 0,
    completed: 0,
    failed: 0,
    permanently_failed: 0,
  };

  for (const entry of index) {
    counts[entry.status]++;
  }

  return counts;
}

/**
 * Get total storage used by indexed captures
 *
 * @returns Total bytes used
 */
export async function getIndexedStorageUsed(): Promise<number> {
  const index = await loadIndex();
  return index.reduce((total, entry) => total + entry.totalSize, 0);
}

/**
 * Validate index against filesystem and repair inconsistencies
 *
 * Performs:
 * 1. Removes index entries for captures not on disk
 * 2. Adds index entries for captures on disk but not in index
 * 3. Validates integrity of each capture
 *
 * @returns Object with validation results
 */
export async function validateAndRepairIndex(): Promise<{
  validated: number;
  removed: number;
  added: number;
  corrupted: string[];
}> {
  console.log('[captureIndex] Starting index validation and repair');

  const index = await loadIndex();
  const diskCaptureIds = await getStoredCaptureIds();

  const results = {
    validated: 0,
    removed: 0,
    added: 0,
    corrupted: [] as string[],
  };

  // Build sets for efficient lookup
  const indexedIds = new Set(index.map((e) => e.captureId));
  const diskIds = new Set(diskCaptureIds);

  // Remove entries not on disk
  const validEntries: CaptureIndexEntry[] = [];
  for (const entry of index) {
    if (diskIds.has(entry.captureId)) {
      // Validate integrity
      const isValid = await validateCaptureIntegrity(entry.captureId);
      if (isValid) {
        validEntries.push(entry);
        results.validated++;
      } else {
        results.corrupted.push(entry.captureId);
        console.warn('[captureIndex] Corrupted capture:', entry.captureId);
      }
    } else {
      results.removed++;
      console.log('[captureIndex] Removed missing capture:', entry.captureId);
    }
  }

  // Add entries on disk but not in index
  for (const captureId of diskCaptureIds) {
    if (!indexedIds.has(captureId)) {
      // Validate before adding
      const isValid = await validateCaptureIntegrity(captureId);
      if (isValid) {
        // Load capture to get metadata
        const capture = await loadCaptureFromStorage(captureId);
        if (capture) {
          // Estimate size (we don't have exact size without loading metadata)
          const entry: CaptureIndexEntry = {
            captureId,
            queuedAt: capture.createdAt,
            totalSize: 0, // Will be updated when we have full metadata
            status: 'pending',
            isOfflineCapture: true,
          };
          validEntries.push(entry);
          results.added++;
          console.log('[captureIndex] Added missing capture:', captureId);
        }
      } else {
        results.corrupted.push(captureId);
      }
    }
  }

  // Save repaired index
  await saveIndex(validEntries);

  console.log('[captureIndex] Validation complete:', results);
  return results;
}

/**
 * Clear the entire index (for testing/reset)
 */
export async function clearIndex(): Promise<void> {
  indexCache = [];
  await AsyncStorage.removeItem(INDEX_STORAGE_KEY);
  console.log('[captureIndex] Index cleared');
}

/**
 * Refresh index cache from storage
 * Call this if external changes may have occurred
 */
export async function refreshIndexCache(): Promise<void> {
  indexCache = null;
  await loadIndex();
}

/**
 * Get oldest capture from index
 *
 * @returns Oldest pending capture entry or undefined
 */
export async function getOldestPendingCapture(): Promise<CaptureIndexEntry | undefined> {
  const pending = await getPendingCaptures();
  return pending.length > 0 ? pending[0] : undefined;
}

/**
 * Get captures older than specified age
 *
 * @param olderThanHours - Age threshold in hours
 * @returns Array of old capture entries
 */
export async function getCapturesOlderThan(olderThanHours: number): Promise<CaptureIndexEntry[]> {
  const captures = await getStoredCaptures();
  const threshold = Date.now() - olderThanHours * 60 * 60 * 1000;

  return captures.filter(
    (entry) => new Date(entry.queuedAt).getTime() < threshold
  );
}

/**
 * Create an index entry from capture metadata
 */
export function createIndexEntry(
  captureId: string,
  queuedAt: string,
  totalSize: number,
  status: QueuedCaptureStatus = 'pending',
  isOfflineCapture = true
): CaptureIndexEntry {
  return {
    captureId,
    queuedAt,
    totalSize,
    status,
    isOfflineCapture,
  };
}
