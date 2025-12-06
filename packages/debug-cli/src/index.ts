#!/usr/bin/env bun
/**
 * Debug CLI
 * Query and manage debug logs from the rial. backend.
 *
 * Usage:
 *   bun debug:tail [options]    - Display recent logs
 *   bun debug:search [options]  - Search logs by criteria
 *   bun debug:clear [options]   - Delete logs
 */

import { Command } from 'commander';
import { createTailCommand } from './commands/tail.js';
import { createSearchCommand } from './commands/search.js';
import { createClearCommand } from './commands/clear.js';

const program = new Command();

program
  .name('debug-cli')
  .description('Query and manage debug logs from the rial. backend')
  .version('0.1.0');

// Register commands
program.addCommand(createTailCommand());
program.addCommand(createSearchCommand());
program.addCommand(createClearCommand());

// Parse arguments and execute
program.parse(process.argv);
