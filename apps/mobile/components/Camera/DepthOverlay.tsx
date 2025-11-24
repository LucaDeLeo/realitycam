/**
 * DepthOverlay Component
 *
 * Renders a depth heatmap overlay from LiDAR depth frame data.
 * Uses viridis-inspired colormap: near = warm (red/orange), far = cool (blue/purple)
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 */

import React, { useMemo } from 'react';
import { View, Image, StyleSheet, Dimensions } from 'react-native';
import type { DepthFrame } from '@realitycam/shared';

interface DepthOverlayProps {
  /** Depth frame from LiDAR sensor */
  depthFrame: DepthFrame | null;
  /** Whether overlay is visible */
  visible: boolean;
  /** Minimum depth in meters (default 0) */
  minDepth?: number;
  /** Maximum depth in meters (default 5) */
  maxDepth?: number;
  /** Overlay opacity 0-1 (default 0.4) */
  opacity?: number;
}

/**
 * Convert depth value to RGB color using viridis-inspired colormap
 * Near objects = warm (red/orange), Far objects = cool (blue/purple)
 *
 * @param depth - Depth value in meters
 * @param minDepth - Minimum depth for normalization
 * @param maxDepth - Maximum depth for normalization
 * @returns RGB tuple [r, g, b] with values 0-255
 */
function depthToColor(
  depth: number,
  minDepth: number = 0,
  maxDepth: number = 5
): [number, number, number] {
  // Normalize depth to 0-1 range
  const normalized = Math.max(0, Math.min(1, (depth - minDepth) / (maxDepth - minDepth)));

  // Viridis-inspired colormap: near = warm, far = cool
  // Red channel: high for near, low for far
  const r = Math.floor(255 * (1 - normalized));
  // Green channel: peaks in middle distances
  const g = Math.floor(255 * Math.abs(normalized - 0.5) * 2);
  // Blue channel: low for near, high for far
  const b = Math.floor(255 * normalized);

  return [r, g, b];
}

/**
 * Decode base64 depth map to Float32Array
 */
function decodeDepthMap(base64: string): Float32Array {
  try {
    // Decode base64 to binary string
    const binaryString = atob(base64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    // Create Float32Array view
    return new Float32Array(bytes.buffer);
  } catch (error) {
    console.error('[DepthOverlay] Failed to decode depth map:', error);
    return new Float32Array(0);
  }
}

/**
 * Generate depth visualization as data URI
 * Creates a colored image from depth values
 */
function generateDepthImageUri(
  depthFrame: DepthFrame,
  minDepth: number,
  maxDepth: number
): string {
  const { depthMap, width, height } = depthFrame;

  // Decode depth data
  const depths = decodeDepthMap(depthMap);

  if (depths.length === 0 || depths.length !== width * height) {
    console.warn('[DepthOverlay] Invalid depth data length');
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
    rgba[pixelIndex + 3] = 255; // Full opacity in the image itself
  }

  // Convert to PNG data URI using raw pixel approach
  // For React Native, we'll use a simplified BMP format
  const bmpDataUri = createBmpDataUri(rgba, width, height);

  return bmpDataUri;
}

/**
 * Create a BMP data URI from RGBA pixel data
 * BMP is simpler than PNG and works well for this use case
 */
function createBmpDataUri(rgba: Uint8ClampedArray, width: number, height: number): string {
  // BMP header (54 bytes) + pixel data
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

  // Reserved
  bmp[6] = 0;
  bmp[7] = 0;
  bmp[8] = 0;
  bmp[9] = 0;

  // Pixel data offset
  bmp[10] = 54;
  bmp[11] = 0;
  bmp[12] = 0;
  bmp[13] = 0;

  // DIB Header (BITMAPINFOHEADER)
  bmp[14] = 40; // Header size
  bmp[15] = 0;
  bmp[16] = 0;
  bmp[17] = 0;

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
  bmp[27] = 0;

  // Bits per pixel (24)
  bmp[28] = 24;
  bmp[29] = 0;

  // Compression (0 = none)
  bmp[30] = 0;
  bmp[31] = 0;
  bmp[32] = 0;
  bmp[33] = 0;

  // Image size (can be 0 for uncompressed)
  bmp[34] = pixelDataSize & 0xff;
  bmp[35] = (pixelDataSize >> 8) & 0xff;
  bmp[36] = (pixelDataSize >> 16) & 0xff;
  bmp[37] = (pixelDataSize >> 24) & 0xff;

  // X/Y pixels per meter (unused)
  bmp[38] = 0;
  bmp[39] = 0;
  bmp[40] = 0;
  bmp[41] = 0;
  bmp[42] = 0;
  bmp[43] = 0;
  bmp[44] = 0;
  bmp[45] = 0;

  // Colors in palette (0 = default)
  bmp[46] = 0;
  bmp[47] = 0;
  bmp[48] = 0;
  bmp[49] = 0;

  // Important colors (0 = all)
  bmp[50] = 0;
  bmp[51] = 0;
  bmp[52] = 0;
  bmp[53] = 0;

  // Pixel data (BGR format, top-down with negative height)
  let offset = 54;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      bmp[offset++] = rgba[i + 2]; // B
      bmp[offset++] = rgba[i + 1]; // G
      bmp[offset++] = rgba[i]; // R
    }
    // Row padding
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
 * DepthOverlay component for displaying LiDAR depth visualization
 */
export function DepthOverlay({
  depthFrame,
  visible,
  minDepth = 0,
  maxDepth = 5,
  opacity = 0.4,
}: DepthOverlayProps) {
  // Generate depth image URI (memoized to avoid recalculation)
  const depthImageUri = useMemo(() => {
    if (!depthFrame || !visible) return '';
    return generateDepthImageUri(depthFrame, minDepth, maxDepth);
  }, [depthFrame, visible, minDepth, maxDepth]);

  // Don't render if not visible or no frame
  if (!visible || !depthFrame || !depthImageUri) {
    return null;
  }

  return (
    <View style={styles.container} pointerEvents="none">
      <Image
        source={{ uri: depthImageUri }}
        style={[styles.overlay, { opacity }]}
        resizeMode="cover"
      />
    </View>
  );
}

const { width: screenWidth, height: screenHeight } = Dimensions.get('window');

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 10,
    justifyContent: 'center',
    alignItems: 'center',
  },
  overlay: {
    // ARKit depth is always 256×192 (landscape). For portrait mode,
    // we rotate -90° and scale to fill the screen.
    // After rotation, the depth's 256px width becomes vertical (height)
    // and 192px height becomes horizontal (width).
    width: screenHeight,  // Fills vertical after rotation
    height: screenWidth,  // Fills horizontal after rotation
    transform: [{ rotate: '90deg' }],
  },
});
