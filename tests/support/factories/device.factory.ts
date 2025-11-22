/**
 * Device Factory for RealityCam Tests
 *
 * Creates test device data for frontend and integration tests.
 * Uses faker for realistic data generation.
 */

import { faker } from '@faker-js/faker';

export interface Device {
  id: string;
  platform: 'ios';
  model: string;
  attestationLevel: 'secure_enclave' | 'unverified';
  attestationKeyId: string;
  hasLidar: boolean;
  firstSeenAt: Date;
  lastSeenAt: Date;
}

export interface DeviceRegistrationRequest {
  platform: string;
  model: string;
  attestation: {
    keyId: string;
    attestationObject: string;
  };
}

const IPHONE_PRO_MODELS = [
  'iPhone 12 Pro',
  'iPhone 12 Pro Max',
  'iPhone 13 Pro',
  'iPhone 13 Pro Max',
  'iPhone 14 Pro',
  'iPhone 14 Pro Max',
  'iPhone 15 Pro',
  'iPhone 15 Pro Max',
  'iPhone 16 Pro',
  'iPhone 16 Pro Max',
];

const NON_PRO_MODELS = [
  'iPhone 12',
  'iPhone 13',
  'iPhone 14',
  'iPhone 15',
  'iPhone 16',
];

export class DeviceFactory {
  private overrides: Partial<Device> = {};
  private createdDevices: string[] = [];

  /**
   * Set specific overrides for the device
   */
  with(overrides: Partial<Device>): DeviceFactory {
    this.overrides = { ...this.overrides, ...overrides };
    return this;
  }

  /**
   * Create a device with secure enclave attestation (default)
   */
  withSecureEnclave(): DeviceFactory {
    return this.with({ attestationLevel: 'secure_enclave' });
  }

  /**
   * Create an unattested device (for negative testing)
   */
  unattested(): DeviceFactory {
    return this.with({ attestationLevel: 'unverified' });
  }

  /**
   * Create a device without LiDAR (for negative testing)
   */
  withoutLidar(): DeviceFactory {
    const model = faker.helpers.arrayElement(NON_PRO_MODELS);
    return this.with({ model, hasLidar: false });
  }

  /**
   * Build a device object
   */
  build(): Device {
    const model = this.overrides.model || faker.helpers.arrayElement(IPHONE_PRO_MODELS);
    const hasLidar = this.overrides.hasLidar ?? model.includes('Pro');

    const device: Device = {
      id: faker.string.uuid(),
      platform: 'ios',
      model,
      attestationLevel: 'secure_enclave',
      attestationKeyId: faker.string.alphanumeric(44), // Base64-like key ID
      hasLidar,
      firstSeenAt: faker.date.recent({ days: 30 }),
      lastSeenAt: new Date(),
      ...this.overrides,
    };

    this.createdDevices.push(device.id);
    return device;
  }

  /**
   * Build a device registration request
   */
  buildRequest(): DeviceRegistrationRequest {
    const device = this.build();
    return {
      platform: device.platform,
      model: device.model,
      attestation: {
        keyId: device.attestationKeyId,
        attestationObject: generateMockAttestationObject(),
      },
    };
  }

  /**
   * Create multiple devices
   */
  buildMany(count: number): Device[] {
    return Array.from({ length: count }, () => this.build());
  }

  /**
   * Clean up created devices (call in afterEach)
   */
  async cleanup(): Promise<void> {
    // In integration tests, this would call API to delete devices
    // For unit tests, just clear the tracking array
    this.createdDevices = [];
    this.overrides = {};
  }
}

/**
 * Generate mock DCAppAttest attestation object
 * In real integration tests, use pre-captured fixtures
 */
function generateMockAttestationObject(): string {
  // Base64-encoded mock CBOR attestation
  return Buffer.from('mock-attestation-object-for-testing').toString('base64');
}

// Export singleton factory for convenience
export const deviceFactory = new DeviceFactory();
