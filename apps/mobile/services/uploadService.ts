/**
 * Upload Service
 *
 * Handles multipart upload of captures to the backend.
 * Includes device authentication headers and progress tracking.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic (AC-7)
 */

import * as FileSystem from 'expo-file-system/legacy';
import * as Crypto from 'expo-crypto';
import type {
  ProcessedCapture,
  CaptureUploadResponse,
  UploadError,
  UploadErrorCode,
} from '@realitycam/shared';
import { useDeviceStore } from '../store/deviceStore';

/**
 * API base URL from environment or localhost default
 */
const API_BASE_URL = (() => {
  // Prefer Expo public env on both dev and release builds (device-friendly)
  const envUrl =
    process.env.EXPO_PUBLIC_API_URL ||
    // @ts-expect-error Expo injects global env at build time
    (typeof globalThis !== 'undefined' ? globalThis.EXPO_PUBLIC_API_URL : undefined);
  return envUrl || 'http://localhost:8080';
})();

/**
 * Request timeout in milliseconds (60 seconds for uploads)
 */
const UPLOAD_TIMEOUT_MS = 60_000;

/**
 * Upload progress callback type
 */
export type UploadProgressCallback = (progress: number) => void;

/**
 * Convert base64 string to Uint8Array
 * Used for depth map and signature preparation
 */
function base64ToBytes(base64: string): Uint8Array {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const cleanBase64 = base64.replace(/=/g, '');
  const len = cleanBase64.length;
  const outputLen = Math.floor((len * 3) / 4);
  const bytes = new Uint8Array(outputLen);

  let p = 0;
  for (let i = 0; i < len; i += 4) {
    const c1 = chars.indexOf(cleanBase64[i]);
    const c2 = i + 1 < len ? chars.indexOf(cleanBase64[i + 1]) : 0;
    const c3 = i + 2 < len ? chars.indexOf(cleanBase64[i + 2]) : 0;
    const c4 = i + 3 < len ? chars.indexOf(cleanBase64[i + 3]) : 0;

    if (p < outputLen) bytes[p++] = (c1 << 2) | (c2 >> 4);
    if (p < outputLen) bytes[p++] = ((c2 & 15) << 4) | (c3 >> 2);
    if (p < outputLen) bytes[p++] = ((c3 & 3) << 6) | c4;
  }

  return bytes;
}

/**
 * Convert Uint8Array to base64 string
 */
function bytesToBase64(bytes: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  const len = bytes.length;

  for (let i = 0; i < len; i += 3) {
    const b1 = bytes[i];
    const b2 = i + 1 < len ? bytes[i + 1] : 0;
    const b3 = i + 2 < len ? bytes[i + 2] : 0;

    result += chars[b1 >> 2];
    result += chars[((b1 & 3) << 4) | (b2 >> 4)];
    result += i + 1 < len ? chars[((b2 & 15) << 2) | (b3 >> 6)] : '=';
    result += i + 2 < len ? chars[b3 & 63] : '=';
  }

  return result;
}

/**
 * Classify HTTP error response into UploadErrorCode
 */
function classifyHttpError(statusCode: number, retryAfter?: number): UploadError {
  switch (statusCode) {
    case 400:
      return {
        code: 'VALIDATION_ERROR',
        message: 'Invalid capture data. Please try again with a new capture.',
        statusCode,
      };
    case 401:
      return {
        code: 'AUTH_ERROR',
        message: 'Device authentication failed. Please restart the app.',
        statusCode,
      };
    case 404:
      return {
        code: 'NOT_FOUND',
        message: 'Device not registered. Please restart the app.',
        statusCode,
      };
    case 413:
      return {
        code: 'PAYLOAD_TOO_LARGE',
        message: 'Capture file is too large to upload.',
        statusCode,
      };
    case 429:
      return {
        code: 'RATE_LIMITED',
        message: 'Too many uploads. Please wait a moment.',
        statusCode,
        retryAfter,
      };
    default:
      if (statusCode >= 500) {
        return {
          code: 'SERVER_ERROR',
          message: 'Server is temporarily unavailable. Will retry.',
          statusCode,
        };
      }
      return {
        code: 'UNKNOWN',
        message: `Unexpected error (${statusCode})`,
        statusCode,
      };
  }
}

/**
 * Parse Retry-After header value (can be seconds or HTTP date)
 */
function parseRetryAfter(headerValue: string | null): number | undefined {
  if (!headerValue) return undefined;

  // Try to parse as number (seconds)
  const seconds = parseInt(headerValue, 10);
  if (!isNaN(seconds)) {
    return seconds;
  }

  // Try to parse as HTTP date
  try {
    const date = new Date(headerValue);
    const now = Date.now();
    const diffMs = date.getTime() - now;
    return Math.max(0, Math.ceil(diffMs / 1000));
  } catch {
    return undefined;
  }
}

