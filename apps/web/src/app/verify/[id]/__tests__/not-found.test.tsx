/**
 * Verify Not Found Page Unit Tests
 *
 * Tests for the 404 page component.
 * Uses Vitest + React Testing Library with Next.js mocks.
 *
 * @see src/app/verify/[id]/not-found.tsx
 */

import { describe, test, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import VerifyNotFound from '../not-found';

describe('VerifyNotFound', () => {
  // ============================================================================
  // Rendering Tests
  // ============================================================================

  describe('Rendering', () => {
    test('[P2] should render not found title', () => {
      render(<VerifyNotFound />);

      expect(screen.getByText('Photo Not Found')).toBeInTheDocument();
    });

    test('[P2] should render helpful message', () => {
      render(<VerifyNotFound />);

      expect(
        screen.getByText(/couldn't find a verified photo with this ID/i)
      ).toBeInTheDocument();
    });

    test('[P2] should mention possible causes', () => {
      render(<VerifyNotFound />);

      expect(
        screen.getByText(/may have been removed or the link may be incorrect/i)
      ).toBeInTheDocument();
    });

    test('[P2] should render header with logo', () => {
      render(<VerifyNotFound />);

      expect(screen.getByText('rial.')).toBeInTheDocument();
    });

    test('[P2] should render "Photo Verification" label', () => {
      render(<VerifyNotFound />);

      expect(screen.getByText('Photo Verification')).toBeInTheDocument();
    });
  });

  // ============================================================================
  // Navigation Tests
  // ============================================================================

  describe('Navigation', () => {
    test('[P2] should render Go Home button', () => {
      render(<VerifyNotFound />);

      const homeLink = screen.getByRole('link', { name: /Go Home/i });
      expect(homeLink).toBeInTheDocument();
    });

    test('[P2] should link to home page', () => {
      render(<VerifyNotFound />);

      const homeLink = screen.getByRole('link', { name: /Go Home/i });
      expect(homeLink).toHaveAttribute('href', '/');
    });

    test('[P2] should have clickable logo linking home', () => {
      render(<VerifyNotFound />);

      const logoLink = screen.getByText('rial.').closest('a');
      expect(logoLink).toHaveAttribute('href', '/');
    });
  });

  // ============================================================================
  // Visual Elements Tests
  // ============================================================================

  describe('Visual Elements', () => {
    test('[P2] should render icon', () => {
      render(<VerifyNotFound />);

      const svg = document.querySelector('svg');
      expect(svg).toBeInTheDocument();
    });

    test('[P2] should have icon with aria-hidden', () => {
      render(<VerifyNotFound />);

      const svg = document.querySelector('svg[aria-hidden="true"]');
      expect(svg).toBeInTheDocument();
    });
  });

  // ============================================================================
  // Accessibility Tests
  // ============================================================================

  describe('Accessibility', () => {
    test('[P2] should have proper heading', () => {
      render(<VerifyNotFound />);

      const heading = screen.getByRole('heading', { level: 1 });
      expect(heading).toHaveTextContent('Photo Not Found');
    });

    test('[P2] should have main landmark', () => {
      render(<VerifyNotFound />);

      const main = document.querySelector('main');
      expect(main).toBeInTheDocument();
    });

    test('[P2] should have header landmark', () => {
      render(<VerifyNotFound />);

      const header = document.querySelector('header');
      expect(header).toBeInTheDocument();
    });
  });

  // ============================================================================
  // Styling Tests
  // ============================================================================

  describe('Styling', () => {
    test('[P2] should have dark mode classes', () => {
      render(<VerifyNotFound />);

      const container = document.querySelector('.dark\\:bg-black');
      expect(container).toBeInTheDocument();
    });

    test('[P2] should be responsive', () => {
      render(<VerifyNotFound />);

      // Check for responsive classes
      const responsiveElement = document.querySelector('[class*="sm:"]');
      expect(responsiveElement).toBeInTheDocument();
    });
  });
});
