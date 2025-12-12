'use client';

import { useEffect, useRef } from 'react';
import type { Platform, AttestationLevel, PlatformInfo } from '@realitycam/shared';

interface PlatformTooltipProps {
  /** Platform info to display */
  platformInfo: PlatformInfo;
  /** Whether the tooltip is visible */
  isVisible: boolean;
  /** Callback to close the tooltip */
  onClose: () => void;
  /** Additional className */
  className?: string;
}

/**
 * Full platform names for display
 */
const FULL_PLATFORM_NAMES: Record<Platform, string> = {
  ios: 'Apple iOS',
  android: 'Google Android',
};

/**
 * Attestation method explanations
 */
const ATTESTATION_EXPLANATIONS: Record<AttestationLevel, string> = {
  secure_enclave: 'Hardware-backed key stored in dedicated security chip. Highest trust level.',
  strongbox: 'Hardware Security Module. Comparable to iOS Secure Enclave.',
  tee: 'Trusted Execution Environment. Hardware-isolated but less secure than StrongBox.',
  unverified: 'Device attestation could not be verified. Lower trust level.',
};

/**
 * Depth method descriptions
 */
function getDepthDescription(platformInfo: PlatformInfo): string {
  if (!platformInfo.depth_available) {
    return 'No depth analysis available';
  }
  if (platformInfo.depth_method === 'lidar') {
    return platformInfo.has_lidar
      ? 'LiDAR depth sensor available'
      : 'LiDAR depth analysis';
  }
  if (platformInfo.depth_method === 'parallax') {
    return 'Multi-camera parallax depth';
  }
  return 'Depth analysis available';
}

/**
 * PlatformTooltip - Detailed platform information tooltip
 *
 * Shows on click/tap (toggle behavior):
 * - Full platform name
 * - Device model (if available)
 * - Attestation method explanation
 * - LiDAR/depth status
 */
export function PlatformTooltip({
  platformInfo,
  isVisible,
  onClose,
  className = '',
}: PlatformTooltipProps) {
  const tooltipRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!isVisible) return;

    function handleClickOutside(event: MouseEvent | TouchEvent) {
      if (tooltipRef.current && !tooltipRef.current.contains(event.target as Node)) {
        onClose();
      }
    }

    // Small delay to prevent immediate close on the same click that opened it
    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handleClickOutside);
      document.addEventListener('touchstart', handleClickOutside);
    }, 10);

    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('touchstart', handleClickOutside);
    };
  }, [isVisible, onClose]);

  // Close on Escape key
  useEffect(() => {
    if (!isVisible) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        onClose();
      }
    }

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isVisible, onClose]);

  if (!isVisible) return null;

  const { platform, attestation_level, device_model, has_lidar } = platformInfo;
  const fullPlatformName = FULL_PLATFORM_NAMES[platform];
  const attestationExplanation = ATTESTATION_EXPLANATIONS[attestation_level];
  const depthDescription = getDepthDescription(platformInfo);

  return (
    <div
      ref={tooltipRef}
      role="tooltip"
      aria-live="polite"
      className={`
        absolute z-50 left-0 mt-2 w-72 sm:w-80
        bg-white dark:bg-zinc-800
        border border-zinc-200 dark:border-zinc-700
        rounded-lg shadow-lg
        p-4
        animate-in fade-in-0 zoom-in-95 duration-200
        ${className}
      `}
      data-testid="platform-tooltip"
    >
      {/* Close button */}
      <button
        type="button"
        onClick={onClose}
        className="absolute top-2 right-2 p-1 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300"
        aria-label="Close tooltip"
      >
        <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>

      {/* Header */}
      <h4 className="text-sm font-semibold text-zinc-900 dark:text-white pr-6">
        {fullPlatformName}
      </h4>

      {/* Device Model */}
      {device_model && (
        <p className="mt-1 text-sm text-zinc-700 dark:text-zinc-300">
          {device_model}
        </p>
      )}

      {/* Details grid */}
      <dl className="mt-3 space-y-3">
        {/* Attestation Method */}
        <div>
          <dt className="text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wide">
            Attestation Method
          </dt>
          <dd className="mt-1 text-sm text-zinc-700 dark:text-zinc-300">
            {attestationExplanation}
          </dd>
        </div>

        {/* Depth Capability */}
        <div>
          <dt className="text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wide">
            Depth Capability
          </dt>
          <dd className="mt-1 text-sm text-zinc-700 dark:text-zinc-300 flex items-center gap-2">
            {platformInfo.depth_available ? (
              <>
                <svg className="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clipRule="evenodd" />
                </svg>
                <span>{depthDescription}</span>
              </>
            ) : (
              <>
                <svg className="w-4 h-4 text-zinc-400" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clipRule="evenodd" />
                </svg>
                <span>{depthDescription}</span>
              </>
            )}
          </dd>
        </div>

        {/* LiDAR Status (iOS only) */}
        {platform === 'ios' && has_lidar !== undefined && (
          <div>
            <dt className="text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wide">
              LiDAR Sensor
            </dt>
            <dd className="mt-1 text-sm text-zinc-700 dark:text-zinc-300 flex items-center gap-2">
              {has_lidar ? (
                <>
                  <svg className="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clipRule="evenodd" />
                  </svg>
                  <span>Available (Pro model)</span>
                </>
              ) : (
                <>
                  <svg className="w-4 h-4 text-zinc-400" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clipRule="evenodd" />
                  </svg>
                  <span>Not available</span>
                </>
              )}
            </dd>
          </div>
        )}
      </dl>
    </div>
  );
}
