/**
 * API Test Helper for RealityCam
 *
 * Provides utilities for testing API endpoints.
 */

export interface ApiResponse<T = unknown> {
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
  };
  meta: {
    request_id: string;
    timestamp: string;
  };
}

/**
 * Create a mock API response wrapper
 */
export function mockApiResponse<T>(data: T): ApiResponse<T> {
  return {
    data,
    meta: {
      request_id: crypto.randomUUID(),
      timestamp: new Date().toISOString(),
    },
  };
}

/**
 * Create a mock API error response
 */
export function mockApiError(
  code: string,
  message: string,
  details?: Record<string, unknown>
): ApiResponse {
  return {
    error: { code, message, details },
    meta: {
      request_id: crypto.randomUUID(),
      timestamp: new Date().toISOString(),
    },
  };
}

/**
 * Common error codes for testing
 */
export const ErrorCodes = {
  ATTESTATION_FAILED: 'ATTESTATION_FAILED',
  DEVICE_NOT_FOUND: 'DEVICE_NOT_FOUND',
  CAPTURE_NOT_FOUND: 'CAPTURE_NOT_FOUND',
  HASH_NOT_FOUND: 'HASH_NOT_FOUND',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  SIGNATURE_INVALID: 'SIGNATURE_INVALID',
  TIMESTAMP_EXPIRED: 'TIMESTAMP_EXPIRED',
  PROCESSING_FAILED: 'PROCESSING_FAILED',
  STORAGE_ERROR: 'STORAGE_ERROR',
} as const;

/**
 * Helper to create device authentication headers
 */
export function createDeviceAuthHeaders(
  deviceId: string,
  signature: string,
  timestamp?: number
): Record<string, string> {
  return {
    'X-Device-Id': deviceId,
    'X-Device-Timestamp': (timestamp || Date.now()).toString(),
    'X-Device-Signature': signature,
  };
}

/**
 * Helper to compute SHA-256 hash of data
 */
export async function computeHash(data: Uint8Array): Promise<string> {
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
