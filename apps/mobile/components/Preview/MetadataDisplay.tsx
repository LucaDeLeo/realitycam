/**
 * MetadataDisplay Component
 *
 * Displays capture metadata including timestamp, location, and attestation status.
 * Shows clear, unobtrusive information about the capture.
 *
 * @see Story 3.6 - Capture Preview Screen
 */

import { View, Text, StyleSheet, useColorScheme } from 'react-native';
import { colors } from '../../constants/colors';
import type { CaptureMetadata } from '@realitycam/shared';

interface MetadataDisplayProps {
  /** Capture metadata to display */
  metadata: CaptureMetadata;
  /** Additional styles for container */
  style?: object;
}

/**
 * Format ISO timestamp to human-readable string
 */
function formatTimestamp(isoString: string): string {
  try {
    const date = new Date(isoString);
    return date.toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
    });
  } catch {
    return isoString;
  }
}

/**
 * Format location coordinates for display
 */
function formatLocation(lat: number, lng: number): string {
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
}

/**
 * Component to display capture metadata
 */
export function MetadataDisplay({ metadata, style }: MetadataDisplayProps) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const hasLocation = !!metadata.location;
  const isAttested = !!metadata.assertion;

  return (
    <View style={[styles.container, style]}>
      {/* Capture Time */}
      <View style={styles.row}>
        <Text
          style={[
            styles.label,
            { color: isDark ? colors.textSecondary : colors.textSecondary },
          ]}
        >
          Captured
        </Text>
        <Text
          style={[
            styles.value,
            { color: isDark ? colors.textDark : colors.text },
          ]}
        >
          {formatTimestamp(metadata.captured_at)}
        </Text>
      </View>

      {/* Location */}
      <View style={styles.row}>
        <Text
          style={[
            styles.label,
            { color: isDark ? colors.textSecondary : colors.textSecondary },
          ]}
        >
          Location
        </Text>
        <Text
          style={[
            styles.value,
            { color: isDark ? colors.textDark : colors.text },
            !hasLocation && styles.unavailable,
          ]}
        >
          {hasLocation
            ? formatLocation(metadata.location!.latitude, metadata.location!.longitude)
            : 'Not available'}
        </Text>
      </View>

      {/* Attestation Status */}
      <View style={styles.row}>
        <Text
          style={[
            styles.label,
            { color: isDark ? colors.textSecondary : colors.textSecondary },
          ]}
        >
          Security
        </Text>
        <View style={styles.attestationRow}>
          <View
            style={[
              styles.attestationBadge,
              isAttested ? styles.attestedBadge : styles.unverifiedBadge,
            ]}
          >
            <Text
              style={[
                styles.attestationText,
                isAttested ? styles.attestedText : styles.unverifiedText,
              ]}
            >
              {isAttested ? 'Verified' : 'Unverified'}
            </Text>
          </View>
        </View>
      </View>

      {/* Device Model */}
      <View style={styles.row}>
        <Text
          style={[
            styles.label,
            { color: isDark ? colors.textSecondary : colors.textSecondary },
          ]}
        >
          Device
        </Text>
        <Text
          style={[
            styles.value,
            { color: isDark ? colors.textDark : colors.text },
          ]}
        >
          {metadata.device_model}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 24,
    gap: 20,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  label: {
    fontSize: 18,
    fontWeight: '600',
  },
  value: {
    fontSize: 18,
    fontWeight: '400',
  },
  unavailable: {
    fontStyle: 'italic',
    opacity: 0.6,
  },
  attestationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  attestationBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  attestedBadge: {
    backgroundColor: '#34C759', // iOS green
  },
  unverifiedBadge: {
    backgroundColor: '#FF9500', // iOS orange
  },
  attestationText: {
    fontSize: 16,
    fontWeight: '600',
  },
  attestedText: {
    color: '#FFFFFF',
  },
  unverifiedText: {
    color: '#FFFFFF',
  },
});
