/**
 * ATDD Test Data & Fixtures for RealityCam
 *
 * This module provides realistic test fixtures for acceptance testing
 * the core capture -> upload -> evidence -> verify flow.
 *
 * Test Data Categories:
 * 1. Mock Attestation (DCAppAttest CBOR simulation)
 * 2. Sample Photos (minimal valid JPEG with EXIF)
 * 3. Sample Depth Maps (real scene vs flat patterns)
 * 4. Expected Evidence Structures
 *
 * References:
 * - Story 2.4: Device Registration
 * - Story 4.1: Capture Upload
 * - Stories 4.4-4.7: Evidence Generation
 * - Story 5.4-5.5: Verification Display
 */

import { faker } from '@faker-js/faker';
import * as crypto from 'crypto';
import * as zlib from 'zlib';

// =============================================================================
// MOCK ATTESTATION DATA (Story 2.4, FR3-FR5)
// =============================================================================

/**
 * Mock DCAppAttest attestation structure
 * Real attestations are CBOR-encoded, but for testing we use a simplified structure
 */
export interface MockAttestation {
  keyId: string;
  attestationObject: string; // Base64-encoded mock CBOR
  publicKey: string; // Ed25519 public key (Base64)
  privateKey?: string; // For signing test requests (kept in test only)
}

/**
 * Pre-generated attestation fixtures for different test scenarios
 *
 * In real DCAppAttest:
 * - attestationObject is CBOR with certificate chain
 * - keyId is base64-encoded key identifier
 * - Verification requires Apple's root CA
 *
 * For testing, we use mock structures that the backend
 * can recognize as test fixtures (via X-Test-Mode header)
 */
export const MockAttestations = {
  /**
   * Valid attestation from iPhone 15 Pro with Secure Enclave
   * Use for happy-path device registration
   */
  validSecureEnclave: (): MockAttestation => {
    const keyId = generateMockKeyId();
    const { publicKey, privateKey } = generateEd25519KeyPair();

    return {
      keyId,
      attestationObject: generateMockAttestationObject({
        keyId,
        publicKey,
        attestationLevel: 'secure_enclave',
        deviceModel: 'iPhone15,2', // iPhone 15 Pro identifier
      }),
      publicKey,
      privateKey,
    };
  },

  /**
   * Invalid attestation (certificate chain fails)
   * Use for negative testing of attestation verification
   */
  invalidCertChain: (): MockAttestation => {
    const keyId = generateMockKeyId();
    const { publicKey, privateKey } = generateEd25519KeyPair();

    return {
      keyId,
      attestationObject: generateMockAttestationObject({
        keyId,
        publicKey,
        attestationLevel: 'invalid',
        deviceModel: 'iPhone15,2',
        invalidReason: 'cert_chain_invalid',
      }),
      publicKey,
      privateKey,
    };
  },

  /**
   * Attestation from non-Pro device (no LiDAR)
   * Backend should accept but flag hasLidar: false
   */
  nonProDevice: (): MockAttestation => {
    const keyId = generateMockKeyId();
    const { publicKey, privateKey } = generateEd25519KeyPair();

    return {
      keyId,
      attestationObject: generateMockAttestationObject({
        keyId,
        publicKey,
        attestationLevel: 'secure_enclave',
        deviceModel: 'iPhone15,3', // iPhone 15 (non-Pro)
      }),
      publicKey,
      privateKey,
    };
  },

  /**
   * Expired attestation timestamp
   * Backend should reject with ATTESTATION_FAILED
   */
  expiredTimestamp: (): MockAttestation => {
    const keyId = generateMockKeyId();
    const { publicKey, privateKey } = generateEd25519KeyPair();

    return {
      keyId,
      attestationObject: generateMockAttestationObject({
        keyId,
        publicKey,
        attestationLevel: 'secure_enclave',
        deviceModel: 'iPhone15,2',
        timestamp: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), // 7 days ago
      }),
      publicKey,
      privateKey,
    };
  },
};

// =============================================================================
// SAMPLE PHOTOS (Story 3.2, FR7)
// =============================================================================

/**
 * Sample photo data with metadata
 */