/**
 * Build device authentication headers for upload request
 *
 * Headers:
 * - X-Device-Id: Device UUID from registration
 * - X-Device-Timestamp: Current Unix timestamp in milliseconds
 * - X-Device-Signature: Base64 signature of timestamp|body_hash
 *
 * Note: For MVP, signature is computed from timestamp and metadata hash.
 * Full implementation would use @expo/app-integrity generateAssertionAsync.
 */
async function buildDeviceAuthHeaders(
  metadataJson: string
): Promise<Record<string, string>> {
  // DEV MODE: Use hardcoded test device UUID
  // In production, this would come from device registration response stored in deviceStore
  const deviceId = '550e8400-e29b-41d4-a716-446655440000';
  const timestamp = Date.now().toString();

  // Compute hash of timestamp|metadata for signature
  const signaturePayload = `${timestamp}|${metadataJson}`;
  const signatureHash = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    signaturePayload,
    { encoding: Crypto.CryptoEncoding.BASE64 }
  );

  // Note: In production, this would use @expo/app-integrity generateAssertionAsync
  // For MVP, we use the hash as a placeholder signature
  const signature = signatureHash;

  return {
    'X-Device-Id': deviceId,
    'X-Device-Timestamp': timestamp,
    'X-Device-Signature': signature,
  };
}

/**
 * Upload result type
 */
export interface UploadResult {
  success: true;
  data: CaptureUploadResponse;
}

export interface UploadFailure {
  success: false;
  error: UploadError;
}

export type UploadOutcome = UploadResult | UploadFailure;

/**
 * Upload a processed capture to the backend
 *
 * POST /api/v1/captures
 * Content-Type: multipart/form-data
 *
 * Parts:
 * - photo: JPEG image file
 * - depth_map: Gzipped depth data
 * - metadata: JSON capture metadata
 *
 * @param capture - Processed capture ready for upload
 * @param onProgress - Optional progress callback (0-100)
 * @returns Upload result or failure with error details
 */
