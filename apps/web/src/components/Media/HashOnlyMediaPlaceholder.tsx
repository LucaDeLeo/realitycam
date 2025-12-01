interface HashOnlyMediaPlaceholderProps {
  className?: string;
  aspectRatio?: '4:3' | '16:9';
}

/**
 * Aspect ratio class mappings for hash-only placeholder
 */
const aspectRatioClasses: Record<string, string> = {
  '4:3': 'aspect-[4/3]',
  '16:9': 'aspect-video',
};

/**
 * HashOnlyMediaPlaceholder - Placeholder for hash-only captures
 *
 * Displays when media is not stored on server but hash is verified via
 * device attestation. Shows lock icon and messaging about privacy mode
 * trust model. Supports both photo (4:3) and video (16:9) aspect ratios.
 */
export function HashOnlyMediaPlaceholder({
  className = '',
  aspectRatio = '4:3',
}: HashOnlyMediaPlaceholderProps) {
  return (
    <div
      className={`relative w-full ${aspectRatioClasses[aspectRatio]}
                  bg-zinc-100 dark:bg-zinc-800
                  rounded-lg overflow-hidden
                  flex flex-col items-center justify-center px-6 ${className}`}
      role="img"
      aria-label="Hash verified - media not stored"
      data-testid="hash-only-placeholder"
    >
      {/* Lock Icon */}
      <svg
        className="h-12 w-12 sm:h-16 sm:w-16 text-zinc-400 dark:text-zinc-500 mb-4"
        fill="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <path
          fillRule="evenodd"
          d="M12 1.5a5.25 5.25 0 00-5.25 5.25v3a3 3 0 00-3 3v6.75a3 3 0 003 3h10.5a3 3 0 003-3v-6.75a3 3 0 00-3-3v-3c0-2.9-2.35-5.25-5.25-5.25zm3.75 8.25v-3a3.75 3.75 0 10-7.5 0v3h7.5z"
          clipRule="evenodd"
        />
      </svg>

      {/* Heading */}
      <h3 className="text-base sm:text-lg font-semibold text-zinc-900 dark:text-white mb-2">
        Hash Verified
      </h3>

      {/* Primary message */}
      <p className="text-xs sm:text-sm text-zinc-600 dark:text-zinc-400 text-center mb-1">
        Original media not stored on server
      </p>

      {/* Trust model explanation */}
      <p className="text-xs text-zinc-500 dark:text-zinc-500 text-center">
        Authenticity verified via device attestation
      </p>
    </div>
  );
}
