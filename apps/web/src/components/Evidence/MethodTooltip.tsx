'use client';

import { useEffect, useRef } from 'react';
import type {
  DetectionMethodResult,
  LidarDepthDetails,
  MoireDetectionResult,
  TextureClassificationResult,
  ArtifactAnalysisResult,
} from '@realitycam/shared';
import { getMethodDisplayName } from './MethodScoreBar';

/** Method descriptions for the tooltip */
const METHOD_DESCRIPTIONS: Record<string, string> = {
  lidar_depth: 'Analyzes LiDAR depth data for 3D scene authenticity. High variance and multiple depth layers indicate real scenes.',
  moire: 'Detects screen patterns (moire) that indicate photo-of-screen recapture. No detection is good.',
  texture: 'Classifies surface textures to identify screens, printed paper, or real-world materials.',
  artifacts: 'Detects display artifacts like PWM flicker, specular reflections, and halftone printing patterns.',
  supporting: 'Aggregated signal from multiple supporting detection methods.',
};

interface MethodTooltipProps {
  /** Method key */
  methodKey: string;
  /** Method result data */
  methodResult: DetectionMethodResult;
  /** Additional method-specific details */
  methodDetails?: {
    moire?: MoireDetectionResult;
    texture?: TextureClassificationResult;
    artifacts?: ArtifactAnalysisResult;
    /** LiDAR-specific details (depth_variance, depth_layers, edge_coherence) */
    lidar?: LidarDepthDetails;
  };
  /** Whether the tooltip is visible */
  isVisible: boolean;
  /** Callback to close the tooltip */
  onClose: () => void;
  /** Additional className */
  className?: string;
}

/**
 * Format a score as a decimal with 2 places
 */
function formatRawScore(score: number | null): string {
  if (score === null) return 'N/A';
  return score.toFixed(2);
}

/**
 * Format contribution as percentage
 */
function formatContribution(contribution: number): string {
  return `${(contribution * 100).toFixed(1)}%`;
}

/**
 * Render method-specific details
 */