export interface SamplePhoto {
  buffer: Buffer;
  hash: string;
  mimeType: 'image/jpeg';
  exifData: {
    timestamp: Date;
    make: string;
    model: string;
    gps?: { latitude: number; longitude: number };
  };
}

/**
 * Generate sample photos for different test scenarios
 */
export const SamplePhotos = {
  /**
   * Valid photo with complete EXIF from iPhone 15 Pro
   * Timestamps within acceptable range
   */
  validWithExif: (captureTime?: Date): SamplePhoto => {
    const timestamp = captureTime || new Date();
    const buffer = generateMinimalJpegWithExif({
      timestamp,
      make: 'Apple',
      model: 'iPhone 15 Pro',
      gps: { latitude: 37.7749, longitude: -122.4194 },
    });

    return {
      buffer,
      hash: computeSha256(buffer),
      mimeType: 'image/jpeg',
      exifData: {
        timestamp,
        make: 'Apple',
        model: 'iPhone 15 Pro',
        gps: { latitude: 37.7749, longitude: -122.4194 },
      },
    };
  },

  /**
   * Photo without GPS (user opted out of location)
   * Should be accepted, location_opted_out flag set
   */
  withoutGps: (captureTime?: Date): SamplePhoto => {
    const timestamp = captureTime || new Date();
    const buffer = generateMinimalJpegWithExif({
      timestamp,
      make: 'Apple',
      model: 'iPhone 15 Pro',
    });

    return {
      buffer,
      hash: computeSha256(buffer),
      mimeType: 'image/jpeg',
      exifData: {
        timestamp,
        make: 'Apple',
        model: 'iPhone 15 Pro',
      },
    };
  },

  /**
   * Photo with stale timestamp (> 5 min from upload)
   * Should be flagged in metadata validation
   */
  staleTimestamp: (): SamplePhoto => {
    const timestamp = new Date(Date.now() - 10 * 60 * 1000); // 10 minutes ago
    const buffer = generateMinimalJpegWithExif({
      timestamp,
      make: 'Apple',
      model: 'iPhone 15 Pro',
    });

    return {
      buffer,
      hash: computeSha256(buffer),
      mimeType: 'image/jpeg',
      exifData: {
        timestamp,
        make: 'Apple',
        model: 'iPhone 15 Pro',
      },
    };
  },

  /**
   * Photo from non-LiDAR device (metadata mismatch)
   * Should be flagged: model_has_lidar: false
   */
  fromNonProDevice: (captureTime?: Date): SamplePhoto => {
    const timestamp = captureTime || new Date();
    const buffer = generateMinimalJpegWithExif({
      timestamp,
      make: 'Apple',
      model: 'iPhone 15', // Non-Pro
    });

    return {
      buffer,
      hash: computeSha256(buffer),
      mimeType: 'image/jpeg',
      exifData: {
        timestamp,
        make: 'Apple',
        model: 'iPhone 15',
      },
    };
  },
};

// =============================================================================
// SAMPLE DEPTH MAPS (Story 3.2, FR8, FR21-22)
// =============================================================================

/**
 * Depth map structure matching LiDAR capture format
 */
export interface SampleDepthMap {
  /** Raw float32 depth values (meters) */
  rawData: Float32Array;
  /** Gzipped for upload */
  compressedBuffer: Buffer;
  /** Dimensions */
  width: number;
  height: number;
  /** Expected analysis results */
  expectedAnalysis: {
    depthVariance: number;
    depthLayers: number;
    edgeCoherence: number;
    isLikelyRealScene: boolean;
  };
}

/**
 * Generate depth maps for different scene types
 *
 * Thresholds from Architecture doc:
 * - Real scene: variance > 0.5, layers >= 3, coherence > 0.7
 * - Flat/fake: fails one or more thresholds
 */
