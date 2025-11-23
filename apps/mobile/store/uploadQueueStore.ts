/**
 * Upload Queue Store
 *
 * Zustand store for managing upload queue state with AsyncStorage persistence.
 * Handles queue operations atomically to prevent partial state.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic (AC-1, AC-3, AC-5, AC-6)
 */

import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type {
  ProcessedCapture,
  QueuedCapture,
  QueuedCaptureStatus,
  UploadQueueState,
  UploadQueueActions,
  UploadError,
  CaptureStorageLocation,
  OfflineQueuedCapture,
} from '@realitycam/shared';

/**
 * Extended queued capture with offline storage support
 */
interface ExtendedQueuedCapture extends QueuedCapture {
  /** Where capture data is stored (memory or disk) */
  storageLocation?: CaptureStorageLocation;
  /** True if capture was created while offline */
  isOfflineCapture?: boolean;
}

/**
 * Combined store type with state and actions
 */
type UploadQueueStore = UploadQueueState & UploadQueueActions & {
  /** Whether store has been hydrated from AsyncStorage */
  hasHydrated: boolean;
  /** Set hydration status */
  setHasHydrated: (hydrated: boolean) => void;
  /** Enqueue with offline storage support */
  enqueueOffline: (capture: ProcessedCapture, storageLocation: CaptureStorageLocation) => void;
  /** Restore captures from disk storage on app start */
  restoreFromDiskStorage: () => Promise<void>;
  /** Get extended capture with storage info */
  getExtendedCapture: (id: string) => ExtendedQueuedCapture | undefined;
};

/**
 * AsyncStorage key for persistence
 */
const STORAGE_KEY = 'realitycam-upload-queue';

/**
 * Upload Queue Store
 *
 * Features:
 * - Sequential queue processing (one at a time)
 * - Atomic state operations
 * - AsyncStorage persistence
 * - Status tracking for each item
 * - Manual retry and cancel support
 *
 * @example
 * ```tsx
 * // Add to queue
 * const { enqueue, items } = useUploadQueueStore();
 * enqueue(processedCapture);
 *
 * // Get pending items
 * const pendingItems = items.filter(item => item.status === 'pending');
 *
 * // Retry failed item
 * const { retry } = useUploadQueueStore();
 * retry(failedItemId);
 * ```
 */
