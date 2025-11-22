/**
 * ATDD Test: Stories 4.4-4.7 - Evidence Generation Pipeline
 *
 * Acceptance Criteria (from epics.md):
 *
 * Story 4.4: Attestation Verification on Upload
 * - Backend retrieves device attestation level on each upload
 * - Verifies device signature is valid
 * - Records attestation verification result in evidence
 *
 * Story 4.5: LiDAR Depth Analysis Service
 * - Decompresses gzipped depth data
 * - Calculates depth variance, layers, edge coherence
 * - Determines is_likely_real_scene
 *
 * Story 4.6: Metadata Validation
 * - Compares EXIF timestamp to server receipt time (±5 min tolerance)
 * - Validates device model is iPhone Pro (has LiDAR)
 *
 * Story 4.7: Evidence Package & Confidence Calculation
 * - Combines hardware, depth, and metadata evidence
 * - Calculates confidence: SUSPICIOUS / HIGH / MEDIUM / LOW
 *
 * FR Coverage:
 * - FR20: Backend verifies DCAppAttest attestation and records level
 * - FR21: Backend performs LiDAR depth analysis
 * - FR22: Backend determines "is_likely_real_scene" from depth analysis
 * - FR23: Backend validates EXIF timestamp against server receipt time
 * - FR24: Backend validates device model is iPhone Pro (has LiDAR)
 * - FR25: Backend generates evidence package with all check results
 * - FR26: Backend calculates confidence level (HIGH/MEDIUM/LOW/SUSPICIOUS)
 */

import { test, expect, request, APIRequestContext } from '@playwright/test';
import {
  MockAttestations,
  SamplePhotos,
  SampleDepthMaps,
  ExpectedEvidenceFixtures,
  buildDeviceRegistrationPayload,
  signWithMockKey,
  computeSha256,
  calculateExpectedConfidence,
  type ExpectedEvidence,
} from '../support/fixtures/atdd-test-data';

const API_BASE_URL = process.env.API_BASE_URL || 'http://localhost:3000';

/**
 * Helper to register device and upload capture in one step
 */
async function uploadCapture(
  apiContext: APIRequestContext,
  options: {
    photo?: ReturnType<typeof SamplePhotos.validWithExif>;
    depthMap?: ReturnType<typeof SampleDepthMaps.realIndoorScene>;
    deviceModel?: string;
    hasLidar?: boolean;
    attestation?: ReturnType<typeof MockAttestations.validSecureEnclave>;
  } = {}
): Promise<{ captureId: string; deviceId: string }> {
  const attestation = options.attestation || MockAttestations.validSecureEnclave();
  const payload = buildDeviceRegistrationPayload({
    attestation,
    model: options.deviceModel || 'iPhone 15 Pro',
    hasLidar: options.hasLidar ?? true,
  });

  // Register device
  const regResponse = await apiContext.post('/api/v1/devices/register', {
    headers: {
      'Content-Type': 'application/json',
      'X-Test-Mode': 'mock-attestation',
    },
    data: payload,
  });
  const { device_id: deviceId } = (await regResponse.json()).data;

  // Upload capture
  const photo = options.photo || SamplePhotos.validWithExif();
  const depthMap = options.depthMap || SampleDepthMaps.realIndoorScene();
  const metadata = {
    capturedAt: new Date().toISOString(),
    deviceModel: options.deviceModel || 'iPhone 15 Pro',
    photoHash: photo.hash,
  };

  const bodyHash = computeSha256(photo.buffer);
  const timestamp = Date.now();
  const signature = signWithMockKey(`${timestamp}:${bodyHash}`, attestation.privateKey!);

  const uploadResponse = await apiContext.post('/api/v1/captures', {
    headers: {
      'X-Device-Id': deviceId,
      'X-Device-Timestamp': timestamp.toString(),
      'X-Device-Signature': signature,
      'X-Test-Mode': 'mock-attestation',
    },
    multipart: {
      photo: {
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        buffer: photo.buffer,
      },
      depth_map: {
        name: 'depth.gz',
        mimeType: 'application/gzip',
        buffer: depthMap.compressedBuffer,
      },
      metadata: JSON.stringify(metadata),
    },
  });

  const { capture_id: captureId } = (await uploadResponse.json()).data;
  return { captureId, deviceId };
}

