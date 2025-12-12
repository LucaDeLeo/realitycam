/**
 * Unit tests for PlatformBadge component (Story 11-3)
 *
 * Tests:
 * - Renders platform name and attestation level
 * - Supports compact and full variants
 * - Color coding based on attestation level
 * - Click behavior for tooltip
 * - Accessibility attributes
 */

import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { PlatformBadge, CompactPlatformBadge, getPlatformDisplayName } from '../PlatformBadge';
import type { PlatformInfo } from '@realitycam/shared';

const mockPlatformInfoiOS: PlatformInfo = {
  platform: 'ios',
  attestation_level: 'secure_enclave',
  device_model: 'iPhone 15 Pro',
  has_lidar: true,
  depth_available: true,
  depth_method: 'lidar',
};

const mockPlatformInfoAndroid: PlatformInfo = {
  platform: 'android',
  attestation_level: 'strongbox',
  device_model: 'Pixel 8 Pro',
  depth_available: true,
  depth_method: 'parallax',
};

const mockPlatformInfoTEE: PlatformInfo = {
  platform: 'android',
  attestation_level: 'tee',
  depth_available: false,
  depth_method: null,
};

const mockPlatformInfoUnverified: PlatformInfo = {
  platform: 'ios',
  attestation_level: 'unverified',
  depth_available: false,
  depth_method: null,
};

describe('PlatformBadge', () => {
  describe('full variant', () => {
    it('renders iOS platform name', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      expect(screen.getByText('iOS')).toBeInTheDocument();
    });

    it('renders attestation level', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      expect(screen.getByText('Secure Enclave')).toBeInTheDocument();
    });

    it('renders Android platform name', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoAndroid} />);
      expect(screen.getByText('Android')).toBeInTheDocument();
    });

    it('renders StrongBox attestation', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoAndroid} />);
      expect(screen.getByText('StrongBox')).toBeInTheDocument();
    });

    it('renders TEE attestation', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoTEE} />);
      expect(screen.getByText('TEE')).toBeInTheDocument();
    });

    it('renders Unverified attestation', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoUnverified} />);
      expect(screen.getByText('Unverified')).toBeInTheDocument();
    });
  });

  describe('compact variant', () => {
    it('shows only platform name', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} variant="compact" />);
      expect(screen.getByText('iOS')).toBeInTheDocument();
      expect(screen.queryByText('Secure Enclave')).not.toBeInTheDocument();
    });
  });

  describe('color coding', () => {
    it('applies green for secure_enclave', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      expect(badge).toHaveClass('bg-green-100');
    });

    it('applies green for strongbox', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoAndroid} />);
      const badge = screen.getByTestId('platform-badge');
      expect(badge).toHaveClass('bg-green-100');
    });

    it('applies blue for tee', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoTEE} />);
      const badge = screen.getByTestId('platform-badge');
      expect(badge).toHaveClass('bg-blue-100');
    });

    it('applies yellow for unverified', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoUnverified} />);
      const badge = screen.getByTestId('platform-badge');
      expect(badge).toHaveClass('bg-yellow-100');
    });
  });

  describe('tooltip interaction', () => {
    it('shows tooltip on click', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      fireEvent.click(badge);
      expect(screen.getByTestId('platform-tooltip')).toBeInTheDocument();
    });

    it('hides tooltip on second click', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      fireEvent.click(badge);
      fireEvent.click(badge);
      expect(screen.queryByTestId('platform-tooltip')).not.toBeInTheDocument();
    });

    it('does not show tooltip when showTooltip is false', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} showTooltip={false} />);
      const badge = screen.getByTestId('platform-badge');
      fireEvent.click(badge);
      expect(screen.queryByTestId('platform-tooltip')).not.toBeInTheDocument();
    });
  });

  describe('keyboard interaction', () => {
    it('toggles tooltip on Enter key', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      fireEvent.keyDown(badge, { key: 'Enter' });
      expect(screen.getByTestId('platform-tooltip')).toBeInTheDocument();
    });

    it('toggles tooltip on Space key', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      fireEvent.keyDown(badge, { key: ' ' });
      expect(screen.getByTestId('platform-tooltip')).toBeInTheDocument();
    });

    it('closes tooltip on Escape key', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      fireEvent.click(badge);
      fireEvent.keyDown(badge, { key: 'Escape' });
      expect(screen.queryByTestId('platform-tooltip')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has descriptive aria-label for full variant', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      expect(badge).toHaveAttribute('aria-label', 'Platform: iOS with Secure Enclave attestation');
    });

    it('has descriptive aria-label for compact variant', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} variant="compact" />);
      const badge = screen.getByTestId('platform-badge');
      expect(badge).toHaveAttribute('aria-label', 'Platform: iOS');
    });

    it('has aria-expanded attribute when tooltip enabled', () => {
      render(<PlatformBadge platformInfo={mockPlatformInfoiOS} />);
      const badge = screen.getByTestId('platform-badge');
      expect(badge).toHaveAttribute('aria-expanded', 'false');
    });
  });
});

describe('CompactPlatformBadge', () => {
  it('renders iOS platform name', () => {
    render(<CompactPlatformBadge platform="ios" />);
    expect(screen.getByText('iOS')).toBeInTheDocument();
  });

  it('renders Android platform name', () => {
    render(<CompactPlatformBadge platform="android" />);
    expect(screen.getByText('Android')).toBeInTheDocument();
  });

  it('has correct testid', () => {
    render(<CompactPlatformBadge platform="ios" />);
    expect(screen.getByTestId('compact-platform-badge')).toBeInTheDocument();
  });

  it('applies neutral gray styling', () => {
    render(<CompactPlatformBadge platform="ios" />);
    const badge = screen.getByTestId('compact-platform-badge');
    expect(badge).toHaveClass('bg-zinc-100');
  });

  it('has aria-label', () => {
    render(<CompactPlatformBadge platform="ios" />);
    const badge = screen.getByTestId('compact-platform-badge');
    expect(badge).toHaveAttribute('aria-label', 'Platform: iOS');
  });
});

describe('getPlatformDisplayName', () => {
  it('returns iOS for ios', () => {
    expect(getPlatformDisplayName('ios')).toBe('iOS');
  });

  it('returns Android for android', () => {
    expect(getPlatformDisplayName('android')).toBe('Android');
  });
});
