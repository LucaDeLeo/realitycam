/**
 * CapturePreview Component
 *
 * Displays the captured photo with optional depth overlay toggle.
 * Shows full-resolution image with proper aspect ratio.
 * Supports depth visualization from compressed (gzipped) depth map.
 *
 * @see Story 3.6 - Capture Preview Screen
 */

import { useState, useCallback, useMemo } from 'react';
import {
  View,
  Image,
  StyleSheet,
  Dimensions,
  TouchableOpacity,
  Text,
} from 'react-native';
import pako from 'pako';
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
  /** Compressed depth map (gzipped base64) */
  compressedDepthMap?: string;
  /** Depth map dimensions */
  depthDimensions?: { width: number; height: number };
  /** Additional styles for container */
  style?: object;
}

const { width: SCREEN_WIDTH } = Dimensions.get('window');

/**
 * Convert depth value to RGB color using viridis-inspired colormap
 * Near objects = warm (red/orange), Far objects = cool (blue/purple)
 */
function depthToColor(
  depth: number,
  minDepth: number = 0,
  maxDepth: number = 5
): [number, number, number] {
  // Normalize depth to 0-1 range
  const normalized = Math.max(0, Math.min(1, (depth - minDepth) / (maxDepth - minDepth)));

  // Viridis-inspired colormap: near = warm, far = cool
  const r = Math.floor(255 * (1 - normalized));
  const g = Math.floor(255 * Math.abs(normalized - 0.5) * 2);
  const b = Math.floor(255 * normalized);

  return [r, g, b];
}

/**
 * Decompress gzipped base64 depth map to Float32Array
 */
function decompressDepthMap(compressedBase64: string): Float32Array {
  try {
    // Decode base64 to Uint8Array
    const binaryString = atob(compressedBase64);
    const compressedBytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      compressedBytes[i] = binaryString.charCodeAt(i);
    }

    // Decompress with pako
    const decompressed = pako.ungzip(compressedBytes);

    // Create Float32Array from decompressed bytes
    return new Float32Array(decompressed.buffer);
  } catch (error) {
    console.error('[CapturePreview] Failed to decompress depth map:', error);
    return new Float32Array(0);
  }
}

/**
 * Create a BMP data URI from RGBA pixel data
 */
function createBmpDataUri(rgba: Uint8ClampedArray, width: number, height: number): string {
  const rowPadding = (4 - ((width * 3) % 4)) % 4;
  const rowSize = width * 3 + rowPadding;
  const pixelDataSize = rowSize * height;
  const fileSize = 54 + pixelDataSize;

  const bmp = new Uint8Array(fileSize);

  // BMP Header
  bmp[0] = 0x42; // 'B'
  bmp[1] = 0x4d; // 'M'

  // File size
  bmp[2] = fileSize & 0xff;
  bmp[3] = (fileSize >> 8) & 0xff;
  bmp[4] = (fileSize >> 16) & 0xff;
  bmp[5] = (fileSize >> 24) & 0xff;

  // Reserved (6-9)
  // Pixel data offset
  bmp[10] = 54;

  // DIB Header (BITMAPINFOHEADER)
  bmp[14] = 40;

  // Width
  bmp[18] = width & 0xff;
  bmp[19] = (width >> 8) & 0xff;
  bmp[20] = (width >> 16) & 0xff;
  bmp[21] = (width >> 24) & 0xff;

  // Height (negative for top-down)
  const negHeight = -height;
  bmp[22] = negHeight & 0xff;
  bmp[23] = (negHeight >> 8) & 0xff;
  bmp[24] = (negHeight >> 16) & 0xff;
  bmp[25] = (negHeight >> 24) & 0xff;

  // Planes
  bmp[26] = 1;

  // Bits per pixel (24)
  bmp[28] = 24;

  // Image size
  bmp[34] = pixelDataSize & 0xff;
  bmp[35] = (pixelDataSize >> 8) & 0xff;
  bmp[36] = (pixelDataSize >> 16) & 0xff;
  bmp[37] = (pixelDataSize >> 24) & 0xff;

  // Pixel data (BGR format)
  let offset = 54;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      bmp[offset++] = rgba[i + 2]; // B
      bmp[offset++] = rgba[i + 1]; // G
      bmp[offset++] = rgba[i]; // R
    }
    for (let p = 0; p < rowPadding; p++) {
      bmp[offset++] = 0;
    }
  }

  // Convert to base64
  let binary = '';
  for (let i = 0; i < bmp.length; i++) {
    binary += String.fromCharCode(bmp[i]);
  }
  const base64 = btoa(binary);

  return `data:image/bmp;base64,${base64}`;
}

