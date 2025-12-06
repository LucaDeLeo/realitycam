'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';
import { logPageLoad, isDebugEnabled } from '@/lib/debug-logger';

/**
 * DebugInitializer - Client component that logs PAGE_LOAD events on mount
 *
 * Only active in development mode (NODE_ENV === 'development').
 * Renders nothing - purely for side effects.
 */
export function DebugInitializer() {
  const pathname = usePathname();

  useEffect(() => {
    if (isDebugEnabled()) {
      logPageLoad(pathname, document.referrer || undefined);
    }
  }, [pathname]);

  return null;
}
