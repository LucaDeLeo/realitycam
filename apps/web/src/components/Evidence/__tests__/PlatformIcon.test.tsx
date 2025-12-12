/**
 * Unit tests for PlatformIcon component (Story 11-3)
 *
 * Tests:
 * - Renders correct icon for iOS platform
 * - Renders correct icon for Android platform
 * - Applies correct size classes
 * - Icons have aria-hidden for accessibility
 */

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { PlatformIcon, AppleIcon, AndroidIcon } from '../PlatformIcon';

describe('PlatformIcon', () => {
  describe('platform rendering', () => {
    it('renders Apple icon for iOS platform', () => {
      render(<PlatformIcon platform="ios" />);
      expect(screen.getByTestId('apple-icon')).toBeInTheDocument();
    });

    it('renders Android icon for Android platform', () => {
      render(<PlatformIcon platform="android" />);
      expect(screen.getByTestId('android-icon')).toBeInTheDocument();
    });
  });

  describe('size variants', () => {
    it('applies small size class', () => {
      render(<PlatformIcon platform="ios" size="sm" />);
      const icon = screen.getByTestId('apple-icon');
      expect(icon).toHaveClass('w-3', 'h-3');
    });

    it('applies medium size class by default', () => {
      render(<PlatformIcon platform="ios" />);
      const icon = screen.getByTestId('apple-icon');
      expect(icon).toHaveClass('w-4', 'h-4');
    });

    it('applies large size class', () => {
      render(<PlatformIcon platform="ios" size="lg" />);
      const icon = screen.getByTestId('apple-icon');
      expect(icon).toHaveClass('w-5', 'h-5');
    });
  });

  describe('accessibility', () => {
    it('Apple icon has aria-hidden', () => {
      render(<PlatformIcon platform="ios" />);
      const icon = screen.getByTestId('apple-icon');
      expect(icon).toHaveAttribute('aria-hidden', 'true');
    });

    it('Android icon has aria-hidden', () => {
      render(<PlatformIcon platform="android" />);
      const icon = screen.getByTestId('android-icon');
      expect(icon).toHaveAttribute('aria-hidden', 'true');
    });
  });

  describe('custom className', () => {
    it('applies custom className to iOS icon', () => {
      render(<PlatformIcon platform="ios" className="text-red-500" />);
      const icon = screen.getByTestId('apple-icon');
      expect(icon).toHaveClass('text-red-500');
    });

    it('applies custom className to Android icon', () => {
      render(<PlatformIcon platform="android" className="text-green-500" />);
      const icon = screen.getByTestId('android-icon');
      expect(icon).toHaveClass('text-green-500');
    });
  });
});

describe('AppleIcon', () => {
  it('renders SVG element', () => {
    render(<AppleIcon />);
    const icon = screen.getByTestId('apple-icon');
    expect(icon.tagName).toBe('svg');
  });
});

describe('AndroidIcon', () => {
  it('renders SVG element', () => {
    render(<AndroidIcon />);
    const icon = screen.getByTestId('android-icon');
    expect(icon.tagName).toBe('svg');
  });
});