/**
 * Wait for capture to finish processing
 */
async function waitForProcessing(
  apiContext: APIRequestContext,
  captureId: string,
  timeoutMs = 30000
): Promise<{ evidence: ExpectedEvidence; confidenceLevel: string }> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    const response = await apiContext.get(`/api/v1/captures/${captureId}`);
    const body = await response.json();

    if (body.data.status === 'complete') {
      return {
        evidence: body.data.evidence,
        confidenceLevel: body.data.confidence_level,
      };
    }

    if (body.data.status === 'failed') {
      throw new Error(`Capture processing failed: ${JSON.stringify(body.data)}`);
    }

    // Poll every 500ms
    await new Promise(resolve => setTimeout(resolve, 500));
  }

  throw new Error(`Capture processing timed out after ${timeoutMs}ms`);
}

test.describe('Story 4.4: Attestation Verification on Upload', () => {
  /**
   * AC-4.4.1: Hardware attestation recorded for Secure Enclave device
   *
   * GIVEN: Device with Secure Enclave attestation
   * WHEN: Capture uploaded and processed
   * THEN: Evidence includes hardware_attestation with status: pass, level: secure_enclave
   */
  test('hardware attestation recorded for Secure Enclave device', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Device with secure enclave
    const { captureId } = await uploadCapture(apiContext, {
      depthMap: SampleDepthMaps.realIndoorScene(),
    });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Hardware attestation passes
    expect(evidence.hardwareAttestation).toBeDefined();
    expect(evidence.hardwareAttestation.status).toBe('pass');
    expect(evidence.hardwareAttestation.level).toBe('secure_enclave');
    expect(evidence.hardwareAttestation.deviceModel).toContain('iPhone');

    await apiContext.dispose();
  });

  /**
   * AC-4.4.2: Invalid attestation flagged in evidence
   *
   * GIVEN: Device with failed attestation
   * WHEN: Capture uploaded
   * THEN: Evidence includes hardware_attestation with status: fail
   */
  test('invalid attestation flagged in evidence', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Device with invalid attestation
    const invalidAttestation = MockAttestations.invalidCertChain();

    // Note: Registration may fail, but if it succeeds with unverified level:
    const regPayload = buildDeviceRegistrationPayload({
      attestation: invalidAttestation,
      model: 'iPhone 15 Pro',
    });

    const regResponse = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: regPayload,
    });

    // Either registration fails (401) or device marked unverified
    if (regResponse.status() === 401) {
      // Expected for invalid cert chain
      const body = await regResponse.json();
      expect(body.error.code).toBe('ATTESTATION_FAILED');
    } else {
      // If registration allowed, attestation level should be unverified
      const body = await regResponse.json();
      expect(body.data.attestation_level).toBe('unverified');
    }

    await apiContext.dispose();
  });
});

