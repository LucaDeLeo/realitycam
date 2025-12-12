'use client';

import { useState } from 'react';
import type { AnomalyReport } from '@realitycam/shared';

/**
 * AnomalyList - Displays detected anomalies from cross-validation (Story 11-2)
 *
 * Shows anomaly count badge, expandable list with severity indicators,
 * and confidence impact per anomaly.
 */

/** Display names for anomaly types */
const ANOMALY_TYPE_DISPLAY: Record<string, string> = {
  contradictory_signals: 'Contradictory Signals',
  too_high_agreement: 'Too Perfect Agreement',
  isolated_disagreement: 'Isolated Disagreement',
  boundary_cluster: 'Boundary Clustering',
  correlation_anomaly: 'Correlation Anomaly',
};

/** Severity color mappings */
const SEVERITY_COLORS: Record<string, { dot: string; text: string }> = {
  low: {
    dot: 'bg-yellow-500 dark:bg-yellow-400',
    text: 'text-yellow-700 dark:text-yellow-400',
  },
  medium: {
    dot: 'bg-orange-500 dark:bg-orange-400',
    text: 'text-orange-700 dark:text-orange-400',
  },
  high: {
    dot: 'bg-red-500 dark:bg-red-400',
    text: 'text-red-700 dark:text-red-400',
  },
};

/** Display names for detection methods */
const METHOD_DISPLAY_NAMES: Record<string, string> = {
  lidar_depth: 'LiDAR',
  lidar: 'LiDAR',
  moire: 'Moire',
  texture: 'Texture',
  artifacts: 'Artifacts',
  supporting: 'Supporting',
};

interface AnomalyListProps {
  /** List of anomaly reports */
  anomalies: AnomalyReport[];
  /** Additional className */
  className?: string;
}

/**
 * Get display name for anomaly type
 */
function getAnomalyTypeDisplay(type: string): string {
  return ANOMALY_TYPE_DISPLAY[type] || type;
}

/**
 * Get display name for a method key
 */
function getMethodDisplayName(methodKey: string): string {
  return METHOD_DISPLAY_NAMES[methodKey] || methodKey;
}

/**
 * Format confidence impact as percentage string
 */
function formatConfidenceImpact(impact: number): string {
  if (impact === 0) return 'No impact';
  const sign = impact > 0 ? '+' : '';
  return `${sign}${Math.round(impact * 100)}%`;
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
 * AnomalyItem - Single anomaly report row
 */
function AnomalyItem({ anomaly }: { anomaly: AnomalyReport }) {
  const severityColors = SEVERITY_COLORS[anomaly.severity] || SEVERITY_COLORS.low;
  const impactText = formatConfidenceImpact(anomaly.confidence_impact);
  const isNegativeImpact = anomaly.confidence_impact < 0;

  return (
    <div
      className="p-3 bg-zinc-50 dark:bg-zinc-800/50 rounded-lg border border-zinc-200 dark:border-zinc-700"
      role="listitem"
    >
      {/* Header: Type and Impact */}
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <span
            className={`w-2 h-2 rounded-full ${severityColors.dot}`}
            aria-label={`${anomaly.severity} severity`}
          />
          <span className="text-sm font-semibold text-zinc-900 dark:text-white">
            {getAnomalyTypeDisplay(anomaly.anomaly_type)}
          </span>
        </div>
        <span
          className={`text-sm font-semibold ${
            isNegativeImpact ? 'text-red-600 dark:text-red-400' : 'text-zinc-600 dark:text-zinc-400'
          }`}
        >
          {impactText}
        </span>
      </div>

      {/* Affected methods */}
      <div className="flex flex-wrap gap-1 mb-2">
        {anomaly.affected_methods.map((method) => (
          <span
            key={method}
            className="inline-flex px-1.5 py-0.5 text-xs font-medium bg-zinc-200 dark:bg-zinc-700 text-zinc-700 dark:text-zinc-300 rounded"
          >
            {getMethodDisplayName(method)}
          </span>
        ))}
      </div>

      {/* Details description */}
      <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
        {anomaly.details}
      </p>
    </div>
  );
}

/**
 * AnomalyList - List of anomalies with collapse behavior
 */
export function AnomalyList({ anomalies, className = '' }: AnomalyListProps) {
  // Collapse by default if more than 2 anomalies
  const [isExpanded, setIsExpanded] = useState(anomalies.length <= 2);

  const toggleExpanded = () => setIsExpanded(!isExpanded);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggleExpanded();
    }
  };

  // No anomalies - show success message
  if (anomalies.length === 0) {
    return (
      <div className={className} data-testid="anomaly-list">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-zinc-900 dark:text-white">
            Anomalies
          </span>
          <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300">
            No anomalies
          </span>
        </div>
      </div>
    );
  }

  // Determine count badge color based on severity
  const hasHighSeverity = anomalies.some((a) => a.severity === 'high');
  const hasMediumSeverity = anomalies.some((a) => a.severity === 'medium');
  const countBadgeColor = hasHighSeverity
    ? 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-300'
    : hasMediumSeverity
      ? 'bg-orange-100 text-orange-800 dark:bg-orange-900/50 dark:text-orange-300'
      : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300';

  return (
    <div className={className} data-testid="anomaly-list">
      {/* Header with count badge */}
      <button
        type="button"
        onClick={toggleExpanded}
        onKeyDown={handleKeyDown}
        aria-expanded={isExpanded}
        aria-controls="anomaly-list-content"
        className="w-full flex items-center justify-between py-1
                   focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500 rounded"
        data-testid="expand-anomalies"
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-zinc-900 dark:text-white">
            Anomalies
          </span>
          <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${countBadgeColor}`}>
            {anomalies.length} detected
          </span>
        </div>
        <ChevronDownIcon
          className={`h-4 w-4 text-zinc-500 dark:text-zinc-400 transition-transform duration-200 ${
            isExpanded ? 'rotate-180' : ''
          }`}
        />
      </button>

      {/* Expandable content */}
      <div
        id="anomaly-list-content"
        className={`transition-all duration-200 ease-in-out overflow-hidden ${
          isExpanded ? 'max-h-[500px] opacity-100 mt-3' : 'max-h-0 opacity-0'
        }`}
      >
        <div className="space-y-2" role="list" aria-label="Detected anomalies">
          {anomalies.map((anomaly, index) => (
            <AnomalyItem key={`${anomaly.anomaly_type}-${index}`} anomaly={anomaly} />
          ))}
        </div>
      </div>
    </div>
  );
}
