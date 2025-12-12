/**
 * Unit tests for MethodBreakdownSection component (Story 11-1)
 *
 * Tests:
 * - Renders overall confidence summary
 * - Shows method count badge
 * - Renders individual method score bars
 * - Expand/collapse functionality
 * - Handles empty detection data gracefully
 */

import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MethodBreakdownSection } from '../MethodBreakdownSection';
import type { DetectionResults } from '@realitycam/shared';

// Sample detection results for testing
const createSampleDetection = (overrides: Partial<DetectionResults> = {}): DetectionResults => ({
  moire: {
    detected: false,
    confidence: 0.0,
    status: 'completed',
  },
  texture: {
    classification: 'real_scene',
    confidence: 0.92,
    is_likely_recaptured: false,
    status: 'success',
  },
  artifacts: {
    pwm_flicker_detected: false,
    specular_pattern_detected: false,
    halftone_detected: false,
    overall_confidence: 0.0,
    is_likely_artificial: false,
    status: 'success',
  },
  aggregated_confidence: {
    overall_confidence: 0.95,
    confidence_level: 'high',
    method_breakdown: {
      lidar_depth: { available: true, score: 0.98, weight: 0.55, contribution: 0.539, status: 'pass' },
      moire: { available: true, score: 0.0, weight: 0.15, contribution: 0.0, status: 'not_detected' },
      texture: { available: true, score: 0.92, weight: 0.15, contribution: 0.138, status: 'pass' },
      supporting: { available: true, score: 0.79, weight: 0.15, contribution: 0.118, status: 'pass' },
    },
    primary_signal_valid: true,
    supporting_signals_agree: true,
    flags: [],
  },
  computed_at: new Date().toISOString(),
  total_processing_time_ms: 85,
  ...overrides,
});

