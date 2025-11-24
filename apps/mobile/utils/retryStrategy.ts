/**
 * Retry Strategy Utilities
 *
 * Exponential backoff retry logic for upload queue.
 * Follows the retry schedule from Epic 4 Tech Spec:
 *
 * - Attempt 1: immediate (0ms)
 * - Attempt 2: 1 second delay
 * - Attempt 3: 2 seconds delay
 * - Attempt 4: 4 seconds delay
 * - Attempt 5: 8 seconds delay
 * - Attempts 6-10: 5 minutes delay (max backoff cap)
 * - After 10 attempts: mark permanently failed
 *
 * @see Story 4.2 - Upload Queue with Retry Logic (AC-2)
 */

import type { UploadError, UploadErrorCode, RetryConfig } from '@realitycam/shared';
import { DEFAULT_RETRY_CONFIG } from '@realitycam/shared';

// Re-export for backwards compatibility
export { DEFAULT_RETRY_CONFIG };

/**
 * Error codes that should trigger automatic retry
 */
const RETRYABLE_ERROR_CODES: UploadErrorCode[] = [
  'NETWORK_ERROR',
  'SERVER_ERROR',
  'RATE_LIMITED',
  'TIMEOUT',
  'UNKNOWN',
];

/**
 * Error codes that should NOT trigger retry (user action needed)
 */
const NON_RETRYABLE_ERROR_CODES: UploadErrorCode[] = [
  'VALIDATION_ERROR',  // 400 - Fix data and resubmit
  'AUTH_ERROR',        // 401 - Re-register device
  'NOT_FOUND',         // 404 - Device not registered
  'PAYLOAD_TOO_LARGE', // 413 - Cannot upload this file
];

/**
 * Calculate the backoff delay for a given retry attempt
 *
 * Formula:
 * - Attempt 1 (retryCount=0): 0ms (immediate)
 * - Attempt 2 (retryCount=1): 1000ms
 * - Attempt 3 (retryCount=2): 2000ms
 * - Attempt 4 (retryCount=3): 4000ms
 * - Attempt 5 (retryCount=4): 8000ms
 * - Attempt 6+ (retryCount>=5): 300000ms (5 minutes cap)
 *
 * @param retryCount - Number of previous retry attempts (0-based)
 * @param config - Optional retry configuration
 * @returns Delay in milliseconds before next attempt
 */
export function calculateBackoffDelay(
  retryCount: number,
  config: RetryConfig = DEFAULT_RETRY_CONFIG
): number {
  // First attempt (retryCount=0) is immediate
  if (retryCount === 0) {
    return 0;
  }

  // Calculate exponential backoff: 2^(retryCount-1) * baseDelay
  // Attempt 2: 2^0 * 1000 = 1000ms
  // Attempt 3: 2^1 * 1000 = 2000ms
  // Attempt 4: 2^2 * 1000 = 4000ms
  // Attempt 5: 2^3 * 1000 = 8000ms
  const exponentialDelay = Math.pow(2, retryCount - 1) * config.baseDelayMs;

  // Cap at maxBackoff
  return Math.min(exponentialDelay, config.maxBackoffMs);
}

/**
 * Determine if an error should trigger automatic retry
 *
 * Retryable errors:
 * - NETWORK_ERROR: Wait for connectivity
 * - SERVER_ERROR: 5xx responses
 * - RATE_LIMITED: 429 with Retry-After
 * - TIMEOUT: Request timed out
 * - UNKNOWN: Unknown errors (retry with caution)
 *
 * Non-retryable errors:
 * - VALIDATION_ERROR: 400 - User must fix data
 * - AUTH_ERROR: 401 - Device may need re-registration
 * - NOT_FOUND: 404 - Device not registered
 * - PAYLOAD_TOO_LARGE: 413 - File too large
 *
 * @param error - The upload error to evaluate
 * @param retryCount - Number of previous retry attempts
 * @param config - Optional retry configuration
 * @returns true if retry should be attempted
 */
