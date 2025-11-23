/**
 * CameraView Component
 *
 * Container component integrating react-native-vision-camera with LiDAR depth overlay.
 * Manages camera permissions and depth capture lifecycle.
 * Includes CaptureButton for synchronized photo + depth capture.
 *
 * Features:
 * - Physical lens switching: 0.5x (ultra-wide), 1x (wide), 2x (telephoto)
 * - Real-time depth overlay from LiDAR
 * - Toggle button for overlay visibility
 * - Permission handling
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
import {
  Camera,
  useCameraDevice,
  useCameraPermission,
  CameraPosition,
} from 'react-native-vision-camera';
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
  onCameraRef?: (ref: Camera | null) => void;
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

/** Zoom level for UI buttons */
type ZoomLevel = '0.5' | '1' | '2';

/**
 * CameraView with LiDAR depth overlay
 *
 * Features:
 * - Camera preview using react-native-vision-camera
 * - Physical lens switching (0.5x, 1x, 2x)
 * - Real-time depth overlay from LiDAR
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
    onCameraRef,
  },
  ref
) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  // Camera permissions (vision-camera)
  const { hasPermission, requestPermission } = useCameraPermission();

  // Local overlay state
  const [overlayEnabled, setOverlayEnabled] = useState(initialShowOverlay);

  // Camera position state (front/back)
  const [position, setPosition] = useState<CameraPosition>('back');

  // Zoom state
  const [zoomLevel, setZoomLevel] = useState<ZoomLevel>('1');
  const [zoom, setZoom] = useState<number>(1);

  // Camera ready state
  const [cameraReady, setCameraReady] = useState(false);

  // Camera ref for photo capture
  const cameraRef = useRef<Camera>(null);

  // Select best available device for the current position (front/back)
  // Auto-selects multi-camera setups on Pro devices (ultra-wide, wide, telephoto)
  const device = useCameraDevice(position);

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

  // Provide camera ref to parent via callback
  const setCameraRefCallback = useCallback(
    (ref: Camera | null) => {
      (cameraRef as React.MutableRefObject<Camera | null>).current = ref;
      onCameraRef?.(ref);
    },
    [onCameraRef]
  );

  // Initialize zoom to neutral (1x) when device changes
  useEffect(() => {
    if (device?.neutralZoom) {
      setZoom(device.neutralZoom);
      setZoomLevel('1');
    }
  }, [device]);

  // Request permission on first load if not already granted
  const hasRequestedPermission = useRef(false);
  const [isRequestingPermission, setIsRequestingPermission] = useState(false);
  useEffect(() => {
    if (!hasPermission && !hasRequestedPermission.current) {
      hasRequestedPermission.current = true;
      setIsRequestingPermission(true);
      requestPermission()
        .catch((error) => console.warn('Camera permission request failed:', error))
        .finally(() => setIsRequestingPermission(false));
    }
  }, [hasPermission, requestPermission]);

  // Report LiDAR status to parent
  useEffect(() => {
    if (isAvailable || lidarError) {
      onLiDARStatus?.(isAvailable, lidarError);
    } else {
      // Report as available in development mode even if LiDAR check hasn't completed
      onLiDARStatus?.(true, null);
    }
  }, [isAvailable, lidarError, onLiDARStatus]);

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
    setPosition((p) => (p === 'back' ? 'front' : 'back'));
    setCameraReady(false);
  }, []);

  // Handle zoom level change
  const handleZoomChange = useCallback((level: ZoomLevel) => {
    if (!device) return;

    setZoomLevel(level);
    const neutralZoom = device.neutralZoom ?? 1;

    switch (level) {
      case '0.5':
        // Ultra-wide: half of neutral zoom (clamped to device min)
        setZoom(Math.max(device.minZoom, neutralZoom * 0.5));
        break;
      case '1':
        // Wide: neutral zoom
        setZoom(neutralZoom);
        break;
      case '2':
        // Telephoto: double neutral zoom (clamped to device max)
        setZoom(Math.min(device.maxZoom, neutralZoom * 2));
        break;
    }
  }, [device]);

  // Expose methods via ref
  useImperativeHandle(ref, () => ({
    captureDepthFrame,
    getCurrentFrame: () => currentFrame,
    startDepthCapture,
    stopDepthCapture,
  }), [captureDepthFrame, currentFrame, startDepthCapture, stopDepthCapture]);

  // While permission is being requested
  if (isRequestingPermission) {
    return (
      <View style={[styles.container, styles.centered, { backgroundColor: isDark ? colors.backgroundDark : colors.background }]}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={[styles.statusText, { color: isDark ? colors.textDark : colors.text }]}>
          Requesting camera permission...
        </Text>
      </View>
    );
  }

  // Permission not granted after request
  if (!hasPermission) {
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

  // Device still loading
  if (!device) {
    return (
      <View style={[styles.container, styles.centered, { backgroundColor: isDark ? colors.backgroundDark : colors.background }]}> 
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={[styles.statusText, { color: isDark ? colors.textDark : colors.text }]}> 
          Initializing camera...
        </Text>
      </View>
    );
  }

  // Check if ultra-wide is available on this device
  const hasUltraWide = device.physicalDevices?.includes('ultra-wide-angle-camera') ?? false;
  const hasTelephoto = device.physicalDevices?.includes('telephoto-camera') ?? false;

  return (
    <View style={styles.container}>
      {/* Camera Preview */}
      <Camera
        ref={(ref) => {
          setCameraRefCallback(ref);
        }}
        style={StyleSheet.absoluteFill}
        device={device}
        isActive={true}
        photo={true}
        zoom={zoom}
        onInitialized={() => setCameraReady(true)}
        onError={(error) => console.error('Camera error:', error)}
      />

      {/* Depth Overlay */}
      <DepthOverlay
        depthFrame={currentFrame}
        visible={overlayEnabled}
        minDepth={minDepth}
        maxDepth={maxDepth}
        opacity={overlayOpacity}
      />

      {/* Controls Overlay */}
      <View style={styles.controls}>
        {/* Top Controls */}
        <View style={styles.topControls}>
          <DepthToggle
            enabled={overlayEnabled}
            onToggle={handleOverlayToggle}
            // Allow toggle regardless of LiDAR availability so overlay isn't gated
            disabled={false}
          />
        </View>

        {/* Bottom Controls */}
        <View style={styles.bottomControls}>
          {/* Zoom Buttons (0.5, 1x, 2x) */}
          <View style={styles.zoomSelector}>
            <TouchableOpacity
              style={[
                styles.zoomButton,
                zoomLevel === '0.5' && styles.zoomButtonActive,
                !hasUltraWide && styles.zoomButtonDisabled,
              ]}
              onPress={() => handleZoomChange('0.5')}
              activeOpacity={0.7}
              disabled={!hasUltraWide}
            >
              <Text style={[
                styles.zoomText,
                zoomLevel === '0.5' && styles.zoomTextActive,
                !hasUltraWide && styles.zoomTextDisabled,
              ]}>
                0.5x
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.zoomButton, zoomLevel === '1' && styles.zoomButtonActive]}
              onPress={() => handleZoomChange('1')}
              activeOpacity={0.7}
            >
              <Text style={[styles.zoomText, zoomLevel === '1' && styles.zoomTextActive]}>
                1x
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[
                styles.zoomButton,
                zoomLevel === '2' && styles.zoomButtonActive,
                !hasTelephoto && styles.zoomButtonDisabled,
              ]}
              onPress={() => handleZoomChange('2')}
              activeOpacity={0.7}
              disabled={!hasTelephoto}
            >
              <Text style={[
                styles.zoomText,
                zoomLevel === '2' && styles.zoomTextActive,
              ]}>
                2x
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
                  disabled={!hasPermission || !cameraReady}
                />
              </View>

              {/* Flip Camera Button - Right */}
              <TouchableOpacity
                style={styles.flipButton}
                onPress={handleFlipCamera}
                activeOpacity={0.7}
                accessibilityLabel={position === 'back' ? 'Switch to front camera' : 'Switch to back camera'}
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
  controls: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 20,
  },
  topControls: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 56 : 24,
    right: 16,
    zIndex: 30,
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
