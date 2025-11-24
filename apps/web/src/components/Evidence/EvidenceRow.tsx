import type { EvidenceStatus } from '@realitycam/shared';

/**
 * Extended status type that includes 'pending' for placeholder states
 */
export type ExtendedEvidenceStatus = EvidenceStatus | 'pending';

interface EvidenceRowProps {
  label: string;
  status: ExtendedEvidenceStatus;
  value?: string;
  className?: string;
}

/**
 * Status icon component - shows visual indicator for each status
 */
function StatusIcon({ status }: { status: ExtendedEvidenceStatus }) {
  const baseClasses = 'h-5 w-5 flex-shrink-0';

  switch (status) {
    case 'pass':
      return (
        <svg
          className={`${baseClasses} text-green-500 dark:text-green-400`}
          fill="currentColor"
          viewBox="0 0 20 20"
          aria-hidden="true"
        >
          <path
            fillRule="evenodd"
            d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
            clipRule="evenodd"
          />
        </svg>
      );
    case 'fail':
      return (
        <svg
          className={`${baseClasses} text-red-500 dark:text-red-400`}
          fill="currentColor"
          viewBox="0 0 20 20"
          aria-hidden="true"
        >
          <path
            fillRule="evenodd"
            d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
            clipRule="evenodd"
          />
        </svg>
      );
    case 'unavailable':
      return (
        <svg
          className={`${baseClasses} text-zinc-400 dark:text-zinc-500`}
          fill="currentColor"
          viewBox="0 0 20 20"
          aria-hidden="true"
        >
          <path
            fillRule="evenodd"
            d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-5a.75.75 0 01.75.75v4.5a.75.75 0 01-1.5 0v-4.5A.75.75 0 0110 5zm0 10a1 1 0 100-2 1 1 0 000 2z"
            clipRule="evenodd"
          />
        </svg>
      );
    case 'pending':
    default:
      return (
        <svg
          className={`${baseClasses} text-zinc-400 dark:text-zinc-500 animate-pulse`}
          fill="currentColor"
          viewBox="0 0 20 20"
          aria-hidden="true"
        >
          <path
            fillRule="evenodd"
            d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z"
            clipRule="evenodd"
          />
        </svg>
      );
  }
}

/**
 * Get status text for accessibility
 */
function getStatusText(status: ExtendedEvidenceStatus): string {
  switch (status) {
    case 'pass':
      return 'Verified';
    case 'fail':
      return 'Failed';
    case 'unavailable':
      return 'Unavailable';
    case 'pending':
    default:
      return 'Pending';
  }
}

/**
 * EvidenceRow - Individual row in the evidence panel
 *
 * Displays a single evidence check with label, status icon, and optional value.
 * Supports pass/fail/unavailable/pending states with appropriate visual indicators.
 */
export function EvidenceRow({ label, status, value, className = '' }: EvidenceRowProps) {
  const statusText = value || getStatusText(status);
  // Generate testid from label: "LiDAR Depth Analysis" -> "depth-analysis"
  const testId = label.toLowerCase()
    .replace('lidar ', '')
    .replace(/\s+/g, '-');

  return (
    <div
      className={`flex items-center justify-between py-3 px-4
                  border-b border-zinc-100 dark:border-zinc-800
                  last:border-b-0 ${className}`}
      data-testid={testId}
    >
      <div className="flex items-center gap-3">
        <StatusIcon status={status} />
        <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          {label}
        </span>
      </div>
      <span
        className={`text-sm ${
          status === 'pass'
            ? 'text-green-600 dark:text-green-400'
            : status === 'fail'
              ? 'text-red-600 dark:text-red-400'
              : 'text-zinc-500 dark:text-zinc-400'
        }`}
      >
        {statusText}
      </span>
    </div>
  );
}
