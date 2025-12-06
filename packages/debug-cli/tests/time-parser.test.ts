/**
 * Time Parser Tests
 */

import { describe, it, expect, beforeEach, afterEach } from 'bun:test';
import { parseRelativeTime, parseDuration, formatDuration } from '../src/lib/time-parser.js';

// Helper to create a mock Date that returns fixed time
function createDateMock(fixedDate: Date) {
  const OriginalDate = globalThis.Date;

  function MockDate(...args: unknown[]): Date {
    if (args.length === 0) {
      return new OriginalDate(fixedDate);
    }
    if (args.length === 1) {
      return new OriginalDate(args[0] as string | number | Date);
    }
    // Handle multiple args (year, month, etc)
    return new OriginalDate(
      args[0] as number,
      args[1] as number,
      args[2] as number | undefined,
      args[3] as number | undefined,
      args[4] as number | undefined,
      args[5] as number | undefined,
      args[6] as number | undefined
    );
  }

  // Copy static methods
  MockDate.now = () => fixedDate.getTime();
  MockDate.parse = OriginalDate.parse;
  MockDate.UTC = OriginalDate.UTC;

  return MockDate as unknown as DateConstructor;
}

describe('parseRelativeTime', () => {
  // Use a fixed date for consistent testing
  const fixedDate = new Date('2024-12-05T12:00:00.000Z');
  let originalDate: DateConstructor;

  beforeEach(() => {
    originalDate = globalThis.Date;
    globalThis.Date = createDateMock(fixedDate);
  });

  afterEach(() => {
    globalThis.Date = originalDate;
  });

  describe('shorthand format', () => {
    it('parses minutes shorthand (30m)', () => {
      const result = parseRelativeTime('30m');
      const expected = new originalDate(fixedDate);
      expected.setMinutes(expected.getMinutes() - 30);
      expect(result).toBe(expected.toISOString());
    });

    it('parses hours shorthand (1h)', () => {
      const result = parseRelativeTime('1h');
      const expected = new originalDate(fixedDate);
      expected.setHours(expected.getHours() - 1);
      expect(result).toBe(expected.toISOString());
    });

    it('parses days shorthand (2d)', () => {
      const result = parseRelativeTime('2d');
      const expected = new originalDate(fixedDate);
      expected.setDate(expected.getDate() - 2);
      expect(result).toBe(expected.toISOString());
    });

    it('parses weeks shorthand (1w)', () => {
      const result = parseRelativeTime('1w');
      const expected = new originalDate(fixedDate);
      expected.setDate(expected.getDate() - 7);
      expect(result).toBe(expected.toISOString());
    });
  });

  describe('long format', () => {
    it('parses "1 minute ago"', () => {
      const result = parseRelativeTime('1 minute ago');
      const expected = new originalDate(fixedDate);
      expected.setMinutes(expected.getMinutes() - 1);
      expect(result).toBe(expected.toISOString());
    });

    it('parses "30 minutes ago"', () => {
      const result = parseRelativeTime('30 minutes ago');
      const expected = new originalDate(fixedDate);
      expected.setMinutes(expected.getMinutes() - 30);
      expect(result).toBe(expected.toISOString());
    });

    it('parses "1 hour ago"', () => {
      const result = parseRelativeTime('1 hour ago');
      const expected = new originalDate(fixedDate);
      expected.setHours(expected.getHours() - 1);
      expect(result).toBe(expected.toISOString());
    });

    it('parses "2 hours ago"', () => {
      const result = parseRelativeTime('2 hours ago');
      const expected = new originalDate(fixedDate);
      expected.setHours(expected.getHours() - 2);
      expect(result).toBe(expected.toISOString());
    });

    it('parses "1 day ago"', () => {
      const result = parseRelativeTime('1 day ago');
      const expected = new originalDate(fixedDate);
      expected.setDate(expected.getDate() - 1);
      expect(result).toBe(expected.toISOString());
    });

    it('parses "7 days ago"', () => {
      const result = parseRelativeTime('7 days ago');
      const expected = new originalDate(fixedDate);
      expected.setDate(expected.getDate() - 7);
      expect(result).toBe(expected.toISOString());
    });

    it('parses "1 week ago"', () => {
      const result = parseRelativeTime('1 week ago');
      const expected = new originalDate(fixedDate);
      expected.setDate(expected.getDate() - 7);
      expect(result).toBe(expected.toISOString());
    });

    it('parses "2 weeks ago"', () => {
      const result = parseRelativeTime('2 weeks ago');
      const expected = new originalDate(fixedDate);
      expected.setDate(expected.getDate() - 14);
      expect(result).toBe(expected.toISOString());
    });
  });

  describe('ISO timestamp passthrough', () => {
    it('passes through valid ISO timestamps', () => {
      const iso = '2024-12-01T00:00:00.000Z';
      const result = parseRelativeTime(iso);
      expect(result).toBe(iso);
    });
  });

  describe('error handling', () => {
    it('throws on invalid format', () => {
      expect(() => parseRelativeTime('invalid')).toThrow();
    });

    it('throws on unsupported unit', () => {
      expect(() => parseRelativeTime('5 years ago')).toThrow();
    });
  });
});

