'use client';

import type { DetectionMethodStatus } from '@realitycam/shared';

/** Human-readable display names for detection methods */
export const METHOD_DISPLAY_NAMES: Record<string, string> = {
  lidar_depth: 'LiDAR Depth',
  moire: 'Moire Detection',
  texture: 'Texture Analysis',
  artifacts: 'Artifact Detection',
  supporting: 'Supporting Signals',
};

/** Get display name for a method key */
export function getMethodDisplayName(methodKey: string): string {
  return METHOD_DISPLAY_NAMES[methodKey] || methodKey;
}

/**
 * Get the progress bar fill color based on detection method status.
 * Note: "not_detected" is GOOD for moire/artifacts (means no patterns found)
 */
export function getMethodStatusColor(status: DetectionMethodStatus): string {
  switch (status) {
    case 'pass':
    case 'not_detected': // Good for moire/artifacts - no patterns found
      return 'bg-green-500 dark:bg-green-400';
    case 'warn':
      return 'bg-yellow-500 dark:bg-yellow-400';
    case 'fail':
      return 'bg-red-500 dark:bg-red-400';
    case 'unavailable':
    default:
      return 'bg-zinc-400 dark:bg-zinc-500';
  }
}

/**
 * Get the status text color based on detection method status
 */
function getStatusTextColor(status: DetectionMethodStatus): string {
  switch (status) {
    case 'pass':
    case 'not_detected':
      return 'text-green-600 dark:text-green-400';
    case 'warn':
      return 'text-yellow-600 dark:text-yellow-400';
    case 'fail':
      return 'text-red-600 dark:text-red-400';
    case 'unavailable':
    default:
      return 'text-zinc-500 dark:text-zinc-400';
  }
}

/**
 * Get human-readable status description
 * Special handling for "not_detected" which is good for moire/artifacts
 */
function getStatusDescription(status: DetectionMethodStatus, methodKey: string): string | null {
  if (status === 'not_detected') {
    if (methodKey === 'moire' || methodKey === 'artifacts') {
      return 'No patterns detected (good)';
    }
    return 'Not detected';
  }
  if (status === 'unavailable') {
    return 'Unavailable';
  }
  return null;
}

interface MethodScoreBarProps {
  /** Method key (e.g., 'lidar_depth', 'moire') */
  methodKey: string;
  /** Score from 0.0 to 1.0, null if unavailable */
  score: number | null;
  /** Weight in overall confidence (0.0 to 1.0) */
  weight: number;
  /** Whether method was available */
  available: boolean;
  /** Status string for color coding */
  status: DetectionMethodStatus;
  /** Optional click handler for tooltip trigger */
  onClick?: () => void;
  /** Whether this bar is currently showing its tooltip */
  isActive?: boolean;
  /** Additional className */
  className?: string;
}

/**
 * MethodScoreBar - Horizontal progress bar showing a detection method's score
 *
 * Displays:
 * - Method name with weight indicator
 * - Horizontal progress bar colored by status
 * - Score percentage
 * - Status description for special states (not_detected, unavailable)
 */
export function MethodScoreBar({
  methodKey,
  score,
  weight,
  available,
  status,
  onClick,
  isActive = false,
  className = '',
}: MethodScoreBarProps) {
  const displayName = getMethodDisplayName(methodKey);
  const fillColor = getMethodStatusColor(status);
  const textColor = getStatusTextColor(status);
  const statusDescription = getStatusDescription(status, methodKey);

  // Calculate percentage for display and bar width
  const scorePercent = score !== null ? Math.round(score * 100) : 0;
  const weightPercent = Math.round(weight * 100);

  // Bar width: use score for available methods, 0 for unavailable
  const barWidth = available && score !== null ? scorePercent : 0;

  return (
    <div
      className={`group cursor-pointer ${className}`}
      onClick={onClick}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onClick?.();
        }
      }}
      tabIndex={0}
      role="button"
      aria-label={`${displayName}: ${available ? `${scorePercent}%` : 'Unavailable'}. Click for details.`}
      data-testid={`score-bar-${methodKey}`}
    >
      {/* Method name and weight */}
      <div className="flex items-center justify-between mb-1.5">
        <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          {displayName}
          <span className="ml-2 text-xs text-zinc-500 dark:text-zinc-400 font-normal">
            ({weightPercent}% weight)
          </span>
        </span>
        <span className={`text-sm font-semibold ${textColor}`}>
          {available ? `${scorePercent}%` : 'N/A'}
        </span>
      </div>

      {/* Progress bar */}
      <div
        className="h-2 w-full rounded-full bg-zinc-200 dark:bg-zinc-700 overflow-hidden"
        role="progressbar"
        aria-valuenow={available ? scorePercent : 0}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`${displayName} score`}
      >
        <div
          className={`h-full rounded-full transition-all duration-500 ease-out ${fillColor}`}
          style={{ width: `${barWidth}%` }}
          data-testid="score-bar-fill"
        />
      </div>

      {/* Status description for special states */}
      {statusDescription && (
        <p className={`mt-1 text-xs ${textColor}`}>
          {statusDescription}
        </p>
      )}

      {/* Active indicator for tooltip */}
      {isActive && (
        <div className="mt-1 h-0.5 bg-blue-500 dark:bg-blue-400 rounded-full" />
      )}
    </div>
  );
}
