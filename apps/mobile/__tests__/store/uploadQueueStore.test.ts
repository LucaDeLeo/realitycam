/**
 * Upload Queue Store Unit Tests
 *
 * Tests for queue state transitions and operations.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic (AC-1, AC-3, AC-5, AC-6)
 */

import { act } from '@testing-library/react-hooks';
import type { ProcessedCapture, UploadError } from '@realitycam/shared';

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    getItem: jest.fn(() => Promise.resolve(null)),
    setItem: jest.fn(() => Promise.resolve()),
    removeItem: jest.fn(() => Promise.resolve()),
  },
}));

// Import after mocking
import { useUploadQueueStore, selectQueueCounts, selectPendingItems, selectCurrentUpload } from '../../store/uploadQueueStore';

/**
 * Create a mock ProcessedCapture for testing
 */
function createMockCapture(id: string = 'test-capture-1'): ProcessedCapture {
  return {
    id,
    photoUri: `file:///photos/${id}.jpg`,
    photoHash: 'abc123hash',
    compressedDepthMap: 'base64compresseddata',
    depthDimensions: { width: 256, height: 192 },
    metadata: {
      captured_at: new Date().toISOString(),
      device_model: 'iPhone 15 Pro',
      photo_hash: 'abc123hash',
      depth_map_dimensions: { width: 256, height: 192 },
    },
    assertion: 'base64assertion',
    status: 'ready',
    createdAt: new Date().toISOString(),
  };
}

