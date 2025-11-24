/**
 * API Service
 *
 * Handles HTTP communication with the RealityCam backend.
 * Story 2.3: Challenge retrieval for DCAppAttest attestation
 *
 * @see Story 2.3 - DCAppAttest Integration
 */

import type { ChallengeResponse } from '@realitycam/shared';
import { uint8ArrayToBase64, base64ToUint8Array } from '@realitycam/shared';

/**
 * API base URL from environment or localhost default
 * In development, backend runs on port 8080
 * Note: Expo sets EXPO_PUBLIC_* env vars at build time
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
 * Request timeout in milliseconds (10 seconds as per spec)
 */
const REQUEST_TIMEOUT_MS = 10_000;

/**
 * API error codes for typed error handling
 */
export const API_ERROR_CODES = {
  TIMEOUT: 'TIMEOUT',
  NETWORK_ERROR: 'NETWORK_ERROR',
  RATE_LIMITED: 'RATE_LIMITED',
  NOT_IMPLEMENTED: 'NOT_IMPLEMENTED',
  SERVER_ERROR: 'SERVER_ERROR',
  UNKNOWN: 'UNKNOWN',
} as const;

export type ApiErrorCode = (typeof API_ERROR_CODES)[keyof typeof API_ERROR_CODES];

/**
 * Custom API error with error code for typed error handling
 */
export class ApiError extends Error {
  code: ApiErrorCode;
  statusCode?: number;

  constructor(message: string, code: ApiErrorCode, statusCode?: number) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

/**
 * Fetches attestation challenge from backend
 *
 * GET /api/v1/devices/challenge
 *
 * Returns a 32-byte base64-encoded challenge with expiration timestamp.
 * Challenge expires after 5 minutes.
 *
 * @returns Promise<ChallengeResponse> - Challenge data with expiration
 * @throws ApiError with code for specific error handling
 *
 * @example
 * ```typescript
 * try {
 *   const response = await fetchChallenge();
 *   console.log('Challenge:', response.data.challenge);
 *   console.log('Expires:', response.data.expires_at);
 * } catch (error) {
 *   if (error instanceof ApiError) {
 *     switch (error.code) {
 *       case 'RATE_LIMITED':
 *         // Wait and retry
 *         break;
 *       case 'NETWORK_ERROR':
 *         // Show connection error
 *         break;
 *     }
 *   }
 * }
 * ```
 */
export async function fetchChallenge(): Promise<ChallengeResponse> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(`${API_BASE_URL}/api/v1/devices/challenge`, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    // Handle rate limiting
    if (response.status === 429) {
      throw new ApiError(
        'Too many requests. Please wait a moment and try again.',
        API_ERROR_CODES.RATE_LIMITED,
        429
      );
    }

    // Handle 501 Not Implemented (backend stub)
    if (response.status === 501) {
      console.log(
        '[api] Challenge endpoint not implemented, returning mock response'
      );
      // Return mock challenge for development/testing
      return createMockChallengeResponse();
    }

    // Handle other errors
    if (!response.ok) {
      const code =
        response.status >= 500
          ? API_ERROR_CODES.SERVER_ERROR
          : API_ERROR_CODES.UNKNOWN;
      throw new ApiError(
        `Server error: ${response.status}`,
        code,
        response.status
      );
    }

    const data: ChallengeResponse = await response.json();
    return data;
  } catch (error) {
    clearTimeout(timeoutId);

    // Re-throw ApiError as-is
    if (error instanceof ApiError) {
      throw error;
    }

    // Handle abort (timeout)
    if (error instanceof Error && error.name === 'AbortError') {
      throw new ApiError(
        'Request timed out. Please check your connection.',
        API_ERROR_CODES.TIMEOUT
      );
    }

    // Handle network errors
    if (error instanceof TypeError && error.message.includes('fetch')) {
      throw new ApiError(
        'Unable to connect to server. Please check your connection.',
        API_ERROR_CODES.NETWORK_ERROR
      );
    }

    // Unknown error
    throw new ApiError(
      error instanceof Error ? error.message : 'Unknown error occurred',
      API_ERROR_CODES.UNKNOWN
    );
  }
}

/**
 * Creates a mock challenge response for development
 * Used when backend returns 501 Not Implemented
 *
 * In production, this would come from the backend.
 * The mock challenge is NOT cryptographically secure - only for testing.
 */
function createMockChallengeResponse(): ChallengeResponse {
  // Generate 32 random bytes and encode as base64
  const randomBytes = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    randomBytes[i] = Math.floor(Math.random() * 256);
  }
  // Manual base64 encoding for React Native compatibility
  const base64Challenge = uint8ArrayToBase64(randomBytes);

  // Expires in 5 minutes
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();

  return {
    data: {
      challenge: base64Challenge,
      expires_at: expiresAt,
    },
    meta: {
      request_id: `mock-${Date.now()}`,
      timestamp: new Date().toISOString(),
    },
  };
}

// Re-export shared base64 utility for backwards compatibility
export { base64ToUint8Array };
