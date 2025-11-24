import type { ConfidenceLevel } from '@realitycam/shared';

/**
 * Extended confidence level type that includes 'pending' for placeholder states
 */
export type ExtendedConfidenceLevel = ConfidenceLevel | 'pending';

/**
 * Badge color mappings for each confidence level
 * Semantic colors: green=high, yellow=medium, orange=low, red=suspicious, gray=pending
 */
const badgeColors: Record<ExtendedConfidenceLevel, string> = {
  high: 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300',
  medium: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300',
  low: 'bg-orange-100 text-orange-800 dark:bg-orange-900/50 dark:text-orange-300',
  suspicious: 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-300',
  pending: 'bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400',
};

/**
 * Human-readable labels for each confidence level
 */
const badgeLabels: Record<ExtendedConfidenceLevel, string> = {
  high: 'HIGH CONFIDENCE',
  medium: 'MEDIUM CONFIDENCE',
  low: 'LOW CONFIDENCE',
  suspicious: 'SUSPICIOUS',
  pending: 'PENDING',
};

interface ConfidenceBadgeProps {
  level: ExtendedConfidenceLevel;
  className?: string;
}

/**
 * ConfidenceBadge - Color-coded badge displaying verification confidence level
 *
 * Shows a pill-shaped badge with semantic colors indicating the verification
 * confidence. Supports dark mode with appropriate color adjustments.
 */
export function ConfidenceBadge({ level, className = '' }: ConfidenceBadgeProps) {
  return (
    <span
      className={`inline-flex items-center px-3 py-1 rounded-full text-xs sm:text-sm font-semibold ${badgeColors[level]} ${className}`}
      role="status"
      aria-label={`Confidence level: ${badgeLabels[level]}`}
      data-testid="confidence-badge"
    >
      {badgeLabels[level]}
    </span>
  );
}
