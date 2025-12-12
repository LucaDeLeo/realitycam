'use client';

import { useEffect, useState, useCallback, useRef } from 'react';

interface TOCItem {
  id: string;
  label: string;
  indent?: boolean;
}

interface TableOfContentsProps {
  /** List of sections to navigate */
  items: TOCItem[];
  /** Additional className */
  className?: string;
}

/**
 * TableOfContents - Desktop sidebar navigation for methodology page
 *
 * Features:
 * - Highlights active section based on scroll position
 * - Smooth scroll to section on click
 * - Hidden on mobile (desktop only via lg: breakpoint)
 * - Sticky positioning for visibility while scrolling
 */
export function TableOfContents({ items, className = '' }: TableOfContentsProps) {
  const [activeId, setActiveId] = useState<string>(items[0]?.id || '');
  const initializedRef = useRef(false);

  // Track scroll position to highlight active section
  const handleScroll = useCallback(() => {
    const sections = items.map(item => ({
      id: item.id,
      element: document.getElementById(item.id),
    }));

    const scrollPosition = window.scrollY + 100; // Offset for header

    // Find the section that is currently in view
    for (let i = sections.length - 1; i >= 0; i--) {
      const section = sections[i];
      if (section.element && section.element.offsetTop <= scrollPosition) {
        setActiveId(section.id);
        return;
      }
    }

    // Default to first section if none found
    if (sections[0]) {
      setActiveId(sections[0].id);
    }
  }, [items]);

  // Set initial active section on mount (separate from scroll listener)
  useEffect(() => {
    if (!initializedRef.current) {
      initializedRef.current = true;
      // Use requestAnimationFrame to avoid synchronous setState in effect
      requestAnimationFrame(() => {
        handleScroll();
      });
    }
  }, [handleScroll]);

  useEffect(() => {
    window.addEventListener('scroll', handleScroll, { passive: true });

    return () => {
      window.removeEventListener('scroll', handleScroll);
    };
  }, [handleScroll]);

  const handleClick = (e: React.MouseEvent<HTMLAnchorElement>, id: string) => {
    e.preventDefault();
    const element = document.getElementById(id);
    if (element) {
      const offset = 80; // Account for sticky header
      const elementPosition = element.getBoundingClientRect().top;
      const offsetPosition = elementPosition + window.scrollY - offset;

      window.scrollTo({
        top: offsetPosition,
        behavior: 'smooth',
      });

      // Update URL hash without jumping
      history.pushState(null, '', `#${id}`);
      setActiveId(id);
    }
  };

  return (
    <nav
      aria-label="Table of contents"
      className={`hidden lg:block sticky top-24 ${className}`}
    >
      <h2 className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-4">
        On this page
      </h2>
      <ul className="space-y-2 text-sm" role="list">
        {items.map((item) => (
          <li key={item.id}>
            <a
              href={`#${item.id}`}
              onClick={(e) => handleClick(e, item.id)}
              data-testid={`toc-${item.id}`}
              className={`
                block py-1 border-l-2 transition-colors
                ${item.indent ? 'pl-6' : 'pl-4'}
                ${activeId === item.id
                  ? 'border-blue-500 text-blue-600 dark:text-blue-400 font-medium'
                  : 'border-transparent text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200 hover:border-zinc-300 dark:hover:border-zinc-600'
                }
              `}
              aria-current={activeId === item.id ? 'location' : undefined}
            >
              {item.label}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
