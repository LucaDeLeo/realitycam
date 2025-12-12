/**
 * Unit tests for MethodScoreBar component (Story 11-1)
 *
 * Tests:
 * - Renders correctly for all status states
 * - Color coding based on status strings
 * - Handles unavailable state with gray styling
 * - Displays weight indicator
 * - Accessible progress bar semantics
 */

import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MethodScoreBar, getMethodStatusColor, getMethodDisplayName } from '../MethodScoreBar';

describe('MethodScoreBar', () => {
  // Helper to render with default props
  const renderScoreBar = (props = {}) => {
    const defaultProps = {
      methodKey: 'lidar_depth',
      score: 0.95,
      weight: 0.55,
      available: true,
      status: 'pass' as const,
    };
    return render(<MethodScoreBar {...defaultProps} {...props} />);
  };

  describe('rendering', () => {
    it('renders method name and score', () => {
      renderScoreBar();

      expect(screen.getByText('LiDAR Depth')).toBeInTheDocument();
      expect(screen.getByText('95%')).toBeInTheDocument();
    });

    it('renders weight indicator', () => {
      renderScoreBar();

      expect(screen.getByText('(55% weight)')).toBeInTheDocument();
    });

    it('renders progress bar with correct aria attributes', () => {
      renderScoreBar();

      const progressBar = screen.getByRole('progressbar');
      expect(progressBar).toHaveAttribute('aria-valuenow', '95');
      expect(progressBar).toHaveAttribute('aria-valuemin', '0');
      expect(progressBar).toHaveAttribute('aria-valuemax', '100');
    });

    it('renders with correct testid', () => {
      renderScoreBar({ methodKey: 'moire' });

      expect(screen.getByTestId('score-bar-moire')).toBeInTheDocument();
    });
  });

  describe('status colors', () => {
    it('renders green bar for pass status', () => {
      renderScoreBar({ status: 'pass' });

      const fill = screen.getByTestId('score-bar-fill');
      expect(fill).toHaveClass('bg-green-500');
    });

    it('renders green bar for not_detected status (good for moire/artifacts)', () => {
      renderScoreBar({ status: 'not_detected', score: 0.0, methodKey: 'moire' });

      const fill = screen.getByTestId('score-bar-fill');
      expect(fill).toHaveClass('bg-green-500');
    });

    it('renders yellow bar for warn status', () => {
      renderScoreBar({ status: 'warn', score: 0.6 });

      const fill = screen.getByTestId('score-bar-fill');
      expect(fill).toHaveClass('bg-yellow-500');
    });

    it('renders red bar for fail status', () => {
      renderScoreBar({ status: 'fail', score: 0.3 });

      const fill = screen.getByTestId('score-bar-fill');
      expect(fill).toHaveClass('bg-red-500');
    });

    it('renders gray bar for unavailable status', () => {
      renderScoreBar({ status: 'unavailable', score: null, available: false });

      const fill = screen.getByTestId('score-bar-fill');
      expect(fill).toHaveClass('bg-zinc-400');
    });
  });

  describe('unavailable state', () => {
    it('shows N/A for unavailable method', () => {
      renderScoreBar({ available: false, score: null, status: 'unavailable' });

      expect(screen.getByText('N/A')).toBeInTheDocument();
    });

    it('shows Unavailable description', () => {
      renderScoreBar({ available: false, score: null, status: 'unavailable' });

      expect(screen.getByText('Unavailable')).toBeInTheDocument();
    });

    it('renders empty progress bar for unavailable method', () => {
      renderScoreBar({ available: false, score: null, status: 'unavailable' });

      const fill = screen.getByTestId('score-bar-fill');
      expect(fill).toHaveStyle({ width: '0%' });
    });
  });

  describe('special status descriptions', () => {
    it('shows "No patterns detected (good)" for moire not_detected', () => {
      renderScoreBar({ methodKey: 'moire', status: 'not_detected', score: 0.0 });

      expect(screen.getByText('No patterns detected (good)')).toBeInTheDocument();
    });

    it('shows "No patterns detected (good)" for artifacts not_detected', () => {
      renderScoreBar({ methodKey: 'artifacts', status: 'not_detected', score: 0.0 });

      expect(screen.getByText('No patterns detected (good)')).toBeInTheDocument();
    });
  });

  describe('interactions', () => {
    it('calls onClick when clicked', () => {
      const handleClick = vi.fn();
      renderScoreBar({ onClick: handleClick });

      fireEvent.click(screen.getByTestId('score-bar-lidar_depth'));
      expect(handleClick).toHaveBeenCalledTimes(1);
    });

    it('calls onClick on Enter key', () => {
      const handleClick = vi.fn();
      renderScoreBar({ onClick: handleClick });

      fireEvent.keyDown(screen.getByTestId('score-bar-lidar_depth'), { key: 'Enter' });
      expect(handleClick).toHaveBeenCalledTimes(1);
    });

    it('calls onClick on Space key', () => {
      const handleClick = vi.fn();
      renderScoreBar({ onClick: handleClick });

      fireEvent.keyDown(screen.getByTestId('score-bar-lidar_depth'), { key: ' ' });
      expect(handleClick).toHaveBeenCalledTimes(1);
    });

    it('shows active indicator when isActive is true', () => {
      const { container } = renderScoreBar({ isActive: true });

      // Active indicator is a blue bar
      const activeIndicator = container.querySelector('.bg-blue-500');
      expect(activeIndicator).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has correct role and aria-label', () => {
      renderScoreBar();

      const element = screen.getByTestId('score-bar-lidar_depth');
      expect(element).toHaveAttribute('role', 'button');
      expect(element).toHaveAttribute('aria-label');
    });

    it('is focusable with tabIndex', () => {
      renderScoreBar();

      const element = screen.getByTestId('score-bar-lidar_depth');
      expect(element).toHaveAttribute('tabIndex', '0');
    });
  });
});

describe('getMethodStatusColor', () => {
  it('returns green for pass status', () => {
    expect(getMethodStatusColor('pass')).toContain('bg-green-500');
  });

  it('returns green for not_detected status', () => {
    expect(getMethodStatusColor('not_detected')).toContain('bg-green-500');
  });

  it('returns yellow for warn status', () => {
    expect(getMethodStatusColor('warn')).toContain('bg-yellow-500');
  });

  it('returns red for fail status', () => {
    expect(getMethodStatusColor('fail')).toContain('bg-red-500');
  });

  it('returns gray for unavailable status', () => {
    expect(getMethodStatusColor('unavailable')).toContain('bg-zinc-400');
  });
});

describe('getMethodDisplayName', () => {
  it('returns correct display name for known methods', () => {
    expect(getMethodDisplayName('lidar_depth')).toBe('LiDAR Depth');
    expect(getMethodDisplayName('moire')).toBe('Moire Detection');
    expect(getMethodDisplayName('texture')).toBe('Texture Analysis');
    expect(getMethodDisplayName('artifacts')).toBe('Artifact Detection');
    expect(getMethodDisplayName('supporting')).toBe('Supporting Signals');
  });

  it('returns method key for unknown methods', () => {
    expect(getMethodDisplayName('unknown_method')).toBe('unknown_method');
  });
});
