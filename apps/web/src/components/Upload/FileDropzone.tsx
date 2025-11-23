'use client';

import { useRef } from 'react';

/**
 * FileDropzone - File upload placeholder component
 *
 * Visual placeholder for file upload functionality. Shows a dashed border dropzone
 * with upload icon and instructions. Click opens file picker but doesn't process files.
 */
export function FileDropzone() {
  const inputRef = useRef<HTMLInputElement>(null);

  const handleClick = () => {
    inputRef.current?.click();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      inputRef.current?.click();
    }
  };

  return (
    <div
      onClick={handleClick}
      onKeyDown={handleKeyDown}
      role="button"
      tabIndex={0}
      aria-label="Upload file"
      className="w-full border-2 border-dashed border-zinc-300 dark:border-zinc-600
                 rounded-xl p-8 sm:p-12 text-center
                 hover:border-blue-500 dark:hover:border-blue-400
                 hover:bg-zinc-50 dark:hover:bg-zinc-900/50
                 transition-colors cursor-pointer
                 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2
                 dark:focus:ring-offset-black"
    >
      {/* Upload Icon - Cloud with arrow */}
      <svg
        className="mx-auto h-12 w-12 sm:h-16 sm:w-16 text-zinc-400 dark:text-zinc-500"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
        />
      </svg>

      <p className="mt-4 text-base sm:text-lg font-medium text-zinc-700 dark:text-zinc-300">
        Drop a file here or click to upload
      </p>

      <p className="mt-2 text-sm text-zinc-500 dark:text-zinc-400">
        Supports JPEG, PNG, HEIC
      </p>

      {/* Hidden file input for click-to-upload */}
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/heic"
        className="hidden"
        aria-hidden="true"
      />
    </div>
  );
}