export const SampleDepthMaps = {
  /**
   * Realistic 3D indoor scene
   * Multiple depth layers (furniture, walls, etc.)
   * Should pass all depth checks
   */
  realIndoorScene: (): SampleDepthMap => {
    const width = 256;
    const height = 192;
    const rawData = generateIndoorSceneDepth(width, height);

    return {
      rawData,
      compressedBuffer: compressDepthMap(rawData),
      width,
      height,
      expectedAnalysis: {
        depthVariance: 1.8, // High variance expected
        depthLayers: 5,
        edgeCoherence: 0.85,
        isLikelyRealScene: true,
      },
    };
  },

  /**
   * Outdoor scene with people at various distances
   * High depth variance, multiple subjects
   */
  realOutdoorScene: (): SampleDepthMap => {
    const width = 256;
    const height = 192;
    const rawData = generateOutdoorSceneDepth(width, height);

    return {
      rawData,
      compressedBuffer: compressDepthMap(rawData),
      width,
      height,
      expectedAnalysis: {
        depthVariance: 2.4,
        depthLayers: 6,
        edgeCoherence: 0.82,
        isLikelyRealScene: true,
      },
    };
  },

  /**
   * Flat surface (photo of screen/monitor)
   * Uniform depth around 0.3-0.5m
   * Should FAIL is_likely_real_scene
   */
  flatScreen: (): SampleDepthMap => {
    const width = 256;
    const height = 192;
    const rawData = generateFlatSurfaceDepth(width, height, 0.4);

    return {
      rawData,
      compressedBuffer: compressDepthMap(rawData),
      width,
      height,
      expectedAnalysis: {
        depthVariance: 0.02, // Very low
        depthLayers: 1,
        edgeCoherence: 0.3, // Low coherence (edges don't align)
        isLikelyRealScene: false,
      },
    };
  },

  /**
   * Printed photo (paper at ~0.5m)
   * Similar to screen but slightly different depth
   */
  printedPhoto: (): SampleDepthMap => {
    const width = 256;
    const height = 192;
    const rawData = generateFlatSurfaceDepth(width, height, 0.5);

    return {
      rawData,
      compressedBuffer: compressDepthMap(rawData),
      width,
      height,
      expectedAnalysis: {
        depthVariance: 0.03,
        depthLayers: 1,
        edgeCoherence: 0.25,
        isLikelyRealScene: false,
      },
    };
  },

  /**
   * Edge case: Scene with only 2 depth layers
   * Borderline - may pass variance but fail layer count
   */
  twoLayerScene: (): SampleDepthMap => {
    const width = 256;
    const height = 192;
    const rawData = generateTwoLayerDepth(width, height);

    return {
      rawData,
      compressedBuffer: compressDepthMap(rawData),
      width,
      height,
      expectedAnalysis: {
        depthVariance: 0.8,
        depthLayers: 2, // Below threshold
        edgeCoherence: 0.75,
        isLikelyRealScene: false, // Fails layer count
      },
    };
  },
};

// =============================================================================
// EXPECTED EVIDENCE STRUCTURES (Stories 4.4-4.7, FR25-26)
// =============================================================================

/**
 * Complete evidence package structure (JSONB in database)
 */
export interface ExpectedEvidence {
  hardwareAttestation: {
    status: 'pass' | 'fail' | 'unavailable';
    level: 'secure_enclave' | 'unverified';
    deviceModel: string;
    keyId: string;
  };
  depthAnalysis: {
    status: 'pass' | 'fail' | 'unavailable';
    depthVariance: number;
    depthLayers: number;
    edgeCoherence: number;
    minDepth: number;
    isLikelyRealScene: boolean;
  };
  metadata: {
    timestampValid: boolean;
    timestampDeltaSeconds: number;
    modelValid: boolean;
    modelHasLidar: boolean;
  };
  location?: {
    latitude: number;
    longitude: number;
    accuracy: number;
    coarseLatitude: number; // Public (city-level)
    coarseLongitude: number;
  };
  processingInfo: {
    processedAt: string;
    durationMs: number;
    version: string;
  };
}

/**
 * Expected confidence levels based on evidence combinations
 */
export type ConfidenceLevel = 'HIGH' | 'MEDIUM' | 'LOW' | 'SUSPICIOUS';

/**
 * Evidence factory for specific test scenarios
 */
