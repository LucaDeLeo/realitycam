interface PrivacyModeBadgeProps {
  className?: string;
}

/**
 * PrivacyModeBadge - Badge indicating Privacy Mode capture
 *
 * Displays a purple badge with shield icon to indicate a hash-only capture
 * where media is verified via device attestation but not stored on server.
 * Includes tooltip explaining the privacy mode trust model.
 */
export function PrivacyModeBadge({ className = '' }: PrivacyModeBadgeProps) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs sm:text-sm font-semibold
                  bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300 ${className}`}
      role="status"
      aria-label="Privacy Mode - Media verified via device attestation"
      title="Media verified via device attestation - original not stored"
      data-testid="privacy-mode-badge"
    >
      {/* Shield Icon */}
      <svg
        className="h-4 w-4"
        fill="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <path
          fillRule="evenodd"
          d="M12.516 2.17a.75.75 0 00-1.032 0 11.209 11.209 0 01-7.877 3.08.75.75 0 00-.722.515A12.74 12.74 0 002.25 9.75c0 5.942 4.064 10.933 9.563 12.348a.749.749 0 00.374 0c5.499-1.415 9.563-6.406 9.563-12.348 0-1.39-.223-2.73-.635-3.985a.75.75 0 00-.722-.516l-.143.001c-2.996 0-5.717-1.17-7.734-3.08zm3.094 8.016a.75.75 0 10-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 00-1.06 1.06l2.25 2.25a.75.75 0 001.14-.094l3.75-5.25z"
          clipRule="evenodd"
        />
      </svg>
      Privacy Mode
    </span>
  );
}
