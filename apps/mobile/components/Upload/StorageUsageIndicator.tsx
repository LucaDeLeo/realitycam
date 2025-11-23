/**
 * StorageUsageIndicator Component
 *
 * Displays storage quota usage with progress bar and status indicators.
 * Shows warnings when approaching or exceeding quota limits.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-7)
 */

import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useOfflineStatus } from '../../hooks/useOfflineStatus';
import { formatBytes } from '../../services/storageQuota';

/**
 * StorageUsageIndicator props
 */
interface StorageUsageIndicatorProps {
  /** Show compact version */
  compact?: boolean;
  /** Show refresh button */
  showRefresh?: boolean;
  /** Callback when cleanup is requested */
  onRequestCleanup?: () => void;
}

/**
 * Get progress bar color based on status
 */
function getProgressColor(status: string, percent: number): string {
  if (status === 'exceeded') return '#DC2626'; // Red
  if (status === 'warning') return '#F59E0B'; // Amber
  if (percent > 50) return '#3B82F6'; // Blue
  return '#10B981'; // Green
}

/**
 * Storage usage indicator with progress bar
 */
export function StorageUsageIndicator({
  compact = false,
  showRefresh = false,
  onRequestCleanup,
}: StorageUsageIndicatorProps) {
  const {
    quota,
    storageUsedFormatted,
    quotaWarning,
    offlineCount,
    hasStaleCaptures,
    staleCaptureCount,
    refreshQuota,
    isLoadingQuota,
  } = useOfflineStatus();

  if (!quota) {
    return (
      <View style={[styles.container, compact && styles.containerCompact]}>
        <Text style={styles.loadingText}>Loading storage info...</Text>
      </View>
    );
  }

  const progressColor = getProgressColor(quota.status, quota.usagePercent);
  const progressWidth = Math.min(100, quota.usagePercent);

  if (compact) {
    return (
      <View style={styles.containerCompact}>
        <View style={styles.compactHeader}>
          <Text style={styles.compactLabel}>Storage</Text>
          <Text style={styles.compactValue}>{storageUsedFormatted}</Text>
        </View>
        <View style={styles.progressBarCompact}>
          <View
            style={[
              styles.progressFillCompact,
              { width: `${progressWidth}%`, backgroundColor: progressColor },
            ]}
          />
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Offline Storage</Text>
        {showRefresh && (
          <Pressable
            onPress={refreshQuota}
            style={styles.refreshButton}
            disabled={isLoadingQuota}
          >
            <Text style={styles.refreshText}>
              {isLoadingQuota ? 'Loading...' : 'Refresh'}
            </Text>
          </Pressable>
        )}
      </View>

      {/* Progress bar */}
      <View style={styles.progressContainer}>
        <View style={styles.progressBar}>
          <View
            style={[
              styles.progressFill,
              { width: `${progressWidth}%`, backgroundColor: progressColor },
            ]}
          />
        </View>
        <Text style={styles.percentText}>{Math.round(quota.usagePercent)}%</Text>
      </View>

      {/* Stats */}
      <View style={styles.statsRow}>
        <View style={styles.stat}>
          <Text style={styles.statValue}>{quota.captureCount}</Text>
          <Text style={styles.statLabel}>/ {quota.maxCaptures} captures</Text>
        </View>
        <View style={styles.stat}>
          <Text style={styles.statValue}>
            {formatBytes(quota.storageUsedBytes)}
          </Text>
          <Text style={styles.statLabel}>
            / {formatBytes(quota.maxStorageBytes)}
          </Text>
        </View>
      </View>

      {/* Warning message */}
      {quotaWarning && (
        <View
          style={[
            styles.warningBanner,
            quotaWarning.type === 'exceeded' && styles.warningBannerError,
          ]}
        >
          <Text
            style={[
              styles.warningText,
              quotaWarning.type === 'exceeded' && styles.warningTextError,
            ]}
          >
            {quotaWarning.message}
          </Text>
        </View>
      )}

      {/* Stale captures warning */}
      {hasStaleCaptures && !quotaWarning && (
        <View style={styles.staleWarning}>
          <Text style={styles.staleWarningText}>
            {staleCaptureCount} capture{staleCaptureCount !== 1 ? 's' : ''}{' '}
            pending for over 24 hours
          </Text>
        </View>
      )}

      {/* Cleanup button */}
      {(quota.status === 'warning' || quota.status === 'exceeded') &&
        onRequestCleanup && (
          <Pressable style={styles.cleanupButton} onPress={onRequestCleanup}>
            <Text style={styles.cleanupButtonText}>Free Up Space</Text>
          </Pressable>
        )}
    </View>
  );
}

/**
 * Simple storage summary for list items
 */
export function StorageSummary() {
  const { quota, offlineCount } = useOfflineStatus();

  if (!quota || offlineCount === 0) {
    return null;
  }

  return (
    <View style={styles.summary}>
      <Text style={styles.summaryText}>
        {offlineCount} offline capture{offlineCount !== 1 ? 's' : ''} ({formatBytes(quota.storageUsedBytes)})
      </Text>
    </View>
  );
}

/**
 * Quota status badge
 */
export function QuotaStatusBadge() {
  const { quota } = useOfflineStatus();

  if (!quota || quota.status === 'ok') {
    return null;
  }

  const isExceeded = quota.status === 'exceeded';

  return (
    <View style={[styles.statusBadge, isExceeded && styles.statusBadgeError]}>
      <Text style={[styles.statusBadgeText, isExceeded && styles.statusBadgeTextError]}>
        {isExceeded ? 'Storage Full' : 'Storage Low'}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 16,
    backgroundColor: '#FFFFFF',
    borderRadius: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  containerCompact: {
    padding: 12,
    backgroundColor: '#F9FAFB',
    borderRadius: 8,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  title: {
    fontSize: 16,
    fontWeight: '600',
    color: '#111827',
  },
  refreshButton: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    backgroundColor: '#F3F4F6',
    borderRadius: 4,
  },
  refreshText: {
    fontSize: 12,
    color: '#6B7280',
  },
  progressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  progressBar: {
    flex: 1,
    height: 8,
    backgroundColor: '#E5E7EB',
    borderRadius: 4,
    overflow: 'hidden',
    marginRight: 8,
  },
  progressFill: {
    height: '100%',
    borderRadius: 4,
  },
  percentText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#374151',
    width: 44,
    textAlign: 'right',
  },
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  stat: {
    flexDirection: 'row',
    alignItems: 'baseline',
  },
  statValue: {
    fontSize: 14,
    fontWeight: '600',
    color: '#111827',
  },
  statLabel: {
    fontSize: 12,
    color: '#6B7280',
    marginLeft: 4,
  },
  warningBanner: {
    marginTop: 12,
    padding: 10,
    backgroundColor: '#FEF3C7',
    borderRadius: 6,
    borderWidth: 1,
    borderColor: '#F59E0B',
  },
  warningBannerError: {
    backgroundColor: '#FEE2E2',
    borderColor: '#EF4444',
  },
  warningText: {
    fontSize: 13,
    color: '#92400E',
    textAlign: 'center',
  },
  warningTextError: {
    color: '#DC2626',
  },
  staleWarning: {
    marginTop: 12,
    padding: 10,
    backgroundColor: '#FED7AA',
    borderRadius: 6,
  },
  staleWarningText: {
    fontSize: 13,
    color: '#C2410C',
    textAlign: 'center',
  },
  cleanupButton: {
    marginTop: 12,
    paddingVertical: 10,
    backgroundColor: '#3B82F6',
    borderRadius: 6,
    alignItems: 'center',
  },
  cleanupButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#FFFFFF',
  },
  compactHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  compactLabel: {
    fontSize: 12,
    color: '#6B7280',
  },
  compactValue: {
    fontSize: 12,
    fontWeight: '500',
    color: '#374151',
  },
  progressBarCompact: {
    height: 4,
    backgroundColor: '#E5E7EB',
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFillCompact: {
    height: '100%',
    borderRadius: 2,
  },
  loadingText: {
    fontSize: 14,
    color: '#9CA3AF',
    textAlign: 'center',
  },
  summary: {
    paddingVertical: 4,
  },
  summaryText: {
    fontSize: 12,
    color: '#6B7280',
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: '#FEF3C7',
    borderRadius: 4,
  },
  statusBadgeError: {
    backgroundColor: '#FEE2E2',
  },
  statusBadgeText: {
    fontSize: 11,
    fontWeight: '600',
    color: '#92400E',
  },
  statusBadgeTextError: {
    color: '#DC2626',
  },
});

export default StorageUsageIndicator;