/**
 * Generate depth visualization as data URI from compressed depth map
 */
function generateDepthImageUri(
  compressedDepthMap: string,
  width: number,
  height: number,
  minDepth: number = 0,
  maxDepth: number = 5
): string {
  // Decompress depth data
  const depths = decompressDepthMap(compressedDepthMap);

  if (depths.length === 0 || depths.length !== width * height) {
    console.warn('[CapturePreview] Invalid depth data:', {
      expected: width * height,
      got: depths.length,
    });
    return '';
  }

  // Create RGBA pixel data
  const rgba = new Uint8ClampedArray(width * height * 4);

  for (let i = 0; i < depths.length; i++) {
    const depth = depths[i];
    const [r, g, b] = depthToColor(depth, minDepth, maxDepth);

    const pixelIndex = i * 4;
    rgba[pixelIndex] = r;
    rgba[pixelIndex + 1] = g;
    rgba[pixelIndex + 2] = b;
    rgba[pixelIndex + 3] = 255;
  }

  return createBmpDataUri(rgba, width, height);
}

/**
 * Component to display captured photo with depth toggle
 */
export function CapturePreview({
  photoUri,
  photoWidth,
  photoHeight,
  hasDepthData = true,
  compressedDepthMap,
  depthDimensions,
  style,
}: CapturePreviewProps) {
  // Depth overlay visibility state
  const [showDepthOverlay, setShowDepthOverlay] = useState(false);

  // Calculate aspect ratio for image display
  const aspectRatio =
    photoWidth && photoHeight ? photoWidth / photoHeight : 4 / 3;
  const imageHeight = SCREEN_WIDTH / aspectRatio;

  // Generate depth image URI (memoized)
  const depthImageUri = useMemo(() => {
    if (!showDepthOverlay || !compressedDepthMap || !depthDimensions) return '';
    return generateDepthImageUri(
      compressedDepthMap,
      depthDimensions.width,
      depthDimensions.height
    );
  }, [showDepthOverlay, compressedDepthMap, depthDimensions]);

  /**
   * Toggle depth overlay visibility
   */
  const handleToggleDepth = useCallback(() => {
    setShowDepthOverlay((prev) => !prev);
  }, []);

  // Check if we actually have depth data to show
  const canShowDepth = hasDepthData && compressedDepthMap && depthDimensions;

  return (
    <View style={[styles.container, style]}>
      {/* Photo Container */}
      <View style={styles.imageContainer}>
        <Image
          source={{ uri: photoUri }}
          style={[styles.image, { width: SCREEN_WIDTH, height: imageHeight }]}
          resizeMode="contain"
        />

        {/* Depth Overlay - Real visualization */}
        {showDepthOverlay && depthImageUri && (
          <Image
            source={{ uri: depthImageUri }}
            style={[
              styles.depthOverlayImage,
              { width: SCREEN_WIDTH, height: imageHeight, opacity: 0.6 },
            ]}
            resizeMode="cover"
          />
        )}

        {/* Fallback when no depth data */}
        {showDepthOverlay && !depthImageUri && hasDepthData && (
          <View
            style={[
              styles.depthOverlayPlaceholder,
              { width: SCREEN_WIDTH, height: imageHeight },
            ]}
          >
            <Text style={styles.depthOverlayText}>Depth Unavailable</Text>
          </View>
        )}
      </View>

      {/* Depth Toggle Button */}
      {canShowDepth && (
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
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
  },
  image: {
    backgroundColor: '#000000',
    width: '100%',
  },
  depthOverlayImage: {
    position: 'absolute',
    top: 0,
    left: 0,
  },
  depthOverlayPlaceholder: {
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
