/**
 * Shared status mapping utilities
 *
 * Centralizes status-related helper functions used across components
 * to avoid duplication and ensure consistency.
 */

import type { ConfidenceLevel, EvidenceStatus } from '@realitycam/shared';

// ============================================================================
// Evidence Status Mapping
// ============================================================================

/**
 * Maps various status strings to standardized EvidenceStatus
 * Handles legacy status names (verified, failed) and current names (pass, fail)
 */
export function mapToEvidenceStatus(status: string | undefined): EvidenceStatus {
  if (status === 'pass' || status === 'verified') return 'pass';
  if (status === 'fail' || status === 'failed') return 'fail';
  return 'unavailable';
}

/**
 * Get human-readable text for evidence status
 */
export function getStatusText(status: EvidenceStatus | 'pending'): string {
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

// ============================================================================
// Verification Status (File Upload)
// ============================================================================

export type VerificationDisplayStatus = 'verified' | 'c2pa_only' | 'no_record';

/**
 * Get background color classes for verification status
 */
export function getVerificationBackground(status: VerificationDisplayStatus): string {
  switch (status) {
    case 'verified':
      return 'bg-green-50 dark:bg-green-900/20 border-b border-green-100 dark:border-green-900';
    case 'c2pa_only':
      return 'bg-yellow-50 dark:bg-yellow-900/20 border-b border-yellow-100 dark:border-yellow-900';
    default:
      return 'bg-zinc-50 dark:bg-zinc-800 border-b border-zinc-100 dark:border-zinc-700';
  }
}

/**
 * Get title text for verification status
 */
export function getVerificationTitle(status: VerificationDisplayStatus): string {
  switch (status) {
    case 'verified':
      return 'Photo Verified';
    case 'c2pa_only':
      return 'Content Credentials Found';
    default:
      return 'No Record Found';
  }
}

// ============================================================================
// Confidence Level Styling
// ============================================================================

/**
 * Get badge color classes for confidence level
 */
export function getConfidenceBadgeColor(level: ConfidenceLevel): string {
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

/**
 * Get full styling classes for confidence level (for larger badges)
 */
export function getConfidenceFullColor(level: ConfidenceLevel): string {
  switch (level) {
    case 'high':
      return 'text-green-600 bg-green-50 border-green-200 dark:text-green-400 dark:bg-green-900/20 dark:border-green-800';
    case 'medium':
      return 'text-yellow-600 bg-yellow-50 border-yellow-200 dark:text-yellow-400 dark:bg-yellow-900/20 dark:border-yellow-800';
    case 'low':
      return 'text-orange-600 bg-orange-50 border-orange-200 dark:text-orange-400 dark:bg-orange-900/20 dark:border-orange-800';
    case 'suspicious':
      return 'text-red-600 bg-red-50 border-red-200 dark:text-red-400 dark:bg-red-900/20 dark:border-red-800';
    default:
      return 'text-zinc-600 bg-zinc-50 border-zinc-200 dark:text-zinc-400 dark:bg-zinc-900/20 dark:border-zinc-800';
  }
}

/**
 * Get label text for confidence level
 */
export function getConfidenceLabel(level: ConfidenceLevel): string {
  switch (level) {
    case 'high':
      return 'HIGH CONFIDENCE';
    case 'medium':
      return 'MEDIUM CONFIDENCE';
    case 'low':
      return 'LOW CONFIDENCE';
    case 'suspicious':
      return 'SUSPICIOUS';
    default:
      return 'UNKNOWN';
  }
}
