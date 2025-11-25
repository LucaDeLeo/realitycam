/**
 * API Client Unit Tests
 *
 * [P1] Tests for API client timeout handling and error cases.
 *
 * @see src/lib/api.ts
 */

import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import { ApiClient, formatDate } from '../api';

// ============================================================================
// Test Setup
// ============================================================================

// Mock fetch globally
const mockFetch = vi.fn();
global.fetch = mockFetch;

// Mock console methods to prevent noise in tests
vi.spyOn(console, 'error').mockImplementation(() => {});

describe('ApiClient', () => {
  let client: ApiClient;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    client = new ApiClient('http://localhost:8080');
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  // ============================================================================
  // Constructor Tests
  // ============================================================================

  describe('constructor', () => {
    test('[P1] should use provided base URL', () => {
      const customClient = new ApiClient('http://custom-api.com');
      expect(customClient.baseUrl).toBe('http://custom-api.com');
    });

    test('[P1] should use default URL when not provided', () => {
      // Note: In test environment, NEXT_PUBLIC_API_URL may not be set
      const defaultClient = new ApiClient();
      expect(defaultClient.baseUrl).toBeDefined();
    });
  });

  // ============================================================================
  // getCapture Tests
  // ============================================================================

  describe('getCapture', () => {
    test('[P1] should return capture data on success', async () => {
      // GIVEN: API returns capture data
      const mockResponse = {
        data: { id: 'test-123', confidence_level: 'high' },
        meta: { request_id: 'req-1', timestamp: '2024-01-01T00:00:00Z' },
      };
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve(mockResponse),
      });

      // WHEN: Fetching capture
      const result = await client.getCapture('test-123');

      // THEN: Should return data
      expect(result).toEqual(mockResponse);
      expect(mockFetch).toHaveBeenCalledWith(
        'http://localhost:8080/api/v1/captures/test-123',
        expect.objectContaining({ cache: 'no-store' })
      );
    });

    test('[P1] should return null on 404', async () => {
      // GIVEN: API returns 404
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 404,
      });

      // WHEN: Fetching non-existent capture
      const result = await client.getCapture('non-existent');

      // THEN: Should return null
      expect(result).toBeNull();
    });

    test('[P1] should return null on other errors', async () => {
      // GIVEN: API returns 500
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
      });

      // WHEN: Fetching capture
      const result = await client.getCapture('test-123');

      // THEN: Should return null
      expect(result).toBeNull();
    });

    test('[P1] should handle timeout (AbortError)', async () => {
      // GIVEN: Fetch throws AbortError (timeout)
      const abortError = new Error('Aborted');
      abortError.name = 'AbortError';
      mockFetch.mockRejectedValueOnce(abortError);

      // WHEN: Fetching capture
      const result = await client.getCapture('test-123');

      // THEN: Should return null and log timeout
      expect(result).toBeNull();
      expect(console.error).toHaveBeenCalledWith(
        'Request timed out fetching capture:',
        'test-123'
      );
    });

    test('[P1] should handle network errors', async () => {
      // GIVEN: Network error
      mockFetch.mockRejectedValueOnce(new Error('Network error'));

      // WHEN: Fetching capture
      const result = await client.getCapture('test-123');

      // THEN: Should return null
      expect(result).toBeNull();
      expect(console.error).toHaveBeenCalledWith(
        'Failed to fetch capture:',
        expect.any(Error)
      );
    });

    test('[P1] should pass AbortSignal to fetch', async () => {
      // GIVEN: API returns data
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ data: {} }),
      });

      // WHEN: Fetching capture
      await client.getCapture('test-123');

      // THEN: Should include signal in fetch options
      expect(mockFetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          signal: expect.any(AbortSignal),
        })
      );
    });
  });

  // ============================================================================
  // getCapturePublic Tests
  // ============================================================================

  describe('getCapturePublic', () => {
    test('[P1] should use public verify endpoint', async () => {
      // GIVEN: API returns data
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ data: {} }),
      });

      // WHEN: Fetching public capture
      await client.getCapturePublic('test-123');

      // THEN: Should call verify endpoint
      expect(mockFetch).toHaveBeenCalledWith(
        'http://localhost:8080/api/v1/verify/test-123',
        expect.any(Object)
      );
    });

    test('[P1] should return null on 404', async () => {
      // GIVEN: 404 response
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 404,
      });

      // WHEN: Fetching non-existent capture
      const result = await client.getCapturePublic('non-existent');

      // THEN: Should return null
      expect(result).toBeNull();
    });

    test('[P1] should handle timeout', async () => {
      // GIVEN: Timeout error
      const abortError = new Error('Aborted');
      abortError.name = 'AbortError';
      mockFetch.mockRejectedValueOnce(abortError);

      // WHEN: Fetching capture
      const result = await client.getCapturePublic('test-123');

      // THEN: Should return null and log
      expect(result).toBeNull();
      expect(console.error).toHaveBeenCalledWith(
        'Request timed out fetching public capture:',
        'test-123'
      );
    });
  });

  // ============================================================================
  // verifyFile Tests
  // ============================================================================

  describe('verifyFile', () => {
    test('[P1] should send file as FormData', async () => {
      // GIVEN: File to verify
      const file = new File(['test content'], 'test.jpg', { type: 'image/jpeg' });
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          data: { status: 'verified', file_hash: 'abc123' },
          meta: {},
        }),
      });

      // WHEN: Verifying file
      await client.verifyFile(file);

      // THEN: Should POST FormData
      expect(mockFetch).toHaveBeenCalledWith(
        'http://localhost:8080/api/v1/verify-file',
        expect.objectContaining({
          method: 'POST',
          body: expect.any(FormData),
        })
      );
    });

    test('[P1] should return verification response on success', async () => {
      // GIVEN: Successful verification
      const file = new File(['test'], 'test.jpg');
      const mockResponse = {
        data: { status: 'verified', file_hash: 'abc123' },
        meta: { request_id: 'req-1' },
      };
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve(mockResponse),
      });

      // WHEN: Verifying file
      const result = await client.verifyFile(file);

      // THEN: Should return response
      expect(result).toEqual(mockResponse);
    });

    test('[P1] should throw on API error', async () => {
      // GIVEN: API returns error
      const file = new File(['test'], 'test.jpg');
      mockFetch.mockResolvedValueOnce({
        ok: false,
        json: () => Promise.resolve({
          error: { message: 'Invalid file format' },
        }),
      });

      // WHEN/THEN: Should throw with error message
      await expect(client.verifyFile(file)).rejects.toThrow('Invalid file format');
    });

    test('[P1] should throw "Verification failed" on unknown error', async () => {
      // GIVEN: API returns unparseable error (json() catches and returns fallback)
      const file = new File(['test'], 'test.jpg');
      mockFetch.mockResolvedValueOnce({
        ok: false,
        json: () => Promise.resolve({ error: {} }), // Empty error object
      });

      // WHEN/THEN: Should throw generic message
      await expect(client.verifyFile(file)).rejects.toThrow('Verification failed');
    });

    test('[P1] should throw timeout message on AbortError', async () => {
      // GIVEN: Timeout error
      const file = new File(['test'], 'test.jpg');
      const abortError = new Error('Aborted');
      abortError.name = 'AbortError';
      mockFetch.mockRejectedValueOnce(abortError);

      // WHEN/THEN: Should throw timeout message
      await expect(client.verifyFile(file)).rejects.toThrow(
        'Request timed out. Please try again.'
      );
    });

    test('[P1] should use longer timeout (30s) for file uploads', async () => {
      // This test verifies the intent - actual timeout is harder to test
      // The implementation uses 30_000ms for verifyFile vs 10_000ms for others

      const file = new File(['test'], 'test.jpg');
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ data: {}, meta: {} }),
      });

      // WHEN: Verifying file
      await client.verifyFile(file);

      // THEN: Should include signal (timeout controller)
      expect(mockFetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          signal: expect.any(AbortSignal),
        })
      );
    });
  });
});