describe('parseDuration', () => {
  // Use a fixed date for consistent testing
  const fixedDate = new Date('2024-12-05T12:00:00.000Z');
  let originalDate: DateConstructor;

  beforeEach(() => {
    originalDate = globalThis.Date;
    globalThis.Date = createDateMock(fixedDate);
  });

  afterEach(() => {
    globalThis.Date = originalDate;
  });

  it('parses "1d"', () => {
    const result = parseDuration('1d');
    const expected = new originalDate(fixedDate);
    expected.setDate(expected.getDate() - 1);
    expect(result).toBe(expected.toISOString());
  });

  it('parses "2h"', () => {
    const result = parseDuration('2h');
    const expected = new originalDate(fixedDate);
    expected.setHours(expected.getHours() - 2);
    expect(result).toBe(expected.toISOString());
  });

  it('parses "1w"', () => {
    const result = parseDuration('1w');
    const expected = new originalDate(fixedDate);
    expected.setDate(expected.getDate() - 7);
    expect(result).toBe(expected.toISOString());
  });

  it('parses "30m"', () => {
    const result = parseDuration('30m');
    const expected = new originalDate(fixedDate);
    expected.setMinutes(expected.getMinutes() - 30);
    expect(result).toBe(expected.toISOString());
  });

  it('throws on invalid format', () => {
    expect(() => parseDuration('1 day')).toThrow();
    expect(() => parseDuration('invalid')).toThrow();
    expect(() => parseDuration('1y')).toThrow();
  });
});

describe('formatDuration', () => {
  it('formats "1d" as "1 day"', () => {
    expect(formatDuration('1d')).toBe('1 day');
  });

  it('formats "2d" as "2 days"', () => {
    expect(formatDuration('2d')).toBe('2 days');
  });

  it('formats "1h" as "1 hour"', () => {
    expect(formatDuration('1h')).toBe('1 hour');
  });

  it('formats "24h" as "24 hours"', () => {
    expect(formatDuration('24h')).toBe('24 hours');
  });

  it('formats "1w" as "1 week"', () => {
    expect(formatDuration('1w')).toBe('1 week');
  });

  it('formats "2w" as "2 weeks"', () => {
    expect(formatDuration('2w')).toBe('2 weeks');
  });

  it('formats "1m" as "1 minute"', () => {
    expect(formatDuration('1m')).toBe('1 minute');
  });

  it('formats "30m" as "30 minutes"', () => {
    expect(formatDuration('30m')).toBe('30 minutes');
  });

  it('returns invalid input unchanged', () => {
    expect(formatDuration('invalid')).toBe('invalid');
  });
});
