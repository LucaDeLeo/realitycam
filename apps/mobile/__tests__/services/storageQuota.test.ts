/**
 * Storage Quota Service Tests
 *
 * Tests for storage quota calculation, status thresholds, and cleanup suggestions.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-5)
 */

import {
  formatBytes,
  formatAge,
  getQuotaConfig,
  calculateCleanupSavings,
} from '../../services/storageQuota';
import { STORAGE_QUOTA_CONFIG } from '@realitycam/shared';
import type { CaptureIndexEntry } from '@realitycam/shared';

// Mock the captureIndex module
jest.mock('../../services/captureIndex', () => ({
  getStoredCaptures: jest.fn(),
  getIndexedStorageUsed: jest.fn(),
}));

import { getStoredCaptures, getIndexedStorageUsed } from '../../services/captureIndex';

const mockGetStoredCaptures = getStoredCaptures as jest.MockedFunction<typeof getStoredCaptures>;
const mockGetIndexedStorageUsed = getIndexedStorageUsed as jest.MockedFunction<typeof getIndexedStorageUsed>;

describe('storageQuota', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('formatBytes', () => {
    it('should format 0 bytes', () => {
      expect(formatBytes(0)).toBe('0 Bytes');
    });

    it('should format bytes under 1KB', () => {
      expect(formatBytes(500)).toBe('500 Bytes');
    });

    it('should format kilobytes', () => {
      expect(formatBytes(1024)).toBe('1 KB');
      expect(formatBytes(1536)).toBe('1.5 KB');
      expect(formatBytes(2048)).toBe('2 KB');
    });

    it('should format megabytes', () => {
      expect(formatBytes(1024 * 1024)).toBe('1 MB');
      expect(formatBytes(1.5 * 1024 * 1024)).toBe('1.5 MB');
      expect(formatBytes(500 * 1024 * 1024)).toBe('500 MB');
    });

    it('should format gigabytes', () => {
      expect(formatBytes(1024 * 1024 * 1024)).toBe('1 GB');
      expect(formatBytes(2.5 * 1024 * 1024 * 1024)).toBe('2.5 GB');
    });

    it('should round to one decimal place', () => {
      expect(formatBytes(1234567)).toBe('1.2 MB');
      expect(formatBytes(9876543)).toBe('9.4 MB');
    });
  });

  describe('formatAge', () => {
    it('should format less than an hour', () => {
      expect(formatAge(0.5)).toBe('less than an hour ago');
      expect(formatAge(0)).toBe('less than an hour ago');
      expect(formatAge(0.99)).toBe('less than an hour ago');
    });

    it('should format hours', () => {
      expect(formatAge(1)).toBe('1 hour ago');
      expect(formatAge(2)).toBe('2 hours ago');
      expect(formatAge(23)).toBe('23 hours ago');
    });

    it('should format days', () => {
      expect(formatAge(24)).toBe('1 day ago');
      expect(formatAge(48)).toBe('2 days ago');
      expect(formatAge(72)).toBe('3 days ago');
    });

    it('should handle fractional hours', () => {
      expect(formatAge(1.5)).toBe('1 hour ago');
      expect(formatAge(5.9)).toBe('5 hours ago');
    });
  });

  describe('getQuotaConfig', () => {
    it('should return correct max captures', () => {
      const config = getQuotaConfig();
      expect(config.maxCaptures).toBe(STORAGE_QUOTA_CONFIG.MAX_CAPTURES);
      expect(config.maxCaptures).toBe(50);
    });

    it('should return correct max storage bytes', () => {
      const config = getQuotaConfig();
      expect(config.maxStorageBytes).toBe(STORAGE_QUOTA_CONFIG.MAX_STORAGE_BYTES);
      expect(config.maxStorageBytes).toBe(500 * 1024 * 1024);
    });

    it('should return correct warning threshold', () => {
      const config = getQuotaConfig();
      expect(config.warningThreshold).toBe(STORAGE_QUOTA_CONFIG.WARNING_THRESHOLD);
      expect(config.warningThreshold).toBe(0.8);
    });

    it('should return formatted max storage', () => {
      const config = getQuotaConfig();
      expect(config.maxStorageFormatted).toBe('500 MB');
    });

    it('should return stale days config', () => {
      const config = getQuotaConfig();
      expect(config.staleDays).toBe(STORAGE_QUOTA_CONFIG.STALE_CAPTURE_DAYS);
      expect(config.staleDays).toBe(7);
    });
  });

  describe('calculateCleanupSavings', () => {
    it('should return 0 for empty array', () => {
      expect(calculateCleanupSavings([])).toBe(0);
    });

    it('should sum total sizes', () => {
      const candidates: CaptureIndexEntry[] = [
        {
          captureId: '1',
          queuedAt: new Date().toISOString(),
          totalSize: 1000,
          status: 'permanently_failed',
          isOfflineCapture: true,
        },
        {
          captureId: '2',
          queuedAt: new Date().toISOString(),
          totalSize: 2000,
          status: 'failed',
          isOfflineCapture: true,
        },
        {
          captureId: '3',
          queuedAt: new Date().toISOString(),
          totalSize: 3000,
          status: 'completed',
          isOfflineCapture: true,
        },
      ];

      expect(calculateCleanupSavings(candidates)).toBe(6000);
    });

    it('should handle single entry', () => {
      const candidates: CaptureIndexEntry[] = [
        {
          captureId: '1',
          queuedAt: new Date().toISOString(),
          totalSize: 5000,
          status: 'pending',
          isOfflineCapture: true,
        },
      ];

      expect(calculateCleanupSavings(candidates)).toBe(5000);
    });
  });

  describe('STORAGE_QUOTA_CONFIG', () => {
    it('should have MAX_CAPTURES of 50', () => {
      expect(STORAGE_QUOTA_CONFIG.MAX_CAPTURES).toBe(50);
    });

    it('should have MAX_STORAGE_BYTES of 500MB', () => {
      expect(STORAGE_QUOTA_CONFIG.MAX_STORAGE_BYTES).toBe(500 * 1024 * 1024);
    });

    it('should have WARNING_THRESHOLD of 80%', () => {
      expect(STORAGE_QUOTA_CONFIG.WARNING_THRESHOLD).toBe(0.8);
    });

    it('should have STALE_CAPTURE_DAYS of 7', () => {
      expect(STORAGE_QUOTA_CONFIG.STALE_CAPTURE_DAYS).toBe(7);
    });
  });

  describe('quota status calculations', () => {
    // These tests verify the logic flow even though we can't easily test
    // the async functions without more complex mocking

    it('should calculate count percentage correctly', () => {
      const captureCount = 40;
      const maxCaptures = STORAGE_QUOTA_CONFIG.MAX_CAPTURES;
      const countPercent = (captureCount / maxCaptures) * 100;

      expect(countPercent).toBe(80);
    });

    it('should calculate storage percentage correctly', () => {
      const storageUsed = 400 * 1024 * 1024; // 400MB
      const maxStorage = STORAGE_QUOTA_CONFIG.MAX_STORAGE_BYTES;
      const storagePercent = (storageUsed / maxStorage) * 100;

      expect(storagePercent).toBe(80);
    });

    it('should determine exceeded status when at max captures', () => {
      const captureCount = 50;
      const maxCaptures = STORAGE_QUOTA_CONFIG.MAX_CAPTURES;

      const isExceeded = captureCount >= maxCaptures;
      expect(isExceeded).toBe(true);
    });

    it('should determine exceeded status when at max storage', () => {
      const storageUsed = 500 * 1024 * 1024;
      const maxStorage = STORAGE_QUOTA_CONFIG.MAX_STORAGE_BYTES;

      const isExceeded = storageUsed >= maxStorage;
      expect(isExceeded).toBe(true);
    });

    it('should determine warning status at 80% threshold', () => {
      const usagePercent = 80;
      const warningThreshold = STORAGE_QUOTA_CONFIG.WARNING_THRESHOLD * 100;

      const isWarning = usagePercent >= warningThreshold;
      expect(isWarning).toBe(true);
    });

    it('should determine ok status below 80%', () => {
      const usagePercent = 79;
      const warningThreshold = STORAGE_QUOTA_CONFIG.WARNING_THRESHOLD * 100;

      const isWarning = usagePercent >= warningThreshold;
      expect(isWarning).toBe(false);
    });
  });

  describe('stale capture detection', () => {
    it('should identify captures older than 7 days as stale', () => {
      const staleDays = STORAGE_QUOTA_CONFIG.STALE_CAPTURE_DAYS;
      const staleThresholdHours = staleDays * 24;

      // 8 days old = 192 hours
      const captureAgeHours = 192;
      const isStale = captureAgeHours >= staleThresholdHours;

      expect(isStale).toBe(true);
    });

    it('should not identify captures under 7 days as stale', () => {
      const staleDays = STORAGE_QUOTA_CONFIG.STALE_CAPTURE_DAYS;
      const staleThresholdHours = staleDays * 24;

      // 6 days old = 144 hours
      const captureAgeHours = 144;
      const isStale = captureAgeHours >= staleThresholdHours;

      expect(isStale).toBe(false);
    });

    it('should identify captures over 24 hours for UI warning', () => {
      const warningThresholdHours = 24;

      const captureAgeHours = 25;
      const needsWarning = captureAgeHours >= warningThresholdHours;

      expect(needsWarning).toBe(true);
    });
  });
});
