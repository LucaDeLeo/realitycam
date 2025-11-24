/**
 * Result Screen (Story 5-8)
 *
 * Displays capture result after successful upload including:
 * - Capture thumbnail with confidence badge
 * - Verification URL with copy and share functionality
 * - Evidence summary (hardware attestation, depth analysis status)
 * - Navigation to web verification page
 *
 * @see Story 5-8 - Capture Result Screen
 */

import { useCallback, useMemo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  useColorScheme,
  TouchableOpacity,
  Image,
  Share,
  Alert,
  Linking,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import * as Clipboard from 'expo-clipboard';

import { colors } from '../constants/colors';

// ============================================================================
// Types
// ============================================================================

type ConfidenceLevel = 'high' | 'medium' | 'low' | 'suspicious';
type CheckStatus = 'pass' | 'fail' | 'unavailable';

interface UploadResult {
  captureId: string;
  confidenceLevel: ConfidenceLevel;
  verificationUrl: string;
  photoUri: string;
  hardwareStatus: CheckStatus;
  depthStatus: CheckStatus;
  capturedAt: string;
}

// ============================================================================
// Helper Functions
// ============================================================================

function getConfidenceColor(level: ConfidenceLevel, isDark: boolean): string {
  switch (level) {
    case 'high':
      return '#34C759'; // iOS system green
    case 'medium':
      return '#FFCC00'; // iOS system yellow
    case 'low':
      return '#FF9500'; // iOS system orange
    case 'suspicious':
      return '#FF3B30'; // iOS system red
    default:
      return colors.systemGray;
  }
}

function getConfidenceLabel(level: ConfidenceLevel): string {
  switch (level) {
    case 'high':
      return 'HIGH CONFIDENCE';
    case 'medium':
      return 'MEDIUM CONFIDENCE';
    case 'low':
      return 'LOW CONFIDENCE';
    case 'suspicious':
      return 'SUSPICIOUS';
    default:
      return 'UNKNOWN';
  }
}

function getStatusIcon(status: CheckStatus): string {
  switch (status) {
    case 'pass':
      return 'checkmark.circle.fill';
    case 'fail':
      return 'xmark.circle.fill';
    case 'unavailable':
      return 'minus.circle.fill';
    default:
      return 'questionmark.circle.fill';
  }
}

function getStatusLabel(status: CheckStatus): string {
  switch (status) {
    case 'pass':
      return 'Verified';
    case 'fail':
      return 'Failed';
    case 'unavailable':
      return 'Not Available';
    default:
      return 'Unknown';
  }
}

function getStatusColor(status: CheckStatus, isDark: boolean): string {
  switch (status) {
    case 'pass':
      return '#34C759';
    case 'fail':
      return '#FF3B30';
    case 'unavailable':
      return colors.systemGray;
    default:
      return colors.systemGray;
  }
}

// ============================================================================
// Component
// ============================================================================

export default function ResultScreen() {
  const colorScheme = useColorScheme();
  // Force light mode for result screen to ensure text visibility
  const isDark = false;
  const router = useRouter();
  const params = useLocalSearchParams();

  // Parse result data from navigation params
  const result = useMemo<UploadResult | null>(() => {
    try {
      if (params.result && typeof params.result === 'string') {
        return JSON.parse(params.result) as UploadResult;
      }
    } catch (err) {
      console.error('[ResultScreen] Failed to parse result:', err);
    }
    return null;
  }, [params.result]);

  // Handle copy verification URL
  const handleCopyUrl = useCallback(async () => {
    if (!result) return;

    try {
      await Clipboard.setStringAsync(result.verificationUrl);
      Alert.alert('Copied!', 'Verification URL copied to clipboard.');
    } catch (err) {
      console.error('[ResultScreen] Failed to copy URL:', err);
      Alert.alert('Error', 'Failed to copy URL. Please try again.');
    }
  }, [result]);

  // Handle share verification URL
  const handleShare = useCallback(async () => {
    if (!result) return;

    try {
      await Share.share({
        message: `Check out this verified photo: ${result.verificationUrl}`,
        url: result.verificationUrl,
        title: 'RealityCam Verified Photo',
      });
    } catch (err) {
      console.error('[ResultScreen] Failed to share:', err);
    }
  }, [result]);

  // Handle open in browser
  const handleViewDetails = useCallback(async () => {
    if (!result) return;

    try {
      const canOpen = await Linking.canOpenURL(result.verificationUrl);
      if (canOpen) {
        await Linking.openURL(result.verificationUrl);
      } else {
        Alert.alert('Error', 'Cannot open verification page.');
      }
    } catch (err) {
      console.error('[ResultScreen] Failed to open URL:', err);
      Alert.alert('Error', 'Failed to open verification page.');
    }
  }, [result]);

  // Handle done - navigate back to capture
  const handleDone = useCallback(() => {
    router.replace('/(tabs)/capture');
  }, [router]);

  // Show error if no result data
  if (!result) {
    return (
      <SafeAreaView
        style={[
          styles.container,
          styles.centered,
          { backgroundColor: isDark ? colors.backgroundDark : colors.background },
        ]}
      >
        <Text style={[styles.errorText, { color: isDark ? colors.textDark : colors.text }]}>
          No result data available
        </Text>
        <TouchableOpacity style={styles.doneButton} onPress={handleDone}>
          <Text style={styles.doneButtonText}>Go Back</Text>
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  const confidenceColor = getConfidenceColor(result.confidenceLevel, isDark);

  return (
    <SafeAreaView
      style={[
        styles.container,
        { backgroundColor: isDark ? colors.backgroundDark : colors.background },
      ]}
      edges={['bottom']}
    >
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Success Header */}
        <View style={styles.headerSection}>
          <View style={[styles.successIcon, { backgroundColor: '#34C759' }]}>
            <Text style={styles.successIconText}>OK</Text>
          </View>
          <Text style={[styles.headerTitle, { color: isDark ? colors.textDark : colors.text }]}>
            Upload Complete
          </Text>
          <Text style={[styles.headerSubtitle, { color: colors.textSecondary }]}>
            Your photo has been verified and is ready to share
          </Text>
        </View>

        {/* Photo Thumbnail with Confidence Badge */}
        <View style={styles.thumbnailSection}>
          <View style={styles.thumbnailContainer}>
            <Image source={{ uri: result.photoUri }} style={styles.thumbnail} resizeMode="cover" />
            <View style={[styles.confidenceBadge, { backgroundColor: confidenceColor }]}>
              <Text style={styles.confidenceBadgeText}>
                {getConfidenceLabel(result.confidenceLevel)}
              </Text>
            </View>
          </View>
        </View>

        {/* Verification URL Section */}
        <View
          style={[
            styles.urlSection,
            {
              backgroundColor: isDark ? colors.backgroundSecondary : '#F5F5F7',
              borderColor: isDark ? colors.borderDark : colors.border,
            },
          ]}
        >
          <Text style={[styles.urlLabel, { color: colors.textSecondary }]}>Verification URL</Text>
          <Text
            style={[styles.urlText, { color: isDark ? colors.textDark : colors.text }]}
            numberOfLines={2}
            ellipsizeMode="middle"
          >
            {result.verificationUrl}
          </Text>
          <View style={styles.urlActions}>
            <TouchableOpacity style={styles.urlActionButton} onPress={handleCopyUrl}>
              <Text style={[styles.urlActionText, { color: colors.primary }]}>Copy</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.urlActionButton} onPress={handleShare}>
              <Text style={[styles.urlActionText, { color: colors.primary }]}>Share</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Evidence Summary */}
        <View style={styles.evidenceSection}>
          <Text style={[styles.sectionTitle, { color: isDark ? colors.textDark : colors.text }]}>
            Evidence Summary
          </Text>

          {/* Hardware Attestation */}
          <View
            style={[
              styles.evidenceRow,
              {
                backgroundColor: isDark ? colors.backgroundSecondary : '#F5F5F7',
                borderColor: isDark ? colors.borderDark : colors.border,
              },
            ]}
          >
            <View style={styles.evidenceInfo}>
              <Text style={[styles.evidenceLabel, { color: isDark ? colors.textDark : colors.text }]}>
                Hardware Attestation
              </Text>
              <Text style={[styles.evidenceStatus, { color: getStatusColor(result.hardwareStatus, isDark) }]}>
                {getStatusLabel(result.hardwareStatus)}
              </Text>
            </View>
            <View
              style={[
                styles.statusIndicator,
                { backgroundColor: getStatusColor(result.hardwareStatus, isDark) },
              ]}
            />
          </View>

          {/* Depth Analysis */}
          <View
            style={[
              styles.evidenceRow,
              {
                backgroundColor: isDark ? colors.backgroundSecondary : '#F5F5F7',
                borderColor: isDark ? colors.borderDark : colors.border,
              },
            ]}
          >
            <View style={styles.evidenceInfo}>
              <Text style={[styles.evidenceLabel, { color: isDark ? colors.textDark : colors.text }]}>
                LiDAR Depth Analysis
              </Text>
              <Text style={[styles.evidenceStatus, { color: getStatusColor(result.depthStatus, isDark) }]}>
                {getStatusLabel(result.depthStatus)}
              </Text>
            </View>
            <View
              style={[
                styles.statusIndicator,
                { backgroundColor: getStatusColor(result.depthStatus, isDark) },
              ]}
            />
          </View>
        </View>

        {/* View Details Button */}
        <TouchableOpacity
          style={[styles.viewDetailsButton, { borderColor: colors.primary }]}
          onPress={handleViewDetails}
        >
          <Text style={[styles.viewDetailsText, { color: colors.primary }]}>View Full Details</Text>
        </TouchableOpacity>
      </ScrollView>

      {/* Done Button */}
      <View
        style={[
          styles.bottomSection,
          {
            backgroundColor: isDark ? colors.backgroundDark : colors.background,
            borderTopColor: isDark ? colors.borderDark : colors.border,
          },
        ]}
      >
        <TouchableOpacity style={styles.doneButton} onPress={handleDone}>
          <Text style={styles.doneButtonText}>Done</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

// ============================================================================
// Styles
// ============================================================================

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  centered: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },
  errorText: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 20,
  },

  // Header Section
  headerSection: {
    alignItems: 'center',
    marginBottom: 24,
  },
  successIcon: {
    width: 56,
    height: 56,
    borderRadius: 28,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 16,
  },
  successIconText: {
    color: '#FFFFFF',
    fontSize: 20,
    fontWeight: '700',
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: '700',
    marginBottom: 8,
  },
  headerSubtitle: {
    fontSize: 15,
    textAlign: 'center',
    lineHeight: 20,
  },

  // Thumbnail Section
  thumbnailSection: {
    alignItems: 'center',
    marginBottom: 24,
  },
  thumbnailContainer: {
    position: 'relative',
    borderRadius: 12,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
  thumbnail: {
    width: 200,
    height: 200,
    borderRadius: 12,
  },
  confidenceBadge: {
    position: 'absolute',
    bottom: 8,
    left: 8,
    right: 8,
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 6,
    alignItems: 'center',
  },
  confidenceBadgeText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0.5,
  },

  // URL Section
  urlSection: {
    borderRadius: 12,
    padding: 16,
    marginBottom: 24,
    borderWidth: StyleSheet.hairlineWidth,
  },
  urlLabel: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 8,
  },
  urlText: {
    fontSize: 14,
    fontFamily: 'monospace',
    marginBottom: 12,
  },
  urlActions: {
    flexDirection: 'row',
    gap: 16,
  },
  urlActionButton: {
    paddingVertical: 6,
    paddingHorizontal: 12,
  },
  urlActionText: {
    fontSize: 15,
    fontWeight: '600',
  },

  // Evidence Section
  evidenceSection: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 17,
    fontWeight: '600',
    marginBottom: 12,
  },
  evidenceRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 16,
    borderRadius: 12,
    marginBottom: 8,
    borderWidth: StyleSheet.hairlineWidth,
  },
  evidenceInfo: {
    flex: 1,
  },
  evidenceLabel: {
    fontSize: 15,
    fontWeight: '500',
    marginBottom: 2,
  },
  evidenceStatus: {
    fontSize: 13,
  },
  statusIndicator: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginLeft: 12,
  },

  // View Details Button
  viewDetailsButton: {
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  viewDetailsText: {
    fontSize: 16,
    fontWeight: '600',
  },

  // Bottom Section
  bottomSection: {
    padding: 16,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  doneButton: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
  },
  doneButtonText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '600',
  },
});
