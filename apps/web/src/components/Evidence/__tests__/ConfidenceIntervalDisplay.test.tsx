/**
 * Unit tests for ConfidenceIntervalDisplay component (Story 11-2)
 *
 * Tests:
 * - Displays point estimate with range
 * - Shows visual error bar
 * - High uncertainty warning
 * - Tooltip functionality
 */

import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ConfidenceIntervalDisplay } from '../ConfidenceIntervalDisplay';
import type { ConfidenceInterval } from '@realitycam/shared';

const createInterval = (overrides: Partial<ConfidenceInterval> = {}): ConfidenceInterval => ({
  lower_bound: 0.87,
  point_estimate: 0.95,
  upper_bound: 0.98,
  ...overrides,
});

describe('ConfidenceIntervalDisplay', () => {
  describe('rendering', () => {
    it('renders with correct test id', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} />);

      expect(screen.getByTestId('confidence-interval-display')).toBeInTheDocument();
    });

    it('displays default label', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} />);

      expect(screen.getByText('Overall Confidence')).toBeInTheDocument();
    });

    it('displays custom label', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} label="Custom Label" />);

      expect(screen.getByText('Custom Label')).toBeInTheDocument();
    });

    it('displays point estimate as percentage', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval({ point_estimate: 0.95 })} />);

      expect(screen.getByText('95%')).toBeInTheDocument();
    });

    it('displays range in parentheses', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval({
        lower_bound: 0.87,
        upper_bound: 0.98,
      })} />);

      expect(screen.getByText('(87%-98%)')).toBeInTheDocument();
    });
  });

  describe('high uncertainty warning', () => {
    it('shows warning when interval width > 0.3', () => {
      const interval = createInterval({
        lower_bound: 0.50,
        point_estimate: 0.70,
        upper_bound: 0.90,
      });
      render(<ConfidenceIntervalDisplay interval={interval} />);

      expect(screen.getByTestId('high-uncertainty-warning')).toBeInTheDocument();
      expect(screen.getByText('High uncertainty - results may vary')).toBeInTheDocument();
    });

    it('does not show warning when interval width <= 0.3', () => {
      const interval = createInterval({
        lower_bound: 0.85,
        point_estimate: 0.90,
        upper_bound: 0.95,
      });
      render(<ConfidenceIntervalDisplay interval={interval} />);

      expect(screen.queryByTestId('high-uncertainty-warning')).not.toBeInTheDocument();
    });

    it('warning has role="alert"', () => {
      const interval = createInterval({
        lower_bound: 0.40,
        point_estimate: 0.65,
        upper_bound: 0.90,
      });
      render(<ConfidenceIntervalDisplay interval={interval} />);

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });
  });

  describe('tooltip', () => {
    it('shows tooltip on hover', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} />);

      const infoButton = screen.getByRole('button', { name: /what is a confidence interval/i });
      fireEvent.mouseEnter(infoButton.parentElement!);

      expect(screen.getByRole('tooltip')).toBeInTheDocument();
      expect(screen.getByText(/95% confidence the true score is within this range/i)).toBeInTheDocument();
    });

    it('hides tooltip on mouse leave', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} />);

      const infoButton = screen.getByRole('button', { name: /what is a confidence interval/i });
      fireEvent.mouseEnter(infoButton.parentElement!);
      fireEvent.mouseLeave(infoButton.parentElement!);

      expect(screen.queryByRole('tooltip')).not.toBeInTheDocument();
    });

    it('shows tooltip on focus', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} />);

      const infoButton = screen.getByRole('button', { name: /what is a confidence interval/i });
      fireEvent.focus(infoButton.parentElement!);

      expect(screen.getByRole('tooltip')).toBeInTheDocument();
    });
  });

  describe('visual bar', () => {
    it('renders progress bar elements', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} />);

      // The visual bar background should be present
      expect(screen.getByTestId('confidence-interval-display').querySelector('.bg-zinc-200')).toBeInTheDocument();
    });
  });

  describe('edge cases', () => {
    it('handles 0% lower bound', () => {
      const interval = createInterval({
        lower_bound: 0.0,
        point_estimate: 0.10,
        upper_bound: 0.20,
      });
      render(<ConfidenceIntervalDisplay interval={interval} />);

      expect(screen.getByText('10%')).toBeInTheDocument();
      expect(screen.getByText('(0%-20%)')).toBeInTheDocument();
    });

    it('handles 100% upper bound', () => {
      const interval = createInterval({
        lower_bound: 0.90,
        point_estimate: 0.95,
        upper_bound: 1.0,
      });
      render(<ConfidenceIntervalDisplay interval={interval} />);

      expect(screen.getByText('95%')).toBeInTheDocument();
      expect(screen.getByText('(90%-100%)')).toBeInTheDocument();
    });
  });

  describe('custom className', () => {
    it('applies additional className', () => {
      render(<ConfidenceIntervalDisplay interval={createInterval()} className="custom-class" />);

      const container = screen.getByTestId('confidence-interval-display');
      expect(container).toHaveClass('custom-class');
    });
  });
});