function MethodSpecificDetails({
  methodKey,
  methodDetails,
}: {
  methodKey: string;
  methodDetails?: MethodTooltipProps['methodDetails'];
}) {
  if (!methodDetails) return null;

  // LiDAR-specific details
  if (methodKey === 'lidar_depth' && methodDetails.lidar) {
    const { depth_variance, depth_layers, edge_coherence } = methodDetails.lidar;
    return (
      <div className="mt-2 pt-2 border-t border-zinc-200 dark:border-zinc-700">
        <p className="text-xs font-medium text-zinc-700 dark:text-zinc-300 mb-1">
          LiDAR Metrics
        </p>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
          {depth_variance !== undefined && (
            <>
              <dt className="text-zinc-500 dark:text-zinc-400">Depth Variance</dt>
              <dd className="text-zinc-700 dark:text-zinc-300">{depth_variance.toFixed(2)}</dd>
            </>
          )}
          {depth_layers !== undefined && (
            <>
              <dt className="text-zinc-500 dark:text-zinc-400">Depth Layers</dt>
              <dd className="text-zinc-700 dark:text-zinc-300">{depth_layers}</dd>
            </>
          )}
          {edge_coherence !== undefined && (
            <>
              <dt className="text-zinc-500 dark:text-zinc-400">Edge Coherence</dt>
              <dd className="text-zinc-700 dark:text-zinc-300">{(edge_coherence * 100).toFixed(0)}%</dd>
            </>
          )}
        </dl>
      </div>
    );
  }

  // Moire-specific details
  if (methodKey === 'moire' && methodDetails.moire) {
    const { detected, screen_type } = methodDetails.moire;
    return (
      <div className="mt-2 pt-2 border-t border-zinc-200 dark:border-zinc-700">
        <p className="text-xs font-medium text-zinc-700 dark:text-zinc-300 mb-1">
          Moire Analysis
        </p>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
          <dt className="text-zinc-500 dark:text-zinc-400">Detected</dt>
          <dd className={detected ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400'}>
            {detected ? 'Yes' : 'No'}
          </dd>
          {detected && screen_type && (
            <>
              <dt className="text-zinc-500 dark:text-zinc-400">Screen Type</dt>
              <dd className="text-zinc-700 dark:text-zinc-300 uppercase">{screen_type}</dd>
            </>
          )}
        </dl>
      </div>
    );
  }

  // Texture-specific details
  // Note: AC4 mentions "material_confidence" but the backend uses "confidence" field
  // which serves the same purpose - confidence in the texture classification result
  if (methodKey === 'texture' && methodDetails.texture) {
    const { classification, confidence, is_likely_recaptured } = methodDetails.texture;
    const classificationDisplay = classification.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    return (
      <div className="mt-2 pt-2 border-t border-zinc-200 dark:border-zinc-700">
        <p className="text-xs font-medium text-zinc-700 dark:text-zinc-300 mb-1">
          Texture Analysis
        </p>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
          <dt className="text-zinc-500 dark:text-zinc-400">Classification</dt>
          <dd className="text-zinc-700 dark:text-zinc-300">{classificationDisplay}</dd>
          <dt className="text-zinc-500 dark:text-zinc-400">Confidence</dt>
          <dd className="text-zinc-700 dark:text-zinc-300">{(confidence * 100).toFixed(0)}%</dd>
          <dt className="text-zinc-500 dark:text-zinc-400">Recaptured</dt>
          <dd className={is_likely_recaptured ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400'}>
            {is_likely_recaptured ? 'Likely' : 'No'}
          </dd>
        </dl>
      </div>
    );
  }

  // Artifacts-specific details
  if (methodKey === 'artifacts' && methodDetails.artifacts) {
    const { pwm_flicker_detected, specular_pattern_detected, halftone_detected } = methodDetails.artifacts;
    const anyDetected = pwm_flicker_detected || specular_pattern_detected || halftone_detected;
    return (
      <div className="mt-2 pt-2 border-t border-zinc-200 dark:border-zinc-700">
        <p className="text-xs font-medium text-zinc-700 dark:text-zinc-300 mb-1">
          Artifact Flags
        </p>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
          <dt className="text-zinc-500 dark:text-zinc-400">PWM Flicker</dt>
          <dd className={pwm_flicker_detected ? 'text-red-600 dark:text-red-400' : 'text-zinc-700 dark:text-zinc-300'}>
            {pwm_flicker_detected ? 'Detected' : 'No'}
          </dd>
          <dt className="text-zinc-500 dark:text-zinc-400">Specular</dt>
          <dd className={specular_pattern_detected ? 'text-red-600 dark:text-red-400' : 'text-zinc-700 dark:text-zinc-300'}>
            {specular_pattern_detected ? 'Detected' : 'No'}
          </dd>
          <dt className="text-zinc-500 dark:text-zinc-400">Halftone</dt>
          <dd className={halftone_detected ? 'text-red-600 dark:text-red-400' : 'text-zinc-700 dark:text-zinc-300'}>
            {halftone_detected ? 'Detected' : 'No'}
          </dd>
        </dl>
        {!anyDetected && (
          <p className="mt-1 text-xs text-green-600 dark:text-green-400">
            No artifacts detected (good)
          </p>
        )}
      </div>
    );
  }

  return null;
}

/**
 * MethodTooltip - Detailed information tooltip for a detection method
 *
 * Shows on click/tap (toggle behavior for both desktop and mobile):
 * - Full method name and description
 * - Raw score (0.0-1.0)
 * - Weight in calculation
 * - Contribution to final score
 * - Method-specific details (LiDAR metrics, moire analysis, texture classification, artifact flags)
 * - Unavailable reason when method was not available
 */
export function MethodTooltip({
  methodKey,
  methodResult,
  methodDetails,
  isVisible,
  onClose,
  className = '',
}: MethodTooltipProps) {
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

  const displayName = getMethodDisplayName(methodKey);
  const description = METHOD_DESCRIPTIONS[methodKey] || 'Detection method for authenticity verification.';
  const { score, weight, contribution, available } = methodResult;

  return (
    <div
      ref={tooltipRef}
      role="tooltip"
      aria-live="polite"
      className={`
        absolute z-50 left-0 right-0 mt-2
        bg-white dark:bg-zinc-800
        border border-zinc-200 dark:border-zinc-700
        rounded-lg shadow-lg
        p-4
        animate-in fade-in-0 zoom-in-95 duration-200
        ${className}
      `}
      data-testid={`tooltip-${methodKey}`}
    >
      {/* Close button (mobile-friendly) */}
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
        {displayName}
      </h4>
      <p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">
        {description}
      </p>

      {/* Score details */}
      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-xs">
        <dt className="text-zinc-500 dark:text-zinc-400">Raw Score</dt>
        <dd className="text-zinc-700 dark:text-zinc-300 font-medium">
          {available ? formatRawScore(score) : 'N/A'}
        </dd>

        <dt className="text-zinc-500 dark:text-zinc-400">Weight</dt>
        <dd className="text-zinc-700 dark:text-zinc-300 font-medium">
          {(weight * 100).toFixed(0)}%
        </dd>

        <dt className="text-zinc-500 dark:text-zinc-400">Contribution</dt>
        <dd className="text-zinc-700 dark:text-zinc-300 font-medium">
          {available ? formatContribution(contribution) : '0%'}
        </dd>
      </dl>

      {/* Unavailable explanation with specific reason when available */}
      {!available && (
        <p className="mt-2 text-xs text-zinc-500 dark:text-zinc-400 italic">
          {methodResult.unavailable_reason
            ? `Unavailable: ${methodResult.unavailable_reason}`
            : 'This method was not available for this capture.'}
        </p>
      )}

      {/* Method-specific details */}
      <MethodSpecificDetails methodKey={methodKey} methodDetails={methodDetails} />
    </div>
  );
}
