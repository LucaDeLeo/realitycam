/**
 * Unit tests for MethodTooltip component (Story 11-1)
 *
 * Tests:
 * - Displays method details correctly
 * - Shows raw score, weight, and contribution
 * - Renders method-specific details
 * - Closes on outside click
 * - Closes on Escape key
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MethodTooltip } from '../MethodTooltip';
import type { DetectionMethodResult } from '@realitycam/shared';

// Sample method result for testing
const createMethodResult = (overrides: Partial<DetectionMethodResult> = {}): DetectionMethodResult => ({
  available: true,
  score: 0.95,
  weight: 0.55,
  contribution: 0.522,
  status: 'pass',
  ...overrides,
});

describe('MethodTooltip', () => {
  const onClose = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers({ shouldAdvanceTime: true });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('visibility', () => {
    it('renders nothing when not visible', () => {
      const { container } = render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={false}
          onClose={onClose}
        />
      );

      expect(container.firstChild).toBeNull();
    });

    it('renders tooltip when visible', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByRole('tooltip')).toBeInTheDocument();
    });

    it('renders with correct testid', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByTestId('tooltip-lidar_depth')).toBeInTheDocument();
    });
  });

  describe('content display', () => {
    it('displays method name', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText('LiDAR Depth')).toBeInTheDocument();
    });

    it('displays method description', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText(/LiDAR depth data/)).toBeInTheDocument();
    });

    it('displays raw score formatted correctly', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult({ score: 0.95 })}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText('0.95')).toBeInTheDocument();
    });

    it('displays weight as percentage', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult({ weight: 0.55 })}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText('55%')).toBeInTheDocument();
    });

    it('displays contribution formatted correctly', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult({ contribution: 0.522 })}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText('52.2%')).toBeInTheDocument();
    });
  });

  describe('unavailable method', () => {
    it('shows N/A for unavailable method score', () => {
      render(
        <MethodTooltip
          methodKey="texture"
          methodResult={createMethodResult({ available: false, score: null })}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getAllByText('N/A').length).toBeGreaterThan(0);
    });

    it('shows unavailable explanation', () => {
      render(
        <MethodTooltip
          methodKey="texture"
          methodResult={createMethodResult({ available: false, score: null })}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText(/not available for this capture/)).toBeInTheDocument();
    });
  });

  describe('method-specific details', () => {
    it('displays moire detection details', () => {
      render(
        <MethodTooltip
          methodKey="moire"
          methodResult={createMethodResult()}
          methodDetails={{
            moire: {
              detected: true,
              confidence: 0.85,
              screen_type: 'lcd',
              status: 'completed',
            },
          }}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText('Moire Analysis')).toBeInTheDocument();
      expect(screen.getByText('Yes')).toBeInTheDocument();
      // The text is lowercase with uppercase CSS class applied visually
      expect(screen.getByText('lcd')).toBeInTheDocument();
    });

    it('displays texture analysis details', () => {
      render(
        <MethodTooltip
          methodKey="texture"
          methodResult={createMethodResult()}
          methodDetails={{
            texture: {
              classification: 'real_scene',
              confidence: 0.92,
              is_likely_recaptured: false,
              status: 'success',
            },
          }}
          isVisible={true}
          onClose={onClose}
        />
      );

      // Use getAllByText since "Texture Analysis" appears twice (as header and details section)
      expect(screen.getAllByText('Texture Analysis').length).toBeGreaterThan(0);
      expect(screen.getByText('Real Scene')).toBeInTheDocument();
    });

    it('displays artifact detection details', () => {
      render(
        <MethodTooltip
          methodKey="artifacts"
          methodResult={createMethodResult()}
          methodDetails={{
            artifacts: {
              pwm_flicker_detected: true,
              specular_pattern_detected: false,
              halftone_detected: false,
              overall_confidence: 0.75,
              is_likely_artificial: true,
              status: 'success',
            },
          }}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText('Artifact Flags')).toBeInTheDocument();
      expect(screen.getByText('Detected')).toBeInTheDocument();
    });

    it('shows "No artifacts detected (good)" when none detected', () => {
      render(
        <MethodTooltip
          methodKey="artifacts"
          methodResult={createMethodResult()}
          methodDetails={{
            artifacts: {
              pwm_flicker_detected: false,
              specular_pattern_detected: false,
              halftone_detected: false,
              overall_confidence: 0.0,
              is_likely_artificial: false,
              status: 'success',
            },
          }}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByText('No artifacts detected (good)')).toBeInTheDocument();
    });
  });

  describe('close behavior', () => {
    it('calls onClose when close button clicked', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      const closeButton = screen.getByLabelText('Close tooltip');
      fireEvent.click(closeButton);

      expect(onClose).toHaveBeenCalledTimes(1);
    });

    it('calls onClose on Escape key', async () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      fireEvent.keyDown(document, { key: 'Escape' });

      expect(onClose).toHaveBeenCalledTimes(1);
    });

    it('calls onClose on outside click after delay', async () => {
      render(
        <div>
          <div data-testid="outside">Outside element</div>
          <MethodTooltip
            methodKey="lidar_depth"
            methodResult={createMethodResult()}
            isVisible={true}
            onClose={onClose}
          />
        </div>
      );

      // Advance timers to allow the click handler to be attached
      vi.advanceTimersByTime(50);

      // Click outside the tooltip
      fireEvent.mouseDown(screen.getByTestId('outside'));

      expect(onClose).toHaveBeenCalledTimes(1);
    });
  });

  describe('accessibility', () => {
    it('has role="tooltip"', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByRole('tooltip')).toBeInTheDocument();
    });

    it('has aria-live for accessibility', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByRole('tooltip')).toHaveAttribute('aria-live', 'polite');
    });

    it('close button has aria-label', () => {
      render(
        <MethodTooltip
          methodKey="lidar_depth"
          methodResult={createMethodResult()}
          isVisible={true}
          onClose={onClose}
        />
      );

      expect(screen.getByLabelText('Close tooltip')).toBeInTheDocument();
    });
  });
});
