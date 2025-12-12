'use client';

/**
 * ValidationStatusBadge - Displays cross-validation status (Story 11-2)
 *
 * Shows pass/warn/fail status with appropriate colors and icons.
 * Follows ConfidenceBadge styling patterns.
 */

/** Validation status type */
export type ValidationStatus = 'pass' | 'warn' | 'fail';

/** Display configuration for each status */
const STATUS_CONFIG: Record<ValidationStatus, { label: string; bgColor: string; textColor: string }> = {
  pass: {
    label: 'Methods Agree',
    bgColor: 'bg-green-100 dark:bg-green-900/50',
    textColor: 'text-green-800 dark:text-green-300',
  },
  warn: {
    label: 'Minor Inconsistencies',
    bgColor: 'bg-yellow-100 dark:bg-yellow-900/50',
    textColor: 'text-yellow-800 dark:text-yellow-300',
  },
  fail: {
    label: 'Methods Disagree',
    bgColor: 'bg-red-100 dark:bg-red-900/50',
    textColor: 'text-red-800 dark:text-red-300',
  },
};

interface ValidationStatusBadgeProps {
  /** Validation status */
  status: ValidationStatus;
  /** Additional className */
  className?: string;
}

/**
 * CheckIcon - Checkmark SVG icon
 */
function CheckIcon({ className = '' }: { className?: string }) {
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
        d="M5 13l4 4L19 7"
      />
    </svg>
  );
}

/**
 * WarningIcon - Warning triangle SVG icon
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
 * XIcon - X mark SVG icon
 */
function XIcon({ className = '' }: { className?: string }) {
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
        d="M6 18L18 6M6 6l12 12"
      />
    </svg>
  );
}

/**
 * StatusIcon - Renders the appropriate icon based on status
 */
function StatusIcon({ status }: { status: ValidationStatus }) {
  const className = "w-3.5 h-3.5";
  switch (status) {
    case 'pass':
      return <CheckIcon className={className} />;
    case 'warn':
      return <WarningIcon className={className} />;
    case 'fail':
      return <XIcon className={className} />;
  }
}

/**
 * ValidationStatusBadge - Shows cross-validation status with icon and label
 */
export function ValidationStatusBadge({ status, className = '' }: ValidationStatusBadgeProps) {
  const config = STATUS_CONFIG[status];

  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold ${config.bgColor} ${config.textColor} ${className}`}
      role="status"
      aria-label={`Cross-validation status: ${config.label}`}
      data-testid="validation-badge"
    >
      <StatusIcon status={status} />
      {config.label}
    </span>
  );
}
