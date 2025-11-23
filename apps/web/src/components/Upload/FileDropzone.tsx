'use client';

import { useState, useCallback, useRef } from 'react';
import { apiClient, type FileVerificationResponse, type ConfidenceLevel } from '@/lib/api';

// ============================================================================
// Types
// ============================================================================

type UploadState = 'idle' | 'dragging' | 'uploading' | 'success' | 'error';

interface FileDropzoneProps {
  onVerificationComplete?: (result: FileVerificationResponse) => void;
  className?: string;
}

// ============================================================================
// Constants
// ============================================================================

const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20MB
const ACCEPTED_TYPES = ['image/jpeg', 'image/png', 'image/heic', 'image/heif'];

// ============================================================================
// Component
// ============================================================================

/**
 * FileDropzone - Drag-and-drop file upload for verification
 *
 * Accepts JPEG, PNG, HEIC files up to 20MB.
 * Uploads file to backend for hash verification.
 */
export function FileDropzone({ onVerificationComplete, className = '' }: FileDropzoneProps) {
  const [state, setState] = useState<UploadState>('idle');
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<FileVerificationResponse | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const validateFile = (file: File): string | null => {
    if (!ACCEPTED_TYPES.includes(file.type)) {
      return 'Invalid file type. Please upload a JPEG, PNG, or HEIC image.';
    }
    if (file.size > MAX_FILE_SIZE) {
      return `File too large. Maximum size is ${MAX_FILE_SIZE / 1024 / 1024}MB.`;
    }
    return null;
  };

  const handleFile = useCallback(async (file: File) => {
    const validationError = validateFile(file);
    if (validationError) {
      setError(validationError);
      setState('error');
      return;
    }

    setFileName(file.name);
    setError(null);
    setState('uploading');

    try {
      const response = await apiClient.verifyFile(file);
      setResult(response);
      setState('success');
      onVerificationComplete?.(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Verification failed');
      setState('error');
    }
  }, [onVerificationComplete]);

  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setState('idle');

    const file = e.dataTransfer.files[0];
    if (file) {
      handleFile(file);
    }
  }, [handleFile]);

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setState('dragging');
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setState('idle');
  }, []);

  const handleFileInput = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      handleFile(file);
    }
  }, [handleFile]);

  const handleClick = () => {
    inputRef.current?.click();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      inputRef.current?.click();
    }
  };

  const handleReset = useCallback(() => {
    setState('idle');
    setError(null);
    setResult(null);
    setFileName(null);
    if (inputRef.current) {
      inputRef.current.value = '';
    }
  }, []);

  // Render result if verification complete
  if (state === 'success' && result) {
    return (
      <VerificationResult
        result={result}
        fileName={fileName}
        onReset={handleReset}
        className={className}
      />
    );
  }

  return (
    <div className={`w-full ${className}`}>
      <div
        onClick={handleClick}
        onKeyDown={handleKeyDown}
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        role="button"
        tabIndex={0}
        aria-label="Upload file for verification"
        className={`
          relative rounded-xl border-2 border-dashed transition-colors cursor-pointer
          focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-black
          ${state === 'dragging'
            ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/20'
            : state === 'error'
            ? 'border-red-300 bg-red-50 dark:border-red-700 dark:bg-red-900/20'
            : 'border-zinc-300 dark:border-zinc-600 hover:border-blue-500 dark:hover:border-blue-400 hover:bg-zinc-50 dark:hover:bg-zinc-900/50'
          }
        `}
      >
        <div className="flex flex-col items-center justify-center gap-4 p-8 sm:p-12">
          <input
            ref={inputRef}
            type="file"
            accept={ACCEPTED_TYPES.join(',')}
            onChange={handleFileInput}
            className="hidden"
            disabled={state === 'uploading'}
            aria-hidden="true"
          />

          {state === 'uploading' ? (
            <>
              <div className="h-12 w-12 sm:h-16 sm:w-16 rounded-full border-4 border-zinc-200 border-t-blue-500 animate-spin" />
              <div className="text-center">
                <p className="text-base sm:text-lg font-medium text-zinc-700 dark:text-zinc-300">
                  Verifying...
                </p>
                <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
                  {fileName}
                </p>
              </div>
            </>
          ) : (
            <>
              <div className={`
                h-12 w-12 sm:h-16 sm:w-16 rounded-full flex items-center justify-center
                ${state === 'error'
                  ? 'bg-red-100 dark:bg-red-900/40'
                  : 'bg-zinc-100 dark:bg-zinc-800'
                }
              `}>
                {state === 'error' ? (
                  <svg className="h-6 w-6 sm:h-8 sm:w-8 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                ) : (
                  <svg className="h-6 w-6 sm:h-8 sm:w-8 text-zinc-400 dark:text-zinc-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
                  </svg>
                )}
              </div>

              <div className="text-center">
                {state === 'error' ? (
                  <>
                    <p className="text-base sm:text-lg font-medium text-red-600 dark:text-red-400">
                      {error}
                    </p>
                    <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
                      Click or drop to try again
                    </p>
                  </>
                ) : (
                  <>
                    <p className="text-base sm:text-lg font-medium text-zinc-700 dark:text-zinc-300">
                      {state === 'dragging' ? 'Drop to verify' : 'Drop a file here or click to upload'}
                    </p>
                    <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
                      Supports JPEG, PNG, HEIC (up to 20MB)
                    </p>
                  </>
                )}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Verification Result Component
// ============================================================================

interface VerificationResultProps {
  result: FileVerificationResponse;
  fileName: string | null;
  onReset: () => void;
  className?: string;
}

function VerificationResult({ result, fileName, onReset, className = '' }: VerificationResultProps) {
  const { status, confidence_level, verification_url, manifest_info, note, file_hash } = result.data;

  return (
    <div className={`w-full rounded-xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 overflow-hidden ${className}`}>
      {/* Status Header */}
      <div className={`px-6 py-4 ${getStatusBackground(status)}`}>
        <div className="flex items-center gap-3">
          <StatusIcon status={status} />
          <div>
            <h3 className="text-lg font-semibold text-zinc-900 dark:text-white">
              {getStatusTitle(status)}
            </h3>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              {fileName}
            </p>
          </div>
        </div>
      </div>

      {/* Result Details */}
      <div className="px-6 py-4 space-y-4">
        {/* Confidence Level (if verified) */}
        {status === 'verified' && confidence_level && (
          <div className="flex items-center justify-between">
            <span className="text-sm text-zinc-600 dark:text-zinc-400">Confidence</span>
            <span className={`px-2 py-1 rounded text-xs font-semibold uppercase ${getConfidenceBadgeColor(confidence_level)}`}>
              {confidence_level}
            </span>
          </div>
        )}

        {/* C2PA Info (if c2pa_only) */}
        {status === 'c2pa_only' && manifest_info && (
          <div className="space-y-2">
            <p className="text-xs text-zinc-500 dark:text-zinc-400 uppercase tracking-wide">
              Content Credentials Found
            </p>
            <div className="bg-zinc-50 dark:bg-zinc-800 rounded-lg p-3 text-sm">
              <p className="text-zinc-700 dark:text-zinc-300">
                <span className="text-zinc-500">Generator:</span> {manifest_info.claim_generator}
              </p>
              {manifest_info.created_at && (
                <p className="text-zinc-700 dark:text-zinc-300 mt-1">
                  <span className="text-zinc-500">Created:</span> {manifest_info.created_at}
                </p>
              )}
            </div>
          </div>
        )}

        {/* Note */}
        {note && (
          <p className="text-sm text-zinc-600 dark:text-zinc-400 bg-zinc-50 dark:bg-zinc-800 rounded-lg p-3">
            {note}
          </p>
        )}

        {/* File Hash */}
        <div>
          <p className="text-xs text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-1">
            File Hash (SHA-256)
          </p>
          <code className="block text-xs text-zinc-600 dark:text-zinc-400 bg-zinc-50 dark:bg-zinc-800 rounded p-2 font-mono break-all">
            {file_hash}
          </code>
        </div>

        {/* Actions */}
        <div className="flex items-center gap-3 pt-2">
          {status === 'verified' && verification_url && (
            <a
              href={verification_url}
              className="flex-1 px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg text-center hover:bg-blue-700 transition-colors"
            >
              View Full Evidence
            </a>
          )}
          <button
            onClick={onReset}
            className={`${status === 'verified' ? '' : 'flex-1'} px-4 py-2 border border-zinc-300 dark:border-zinc-600 text-zinc-700 dark:text-zinc-300 text-sm font-medium rounded-lg hover:bg-zinc-50 dark:hover:bg-zinc-800 transition-colors`}
          >
            Verify Another
          </button>
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Helper Components
// ============================================================================

function StatusIcon({ status }: { status: string }) {
  const baseClasses = 'h-10 w-10 rounded-full flex items-center justify-center';

  if (status === 'verified') {
    return (
      <div className={`${baseClasses} bg-green-100 dark:bg-green-900/40`}>
        <svg className="h-6 w-6 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
        </svg>
      </div>
    );
  }

  if (status === 'c2pa_only') {
    return (
      <div className={`${baseClasses} bg-yellow-100 dark:bg-yellow-900/40`}>
        <svg className="h-6 w-6 text-yellow-600 dark:text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </div>
    );
  }

  return (
    <div className={`${baseClasses} bg-zinc-100 dark:bg-zinc-800`}>
      <svg className="h-6 w-6 text-zinc-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    </div>
  );
}

// ============================================================================
// Helper Functions
// ============================================================================

function getStatusBackground(status: string): string {
  switch (status) {
    case 'verified':
      return 'bg-green-50 dark:bg-green-900/20 border-b border-green-100 dark:border-green-900';
    case 'c2pa_only':
      return 'bg-yellow-50 dark:bg-yellow-900/20 border-b border-yellow-100 dark:border-yellow-900';
    default:
      return 'bg-zinc-50 dark:bg-zinc-800 border-b border-zinc-100 dark:border-zinc-700';
  }
}

function getStatusTitle(status: string): string {
  switch (status) {
    case 'verified':
      return 'Photo Verified';
    case 'c2pa_only':
      return 'Content Credentials Found';
    default:
      return 'No Record Found';
  }
}

function getConfidenceBadgeColor(level: ConfidenceLevel): string {
  switch (level) {
    case 'high':
      return 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-400';
    case 'medium':
      return 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-400';
    case 'low':
      return 'bg-orange-100 text-orange-700 dark:bg-orange-900/40 dark:text-orange-400';
    case 'suspicious':
      return 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-400';
    default:
      return 'bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-400';
  }
}
