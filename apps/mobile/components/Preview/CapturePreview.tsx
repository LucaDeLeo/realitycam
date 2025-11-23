/**
 * CapturePreview Component
 *
 * Displays the captured photo with optional depth overlay toggle.
 * Shows full-resolution image with proper aspect ratio.
 *
 * @see Story 3.6 - Capture Preview Screen
 */

import { useState, useCallback } from 'react';
import {
  View,
  Image,
  StyleSheet,
  Dimensions,
  TouchableOpacity,
  Text,
  useColorScheme,
} from 'react-native';
import { colors } from '../../constants/colors';

interface CapturePreviewProps {
  /** Local file URI to captured photo */
  photoUri: string;
  /** Photo width for aspect ratio */
  photoWidth?: number;
  /** Photo height for aspect ratio */
  photoHeight?: number;
  /** Whether depth overlay is available */
  hasDepthData?: boolean;
  /** Additional styles for container */
  style?: object;
}

const { width: SCREEN_WIDTH } = Dimensions.get('window');

/**
 * Component to display captured photo with depth toggle
 */
export function CapturePreview({
  photoUri,
  photoWidth,
  photoHeight,
  hasDepthData = true,
  style,
}: CapturePreviewProps) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  // Depth overlay visibility state
  const [showDepthOverlay, setShowDepthOverlay] = useState(false);

  // Calculate aspect ratio for image display
  const aspectRatio =
    photoWidth && photoHeight ? photoWidth / photoHeight : 4 / 3;
  const imageHeight = SCREEN_WIDTH / aspectRatio;

  /**
   * Toggle depth overlay visibility
   */
  const handleToggleDepth = useCallback(() => {
    setShowDepthOverlay((prev) => !prev);
  }, []);

  return (
    <View style={[styles.container, style]}>
      {/* Photo Container */}
      <View style={styles.imageContainer}>
        <Image
          source={{ uri: photoUri }}
          style={[styles.image, { width: SCREEN_WIDTH, height: imageHeight }]}
          resizeMode="contain"
        />

        {/* Depth Overlay Placeholder */}
        {showDepthOverlay && hasDepthData && (
          <View
            style={[
              styles.depthOverlay,
              { width: SCREEN_WIDTH, height: imageHeight },
            ]}
          >
            <Text style={styles.depthOverlayText}>Depth Overlay</Text>
            <Text style={styles.depthOverlaySubtext}>
              (Visualization coming in Epic 4)
            </Text>
          </View>
        )}
      </View>

      {/* Depth Toggle Button */}
      {hasDepthData && (
        <TouchableOpacity
          style={[
            styles.depthToggle,
            showDepthOverlay && styles.depthToggleActive,
          ]}
          onPress={handleToggleDepth}
          activeOpacity={0.7}
        >
          <Text
            style={[
              styles.depthToggleText,
              showDepthOverlay && styles.depthToggleTextActive,
            ]}
          >
            {showDepthOverlay ? 'Hide Depth' : 'Show Depth'}
          </Text>
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
  },
  imageContainer: {
    position: 'relative',
    backgroundColor: '#000000',
  },
  image: {
    backgroundColor: '#000000',
  },
  depthOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    backgroundColor: 'rgba(0, 122, 255, 0.4)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  depthOverlayText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '600',
  },
  depthOverlaySubtext: {
    color: '#FFFFFF',
    fontSize: 12,
    marginTop: 4,
    opacity: 0.8,
  },
  depthToggle: {
    position: 'absolute',
    top: 16,
    right: 16,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
  },
  depthToggleActive: {
    backgroundColor: colors.primary,
  },
  depthToggleText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
  },
  depthToggleTextActive: {
    color: '#FFFFFF',
  },
});
