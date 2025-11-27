interface PartialVideoBannerProps {
  verifiedFrames: number;
  totalFrames: number;
  verifiedDurationMs: number;
  totalDurationMs: number;
  checkpointIndex?: number;
  className?: string;
}

/**
 * Formats duration in milliseconds to a readable string
 */
function formatDuration(ms: number): string {
  const seconds = ms / 1000;
  if (seconds < 60) {
    return `${seconds.toFixed(1)}s`;
  }
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  return `${minutes}m ${remainingSeconds.toFixed(0)}s`;
}

/**
 * Maps checkpoint index to approximate time
 * Checkpoints occur at 5s intervals (0=5s, 1=10s, 2=15s)
 */
function getCheckpointTime(index: number): string {
  const seconds = (index + 1) * 5;
  return `${seconds}s`;
}

/**
 * PartialVideoBanner - Displays information about partial video verification
 *
 * Shown when a video recording was interrupted and only a portion
 * was verified via checkpoint attestation. Uses info styling (blue)
 * since partial verification is still valid evidence.
 */
export function PartialVideoBanner({
  verifiedFrames,
  totalFrames,
  verifiedDurationMs,
  totalDurationMs,
  checkpointIndex,
  className = '',
}: PartialVideoBannerProps) {
  const verifiedDuration = formatDuration(verifiedDurationMs);
  const totalDuration = formatDuration(totalDurationMs);
  const percentVerified = Math.round((verifiedFrames / totalFrames) * 100);

  return (
    <div
      className={`rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/30 p-4 ${className}`}
      data-testid="partial-video-banner"
      role="status"
    >
      <div className="flex items-start gap-3">
        {/* Info Icon */}
        <div className="flex-shrink-0">
          <svg
            className="h-5 w-5 text-blue-500 dark:text-blue-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-medium text-blue-800 dark:text-blue-300">
            Partial Verification
          </h4>
          <p className="mt-1 text-sm text-blue-700 dark:text-blue-400">
            {verifiedDuration} of {totalDuration} verified ({percentVerified}% of video)
          </p>

          {/* Details */}
          <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-blue-600 dark:text-blue-400">
            <span>
              {verifiedFrames.toLocaleString()} / {totalFrames.toLocaleString()} frames
            </span>
            {checkpointIndex !== undefined && (
              <span>
                Checkpoint {checkpointIndex + 1} ({getCheckpointTime(checkpointIndex)})
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
