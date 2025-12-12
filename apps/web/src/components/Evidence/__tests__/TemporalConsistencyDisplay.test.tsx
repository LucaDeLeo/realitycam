/**
 * Unit tests for TemporalConsistencyDisplay component (Story 11-2)
 *
 * Tests:
 * - Displays overall stability score
 * - Shows frame count
 * - Renders per-method stability bars
 * - Shows temporal anomalies when present
 */

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { TemporalConsistencyDisplay } from '../TemporalConsistencyDisplay';
import type { TemporalConsistency, TemporalAnomaly } from '@realitycam/shared';

const createTemporalConsistency = (overrides: Partial<TemporalConsistency> = {}): TemporalConsistency => ({
  frame_count: 30,
  stability_scores: {
    lidar_depth: 0.94,
    moire: 0.88,
    texture: 0.91,
  },
  anomalies: [],
  overall_stability: 0.91,
  ...overrides,
});

const createTemporalAnomaly = (overrides: Partial<TemporalAnomaly> = {}): TemporalAnomaly => ({
  frame_index: 15,
  method: 'moire',
  delta_score: 0.25,
  anomaly_type: 'sudden_jump',
  ...overrides,
});

describe('TemporalConsistencyDisplay', () => {
  describe('rendering', () => {
    it('renders with correct test id', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency()} />);

      expect(screen.getByTestId('temporal-consistency-display')).toBeInTheDocument();
    });

    it('displays section title', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency()} />);

      expect(screen.getByText('Temporal Stability')).toBeInTheDocument();
    });

    it('displays frame count', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ frame_count: 30 })} />);

      expect(screen.getByText('30 frames analyzed')).toBeInTheDocument();
    });

    it('displays overall stability score', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ overall_stability: 0.91 })} />);

      // Overall stability appears in the header as a large font
      const percentage = screen.getAllByText('91%')[0];
      expect(percentage).toBeInTheDocument();
    });

    it('formats large frame counts with comma separators', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ frame_count: 1500 })} />);

      expect(screen.getByText('1,500 frames analyzed')).toBeInTheDocument();
    });
  });

  describe('per-method stability', () => {
    it('displays method names with display names', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency()} />);

      expect(screen.getByText('LiDAR')).toBeInTheDocument();
      expect(screen.getByText('Moire')).toBeInTheDocument();
      expect(screen.getByText('Texture')).toBeInTheDocument();
    });

    it('displays per-method stability percentages', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({
        overall_stability: 0.85,
        stability_scores: {
          lidar_depth: 0.94,
          texture: 0.89,
        },
      })} />);

      expect(screen.getByText('94%')).toBeInTheDocument();
      expect(screen.getByText('89%')).toBeInTheDocument();
    });

    it('renders progress bars for each method', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency()} />);

      const progressbars = screen.getAllByRole('progressbar');
      expect(progressbars.length).toBeGreaterThan(0);
    });
  });

  describe('temporal anomalies', () => {
    it('does not show anomalies section when empty', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies: [] })} />);

      expect(screen.queryByText(/Temporal Anomalies/i)).not.toBeInTheDocument();
    });

    it('shows anomalies section when anomalies exist', () => {
      const anomalies = [createTemporalAnomaly()];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies })} />);

      expect(screen.getByText('Temporal Anomalies (1)')).toBeInTheDocument();
    });

    it('displays anomaly frame index', () => {
      const anomalies = [createTemporalAnomaly({ frame_index: 15 })];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies })} />);

      expect(screen.getByText(/Frame 15/i)).toBeInTheDocument();
    });

    it('displays anomaly type name', () => {
      const anomalies = [createTemporalAnomaly({ anomaly_type: 'sudden_jump' })];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies })} />);

      expect(screen.getByText(/Sudden jump/i)).toBeInTheDocument();
    });

    it('displays anomaly method name', () => {
      const anomalies = [createTemporalAnomaly({ method: 'artifacts' })];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({
        anomalies,
        stability_scores: { lidar_depth: 0.90 }, // no moire to avoid duplicates
      })} />);

      expect(screen.getByText(/Artifacts/i)).toBeInTheDocument();
    });

    it('displays delta score', () => {
      const anomalies = [createTemporalAnomaly({ delta_score: 0.25 })];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies })} />);

      expect(screen.getByText('+25%')).toBeInTheDocument();
    });

    it('displays negative delta score', () => {
      const anomalies = [createTemporalAnomaly({ delta_score: -0.30 })];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies })} />);

      expect(screen.getByText('-30%')).toBeInTheDocument();
    });

    it('shows multiple anomalies', () => {
      const anomalies = [
        createTemporalAnomaly({ frame_index: 10, anomaly_type: 'sudden_jump' }),
        createTemporalAnomaly({ frame_index: 25, anomaly_type: 'oscillation' }),
      ];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies })} />);

      expect(screen.getByText('Temporal Anomalies (2)')).toBeInTheDocument();
    });
  });

  describe('stability color coding', () => {
    it('uses green color for high stability (>= 0.8)', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({
        overall_stability: 0.85,
        stability_scores: { lidar_depth: 0.94 }, // avoid duplicate percentages
      })} />);

      // The header overall stability score has the color class
      const percentage = screen.getByText('85%');
      expect(percentage).toHaveClass('text-green-600');
    });

    it('uses yellow color for medium stability (0.5-0.8)', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ overall_stability: 0.65 })} />);

      const percentage = screen.getByText('65%');
      expect(percentage).toHaveClass('text-yellow-600');
    });

    it('uses red color for low stability (< 0.5)', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ overall_stability: 0.35 })} />);

      const percentage = screen.getByText('35%');
      expect(percentage).toHaveClass('text-red-600');
    });
  });

  describe('accessibility', () => {
    it('progress bars have aria labels', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency()} />);

      const progressbars = screen.getAllByRole('progressbar');
      progressbars.forEach((bar) => {
        expect(bar).toHaveAttribute('aria-label');
      });
    });

    it('anomalies have role="list"', () => {
      const anomalies = [createTemporalAnomaly()];
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency({ anomalies })} />);

      const list = screen.getByRole('list');
      expect(list).toHaveAttribute('aria-label', 'Temporal anomalies');
    });
  });

  describe('custom className', () => {
    it('applies additional className', () => {
      render(<TemporalConsistencyDisplay temporalConsistency={createTemporalConsistency()} className="custom-class" />);

      const container = screen.getByTestId('temporal-consistency-display');
      expect(container).toHaveClass('custom-class');
    });
  });
});
