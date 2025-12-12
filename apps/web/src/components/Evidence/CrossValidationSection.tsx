'use client';

import { useState } from 'react';
import type { CrossValidationResult } from '@realitycam/shared';
import { ValidationStatusBadge } from './ValidationStatusBadge';
import { ConfidenceIntervalDisplay } from './ConfidenceIntervalDisplay';
import { PairwiseConsistencyGrid } from './PairwiseConsistencyGrid';
import { AnomalyList } from './AnomalyList';
import { TemporalConsistencyDisplay } from './TemporalConsistencyDisplay';

/**
 * CrossValidationSection - Composite component for cross-validation display (Story 11-2)
 *
 * Composes:
 * - ValidationStatusBadge (header status)
 * - ConfidenceIntervalDisplay (overall confidence with range)
 * - PairwiseConsistencyGrid (method pair agreements)
 * - AnomalyList (detected anomalies)
 * - TemporalConsistencyDisplay (video only)
 * - Penalty display (if penalty > 0)
 *
 * Features:
 * - Collapsible with independent expand/collapse state
 * - Visually separated from method scores
 * - Responsive design matching MethodBreakdownSection
 */

interface CrossValidationSectionProps {
  /** Cross-validation result data */
  crossValidation: CrossValidationResult;
  /** Whether section is expanded by default */
  defaultExpanded?: boolean;
  /** Additional className */
  className?: string;
}

/**
 * ChevronDownIcon - Expand/collapse indicator
 */
function ChevronDownIcon({ className = '' }: { className?: string }) {
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
        d="M19 9l-7 7-7-7"
      />
    </svg>
  );
}

/**
 * PenaltyDisplay - Shows the overall penalty applied (if any)
 */
function PenaltyDisplay({
  penalty,
  anomalyCount,
}: {
  penalty: number;
  anomalyCount: number;
}) {
  // Don't show if no penalty
  if (penalty === 0) {
    return null;
  }

  const penaltyPercent = Math.round(penalty * 100);

  return (
    <div
      className="flex items-center justify-between p-3 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800"
      role="alert"
      data-testid="penalty-display"
    >
      <div>
        <p className="text-sm font-semibold text-red-800 dark:text-red-300">
          Cross-validation penalty: -{penaltyPercent}%
        </p>
        <p className="text-xs text-red-600 dark:text-red-400">
          Applied due to {anomalyCount} detected {anomalyCount === 1 ? 'inconsistency' : 'inconsistencies'}
        </p>
      </div>
    </div>
  );
}

/**
 * ProcessingFooter - Shows analysis time and version
 */
function ProcessingFooter({
  analysisTimeMs,
  algorithmVersion,
}: {
  analysisTimeMs: number;
  algorithmVersion: string;
}) {
  return (
    <div className="text-xs text-zinc-500 dark:text-zinc-400 pt-3 border-t border-zinc-100 dark:border-zinc-800">
      Analysis: {analysisTimeMs}ms (v{algorithmVersion})
    </div>
  );
}

/**
 * CrossValidationSection - Main composite component
 */
export function CrossValidationSection({
  crossValidation,
  defaultExpanded = true,
  className = '',
}: CrossValidationSectionProps) {
  const [isExpanded, setIsExpanded] = useState(defaultExpanded);

  const toggleExpanded = () => setIsExpanded(!isExpanded);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggleExpanded();
    }
  };

  const {
    validation_status,
    aggregated_interval,
    pairwise_consistencies,
    anomalies,
    temporal_consistency,
    overall_penalty,
    analysis_time_ms,
    algorithm_version,
  } = crossValidation;

  return (
    <div
      className={`border-t border-zinc-200 dark:border-zinc-700 ${className}`}
      data-testid="cross-validation-section"
    >
      {/* Section Header - Click to expand/collapse */}
      <button
        type="button"
        onClick={toggleExpanded}
        onKeyDown={handleKeyDown}
        aria-expanded={isExpanded}
        aria-controls="cross-validation-content"
        className="w-full flex items-center justify-between px-4 sm:px-6 py-3
                   bg-zinc-50 dark:bg-zinc-900/50
                   hover:bg-zinc-100 dark:hover:bg-zinc-800/50
                   transition-colors cursor-pointer
                   focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500"
      >
        <div className="flex items-center gap-3">
          <h4
            id="cross-validation-header"
            className="text-sm font-semibold text-zinc-900 dark:text-white"
          >
            Cross-Validation
          </h4>
          <ValidationStatusBadge status={validation_status} />
        </div>
        <ChevronDownIcon
          className={`h-4 w-4 text-zinc-500 dark:text-zinc-400 transition-transform duration-200 ${
            isExpanded ? 'rotate-180' : ''
          }`}
        />
      </button>

      {/* Section Content */}
      <div
        id="cross-validation-content"
        role="region"
        aria-labelledby="cross-validation-header"
        className={`transition-all duration-200 ease-in-out ${
          isExpanded ? 'max-h-[2000px] opacity-100' : 'max-h-0 opacity-0 overflow-hidden'
        }`}
      >
        <div className="px-4 sm:px-6 py-4 space-y-4">
          {/* Confidence Interval */}
          <ConfidenceIntervalDisplay interval={aggregated_interval} />

          {/* Pairwise Consistency Grid */}
          {pairwise_consistencies.length > 0 && (
            <PairwiseConsistencyGrid consistencies={pairwise_consistencies} />
          )}

          {/* Anomaly List */}
          <AnomalyList anomalies={anomalies} />

          {/* Temporal Consistency (video only) */}
          {temporal_consistency && (
            <div className="pt-3 border-t border-zinc-100 dark:border-zinc-800">
              <TemporalConsistencyDisplay temporalConsistency={temporal_consistency} />
            </div>
          )}

          {/* Penalty Display */}
          {overall_penalty > 0 && (
            <PenaltyDisplay penalty={overall_penalty} anomalyCount={anomalies.length} />
          )}

          {/* Processing Footer */}
          <ProcessingFooter
            analysisTimeMs={analysis_time_ms}
            algorithmVersion={algorithm_version}
          />
        </div>
      </div>
    </div>
  );
}
