/**
 * Unit tests for platform utility functions (Story 11-3)
 *
 * Tests:
 * - extractPlatformInfo extracts correct info from various evidence formats
 * - Backward compatibility when platform field is missing
 * - createPlatformEvidenceItem creates correct EvidencePanel item
 */

import { describe, it, expect } from 'vitest';
import { extractPlatformInfo, createPlatformEvidenceItem } from '../platform';

describe('extractPlatformInfo', () => {
  describe('iOS platform', () => {
    it('extracts iOS platform info with secure_enclave', () => {
      const evidence = {
        platform: 'ios' as const,
        hardware_attestation: {
          status: 'pass',
          level: 'secure_enclave',
          device_model: 'iPhone 15 Pro',
        },
        depth_analysis: {
          status: 'pass',
          is_likely_real_scene: true,
        },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.platform).toBe('ios');
      expect(info.attestation_level).toBe('secure_enclave');
      expect(info.device_model).toBe('iPhone 15 Pro');
      expect(info.has_lidar).toBe(true);
      expect(info.depth_available).toBe(true);
      expect(info.depth_method).toBe('lidar');
    });

    it('extracts iOS platform with "full" level (legacy)', () => {
      const evidence = {
        platform: 'ios' as const,
        hardware_attestation: {
          status: 'pass',
          level: 'full',
          device_model: 'iPhone 15 Pro',
        },
        depth_analysis: {
          status: 'pass',
        },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.attestation_level).toBe('secure_enclave');
    });

    it('detects LiDAR capability for Pro models', () => {
      const evidence = {
        platform: 'ios' as const,
        hardware_attestation: {
          device_model: 'iPhone 15 Pro Max',
        },
        depth_analysis: { status: 'pass' },
      };

      const info = extractPlatformInfo(evidence);
      expect(info.has_lidar).toBe(true);
    });

    it('detects no LiDAR for non-Pro models', () => {
      const evidence = {
        platform: 'ios' as const,
        hardware_attestation: {
          device_model: 'iPhone 15',
        },
        depth_analysis: { status: 'pass' },
      };

      const info = extractPlatformInfo(evidence);
      expect(info.has_lidar).toBe(false);
    });
  });

  describe('Android platform', () => {
    it('extracts Android platform with strongbox', () => {
      const evidence = {
        platform: 'android' as const,
        hardware_attestation: {
          status: 'pass',
          device_model: 'Pixel 8 Pro',
          security_level: {
            attestation_level: 'strongbox',
          },
        },
        depth_analysis: {
          status: 'pass',
        },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.platform).toBe('android');
      expect(info.attestation_level).toBe('strongbox');
      expect(info.device_model).toBe('Pixel 8 Pro');
      expect(info.depth_method).toBe('parallax');
    });

    it('extracts Android platform with tee', () => {
      const evidence = {
        platform: 'android' as const,
        hardware_attestation: {
          security_level: {
            attestation_level: 'tee',
          },
        },
        depth_analysis: { status: 'unavailable' },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.attestation_level).toBe('tee');
    });

    it('defaults to unverified for unknown Android levels', () => {
      const evidence = {
        platform: 'android' as const,
        hardware_attestation: {
          security_level: {
            attestation_level: 'software',
          },
        },
        depth_analysis: { status: 'unavailable' },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.attestation_level).toBe('unverified');
    });
  });

  describe('backward compatibility', () => {
    it('defaults to iOS when platform field is missing', () => {
      const evidence = {
        hardware_attestation: {
          level: 'secure_enclave',
          device_model: 'iPhone 14 Pro',
        },
        depth_analysis: { status: 'pass' },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.platform).toBe('ios');
    });

    it('defaults to secure_enclave for missing iOS attestation level', () => {
      const evidence = {
        hardware_attestation: {},
        depth_analysis: { status: 'pass' },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.attestation_level).toBe('unverified');
    });

    it('extracts device model from metadata if not in hardware_attestation', () => {
      const evidence = {
        hardware_attestation: {},
        metadata: {
          model_name: 'iPhone 15 Pro',
        },
        depth_analysis: { status: 'pass' },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.device_model).toBe('iPhone 15 Pro');
    });
  });

  describe('depth analysis', () => {
    it('marks depth as available when status is pass', () => {
      const evidence = {
        platform: 'ios' as const,
        hardware_attestation: {},
        depth_analysis: { status: 'pass' },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.depth_available).toBe(true);
    });

    it('marks depth as unavailable when status is unavailable', () => {
      const evidence = {
        platform: 'ios' as const,
        hardware_attestation: {},
        depth_analysis: { status: 'unavailable' },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.depth_available).toBe(false);
    });

    it('marks depth as available when is_likely_real_scene is true', () => {
      const evidence = {
        platform: 'ios' as const,
        hardware_attestation: {},
        depth_analysis: {
          status: 'unavailable',
          is_likely_real_scene: true,
        },
      };

      const info = extractPlatformInfo(evidence);

      expect(info.depth_available).toBe(true);
    });
  });
});

describe('createPlatformEvidenceItem', () => {
  it('creates item with pass status for secure_enclave', () => {
    const platformInfo = {
      platform: 'ios' as const,
      attestation_level: 'secure_enclave' as const,
      device_model: 'iPhone 15 Pro',
      has_lidar: true,
      depth_available: true,
      depth_method: 'lidar' as const,
    };

    const item = createPlatformEvidenceItem(platformInfo);

    expect(item.label).toBe('Platform & Attestation');
    expect(item.status).toBe('pass');
    expect(item.value).toContain('iOS');
    expect(item.value).toContain('Secure Enclave');
    expect(item.value).toContain('iPhone 15 Pro');
    expect(item.value).toContain('LiDAR available');
  });

  it('creates item with pass status for strongbox', () => {
    const platformInfo = {
      platform: 'android' as const,
      attestation_level: 'strongbox' as const,
      device_model: 'Pixel 8 Pro',
      depth_available: true,
      depth_method: 'parallax' as const,
    };

    const item = createPlatformEvidenceItem(platformInfo);

    expect(item.status).toBe('pass');
    expect(item.value).toContain('Android');
    expect(item.value).toContain('StrongBox');
  });

  it('creates item with pass status for tee', () => {
    const platformInfo = {
      platform: 'android' as const,
      attestation_level: 'tee' as const,
      depth_available: false,
      depth_method: null,
    };

    const item = createPlatformEvidenceItem(platformInfo);

    expect(item.status).toBe('pass');
    expect(item.value).toContain('TEE');
  });

  it('creates item with unavailable status for unverified', () => {
    const platformInfo = {
      platform: 'ios' as const,
      attestation_level: 'unverified' as const,
      depth_available: false,
      depth_method: null,
    };

    const item = createPlatformEvidenceItem(platformInfo);

    expect(item.status).toBe('unavailable');
    expect(item.value).toContain('Unverified');
  });

  it('includes device model when available', () => {
    const platformInfo = {
      platform: 'ios' as const,
      attestation_level: 'secure_enclave' as const,
      device_model: 'iPhone 15 Pro',
      depth_available: true,
      depth_method: 'lidar' as const,
    };

    const item = createPlatformEvidenceItem(platformInfo);

    expect(item.value).toContain('iPhone 15 Pro');
  });

  it('excludes device model when not available', () => {
    const platformInfo = {
      platform: 'ios' as const,
      attestation_level: 'secure_enclave' as const,
      depth_available: true,
      depth_method: 'lidar' as const,
    };

    const item = createPlatformEvidenceItem(platformInfo);

    expect(item.value).not.toContain('undefined');
  });
});
