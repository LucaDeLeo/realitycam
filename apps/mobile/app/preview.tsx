/**
 * Preview Screen
 *
 * Displays captured photo with depth overlay toggle, metadata summary,
 * and action buttons (Upload/Discard). Receives ProcessedCapture data
 * via navigation params or global state.
 *
 * @see Story 3.6 - Capture Preview Screen
 */

import { useCallback, useEffect, useState } from 'react';
import {
  View,
  StyleSheet,
  useColorScheme,
  ScrollView,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import * as FileSystem from 'expo-file-system/legacy';

import { CapturePreview, MetadataDisplay, ActionButtons } from '../components/Preview';
import { colors } from '../constants/colors';
import { uploadCapture } from '../services/uploadService';
import type { ProcessedCapture } from '@realitycam/shared';

/**
 * Preview screen component
 */
export default function PreviewScreen() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  const router = useRouter();
  const params = useLocalSearchParams();

  // State for processed capture data
  const [capture, setCapture] = useState<ProcessedCapture | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isUploading, setIsUploading] = useState(false);

  // Parse capture data from navigation params
  useEffect(() => {
    try {
      if (params.capture && typeof params.capture === 'string') {
        const parsed = JSON.parse(params.capture) as ProcessedCapture;
        setCapture(parsed);
        console.log('[PreviewScreen] Loaded capture:', parsed.id);
      } else {
        console.warn('[PreviewScreen] No capture data in params');
      }
    } catch (err) {
      console.error('[PreviewScreen] Failed to parse capture data:', err);
    } finally {
      setIsLoading(false);
    }
  }, [params.capture]);

  /**
   * Handle discard action
   * Deletes temporary files and navigates back to capture screen
   */
  const handleDiscard = useCallback(async () => {
    if (!capture) return;

    try {
      // Delete photo file from temporary storage
      console.log('[PreviewScreen] Deleting capture files:', capture.photoUri);
      const fileInfo = await FileSystem.getInfoAsync(capture.photoUri);
      if (fileInfo.exists) {
        await FileSystem.deleteAsync(capture.photoUri, { idempotent: true });
        console.log('[PreviewScreen] Photo file deleted');
      }

      // Navigate back to capture screen
      router.back();
      console.log('[PreviewScreen] Navigated back to capture screen');
    } catch (err) {
      console.error('[PreviewScreen] Failed to delete capture files:', err);
      Alert.alert(
        'Error',
        'Failed to discard capture. Please try again.',
        [{ text: 'OK' }]
      );
    }
  }, [capture, router]);

  /**
   * Handle upload action
   */
  const handleUpload = useCallback(async () => {
    if (!capture || isUploading) return;

    console.log('[PreviewScreen] Starting upload for capture:', capture.id);
    setIsUploading(true);

    try {
      const result = await uploadCapture(capture);

      if (result.success) {
        console.log('[PreviewScreen] Upload successful:', result.data);

        // Navigate to result screen with upload response
        router.replace({
          pathname: '/result',
          params: {
            result: JSON.stringify({
              captureId: result.data.data.capture_id,
              confidenceLevel: 'medium', // Backend will determine actual level
              verificationUrl: result.data.data.verification_url,
              photoUri: capture.photoUri,
              hardwareStatus: 'pass',
              depthStatus: capture.compressedDepthMap ? 'pass' : 'unavailable',
              capturedAt: capture.metadata.captured_at,
            }),
          },
        });
      } else {
        console.error('[PreviewScreen] Upload failed:', result.error);
        Alert.alert(
          'Upload Failed',
          result.error.message || 'Please try again.',
          [{ text: 'OK' }]
        );
      }
    } catch (err) {
      console.error('[PreviewScreen] Upload error:', err);
      Alert.alert(
        'Upload Error',
        'An unexpected error occurred. Please try again.',
        [{ text: 'OK' }]
      );
    } finally {
      setIsUploading(false);
    }
  }, [capture, isUploading, router]);

  // Show loading or error state
  if (isLoading) {
    return (
      <SafeAreaView
        style={[
          styles.container,
          styles.centered,
          { backgroundColor: isDark ? colors.backgroundDark : colors.background },
        ]}
      />
    );
  }

  // Show error if no capture data
  if (!capture) {
    return (
      <SafeAreaView
        style={[
          styles.container,
          styles.centered,
          { backgroundColor: isDark ? colors.backgroundDark : colors.background },
        ]}
      >
        <View style={styles.errorContainer}>
          {/* Error state - navigate back */}
          {(() => {
            // Navigate back after a short delay
            setTimeout(() => router.back(), 100);
            return null;
          })()}
        </View>
      </SafeAreaView>
    );
  }

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
        bounces={false}
      >
        {/* Photo Preview with Depth Toggle */}
        <CapturePreview
          photoUri={capture.photoUri}
          hasDepthData={!!capture.compressedDepthMap}
          compressedDepthMap={capture.compressedDepthMap}
          depthDimensions={capture.depthDimensions}
        />

        {/* Metadata Display */}
        <View
          style={[
            styles.metadataSection,
            {
              backgroundColor: isDark
                ? colors.backgroundDark
                : colors.backgroundSecondary,
            },
          ]}
        >
          <MetadataDisplay metadata={capture.metadata} />
        </View>
      </ScrollView>

      {/* Action Buttons */}
      <View
        style={[
          styles.actionsSection,
          { backgroundColor: isDark ? colors.backgroundDark : colors.background },
        ]}
      >
        <ActionButtons
          onDiscard={handleDiscard}
          onUpload={handleUpload}
          isLoading={isUploading}
        />
      </View>
    </SafeAreaView>
  );
}

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
    flexGrow: 1,
  },
  errorContainer: {
    padding: 24,
    alignItems: 'center',
  },
  metadataSection: {
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    marginTop: -16,
  },
  actionsSection: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});