export function shouldRetry(
  error: UploadError,
  retryCount: number,
  config: RetryConfig = DEFAULT_RETRY_CONFIG
): boolean {
  // Never retry if max attempts reached
  if (retryCount >= config.maxAttempts) {
    return false;
  }

  // Check if error code is retryable
  return RETRYABLE_ERROR_CODES.includes(error.code);
}

/**
 * Check if max retry attempts have been exceeded
 *
 * @param retryCount - Number of previous retry attempts
 * @param config - Optional retry configuration
 * @returns true if max attempts exceeded
 */
export function isMaxRetriesExceeded(
  retryCount: number,
  config: RetryConfig = DEFAULT_RETRY_CONFIG
): boolean {
  return retryCount >= config.maxAttempts;
}

/**
 * Calculate delay respecting Retry-After header for 429 responses
 *
 * If the error has a retryAfter value (from 429 response), use that.
 * Otherwise fall back to exponential backoff.
 *
 * @param error - The upload error
 * @param retryCount - Number of previous retry attempts
 * @param config - Optional retry configuration
 * @returns Delay in milliseconds
 */
export function calculateDelayWithRetryAfter(
  error: UploadError,
  retryCount: number,
  config: RetryConfig = DEFAULT_RETRY_CONFIG
): number {
  // If error has Retry-After header value (in seconds), use it
  if (error.retryAfter !== undefined && error.retryAfter > 0) {
    const retryAfterMs = error.retryAfter * 1000;
    // Cap at maxBackoff to prevent absurdly long waits
    return Math.min(retryAfterMs, config.maxBackoffMs);
  }

  // Fall back to exponential backoff
  return calculateBackoffDelay(retryCount, config);
}

/**
 * Get human-readable retry status message
 *
 * @param retryCount - Number of previous retry attempts
 * @param config - Optional retry configuration
 * @returns Status message for UI display
 */
export function getRetryStatusMessage(
  retryCount: number,
  config: RetryConfig = DEFAULT_RETRY_CONFIG
): string {
  const remainingAttempts = config.maxAttempts - retryCount;

  if (remainingAttempts <= 0) {
    return 'Upload failed permanently after maximum retries';
  }

  if (retryCount === 0) {
    return 'Upload queued';
  }

  const delay = calculateBackoffDelay(retryCount, config);
  const delaySeconds = Math.round(delay / 1000);

  if (delaySeconds === 0) {
    return `Retrying immediately (attempt ${retryCount + 1}/${config.maxAttempts})`;
  }

  if (delaySeconds < 60) {
    return `Retrying in ${delaySeconds}s (attempt ${retryCount + 1}/${config.maxAttempts})`;
  }

  const delayMinutes = Math.round(delaySeconds / 60);
  return `Retrying in ${delayMinutes}m (attempt ${retryCount + 1}/${config.maxAttempts})`;
}

/**
 * Check if an error code indicates a non-retryable failure
 *
 * @param code - Upload error code
 * @returns true if error should not be retried
 */
export function isNonRetryableError(code: UploadErrorCode): boolean {
  return NON_RETRYABLE_ERROR_CODES.includes(code);
}

/**
 * Get user-friendly error message for display
 *
 * @param error - Upload error
 * @returns Message suitable for UI display
 */
export function getErrorDisplayMessage(error: UploadError): string {
  switch (error.code) {
    case 'NETWORK_ERROR':
      return 'No internet connection. Will retry when connected.';
    case 'SERVER_ERROR':
      return 'Server is temporarily unavailable. Retrying...';
    case 'VALIDATION_ERROR':
      return 'Invalid capture data. Please try again with a new capture.';
    case 'AUTH_ERROR':
      return 'Device authentication failed. Please restart the app.';
    case 'NOT_FOUND':
      return 'Device not registered. Please restart the app.';
    case 'PAYLOAD_TOO_LARGE':
      return 'Capture file is too large to upload.';
    case 'RATE_LIMITED':
      return 'Too many uploads. Please wait a moment.';
    case 'TIMEOUT':
      return 'Upload timed out. Retrying...';
    case 'UNKNOWN':
    default:
      return error.message || 'An unexpected error occurred.';
  }
}
