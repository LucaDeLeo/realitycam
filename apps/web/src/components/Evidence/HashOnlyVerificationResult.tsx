'use client';

import { useState } from 'react';
import Link from 'next/link';
import type { ConfidenceLevel, Evidence, MetadataFlags } from '@realitycam/shared';
import { ConfidenceBadge } from './ConfidenceBadge';
import { PrivacyModeBadge } from './PrivacyModeBadge';

interface HashOnlyVerificationResultProps {
  captureId: string;
  mediaHash: string;
  confidenceLevel: ConfidenceLevel;
  mediaType: 'photo' | 'video';
  evidence: Evidence;
  capturedAt: string;
  metadataFlags?: MetadataFlags;
}

/**
 * HashOnlyVerificationResult - Display hash-only file verification results
 *
 * Shows verification results for hash-only captures where media is not stored
 * on the server. Displays Privacy Mode badge, hash value, evidence summary,
 * and metadata per privacy flags.
 */
export function HashOnlyVerificationResult({
  captureId,
  mediaHash,
  confidenceLevel,
  mediaType,
  evidence,
  capturedAt,
  metadataFlags,
}: HashOnlyVerificationResultProps) {
  const [hashCopied, setHashCopied] = useState(false);

  const copyHashToClipboard = () => {
    navigator.clipboard.writeText(mediaHash);
    setHashCopied(true);
    setTimeout(() => setHashCopied(false), 2000);
  };

  // Format timestamp based on metadata flags
  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    if (!metadataFlags?.timestamp_included || metadataFlags.timestamp_level === 'none') {
      return 'Not included';
    }
    if (metadataFlags.timestamp_level === 'day_only') {
      return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      });
    }
    // exact
    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      timeZoneName: 'short',
    });
  };

  // Format location based on metadata flags
  const formatLocation = () => {
    if (!metadataFlags?.location_included || metadataFlags.location_level === 'none') {
      return 'Not included';
    }
    if (metadataFlags.location_level === 'coarse') {
      return evidence.metadata.location_coarse || 'City/region level';
    }
    // precise - but for hash-only, we shouldn't have precise
    return evidence.metadata.location_coarse || 'Available';
  };

  // Format device info based on metadata flags
  const formatDeviceInfo = () => {
    if (!metadataFlags?.device_info_included || metadataFlags.device_info_level === 'none') {
      return 'Not included';
    }
    if (metadataFlags.device_info_level === 'model_only') {
      return evidence.hardware_attestation.device_model;
    }
    // full
    return `${evidence.hardware_attestation.device_model} (Secure Enclave)`;
  };

  return (
    <div className="max-w-3xl mx-auto p-6" data-testid="hash-only-verification-result">
      {/* Header */}
      <div className="flex items-start gap-4 mb-6">
        <div className="flex-shrink-0">
          <svg
            className="h-12 w-12 text-green-600"
            fill="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path
              fillRule="evenodd"
              d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12zm13.36-1.814a.75.75 0 10-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 00-1.06 1.06l2.25 2.25a.75.75 0 001.14-.094l3.75-5.25z"
              clipRule="evenodd"
            />
          </svg>
        </div>
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-zinc-900 dark:text-zinc-100 mb-1">
            File Verified - Hash Match
          </h1>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            This file matches a registered capture from {mediaType === 'video' ? 'a video' : 'a photo'} taken with rial.
          </p>
        </div>
      </div>

      {/* Badges */}
      <div className="flex flex-wrap gap-2 mb-6">
        <ConfidenceBadge level={confidenceLevel} />
        <PrivacyModeBadge />
        {mediaType === 'video' && (
          <span
            className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs sm:text-sm font-semibold
                       bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300"
            data-testid="video-badge"
          >
            <svg className="h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M4.5 5.25a.75.75 0 00-.75.75v12c0 .414.336.75.75.75h15a.75.75 0 00.75-.75V6a.75.75 0 00-.75-.75h-15zm7.03 3.97a.75.75 0 011.06 0l3 3a.75.75 0 010 1.06l-3 3a.75.75 0 01-1.06-1.06l1.72-1.72H8.25a.75.75 0 010-1.5h4.94l-1.72-1.72a.75.75 0 010-1.06z" />
            </svg>
            Video Hash Verified
          </span>
        )}
      </div>

      {/* Hash Display */}
      <div className="bg-zinc-50 dark:bg-zinc-900 rounded-lg p-4 mb-6">
        <div className="text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-2">
          File Hash (SHA-256)
        </div>
        <div className="font-mono text-xs break-all text-zinc-900 dark:text-zinc-100 mb-3">
          {mediaHash}
        </div>
        <button
          onClick={copyHashToClipboard}
          className="text-sm text-blue-600 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300 font-medium transition-colors"
          data-testid="copy-hash-button"
        >
          {hashCopied ? '✓ Copied!' : 'Copy hash'}
        </button>
      </div>

      {/* Trust Model Explanation */}
      <div className="bg-purple-50 dark:bg-purple-900/20 rounded-lg p-4 mb-6">
        <div className="flex items-start gap-3">
          <svg
            className="h-5 w-5 text-purple-600 dark:text-purple-400 flex-shrink-0 mt-0.5"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              fillRule="evenodd"
              d="M12.516 2.17a.75.75 0 00-1.032 0 11.209 11.209 0 01-7.877 3.08.75.75 0 00-.722.515A12.74 12.74 0 002.25 9.75c0 5.942 4.064 10.933 9.563 12.348a.749.749 0 00.374 0c5.499-1.415 9.563-6.406 9.563-12.348 0-1.39-.223-2.73-.635-3.985a.75.75 0 00-.722-.516l-.143.001c-2.996 0-5.717-1.17-7.734-3.08zm3.094 8.016a.75.75 0 10-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 00-1.06 1.06l2.25 2.25a.75.75 0 001.14-.094l3.75-5.25z"
              clipRule="evenodd"
            />
          </svg>
          <div>
            <div className="font-semibold text-purple-900 dark:text-purple-100 mb-1">
              Privacy Mode Capture
            </div>
            <p className="text-sm text-purple-800 dark:text-purple-200">
              Original media not stored on server. Authenticity verified via device attestation
              and client-side depth analysis. Only the file hash and evidence metadata were
              uploaded.
            </p>
          </div>
        </div>
      </div>

      {/* Evidence Summary */}
      <div className="bg-white dark:bg-zinc-800 rounded-lg border border-zinc-200 dark:border-zinc-700 p-6 mb-6">
        <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100 mb-4">
          Evidence Summary
        </h2>

        <div className="space-y-4">
          {/* Hardware Attestation */}
          <div>
            <div className="text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-1">
              Hardware Attestation (Device)
            </div>
            <div className="flex items-center gap-2">
              {evidence.hardware_attestation.status === 'pass' ? (
                <span className="text-green-600 dark:text-green-400 text-sm">✓ Verified</span>
              ) : (
                <span className="text-red-600 dark:text-red-400 text-sm">✗ Failed</span>
              )}
              <span className="text-xs text-zinc-500 dark:text-zinc-400">
                {evidence.hardware_attestation.device_model}
              </span>
            </div>
          </div>

          {/* Depth Analysis */}
          <div>
            <div className="text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-1">
              LiDAR Depth Analysis (Device)
            </div>
            <div className="flex items-center gap-2">
              {evidence.depth_analysis.status === 'pass' ? (
                <span className="text-green-600 dark:text-green-400 text-sm">✓ Pass</span>
              ) : (
                <span className="text-red-600 dark:text-red-400 text-sm">✗ Fail</span>
              )}
              <span className="text-xs text-zinc-500 dark:text-zinc-400">
                {evidence.depth_analysis.is_likely_real_scene ? 'Likely real scene' : 'Suspicious'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Capture Information */}
      {metadataFlags && (
        <div className="bg-white dark:bg-zinc-800 rounded-lg border border-zinc-200 dark:border-zinc-700 p-6 mb-6">
          <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100 mb-4">
            Capture Information
          </h2>

          <div className="space-y-3 text-sm">
            <div className="flex justify-between items-center">
              <span className="text-zinc-600 dark:text-zinc-400">Captured At:</span>
              <span className="text-zinc-900 dark:text-zinc-100 font-medium">
                {formatTimestamp(capturedAt)}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-zinc-600 dark:text-zinc-400">Location:</span>
              <span className="text-zinc-900 dark:text-zinc-100 font-medium">
                {formatLocation()}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-zinc-600 dark:text-zinc-400">Device:</span>
              <span className="text-zinc-900 dark:text-zinc-100 font-medium">
                {formatDeviceInfo()}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex flex-wrap gap-3">
        <Link
          href={`/verify/${captureId}`}
          className="inline-flex items-center justify-center px-4 py-2 rounded-lg
                     bg-blue-600 text-white font-medium hover:bg-blue-700
                     dark:bg-blue-500 dark:hover:bg-blue-600 transition-colors"
        >
          View Full Verification Page
        </Link>
        <button
          onClick={() => window.print()}
          className="inline-flex items-center justify-center px-4 py-2 rounded-lg
                     bg-zinc-100 text-zinc-700 font-medium hover:bg-zinc-200
                     dark:bg-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-600 transition-colors"
        >
          Print Verification
        </button>
      </div>
    </div>
  );
}
