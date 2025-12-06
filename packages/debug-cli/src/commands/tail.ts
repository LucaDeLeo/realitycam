/**
 * Tail Command
 * Display recent debug logs with optional filtering and follow mode.
 */

import { Command } from 'commander';
import { createClient, type DebugLog, type QueryFilters } from '../lib/api.js';
import {
  formatLogs,
  formatLogsJson,
  formatError,
  formatWatching,
  formatSeparator,
} from '../lib/formatters.js';

const POLL_INTERVAL_MS = 2000;
const DEFAULT_LIMIT = 100;

interface TailOptions {
  source?: 'ios' | 'backend' | 'web';
  level?: 'debug' | 'info' | 'warn' | 'error';
  follow?: boolean;
  json?: boolean;
  number?: number;
  apiUrl?: string;
}

/**
 * Sleep for specified milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Execute the tail command
 */
async function runTail(options: TailOptions): Promise<void> {
  const client = createClient(options.apiUrl);
  const limit = options.number ?? DEFAULT_LIMIT;

  const filters: QueryFilters = {
    order: 'desc',
    limit,
  };

  if (options.source) filters.source = options.source;
  if (options.level) filters.level = options.level;

  // Initial fetch
  try {
    const response = await client.getDebugLogs(filters);

    if (options.json) {
      console.log(formatLogsJson(response.logs));
    } else {
      console.log(formatLogs(response.logs));
    }

    // If not following, we're done
    if (!options.follow) {
      return;
    }

    // Follow mode: poll for new logs
    console.log('');
    console.log(formatWatching());
    console.log(formatSeparator());

    let lastTimestamp: string | null = response.logs[0]?.timestamp ?? null;
    let isRunning = true;

    // Handle graceful shutdown on Ctrl+C
    const handleSignal = () => {
      isRunning = false;
      console.log('\n');
      process.exit(0);
    };

    process.on('SIGINT', handleSignal);
    process.on('SIGTERM', handleSignal);

    while (isRunning) {
      await sleep(POLL_INTERVAL_MS);

      if (!isRunning) break;

      try {
        // Fetch logs newer than the last seen timestamp
        const pollFilters: QueryFilters = {
          ...filters,
          order: 'asc', // Get oldest first so we can display in order
        };

        if (lastTimestamp) {
          pollFilters.since = lastTimestamp;
        }

        const pollResponse = await client.getDebugLogs(pollFilters);

        // Filter out logs we've already seen (since is inclusive)
        const newLogs = pollResponse.logs.filter(
          log => !lastTimestamp || log.timestamp > lastTimestamp
        );

        if (newLogs.length > 0) {
          // Update last timestamp
          lastTimestamp = newLogs[newLogs.length - 1].timestamp;

          // Display new logs
          if (options.json) {
            // In JSON mode, output each log as a separate line for streaming
            for (const log of newLogs) {
              console.log(JSON.stringify(log));
            }
          } else {
            console.log(formatLogs(newLogs));
          }
        }
      } catch (error) {
        // Don't exit on poll errors, just log and continue
        if (error instanceof Error) {
          console.error(formatError(`Poll failed: ${error.message}`));
        }
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
 * Create the tail command
 */
export function createTailCommand(): Command {
  const command = new Command('tail')
    .description('Display recent debug logs')
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
    .option('-f, --follow', 'Continuously poll for new logs')
    .option('-n, --number <count>', 'Number of log entries to show', (value) => {
      const num = parseInt(value, 10);
      if (isNaN(num) || num < 1) {
        throw new Error('Number must be a positive integer');
      }
      return num;
    })
    .option('--json', 'Output raw JSON')
    .option('--api-url <url>', 'API URL (default: http://localhost:8080)')
    .action(async (options: TailOptions) => {
      await runTail(options);
    });

  return command;
}
