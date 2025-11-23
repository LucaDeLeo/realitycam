/**
 * Retry Strategy Unit Tests
 *
 * Tests for exponential backoff calculations and retry decision logic.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic (AC-2)
 */

import {
  calculateBackoffDelay,
  shouldRetry,
  isMaxRetriesExceeded,
  calculateDelayWithRetryAfter,
  getRetryStatusMessage,
  isNonRetryableError,
  getErrorDisplayMessage,
  DEFAULT_RETRY_CONFIG,
} from '../../utils/retryStrategy';
import type { UploadError } from '@realitycam/shared';

describe('retryStrategy', () => {
  describe('calculateBackoffDelay', () => {
    it('returns 0 for first attempt (retryCount=0)', () => {
      expect(calculateBackoffDelay(0)).toBe(0);
    });

    it('returns 1 second for second attempt (retryCount=1)', () => {
      expect(calculateBackoffDelay(1)).toBe(1000);
    });

    it('returns 2 seconds for third attempt (retryCount=2)', () => {
      expect(calculateBackoffDelay(2)).toBe(2000);
    });

    it('returns 4 seconds for fourth attempt (retryCount=3)', () => {
      expect(calculateBackoffDelay(3)).toBe(4000);
    });

    it('returns 8 seconds for fifth attempt (retryCount=4)', () => {
      expect(calculateBackoffDelay(4)).toBe(8000);
    });

    it('returns 5 minutes (cap) for sixth attempt (retryCount=5)', () => {
      expect(calculateBackoffDelay(5)).toBe(300000);
    });

    it('returns 5 minutes (cap) for attempts 6-10', () => {
      expect(calculateBackoffDelay(6)).toBe(300000);
      expect(calculateBackoffDelay(7)).toBe(300000);
      expect(calculateBackoffDelay(8)).toBe(300000);
      expect(calculateBackoffDelay(9)).toBe(300000);
    });

    it('respects custom config', () => {
      const customConfig = {
        maxAttempts: 5,
        maxBackoffMs: 60000, // 1 minute cap
        baseDelayMs: 500,    // 500ms base
      };

      expect(calculateBackoffDelay(1, customConfig)).toBe(500);
      expect(calculateBackoffDelay(2, customConfig)).toBe(1000);
      expect(calculateBackoffDelay(5, customConfig)).toBe(60000); // capped
    });
  });

  describe('shouldRetry', () => {
    it('returns true for NETWORK_ERROR within retry limit', () => {
      const error: UploadError = { code: 'NETWORK_ERROR', message: 'No connection' };
      expect(shouldRetry(error, 0)).toBe(true);
      expect(shouldRetry(error, 5)).toBe(true);
      expect(shouldRetry(error, 9)).toBe(true);
    });

    it('returns true for SERVER_ERROR within retry limit', () => {
      const error: UploadError = { code: 'SERVER_ERROR', message: 'Internal error', statusCode: 500 };
      expect(shouldRetry(error, 0)).toBe(true);
      expect(shouldRetry(error, 5)).toBe(true);
    });

    it('returns true for RATE_LIMITED within retry limit', () => {
      const error: UploadError = { code: 'RATE_LIMITED', message: 'Too many requests', statusCode: 429 };
      expect(shouldRetry(error, 0)).toBe(true);
    });

    it('returns true for TIMEOUT within retry limit', () => {
      const error: UploadError = { code: 'TIMEOUT', message: 'Request timed out' };
      expect(shouldRetry(error, 0)).toBe(true);
    });

    it('returns true for UNKNOWN within retry limit', () => {
      const error: UploadError = { code: 'UNKNOWN', message: 'Unknown error' };
      expect(shouldRetry(error, 0)).toBe(true);
    });

    it('returns false for VALIDATION_ERROR', () => {
      const error: UploadError = { code: 'VALIDATION_ERROR', message: 'Bad request', statusCode: 400 };
      expect(shouldRetry(error, 0)).toBe(false);
    });

    it('returns false for AUTH_ERROR', () => {
      const error: UploadError = { code: 'AUTH_ERROR', message: 'Unauthorized', statusCode: 401 };
      expect(shouldRetry(error, 0)).toBe(false);
    });

    it('returns false for NOT_FOUND', () => {
      const error: UploadError = { code: 'NOT_FOUND', message: 'Device not found', statusCode: 404 };
      expect(shouldRetry(error, 0)).toBe(false);
    });

    it('returns false for PAYLOAD_TOO_LARGE', () => {
      const error: UploadError = { code: 'PAYLOAD_TOO_LARGE', message: 'File too large', statusCode: 413 };
      expect(shouldRetry(error, 0)).toBe(false);
    });

    it('returns false when max retries exceeded', () => {
      const error: UploadError = { code: 'NETWORK_ERROR', message: 'No connection' };
      expect(shouldRetry(error, 10)).toBe(false);
      expect(shouldRetry(error, 11)).toBe(false);
    });
  });

  describe('isMaxRetriesExceeded', () => {
    it('returns false when retryCount < maxAttempts', () => {
      expect(isMaxRetriesExceeded(0)).toBe(false);
      expect(isMaxRetriesExceeded(5)).toBe(false);
      expect(isMaxRetriesExceeded(9)).toBe(false);
    });

    it('returns true when retryCount >= maxAttempts', () => {
      expect(isMaxRetriesExceeded(10)).toBe(true);
      expect(isMaxRetriesExceeded(11)).toBe(true);
      expect(isMaxRetriesExceeded(100)).toBe(true);
    });

    it('respects custom maxAttempts', () => {
      const customConfig = { ...DEFAULT_RETRY_CONFIG, maxAttempts: 5 };
      expect(isMaxRetriesExceeded(4, customConfig)).toBe(false);
      expect(isMaxRetriesExceeded(5, customConfig)).toBe(true);
    });
  });

  describe('calculateDelayWithRetryAfter', () => {
    it('uses retryAfter value when present', () => {
      const error: UploadError = {
        code: 'RATE_LIMITED',
        message: 'Too many requests',
        statusCode: 429,
        retryAfter: 30, // 30 seconds
      };
      expect(calculateDelayWithRetryAfter(error, 0)).toBe(30000);
    });

    it('caps retryAfter at maxBackoff', () => {
      const error: UploadError = {
        code: 'RATE_LIMITED',
        message: 'Too many requests',
        statusCode: 429,
        retryAfter: 600, // 10 minutes
      };
      // Capped at 5 minutes (300000ms)
      expect(calculateDelayWithRetryAfter(error, 0)).toBe(300000);
    });

    it('falls back to exponential backoff when no retryAfter', () => {
      const error: UploadError = {
        code: 'SERVER_ERROR',
        message: 'Internal error',
        statusCode: 500,
      };
      expect(calculateDelayWithRetryAfter(error, 0)).toBe(0);
      expect(calculateDelayWithRetryAfter(error, 1)).toBe(1000);
      expect(calculateDelayWithRetryAfter(error, 2)).toBe(2000);
    });

    it('ignores zero or negative retryAfter', () => {
      const error: UploadError = {
        code: 'RATE_LIMITED',
        message: 'Too many requests',
        retryAfter: 0,
      };
      expect(calculateDelayWithRetryAfter(error, 2)).toBe(2000); // Falls back to backoff
    });
  });

  describe('getRetryStatusMessage', () => {
    it('returns queued message for first attempt', () => {
      expect(getRetryStatusMessage(0)).toBe('Upload queued');
    });

    it('returns immediate retry message', () => {
      // retryCount=1 means delay=1s, but the formula gives 1000ms
      // Actually for immediate we need to check the actual delay
      const msg = getRetryStatusMessage(1);
      expect(msg).toMatch(/Retrying in 1s/);
      expect(msg).toMatch(/attempt 2\/10/);
    });

    it('returns seconds message for short delays', () => {
      const msg = getRetryStatusMessage(3);
      expect(msg).toMatch(/Retrying in 4s/);
    });

    it('returns minutes message for long delays', () => {
      const msg = getRetryStatusMessage(6);
      expect(msg).toMatch(/Retrying in 5m/);
    });

    it('returns permanently failed message when max retries exceeded', () => {
      expect(getRetryStatusMessage(10)).toBe('Upload failed permanently after maximum retries');
    });
  });

  describe('isNonRetryableError', () => {
    it('returns true for non-retryable codes', () => {
      expect(isNonRetryableError('VALIDATION_ERROR')).toBe(true);
      expect(isNonRetryableError('AUTH_ERROR')).toBe(true);
      expect(isNonRetryableError('NOT_FOUND')).toBe(true);
      expect(isNonRetryableError('PAYLOAD_TOO_LARGE')).toBe(true);
    });

    it('returns false for retryable codes', () => {
      expect(isNonRetryableError('NETWORK_ERROR')).toBe(false);
      expect(isNonRetryableError('SERVER_ERROR')).toBe(false);
      expect(isNonRetryableError('RATE_LIMITED')).toBe(false);
      expect(isNonRetryableError('TIMEOUT')).toBe(false);
      expect(isNonRetryableError('UNKNOWN')).toBe(false);
    });
  });

  describe('getErrorDisplayMessage', () => {
    it('returns appropriate messages for each error code', () => {
      expect(getErrorDisplayMessage({ code: 'NETWORK_ERROR', message: '' }))
        .toBe('No internet connection. Will retry when connected.');

      expect(getErrorDisplayMessage({ code: 'SERVER_ERROR', message: '' }))
        .toBe('Server is temporarily unavailable. Retrying...');

      expect(getErrorDisplayMessage({ code: 'VALIDATION_ERROR', message: '' }))
        .toBe('Invalid capture data. Please try again with a new capture.');

      expect(getErrorDisplayMessage({ code: 'AUTH_ERROR', message: '' }))
        .toBe('Device authentication failed. Please restart the app.');

      expect(getErrorDisplayMessage({ code: 'NOT_FOUND', message: '' }))
        .toBe('Device not registered. Please restart the app.');

      expect(getErrorDisplayMessage({ code: 'PAYLOAD_TOO_LARGE', message: '' }))
        .toBe('Capture file is too large to upload.');

      expect(getErrorDisplayMessage({ code: 'RATE_LIMITED', message: '' }))
        .toBe('Too many uploads. Please wait a moment.');

      expect(getErrorDisplayMessage({ code: 'TIMEOUT', message: '' }))
        .toBe('Upload timed out. Retrying...');
    });

    it('returns error message for UNKNOWN with custom message', () => {
      expect(getErrorDisplayMessage({ code: 'UNKNOWN', message: 'Custom error' }))
        .toBe('Custom error');
    });

    it('returns fallback for UNKNOWN without message', () => {
      expect(getErrorDisplayMessage({ code: 'UNKNOWN', message: '' }))
        .toBe('An unexpected error occurred.');
    });
  });
});