export async function uploadCapture(
  capture: ProcessedCapture,
  onProgress?: UploadProgressCallback
): Promise<UploadOutcome> {
  console.log('[uploadService] ========== UPLOAD START ==========');
  console.log('[uploadService] Capture ID:', capture.id);
  console.log('[uploadService] Photo URI:', capture.photoUri);
  console.log('[uploadService] Depth map length:', capture.compressedDepthMap?.length || 0);
  console.log('[uploadService] API URL:', API_BASE_URL);

  try {
    // Build metadata JSON
    const metadataJson = JSON.stringify(capture.metadata);
    console.log('[uploadService] Metadata:', metadataJson.substring(0, 200) + '...');

    // Build auth headers
    const authHeaders = await buildDeviceAuthHeaders(metadataJson);
    console.log('[uploadService] Auth headers:', JSON.stringify(authHeaders, null, 2));

    // Create FormData using React Native compatible format
    // RN FormData expects {uri, type, name} objects for files, not Blobs
    const formData = new FormData();

    // Add photo part - use file URI directly (RN FormData format)
    formData.append('photo', {
      uri: capture.photoUri,
      type: 'image/jpeg',
      name: 'capture.jpg',
    } as unknown as Blob);

    // Save depth_map to temp file for FormData (RN doesn't support Blob from ArrayBuffer)
    const depthTempPath = `${FileSystem.cacheDirectory}depth_${capture.id}.gz`;
    console.log('[uploadService] Writing depth to:', depthTempPath);
    await FileSystem.writeAsStringAsync(depthTempPath, capture.compressedDepthMap, {
      encoding: 'base64',
    });
    const depthInfo = await FileSystem.getInfoAsync(depthTempPath);
    console.log('[uploadService] Depth file created:', depthInfo);
    formData.append('depth_map', {
      uri: depthTempPath,
      type: 'application/gzip',
      name: 'depth.gz',
    } as unknown as Blob);

    // Save metadata to temp file for FormData
    const metadataTempPath = `${FileSystem.cacheDirectory}metadata_${capture.id}.json`;
    console.log('[uploadService] Writing metadata to:', metadataTempPath);
    await FileSystem.writeAsStringAsync(metadataTempPath, metadataJson, {
      encoding: 'utf8',
    });
    const metaInfo = await FileSystem.getInfoAsync(metadataTempPath);
    console.log('[uploadService] Metadata file created:', metaInfo);
    formData.append('metadata', {
      uri: metadataTempPath,
      type: 'application/json',
      name: 'metadata.json',
    } as unknown as Blob);

    // Check photo file exists
    const photoInfo = await FileSystem.getInfoAsync(capture.photoUri);
    console.log('[uploadService] Photo file info:', photoInfo);

    console.log('[uploadService] FormData prepared, starting fetch to:', `${API_BASE_URL}/api/v1/captures`);

    // Report initial progress
    onProgress?.(5);

    // Create abort controller for timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), UPLOAD_TIMEOUT_MS);

    try {
      console.log('[uploadService] Sending fetch request...');
      // Make upload request
      const response = await fetch(`${API_BASE_URL}/api/v1/captures`, {
        method: 'POST',
        headers: {
          ...authHeaders,
          // Note: Don't set Content-Type - fetch will set it with boundary for multipart
        },
        body: formData,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);
      console.log('[uploadService] Response received:', {
        status: response.status,
        statusText: response.statusText,
        ok: response.ok,
        headers: Object.fromEntries(response.headers.entries()),
      });

      // Report upload complete, waiting for response
      onProgress?.(90);

      // Handle non-success responses
      if (!response.ok) {
        const retryAfter = parseRetryAfter(response.headers.get('Retry-After'));
        const error = classifyHttpError(response.status, retryAfter);

        // Try to get error details from response body
        try {
          const errorBody = await response.json();
          if (errorBody.error?.message) {
            error.message = errorBody.error.message;
          }
        } catch {
          // Ignore JSON parse errors
        }

        console.log('[uploadService] Upload failed with HTTP error:', {
          id: capture.id,
          status: response.status,
          error: error.code,
        });

        return { success: false, error };
      }

      // Parse success response
      const responseData = await response.json() as CaptureUploadResponse;

      console.log('[uploadService] Upload successful:', {
        id: capture.id,
        captureId: responseData.data.capture_id,
        status: responseData.data.status,
      });

      onProgress?.(100);

      return {
        success: true,
        data: responseData,
      };
    } catch (fetchError) {
      clearTimeout(timeoutId);
      console.error('[uploadService] ========== FETCH ERROR ==========');
      console.error('[uploadService] Error type:', fetchError?.constructor?.name);
      console.error('[uploadService] Error message:', fetchError instanceof Error ? fetchError.message : String(fetchError));
      console.error('[uploadService] Full error:', fetchError);

      // Handle abort (timeout)
      if (fetchError instanceof Error && fetchError.name === 'AbortError') {
        console.log('[uploadService] Upload timed out:', capture.id);
        return {
          success: false,
          error: {
            code: 'TIMEOUT',
            message: 'Upload timed out. Will retry.',
          },
        };
      }

      // Handle network errors
      if (fetchError instanceof TypeError) {
        console.log('[uploadService] Network error:', capture.id, fetchError.message);
        return {
          success: false,
          error: {
            code: 'NETWORK_ERROR',
            message: 'No internet connection. Will retry when connected.',
          },
        };
      }

      // Unknown fetch error
      console.error('[uploadService] Unexpected fetch error:', fetchError);
      return {
        success: false,
        error: {
          code: 'UNKNOWN',
          message: fetchError instanceof Error ? fetchError.message : 'Upload failed',
        },
      };
    }
  } catch (error) {
    // Handle file reading or other preparation errors
    console.error('[uploadService] Upload preparation failed:', error);
    return {
      success: false,
      error: {
        code: 'UNKNOWN',
        message: error instanceof Error ? error.message : 'Failed to prepare upload',
      },
    };
  }
}

/**
 * Upload using FileSystem.uploadAsync (alternative implementation)
 * Provides better progress tracking but less control over headers
 *
 * Note: Keeping this as alternative implementation for future optimization
 */
export async function uploadCaptureWithFileSystem(
  capture: ProcessedCapture,
  onProgress?: UploadProgressCallback
): Promise<UploadOutcome> {
  console.log('[uploadService] Starting FileSystem upload for capture:', capture.id);

  try {
    const metadataJson = JSON.stringify(capture.metadata);
    const authHeaders = await buildDeviceAuthHeaders(metadataJson);

    // Upload using FileSystem.uploadAsync
    // This provides built-in progress tracking
    const uploadResult = await FileSystem.uploadAsync(
      `${API_BASE_URL}/api/v1/captures`,
      capture.photoUri,
      {
        httpMethod: 'POST',
        uploadType: 1, // MULTIPART = 1
        fieldName: 'photo',
        mimeType: 'image/jpeg',
        headers: {
          ...authHeaders,
        },
        parameters: {
          metadata: metadataJson,
          depth_map_base64: capture.compressedDepthMap,
        },
      }
    );

    onProgress?.(100);

    // Handle response
    if (uploadResult.status >= 200 && uploadResult.status < 300) {
      const responseData = JSON.parse(uploadResult.body) as CaptureUploadResponse;
      return { success: true, data: responseData };
    }

    // Handle error response
    const retryAfter = parseRetryAfter(uploadResult.headers['Retry-After'] || null);
    const error = classifyHttpError(uploadResult.status, retryAfter);

    try {
      const errorBody = JSON.parse(uploadResult.body);
      if (errorBody.error?.message) {
        error.message = errorBody.error.message;
      }
    } catch {
      // Ignore JSON parse errors
    }

    return { success: false, error };
  } catch (error) {
    console.error('[uploadService] FileSystem upload failed:', error);

    // Check for network-related errors
    if (error instanceof Error) {
      if (error.message.includes('Network') || error.message.includes('connection')) {
        return {
          success: false,
          error: {
            code: 'NETWORK_ERROR',
            message: 'No internet connection. Will retry when connected.',
          },
        };
      }
    }

    return {
      success: false,
      error: {
        code: 'UNKNOWN',
        message: error instanceof Error ? error.message : 'Upload failed',
      },
    };
  }
}