export const useUploadQueueStore = create<UploadQueueStore>()(
  persist(
    (set, get) => ({
      // === State ===
      items: [],
      isProcessing: false,
      currentUploadId: null,
      hasHydrated: false,

      // === Hydration ===
      setHasHydrated: (hydrated: boolean) => set({ hasHydrated: hydrated }),

      // === Queue Operations ===

      /**
       * Add a processed capture to the queue
       * Capture enters with 'pending' status
       */
      enqueue: (capture: ProcessedCapture) => {
        const now = new Date().toISOString();
        const queuedCapture: ExtendedQueuedCapture = {
          capture,
          status: 'pending',
          retryCount: 0,
          queuedAt: now,
          storageLocation: 'memory',
          isOfflineCapture: false,
        };

        set((state) => ({
          items: [...state.items, queuedCapture],
        }));

        console.log('[uploadQueueStore] Enqueued capture:', {
          id: capture.id,
          queueLength: get().items.length,
        });
      },

      /**
       * Add a processed capture to the queue with offline storage
       * Used when network is unavailable and capture is stored on disk
       */
      enqueueOffline: (capture: ProcessedCapture, storageLocation: CaptureStorageLocation) => {
        const now = new Date().toISOString();
        const queuedCapture: ExtendedQueuedCapture = {
          capture,
          status: 'pending',
          retryCount: 0,
          queuedAt: now,
          storageLocation,
          isOfflineCapture: true,
        };

        set((state) => ({
          items: [...state.items, queuedCapture],
        }));

        console.log('[uploadQueueStore] Enqueued offline capture:', {
          id: capture.id,
          storageLocation,
          queueLength: get().items.length,
        });
      },

      /**
       * Restore captures from disk storage on app start
       * Called during hydration to restore offline captures
       */
      restoreFromDiskStorage: async () => {
        // Import dynamically to avoid circular dependencies
        const { getStoredCaptures } = await import('../services/captureIndex');
        const { loadCaptureFromStorage } = await import('../services/offlineStorage');

        console.log('[uploadQueueStore] Restoring captures from disk storage');

        try {
          const storedCaptures = await getStoredCaptures();
          const currentItems = get().items;
          const currentIds = new Set(currentItems.map((item) => item.capture.id));

          let restoredCount = 0;
          for (const entry of storedCaptures) {
            // Skip if already in queue
            if (currentIds.has(entry.captureId)) {
              continue;
            }

            // Only restore pending/failed captures
            if (entry.status !== 'pending' && entry.status !== 'failed') {
              continue;
            }

            // Load capture data from disk
            const capture = await loadCaptureFromStorage(entry.captureId);
            if (capture) {
              const queuedCapture: ExtendedQueuedCapture = {
                capture,
                status: 'pending',
                retryCount: 0,
                queuedAt: entry.queuedAt,
                storageLocation: 'disk',
                isOfflineCapture: true,
              };

              set((state) => ({
                items: [...state.items, queuedCapture],
              }));

              restoredCount++;
            }
          }

          console.log('[uploadQueueStore] Restored captures from disk:', restoredCount);
        } catch (error) {
          console.error('[uploadQueueStore] Failed to restore from disk:', error);
        }
      },

      /**
       * Get extended capture with storage info
       */
      getExtendedCapture: (id: string): ExtendedQueuedCapture | undefined => {
        return get().items.find((item) => item.capture.id === id) as ExtendedQueuedCapture | undefined;
      },

      /**
       * Remove the first item from queue
       * Used internally after completion or permanent failure
       */
      dequeue: () => {
        set((state) => ({
          items: state.items.slice(1),
        }));
      },

      /**
       * Mark an item as completed with server response data
       */
      markCompleted: (id: string, captureId: string, verificationUrl: string) => {
        const now = new Date().toISOString();

        // Get item before state change to check if it was an offline capture
        const item = get().items.find((i) => i.capture.id === id) as ExtendedQueuedCapture | undefined;
        const wasOfflineCapture = item?.isOfflineCapture === true;

        set((state) => ({
          items: state.items.map((item) =>
            item.capture.id === id
              ? {
                  ...item,
                  status: 'completed' as QueuedCaptureStatus,
                  captureId,
                  verificationUrl,
                  completedAt: now,
                  progress: 100,
                  error: undefined,
                }
              : item
          ),
          currentUploadId: state.currentUploadId === id ? null : state.currentUploadId,
        }));

        console.log('[uploadQueueStore] Marked completed:', {
          id,
          captureId,
          verificationUrl,
          wasOfflineCapture,
        });

        // Trigger cleanup for offline captures (Story 4.3 AC-6)
        if (wasOfflineCapture) {
          import('../services/captureCleanup')
            .then(({ onUploadCompleted }) => onUploadCompleted(id))
            .catch((err) => console.warn('[uploadQueueStore] Cleanup trigger failed:', err));
        }
      },

      /**
       * Mark an item as failed with error details
       * Item can still be retried unless max retries exceeded
       */
      markFailed: (id: string, error: UploadError) => {
        const now = new Date().toISOString();

        set((state) => ({
          items: state.items.map((item) =>
            item.capture.id === id
              ? {
                  ...item,
                  status: 'failed' as QueuedCaptureStatus,
                  error,
                  lastAttemptAt: now,
                  retryCount: item.retryCount + 1,
                  progress: undefined,
                }
              : item
          ),
          currentUploadId: state.currentUploadId === id ? null : state.currentUploadId,
        }));

        console.log('[uploadQueueStore] Marked failed:', {
          id,
          error: error.code,
          message: error.message,
        });
      },

      /**
       * Mark an item as permanently failed (max retries exceeded)
       * Item will not be automatically retried
       */
      markPermanentlyFailed: (id: string) => {
        set((state) => ({
          items: state.items.map((item) =>
            item.capture.id === id
              ? {
                  ...item,
                  status: 'permanently_failed' as QueuedCaptureStatus,
                  progress: undefined,
                }
              : item
          ),
          currentUploadId: state.currentUploadId === id ? null : state.currentUploadId,
        }));

        console.log('[uploadQueueStore] Marked permanently failed:', { id });
      },

      /**
       * Update upload progress for an item (0-100)
       */
      updateProgress: (id: string, progress: number) => {
        set((state) => ({
          items: state.items.map((item) =>
            item.capture.id === id
              ? { ...item, progress: Math.min(100, Math.max(0, progress)) }
              : item
          ),
        }));
      },

      /**
       * Set item status to 'uploading'
       */
      setUploading: (id: string) => {
        const now = new Date().toISOString();

        set((state) => ({
          items: state.items.map((item) =>
            item.capture.id === id
              ? {
                  ...item,
                  status: 'uploading' as QueuedCaptureStatus,
                  lastAttemptAt: now,
                  progress: 0,
                }
              : item
          ),
          currentUploadId: id,
        }));

        console.log('[uploadQueueStore] Set uploading:', { id });
      },

      /**
       * Set item status to 'processing' (server-side processing)
       */
      setProcessing: (id: string) => {
        set((state) => ({
          items: state.items.map((item) =>
            item.capture.id === id
              ? {
                  ...item,
                  status: 'processing' as QueuedCaptureStatus,
                  progress: 100,
                }
              : item
          ),
        }));

        console.log('[uploadQueueStore] Set processing:', { id });
      },

      /**
       * Retry a failed item
       * Moves item to front of queue while preserving retry count
       */
      retry: (id: string) => {
        const state = get();
        const itemIndex = state.items.findIndex((item) => item.capture.id === id);

        if (itemIndex === -1) {
          console.warn('[uploadQueueStore] Cannot retry - item not found:', { id });
          return;
        }

        const item = state.items[itemIndex];
        if (item.status !== 'failed') {
          console.warn('[uploadQueueStore] Cannot retry - item not in failed status:', {
            id,
            status: item.status,
          });
          return;
        }

        // Remove item and add to front with pending status
        const newItems = [...state.items];
        newItems.splice(itemIndex, 1);

        const retriedItem: QueuedCapture = {
          ...item,
          status: 'pending',
          error: undefined,
          progress: undefined,
        };

        set({
          items: [retriedItem, ...newItems],
        });

        console.log('[uploadQueueStore] Retry scheduled:', {
          id,
          retryCount: item.retryCount,
          newQueuePosition: 0,
        });
      },

      /**
       * Cancel and remove an item from queue
       * Only works for pending or failed items
       */
      cancel: (id: string) => {
        const state = get();
        const item = state.items.find((item) => item.capture.id === id);

        if (!item) {
          console.warn('[uploadQueueStore] Cannot cancel - item not found:', { id });
          return;
        }

        if (item.status === 'uploading' || item.status === 'processing') {
          console.warn('[uploadQueueStore] Cannot cancel - item is active:', {
            id,
            status: item.status,
          });
          return;
        }

        set((state) => ({
          items: state.items.filter((item) => item.capture.id !== id),
        }));

        console.log('[uploadQueueStore] Cancelled:', { id });
      },

      /**
       * Set processing flag
       */
      setIsProcessing: (isProcessing: boolean) => {
        set({ isProcessing });
      },

      /**
       * Set current upload ID
       */
      setCurrentUploadId: (id: string | null) => {
        set({ currentUploadId: id });
      },

      /**
       * Get next pending item in queue
       * Returns the first item with 'pending' status
       */
      getNextPending: (): QueuedCapture | undefined => {
        return get().items.find((item) => item.status === 'pending');
      },

      /**
       * Clear all completed items from queue
       */
      clearCompleted: () => {
        set((state) => ({
          items: state.items.filter((item) => item.status !== 'completed'),
        }));

        console.log('[uploadQueueStore] Cleared completed items');
      },
    }),
    {
      name: STORAGE_KEY,
      storage: createJSONStorage(() => AsyncStorage),
      // Only persist the items array - transient state is not persisted
      partialize: (state) => ({
        items: state.items,
      }),
      onRehydrateStorage: () => (state) => {
        // Called when hydration completes
        console.log('[uploadQueueStore] Hydration complete, items:', state?.items?.length ?? 0);
        state?.setHasHydrated(true);

        // Reset any items that were uploading/processing when app was killed
        // They need to be retried
        if (state?.items) {
          const itemsNeedingReset = state.items.filter(
            (item) => item.status === 'uploading' || item.status === 'processing'
          );
          if (itemsNeedingReset.length > 0) {
            console.log('[uploadQueueStore] Resetting interrupted uploads:', itemsNeedingReset.length);
            state.items = state.items.map((item) => {
              if (item.status === 'uploading' || item.status === 'processing') {
                return {
                  ...item,
                  status: 'pending' as QueuedCaptureStatus,
                  progress: undefined,
                };
              }
              return item;
            });
          }
        }
      },
    }
  )
);

