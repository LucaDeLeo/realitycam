'use client';

import type { TemporalConsistency, TemporalAnomaly } from '@realitycam/shared';

/**
 * TemporalConsistencyDisplay - Shows temporal stability for video captures (Story 11-2)
 *
 * Displays:
 * - Overall stability score
 * - Frame count analyzed
 * - Per-method stability scores
 * - Temporal anomalies if present
 *
 * Hidden entirely for single-frame (photo) captures.
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

/** Display names for temporal anomaly types */
const TEMPORAL_ANOMALY_TYPE_DISPLAY: Record<string, string> = {
  sudden_jump: 'Sudden jump',
  oscillation: 'Oscillation',
  drift: 'Drift',
};

interface TemporalConsistencyDisplayProps {
  /** Temporal consistency data */
  temporalConsistency: TemporalConsistency;
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
 * Get display name for temporal anomaly type
 */
function getAnomalyTypeDisplay(type: string): string {
  return TEMPORAL_ANOMALY_TYPE_DISPLAY[type] || type;
}

/**
 * Format a score as percentage string
 */
function formatPercent(value: number): string {
  return `${Math.round(value * 100)}%`;
}

/**
 * Get color class based on stability score
 */
function getStabilityColor(score: number): string {
  if (score >= 0.8) {
    return 'bg-green-500 dark:bg-green-400';
  }
  if (score >= 0.5) {
    return 'bg-yellow-500 dark:bg-yellow-400';
  }
  return 'bg-red-500 dark:bg-red-400';
}

/**
 * Get text color class based on stability score
 */
function getStabilityTextColor(score: number): string {
  if (score >= 0.8) {
    return 'text-green-600 dark:text-green-400';
  }
  if (score >= 0.5) {
    return 'text-yellow-600 dark:text-yellow-400';
  }
  return 'text-red-600 dark:text-red-400';
}

/**
 * MiniStabilityBar - Small horizontal bar for per-method stability
 */
function MiniStabilityBar({ method, score }: { method: string; score: number }) {
  const displayName = getMethodDisplayName(method);
  const percentValue = Math.round(score * 100);
  const barColor = getStabilityColor(score);

  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-zinc-600 dark:text-zinc-400 w-16 truncate">
        {displayName}
      </span>
      <div className="flex-1 h-1.5 bg-zinc-200 dark:bg-zinc-700 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all ${barColor}`}
          style={{ width: `${percentValue}%` }}
          role="progressbar"
          aria-valuenow={percentValue}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label={`${displayName} stability`}
        />
      </div>
      <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300 w-10 text-right">
        {formatPercent(score)}
      </span>
    </div>
  );
}

/**
 * TemporalAnomalyItem - Single temporal anomaly display
 */
function TemporalAnomalyItem({ anomaly }: { anomaly: TemporalAnomaly }) {
  const method = getMethodDisplayName(anomaly.method);
  const anomalyType = getAnomalyTypeDisplay(anomaly.anomaly_type);

  return (
    <div
      className="flex items-center justify-between py-1.5 px-2 bg-yellow-50 dark:bg-yellow-900/20 rounded text-xs"
      role="listitem"
    >
      <span className="text-yellow-800 dark:text-yellow-300">
        Frame {anomaly.frame_index}: {anomalyType} in {method}
      </span>
      <span className="text-yellow-600 dark:text-yellow-400 font-medium">
        {anomaly.delta_score > 0 ? '+' : ''}{(anomaly.delta_score * 100).toFixed(0)}%
      </span>
    </div>
  );
}

/**
 * TemporalConsistencyDisplay - Video temporal stability section
 */
export function TemporalConsistencyDisplay({
  temporalConsistency,
  className = '',
}: TemporalConsistencyDisplayProps) {
  const { frame_count, stability_scores, anomalies, overall_stability } = temporalConsistency;
  const overallPercent = formatPercent(overall_stability);
  const stabilityTextColor = getStabilityTextColor(overall_stability);

  // Sort stability scores by method name for consistent display
  const sortedScores = Object.entries(stability_scores).sort(([a], [b]) => {
    // Put lidar_depth first
    if (a === 'lidar_depth') return -1;
    if (b === 'lidar_depth') return 1;
    return a.localeCompare(b);
  });

  return (
    <div className={className} data-testid="temporal-consistency-display">
      {/* Header with overall stability */}
      <div className="flex items-center justify-between mb-3">
        <div>
          <h4 className="text-sm font-semibold text-zinc-900 dark:text-white">
            Temporal Stability
          </h4>
          <p className="text-xs text-zinc-500 dark:text-zinc-400">
            {frame_count.toLocaleString()} frames analyzed
          </p>
        </div>
        <span className={`text-lg font-bold ${stabilityTextColor}`}>
          {overallPercent}
        </span>
      </div>

      {/* Per-method stability bars */}
      {sortedScores.length > 0 && (
        <div className="space-y-2 mb-4">
          {sortedScores.map(([method, score]) => (
            <MiniStabilityBar key={method} method={method} score={score} />
          ))}
        </div>
      )}

      {/* Temporal anomalies */}
      {anomalies.length > 0 && (
        <div>
          <p className="text-xs font-medium text-zinc-700 dark:text-zinc-300 mb-2">
            Temporal Anomalies ({anomalies.length})
          </p>
          <div className="space-y-1" role="list" aria-label="Temporal anomalies">
            {anomalies.map((anomaly, index) => (
              <TemporalAnomalyItem
                key={`${anomaly.frame_index}-${anomaly.method}-${index}`}
                anomaly={anomaly}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
