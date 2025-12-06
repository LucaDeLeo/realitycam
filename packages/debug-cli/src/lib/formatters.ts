/**
 * Output Formatters
 * Color-coded and aligned log output for terminal display.
 */

import chalk from 'chalk';
import type { DebugLog } from './api.js';

/**
 * Level colors as specified in AC1:
 * - red = error
 * - yellow = warn
 * - blue = info
 * - gray = debug
 */
const levelColors = {
  error: chalk.red,
  warn: chalk.yellow,
  info: chalk.blue,
  debug: chalk.gray,
} as const;

/**
 * Source column width for alignment
 */
const SOURCE_WIDTH = 8;
const LEVEL_WIDTH = 7;
const EVENT_WIDTH = 24;

/**
 * Format a level string with color
 */
function formatLevel(level: DebugLog['level']): string {
  const colorFn = levelColors[level] || chalk.white;
  const paddedLevel = `[${level.toUpperCase()}]`.padEnd(LEVEL_WIDTH + 2);
  return colorFn(paddedLevel);
}

/**
 * Format a source string (padded for alignment)
 */
function formatSource(source: DebugLog['source']): string {
  return chalk.cyan(source.padEnd(SOURCE_WIDTH));
}

/**
 * Format an event string (padded/truncated for alignment)
 */
function formatEvent(event: string): string {
  const truncated = event.length > EVENT_WIDTH
    ? event.slice(0, EVENT_WIDTH - 1) + '\u2026'
    : event.padEnd(EVENT_WIDTH);
  return chalk.white(truncated);
}

/**
 * Format a timestamp for display
 */
function formatTimestamp(timestamp: string): string {
  return chalk.gray(timestamp);
}

/**
 * Format correlation ID
 */
function formatCorrelationId(correlationId: string): string {
  // Show first 8 chars of UUID for brevity
  const short = correlationId.slice(0, 8);
  return chalk.magenta(`correlation: ${short}`);
}

/**
 * Format a single log entry for colored terminal output.
 *
 * Format:
 * 2024-12-05T10:30:15Z  [ERROR]  ios      UPLOAD_FAILED    correlation: abc-123
 */
export function formatLogEntry(log: DebugLog): string {
  const parts = [
    formatTimestamp(log.timestamp),
    ' ',
    formatLevel(log.level),
    ' ',
    formatSource(log.source),
    ' ',
    formatEvent(log.event),
    ' ',
    formatCorrelationId(log.correlation_id),
  ];

  return parts.join('');
}

/**
 * Format a single log entry with payload details.
 */
export function formatLogEntryVerbose(log: DebugLog): string {
  const mainLine = formatLogEntry(log);
  const payloadStr = JSON.stringify(log.payload, null, 2);
  const indentedPayload = payloadStr
    .split('\n')
    .map(line => '    ' + chalk.gray(line))
    .join('\n');

  return `${mainLine}\n${indentedPayload}`;
}

/**
 * Format multiple log entries for terminal display.
 */
export function formatLogs(logs: DebugLog[], verbose = false): string {
  if (logs.length === 0) {
    return chalk.gray('No logs found.');
  }

  const formatter = verbose ? formatLogEntryVerbose : formatLogEntry;
  return logs.map(formatter).join('\n');
}

/**
 * Format logs as JSON (for --json flag).
 */
export function formatLogsJson(logs: DebugLog[]): string {
  return JSON.stringify(logs, null, 2);
}

/**
 * Format deletion result message.
 */
export function formatDeleteResult(deleted: number, filters: { source?: string; olderThan?: string }): string {
  const parts: string[] = [];

  if (filters.source) {
    parts.push(`from source "${filters.source}"`);
  }
  if (filters.olderThan) {
    parts.push(`older than ${filters.olderThan}`);
  }

  const filterStr = parts.length > 0 ? ` (${parts.join(', ')})` : '';

  if (deleted === 0) {
    return chalk.yellow(`No logs deleted${filterStr}.`);
  }

  return chalk.green(`Deleted ${deleted} log${deleted === 1 ? '' : 's'}${filterStr}.`);
}

/**
 * Format an error message for display.
 */
export function formatError(message: string): string {
  return chalk.red(`Error: ${message}`);
}

/**
 * Format a warning message.
 */
export function formatWarning(message: string): string {
  return chalk.yellow(`Warning: ${message}`);
}

/**
 * Format a success message.
 */
export function formatSuccess(message: string): string {
  return chalk.green(message);
}

/**
 * Format a header/title.
 */
export function formatHeader(title: string): string {
  return chalk.bold.underline(title);
}

/**
 * Format "watching for new logs" message
 */
export function formatWatching(): string {
  return chalk.gray('Watching for new logs... (Ctrl+C to stop)');
}

/**
 * Format a separator line
 */
export function formatSeparator(): string {
  return chalk.gray('-'.repeat(80));
}
