/**
 * OfflineCaptureBadge Component
 *
 * Displays status badge for offline captures with age information.
 * Shows warnings for captures older than 24 hours.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-7)
 */

import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useCaptureAge } from '../../hooks/useOfflineStatus';

/**
 * Badge variant based on capture status
 */
type BadgeVariant = 'pending' | 'uploading' | 'failed' | 'stale';

/**
 * OfflineCaptureBadge props
 */
interface OfflineCaptureBadgeProps {
  /** ISO timestamp when capture was queued */
  queuedAt: string;
  /** Current capture status */
  status: string;
  /** Optional size override */
  size?: 'small' | 'medium';
}

/**
 * Get badge variant from status and age
 */
function getBadgeVariant(status: string, isStale: boolean): BadgeVariant {
  if (isStale) return 'stale';
  if (status === 'uploading' || status === 'processing') return 'uploading';
  if (status === 'failed' || status === 'permanently_failed') return 'failed';
  return 'pending';
}

/**
 * Get badge label from variant
 */
function getBadgeLabel(variant: BadgeVariant): string {
  switch (variant) {
    case 'pending':
      return 'Pending upload';
    case 'uploading':
      return 'Uploading';
    case 'failed':
      return 'Upload failed';
    case 'stale':
      return 'Pending (old)';
  }
}

/**
 * Badge component showing offline capture status
 */
export function OfflineCaptureBadge({
  queuedAt,
  status,
  size = 'medium',
}: OfflineCaptureBadgeProps) {
  const { ageFormatted, isStale } = useCaptureAge(queuedAt);
  const variant = getBadgeVariant(status, isStale);
  const label = getBadgeLabel(variant);

  const containerStyle = [
    styles.container,
    styles[`container_${variant}`],
    size === 'small' && styles.containerSmall,
  ];

  const textStyle = [
    styles.text,
    styles[`text_${variant}`],
    size === 'small' && styles.textSmall,
  ];

  const ageTextStyle = [
    styles.ageText,
    styles[`ageText_${variant}`],
    size === 'small' && styles.ageTextSmall,
  ];

  return (
    <View style={containerStyle}>
      <Text style={textStyle}>{label}</Text>
      <Text style={ageTextStyle}>Captured {ageFormatted}</Text>
    </View>
  );
}

/**
 * Simple badge showing just the pending status
 */
export function PendingUploadBadge({ size = 'medium' }: { size?: 'small' | 'medium' }) {
  const containerStyle = [
    styles.simpleBadge,
    size === 'small' && styles.simpleBadgeSmall,
  ];

  const textStyle = [
    styles.simpleBadgeText,
    size === 'small' && styles.simpleBadgeTextSmall,
  ];

  return (
    <View style={containerStyle}>
      <Text style={textStyle}>Pending upload</Text>
    </View>
  );
}

/**
 * Stale capture warning badge
 */
export function StaleCaptureWarning() {
  return (
    <View style={styles.warningContainer}>
      <Text style={styles.warningIcon}>!</Text>
      <Text style={styles.warningText}>
        This capture has been pending for over 24 hours
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: '#F3F4F6',
  },
  containerSmall: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  container_pending: {
    backgroundColor: '#FEF3C7',
    borderColor: '#F59E0B',
    borderWidth: 1,
  },
  container_uploading: {
    backgroundColor: '#DBEAFE',
    borderColor: '#3B82F6',
    borderWidth: 1,
  },
  container_failed: {
    backgroundColor: '#FEE2E2',
    borderColor: '#EF4444',
    borderWidth: 1,
  },
  container_stale: {
    backgroundColor: '#FED7AA',
    borderColor: '#EA580C',
    borderWidth: 1,
  },
  text: {
    fontSize: 14,
    fontWeight: '600',
    color: '#374151',
  },
  textSmall: {
    fontSize: 12,
  },
  text_pending: {
    color: '#92400E',
  },
  text_uploading: {
    color: '#1D4ED8',
  },
  text_failed: {
    color: '#DC2626',
  },
  text_stale: {
    color: '#C2410C',
  },
  ageText: {
    fontSize: 12,
    color: '#6B7280',
    marginTop: 2,
  },
  ageTextSmall: {
    fontSize: 10,
    marginTop: 1,
  },
  ageText_pending: {
    color: '#B45309',
  },
  ageText_uploading: {
    color: '#2563EB',
  },
  ageText_failed: {
    color: '#DC2626',
  },
  ageText_stale: {
    color: '#EA580C',
  },
  simpleBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    backgroundColor: '#FEF3C7',
  },
  simpleBadgeSmall: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 8,
  },
  simpleBadgeText: {
    fontSize: 12,
    fontWeight: '500',
    color: '#92400E',
  },
  simpleBadgeTextSmall: {
    fontSize: 10,
  },
  warningContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    backgroundColor: '#FED7AA',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#EA580C',
  },
  warningIcon: {
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: '#EA580C',
    color: '#FFFFFF',
    textAlign: 'center',
    lineHeight: 20,
    fontWeight: '700',
    marginRight: 8,
  },
  warningText: {
    flex: 1,
    fontSize: 14,
    color: '#C2410C',
  },
});

export default OfflineCaptureBadge;
