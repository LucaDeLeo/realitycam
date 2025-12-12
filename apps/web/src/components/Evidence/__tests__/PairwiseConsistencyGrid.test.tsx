/**
 * Unit tests for PairwiseConsistencyGrid component (Story 11-2)
 *
 * Tests:
 * - Renders method pairs correctly
 * - Shows agreement scores and indicators
 * - Handles anomaly highlighting
 * - Handles empty state
 */

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { PairwiseConsistencyGrid } from '../PairwiseConsistencyGrid';
import type { PairwiseConsistency } from '@realitycam/shared';

const createConsistency = (overrides: Partial<PairwiseConsistency> = {}): PairwiseConsistency => ({
  method_a: 'lidar_depth',
  method_b: 'texture',
  expected_relationship: 'positive',
  actual_agreement: 0.85,
  anomaly_score: 0.05,
  is_anomaly: false,
  ...overrides,
});

describe('PairwiseConsistencyGrid', () => {
  describe('rendering', () => {
    it('renders grid with correct test id', () => {
      const consistencies = [createConsistency()];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.getByTestId('pairwise-consistency-grid')).toBeInTheDocument();
    });

    it('renders section header', () => {
      const consistencies = [createConsistency()];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.getByText('Pairwise Consistency')).toBeInTheDocument();
    });

    it('displays method pair names with display names', () => {
      const consistencies = [createConsistency({ method_a: 'lidar_depth', method_b: 'moire' })];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.getByText('LiDAR')).toBeInTheDocument();
      expect(screen.getByText('Moire')).toBeInTheDocument();
    });

    it('displays agreement score as percentage', () => {
      const consistencies = [createConsistency({ actual_agreement: 0.87 })];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.getByText('87%')).toBeInTheDocument();
    });

    it('renders multiple pairs', () => {
      const consistencies = [
        createConsistency({ method_a: 'lidar_depth', method_b: 'moire', actual_agreement: 0.87 }),
        createConsistency({ method_a: 'lidar_depth', method_b: 'texture', actual_agreement: 0.92 }),
      ];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.getByText('87%')).toBeInTheDocument();
      expect(screen.getByText('92%')).toBeInTheDocument();
    });
  });

  describe('anomaly handling', () => {
    it('shows "Anomaly" label for anomalous pairs', () => {
      const consistencies = [createConsistency({ is_anomaly: true })];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.getByText('Anomaly')).toBeInTheDocument();
    });

    it('does not show "Anomaly" label for normal pairs', () => {
      const consistencies = [createConsistency({ is_anomaly: false })];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.queryByText('Anomaly')).not.toBeInTheDocument();
    });

    it('applies red background for anomalous pairs', () => {
      const consistencies = [createConsistency({ is_anomaly: true })];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      // The role="listitem" is on the div that has the background color
      const listitem = screen.getByRole('listitem');
      expect(listitem).toHaveClass('bg-red-50');
    });
  });

  describe('empty state', () => {
    it('shows empty message when no consistencies', () => {
      render(<PairwiseConsistencyGrid consistencies={[]} />);

      expect(screen.getByText('No pairwise consistency data available')).toBeInTheDocument();
    });

    it('does not render grid when empty', () => {
      render(<PairwiseConsistencyGrid consistencies={[]} />);

      expect(screen.queryByTestId('pairwise-consistency-grid')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has role="list" on grid', () => {
      const consistencies = [createConsistency()];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      expect(screen.getByRole('list')).toBeInTheDocument();
    });

    it('has role="listitem" on each pair', () => {
      const consistencies = [
        createConsistency({ method_a: 'lidar_depth', method_b: 'moire' }),
        createConsistency({ method_a: 'lidar_depth', method_b: 'texture' }),
      ];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      const listitems = screen.getAllByRole('listitem');
      expect(listitems).toHaveLength(2);
    });

    it('has aria-label on grid', () => {
      const consistencies = [createConsistency()];
      render(<PairwiseConsistencyGrid consistencies={consistencies} />);

      const list = screen.getByRole('list');
      expect(list).toHaveAttribute('aria-label', 'Method pair consistency results');
    });
  });

  describe('custom className', () => {
    it('applies additional className', () => {
      const consistencies = [createConsistency()];
      const { container } = render(
        <PairwiseConsistencyGrid consistencies={consistencies} className="custom-class" />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });
});
