/**
 * Unit tests for PlatformTooltip component (Story 11-3)
 *
 * Tests:
 * - Displays platform details correctly
 * - Shows device model when available
 * - Shows attestation method explanation
 * - Shows LiDAR status for iOS
 * - Shows depth capability
 * - Close behavior (button, escape key, outside click)
 * - Accessibility
 */

import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { PlatformTooltip } from '../PlatformTooltip';
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
  has_lidar: false,
  depth_available: false,
  depth_method: null,
};

describe('PlatformTooltip', () => {
  describe('visibility', () => {
    it('renders when isVisible is true', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByTestId('platform-tooltip')).toBeInTheDocument();
    });

    it('does not render when isVisible is false', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={false}
          onClose={vi.fn()}
        />
      );
      expect(screen.queryByTestId('platform-tooltip')).not.toBeInTheDocument();
    });
  });

  describe('platform display', () => {
    it('shows Apple iOS for ios platform', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText('Apple iOS')).toBeInTheDocument();
    });

    it('shows Google Android for android platform', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoAndroid}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText('Google Android')).toBeInTheDocument();
    });
  });

  describe('device model', () => {
    it('shows device model when available', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText('iPhone 15 Pro')).toBeInTheDocument();
    });

    it('does not show device model section when not available', () => {
      const infoWithoutModel: PlatformInfo = {
        ...mockPlatformInfoiOS,
        device_model: undefined,
      };
      render(
        <PlatformTooltip
          platformInfo={infoWithoutModel}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.queryByText('iPhone 15 Pro')).not.toBeInTheDocument();
    });
  });

  describe('attestation explanations', () => {
    it('shows Secure Enclave explanation', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText(/Hardware-backed key stored in dedicated security chip/)).toBeInTheDocument();
    });

    it('shows StrongBox explanation', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoAndroid}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText(/Hardware Security Module/)).toBeInTheDocument();
    });

    it('shows TEE explanation', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoTEE}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText(/Trusted Execution Environment/)).toBeInTheDocument();
    });

    it('shows unverified explanation', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoUnverified}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText(/Device attestation could not be verified/)).toBeInTheDocument();
    });
  });

  describe('depth capability', () => {
    it('shows depth available with LiDAR', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText(/LiDAR depth sensor available/)).toBeInTheDocument();
    });

    it('shows depth unavailable message', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoUnverified}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText(/No depth analysis available/)).toBeInTheDocument();
    });
  });

  describe('LiDAR status (iOS only)', () => {
    it('shows LiDAR available for iOS Pro', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText('LiDAR Sensor')).toBeInTheDocument();
      expect(screen.getByText('Available (Pro model)')).toBeInTheDocument();
    });

    it('shows LiDAR not available for iOS non-Pro', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoUnverified}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.getByText('Not available')).toBeInTheDocument();
    });

    it('does not show LiDAR section for Android', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoAndroid}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      expect(screen.queryByText('LiDAR Sensor')).not.toBeInTheDocument();
    });
  });

  describe('close behavior', () => {
    it('calls onClose when close button clicked', () => {
      const onClose = vi.fn();
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={onClose}
        />
      );
      const closeButton = screen.getByRole('button', { name: /close/i });
      fireEvent.click(closeButton);
      expect(onClose).toHaveBeenCalled();
    });

    it('calls onClose on Escape key', () => {
      const onClose = vi.fn();
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={onClose}
        />
      );
      fireEvent.keyDown(document, { key: 'Escape' });
      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('accessibility', () => {
    it('has role="tooltip"', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      const tooltip = screen.getByTestId('platform-tooltip');
      expect(tooltip).toHaveAttribute('role', 'tooltip');
    });

    it('has aria-live="polite"', () => {
      render(
        <PlatformTooltip
          platformInfo={mockPlatformInfoiOS}
          isVisible={true}
          onClose={vi.fn()}
        />
      );
      const tooltip = screen.getByTestId('platform-tooltip');
      expect(tooltip).toHaveAttribute('aria-live', 'polite');
    });
  });
});