test.describe('Story 4.5: LiDAR Depth Analysis Service', () => {
  /**
   * AC-4.5.1: Real 3D scene detected from depth analysis
   *
   * GIVEN: Capture with real indoor scene depth map
   * WHEN: Processing completes
   * THEN: depth_analysis shows is_likely_real_scene: true
   */
  test('real 3D indoor scene detected with high variance', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Real indoor scene
    const depthMap = SampleDepthMaps.realIndoorScene();
    const { captureId } = await uploadCapture(apiContext, { depthMap });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Depth analysis passes
    expect(evidence.depthAnalysis).toBeDefined();
    expect(evidence.depthAnalysis.status).toBe('pass');
    expect(evidence.depthAnalysis.isLikelyRealScene).toBe(true);

    // Verify metrics within expected ranges
    expect(evidence.depthAnalysis.depthVariance).toBeGreaterThan(0.5);
    expect(evidence.depthAnalysis.depthLayers).toBeGreaterThanOrEqual(3);
    expect(evidence.depthAnalysis.edgeCoherence).toBeGreaterThan(0.7);

    await apiContext.dispose();
  });

  /**
   * AC-4.5.2: Real outdoor scene detected
   *
   * GIVEN: Capture with outdoor scene depth map
   * WHEN: Processing completes
   * THEN: depth_analysis shows is_likely_real_scene: true with higher variance
   */
  test('real outdoor scene detected with higher variance', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Real outdoor scene
    const depthMap = SampleDepthMaps.realOutdoorScene();
    const { captureId } = await uploadCapture(apiContext, { depthMap });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Depth analysis passes with high variance
    expect(evidence.depthAnalysis.status).toBe('pass');
    expect(evidence.depthAnalysis.isLikelyRealScene).toBe(true);
    expect(evidence.depthAnalysis.depthVariance).toBeGreaterThan(1.5); // Outdoor typically higher

    await apiContext.dispose();
  });

  /**
   * AC-4.5.3: Flat screen detected from depth analysis
   *
   * GIVEN: Capture of flat screen (photo-of-photo attack)
   * WHEN: Processing completes
   * THEN: depth_analysis shows is_likely_real_scene: false
   */
  test('flat screen detected with low variance', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Flat screen depth
    const depthMap = SampleDepthMaps.flatScreen();
    const { captureId } = await uploadCapture(apiContext, { depthMap });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Depth analysis fails
    expect(evidence.depthAnalysis.status).toBe('fail');
    expect(evidence.depthAnalysis.isLikelyRealScene).toBe(false);

    // Low variance (flat surface)
    expect(evidence.depthAnalysis.depthVariance).toBeLessThan(0.5);
    expect(evidence.depthAnalysis.depthLayers).toBeLessThan(3);

    await apiContext.dispose();
  });

  /**
   * AC-4.5.4: Printed photo detected
   *
   * GIVEN: Capture of printed photo (paper)
   * WHEN: Processing completes
   * THEN: depth_analysis shows is_likely_real_scene: false
   */
  test('printed photo detected as flat', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Printed photo depth
    const depthMap = SampleDepthMaps.printedPhoto();
    const { captureId } = await uploadCapture(apiContext, { depthMap });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Fails depth check
    expect(evidence.depthAnalysis.isLikelyRealScene).toBe(false);

    await apiContext.dispose();
  });

  /**
   * AC-4.5.5: Edge case - two layer scene
   *
   * GIVEN: Scene with only 2 distinct depth layers
   * WHEN: Processing completes
   * THEN: Fails layer count threshold
   */
  test('borderline two-layer scene fails layer count', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Two layer depth
    const depthMap = SampleDepthMaps.twoLayerScene();
    const { captureId } = await uploadCapture(apiContext, { depthMap });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Fails due to insufficient layers
    expect(evidence.depthAnalysis.depthLayers).toBe(2);
    expect(evidence.depthAnalysis.isLikelyRealScene).toBe(false);

    await apiContext.dispose();
  });
});

