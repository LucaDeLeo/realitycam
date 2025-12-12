'use client';

import { useState } from 'react';
import type { PairwiseConsistency } from '@realitycam/shared';

/**
 * PairwiseConsistencyGrid - Displays method pair agreement grid (Story 11-2)
 *
 * Shows pairwise consistency between detection methods in a compact grid.
 * Supports responsive layouts and tooltips for expected relationships.
 */

/** Display names for detection methods */
const METHOD_DISPLAY_NAMES: Record<string, string> = {
  lidar_depth: 'LiDAR',
  lidar: 'LiDAR',
  moire: 'Moire',
  texture: 'Texture',
  artifacts: 'Artifacts',
  supporting: 'Supporting',
};

/** Human-readable explanations for expected relationships */
const EXPECTED_RELATIONSHIP_DISPLAY: Record<string, string> = {
  positive: 'Expected to correlate (both high or both low)',
  negative: 'Expected to be inverse (one high, one low)',
  neutral: 'No strong expected relationship',
};

interface PairwiseConsistencyGridProps {
  /** List of pairwise consistency results */
  consistencies: PairwiseConsistency[];
  /** Additional className */
  className?: string;
}

/**
 * Get display name for a method key
 */
function getMethodDisplayName(methodKey: string): string {
  return METHOD_DISPLAY_NAMES[methodKey] || methodKey;
}

/**
 * Format agreement score as percentage
 */
function formatAgreement(score: number): string {
  return `${Math.round(score * 100)}%`;
}

/**
 * Get color classes for agreement indicator dot
 */
function getAgreementDotColor(isAnomaly: boolean, agreementScore: number): string {
  if (isAnomaly) {
    return 'bg-red-500 dark:bg-red-400';
  }
  if (agreementScore >= 0.7) {
    return 'bg-green-500 dark:bg-green-400';
  }
  if (agreementScore >= 0.4) {
    return 'bg-yellow-500 dark:bg-yellow-400';
  }
  return 'bg-orange-500 dark:bg-orange-400';
}

/**
 * PairwiseConsistencyItem - Single pair row in the grid
 */
function PairwiseConsistencyItem({
  consistency,
  isHovered,
  onHover,
  onLeave,
}: {
  consistency: PairwiseConsistency;
  isHovered: boolean;
  onHover: () => void;
  onLeave: () => void;
}) {
  const methodA = getMethodDisplayName(consistency.method_a);
  const methodB = getMethodDisplayName(consistency.method_b);
  const agreement = formatAgreement(consistency.actual_agreement);
  const dotColor = getAgreementDotColor(consistency.is_anomaly, consistency.actual_agreement);

  return (
    <div
      className="relative"
      onMouseEnter={onHover}
      onMouseLeave={onLeave}
      onFocus={onHover}
      onBlur={onLeave}
    >
      <div
        className={`flex items-center justify-between p-2 rounded-lg transition-colors ${
          consistency.is_anomaly
            ? 'bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800'
            : 'bg-zinc-50 dark:bg-zinc-800/50'
        }`}
        role="listitem"
        aria-label={`${methodA} and ${methodB}: ${agreement} agreement${consistency.is_anomaly ? ' (anomaly)' : ''}`}
        tabIndex={0}
      >
        {/* Method pair names */}
        <div className="flex items-center gap-1.5 text-sm text-zinc-700 dark:text-zinc-300">
          <span className="font-medium">{methodA}</span>
          <span className="text-zinc-400 dark:text-zinc-500">&harr;</span>
          <span className="font-medium">{methodB}</span>
        </div>

        {/* Agreement score and indicator */}
        <div className="flex items-center gap-2">
          <span className={`text-sm font-semibold ${
            consistency.is_anomaly ? 'text-red-600 dark:text-red-400' : 'text-zinc-700 dark:text-zinc-300'
          }`}>
            {agreement}
          </span>
          <span
            className={`w-2 h-2 rounded-full ${dotColor}`}
            aria-hidden="true"
          />
          {consistency.is_anomaly && (
            <span className="text-xs font-medium text-red-600 dark:text-red-400 uppercase">
              Anomaly
            </span>
          )}
        </div>
      </div>

      {/* Tooltip */}
      {isHovered && (
        <div
          className="absolute z-10 bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2
                     bg-zinc-900 dark:bg-zinc-100 text-white dark:text-zinc-900
                     text-xs rounded-lg shadow-lg whitespace-nowrap"
          role="tooltip"
        >
          {EXPECTED_RELATIONSHIP_DISPLAY[consistency.expected_relationship]}
          <div className="absolute top-full left-1/2 -translate-x-1/2 -mt-1">
            <div className="w-2 h-2 bg-zinc-900 dark:bg-zinc-100 rotate-45" />
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * PairwiseConsistencyGrid - Grid of method pair consistencies
 */
export function PairwiseConsistencyGrid({
  consistencies,
  className = '',
}: PairwiseConsistencyGridProps) {
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);

  if (consistencies.length === 0) {
    return (
      <div className={`text-sm text-zinc-500 dark:text-zinc-400 italic ${className}`}>
        No pairwise consistency data available
      </div>
    );
  }

  return (
    <div className={className}>
      <h4 className="text-sm font-semibold text-zinc-900 dark:text-white mb-3">
        Pairwise Consistency
      </h4>
      <div
        className="grid grid-cols-1 md:grid-cols-2 gap-2"
        role="list"
        aria-label="Method pair consistency results"
        data-testid="pairwise-consistency-grid"
      >
        {consistencies.map((consistency, index) => (
          <PairwiseConsistencyItem
            key={`${consistency.method_a}-${consistency.method_b}`}
            consistency={consistency}
            isHovered={hoveredIndex === index}
            onHover={() => setHoveredIndex(index)}
            onLeave={() => setHoveredIndex(null)}
          />
        ))}
      </div>
    </div>
  );
}
