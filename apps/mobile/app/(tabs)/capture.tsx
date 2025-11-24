/**
 * Capture Screen
 *
 * Main camera capture screen with LiDAR depth overlay.
 * Displays camera preview with real-time depth visualization.
 * Implements synchronized photo + depth + location capture via useCapture hook.
 * Processes capture and navigates to preview screen.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 * @see Story 3.2 - Photo Capture with Depth Map
 * @see Story 3.3 - GPS Metadata Collection
 * @see Story 3.5 - Local Processing Pipeline
 * @see Story 3.6 - Capture Preview Screen
 */

import { useState, useCallback, useRef } from 'react';
import { View, Text, StyleSheet, Alert, useColorScheme } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { CameraView, CameraViewHandle } from '../../components/Camera';
import { useDeviceStore } from '../../store/deviceStore';
import { useCapture } from '../../hooks/useCapture';
import { useCaptureProcessing } from '../../hooks/useCaptureProcessing';
import { colors } from '../../constants/colors';

/**
 * LiDAR unavailable message component
 */
function LiDARUnavailable({ reason }: { reason?: string }) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  return (
    <SafeAreaView
      style={[
        styles.container,
        styles.centered,
        { backgroundColor: isDark ? colors.backgroundDark : colors.background },
      ]}
    >
      <View style={styles.unavailableContainer}>
        <Text style={[styles.unavailableTitle, { color: isDark ? colors.textDark : colors.text }]}>
          LiDAR Required
        </Text>
        <Text style={[styles.unavailableMessage, { color: isDark ? colors.textDark : colors.text }]}>
          This app requires iPhone Pro with LiDAR sensor for authenticated photo capture.
        </Text>
        {reason && (
          <Text style={[styles.unavailableReason, { color: colors.textSecondary }]}>
            {reason}
          </Text>
        )}
      </View>
    </SafeAreaView>
  );
}

/**
 * Capture screen with camera and depth overlay
 */
export default function CaptureScreen() {
  const router = useRouter();

  // Get device capabilities from store
  const capabilities = useDeviceStore((state) => state.capabilities);

  // Camera ref for future capture functionality
  const cameraRef = useRef<CameraViewHandle>(null);

  // Overlay visibility state
  const [overlayEnabled, setOverlayEnabled] = useState(true);

  // LiDAR status tracking
  const [lidarError, setLidarError] = useState<string | null>(null);

  // Capture hook for synchronized photo + depth + location capture
  const {
    capture,
    isCapturing,
    isReady: isCaptureReady,
    error: captureError,
    setCameraRef,
    clearError,
    requestLocationPermission,
    locationPermissionStatus,
  } = useCapture();

  // Processing hook for local processing pipeline (Story 3.5)
  const {
    processCapture,
    isProcessing,
    error: processingError,
    clearError: clearProcessingError,
  } = useCaptureProcessing();

  // Track if we've requested location permission (to avoid repeated prompts)
  const hasRequestedLocationPermission = useRef(false);

  // Handle LiDAR status callback
  const handleLiDARStatus = useCallback((available: boolean, error: string | null) => {
    if (!available && error) {
      setLidarError(error);
    } else {
      setLidarError(null);
    }
  }, []);

  // Handle overlay toggle
  const handleOverlayToggle = useCallback((enabled: boolean) => {
    setOverlayEnabled(enabled);
  }, []);

  // Handle capture button press
  const handleCapture = useCallback(async () => {
    // Request location permission on first capture if not yet requested
    if (!hasRequestedLocationPermission.current && locationPermissionStatus === 'undetermined') {
      hasRequestedLocationPermission.current = true;
      // Request permission asynchronously - don't block capture
      requestLocationPermission().then((granted) => {
        console.log(`[CaptureScreen] Location permission ${granted ? 'granted' : 'denied'}`);
      });
    }

    try {
      // Step 1: Capture photo + depth + location
      const rawCapture = await capture();
      console.log('[CaptureScreen] Capture successful:', {
        id: rawCapture.id,
        photoUri: rawCapture.photoUri,
        dimensions: `${rawCapture.photoWidth}x${rawCapture.photoHeight}`,
        syncDeltaMs: rawCapture.syncDeltaMs,
        depthSize: `${rawCapture.depthFrame.width}x${rawCapture.depthFrame.height}`,
        hasLocation: !!rawCapture.location,
        hasAssertion: !!rawCapture.assertion,
      });

      // Step 2: Process capture (hash, compress, assemble metadata)
      console.log('[CaptureScreen] Processing capture...');
      const processedCapture = await processCapture(rawCapture);
      console.log('[CaptureScreen] Processing complete:', {
        id: processedCapture.id,
        status: processedCapture.status,
        photoHashPrefix: processedCapture.photoHash.substring(0, 8) + '...',
      });

      // Step 3: Navigate to preview screen with processed capture data
      console.log('[CaptureScreen] Navigating to preview...');
      router.push({
        pathname: '/preview',
        params: { capture: JSON.stringify(processedCapture) },
      });
    } catch (err) {
      // Log the full error for debugging
      console.error('[CaptureScreen] Capture error:', err);
      const errorMessage =
        captureError?.message ||
        processingError?.message ||
        (err instanceof Error ? err.message : String(err)) ||
        'Failed to capture photo. Please try again.';
      Alert.alert('Capture Failed', errorMessage, [
        {
          text: 'OK',
          onPress: () => {
            clearError();
            clearProcessingError();
          },
        },
      ]);
    }
  }, [capture, captureError, clearError, processingError, clearProcessingError, locationPermissionStatus, requestLocationPermission, processCapture, router]);

  // Check if device has LiDAR capability
  if (!capabilities?.hasLiDAR) {
    return <LiDARUnavailable reason="Device does not have LiDAR sensor" />;
  }

  // Show LiDAR error if native check failed
  if (lidarError) {
    return <LiDARUnavailable reason={lidarError} />;
  }

  return (
    <View style={styles.container}>
      <CameraView
        ref={cameraRef}
        showOverlay={overlayEnabled}
        onOverlayToggle={handleOverlayToggle}
        onLiDARStatus={handleLiDARStatus}
        minDepth={0}
        maxDepth={5}
        overlayOpacity={0.4}
        onCapture={handleCapture}
        isCapturing={isCapturing || isProcessing}
        isCaptureReady={isCaptureReady}
        onCameraRef={setCameraRef}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  centered: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  unavailableContainer: {
    alignItems: 'center',
    paddingHorizontal: 24,
  },
  unavailableTitle: {
    fontSize: 24,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 16,
  },
  unavailableMessage: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 12,
    lineHeight: 24,
    opacity: 0.9,
  },
  unavailableReason: {
    fontSize: 14,
    textAlign: 'center',
    fontStyle: 'italic',
  },
});
