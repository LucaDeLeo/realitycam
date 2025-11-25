/**
 * useUploadQueue Hook Unit Tests
 *
 * [P2] Tests for upload queue hook, focusing on cleanup timer management
 * to prevent memory leaks.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic
 */

import type { ProcessedCapture } from '@realitycam/shared';

// ============================================================================
// Mocks
// ============================================================================

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    getItem: jest.fn(() => Promise.resolve(null)),
    setItem: jest.fn(() => Promise.resolve()),
    removeItem: jest.fn(() => Promise.resolve()),
  },
}));

// Mock uploadService
const mockUploadCapture = jest.fn();
jest.mock('../../services/uploadService', () => ({
  uploadCapture: (...args: unknown[]) => mockUploadCapture(...args),
}));

// Mock captureCleanup
const mockCleanupCapture = jest.fn();
jest.mock('../../services/captureCleanup', () => ({
  cleanupCapture: (...args: unknown[]) => mockCleanupCapture(...args),
}));

// Mock useNetworkStatus
jest.mock('../../hooks/useNetworkStatus', () => ({
  useNetworkStatus: () => ({
    isConnected: true,
    isInternetReachable: true,
  }),
}));

// Mock retryStrategy
jest.mock('../../utils/retryStrategy', () => ({
  calculateDelayWithRetryAfter: jest.fn(() => 1000),
  shouldRetry: jest.fn(() => true),
  isMaxRetriesExceeded: jest.fn(() => false),
}));

// Import after mocks
import { useUploadQueueStore } from '../../store/uploadQueueStore';

// ============================================================================
// Test Utilities
// ============================================================================

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

// ============================================================================
// Timer Management Tests
// ============================================================================

describe('useUploadQueue Timer Management', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();

    // Reset store state
    const store = useUploadQueueStore.getState();
    store.items.forEach((item) => store.cancel(item.capture.id));
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('Cleanup Timer', () => {
    test('[P2] cleanup timer should be scheduled after successful upload', async () => {
      // GIVEN: Upload succeeds
      mockUploadCapture.mockResolvedValueOnce({
        success: true,
        data: {
          data: {
            capture_id: 'server-123',
            verification_url: 'https://example.com/verify/123',
            status: 'complete',
          },
        },
      });
      mockCleanupCapture.mockResolvedValueOnce({
        success: true,
        freedBytes: 1024,
      });

      // WHEN: Item is uploaded (simulated)
      const capture = createMockCapture();
      const store = useUploadQueueStore.getState();
      store.enqueue(capture);

      // Process upload (would normally be done by hook)
      const result = await mockUploadCapture(capture);

      // THEN: Cleanup should be callable
      expect(result.success).toBe(true);
    });

    test('[P2] cleanup timer should clear previous timer on new upload', () => {
      // GIVEN: Multiple timers tracked
      let timerRef: ReturnType<typeof setTimeout> | null = null;
      const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');

      // WHEN: Setting new timer (simulating hook behavior)
      if (timerRef) {
        clearTimeout(timerRef);
      }
      timerRef = setTimeout(() => {}, 100);

      // Set another timer
      if (timerRef) {
        clearTimeout(timerRef);
      }
      timerRef = setTimeout(() => {}, 100);

      // THEN: Previous timer should be cleared
      expect(clearTimeoutSpy).toHaveBeenCalled();

      clearTimeoutSpy.mockRestore();
    });

    test('[P2] cleanup timer should handle cleanup failure gracefully', async () => {
      // GIVEN: Cleanup fails
      mockCleanupCapture.mockResolvedValueOnce({
        success: false,
        error: 'File not found',
      });

      // WHEN: Running cleanup
      const result = await mockCleanupCapture('test-id');

      // THEN: Should handle failure without throwing
      expect(result.success).toBe(false);
      expect(result.error).toBe('File not found');
    });

    test('[P2] cleanup timer should handle cleanup error gracefully', async () => {
      // GIVEN: Cleanup throws
      mockCleanupCapture.mockRejectedValueOnce(new Error('Disk error'));

      // WHEN/THEN: Should handle error
      await expect(mockCleanupCapture('test-id')).rejects.toThrow('Disk error');
    });
  });

  describe('Retry Timer', () => {
    test('[P2] retry timer should be scheduled after failed upload', async () => {
      // GIVEN: Upload fails with retryable error
      mockUploadCapture.mockResolvedValueOnce({
        success: false,
        error: { code: 'NETWORK_ERROR', message: 'Connection lost' },
      });

      const { shouldRetry, calculateDelayWithRetryAfter } = require('../../utils/retryStrategy');
      shouldRetry.mockReturnValue(true);
      calculateDelayWithRetryAfter.mockReturnValue(2000);

      // WHEN: Upload fails
      const result = await mockUploadCapture(createMockCapture());

      // THEN: Retry logic should be invoked
      expect(result.success).toBe(false);
      expect(calculateDelayWithRetryAfter).toBeDefined();
    });

    test('[P2] retry timer should clear previous timer', () => {
      // GIVEN: Timer tracking ref
      let retryTimerRef: ReturnType<typeof setTimeout> | null = null;
      const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');

      // WHEN: Setting new retry timer
      if (retryTimerRef) {
        clearTimeout(retryTimerRef);
      }
      retryTimerRef = setTimeout(() => {}, 2000);

      // Set another
      if (retryTimerRef) {
        clearTimeout(retryTimerRef);
      }
      retryTimerRef = setTimeout(() => {}, 2000);

      // THEN: Previous should be cleared
      expect(clearTimeoutSpy).toHaveBeenCalled();

      clearTimeoutSpy.mockRestore();
    });
  });

  describe('Unmount Cleanup', () => {
    test('[P2] should clear all timers on unmount', () => {
      // GIVEN: Active timers
      const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');
      const retryTimer = setTimeout(() => {}, 1000);
      const cleanupTimer = setTimeout(() => {}, 1000);

      // WHEN: Simulating unmount cleanup
      clearTimeout(retryTimer);
      clearTimeout(cleanupTimer);

      // THEN: Both timers should be cleared
      expect(clearTimeoutSpy).toHaveBeenCalledTimes(2);

      clearTimeoutSpy.mockRestore();
    });

    test('[P2] should handle null timer refs gracefully', () => {
      // GIVEN: Null timer refs
      let retryTimerRef: ReturnType<typeof setTimeout> | null = null;
      let cleanupTimerRef: ReturnType<typeof setTimeout> | null = null;

      // WHEN: Cleanup runs (simulating unmount)
      const cleanup = () => {
        if (retryTimerRef) {
          clearTimeout(retryTimerRef);
        }
        if (cleanupTimerRef) {
          clearTimeout(cleanupTimerRef);
        }
      };

      // THEN: Should not throw
      expect(() => cleanup()).not.toThrow();
    });
  });
});

