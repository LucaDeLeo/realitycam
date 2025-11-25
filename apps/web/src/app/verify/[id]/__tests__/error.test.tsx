/**
 * Verify Error Page Unit Tests
 *
 * Tests for the error boundary component (client component with 'use client').
 * Uses Vitest + React Testing Library with Next.js mocks.
 *
 * @see src/app/verify/[id]/error.tsx
 */

import { describe, test, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import VerifyError from '../error';

describe('VerifyError', () => {
  const mockReset = vi.fn();
  const mockError = new Error('Test error message');

  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  // ============================================================================
  // Rendering Tests
  // ============================================================================

  describe('Rendering', () => {
    test('[P2] should render error page with title', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      expect(screen.getByText('Verification Error')).toBeInTheDocument();
    });

    test('[P2] should render error message', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      expect(
        screen.getByText(/Something went wrong while verifying this photo/i)
      ).toBeInTheDocument();
    });

    test('[P2] should render header with logo', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      expect(screen.getByText('rial.')).toBeInTheDocument();
    });

    test('[P2] should render "Photo Verification" label', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      expect(screen.getByText('Photo Verification')).toBeInTheDocument();
    });
  });

  // ============================================================================
  // Action Tests
  // ============================================================================

  describe('Actions', () => {
    test('[P2] should render Try Again button', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      expect(screen.getByRole('button', { name: /Try Again/i })).toBeInTheDocument();
    });

    test('[P2] should call reset when Try Again clicked', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      fireEvent.click(screen.getByRole('button', { name: /Try Again/i }));

      expect(mockReset).toHaveBeenCalledTimes(1);
    });

    test('[P2] should render Go Home link', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      const homeLink = screen.getByRole('link', { name: /Go Home/i });
      expect(homeLink).toBeInTheDocument();
      expect(homeLink).toHaveAttribute('href', '/');
    });

    test('[P2] should have clickable logo linking home', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      const logoLink = screen.getByText('rial.').closest('a');
      expect(logoLink).toHaveAttribute('href', '/');
    });
  });

  // ============================================================================
  // Error Logging Tests
  // ============================================================================

  describe('Error Logging', () => {
    test('[P2] should log error to console on mount', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      expect(console.error).toHaveBeenCalledWith(
        'Verification page error:',
        mockError
      );
    });
  });

  // ============================================================================
  // Accessibility Tests
  // ============================================================================

  describe('Accessibility', () => {
    test('[P2] should have accessible error icon', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      const svg = document.querySelector('svg[aria-hidden="true"]');
      expect(svg).toBeInTheDocument();
    });

    test('[P2] should have proper heading hierarchy', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      const heading = screen.getByRole('heading', { level: 1 });
      expect(heading).toHaveTextContent('Verification Error');
    });

    test('[P2] should have main content area', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      const main = document.querySelector('main');
      expect(main).toBeInTheDocument();
    });

    test('[P2] should have header landmark', () => {
      render(<VerifyError error={mockError} reset={mockReset} />);

      const header = document.querySelector('header');
      expect(header).toBeInTheDocument();
    });
  });

  // ============================================================================
  // Error Digest Tests
  // ============================================================================

  describe('Error Digest', () => {
    test('[P2] should support error with digest property', () => {
      const errorWithDigest = new Error('Test error') as Error & { digest?: string };
      errorWithDigest.digest = 'error-digest-123';

      render(<VerifyError error={errorWithDigest} reset={mockReset} />);

      // Component should render without crashing
      expect(screen.getByText('Verification Error')).toBeInTheDocument();
    });
  });
});
