/**
 * Capture Factory for RealityCam Tests
 *
 * Creates test capture data with realistic photos, depth maps, and metadata.
 */

import { faker } from '@faker-js/faker';

export interface Capture {
  id: string;
  deviceId: string;
  photoHash: string;
  capturedAt: Date;
  uploadedAt: Date;
  status: 'pending' | 'processing' | 'complete' | 'failed';
  confidenceLevel: 'high' | 'medium' | 'low' | 'suspicious';
  metadata: CaptureMetadata;
  evidence?: Evidence;
}

export interface CaptureMetadata {
  capturedAt: Date;
  deviceModel: string;
  latitude?: number;
  longitude?: number;
}

export interface Evidence {
  hardwareAttestation: {
    status: 'pass' | 'fail' | 'unavailable';
    level: string;
    deviceModel: string;
  };
  depthAnalysis: {
    status: 'pass' | 'fail' | 'unavailable';
    depthVariance: number;
    depthLayers: number;
    edgeCoherence: number;
    isLikelyRealScene: boolean;
  };
  metadata: {
    timestampValid: boolean;
    modelHasLidar: boolean;
  };
}

export interface DepthMap {
  data: Float32Array;
  width: number;
  height: number;
}

export class CaptureFactory {
  private overrides: Partial<Capture> = {};
  private depthType: 'real_scene' | 'flat' | 'custom' = 'real_scene';
  private createdCaptures: string[] = [];

  /**
   * Set specific overrides
   */
  with(overrides: Partial<Capture>): CaptureFactory {
    this.overrides = { ...this.overrides, ...overrides };
    return this;
  }

  /**
   * Associate capture with a specific device
   */
  forDevice(deviceId: string): CaptureFactory {
    return this.with({ deviceId });
  }

  /**
   * Set capture timestamp
   */
  capturedAt(date: Date): CaptureFactory {
    return this.with({ capturedAt: date });
  }

  /**
   * Create capture with realistic 3D scene depth
   */
  withRealSceneDepth(): CaptureFactory {
    this.depthType = 'real_scene';
    return this;
  }

  /**
   * Create capture with flat depth (simulating photo of screen)
   */
  withFlatDepth(): CaptureFactory {
    this.depthType = 'flat';
    return this;
  }

  /**
   * Create capture without location data
   */
  withoutLocation(): CaptureFactory {
    return this.with({
      metadata: {
        ...this.overrides.metadata,
        capturedAt: this.overrides.capturedAt || new Date(),
        deviceModel: this.overrides.metadata?.deviceModel || 'iPhone 15 Pro',
        latitude: undefined,
        longitude: undefined,
      },
    });
  }

  /**
   * Build a capture object
   */
  build(): Capture {
    const capturedAt = this.overrides.capturedAt || faker.date.recent({ days: 1 });
    const isRealScene = this.depthType === 'real_scene';

    const capture: Capture = {
      id: faker.string.uuid(),
      deviceId: faker.string.uuid(),
      photoHash: faker.string.hexadecimal({ length: 64, casing: 'lower' }).slice(2),
      capturedAt,
      uploadedAt: new Date(),
      status: 'complete',
      confidenceLevel: isRealScene ? 'high' : 'medium',
      metadata: {
        capturedAt,
        deviceModel: 'iPhone 15 Pro',
        latitude: 37.7749 + (faker.number.float({ min: -0.01, max: 0.01 })),
        longitude: -122.4194 + (faker.number.float({ min: -0.01, max: 0.01 })),
      },
      evidence: this.buildEvidence(isRealScene),
      ...this.overrides,
    };

    this.createdCaptures.push(capture.id);
    return capture;
  }

  /**
   * Build evidence object
   */
  private buildEvidence(isRealScene: boolean): Evidence {
    const depthVariance = isRealScene
      ? faker.number.float({ min: 0.6, max: 2.5 })
      : faker.number.float({ min: 0.05, max: 0.3 });

    const depthLayers = isRealScene
      ? faker.number.int({ min: 3, max: 8 })
      : faker.number.int({ min: 1, max: 2 });

    const edgeCoherence = isRealScene
      ? faker.number.float({ min: 0.75, max: 0.95 })
      : faker.number.float({ min: 0.2, max: 0.5 });

    return {
      hardwareAttestation: {
        status: 'pass',
        level: 'secure_enclave',
        deviceModel: 'iPhone 15 Pro',
      },
      depthAnalysis: {
        status: isRealScene ? 'pass' : 'fail',
        depthVariance,
        depthLayers,
        edgeCoherence,
        isLikelyRealScene: isRealScene,
      },
      metadata: {
        timestampValid: true,
        modelHasLidar: true,
      },
    };
  }

  /**
   * Build capture metadata for upload request
   */
  buildMetadata(): CaptureMetadata {
    const capture = this.build();
    return capture.metadata;
  }

  /**
   * Generate mock depth map
   */
  buildDepthMap(width = 256, height = 192): DepthMap {
    const data = new Float32Array(width * height);

    if (this.depthType === 'flat') {
      // Flat surface at ~0.4m (typical screen distance)
      data.fill(0.4);
    } else {
      // Realistic 3D scene with depth gradient and noise
      for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
          const baseDepth = 1.0 + (y / height) * 3.0; // 1m to 4m gradient
          const noise = (Math.random() - 0.5) * 0.3;
          data[y * width + x] = baseDepth + noise;
        }
      }
    }

    return { data, width, height };
  }

  /**
   * Generate mock JPEG data
   */
  buildPhoto(): Uint8Array {
    // Minimal valid JPEG structure
    const header = [0xFF, 0xD8, 0xFF, 0xE0]; // SOI + APP0
    const padding = new Array(1024).fill(0);
    const footer = [0xFF, 0xD9]; // EOI
    return new Uint8Array([...header, ...padding, ...footer]);
  }

  /**
   * Create multiple captures
   */
  buildMany(count: number): Capture[] {
    return Array.from({ length: count }, () => this.build());
  }

  /**
   * Clean up created captures
   */
  async cleanup(): Promise<void> {
    this.createdCaptures = [];
    this.overrides = {};
    this.depthType = 'real_scene';
  }
}

// Export singleton factory
export const captureFactory = new CaptureFactory();
