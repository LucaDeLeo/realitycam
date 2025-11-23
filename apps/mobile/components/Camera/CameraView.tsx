/**
 * CameraView Component
 *
 * Container component integrating expo-camera with LiDAR depth overlay.
 * Manages camera permissions and depth capture lifecycle.
 * Includes CaptureButton for synchronized photo + depth capture.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 * @see Story 3.2 - Photo Capture with Depth Map
 */

import React, { useEffect, useRef, useState, useCallback, forwardRef, useImperativeHandle } from 'react';
import {
  View,
  Text,
  StyleSheet,
  useColorScheme,
  ActivityIndicator,
  TouchableOpacity,
  Platform,
} from 'react-native';
import { CameraView as ExpoCameraView, CameraType, useCameraPermissions } from 'expo-camera';
import { Ionicons } from '@expo/vector-icons';
import type { DepthFrame } from '@realitycam/shared';
import { useLiDAR } from '../../hooks/useLiDAR';
import { DepthOverlay } from './DepthOverlay';
import { DepthToggle } from './DepthToggle';
import { CaptureButton } from './CaptureButton';
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
  /** Callback when capture button is pressed */
  onCapture?: () => void;
  /** Whether capture is in progress (disables button) */
  isCapturing?: boolean;
  /** Whether capture is ready (enables button) */
  isCaptureReady?: boolean;
  /** Callback to receive camera ref for useCapture hook */
  onCameraRef?: (ref: ExpoCameraView | null) => void;
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
    onCapture,
    isCapturing = false,
    isCaptureReady = true,
    onCameraRef,
  },
  ref
) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  // Camera permissions
  const [permission, requestPermission] = useCameraPermissions();

  // Local overlay state
  const [overlayEnabled, setOverlayEnabled] = useState(initialShowOverlay);
  
  // Camera facing state (front/back)
  const [facing, setFacing] = useState<CameraType>('back');
  
  // Zoom state - actual zoom value for camera (0 to 1 where 0 = 1x, 0.5 = 2x, 1 = max zoom)
  const [zoom, setZoom] = useState<number>(0);
  
  // Zoom level for display
  const [zoomLevel, setZoomLevel] = useState<'0.5' | '1' | '2'>('1');

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

  // Camera ref for photo capture
  const cameraRef = useRef<ExpoCameraView>(null);
  const [cameraReady, setCameraReady] = useState(false);

  // Provide camera ref to parent via callback
  const setCameraRef = useCallback(
    (ref: ExpoCameraView | null) => {
      (cameraRef as React.MutableRefObject<ExpoCameraView | null>).current = ref;
      setCameraReady(ref !== null);
      onCameraRef?.(ref);
    },
    [onCameraRef]
  );

  // Report LiDAR status to parent
  useEffect(() => {
    // Wait until we have a definitive status
    // In development mode, always report as available (even if not) to allow camera to work
    if (isAvailable || lidarError) {
      onLiDARStatus?.(isAvailable, lidarError);
    } else {
      // Report as available in development mode even if LiDAR check hasn't completed
      // This allows camera to work without LiDAR
      onLiDARStatus?.(true, null);
    }
  }, [isAvailable, lidarError, onLiDARStatus]);

  // DISABLED: Start depth capture when camera is ready and LiDAR is available
  // Temporarily disabled for development/testing in Expo Go
  // useEffect(() => {
  //   if (permission?.granted && isAvailable && !isReady) {
  //     startDepthCapture();
  //   }
  // }, [permission?.granted, isAvailable, isReady, startDepthCapture]);

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

  // Handle camera flip
  const handleFlipCamera = useCallback(() => {
    setFacing((current) => {
      const newFacing = current === 'back' ? 'front' : 'back';
      // Reset camera ready state when flipping
      setCameraReady(false);
      return newFacing;
    });
  }, []);
  
  // Handle zoom change
  const handleZoomChange = useCallback((level: '0.5' | '1' | '2') => {
    console.log(`[CameraView] Zoom change requested: ${level}x`);
    setZoomLevel(level);
    
    // Map zoom level to camera zoom value (0-1)
    // Note: Expo Camera zoom is 0-1 where 0 = no zoom, 1 = max zoom
    // Ultra-wide (0.5x) is NOT supported in Expo Go - requires native development build
    if (level === '0.5') {
      // Ultra-wide not available in Expo Go - would need native module
      console.warn('[CameraView] Ultra-wide (0.5x) not available in Expo Go. Use development build for native lens access.');
      setZoom(0); // Keep at 1x for now
    } else if (level === '1') {
      // Default zoom (1x)
      setZoom(0);
      console.log('[CameraView] Zoom set to 1x (default)');
    } else if (level === '2') {
      // 2x digital zoom - use zoom value of ~0.5 (adjust as needed)
      setZoom(0.5);
      console.log('[CameraView] Zoom set to 2x (digital zoom: 0.5)');
    }
  }, []);

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
        key={facing} // Force re-render when facing changes
        ref={setCameraRef}
        style={styles.camera}
        facing={facing}
        mode="picture"
        zoom={zoom}
        onCameraReady={() => {
          setCameraReady(true);
        }}
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
        {/* Bottom Controls */}
        <View style={styles.bottomControls}>
          {/* Zoom Buttons (0.5, 1×, 2×) */}
          <View style={styles.zoomSelector}>
            <TouchableOpacity
              style={[
                styles.zoomButton, 
                zoomLevel === '0.5' && styles.zoomButtonActive,
                styles.zoomButtonDisabled // Ultra-wide not available in Expo Go
              ]}
              onPress={() => handleZoomChange('0.5')}
              activeOpacity={0.7}
            >
              <Text style={[
                styles.zoomText, 
                zoomLevel === '0.5' && styles.zoomTextActive,
                styles.zoomTextDisabled
              ]}>
                0,5
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.zoomButton, zoomLevel === '1' && styles.zoomButtonActive]}
              onPress={() => handleZoomChange('1')}
              activeOpacity={0.7}
            >
              <Text style={[styles.zoomText, zoomLevel === '1' && styles.zoomTextActive]}>
                1×
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.zoomButton, zoomLevel === '2' && styles.zoomButtonActive]}
              onPress={() => handleZoomChange('2')}
              activeOpacity={0.7}
            >
              <Text style={[styles.zoomText, zoomLevel === '2' && styles.zoomTextActive]}>
                2×
              </Text>
            </TouchableOpacity>
          </View>

          {/* Capture Controls - Capture Button and Flip Camera Button aligned horizontally */}
          {onCapture && (
            <View style={styles.captureRow}>
              {/* Empty space on left for symmetry */}
              <View style={styles.captureLeftSpace} />
              
              {/* Capture Button - Center */}
              <View style={styles.captureButtonContainer}>
                <CaptureButton
                  onCapture={onCapture}
                  isCapturing={isCapturing}
                  disabled={!permission?.granted || !cameraReady}
                />
              </View>
              
              {/* Flip Camera Button - Right */}
              <TouchableOpacity
                style={styles.flipButton}
                onPress={handleFlipCamera}
                activeOpacity={0.7}
                accessibilityLabel={facing === 'back' ? 'Switch to front camera' : 'Switch to back camera'}
                accessibilityRole="button"
              >
                <Ionicons name="camera-reverse-outline" size={28} color="#FFFFFF" />
              </TouchableOpacity>
            </View>
          )}
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
    backgroundColor: '#000000',
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
  bottomControls: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    paddingBottom: Platform.OS === 'ios' ? 40 : 30,
    alignItems: 'center',
  },
  zoomSelector: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    marginBottom: 20,
  },
  zoomButton: {
    width: 48,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.2)',
  },
  zoomButtonActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    borderColor: 'rgba(255, 255, 255, 0.9)',
  },
  zoomButtonDisabled: {
    opacity: 0.5,
  },
  zoomText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '600',
  },
  zoomTextActive: {
    color: '#000000',
    fontWeight: '700',
  },
  zoomTextDisabled: {
    opacity: 0.6,
  },
  captureRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
    paddingHorizontal: 40,
  },
  captureLeftSpace: {
    width: 60,
  },
  captureButtonContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  flipButton: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: 'rgba(255, 255, 255, 0.2)',
  },
  statusContainer: {
    position: 'absolute',
    bottom: 200,
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
    color: '#FFFFFF',
  },
  permissionButton: {
    fontSize: 16,
    fontWeight: '600',
    padding: 12,
    color: '#FFD60A',
  },
});
