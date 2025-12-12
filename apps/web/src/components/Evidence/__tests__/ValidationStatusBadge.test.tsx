/**
 * Unit tests for ValidationStatusBadge component (Story 11-2)
 *
 * Tests:
 * - Renders all three status states (pass, warn, fail)
 * - Shows correct labels and colors
 * - Includes proper accessibility attributes
 */

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ValidationStatusBadge } from '../ValidationStatusBadge';

describe('ValidationStatusBadge', () => {
  describe('pass status', () => {
    it('renders green badge with "Methods Agree" text', () => {
      render(<ValidationStatusBadge status="pass" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveTextContent('Methods Agree');
    });

    it('has correct color classes for pass status', () => {
      render(<ValidationStatusBadge status="pass" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toHaveClass('bg-green-100');
      expect(badge).toHaveClass('text-green-800');
    });
  });

  describe('warn status', () => {
    it('renders yellow badge with "Minor Inconsistencies" text', () => {
      render(<ValidationStatusBadge status="warn" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveTextContent('Minor Inconsistencies');
    });

    it('has correct color classes for warn status', () => {
      render(<ValidationStatusBadge status="warn" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toHaveClass('bg-yellow-100');
      expect(badge).toHaveClass('text-yellow-800');
    });
  });

  describe('fail status', () => {
    it('renders red badge with "Methods Disagree" text', () => {
      render(<ValidationStatusBadge status="fail" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveTextContent('Methods Disagree');
    });

    it('has correct color classes for fail status', () => {
      render(<ValidationStatusBadge status="fail" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toHaveClass('bg-red-100');
      expect(badge).toHaveClass('text-red-800');
    });
  });

  describe('accessibility', () => {
    it('has role="status"', () => {
      render(<ValidationStatusBadge status="pass" />);

      const badge = screen.getByRole('status');
      expect(badge).toBeInTheDocument();
    });

    it('has correct aria-label for pass status', () => {
      render(<ValidationStatusBadge status="pass" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toHaveAttribute('aria-label', 'Cross-validation status: Methods Agree');
    });

    it('has correct aria-label for warn status', () => {
      render(<ValidationStatusBadge status="warn" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toHaveAttribute('aria-label', 'Cross-validation status: Minor Inconsistencies');
    });

    it('has correct aria-label for fail status', () => {
      render(<ValidationStatusBadge status="fail" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toHaveAttribute('aria-label', 'Cross-validation status: Methods Disagree');
    });
  });

  describe('custom className', () => {
    it('applies additional className', () => {
      render(<ValidationStatusBadge status="pass" className="custom-class" />);

      const badge = screen.getByTestId('validation-badge');
      expect(badge).toHaveClass('custom-class');
    });
  });
});
