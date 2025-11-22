/**
 * Test Fixtures for RealityCam ATDD
 *
 * This module re-exports all test fixtures for easy importing.
 *
 * Usage:
 *   import {
 *     MockAttestations,
 *     SamplePhotos,
 *     SampleDepthMaps,
 *     buildCaptureUploadPayload,
 *   } from '../support/fixtures';
 */

export {
  // Mock Attestation Data
  MockAttestations,
  type MockAttestation,

  // Sample Photos
  SamplePhotos,
  type SamplePhoto,

  // Sample Depth Maps
  SampleDepthMaps,
  type SampleDepthMap,

  // Expected Evidence Structures
  ExpectedEvidenceFixtures,
  type ExpectedEvidence,
  type ConfidenceLevel,
  calculateExpectedConfidence,

  // Payload Builders
  buildCaptureUploadPayload,
  buildDeviceRegistrationPayload,
  type CaptureUploadPayload,
  type DeviceRegistrationPayload,

  // Utility Functions
  computeSha256,
  compressDepthMap,
  generateMockKeyId,
  generateEd25519KeyPair,
  signWithMockKey,
} from './atdd-test-data';
