/**
 * Unit tests for CrossValidationSection component (Story 11-2)
 *
 * Tests:
 * - Renders all child components
 * - Expand/collapse functionality
 * - Penalty display
 * - Temporal consistency for video
 * - Processing footer
 */

import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CrossValidationSection } from '../CrossValidationSection';
import type { CrossValidationResult, PairwiseConsistency, ConfidenceInterval, AnomalyReport, TemporalConsistency } from '@realitycam/shared';

const createPairwiseConsistency = (overrides: Partial<PairwiseConsistency> = {}): PairwiseConsistency => ({
  method_a: 'lidar_depth',
  method_b: 'texture',
  expected_relationship: 'positive',
  actual_agreement: 0.85,
  anomaly_score: 0.05,
  is_anomaly: false,
  ...overrides,
});

const createConfidenceInterval = (overrides: Partial<ConfidenceInterval> = {}): ConfidenceInterval => ({
  lower_bound: 0.87,
  point_estimate: 0.95,
  upper_bound: 0.98,
  ...overrides,
});

const createAnomaly = (overrides: Partial<AnomalyReport> = {}): AnomalyReport => ({
  anomaly_type: 'contradictory_signals',
  severity: 'medium',
  affected_methods: ['lidar_depth', 'texture'],
  details: 'Test anomaly details',
  confidence_impact: -0.15,
  ...overrides,
});

const createTemporalConsistency = (overrides: Partial<TemporalConsistency> = {}): TemporalConsistency => ({
  frame_count: 30,
  stability_scores: { lidar_depth: 0.94, texture: 0.91 },
  anomalies: [],
  overall_stability: 0.92,
  ...overrides,
});

const createCrossValidation = (overrides: Partial<CrossValidationResult> = {}): CrossValidationResult => ({
  validation_status: 'pass',
  pairwise_consistencies: [createPairwiseConsistency()],
  confidence_intervals: {
    lidar_depth: createConfidenceInterval(),
  },
  aggregated_interval: createConfidenceInterval(),
  anomalies: [],
  overall_penalty: 0,
  analysis_time_ms: 5,
  algorithm_version: '1.0',
  computed_at: new Date().toISOString(),
  ...overrides,
});

describe('CrossValidationSection', () => {
  describe('rendering', () => {
    it('renders with correct test id', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      expect(screen.getByTestId('cross-validation-section')).toBeInTheDocument();
    });

    it('displays section title', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      expect(screen.getByText('Cross-Validation')).toBeInTheDocument();
    });

    it('displays ValidationStatusBadge', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({ validation_status: 'pass' })} />);

      expect(screen.getByTestId('validation-badge')).toBeInTheDocument();
      expect(screen.getByText('Methods Agree')).toBeInTheDocument();
    });

    it('displays ConfidenceIntervalDisplay', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      expect(screen.getByTestId('confidence-interval-display')).toBeInTheDocument();
    });

    it('displays PairwiseConsistencyGrid', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      expect(screen.getByTestId('pairwise-consistency-grid')).toBeInTheDocument();
    });

    it('displays AnomalyList', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      expect(screen.getByTestId('anomaly-list')).toBeInTheDocument();
    });

    it('displays processing footer', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({
        analysis_time_ms: 5,
        algorithm_version: '1.0',
      })} />);

      expect(screen.getByText(/Analysis: 5ms \(v1\.0\)/)).toBeInTheDocument();
    });
  });

  describe('expand/collapse behavior', () => {
    it('is expanded by default', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const content = document.getElementById('cross-validation-content');
      expect(content).not.toHaveClass('max-h-0');
    });

    it('can be collapsed by default', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} defaultExpanded={false} />);

      const content = document.getElementById('cross-validation-content');
      expect(content).toHaveClass('max-h-0');
    });

    it('toggles on header click', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const header = screen.getByRole('button', { name: /Cross-Validation/i });
      fireEvent.click(header);

      const content = document.getElementById('cross-validation-content');
      expect(content).toHaveClass('max-h-0');
    });

    it('toggles on Enter key', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const header = screen.getByRole('button', { name: /Cross-Validation/i });
      fireEvent.keyDown(header, { key: 'Enter' });

      const content = document.getElementById('cross-validation-content');
      expect(content).toHaveClass('max-h-0');
    });

    it('toggles on Space key', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const header = screen.getByRole('button', { name: /Cross-Validation/i });
      fireEvent.keyDown(header, { key: ' ' });

      const content = document.getElementById('cross-validation-content');
      expect(content).toHaveClass('max-h-0');
    });
  });

  describe('penalty display', () => {
    it('does not show penalty when zero', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({ overall_penalty: 0 })} />);

      expect(screen.queryByTestId('penalty-display')).not.toBeInTheDocument();
    });

    it('shows penalty when greater than zero', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({
        overall_penalty: 0.15,
        anomalies: [createAnomaly()],
      })} />);

      expect(screen.getByTestId('penalty-display')).toBeInTheDocument();
      expect(screen.getByText('Cross-validation penalty: -15%')).toBeInTheDocument();
    });

    it('shows correct inconsistency count in penalty', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({
        overall_penalty: 0.20,
        anomalies: [createAnomaly(), createAnomaly()],
      })} />);

      expect(screen.getByText(/Applied due to 2 detected inconsistencies/)).toBeInTheDocument();
    });

    it('uses singular "inconsistency" for single anomaly', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({
        overall_penalty: 0.10,
        anomalies: [createAnomaly()],
      })} />);

      expect(screen.getByText(/Applied due to 1 detected inconsistency/)).toBeInTheDocument();
    });
  });

  describe('temporal consistency (video)', () => {
    it('does not show temporal consistency when not present', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      expect(screen.queryByTestId('temporal-consistency-display')).not.toBeInTheDocument();
    });

    it('shows temporal consistency when present', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({
        temporal_consistency: createTemporalConsistency(),
      })} />);

      expect(screen.getByTestId('temporal-consistency-display')).toBeInTheDocument();
      expect(screen.getByText('Temporal Stability')).toBeInTheDocument();
    });
  });

  describe('validation status variants', () => {
    it('renders pass status correctly', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({ validation_status: 'pass' })} />);

      expect(screen.getByText('Methods Agree')).toBeInTheDocument();
    });

    it('renders warn status correctly', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({ validation_status: 'warn' })} />);

      expect(screen.getByText('Minor Inconsistencies')).toBeInTheDocument();
    });

    it('renders fail status correctly', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation({ validation_status: 'fail' })} />);

      expect(screen.getByText('Methods Disagree')).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has aria-expanded attribute', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const header = screen.getByRole('button', { name: /Cross-Validation/i });
      expect(header).toHaveAttribute('aria-expanded', 'true');
    });

    it('has aria-controls pointing to content', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const header = screen.getByRole('button', { name: /Cross-Validation/i });
      expect(header).toHaveAttribute('aria-controls', 'cross-validation-content');
    });

    it('content has role="region"', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const content = document.getElementById('cross-validation-content');
      expect(content).toHaveAttribute('role', 'region');
    });

    it('content has aria-labelledby', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} />);

      const content = document.getElementById('cross-validation-content');
      expect(content).toHaveAttribute('aria-labelledby', 'cross-validation-header');
    });
  });

  describe('custom className', () => {
    it('applies additional className', () => {
      render(<CrossValidationSection crossValidation={createCrossValidation()} className="custom-class" />);

      const container = screen.getByTestId('cross-validation-section');
      expect(container).toHaveClass('custom-class');
    });
  });
});