test.describe('Story 4.6: Metadata Validation', () => {
  /**
   * AC-4.6.1: Valid timestamp within 5 minute tolerance
   *
   * GIVEN: Photo with EXIF timestamp within 5 min of upload
   * WHEN: Processing completes
   * THEN: metadata.timestamp_valid is true
   */
  test('timestamp within tolerance is valid', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Photo with current timestamp
    const photo = SamplePhotos.validWithExif(new Date());
    const { captureId } = await uploadCapture(apiContext, { photo });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Timestamp valid
    expect(evidence.metadata.timestampValid).toBe(true);
    expect(Math.abs(evidence.metadata.timestampDeltaSeconds)).toBeLessThan(300); // < 5 min

    await apiContext.dispose();
  });

  /**
   * AC-4.6.2: Stale timestamp flagged
   *
   * GIVEN: Photo with EXIF timestamp > 5 min from upload
   * WHEN: Processing completes
   * THEN: metadata.timestamp_valid is false
   */
  test('stale timestamp is flagged invalid', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Photo with stale timestamp (10 min ago)
    const photo = SamplePhotos.staleTimestamp();
    const { captureId } = await uploadCapture(apiContext, { photo });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Timestamp flagged invalid
    expect(evidence.metadata.timestampValid).toBe(false);
    expect(Math.abs(evidence.metadata.timestampDeltaSeconds)).toBeGreaterThan(300);

    await apiContext.dispose();
  });

  /**
   * AC-4.6.3: iPhone Pro model validated as having LiDAR
   *
   * GIVEN: Photo from iPhone Pro device
   * WHEN: Processing completes
   * THEN: metadata.model_has_lidar is true
   */
  test('iPhone Pro model validated as having LiDAR', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: iPhone 15 Pro
    const { captureId } = await uploadCapture(apiContext, {
      deviceModel: 'iPhone 15 Pro',
    });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: Model validated
    expect(evidence.metadata.modelValid).toBe(true);
    expect(evidence.metadata.modelHasLidar).toBe(true);

    await apiContext.dispose();
  });

  /**
   * AC-4.6.4: Non-Pro device flagged without LiDAR
   *
   * GIVEN: Photo from non-Pro iPhone
   * WHEN: Processing completes
   * THEN: metadata.model_has_lidar is false
   */
  test('non-Pro device flagged without LiDAR', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: iPhone 15 (non-Pro)
    const photo = SamplePhotos.fromNonProDevice();
    const { captureId } = await uploadCapture(apiContext, {
      photo,
      deviceModel: 'iPhone 15',
      hasLidar: false,
    });

    // WHEN: Processing completes
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // THEN: LiDAR flagged false
    expect(evidence.metadata.modelHasLidar).toBe(false);

    await apiContext.dispose();
  });
});