describe('MethodBreakdownSection', () => {
  describe('rendering', () => {
    it('renders section header with method count', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByText('Detection Methods')).toBeInTheDocument();
      expect(screen.getByText('4 methods')).toBeInTheDocument();
    });

    it('renders overall confidence percentage', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByText('95%')).toBeInTheDocument();
    });

    it('renders confidence badge with correct level', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByTestId('confidence-badge')).toBeInTheDocument();
      expect(screen.getByText('HIGH CONFIDENCE')).toBeInTheDocument();
    });

    it('renders primary signal status indicator', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByText(/Primary:/)).toBeInTheDocument();
      expect(screen.getByText('PASS')).toBeInTheDocument();
    });

    it('renders supporting signals status indicator', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByText(/Supporting:/)).toBeInTheDocument();
      expect(screen.getByText('AGREE')).toBeInTheDocument();
    });

    it('renders all method score bars', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByTestId('score-bar-lidar_depth')).toBeInTheDocument();
      expect(screen.getByTestId('score-bar-moire')).toBeInTheDocument();
      expect(screen.getByTestId('score-bar-texture')).toBeInTheDocument();
      expect(screen.getByTestId('score-bar-supporting')).toBeInTheDocument();
    });

    it('renders processing time info', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByText(/Detection computed in 85ms/)).toBeInTheDocument();
    });

    it('renders with correct testid', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      expect(screen.getByTestId('method-breakdown-section')).toBeInTheDocument();
    });
  });

  describe('expand/collapse behavior', () => {
    it('is expanded by default', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      // Content should be visible
      expect(screen.getByTestId('score-bar-lidar_depth')).toBeVisible();
    });

    it('can be collapsed by default', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} defaultExpanded={false} />);

      // The content container should have max-h-0 class when collapsed
      const content = document.getElementById('method-breakdown-content');
      expect(content).toHaveClass('max-h-0');
    });

    it('toggles expansion on header click', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      const header = screen.getByRole('button', { name: /Detection Methods/i });
      fireEvent.click(header);

      const content = document.getElementById('method-breakdown-content');
      expect(content).toHaveClass('max-h-0');
    });

    it('toggles expansion on Enter key', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      const header = screen.getByRole('button', { name: /Detection Methods/i });
      fireEvent.keyDown(header, { key: 'Enter' });

      const content = document.getElementById('method-breakdown-content');
      expect(content).toHaveClass('max-h-0');
    });

    it('toggles expansion on Space key', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      const header = screen.getByRole('button', { name: /Detection Methods/i });
      fireEvent.keyDown(header, { key: ' ' });

      const content = document.getElementById('method-breakdown-content');
      expect(content).toHaveClass('max-h-0');
    });
  });

  describe('flags display', () => {
    it('renders warning flags when present', () => {
      const detection = createSampleDetection({
        aggregated_confidence: {
          ...createSampleDetection().aggregated_confidence!,
          flags: ['lidar_unavailable', 'low_confidence'],
        },
      });

      render(<MethodBreakdownSection detection={detection} />);

      expect(screen.getByText('lidar_unavailable')).toBeInTheDocument();
      expect(screen.getByText('low_confidence')).toBeInTheDocument();
    });

    it('does not render flags section when empty', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      // With empty flags, the section should not show any flag badges
      expect(screen.queryByText('lidar_unavailable')).not.toBeInTheDocument();
    });
  });

  describe('status indicators', () => {
    it('shows FAIL for primary signal when invalid', () => {
      const detection = createSampleDetection({
        aggregated_confidence: {
          ...createSampleDetection().aggregated_confidence!,
          primary_signal_valid: false,
        },
      });

      render(<MethodBreakdownSection detection={detection} />);

      expect(screen.getByText('FAIL')).toBeInTheDocument();
    });

    it('shows DISAGREE for supporting signals when not agreeing', () => {
      const detection = createSampleDetection({
        aggregated_confidence: {
          ...createSampleDetection().aggregated_confidence!,
          supporting_signals_agree: false,
        },
      });

      render(<MethodBreakdownSection detection={detection} />);

      expect(screen.getByText('DISAGREE')).toBeInTheDocument();
    });
  });

  describe('edge cases', () => {
    it('returns null when no aggregated_confidence', () => {
      const detection = createSampleDetection();
      delete detection.aggregated_confidence;

      const { container } = render(<MethodBreakdownSection detection={detection} />);

      expect(container.firstChild).toBeNull();
    });

    it('handles unavailable methods correctly', () => {
      const baseAggregated = createSampleDetection().aggregated_confidence!;
      const detection = createSampleDetection({
        aggregated_confidence: {
          ...baseAggregated,
          method_breakdown: {
            lidar_depth: baseAggregated.method_breakdown.lidar_depth,
            moire: baseAggregated.method_breakdown.moire,
            texture: baseAggregated.method_breakdown.texture,
            artifacts: { available: false, score: null, weight: 0.15, contribution: 0.0, status: 'unavailable' },
          },
        },
      });

      render(<MethodBreakdownSection detection={detection} />);

      // Should show 3 available methods (artifacts is unavailable)
      expect(screen.getByText('3 methods')).toBeInTheDocument();
    });

    it('handles different confidence levels', () => {
      const detection = createSampleDetection({
        aggregated_confidence: {
          ...createSampleDetection().aggregated_confidence!,
          overall_confidence: 0.45,
          confidence_level: 'low',
        },
      });

      render(<MethodBreakdownSection detection={detection} />);

      expect(screen.getByText('45%')).toBeInTheDocument();
      expect(screen.getByText('LOW CONFIDENCE')).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has correct aria-expanded attribute', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      const header = screen.getByRole('button', { name: /Detection Methods/i });
      expect(header).toHaveAttribute('aria-expanded', 'true');
    });

    it('has aria-controls pointing to content', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      const header = screen.getByRole('button', { name: /Detection Methods/i });
      expect(header).toHaveAttribute('aria-controls', 'method-breakdown-content');
    });

    it('content has role="region"', () => {
      render(<MethodBreakdownSection detection={createSampleDetection()} />);

      const content = document.getElementById('method-breakdown-content');
      expect(content).toHaveAttribute('role', 'region');
    });
  });
});