export const ExpectedEvidenceFixtures = {
  /**
   * HIGH confidence: Hardware pass + Depth pass
   * Best-case scenario
   */
  highConfidence: (overrides?: Partial<ExpectedEvidence>): ExpectedEvidence => ({
    hardwareAttestation: {
      status: 'pass',
      level: 'secure_enclave',
      deviceModel: 'iPhone 15 Pro',
      keyId: faker.string.alphanumeric(44),
    },
    depthAnalysis: {
      status: 'pass',
      depthVariance: 1.8,
      depthLayers: 5,
      edgeCoherence: 0.85,
      minDepth: 0.8,
      isLikelyRealScene: true,
    },
    metadata: {
      timestampValid: true,
      timestampDeltaSeconds: 2,
      modelValid: true,
      modelHasLidar: true,
    },
    location: {
      latitude: 37.7749,
      longitude: -122.4194,
      accuracy: 10,
      coarseLatitude: 37.8, // Rounded for privacy
      coarseLongitude: -122.4,
    },
    processingInfo: {
      processedAt: new Date().toISOString(),
      durationMs: 3500,
      version: '1.0.0',
    },
    ...overrides,
  }),

  /**
   * MEDIUM confidence: Hardware pass, Depth fail
   * Verified device but scene might be flat
   */
  mediumHardwareOnly: (): ExpectedEvidence => ({
    hardwareAttestation: {
      status: 'pass',
      level: 'secure_enclave',
      deviceModel: 'iPhone 15 Pro',
      keyId: faker.string.alphanumeric(44),
    },
    depthAnalysis: {
      status: 'fail',
      depthVariance: 0.15,
      depthLayers: 1,
      edgeCoherence: 0.35,
      minDepth: 0.4,
      isLikelyRealScene: false,
    },
    metadata: {
      timestampValid: true,
      timestampDeltaSeconds: 3,
      modelValid: true,
      modelHasLidar: true,
    },
    processingInfo: {
      processedAt: new Date().toISOString(),
      durationMs: 4200,
      version: '1.0.0',
    },
  }),

  /**
   * LOW confidence: No hardware attestation, no depth
   * Unverified device + flat scene
   */
  lowConfidence: (): ExpectedEvidence => ({
    hardwareAttestation: {
      status: 'fail',
      level: 'unverified',
      deviceModel: 'Unknown',
      keyId: '',
    },
    depthAnalysis: {
      status: 'fail',
      depthVariance: 0.1,
      depthLayers: 1,
      edgeCoherence: 0.2,
      minDepth: 0.3,
      isLikelyRealScene: false,
    },
    metadata: {
      timestampValid: true,
      timestampDeltaSeconds: 1,
      modelValid: false,
      modelHasLidar: false,
    },
    processingInfo: {
      processedAt: new Date().toISOString(),
      durationMs: 2800,
      version: '1.0.0',
    },
  }),

  /**
   * SUSPICIOUS: Any check explicitly failed (not unavailable)
   * E.g., timestamp manipulation detected
   */
  suspicious: (): ExpectedEvidence => ({
    hardwareAttestation: {
      status: 'pass',
      level: 'secure_enclave',
      deviceModel: 'iPhone 15 Pro',
      keyId: faker.string.alphanumeric(44),
    },
    depthAnalysis: {
      status: 'pass',
      depthVariance: 1.5,
      depthLayers: 4,
      edgeCoherence: 0.78,
      minDepth: 1.0,
      isLikelyRealScene: true,
    },
    metadata: {
      timestampValid: false, // Timestamp manipulation detected!
      timestampDeltaSeconds: 3600, // 1 hour off
      modelValid: true,
      modelHasLidar: true,
    },
    processingInfo: {
      processedAt: new Date().toISOString(),
      durationMs: 3100,
      version: '1.0.0',
    },
  }),
};

/**
 * Calculate expected confidence level from evidence
 * Mirrors backend logic from Architecture doc
 */
export function calculateExpectedConfidence(evidence: ExpectedEvidence): ConfidenceLevel {
  const hwPass = evidence.hardwareAttestation.status === 'pass';
  const depthPass = evidence.depthAnalysis.isLikelyRealScene;
  const anyFail =
    !evidence.metadata.timestampValid ||
    evidence.hardwareAttestation.status === 'fail' ||
    evidence.depthAnalysis.status === 'fail';

  if (anyFail && !evidence.metadata.timestampValid) {
    return 'SUSPICIOUS';
  }

  if (hwPass && depthPass) return 'HIGH';
  if (hwPass || depthPass) return 'MEDIUM';
  return 'LOW';
}