test.describe('Story 4.7: Evidence Package & Confidence Calculation', () => {
  /**
   * AC-4.7.1: HIGH confidence - Hardware pass AND Depth pass
   *
   * GIVEN: Secure Enclave device + real 3D scene
   * WHEN: Processing completes
   * THEN: confidence_level is HIGH
   */
  test('HIGH confidence for hardware pass AND depth pass', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Best case scenario
    const { captureId } = await uploadCapture(apiContext, {
      depthMap: SampleDepthMaps.realIndoorScene(),
    });

    // WHEN: Processing completes
    const { evidence, confidenceLevel } = await waitForProcessing(apiContext, captureId);

    // THEN: HIGH confidence
    expect(confidenceLevel).toBe('HIGH');
    expect(evidence.hardwareAttestation.status).toBe('pass');
    expect(evidence.depthAnalysis.isLikelyRealScene).toBe(true);

    await apiContext.dispose();
  });

  /**
   * AC-4.7.2: MEDIUM confidence - Hardware pass XOR Depth pass
   *
   * GIVEN: Secure Enclave device + flat screen (depth fail)
   * WHEN: Processing completes
   * THEN: confidence_level is MEDIUM
   */
  test('MEDIUM confidence for hardware pass only', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Good hardware, bad depth
    const { captureId } = await uploadCapture(apiContext, {
      depthMap: SampleDepthMaps.flatScreen(),
    });

    // WHEN: Processing completes
    const { evidence, confidenceLevel } = await waitForProcessing(apiContext, captureId);

    // THEN: MEDIUM confidence
    expect(confidenceLevel).toBe('MEDIUM');
    expect(evidence.hardwareAttestation.status).toBe('pass');
    expect(evidence.depthAnalysis.isLikelyRealScene).toBe(false);

    await apiContext.dispose();
  });

  /**
   * AC-4.7.3: SUSPICIOUS confidence - Timestamp manipulation detected
   *
   * GIVEN: Valid hardware + valid depth but stale timestamp
   * WHEN: Processing completes
   * THEN: confidence_level is SUSPICIOUS
   */
  test('SUSPICIOUS confidence for timestamp manipulation', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Stale timestamp
    const photo = SamplePhotos.staleTimestamp();
    const { captureId } = await uploadCapture(apiContext, {
      photo,
      depthMap: SampleDepthMaps.realIndoorScene(),
    });

    // WHEN: Processing completes
    const { evidence, confidenceLevel } = await waitForProcessing(apiContext, captureId);

    // THEN: SUSPICIOUS due to timestamp fail
    expect(confidenceLevel).toBe('SUSPICIOUS');
    expect(evidence.metadata.timestampValid).toBe(false);

    await apiContext.dispose();
  });

  /**
   * AC-4.7.4: Evidence package structure is complete
   *
   * GIVEN: Any capture upload
   * WHEN: Processing completes
   * THEN: Evidence has all required fields
   */
  test('evidence package contains all required fields', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    const { captureId } = await uploadCapture(apiContext);
    const { evidence } = await waitForProcessing(apiContext, captureId);

    // Hardware attestation fields
    expect(evidence.hardwareAttestation).toBeDefined();
    expect(evidence.hardwareAttestation.status).toMatch(/pass|fail|unavailable/);
    expect(evidence.hardwareAttestation.level).toBeDefined();
    expect(evidence.hardwareAttestation.deviceModel).toBeDefined();

    // Depth analysis fields
    expect(evidence.depthAnalysis).toBeDefined();
    expect(evidence.depthAnalysis.status).toMatch(/pass|fail|unavailable/);
    expect(typeof evidence.depthAnalysis.depthVariance).toBe('number');
    expect(typeof evidence.depthAnalysis.depthLayers).toBe('number');
    expect(typeof evidence.depthAnalysis.edgeCoherence).toBe('number');
    expect(typeof evidence.depthAnalysis.isLikelyRealScene).toBe('boolean');

    // Metadata fields
    expect(evidence.metadata).toBeDefined();
    expect(typeof evidence.metadata.timestampValid).toBe('boolean');
    expect(typeof evidence.metadata.modelHasLidar).toBe('boolean');

    // Processing info
    expect(evidence.processingInfo).toBeDefined();
    expect(evidence.processingInfo.processedAt).toBeTruthy();
    expect(typeof evidence.processingInfo.durationMs).toBe('number');

    await apiContext.dispose();
  });

  /**
   * AC-4.7.5: Capture status transitions to complete
   *
   * GIVEN: Capture uploaded with status "processing"
   * WHEN: Evidence computation finishes
   * THEN: Status is "complete"
   */
  test('capture status transitions to complete after processing', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    const { captureId } = await uploadCapture(apiContext);

    // Initial status is "processing"
    const initialResponse = await apiContext.get(`/api/v1/captures/${captureId}`);
    const initialBody = await initialResponse.json();
    expect(['processing', 'complete']).toContain(initialBody.data.status);

    // After waiting, status is "complete"
    await waitForProcessing(apiContext, captureId);

    const finalResponse = await apiContext.get(`/api/v1/captures/${captureId}`);
    const finalBody = await finalResponse.json();
    expect(finalBody.data.status).toBe('complete');

    await apiContext.dispose();
  });
});

test.describe('Evidence Pipeline Performance', () => {
  /**
   * Evidence computation should complete within 15 seconds
   */
  test('evidence computation completes within performance target', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    const { captureId } = await uploadCapture(apiContext);

    const startTime = Date.now();
    const { evidence } = await waitForProcessing(apiContext, captureId, 15000);
    const totalTime = Date.now() - startTime;

    // Should complete within 15s
    expect(totalTime).toBeLessThan(15000);

    // Processing duration should be recorded
    expect(evidence.processingInfo.durationMs).toBeLessThan(10000);

    await apiContext.dispose();
  });
});
