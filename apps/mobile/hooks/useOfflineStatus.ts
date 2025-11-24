/**
 * useOfflineStatus Hook
 *
 * Provides offline capture status and storage quota information for UI display.
 * Combines network status, queue status, and storage quota into a unified view.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-7)
 */

import { useEffect, useState, useCallback } from 'react';
import { useNetworkStatus } from './useNetworkStatus';
import {
  useUploadQueueStore,
  selectOfflineCaptures,
  selectOfflineCounts,
} from '../store/uploadQueueStore';
import type { StorageQuotaInfo } from '@realitycam/shared';
import { getStorageUsage, getQuotaWarning, formatAge, formatBytes } from '../services/storageQuota';

/**
 * Offline capture display information
 */
export interface OfflineCaptureInfo {
  /** Capture ID */
  id: string;
  /** Time since capture in hours */
  ageHours: number;
  /** Formatted age string (e.g., "2 hours ago") */
  ageFormatted: string;
  /** Whether capture is older than 24 hours */
  isStale: boolean;
  /** Current status */
  status: string;
  /** Size in bytes */
  size?: number;
}

/**
 * Quota warning info for UI
 */
export interface QuotaWarningInfo {
  type: 'approaching' | 'exceeded' | 'stale';
  message: string;
}

/**
 * useOfflineStatus hook return type
 */
export interface UseOfflineStatusReturn {
  /** Whether device is currently online */
  isOnline: boolean;
  /** Whether device is offline */
  isOffline: boolean;
  /** Number of offline captures pending upload */
  offlineCount: number;
  /** Storage quota information */
  quota: StorageQuotaInfo | null;
  /** Formatted storage usage string */
  storageUsedFormatted: string;
  /** Storage warning if approaching/exceeded quota */
  quotaWarning: QuotaWarningInfo | null;
  /** List of offline captures with display info */
  offlineCaptures: OfflineCaptureInfo[];
  /** Whether any captures are stale (older than 24h) */
  hasStaleCaptures: boolean;
  /** Number of stale captures */
  staleCaptureCount: number;
  /** Refresh quota information */
  refreshQuota: () => Promise<void>;
  /** Whether quota is being loaded */
  isLoadingQuota: boolean;
}

/**
 * Hook for offline status and storage quota UI information
 *
 * @example
 * ```tsx
 * const {
 *   isOffline,
 *   offlineCount,
 *   quota,
 *   quotaWarning,
 *   hasStaleCaptures,
 * } = useOfflineStatus();
 *
 * if (isOffline && offlineCount > 0) {
 *   return <OfflineBanner count={offlineCount} />;
 * }
 *
 * if (quotaWarning) {
 *   return <QuotaWarning type={quotaWarning.type} message={quotaWarning.message} />;
 * }
 * ```
 */
export function useOfflineStatus(): UseOfflineStatusReturn {
  // Network status
  const { isConnected, isInternetReachable } = useNetworkStatus();
  const isOnline = isConnected === true && isInternetReachable === true;
  const isOffline = !isOnline;

  // Queue status
  const offlineCaptureItems = useUploadQueueStore(selectOfflineCaptures);
  const offlineCounts = useUploadQueueStore(selectOfflineCounts);

  // Quota state
  const [quota, setQuota] = useState<StorageQuotaInfo | null>(null);
  const [quotaWarning, setQuotaWarning] = useState<QuotaWarningInfo | null>(null);
  const [isLoadingQuota, setIsLoadingQuota] = useState(true);

  /**
   * Refresh quota information
   */
  const refreshQuota = useCallback(async () => {
    setIsLoadingQuota(true);
    try {
      const [quotaInfo, warning] = await Promise.all([
        getStorageUsage(),
        getQuotaWarning(),
      ]);
      setQuota(quotaInfo);
      setQuotaWarning(warning);
    } catch (error) {
      console.error('[useOfflineStatus] Failed to refresh quota:', error);
    } finally {
      setIsLoadingQuota(false);
    }
  }, []);

  // Load quota on mount and when offline count changes
  useEffect(() => {
    refreshQuota();
  }, [refreshQuota, offlineCounts.total]);

  // Process offline captures for display
  const offlineCaptures: OfflineCaptureInfo[] = offlineCaptureItems.map((item) => {
    const queuedAt = new Date(item.queuedAt).getTime();
    const ageMs = Date.now() - queuedAt;
    const ageHours = ageMs / (60 * 60 * 1000);

    return {
      id: item.capture.id,
      ageHours,
      ageFormatted: formatAge(ageHours),
      isStale: ageHours >= 24,
      status: item.status,
    };
  });

  // Calculate stale captures
  const staleCaptures = offlineCaptures.filter((c) => c.isStale);
  const hasStaleCaptures = staleCaptures.length > 0;
  const staleCaptureCount = staleCaptures.length;

  // Format storage used
  const storageUsedFormatted = quota
    ? `${formatBytes(quota.storageUsedBytes)} / ${formatBytes(quota.maxStorageBytes)}`
    : 'Loading...';

  return {
    isOnline,
    isOffline,
    offlineCount: offlineCounts.total,
    quota,
    storageUsedFormatted,
    quotaWarning,
    offlineCaptures,
    hasStaleCaptures,
    staleCaptureCount,
    refreshQuota,
    isLoadingQuota,
  };
}

/**
 * Lightweight hook for just checking if offline captures exist
 */
export function useHasOfflineCaptures(): boolean {
  const offlineCounts = useUploadQueueStore(selectOfflineCounts);
  return offlineCounts.total > 0;
}

/**
 * Hook for getting formatted capture age
 *
 * @param queuedAt - ISO timestamp when capture was queued
 * @returns Formatted age string
 */
export function useCaptureAge(queuedAt: string): {
  ageHours: number;
  ageFormatted: string;
  isStale: boolean;
} {
  const [ageInfo, setAgeInfo] = useState(() => {
    const ageMs = Date.now() - new Date(queuedAt).getTime();
    const ageHours = ageMs / (60 * 60 * 1000);
    return {
      ageHours,
      ageFormatted: formatAge(ageHours),
      isStale: ageHours >= 24,
    };
  });

  // Update every minute
  useEffect(() => {
    const interval = setInterval(() => {
      const ageMs = Date.now() - new Date(queuedAt).getTime();
      const ageHours = ageMs / (60 * 60 * 1000);
      setAgeInfo({
        ageHours,
        ageFormatted: formatAge(ageHours),
        isStale: ageHours >= 24,
      });
    }, 60 * 1000);

    return () => clearInterval(interval);
  }, [queuedAt]);

  return ageInfo;
}