// =============================================================================
// CAPTURE UPLOAD PAYLOAD (Story 4.1, FR14)
// =============================================================================

/**
 * Complete capture upload payload for multipart POST
 */
export interface CaptureUploadPayload {
  photo: SamplePhoto;
  depthMap: SampleDepthMap;
  metadata: {
    capturedAt: string;
    deviceModel: string;
    location?: { latitude: number; longitude: number };
    photoHash: string;
  };
  deviceSignature: {
    deviceId: string;
    timestamp: number;
    signature: string;
  };
}

/**
 * Build complete capture upload payload
 */
export function buildCaptureUploadPayload(options: {
  attestation: MockAttestation;
  deviceId: string;
  photo?: SamplePhoto;
  depthMap?: SampleDepthMap;
  captureTime?: Date;
}): CaptureUploadPayload {
  const captureTime = options.captureTime || new Date();
  const photo = options.photo || SamplePhotos.validWithExif(captureTime);
  const depthMap = options.depthMap || SampleDepthMaps.realIndoorScene();

  const timestamp = Date.now();
  const signaturePayload = `${timestamp}:${photo.hash}`;
  const signature = signWithMockKey(signaturePayload, options.attestation.privateKey!);

  return {
    photo,
    depthMap,
    metadata: {
      capturedAt: captureTime.toISOString(),
      deviceModel: photo.exifData.model,
      location: photo.exifData.gps,
      photoHash: photo.hash,
    },
    deviceSignature: {
      deviceId: options.deviceId,
      timestamp,
      signature,
    },
  };
}

// =============================================================================
// DEVICE REGISTRATION PAYLOAD (Story 2.4, FR4, FR43)
// =============================================================================

/**
 * Device registration request structure
 */
export interface DeviceRegistrationPayload {
  platform: 'ios';
  model: string;
  attestation: {
    keyId: string;
    attestationObject: string;
    publicKey: string;
  };
  capabilities: {
    hasLidar: boolean;
    hasSecureEnclave: boolean;
  };
}

/**
 * Build device registration payload
 */
export function buildDeviceRegistrationPayload(options: {
  attestation: MockAttestation;
  model?: string;
  hasLidar?: boolean;
}): DeviceRegistrationPayload {
  const model = options.model || 'iPhone 15 Pro';
  const hasLidar = options.hasLidar ?? model.includes('Pro');

  return {
    platform: 'ios',
    model,
    attestation: {
      keyId: options.attestation.keyId,
      attestationObject: options.attestation.attestationObject,
      publicKey: options.attestation.publicKey,
    },
    capabilities: {
      hasLidar,
      hasSecureEnclave: true,
    },
  };
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

function generateMockKeyId(): string {
  return Buffer.from(crypto.randomBytes(32)).toString('base64');
}

function generateEd25519KeyPair(): { publicKey: string; privateKey: string } {
  // Mock Ed25519 key pair (in real tests, use actual crypto)
  const mockPrivate = crypto.randomBytes(32);
  const mockPublic = crypto.randomBytes(32);

  return {
    publicKey: mockPublic.toString('base64'),
    privateKey: mockPrivate.toString('base64'),
  };
}

function generateMockAttestationObject(params: {
  keyId: string;
  publicKey: string;
  attestationLevel: string;
  deviceModel: string;
  invalidReason?: string;
  timestamp?: Date;
}): string {
  // Simplified mock structure (real is CBOR-encoded)
  const mockStructure = {
    fmt: 'apple-appattest',
    attStmt: {
      x5c: ['mock-cert-chain'],
      receipt: 'mock-receipt',
    },
    authData: {
      keyId: params.keyId,
      publicKey: params.publicKey,
      attestationLevel: params.attestationLevel,
      deviceModel: params.deviceModel,
      timestamp: (params.timestamp || new Date()).toISOString(),
      ...(params.invalidReason && { _test_invalid: params.invalidReason }),
    },
  };

  return Buffer.from(JSON.stringify(mockStructure)).toString('base64');
}

function generateMinimalJpegWithExif(params: {
  timestamp: Date;
  make: string;
  model: string;
  gps?: { latitude: number; longitude: number };
}): Buffer {
  // Minimal valid JPEG with mock EXIF
  // In real tests, use a proper JPEG library
  const header = Buffer.from([0xff, 0xd8, 0xff, 0xe0]); // SOI + APP0

  // Mock EXIF data (simplified)
  const exifData = Buffer.from(
    JSON.stringify({
      _exif: {
        DateTimeOriginal: params.timestamp.toISOString(),
        Make: params.make,
        Model: params.model,
        ...(params.gps && {
          GPSLatitude: params.gps.latitude,
          GPSLongitude: params.gps.longitude,
        }),
      },
    })
  );

  const padding = Buffer.alloc(1024);
  const footer = Buffer.from([0xff, 0xd9]); // EOI

  return Buffer.concat([header, exifData, padding, footer]);
}

function computeSha256(data: Buffer): string {
  return crypto.createHash('sha256').update(data).digest('hex');
}

function generateIndoorSceneDepth(width: number, height: number): Float32Array {
  const data = new Float32Array(width * height);

  // Simulate indoor scene with multiple objects at different depths
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;

      // Background wall at 3-4m
      let depth = 3.5 + Math.random() * 0.2;

      // Furniture region (table at 1.5m)
      if (y > height * 0.6 && y < height * 0.9) {
        depth = 1.5 + Math.random() * 0.1;
      }

      // Chair in foreground (0.8m)
      if (x > width * 0.3 && x < width * 0.5 && y > height * 0.4) {
        depth = 0.8 + Math.random() * 0.05;
      }

      // Person standing (1.2-2m range)
      if (x > width * 0.6 && x < width * 0.8 && y < height * 0.7) {
        depth = 1.2 + (y / height) * 0.8 + Math.random() * 0.1;
      }

      data[idx] = depth;
    }
  }

  return data;
}

