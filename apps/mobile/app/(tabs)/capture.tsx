/**
 * Capture Screen
 *
 * Main camera capture screen with LiDAR depth overlay.
 * Displays camera preview with real-time depth visualization.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 */

import { useState, useCallback, useRef } from 'react';
import { View, Text, StyleSheet, useColorScheme } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView, CameraViewHandle } from '../../components/Camera';
import { useDeviceStore } from '../../store/deviceStore';
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
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  // Get device capabilities from store
  const capabilities = useDeviceStore((state) => state.capabilities);

  // Camera ref for future capture functionality
  const cameraRef = useRef<CameraViewHandle>(null);

  // Overlay visibility state
  const [overlayEnabled, setOverlayEnabled] = useState(true);

  // LiDAR status tracking
  const [lidarError, setLidarError] = useState<string | null>(null);

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

  // Check if device has LiDAR capability
  // This is a double-check - the device store should already show LiDAR
  // But the native module provides runtime verification
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