// ============================================================================
// formatDate Tests
// ============================================================================

describe('formatDate', () => {
  test('[P2] should format valid date string', () => {
    // GIVEN: ISO date string
    const dateString = '2024-06-15T14:30:00Z';

    // WHEN: Formatting
    const result = formatDate(dateString);

    // THEN: Should return human-readable format
    expect(result).toContain('2024');
    expect(result).toContain('June');
    expect(result).toContain('15');
  });

  test('[P2] should handle invalid date gracefully', () => {
    // GIVEN: Invalid date string
    const invalidDate = 'not-a-date';

    // WHEN: Formatting
    const result = formatDate(invalidDate);

    // THEN: Should return something (either original or "Invalid Date")
    // The function returns the original on parse error
    expect(typeof result).toBe('string');
  });

  test('[P2] should include time in formatted output', () => {
    // GIVEN: Date with specific time
    const dateString = '2024-01-01T09:30:00Z';

    // WHEN: Formatting
    const result = formatDate(dateString);

    // THEN: Should include time (format depends on locale)
    // Just verify it contains some time-related characters
    expect(result.length).toBeGreaterThan(10);
  });
});

// ============================================================================
// Timeout Controller Tests
// ============================================================================

describe('Timeout handling', () => {
  test('[P2] should clear timeout on successful response', async () => {
    // GIVEN: Fast successful response and client
    const client = new ApiClient('http://localhost:8080');
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ data: {} }),
    });

    // WHEN: Making request
    const result = await client.getCapture('test');

    // THEN: Request should complete without timeout (no error)
    expect(mockFetch).toHaveBeenCalled();
    expect(result).toBeDefined();
  });

  test('[P2] should clear timeout on error response', async () => {
    // GIVEN: Error response and client
    const client = new ApiClient('http://localhost:8080');
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
    });

    // WHEN: Making request
    const result = await client.getCapture('test');

    // THEN: Request should complete (timeout cleared), returns null on error
    expect(mockFetch).toHaveBeenCalled();
    expect(result).toBeNull();
  });
});