function generateOutdoorSceneDepth(width: number, height: number): Float32Array {
  const data = new Float32Array(width * height);

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;

      // Sky/far background (10+ meters)
      let depth = 15.0 + Math.random() * 5;

      // Ground plane gets closer at bottom
      if (y > height * 0.5) {
        const groundProgress = (y - height * 0.5) / (height * 0.5);
        depth = 10.0 - groundProgress * 8.0 + Math.random() * 0.3;
      }

      // Person at 2m
      if (x > width * 0.4 && x < width * 0.6 && y > height * 0.2 && y < height * 0.8) {
        depth = 2.0 + Math.random() * 0.1;
      }

      // Tree at 4m on the left
      if (x < width * 0.25 && y < height * 0.7) {
        depth = 4.0 + Math.random() * 0.2;
      }

      data[idx] = depth;
    }
  }

  return data;
}

function generateFlatSurfaceDepth(width: number, height: number, distance: number): Float32Array {
  const data = new Float32Array(width * height);

  // Uniform depth with minimal noise (flat surface)
  for (let i = 0; i < data.length; i++) {
    data[i] = distance + (Math.random() - 0.5) * 0.02;
  }

  return data;
}

function generateTwoLayerDepth(width: number, height: number): Float32Array {
  const data = new Float32Array(width * height);

  // Two distinct layers: foreground object + background
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;

      // Background at 3m
      let depth = 3.0 + Math.random() * 0.1;

      // Single foreground object at 1m
      if (x > width * 0.3 && x < width * 0.7 && y > height * 0.3 && y < height * 0.7) {
        depth = 1.0 + Math.random() * 0.05;
      }

      data[idx] = depth;
    }
  }

  return data;
}

function compressDepthMap(data: Float32Array): Buffer {
  const buffer = Buffer.from(data.buffer);
  return zlib.gzipSync(buffer);
}

function signWithMockKey(payload: string, privateKey: string): string {
  // Mock signature (in real tests, use ed25519)
  const hmac = crypto.createHmac('sha256', Buffer.from(privateKey, 'base64'));
  hmac.update(payload);
  return hmac.digest('base64');
}

// =============================================================================
// EXPORTS
// =============================================================================

export {
  computeSha256,
  compressDepthMap,
  generateMockKeyId,
  generateEd25519KeyPair,
  signWithMockKey,
};
