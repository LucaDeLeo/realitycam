'use client';

import { useState, useId } from 'react';

interface ExpandableSectionProps {
  /** Section title */
  title: string;
  /** Section identifier for navigation */
  id: string;
  /** Whether section is expanded by default */
  defaultExpanded?: boolean;
  /** Optional icon to display before title */
  icon?: React.ReactNode;
  /** Optional summary text below title (visible when collapsed) */
  summary?: string;
  /** Section content */
  children: React.ReactNode;
  /** Heading level for semantic structure */
  headingLevel?: 'h2' | 'h3';
  /** Additional className */
  className?: string;
}

/**
 * ExpandableSection - Reusable collapsible section for methodology page
 *
 * Features:
 * - Progressive disclosure with expand/collapse
 * - Accessible with aria-expanded, aria-controls, keyboard support
 * - Smooth animation on expand/collapse
 * - Configurable heading level for proper document outline
 */
export function ExpandableSection({
  title,
  id,
  defaultExpanded = false,
  icon,
  summary,
  children,
  headingLevel = 'h2',
  className = '',
}: ExpandableSectionProps) {
  const [isExpanded, setIsExpanded] = useState(defaultExpanded);
  const contentId = useId();

  const toggleExpanded = () => setIsExpanded(!isExpanded);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggleExpanded();
    }
  };

  const HeadingTag = headingLevel;

  return (
    <section
      id={id}
      className={`scroll-mt-20 ${className}`}
      data-testid={`section-${id}`}
    >
      <button
        type="button"
        onClick={toggleExpanded}
        onKeyDown={handleKeyDown}
        aria-expanded={isExpanded}
        aria-controls={contentId}
        className="w-full flex items-center justify-between px-4 sm:px-6 py-4
                   bg-white dark:bg-zinc-900
                   border border-zinc-200 dark:border-zinc-800
                   hover:bg-zinc-50 dark:hover:bg-zinc-800/50
                   rounded-xl transition-colors cursor-pointer
                   focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500"
      >
        <div className="flex items-center gap-3">
          {icon && (
            <span className="text-zinc-500 dark:text-zinc-400" aria-hidden="true">
              {icon}
            </span>
          )}
          <div className="text-left">
            <HeadingTag className="text-lg font-semibold text-zinc-900 dark:text-white">
              {title}
            </HeadingTag>
            {summary && !isExpanded && (
              <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-0.5">
                {summary}
              </p>
            )}
          </div>
        </div>
        <svg
          className={`h-5 w-5 flex-shrink-0 text-zinc-500 dark:text-zinc-400 transition-transform duration-200 ${
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

      <div
        id={contentId}
        role="region"
        aria-labelledby={id}
        className={`transition-all duration-300 ease-in-out overflow-hidden ${
          isExpanded ? 'max-h-[5000px] opacity-100' : 'max-h-0 opacity-0'
        }`}
      >
        <div className="px-4 sm:px-6 py-6 bg-white dark:bg-zinc-900 border border-t-0 border-zinc-200 dark:border-zinc-800 rounded-b-xl -mt-3">
          {children}
        </div>
      </div>
    </section>
  );
}
