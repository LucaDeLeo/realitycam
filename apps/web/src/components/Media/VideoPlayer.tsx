'use client';

import { useState, useRef } from 'react';

interface VideoPlayerProps {
  src: string;
  poster?: string;
  className?: string;
  aspectRatio?: '16:9' | '4:3';
}

/**
 * VideoPlayer - HTML5 video player for video verification
 *
 * Features:
 * - Native HTML5 video controls (play, pause, scrub, volume)
 * - Responsive sizing with preserved aspect ratio
 * - Loading state indicator
 * - Error handling with retry
 * - Mobile-optimized with playsinline attribute
 */
export function VideoPlayer({
  src,
  poster,
  className = '',
  aspectRatio = '16:9',
}: VideoPlayerProps) {
  const [isLoading, setIsLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);

  const aspectClass = aspectRatio === '16:9' ? 'aspect-video' : 'aspect-[4/3]';

  const handleLoadedData = () => {
    setIsLoading(false);
    setHasError(false);
  };

  const handleError = () => {
    setIsLoading(false);
    setHasError(true);
  };

  const handleRetry = () => {
    setIsLoading(true);
    setHasError(false);
    if (videoRef.current) {
      videoRef.current.load();
    }
  };

  return (
    <div
      className={`relative w-full ${aspectClass} bg-zinc-100 dark:bg-zinc-800 rounded-lg overflow-hidden ${className}`}
      data-testid="video-player"
    >
      {/* Loading Spinner */}
      {isLoading && !hasError && (
        <div className="absolute inset-0 flex items-center justify-center z-10">
          <div className="flex flex-col items-center gap-2">
            <svg
              className="animate-spin h-8 w-8 text-zinc-400"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              aria-hidden="true"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            <span className="text-sm text-zinc-500 dark:text-zinc-400">
              Loading video...
            </span>
          </div>
        </div>
      )}

      {/* Error State */}
      {hasError && (
        <div className="absolute inset-0 flex items-center justify-center z-10 bg-zinc-100 dark:bg-zinc-800">
          <div className="flex flex-col items-center gap-3 px-4 text-center">
            <svg
              className="h-10 w-10 text-zinc-400"
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
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Unable to load video
            </p>
            <button
              type="button"
              onClick={handleRetry}
              className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
            >
              Retry
            </button>
          </div>
        </div>
      )}

      {/* Video Element */}
      <video
        ref={videoRef}
        src={src}
        poster={poster}
        controls
        playsInline
        preload="metadata"
        onLoadedData={handleLoadedData}
        onError={handleError}
        className={`w-full h-full object-contain ${isLoading || hasError ? 'opacity-0' : 'opacity-100'} transition-opacity duration-200`}
        aria-label="Verified video capture"
      >
        <track kind="captions" src="" label="No captions available" />
        Your browser does not support the video tag.
      </video>
    </div>
  );
}

/**
 * VideoPlaceholder - Placeholder when video is not available
 */
export function VideoPlaceholder({
  aspectRatio = '16:9',
  message = 'Video not available',
  className = '',
}: {
  aspectRatio?: '16:9' | '4:3';
  message?: string;
  className?: string;
}) {
  const aspectClass = aspectRatio === '16:9' ? 'aspect-video' : 'aspect-[4/3]';

  return (
    <div
      className={`relative w-full ${aspectClass} bg-zinc-100 dark:bg-zinc-800 rounded-lg flex items-center justify-center ${className}`}
      data-testid="video-placeholder"
    >
      <div className="flex flex-col items-center gap-2 text-zinc-400">
        <svg
          className="h-12 w-12"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={1.5}
            d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
          />
        </svg>
        <span className="text-sm">{message}</span>
      </div>
    </div>
  );
}
