'use client';

import { useState } from 'react';
import type { ConfidenceInterval } from '@realitycam/shared';

/**
 * ConfidenceIntervalDisplay - Shows confidence score with range indicator (Story 11-2)
 *
 * Displays:
 * - Point estimate with range (e.g., "91% (87%-95%)")
 * - Visual error bar representation
 * - High uncertainty warning when interval width > 0.3
 * - Tooltip explaining confidence intervals
 */

interface ConfidenceIntervalDisplayProps {
  /** Confidence interval data */
  interval: ConfidenceInterval;
  /** Optional label prefix */
  label?: string;
  /** Additional className */
  className?: string;
}

/**
 * InfoIcon - Information icon for tooltip trigger
 */
function InfoIcon({ className = '' }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
  );
}

/**
 * WarningIcon - Warning icon for high uncertainty
 */
function WarningIcon({ className = '' }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
      />
    </svg>
  );
}

/**
 * Format a value as percentage string
 */
function formatPercent(value: number): string {
  return `${Math.round(value * 100)}%`;
}

/**
 * ConfidenceIntervalDisplay - Visual confidence interval with range
 */
export function ConfidenceIntervalDisplay({
  interval,
  label = 'Overall Confidence',
  className = '',
}: ConfidenceIntervalDisplayProps) {
  const [showTooltip, setShowTooltip] = useState(false);

  const pointEstimate = formatPercent(interval.point_estimate);
  const lowerBound = formatPercent(interval.lower_bound);
  const upperBound = formatPercent(interval.upper_bound);
  const intervalWidth = interval.upper_bound - interval.lower_bound;
  const hasHighUncertainty = intervalWidth > 0.3;

  // Calculate positions for visual bar (0-100 scale)
  const lowerPos = Math.round(interval.lower_bound * 100);
  const upperPos = Math.round(interval.upper_bound * 100);
  const pointPos = Math.round(interval.point_estimate * 100);
  const barWidth = upperPos - lowerPos;

  return (
    <div className={className} data-testid="confidence-interval-display">
      {/* Label and value row */}
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-1.5">
          <span className="text-sm font-semibold text-zinc-900 dark:text-white">
            {label}
          </span>
          <div
            className="relative"
            onMouseEnter={() => setShowTooltip(true)}
            onMouseLeave={() => setShowTooltip(false)}
            onFocus={() => setShowTooltip(true)}
            onBlur={() => setShowTooltip(false)}
          >
            <button
              type="button"
              className="text-zinc-400 dark:text-zinc-500 hover:text-zinc-600 dark:hover:text-zinc-300
                         focus:outline-none focus:ring-2 focus:ring-blue-500 rounded"
              aria-label="What is a confidence interval?"
              tabIndex={0}
            >
              <InfoIcon className="w-4 h-4" />
            </button>

            {/* Tooltip */}
            {showTooltip && (
              <div
                className="absolute z-10 bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2
                           bg-zinc-900 dark:bg-zinc-100 text-white dark:text-zinc-900
                           text-xs rounded-lg shadow-lg w-48 text-center"
                role="tooltip"
              >
                95% confidence the true score is within this range
                <div className="absolute top-full left-1/2 -translate-x-1/2 -mt-1">
                  <div className="w-2 h-2 bg-zinc-900 dark:bg-zinc-100 rotate-45" />
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Point estimate with range */}
        <span className="text-sm font-bold text-zinc-900 dark:text-white">
          {pointEstimate}
          <span className="font-normal text-zinc-500 dark:text-zinc-400 ml-1">
            ({lowerBound}-{upperBound})
          </span>
        </span>
      </div>

      {/* Visual error bar */}
      <div className="relative h-3 w-full bg-zinc-200 dark:bg-zinc-700 rounded-full overflow-visible">
        {/* Range bar (interval) */}
        <div
          className="absolute h-full bg-blue-200 dark:bg-blue-800 rounded-full"
          style={{
            left: `${lowerPos}%`,
            width: `${barWidth}%`,
          }}
          aria-hidden="true"
        />

        {/* Point estimate marker */}
        <div
          className="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-blue-600 dark:bg-blue-400 rounded-full border-2 border-white dark:border-zinc-900 shadow"
          style={{ left: `calc(${pointPos}% - 6px)` }}
          aria-hidden="true"
        />

        {/* Lower bound tick */}
        <div
          className="absolute top-0 h-full w-0.5 bg-blue-400 dark:bg-blue-600"
          style={{ left: `${lowerPos}%` }}
          aria-hidden="true"
        />

        {/* Upper bound tick */}
        <div
          className="absolute top-0 h-full w-0.5 bg-blue-400 dark:bg-blue-600"
          style={{ left: `${upperPos}%` }}
          aria-hidden="true"
        />
      </div>

      {/* High uncertainty warning */}
      {hasHighUncertainty && (
        <div
          className="flex items-center gap-1.5 mt-2 text-xs text-yellow-700 dark:text-yellow-400"
          role="alert"
          data-testid="high-uncertainty-warning"
        >
          <WarningIcon className="w-3.5 h-3.5" />
          <span>High uncertainty - results may vary</span>
        </div>
      )}
    </div>
  );
}