describe('uploadQueueStore', () => {
  beforeEach(() => {
    // Reset store state before each test
    const store = useUploadQueueStore.getState();
    store.items.forEach(item => store.cancel(item.capture.id));
    useUploadQueueStore.setState({
      items: [],
      isProcessing: false,
      currentUploadId: null,
      hasHydrated: true,
    });
  });

  describe('enqueue', () => {
    it('adds a capture to the queue with pending status', () => {
      const capture = createMockCapture();
      const { enqueue } = useUploadQueueStore.getState();

      act(() => {
        enqueue(capture);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items).toHaveLength(1);
      expect(state.items[0].capture.id).toBe(capture.id);
      expect(state.items[0].status).toBe('pending');
      expect(state.items[0].retryCount).toBe(0);
      expect(state.items[0].queuedAt).toBeDefined();
    });

    it('adds multiple captures in order', () => {
      const capture1 = createMockCapture('capture-1');
      const capture2 = createMockCapture('capture-2');
      const capture3 = createMockCapture('capture-3');
      const { enqueue } = useUploadQueueStore.getState();

      act(() => {
        enqueue(capture1);
        enqueue(capture2);
        enqueue(capture3);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items).toHaveLength(3);
      expect(state.items[0].capture.id).toBe('capture-1');
      expect(state.items[1].capture.id).toBe('capture-2');
      expect(state.items[2].capture.id).toBe('capture-3');
    });
  });

  describe('setUploading', () => {
    it('transitions item to uploading status', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items[0].status).toBe('uploading');
      expect(state.items[0].progress).toBe(0);
      expect(state.items[0].lastAttemptAt).toBeDefined();
      expect(state.currentUploadId).toBe(capture.id);
    });
  });

  describe('updateProgress', () => {
    it('updates upload progress', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.updateProgress(capture.id, 50);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items[0].progress).toBe(50);
    });

    it('clamps progress to 0-100', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
      });

      act(() => {
        store.updateProgress(capture.id, -10);
      });
      expect(useUploadQueueStore.getState().items[0].progress).toBe(0);

      act(() => {
        store.updateProgress(capture.id, 150);
      });
      expect(useUploadQueueStore.getState().items[0].progress).toBe(100);
    });
  });

  describe('setProcessing', () => {
    it('transitions item to processing status', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.setProcessing(capture.id);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items[0].status).toBe('processing');
      expect(state.items[0].progress).toBe(100);
    });
  });

  describe('markCompleted', () => {
    it('transitions item to completed status with server data', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();
      const captureId = 'server-capture-uuid';
      const verificationUrl = 'https://realitycam.app/verify/123';

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.markCompleted(capture.id, captureId, verificationUrl);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items[0].status).toBe('completed');
      expect(state.items[0].captureId).toBe(captureId);
      expect(state.items[0].verificationUrl).toBe(verificationUrl);
      expect(state.items[0].completedAt).toBeDefined();
      expect(state.items[0].progress).toBe(100);
      expect(state.currentUploadId).toBeNull();
    });
  });

  describe('markFailed', () => {
    it('transitions item to failed status with error', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();
      const error: UploadError = {
        code: 'NETWORK_ERROR',
        message: 'No internet connection',
      };

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.markFailed(capture.id, error);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items[0].status).toBe('failed');
      expect(state.items[0].error).toEqual(error);
      expect(state.items[0].retryCount).toBe(1);
      expect(state.items[0].lastAttemptAt).toBeDefined();
      expect(state.items[0].progress).toBeUndefined();
      expect(state.currentUploadId).toBeNull();
    });

    it('increments retry count on each failure', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();
      const error: UploadError = {
        code: 'SERVER_ERROR',
        message: 'Internal error',
        statusCode: 500,
      };

      act(() => {
        store.enqueue(capture);
      });

      // Fail 3 times
      for (let i = 0; i < 3; i++) {
        act(() => {
          store.setUploading(capture.id);
          store.markFailed(capture.id, error);
        });
        // Reset status to allow another retry
        useUploadQueueStore.setState((state) => ({
          items: state.items.map((item) =>
            item.capture.id === capture.id
              ? { ...item, status: 'pending' as const }
              : item
          ),
        }));
      }

      const state = useUploadQueueStore.getState();
      expect(state.items[0].retryCount).toBe(3);
    });
  });

  describe('markPermanentlyFailed', () => {
    it('transitions item to permanently_failed status', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.markPermanentlyFailed(capture.id);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items[0].status).toBe('permanently_failed');
      expect(state.currentUploadId).toBeNull();
    });
  });

  describe('retry', () => {
    it('moves failed item to front of queue with pending status', () => {
      const capture1 = createMockCapture('capture-1');
      const capture2 = createMockCapture('capture-2');
      const store = useUploadQueueStore.getState();
      const error: UploadError = { code: 'NETWORK_ERROR', message: 'No connection' };

      act(() => {
        store.enqueue(capture1);
        store.enqueue(capture2);
        store.setUploading(capture1.id);
        store.markFailed(capture1.id, error);
      });

      // capture-1 is now at the end with failed status
      expect(useUploadQueueStore.getState().items[0].status).toBe('failed');

      act(() => {
        store.retry(capture1.id);
      });

      const state = useUploadQueueStore.getState();
      // capture-1 should be at front with pending status
      expect(state.items[0].capture.id).toBe('capture-1');
      expect(state.items[0].status).toBe('pending');
      // retry count should be preserved
      expect(state.items[0].retryCount).toBe(1);
      // error should be cleared
      expect(state.items[0].error).toBeUndefined();
    });

    it('does not retry item that is not in failed status', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.retry(capture.id); // Should be ignored - item is pending not failed
      });

      const state = useUploadQueueStore.getState();
      expect(state.items[0].status).toBe('pending');
    });
  });

  describe('cancel', () => {
    it('removes pending item from queue', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.cancel(capture.id);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items).toHaveLength(0);
    });

    it('removes failed item from queue', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();
      const error: UploadError = { code: 'NETWORK_ERROR', message: 'No connection' };

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.markFailed(capture.id, error);
        store.cancel(capture.id);
      });

      const state = useUploadQueueStore.getState();
      expect(state.items).toHaveLength(0);
    });

    it('does not cancel uploading item', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.cancel(capture.id); // Should be ignored - item is uploading
      });

      const state = useUploadQueueStore.getState();
      expect(state.items).toHaveLength(1);
      expect(state.items[0].status).toBe('uploading');
    });

    it('does not cancel processing item', () => {
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture);
        store.setUploading(capture.id);
        store.setProcessing(capture.id);
        store.cancel(capture.id); // Should be ignored - item is processing
      });

      const state = useUploadQueueStore.getState();
      expect(state.items).toHaveLength(1);
      expect(state.items[0].status).toBe('processing');
    });
  });

  describe('getNextPending', () => {
    it('returns first pending item', () => {
      const capture1 = createMockCapture('capture-1');
      const capture2 = createMockCapture('capture-2');
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture1);
        store.enqueue(capture2);
      });

      const nextPending = store.getNextPending();
      expect(nextPending?.capture.id).toBe('capture-1');
    });

    it('skips non-pending items', () => {
      const capture1 = createMockCapture('capture-1');
      const capture2 = createMockCapture('capture-2');
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture1);
        store.enqueue(capture2);
        store.setUploading(capture1.id);
      });

      const nextPending = useUploadQueueStore.getState().getNextPending();
      expect(nextPending?.capture.id).toBe('capture-2');
    });

    it('returns undefined when no pending items', () => {
      const store = useUploadQueueStore.getState();
      expect(store.getNextPending()).toBeUndefined();
    });
  });

  describe('clearCompleted', () => {
    it('removes all completed items', () => {
      const capture1 = createMockCapture('capture-1');
      const capture2 = createMockCapture('capture-2');
      const capture3 = createMockCapture('capture-3');
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(capture1);
        store.enqueue(capture2);
        store.enqueue(capture3);
        store.setUploading(capture1.id);
        store.markCompleted(capture1.id, 'server-1', 'https://verify/1');
        store.setUploading(capture2.id);
        store.markCompleted(capture2.id, 'server-2', 'https://verify/2');
      });

      expect(useUploadQueueStore.getState().items).toHaveLength(3);

      act(() => {
        store.clearCompleted();
      });

      const state = useUploadQueueStore.getState();
      expect(state.items).toHaveLength(1);
      expect(state.items[0].capture.id).toBe('capture-3');
    });
  });

  describe('selectors', () => {
    it('selectQueueCounts returns correct counts', () => {
      const store = useUploadQueueStore.getState();
      const error: UploadError = { code: 'NETWORK_ERROR', message: 'No connection' };

      act(() => {
        store.enqueue(createMockCapture('pending-1'));
        store.enqueue(createMockCapture('pending-2'));
        store.enqueue(createMockCapture('uploading-1'));
        store.enqueue(createMockCapture('completed-1'));
        store.enqueue(createMockCapture('failed-1'));

        store.setUploading('uploading-1');
        store.setUploading('completed-1');
        store.markCompleted('completed-1', 'server-1', 'https://verify/1');
        store.setUploading('failed-1');
        store.markFailed('failed-1', error);
      });

      const counts = selectQueueCounts(useUploadQueueStore.getState());
      expect(counts.pending).toBe(2);
      expect(counts.uploading).toBe(1);
      expect(counts.completed).toBe(1);
      expect(counts.failed).toBe(1);
      expect(counts.total).toBe(5);
    });

    it('selectPendingItems returns only pending items', () => {
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(createMockCapture('pending-1'));
        store.enqueue(createMockCapture('uploading-1'));
        store.setUploading('uploading-1');
      });

      const pending = selectPendingItems(useUploadQueueStore.getState());
      expect(pending).toHaveLength(1);
      expect(pending[0].capture.id).toBe('pending-1');
    });

    it('selectCurrentUpload returns current upload', () => {
      const store = useUploadQueueStore.getState();

      act(() => {
        store.enqueue(createMockCapture('capture-1'));
        store.setUploading('capture-1');
      });

      const current = selectCurrentUpload(useUploadQueueStore.getState());
      expect(current?.capture.id).toBe('capture-1');
      expect(current?.status).toBe('uploading');
    });

    it('selectCurrentUpload returns null when no upload', () => {
      const current = selectCurrentUpload(useUploadQueueStore.getState());
      expect(current).toBeNull();
    });
  });
});
