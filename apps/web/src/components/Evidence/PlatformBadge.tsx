'use client';

import { useState, useCallback } from 'react';
import type { Platform, AttestationLevel, PlatformInfo } from '@realitycam/shared';
import { PlatformIcon } from './PlatformIcon';
import { getAttestationConfig } from './AttestationLevelBadge';
import { PlatformTooltip } from './PlatformTooltip';

type BadgeVariant = 'full' | 'compact';

interface PlatformBadgeProps {
  /** Platform info to display */
  platformInfo: PlatformInfo;
  /** Badge variant: 'full' for desktop, 'compact' for mobile/header */
  variant?: BadgeVariant;
  /** Whether to show tooltip on click */
  showTooltip?: boolean;
  /** Additional className */
  className?: string;
}

/**
 * Platform display configuration
 */
const PLATFORM_DISPLAY: Record<Platform, string> = {
  ios: 'iOS',
  android: 'Android',
};

/**
 * Get platform display name
 */
export function getPlatformDisplayName(platform: Platform): string {
  return PLATFORM_DISPLAY[platform] || platform.toUpperCase();
}

/**
 * Get badge styling based on attestation level
 */
function getBadgeColors(level: AttestationLevel): string {
  const config = getAttestationConfig(level);
  return config.colorClasses;
}

/**
 * PlatformBadge - Combined platform + attestation badge component
 *
 * Displays platform icon and name with attestation level in a badge format.
 * Supports two variants:
 * - 'full': Shows "[Icon] iOS - Secure Enclave" (for desktop/main display)
 * - 'compact': Shows "[Icon] iOS" only (for headers/mobile)
 *
 * Optionally shows a tooltip with detailed platform info on click.
 */
export function PlatformBadge({
  platformInfo,
  variant = 'full',
  showTooltip = true,
  className = '',
}: PlatformBadgeProps) {
  const [isTooltipVisible, setIsTooltipVisible] = useState(false);

  const handleClick = useCallback(() => {
    if (showTooltip) {
      setIsTooltipVisible(prev => !prev);
    }
  }, [showTooltip]);

  const handleCloseTooltip = useCallback(() => {
    setIsTooltipVisible(false);
  }, []);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleClick();
    }
    if (e.key === 'Escape' && isTooltipVisible) {
      handleCloseTooltip();
    }
  };

  const { platform, attestation_level } = platformInfo;
  const platformName = getPlatformDisplayName(platform);
  const attestationConfig = getAttestationConfig(attestation_level);
  const badgeColors = getBadgeColors(attestation_level);

  // Build aria-label for accessibility
  const ariaLabel = variant === 'full'
    ? `Platform: ${platformName} with ${attestationConfig.label} attestation`
    : `Platform: ${platformName}`;

  return (
    <div className={`relative inline-block ${className}`}>
      <button
        type="button"
        onClick={handleClick}
        onKeyDown={handleKeyDown}
        className={`
          inline-flex items-center gap-1.5 px-3 py-1 rounded-full
          text-xs sm:text-sm font-medium
          transition-colors cursor-pointer
          focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500
          ${badgeColors}
          ${showTooltip ? 'hover:opacity-90' : ''}
        `}
        data-testid="platform-badge"
        aria-label={ariaLabel}
        aria-expanded={showTooltip ? isTooltipVisible : undefined}
        aria-haspopup={showTooltip ? 'dialog' : undefined}
      >
        <PlatformIcon platform={platform} size="sm" />
        <span>{platformName}</span>
        {variant === 'full' && (
          <>
            <span className="opacity-50">-</span>
            <span>{attestationConfig.label}</span>
          </>
        )}
      </button>

      {/* Tooltip */}
      {showTooltip && (
        <PlatformTooltip
          platformInfo={platformInfo}
          isVisible={isTooltipVisible}
          onClose={handleCloseTooltip}
        />
      )}
    </div>
  );
}

/**
 * CompactPlatformBadge - Simplified badge for headers and tight spaces
 *
 * Shows only platform icon and name without attestation level.
 * No tooltip - click behavior disabled.
 */
export function CompactPlatformBadge({
  platform,
  className = '',
}: {
  platform: Platform;
  className?: string;
}) {
  const platformName = getPlatformDisplayName(platform);

  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium
        bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 ${className}`}
      data-testid="compact-platform-badge"
      aria-label={`Platform: ${platformName}`}
    >
      <PlatformIcon platform={platform} size="sm" />
      <span>{platformName}</span>
    </span>
  );
}
