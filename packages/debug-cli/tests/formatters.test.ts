/**
 * Formatter Tests
 */

import { describe, it, expect } from 'bun:test';
import {
  formatLogEntry,
  formatLogs,
  formatLogsJson,
  formatDeleteResult,
  formatError,
} from '../src/lib/formatters.js';
import type { DebugLog } from '../src/lib/api.js';

// Strip ANSI codes for easier testing
function stripAnsi(str: string): string {
  // eslint-disable-next-line no-control-regex
  return str.replace(/\x1B\[[0-9;]*[A-Za-z]/g, '');
}

describe('formatLogEntry', () => {
  const sampleLog: DebugLog = {
    id: '123',
    correlation_id: 'abc-456-def-789',
    timestamp: '2024-12-05T10:30:15Z',
    source: 'ios',
    level: 'error',
    event: 'UPLOAD_FAILED',
    payload: { error: 'Network timeout' },
    created_at: '2024-12-05T10:30:15Z',
  };

  it('includes timestamp', () => {
    const result = stripAnsi(formatLogEntry(sampleLog));
    expect(result).toContain('2024-12-05T10:30:15Z');
  });

  it('includes level in brackets', () => {
    const result = stripAnsi(formatLogEntry(sampleLog));
    expect(result).toContain('[ERROR]');
  });

  it('includes source', () => {
    const result = stripAnsi(formatLogEntry(sampleLog));
    expect(result).toContain('ios');
  });

  it('includes event', () => {
    const result = stripAnsi(formatLogEntry(sampleLog));
    expect(result).toContain('UPLOAD_FAILED');
  });

  it('includes correlation ID prefix', () => {
    const result = stripAnsi(formatLogEntry(sampleLog));
    expect(result).toContain('correlation: abc-456-');
  });
});

describe('formatLogs', () => {
  const sampleLogs: DebugLog[] = [
    {
      id: '1',
      correlation_id: 'abc-123',
      timestamp: '2024-12-05T10:30:15Z',
      source: 'ios',
      level: 'error',
      event: 'ERROR_EVENT',
      payload: {},
      created_at: '2024-12-05T10:30:15Z',
    },
    {
      id: '2',
      correlation_id: 'def-456',
      timestamp: '2024-12-05T10:30:14Z',
      source: 'backend',
      level: 'info',
      event: 'INFO_EVENT',
      payload: {},
      created_at: '2024-12-05T10:30:14Z',
    },
  ];

  it('formats multiple logs with newlines', () => {
    const result = formatLogs(sampleLogs);
    const lines = result.split('\n');
    expect(lines.length).toBe(2);
  });

  it('returns "No logs found" for empty array', () => {
    const result = stripAnsi(formatLogs([]));
    expect(result).toBe('No logs found.');
  });
});

describe('formatLogsJson', () => {
  const sampleLogs: DebugLog[] = [
    {
      id: '1',
      correlation_id: 'abc-123',
      timestamp: '2024-12-05T10:30:15Z',
      source: 'ios',
      level: 'error',
      event: 'ERROR_EVENT',
      payload: { foo: 'bar' },
      created_at: '2024-12-05T10:30:15Z',
    },
  ];

  it('outputs valid JSON', () => {
    const result = formatLogsJson(sampleLogs);
    expect(() => JSON.parse(result)).not.toThrow();
  });

  it('preserves all log properties', () => {
    const result = formatLogsJson(sampleLogs);
    const parsed = JSON.parse(result);
    expect(parsed[0].id).toBe('1');
    expect(parsed[0].correlation_id).toBe('abc-123');
    expect(parsed[0].payload.foo).toBe('bar');
  });

  it('outputs empty array for no logs', () => {
    const result = formatLogsJson([]);
    expect(JSON.parse(result)).toEqual([]);
  });
});

describe('formatDeleteResult', () => {
  it('shows count of deleted logs', () => {
    const result = stripAnsi(formatDeleteResult(5, {}));
    expect(result).toContain('5 logs');
  });

  it('uses singular for 1 log', () => {
    const result = stripAnsi(formatDeleteResult(1, {}));
    expect(result).toContain('1 log');
    expect(result).not.toContain('1 logs');
  });

  it('shows source filter if provided', () => {
    const result = stripAnsi(formatDeleteResult(5, { source: 'ios' }));
    expect(result).toContain('ios');
  });

  it('shows olderThan filter if provided', () => {
    const result = stripAnsi(formatDeleteResult(5, { olderThan: '1 day' }));
    expect(result).toContain('1 day');
  });

  it('shows message for 0 deleted', () => {
    const result = stripAnsi(formatDeleteResult(0, {}));
    expect(result).toContain('No logs deleted');
  });
});

describe('formatError', () => {
  it('prefixes with Error:', () => {
    const result = stripAnsi(formatError('Something went wrong'));
    expect(result).toBe('Error: Something went wrong');
  });
});
