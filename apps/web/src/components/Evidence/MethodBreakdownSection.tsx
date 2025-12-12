'use client';

import { useState, useCallback } from 'react';
import type { DetectionResults, AggregatedConfidence, ConfidenceLevel } from '@realitycam/shared';
import { ConfidenceBadge } from './ConfidenceBadge';
import { MethodScoreBar } from './MethodScoreBar';
import { MethodTooltip } from './MethodTooltip';

interface MethodBreakdownSectionProps {
  /** Detection results from API */
  detection: DetectionResults;
  /** Whether section is expanded by default */
  defaultExpanded?: boolean;
  /** Additional className */
  className?: string;
}

/**
 * Count available methods in the breakdown
 */
function countAvailableMethods(aggregated?: AggregatedConfidence): number {
  if (!aggregated?.method_breakdown) return 0;
  return Object.values(aggregated.method_breakdown).filter(m => m.available).length;
}

/**
 * MethodBreakdownSection - Collapsible section showing detection method breakdown
 *
 * Displays:
 * - Overall confidence summary with ConfidenceBadge
 * - Primary/supporting signal status indicators
 * - List of individual method score bars
 * - Tooltips with detailed method information
 */
export function MethodBreakdownSection({
  detection,
  defaultExpanded = true,
  className = '',
}: MethodBreakdownSectionProps) {
  const [isExpanded, setIsExpanded] = useState(defaultExpanded);
  const [activeTooltip, setActiveTooltip] = useState<string | null>(null);

  const toggleExpanded = () => setIsExpanded(!isExpanded);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggleExpanded();
    }
  };

  const handleMethodClick = useCallback((methodKey: string) => {
    setActiveTooltip(prev => prev === methodKey ? null : methodKey);
  }, []);

  const handleCloseTooltip = useCallback(() => {
    setActiveTooltip(null);
  }, []);

  const aggregated = detection.aggregated_confidence;

  // Don't render if no aggregated confidence data
  if (!aggregated) {
    return null;
  }

  const methodCount = countAvailableMethods(aggregated);
  const overallPercent = Math.round(aggregated.overall_confidence * 100);

  // Order methods: lidar_depth first (primary), then others
  const methodEntries = Object.entries(aggregated.method_breakdown);
  const sortedMethods = methodEntries.sort(([keyA], [keyB]) => {
    if (keyA === 'lidar_depth') return -1;
    if (keyB === 'lidar_depth') return 1;
    return 0;
  });

  return (
    <div
      className={`w-full rounded-xl border border-zinc-200 dark:border-zinc-800
                  bg-white dark:bg-zinc-900 overflow-hidden ${className}`}
      data-testid="method-breakdown-section"
    >
      {/* Section Header - Click to expand/collapse */}
      <button
        type="button"
        onClick={toggleExpanded}
        onKeyDown={handleKeyDown}
        aria-expanded={isExpanded}
        aria-controls="method-breakdown-content"
        className="w-full flex items-center justify-between px-4 sm:px-6 py-4
                   bg-zinc-50 dark:bg-zinc-900
                   hover:bg-zinc-100 dark:hover:bg-zinc-800
                   transition-colors cursor-pointer
                   focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500"
      >
        <div className="flex items-center gap-3">
          <h3
            id="method-breakdown-header"
            className="text-base font-semibold text-zinc-900 dark:text-white"
          >
            Detection Methods
          </h3>
          <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400">
            {methodCount} methods
          </span>
        </div>
        <svg
          className={`h-5 w-5 text-zinc-500 dark:text-zinc-400 transition-transform duration-200 ${
            isExpanded ? 'rotate-180' : ''
          }`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </button>

      {/* Section Content */}
      <div
        id="method-breakdown-content"
        role="region"
        aria-labelledby="method-breakdown-header"
        className={`transition-all duration-200 ease-in-out ${
          isExpanded ? 'max-h-[1000px] opacity-100' : 'max-h-0 opacity-0 overflow-hidden'
        }`}
      >
        {/* Overall Confidence Summary */}
        <div className="px-4 sm:px-6 py-4 border-b border-zinc-100 dark:border-zinc-800">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            {/* Score and Badge */}
            <div className="flex items-center gap-4">
              <div className="text-center">
                <p className="text-3xl font-bold text-zinc-900 dark:text-white">
                  {overallPercent}%
                </p>
                <p className="text-xs text-zinc-500 dark:text-zinc-400">
                  Overall
                </p>
              </div>
              <ConfidenceBadge level={aggregated.confidence_level as ConfidenceLevel} />
            </div>

            {/* Signal Status Indicators */}
            <div className="flex items-center gap-4 text-sm" role="group" aria-label="Signal validation status">
              {/* Primary Signal */}
              <div
                className="flex items-center gap-2"
                role="status"
                aria-label={`Primary signal ${aggregated.primary_signal_valid ? 'passed' : 'failed'}`}
              >
                <span
                  className={`w-2 h-2 rounded-full ${
                    aggregated.primary_signal_valid
                      ? 'bg-green-500 dark:bg-green-400'
                      : 'bg-red-500 dark:bg-red-400'
                  }`}
                  aria-hidden="true"
                />
                <span className="text-zinc-600 dark:text-zinc-400">
                  Primary: <span className={aggregated.primary_signal_valid ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}>
                    {aggregated.primary_signal_valid ? 'PASS' : 'FAIL'}
                  </span>
                </span>
              </div>

              {/* Supporting Signals */}
              <div
                className="flex items-center gap-2"
                role="status"
                aria-label={`Supporting signals ${aggregated.supporting_signals_agree ? 'agree' : 'disagree'}`}
              >
                <span
                  className={`w-2 h-2 rounded-full ${
                    aggregated.supporting_signals_agree
                      ? 'bg-green-500 dark:bg-green-400'
                      : 'bg-yellow-500 dark:bg-yellow-400'
                  }`}
                  aria-hidden="true"
                />
                <span className="text-zinc-600 dark:text-zinc-400">
                  Supporting: <span className={aggregated.supporting_signals_agree ? 'text-green-600 dark:text-green-400' : 'text-yellow-600 dark:text-yellow-400'}>
                    {aggregated.supporting_signals_agree ? 'AGREE' : 'DISAGREE'}
                  </span>
                </span>
              </div>
            </div>
          </div>

          {/* Flags if any */}
          {aggregated.flags && aggregated.flags.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-2">
              {aggregated.flags.map((flag, index) => (
                <span
                  key={index}
                  className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300"
                >
                  {flag}
                </span>
              ))}
            </div>
          )}
        </div>

        {/* Method Score Bars - 2-column on tablet (md: 768px+) per AC7 */}
        <div className="px-4 sm:px-6 py-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {sortedMethods.map(([methodKey, result]) => (
              <div key={methodKey} className="relative">
                <MethodScoreBar
                  methodKey={methodKey}
                  score={result.score}
                  weight={result.weight}
                  available={result.available}
                  status={result.status}
                  onClick={() => handleMethodClick(methodKey)}
                  isActive={activeTooltip === methodKey}
                />
                <MethodTooltip
                  methodKey={methodKey}
                  methodResult={result}
                  methodDetails={{
                    moire: detection.moire,
                    texture: detection.texture,
                    artifacts: detection.artifacts,
                    lidar: detection.lidar,
                  }}
                  isVisible={activeTooltip === methodKey}
                  onClose={handleCloseTooltip}
                />
              </div>
            ))}
          </div>
        </div>

        {/* Processing Info */}
        {detection.total_processing_time_ms > 0 && (
          <div className="px-4 sm:px-6 py-2 bg-zinc-50 dark:bg-zinc-900/50 border-t border-zinc-100 dark:border-zinc-800">
            <p className="text-xs text-zinc-500 dark:text-zinc-400">
              Detection computed in {detection.total_processing_time_ms}ms
              {detection.computed_at && (
                <> at {new Date(detection.computed_at).toLocaleString()}</>
              )}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
