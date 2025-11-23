'use client';

import { useState } from 'react';
import { EvidenceRow, type ExtendedEvidenceStatus } from './EvidenceRow';

interface EvidenceItem {
  label: string;
  status: ExtendedEvidenceStatus;
  value?: string;
}

interface EvidencePanelProps {
  items?: EvidenceItem[];
  className?: string;
  defaultExpanded?: boolean;
}

/**
 * Default evidence items for placeholder state
 */
const defaultEvidenceItems: EvidenceItem[] = [
  { label: 'Hardware Attestation', status: 'pending' },
  { label: 'LiDAR Depth Analysis', status: 'pending' },
  { label: 'Timestamp', status: 'pending' },
  { label: 'Device Model', status: 'pending' },
  { label: 'Location', status: 'pending' },
];

/**
 * EvidencePanel - Expandable panel showing verification evidence details
 *
 * Displays a collapsible panel with evidence rows for each verification check.
 * Collapsed by default with expand/collapse indicator. Each row shows the
 * evidence type, status icon, and current status text.
 */
export function EvidencePanel({
  items = defaultEvidenceItems,
  className = '',
  defaultExpanded = false,
}: EvidencePanelProps) {
  const [isExpanded, setIsExpanded] = useState(defaultExpanded);

  const toggleExpanded = () => setIsExpanded(!isExpanded);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggleExpanded();
    }
  };

  return (
    <div
      className={`w-full rounded-xl border border-zinc-200 dark:border-zinc-800
                  bg-white dark:bg-zinc-900 overflow-hidden ${className}`}
    >
      {/* Panel Header - Click to expand/collapse */}
      <button
        type="button"
        onClick={toggleExpanded}
        onKeyDown={handleKeyDown}
        aria-expanded={isExpanded}
        aria-controls="evidence-panel-content"
        className="w-full flex items-center justify-between px-4 sm:px-6 py-4
                   bg-zinc-50 dark:bg-zinc-900
                   hover:bg-zinc-100 dark:hover:bg-zinc-800
                   transition-colors cursor-pointer
                   focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500"
      >
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white">
          Evidence Details
        </h3>
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

      {/* Panel Content - Evidence rows */}
      <div
        id="evidence-panel-content"
        role="region"
        aria-labelledby="evidence-panel-header"
        className={`transition-all duration-200 ease-in-out ${
          isExpanded ? 'max-h-[500px] opacity-100' : 'max-h-0 opacity-0 overflow-hidden'
        }`}
      >
        <div className="divide-y divide-zinc-100 dark:divide-zinc-800">
          {items.map((item, index) => (
            <EvidenceRow
              key={`${item.label}-${index}`}
              label={item.label}
              status={item.status}
              value={item.value}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
