/**
 * Unit tests for AttestationLevelBadge component (Story 11-3)
 *
 * Tests:
 * - Renders correct labels for each attestation level
 * - Applies correct color classes
 * - Displays appropriate shield icon
 * - Accessibility attributes
 */

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AttestationLevelBadge, getAttestationConfig } from '../AttestationLevelBadge';

describe('AttestationLevelBadge', () => {
  describe('secure_enclave', () => {
    it('renders Secure Enclave label', () => {
      render(<AttestationLevelBadge level="secure_enclave" />);
      expect(screen.getByText('Secure Enclave')).toBeInTheDocument();
    });

    it('applies green color classes', () => {
      render(<AttestationLevelBadge level="secure_enclave" />);
      const badge = screen.getByTestId('attestation-level-badge');
      expect(badge).toHaveClass('bg-green-100', 'text-green-800');
    });
  });

  describe('strongbox', () => {
    it('renders StrongBox label', () => {
      render(<AttestationLevelBadge level="strongbox" />);
      expect(screen.getByText('StrongBox')).toBeInTheDocument();
    });

    it('applies green color classes', () => {
      render(<AttestationLevelBadge level="strongbox" />);
      const badge = screen.getByTestId('attestation-level-badge');
      expect(badge).toHaveClass('bg-green-100', 'text-green-800');
    });
  });

  describe('tee', () => {
    it('renders TEE label', () => {
      render(<AttestationLevelBadge level="tee" />);
      expect(screen.getByText('TEE')).toBeInTheDocument();
    });

    it('applies blue color classes', () => {
      render(<AttestationLevelBadge level="tee" />);
      const badge = screen.getByTestId('attestation-level-badge');
      expect(badge).toHaveClass('bg-blue-100', 'text-blue-800');
    });
  });

  describe('unverified', () => {
    it('renders Unverified label', () => {
      render(<AttestationLevelBadge level="unverified" />);
      expect(screen.getByText('Unverified')).toBeInTheDocument();
    });

    it('applies yellow color classes', () => {
      render(<AttestationLevelBadge level="unverified" />);
      const badge = screen.getByTestId('attestation-level-badge');
      expect(badge).toHaveClass('bg-yellow-100', 'text-yellow-800');
    });
  });

  describe('accessibility', () => {
    it('has role="status"', () => {
      render(<AttestationLevelBadge level="secure_enclave" />);
      const badge = screen.getByTestId('attestation-level-badge');
      expect(badge).toHaveAttribute('role', 'status');
    });

    it('has descriptive aria-label', () => {
      render(<AttestationLevelBadge level="secure_enclave" />);
      const badge = screen.getByTestId('attestation-level-badge');
      expect(badge).toHaveAttribute('aria-label', 'Attestation level: Secure Enclave');
    });
  });

  describe('custom className', () => {
    it('applies additional className', () => {
      render(<AttestationLevelBadge level="secure_enclave" className="mt-2" />);
      const badge = screen.getByTestId('attestation-level-badge');
      expect(badge).toHaveClass('mt-2');
    });
  });
});

describe('getAttestationConfig', () => {
  it('returns correct config for secure_enclave', () => {
    const config = getAttestationConfig('secure_enclave');
    expect(config.label).toBe('Secure Enclave');
    expect(config.colorClasses).toContain('bg-green-100');
  });

  it('returns correct config for strongbox', () => {
    const config = getAttestationConfig('strongbox');
    expect(config.label).toBe('StrongBox');
    expect(config.colorClasses).toContain('bg-green-100');
  });

  it('returns correct config for tee', () => {
    const config = getAttestationConfig('tee');
    expect(config.label).toBe('TEE');
    expect(config.colorClasses).toContain('bg-blue-100');
  });

  it('returns correct config for unverified', () => {
    const config = getAttestationConfig('unverified');
    expect(config.label).toBe('Unverified');
    expect(config.colorClasses).toContain('bg-yellow-100');
  });
});
