import type { AttestationLevel } from '@realitycam/shared';

interface AttestationLevelBadgeProps {
  /** Attestation level to display */
  level: AttestationLevel;
  /** Additional className */
  className?: string;
}

/** Shield with checkmark icon (for secure_enclave, strongbox) */
function ShieldCheckIcon({ className = '' }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="currentColor"
      className={`w-4 h-4 ${className}`}
      aria-hidden="true"
    >
      <path
        fillRule="evenodd"
        d="M10 1a.75.75 0 0 1 .59.29l5.5 7a.75.75 0 0 1-.15 1.05A7.48 7.48 0 0 0 12.5 16c0 .67.09 1.32.25 1.94a.75.75 0 0 1-1 .88A8.03 8.03 0 0 1 3 12.54a.75.75 0 0 1 .15-1.05l5.5-7A.75.75 0 0 1 9.1 5H10a.75.75 0 0 1 0 1.5h-.25l-4.3 5.47A6.47 6.47 0 0 0 10 17.98a8.97 8.97 0 0 1-.25-2.1c0-2.72 1.2-5.16 3.1-6.82L10 5h-.25z"
        clipRule="evenodd"
      />
      <path
        fillRule="evenodd"
        d="M10 2.64 5.23 8.72A6.48 6.48 0 0 0 3.5 13c0 2.39 1.29 4.47 3.2 5.59L10 18V2.64zM8.85 11.56l1.43 1.42 3.13-3.13a.75.75 0 1 0-1.06-1.06l-2.07 2.07-.37-.37a.75.75 0 0 0-1.06 1.07z"
        clipRule="evenodd"
      />
    </svg>
  );
}

/** Simple shield icon (for TEE) */
function ShieldIcon({ className = '' }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="currentColor"
      className={`w-4 h-4 ${className}`}
      aria-hidden="true"
    >
      <path
        fillRule="evenodd"
        d="M9.661 2.237a.75.75 0 0 1 .678 0 12.023 12.023 0 0 0 5.267 1.607.75.75 0 0 1 .694.75v3.406c0 4.044-2.137 7.513-5.658 9.317a.75.75 0 0 1-.684 0C6.637 15.513 4.5 12.044 4.5 8V4.594a.75.75 0 0 1 .694-.75 12.023 12.023 0 0 0 5.267-1.607h.2ZM6 5.2v2.8c0 3.283 1.692 6.186 4 7.777 2.308-1.591 4-4.494 4-7.777V5.2a13.502 13.502 0 0 1-4-1.26A13.502 13.502 0 0 1 6 5.2Z"
        clipRule="evenodd"
      />
    </svg>
  );
}

/** Shield with warning/exclamation icon (for unverified) */
function ShieldWarningIcon({ className = '' }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="currentColor"
      className={`w-4 h-4 ${className}`}
      aria-hidden="true"
    >
      <path
        fillRule="evenodd"
        d="M9.661 2.237a.75.75 0 0 1 .678 0 12.023 12.023 0 0 0 5.267 1.607.75.75 0 0 1 .694.75v3.406c0 4.044-2.137 7.513-5.658 9.317a.75.75 0 0 1-.684 0C6.637 15.513 4.5 12.044 4.5 8V4.594a.75.75 0 0 1 .694-.75 12.023 12.023 0 0 0 5.267-1.607h.2ZM10 6a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 10 6Zm0 9a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z"
        clipRule="evenodd"
      />
    </svg>
  );
}

/**
 * Attestation display configuration
 */
const ATTESTATION_CONFIG: Record<AttestationLevel, {
  label: string;
  colorClasses: string;
  Icon: typeof ShieldCheckIcon;
}> = {
  secure_enclave: {
    label: 'Secure Enclave',
    colorClasses: 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300',
    Icon: ShieldCheckIcon,
  },
  strongbox: {
    label: 'StrongBox',
    colorClasses: 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300',
    Icon: ShieldCheckIcon,
  },
  tee: {
    label: 'TEE',
    colorClasses: 'bg-blue-100 text-blue-800 dark:bg-blue-900/50 dark:text-blue-300',
    Icon: ShieldIcon,
  },
  unverified: {
    label: 'Unverified',
    colorClasses: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300',
    Icon: ShieldWarningIcon,
  },
};

/**
 * Get attestation badge configuration
 */
export function getAttestationConfig(level: AttestationLevel) {
  return ATTESTATION_CONFIG[level] || ATTESTATION_CONFIG.unverified;
}

/**
 * AttestationLevelBadge - Color-coded badge displaying attestation security level
 *
 * Shows the attestation level with appropriate color coding:
 * - Green: secure_enclave (iOS), strongbox (Android) - highest trust
 * - Blue: tee (Android) - hardware-isolated but less secure
 * - Yellow: unverified - attestation could not be verified
 */
export function AttestationLevelBadge({ level, className = '' }: AttestationLevelBadgeProps) {
  const config = getAttestationConfig(level);
  const { Icon } = config;

  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${config.colorClasses} ${className}`}
      data-testid="attestation-level-badge"
      role="status"
      aria-label={`Attestation level: ${config.label}`}
    >
      <Icon />
      <span>{config.label}</span>
    </span>
  );
}