// === Selectors for efficient component subscriptions ===

/**
 * Select only pending items
 */
export const selectPendingItems = (state: UploadQueueStore) =>
  state.items.filter((item) => item.status === 'pending');

/**
 * Select only failed items (excludes permanently_failed)
 */
export const selectFailedItems = (state: UploadQueueStore) =>
  state.items.filter((item) => item.status === 'failed');

/**
 * Select only completed items
 */
export const selectCompletedItems = (state: UploadQueueStore) =>
  state.items.filter((item) => item.status === 'completed');

/**
 * Select count of items by status
 */
export const selectQueueCounts = (state: UploadQueueStore) => ({
  pending: state.items.filter((item) => item.status === 'pending').length,
  uploading: state.items.filter((item) => item.status === 'uploading').length,
  processing: state.items.filter((item) => item.status === 'processing').length,
  completed: state.items.filter((item) => item.status === 'completed').length,
  failed: state.items.filter((item) => item.status === 'failed').length,
  permanentlyFailed: state.items.filter((item) => item.status === 'permanently_failed').length,
  total: state.items.length,
});

/**
 * Select current upload (if any)
 */
export const selectCurrentUpload = (state: UploadQueueStore) => {
  if (!state.currentUploadId) return null;
  return state.items.find((item) => item.capture.id === state.currentUploadId);
};

/**
 * Select only offline captures (stored on disk)
 */
export const selectOfflineCaptures = (state: UploadQueueStore) =>
  state.items.filter((item) => {
    const extended = item as ExtendedQueuedCapture;
    return extended.isOfflineCapture === true;
  });

/**
 * Select offline capture counts
 */
export const selectOfflineCounts = (state: UploadQueueStore) => {
  const offline = selectOfflineCaptures(state);
  return {
    total: offline.length,
    pending: offline.filter((item) => item.status === 'pending').length,
    failed: offline.filter((item) => item.status === 'failed').length,
    permanentlyFailed: offline.filter((item) => item.status === 'permanently_failed').length,
  };
};

// Export the extended type for external use
export type { ExtendedQueuedCapture };
