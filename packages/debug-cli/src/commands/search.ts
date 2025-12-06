/**
 * Search Command
 * Search debug logs by correlation ID, event pattern, or time range.
 */

import { Command } from 'commander';
import { createClient, type QueryFilters } from '../lib/api.js';
import { parseRelativeTime } from '../lib/time-parser.js';
import {
  formatLogs,
  formatLogsJson,
  formatError,
} from '../lib/formatters.js';

const DEFAULT_LIMIT = 100;

interface SearchOptions {
  correlationId?: string;
  event?: string;
  since?: string;
  source?: 'ios' | 'backend' | 'web';
  level?: 'debug' | 'info' | 'warn' | 'error';
  limit?: number;
  json?: boolean;
  apiUrl?: string;
}

/**
 * Execute the search command
 */
async function runSearch(options: SearchOptions): Promise<void> {
  const client = createClient(options.apiUrl);

  const filters: QueryFilters = {
    order: 'desc',
    limit: options.limit ?? DEFAULT_LIMIT,
  };

  // Apply filters
  if (options.correlationId) {
    filters.correlation_id = options.correlationId;
  }

  if (options.event) {
    filters.event = options.event;
  }

  if (options.source) {
    filters.source = options.source;
  }

  if (options.level) {
    filters.level = options.level;
  }

  // Parse relative time if provided
  if (options.since) {
    try {
      filters.since = parseRelativeTime(options.since);
    } catch (error) {
      if (error instanceof Error) {
        console.error(formatError(error.message));
        process.exit(1);
      }
      throw error;
    }
  }

  // Validate that at least one search filter is provided
  const hasSearchFilter = options.correlationId || options.event || options.since;
  if (!hasSearchFilter) {
    console.error(formatError(
      'At least one search filter is required. Use --correlation-id, --event, or --since.'
    ));
    process.exit(1);
  }

  try {
    const response = await client.getDebugLogs(filters);

    if (options.json) {
      console.log(formatLogsJson(response.logs));
    } else {
      console.log(formatLogs(response.logs));

      // Show count information
      if (response.logs.length > 0) {
        const moreText = response.has_more ? ' (more available)' : '';
        console.log('');
        console.log(`Found ${response.count} log(s)${moreText}`);
      }
    }
  } catch (error) {
    if (error instanceof Error) {
      console.error(formatError(error.message));
      process.exit(1);
    }
    throw error;
  }
}

/**
 * Create the search command
 */
export function createSearchCommand(): Command {
  const command = new Command('search')
    .description('Search debug logs by correlation ID, event pattern, or time range')
    .option(
      '-c, --correlation-id <id>',
      'Filter by correlation ID (UUID)'
    )
    .option(
      '-e, --event <pattern>',
      'Filter by event pattern (case-insensitive substring match)'
    )
    .option(
      '--since <time>',
      'Filter logs newer than time (e.g., "1 hour ago", "30m", "2d")'
    )
    .option(
      '-s, --source <source>',
      'Filter by source (ios, backend, web)',
      (value) => {
        const valid = ['ios', 'backend', 'web'];
        if (!valid.includes(value)) {
          throw new Error(`Invalid source: ${value}. Must be one of: ${valid.join(', ')}`);
        }
        return value as 'ios' | 'backend' | 'web';
      }
    )
    .option(
      '-l, --level <level>',
      'Filter by level (debug, info, warn, error)',
      (value) => {
        const valid = ['debug', 'info', 'warn', 'error'];
        if (!valid.includes(value)) {
          throw new Error(`Invalid level: ${value}. Must be one of: ${valid.join(', ')}`);
        }
        return value as 'debug' | 'info' | 'warn' | 'error';
      }
    )
    .option(
      '-n, --limit <count>',
      'Maximum number of results',
      (value) => {
        const num = parseInt(value, 10);
        if (isNaN(num) || num < 1) {
          throw new Error('Limit must be a positive integer');
        }
        return num;
      }
    )
    .option('--json', 'Output raw JSON array')
    .option('--api-url <url>', 'API URL (default: http://localhost:8080)')
    .action(async (options: SearchOptions) => {
      await runSearch(options);
    });

  return command;
}
