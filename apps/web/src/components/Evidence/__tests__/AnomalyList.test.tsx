/**
 * Unit tests for AnomalyList component (Story 11-2)
 *
 * Tests:
 * - Renders anomaly count badge
 * - Shows "No anomalies" for empty list
 * - Expandable list behavior
 * - Severity indicators
 * - Confidence impact display
 */

import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { AnomalyList } from '../AnomalyList';
import type { AnomalyReport } from '@realitycam/shared';

const createAnomaly = (overrides: Partial<AnomalyReport> = {}): AnomalyReport => ({
  anomaly_type: 'contradictory_signals',
  severity: 'medium',
  affected_methods: ['lidar_depth', 'texture'],
  details: 'LiDAR indicates flat but texture suggests real material',
  confidence_impact: -0.15,
  ...overrides,
});

describe('AnomalyList', () => {
  describe('empty state', () => {
    it('shows "No anomalies" badge when list is empty', () => {
      render(<AnomalyList anomalies={[]} />);

      expect(screen.getByText('No anomalies')).toBeInTheDocument();
    });

    it('does not show expand button when empty', () => {
      render(<AnomalyList anomalies={[]} />);

      expect(screen.queryByTestId('expand-anomalies')).not.toBeInTheDocument();
    });
  });

  describe('populated state', () => {
    it('shows anomaly count badge', () => {
      const anomalies = [createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      expect(screen.getByText('1 detected')).toBeInTheDocument();
    });

    it('shows correct count for multiple anomalies', () => {
      const anomalies = [createAnomaly(), createAnomaly(), createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      expect(screen.getByText('3 detected')).toBeInTheDocument();
    });

    it('displays anomaly type name', () => {
      const anomalies = [createAnomaly({ anomaly_type: 'contradictory_signals' })];
      render(<AnomalyList anomalies={anomalies} />);

      expect(screen.getByText('Contradictory Signals')).toBeInTheDocument();
    });

    it('displays affected methods', () => {
      const anomalies = [createAnomaly({ affected_methods: ['lidar_depth', 'texture'] })];
      render(<AnomalyList anomalies={anomalies} />);

      expect(screen.getByText('LiDAR')).toBeInTheDocument();
      expect(screen.getByText('Texture')).toBeInTheDocument();
    });

    it('displays details text', () => {
      const anomalies = [createAnomaly({ details: 'Test details message' })];
      render(<AnomalyList anomalies={anomalies} />);

      expect(screen.getByText('Test details message')).toBeInTheDocument();
    });

    it('displays confidence impact as percentage', () => {
      const anomalies = [createAnomaly({ confidence_impact: -0.15 })];
      render(<AnomalyList anomalies={anomalies} />);

      expect(screen.getByText('-15%')).toBeInTheDocument();
    });
  });

  describe('collapse/expand behavior', () => {
    it('is expanded by default when 2 or fewer anomalies', () => {
      const anomalies = [createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      // Content should be visible
      expect(screen.getByText('Contradictory Signals')).toBeVisible();
    });

    it('is collapsed by default when more than 2 anomalies', () => {
      const anomalies = [
        createAnomaly(),
        createAnomaly(),
        createAnomaly(),
      ];
      render(<AnomalyList anomalies={anomalies} />);

      // The expand button should be present
      const expandButton = screen.getByTestId('expand-anomalies');
      expect(expandButton).toHaveAttribute('aria-expanded', 'false');
    });

    it('expands on click when collapsed', () => {
      const anomalies = [
        createAnomaly(),
        createAnomaly(),
        createAnomaly(),
      ];
      render(<AnomalyList anomalies={anomalies} />);

      const expandButton = screen.getByTestId('expand-anomalies');
      fireEvent.click(expandButton);

      expect(expandButton).toHaveAttribute('aria-expanded', 'true');
    });

    it('collapses on click when expanded', () => {
      const anomalies = [createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      const expandButton = screen.getByTestId('expand-anomalies');
      fireEvent.click(expandButton);

      expect(expandButton).toHaveAttribute('aria-expanded', 'false');
    });

    it('toggles on Enter key', () => {
      const anomalies = [createAnomaly(), createAnomaly(), createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      const expandButton = screen.getByTestId('expand-anomalies');
      fireEvent.keyDown(expandButton, { key: 'Enter' });

      expect(expandButton).toHaveAttribute('aria-expanded', 'true');
    });

    it('toggles on Space key', () => {
      const anomalies = [createAnomaly(), createAnomaly(), createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      const expandButton = screen.getByTestId('expand-anomalies');
      fireEvent.keyDown(expandButton, { key: ' ' });

      expect(expandButton).toHaveAttribute('aria-expanded', 'true');
    });
  });

  describe('severity indicators', () => {
    it('uses orange badge color for medium severity', () => {
      const anomalies = [createAnomaly({ severity: 'medium' })];
      render(<AnomalyList anomalies={anomalies} />);

      const badge = screen.getByText('1 detected');
      expect(badge).toHaveClass('bg-orange-100');
    });

    it('uses red badge color when any anomaly has high severity', () => {
      const anomalies = [
        createAnomaly({ severity: 'low' }),
        createAnomaly({ severity: 'high' }),
      ];
      render(<AnomalyList anomalies={anomalies} />);

      const badge = screen.getByText('2 detected');
      expect(badge).toHaveClass('bg-red-100');
    });

    it('uses yellow badge color for low severity only', () => {
      const anomalies = [createAnomaly({ severity: 'low' })];
      render(<AnomalyList anomalies={anomalies} />);

      const badge = screen.getByText('1 detected');
      expect(badge).toHaveClass('bg-yellow-100');
    });
  });

  describe('accessibility', () => {
    it('has aria-expanded attribute on expand button', () => {
      const anomalies = [createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      const button = screen.getByTestId('expand-anomalies');
      expect(button).toHaveAttribute('aria-expanded');
    });

    it('has aria-controls pointing to content', () => {
      const anomalies = [createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      const button = screen.getByTestId('expand-anomalies');
      expect(button).toHaveAttribute('aria-controls', 'anomaly-list-content');
    });

    it('content has role="list"', () => {
      const anomalies = [createAnomaly()];
      render(<AnomalyList anomalies={anomalies} />);

      const list = screen.getByRole('list');
      expect(list).toHaveAttribute('aria-label', 'Detected anomalies');
    });
  });

  describe('custom className', () => {
    it('applies additional className', () => {
      const anomalies = [createAnomaly()];
      render(<AnomalyList anomalies={anomalies} className="custom-class" />);

      const container = screen.getByTestId('anomaly-list');
      expect(container).toHaveClass('custom-class');
    });
  });
});
