/**
 * CameraView Component
 *
 * Container component integrating expo-camera with LiDAR depth overlay.
 * Manages camera permissions and depth capture lifecycle.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 */

import React, { useEffect, useRef, useState, useCallback, forwardRef, useImperativeHandle } from 'react';
import {
  View,
  Text,
  StyleSheet,
  useColorScheme,
  ActivityIndicator,
} from 'react-native';
import { CameraView as ExpoCameraView, CameraType, useCameraPermissions } from 'expo-camera';
import type { DepthFrame } from '@realitycam/shared';
import { useLiDAR } from '../../hooks/useLiDAR';
import { DepthOverlay } from './DepthOverlay';
import { DepthToggle } from './DepthToggle';
import { colors } from '../../constants/colors';

interface CameraViewProps {
  /** Whether to show depth overlay (default true) */
  showOverlay?: boolean;
  /** Callback when depth overlay toggle changes */
  onOverlayToggle?: (enabled: boolean) => void;
  /** Callback when LiDAR availability is determined */
  onLiDARStatus?: (available: boolean, error: string | null) => void;
  /** Depth overlay min depth in meters */
  minDepth?: number;
  /** Depth overlay max depth in meters */
  maxDepth?: number;
  /** Depth overlay opacity */
  overlayOpacity?: number;
}

/**
 * Ref handle for CameraView
 */
export interface CameraViewHandle {
  /** Capture a depth frame */
  captureDepthFrame: () => Promise<DepthFrame>;
  /** Get current depth frame without triggering new capture */
  getCurrentFrame: () => DepthFrame | null;
  /** Start depth capture if not already running */
  startDepthCapture: () => Promise<void>;
  /** Stop depth capture */
  stopDepthCapture: () => Promise<void>;
}

/**
 * CameraView with LiDAR depth overlay
 *
 * Features:
 * - Camera preview using expo-camera
 * - Real-time depth overlay from LiDAR
 * - Toggle button for overlay visibility
 * - Permission handling
 * - LiDAR lifecycle management
 *
 * @example
 * ```tsx
 * const cameraRef = useRef<CameraViewHandle>(null);
 *
 * const handleCapture = async () => {
 *   const frame = await cameraRef.current?.captureDepthFrame();
 *   // Use depth frame...
 * };
 *
 * <CameraView
 *   ref={cameraRef}
 *   showOverlay={true}
 *   onLiDARStatus={(available, error) => {
 *     if (!available) console.log('LiDAR not available:', error);
 *   }}
 * />
 * ```
 */
export const CameraView = forwardRef<CameraViewHandle, CameraViewProps>(function CameraView(
  {
    showOverlay: initialShowOverlay = true,
    onOverlayToggle,
    onLiDARStatus,
    minDepth = 0,
    maxDepth = 5,
    overlayOpacity = 0.4,
  },
  ref
) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  // Camera permissions
  const [permission, requestPermission] = useCameraPermissions();

  // Local overlay state
  const [overlayEnabled, setOverlayEnabled] = useState(initialShowOverlay);

  // LiDAR hook
  const {
    isAvailable,
    isReady,
    startDepthCapture,
    stopDepthCapture,
    captureDepthFrame,
    currentFrame,
    error: lidarError,
  } = useLiDAR();

  // Camera ref for future photo capture
  const cameraRef = useRef<ExpoCameraView>(null);

  // Report LiDAR status to parent
  useEffect(() => {
    // Wait until we have a definitive status
    if (isAvailable || lidarError) {
      onLiDARStatus?.(isAvailable, lidarError);
    }
  }, [isAvailable, lidarError, onLiDARStatus]);

  // Start depth capture when camera is ready and LiDAR is available
  useEffect(() => {
    if (permission?.granted && isAvailable && !isReady) {
      startDepthCapture();
    }
  }, [permission?.granted, isAvailable, isReady, startDepthCapture]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopDepthCapture();
    };
  }, [stopDepthCapture]);

  // Handle overlay toggle
  const handleOverlayToggle = useCallback(() => {
    const newState = !overlayEnabled;
    setOverlayEnabled(newState);
    onOverlayToggle?.(newState);
  }, [overlayEnabled, onOverlayToggle]);

  // Expose methods via ref
  useImperativeHandle(ref, () => ({
    captureDepthFrame,
    getCurrentFrame: () => currentFrame,
    startDepthCapture,
    stopDepthCapture,
  }), [captureDepthFrame, currentFrame, startDepthCapture, stopDepthCapture]);

  // Handle camera permission
  if (!permission) {
    return (
      <View style={[styles.container, styles.centered, { backgroundColor: isDark ? colors.backgroundDark : colors.background }]}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={[styles.statusText, { color: isDark ? colors.textDark : colors.text }]}>
          Checking camera permissions...
        </Text>
      </View>
    );
  }

  if (!permission.granted) {
    return (
      <View style={[styles.container, styles.centered, { backgroundColor: isDark ? colors.backgroundDark : colors.background }]}>
        <Text style={[styles.statusText, { color: isDark ? colors.textDark : colors.text }]}>
          Camera access is required
        </Text>
        <Text
          style={[styles.permissionButton, { color: colors.primary }]}
          onPress={requestPermission}
        >
          Grant Permission
        </Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Camera Preview */}
      <ExpoCameraView
        ref={cameraRef}
        style={styles.camera}
        facing="back"
        mode="picture"
      />

      {/* Depth Overlay */}
      <DepthOverlay
        depthFrame={currentFrame}
        visible={overlayEnabled && isReady}
        minDepth={minDepth}
        maxDepth={maxDepth}
        opacity={overlayOpacity}
      />

      {/* Controls Overlay */}
      <View style={styles.controls}>
        {/* Depth Toggle Button */}
        <View style={styles.toggleContainer}>
          <DepthToggle
            enabled={overlayEnabled}
            onToggle={handleOverlayToggle}
            disabled={!isAvailable || !isReady}
          />
        </View>

        {/* Status Indicator */}
        {!isReady && isAvailable && (
          <View style={styles.statusContainer}>
            <ActivityIndicator size="small" color="#FFFFFF" />
            <Text style={styles.statusLabel}>Initializing depth sensor...</Text>
          </View>
        )}
      </View>
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  centered: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  camera: {
    ...StyleSheet.absoluteFillObject,
  },
  controls: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 20,
  },
  toggleContainer: {
    position: 'absolute',
    top: 60,
    right: 20,
  },
  statusContainer: {
    position: 'absolute',
    bottom: 100,
    left: 0,
    right: 0,
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 8,
  },
  statusLabel: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '500',
    textShadowColor: 'rgba(0, 0, 0, 0.5)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
  },
  statusText: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 16,
  },
  permissionButton: {
    fontSize: 16,
    fontWeight: '600',
    padding: 12,
  },
});
