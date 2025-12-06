/**
 * Clear Command
 * Delete debug logs with optional filters and confirmation.
 */

import { Command } from 'commander';
import * as readline from 'readline';
import { createClient, type DeleteFilters } from '../lib/api.js';
import { parseDuration, formatDuration } from '../lib/time-parser.js';
import {
  formatDeleteResult,
  formatError,
  formatWarning,
} from '../lib/formatters.js';

interface ClearOptions {
  olderThan?: string;
  source?: 'ios' | 'backend' | 'web';
  level?: 'debug' | 'info' | 'warn' | 'error';
  yes?: boolean;
  apiUrl?: string;
}

/**
 * Prompt user for confirmation
 */
function confirm(message: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(message, (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes');
    });
  });
}

/**
 * Build a human-readable description of what will be deleted
 */
function buildDeleteDescription(options: ClearOptions): string {
  const parts: string[] = [];

  if (options.olderThan) {
    parts.push(`older than ${formatDuration(options.olderThan)}`);
  }

  if (options.source) {
    parts.push(`from source "${options.source}"`);
  }

  if (options.level) {
    parts.push(`with level "${options.level}"`);
  }

  if (parts.length === 0) {
    return 'ALL logs';
  }

  return `logs ${parts.join(' and ')}`;
}

/**
 * Execute the clear command
 */
async function runClear(options: ClearOptions): Promise<void> {
  const client = createClient(options.apiUrl);

  const filters: DeleteFilters = {};

  // Parse older-than duration
  if (options.olderThan) {
    try {
      filters.older_than = parseDuration(options.olderThan);
    } catch (error) {
      if (error instanceof Error) {
        console.error(formatError(error.message));
        process.exit(1);
      }
      throw error;
    }
  }

  if (options.source) {
    filters.source = options.source;
  }

  if (options.level) {
    filters.level = options.level;
  }

  // Build description for confirmation
  const description = buildDeleteDescription(options);

  // Require confirmation unless --yes is provided
  if (!options.yes) {
    const hasFilters = options.olderThan || options.source || options.level;

    if (!hasFilters) {
      // Deleting everything - extra warning
      console.log(formatWarning('This will delete ALL debug logs from the database.'));
    }

    const confirmed = await confirm(`Are you sure you want to delete ${description}? (y/N) `);

    if (!confirmed) {
      console.log('Aborted.');
      return;
    }
  }

  try {
    const response = await client.deleteDebugLogs(filters);

    console.log(formatDeleteResult(response.deleted, {
      source: options.source,
      olderThan: options.olderThan ? formatDuration(options.olderThan) : undefined,
    }));
  } catch (error) {
    if (error instanceof Error) {
      console.error(formatError(error.message));
      process.exit(1);
    }
    throw error;
  }
}

/**
 * Create the clear command
 */
export function createClearCommand(): Command {
  const command = new Command('clear')
    .description('Delete debug logs with optional filters')
    .option(
      '--older-than <duration>',
      'Delete logs older than duration (e.g., "1d", "2h", "1w")'
    )
    .option(
      '-s, --source <source>',
      'Delete only logs from specific source (ios, backend, web)',
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
      'Delete only logs with specific level (debug, info, warn, error)',
      (value) => {
        const valid = ['debug', 'info', 'warn', 'error'];
        if (!valid.includes(value)) {
          throw new Error(`Invalid level: ${value}. Must be one of: ${valid.join(', ')}`);
        }
        return value as 'debug' | 'info' | 'warn' | 'error';
      }
    )
    .option('-y, --yes', 'Skip confirmation prompt')
    .option('--api-url <url>', 'API URL (default: http://localhost:8080)')
    .action(async (options: ClearOptions) => {
      await runClear(options);
    });

  return command;
}