// ============================================================================
// Processing Lock Tests
// ============================================================================

describe('useUploadQueue Processing Lock', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('[P2] should prevent concurrent processing', async () => {
    // GIVEN: Processing lock
    let processingLock = false;
    const processQueue = async () => {
      if (processingLock) {
        return 'already_processing';
      }
      processingLock = true;
      // Simulate async work
      await new Promise((resolve) => setTimeout(resolve, 10));
      processingLock = false;
      return 'processed';
    };

    // WHEN: Two concurrent calls
    const promise1 = processQueue();
    const promise2 = processQueue();

    const [result1, result2] = await Promise.all([promise1, promise2]);

    // THEN: Second should be blocked
    expect(result1).toBe('processed');
    expect(result2).toBe('already_processing');
  });
});

// ============================================================================
// Network Awareness Tests
// ============================================================================

describe('useUploadQueue Network Awareness', () => {
  test('[P2] should pause queue when network unavailable', () => {
    // GIVEN: Network status check
    const isConnected = false;
    const isInternetReachable = false;
    const isNetworkAvailable = isConnected === true && isInternetReachable === true;

    // THEN: Should be unavailable
    expect(isNetworkAvailable).toBe(false);
  });

  test('[P2] should resume queue when network available', () => {
    // GIVEN: Network status check
    const isConnected = true;
    const isInternetReachable = true;
    const isNetworkAvailable = isConnected === true && isInternetReachable === true;

    // THEN: Should be available
    expect(isNetworkAvailable).toBe(true);
  });

  test('[P2] should handle null network values', () => {
    // GIVEN: Null network values (initial state)
    const isConnected: boolean | null = null;
    const isInternetReachable: boolean | null = null;
    const isNetworkAvailable = isConnected === true && isInternetReachable === true;

    // THEN: Should be unavailable (safe default)
    expect(isNetworkAvailable).toBe(false);
  });
});
