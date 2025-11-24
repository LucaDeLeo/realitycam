/**
 * useCaptureProcessing Hook
 *
 * Processes raw captures into upload-ready packages with compressed depth maps,
 * computed hashes, and assembled metadata.
 *
 * Features:
 * - Gzip compression of depth map data using pako
 * - SHA-256 hash computation of photo bytes using expo-crypto
 * - Metadata assembly with device model and optional location/assertion
 * - Base64 encoding for transport
 *
 * @see Story 3.5 - Local Processing Pipeline
 */

import { useCallback, useState } from 'react';
import * as Crypto from 'expo-crypto';
import * as FileSystem from 'expo-file-system/legacy';
import pako from 'pako';

import { useDeviceStore } from '../store/deviceStore';
import type {
  RawCapture,
  ProcessedCapture,
  CaptureMetadata,
  ProcessingError,
} from '@realitycam/shared';

/**
 * useCaptureProcessing hook return type
 */
export interface UseCaptureProcessingReturn {
  /** Process raw capture into upload-ready package */
  processCapture: (raw: RawCapture) => Promise<ProcessedCapture>;
  /** Whether processing is in progress */
  isProcessing: boolean;
  /** Error from last operation (null if none) */
  error: ProcessingError | null;
  /** Clear error state */
  clearError: () => void;
}

/**
 * Convert base64 string to Uint8Array
 */
function base64ToBytes(base64: string): Uint8Array {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

/**
 * Convert Uint8Array to base64 string
 */
function bytesToBase64(bytes: Uint8Array): string {
  let binaryString = '';
  for (let i = 0; i < bytes.length; i++) {
    binaryString += String.fromCharCode(bytes[i]);
  }
  return btoa(binaryString);
}

/**
 * Compress depth map data with gzip
 * Input: base64-encoded Float32Array depth map
 * Output: base64-encoded gzipped data
 */
function compressDepthMap(depthMapBase64: string): string {
  // Decode base64 to bytes
  const depthBytes = base64ToBytes(depthMapBase64);

  // Gzip compress the bytes
  const compressed = pako.gzip(depthBytes);

  // Encode compressed data back to base64 for storage
  return bytesToBase64(compressed);
}

/**
 * Hook for processing raw captures into upload-ready packages
 *
 * @example
 * ```tsx
 * const { processCapture, isProcessing, error } = useCaptureProcessing();
 *
 * const handleCapture = async (rawCapture: RawCapture) => {
 *   try {
 *     const processed = await processCapture(rawCapture);
 *     console.log('Ready for upload:', processed.id);
 *   } catch (err) {
 *     console.error('Processing failed:', err);
 *   }
 * };
 * ```
 */
export function useCaptureProcessing(): UseCaptureProcessingReturn {
  // Get device model from store
  const capabilities = useDeviceStore((state) => state.capabilities);

  // Processing state
  const [isProcessing, setIsProcessing] = useState(false);
  const [error, setError] = useState<ProcessingError | null>(null);

  /**
   * Clear error state
   */
  const clearError = useCallback(() => {
    setError(null);
  }, []);

  /**
   * Process raw capture into upload-ready package
   */
  const processCapture = useCallback(
    async (raw: RawCapture): Promise<ProcessedCapture> => {
      setIsProcessing(true);
      setError(null);

      console.log('[useCaptureProcessing] Starting processing for capture:', raw.id);

      try {
        // 1. Read photo file and compute SHA-256 hash
        console.log('[useCaptureProcessing] Computing photo hash...');
        let photoHash: string;
        try {
          // Use legacy API
          const photoBase64 = await FileSystem.readAsStringAsync(raw.photoUri, {
            encoding: FileSystem.EncodingType.Base64,
          });
          photoHash = await Crypto.digestStringAsync(
            Crypto.CryptoDigestAlgorithm.SHA256,
            photoBase64,
            { encoding: Crypto.CryptoEncoding.BASE64 }
          );
          console.log('[useCaptureProcessing] Photo hash computed successfully');
        } catch (fileError) {
          console.error('[useCaptureProcessing] Failed to read photo file:', fileError);
          const processingError: ProcessingError = {
            code: 'FILE_READ_FAILED',
            message: 'Failed to read captured photo. Please try again.',
          };
          setError(processingError);
          setIsProcessing(false);
          throw processingError;
        }

        // 2. Compress depth map with gzip
        console.log('[useCaptureProcessing] Compressing depth map...');
        let compressedDepthMap: string;
        try {
          const originalSize = raw.depthFrame.depthMap.length;
          compressedDepthMap = compressDepthMap(raw.depthFrame.depthMap);
          const compressedSize = compressedDepthMap.length;
          console.log(
            `[useCaptureProcessing] Depth map compressed: ${originalSize} -> ${compressedSize} bytes (${Math.round((compressedSize / originalSize) * 100)}%)`
          );
        } catch (compressError) {
          console.error('[useCaptureProcessing] Failed to compress depth map:', compressError);
          const processingError: ProcessingError = {
            code: 'COMPRESSION_FAILED',
            message: 'Failed to compress depth data. Please try again.',
          };
          setError(processingError);
          setIsProcessing(false);
          throw processingError;
        }

        // 3. Get device model for metadata
        const deviceModel = capabilities?.model ?? 'Unknown iPhone';

        // 4. Assemble metadata for backend
        const metadata: CaptureMetadata = {
          captured_at: raw.capturedAt,
          device_model: deviceModel,
          photo_hash: photoHash,
          depth_map_dimensions: {
            width: raw.depthFrame.width,
            height: raw.depthFrame.height,
          },
          location: raw.location,
          assertion: raw.assertion?.assertion,
        };
        console.log('[useCaptureProcessing] Metadata assembled:', {
          device_model: metadata.device_model,
          depth_dimensions: metadata.depth_map_dimensions,
          has_location: !!metadata.location,
          has_assertion: !!metadata.assertion,
        });

        // 5. Construct processed capture
        const processed: ProcessedCapture = {
          id: raw.id,
          photoUri: raw.photoUri,
          photoHash,
          compressedDepthMap,
          depthDimensions: {
            width: raw.depthFrame.width,
            height: raw.depthFrame.height,
          },
          metadata,
          assertion: raw.assertion?.assertion,
          status: 'ready',
          createdAt: raw.capturedAt,
        };

        console.log('[useCaptureProcessing] Processing complete:', {
          id: processed.id,
          status: processed.status,
          photoHashPrefix: processed.photoHash.substring(0, 8) + '...',
          compressedDepthSize: processed.compressedDepthMap.length,
        });

        setIsProcessing(false);
        return processed;
      } catch (err) {
        // If error is already a ProcessingError, it's already handled
        if (err && typeof err === 'object' && 'code' in err) {
          throw err;
        }

        // Classify unknown errors
        console.error('[useCaptureProcessing] Unexpected error:', err);
        const processingError: ProcessingError = {
          code: 'UNKNOWN',
          message: 'An unexpected error occurred during processing.',
        };
        setError(processingError);
        setIsProcessing(false);
        throw processingError;
      }
    },
    [capabilities?.model]
  );

  return {
    processCapture,
    isProcessing,
    error,
    clearError,
  };
}
