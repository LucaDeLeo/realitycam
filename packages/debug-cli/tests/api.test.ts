/**
 * API Client Tests
 */

import { describe, it, expect, beforeEach, afterEach, mock } from 'bun:test';
import { DebugApiClient, createClient, type DebugLog, type QueryLogsResponse } from '../src/lib/api.js';

// Mock fetch for testing
const mockFetch = mock(() => Promise.resolve(new Response()));

describe('DebugApiClient', () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
    globalThis.fetch = mockFetch as unknown as typeof fetch;
    mockFetch.mockClear();
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  describe('constructor', () => {
    it('uses default URL when none provided', () => {
      const client = new DebugApiClient();
      expect(client.baseUrl).toBe('http://localhost:8080');
    });

    it('accepts custom URL', () => {
      const client = new DebugApiClient('http://custom:9000');
      expect(client.baseUrl).toBe('http://custom:9000');
    });

    it('removes trailing slash from URL', () => {
      const client = new DebugApiClient('http://localhost:8080/');
      expect(client.baseUrl).toBe('http://localhost:8080');
    });
  });

  describe('getDebugLogs', () => {
    const mockLogs: DebugLog[] = [
      {
        id: '123',
        correlation_id: 'abc-456',
        timestamp: '2024-12-05T10:00:00Z',
        source: 'ios',
        level: 'info',
        event: 'TEST_EVENT',
        payload: { foo: 'bar' },
        created_at: '2024-12-05T10:00:00Z',
      },
    ];

    const mockResponse: QueryLogsResponse = {
      logs: mockLogs,
      count: 1,
      has_more: false,
    };

    it('calls correct endpoint with no filters', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response(JSON.stringify({ data: mockResponse }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const client = new DebugApiClient();
      await client.getDebugLogs();

      expect(mockFetch).toHaveBeenCalledTimes(1);
      const calls = mockFetch.mock.calls as unknown as [string, RequestInit][];
      const url = calls[0][0];
      expect(url).toBe('http://localhost:8080/api/v1/debug/logs');
    });

    it('includes query params for filters', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response(JSON.stringify({ data: mockResponse }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const client = new DebugApiClient();
      await client.getDebugLogs({
        source: 'ios',
        level: 'error',
        limit: 50,
        order: 'desc',
      });

      expect(mockFetch).toHaveBeenCalledTimes(1);
      const calls = mockFetch.mock.calls as unknown as [string, RequestInit][];
      const url = calls[0][0];
      expect(url).toContain('source=ios');
      expect(url).toContain('level=error');
      expect(url).toContain('limit=50');
      expect(url).toContain('order=desc');
    });

    it('returns parsed response data', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response(JSON.stringify({ data: mockResponse }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const client = new DebugApiClient();
      const result = await client.getDebugLogs();

      expect(result.logs).toEqual(mockLogs);
      expect(result.count).toBe(1);
      expect(result.has_more).toBe(false);
    });

    it('throws on non-200 response', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response('Not found', { status: 404 })
      );

      const client = new DebugApiClient();
      await expect(client.getDebugLogs()).rejects.toThrow('API error (404)');
    });
  });

  describe('deleteDebugLogs', () => {
    const mockDeleteResponse = { deleted: 5 };

    it('calls DELETE endpoint', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response(JSON.stringify({ data: mockDeleteResponse }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const client = new DebugApiClient();
      await client.deleteDebugLogs({ source: 'web' });

      expect(mockFetch).toHaveBeenCalledTimes(1);
      const calls = mockFetch.mock.calls as unknown as [string, RequestInit][];
      const url = calls[0][0];
      const options = calls[0][1];
      expect(options.method).toBe('DELETE');
      expect(url).toContain('source=web');
    });

    it('returns deleted count', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response(JSON.stringify({ data: mockDeleteResponse }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const client = new DebugApiClient();
      const result = await client.deleteDebugLogs();

      expect(result.deleted).toBe(5);
    });
  });

  describe('getStats', () => {
    const mockStats = {
      total_count: 100,
      by_source: { ios: 50, backend: 30, web: 20 },
      by_level: { debug: 10, info: 50, warn: 30, error: 10 },
      oldest_timestamp: '2024-12-01T00:00:00Z',
      newest_timestamp: '2024-12-05T12:00:00Z',
    };

    it('calls stats endpoint', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response(JSON.stringify({ data: mockStats }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const client = new DebugApiClient();
      await client.getStats();

      expect(mockFetch).toHaveBeenCalledTimes(1);
      const calls = mockFetch.mock.calls as unknown as [string, RequestInit][];
      const url = calls[0][0];
      expect(url).toBe('http://localhost:8080/api/v1/debug/logs/stats');
    });

    it('returns stats data', async () => {
      mockFetch.mockResolvedValueOnce(
        new Response(JSON.stringify({ data: mockStats }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const client = new DebugApiClient();
      const result = await client.getStats();

      expect(result.total_count).toBe(100);
      expect(result.by_source).toEqual({ ios: 50, backend: 30, web: 20 });
    });
  });
});

describe('createClient', () => {
  it('creates client with default URL', () => {
    const client = createClient();
    expect(client.baseUrl).toBe('http://localhost:8080');
  });

  it('creates client with custom URL', () => {
    const client = createClient('http://custom:9000');
    expect(client.baseUrl).toBe('http://custom:9000');
  });
});
