/**
 * ATDD Test: Story 4.1 - Capture Upload Endpoint
 *
 * Acceptance Criteria (from epics.md Story 4.1):
 * - Device can multipart POST photo + depth_map + metadata
 * - Server validates device signature via middleware
 * - Server stores photo/depth to S3
 * - Server creates capture record with status: "processing"
 * - Server returns capture_id + status
 *
 * FR Coverage:
 * - FR14: App uploads capture via multipart POST (photo + depth_map + metadata JSON)
 * - FR15: App uses TLS 1.3 for all API communication
 *
 * Test Environment:
 * - Requires: Docker (PostgreSQL + LocalStack for S3)
 * - API runs on localhost:3000
 * - LocalStack S3 on localhost:4566
 */

import { test, expect, request, APIRequestContext } from '@playwright/test';
import {
  MockAttestations,
  SamplePhotos,
  SampleDepthMaps,
  buildDeviceRegistrationPayload,
  buildCaptureUploadPayload,
  signWithMockKey,
  computeSha256,
} from '../support/fixtures/atdd-test-data';

const API_BASE_URL = process.env.API_BASE_URL || 'http://localhost:3000';

/**
 * Helper to register a device and get credentials
 */
async function registerTestDevice(apiContext: APIRequestContext): Promise<{
  deviceId: string;
  attestation: ReturnType<typeof MockAttestations.validSecureEnclave>;
}> {
  const attestation = MockAttestations.validSecureEnclave();
  const payload = buildDeviceRegistrationPayload({
    attestation,
    model: 'iPhone 15 Pro',
  });

  const response = await apiContext.post('/api/v1/devices/register', {
    headers: {
      'Content-Type': 'application/json',
      'X-Test-Mode': 'mock-attestation',
    },
    data: payload,
  });

  const body = await response.json();
  return {
    deviceId: body.data.device_id,
    attestation,
  };
}

/**
 * Create device signature headers for authenticated requests
 */
function createSignatureHeaders(
  deviceId: string,
  privateKey: string,
  bodyHash: string
): Record<string, string> {
  const timestamp = Date.now();
  const signaturePayload = `${timestamp}:${bodyHash}`;
  const signature = signWithMockKey(signaturePayload, privateKey);

  return {
    'X-Device-Id': deviceId,
    'X-Device-Timestamp': timestamp.toString(),
    'X-Device-Signature': signature,
  };
}

test.describe('Story 4.1: Capture Upload', () => {
  /**
   * AC-4.1.1: Device uploads capture with photo, depth map, and metadata
   *
   * GIVEN: Device registered with valid attestation
   * WHEN: Device uploads capture via multipart POST
   * THEN: Capture stored with status "processing"
   */
  test('device uploads capture with photo, depth map, and metadata', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // GIVEN: Device registered with valid attestation
    const { deviceId, attestation } = await registerTestDevice(apiContext);

    // Prepare capture data
    const photo = SamplePhotos.validWithExif();
    const depthMap = SampleDepthMaps.realIndoorScene();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      location: { latitude: 37.7749, longitude: -122.4194 },
      photoHash: photo.hash,
    };

    // Create signature headers
    const bodyHash = computeSha256(photo.buffer);
    const signatureHeaders = createSignatureHeaders(
      deviceId,
      attestation.privateKey!,
      bodyHash
    );

    // WHEN: Device uploads capture via multipart POST
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        ...signatureHeaders,
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

    // THEN: Capture stored with status "processing"
    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body.data).toBeDefined();
    expect(body.data.capture_id).toMatch(/^[0-9a-f-]{36}$/); // UUID format
    expect(body.data.status).toBe('processing');

    // Should include verification URL
    expect(body.data.verification_url).toContain('/verify/');
    expect(body.data.verification_url).toContain(body.data.capture_id);

    await apiContext.dispose();
  });

  /**
   * AC-4.1.2: Capture without GPS is accepted
   *
   * GIVEN: Device registered, photo captured without location permission
   * WHEN: Device uploads capture without GPS
   * THEN: Upload succeeds, location marked as opted_out
   */
  test('capture without GPS is accepted with location_opted_out flag', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const { deviceId, attestation } = await registerTestDevice(apiContext);

    // GIVEN: Photo without GPS
    const photo = SamplePhotos.withoutGps();
    const depthMap = SampleDepthMaps.realIndoorScene();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      // No location field
      photoHash: photo.hash,
    };

    const bodyHash = computeSha256(photo.buffer);
    const signatureHeaders = createSignatureHeaders(
      deviceId,
      attestation.privateKey!,
      bodyHash
    );

    // WHEN: Device uploads without GPS
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        ...signatureHeaders,
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

    // THEN: Upload succeeds
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.data.capture_id).toBeTruthy();
    expect(body.data.status).toBe('processing');

    await apiContext.dispose();
  });

  /**
   * AC-4.1.3: Upload with real scene depth map
   *
   * GIVEN: Device with capture of real 3D scene
   * WHEN: Device uploads with real scene depth
   * THEN: Upload accepted for evidence processing
   */
  test('upload with real scene depth map is accepted', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const { deviceId, attestation } = await registerTestDevice(apiContext);

    // GIVEN: Real scene depth map (high variance, multiple layers)
    const photo = SamplePhotos.validWithExif();
    const depthMap = SampleDepthMaps.realOutdoorScene();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      location: { latitude: 37.7749, longitude: -122.4194 },
      photoHash: photo.hash,
    };

    const bodyHash = computeSha256(photo.buffer);
    const signatureHeaders = createSignatureHeaders(
      deviceId,
      attestation.privateKey!,
      bodyHash
    );

    // WHEN: Upload real scene
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        ...signatureHeaders,
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

    // THEN: Upload accepted
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.data.capture_id).toBeTruthy();

    await apiContext.dispose();
  });

  /**
   * AC-4.1.4: Upload with flat depth (photo of screen)
   *
   * GIVEN: Device capturing image of a screen (flat depth)
   * WHEN: Device uploads with flat depth map
   * THEN: Upload accepted (depth analysis will flag it later)
   */
  test('upload with flat depth map is accepted for processing', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const { deviceId, attestation } = await registerTestDevice(apiContext);

    // GIVEN: Flat depth map (simulating photo of screen)
    const photo = SamplePhotos.validWithExif();
    const depthMap = SampleDepthMaps.flatScreen();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      photoHash: photo.hash,
    };

    const bodyHash = computeSha256(photo.buffer);
    const signatureHeaders = createSignatureHeaders(
      deviceId,
      attestation.privateKey!,
      bodyHash
    );

    // WHEN: Upload with flat depth
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        ...signatureHeaders,
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

    // THEN: Upload accepted (evidence will determine confidence)
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.data.capture_id).toBeTruthy();
    expect(body.data.status).toBe('processing');

    await apiContext.dispose();
  });

  /**
   * AC-4.1.5: Missing photo part is rejected
   *
   * GIVEN: Device attempts upload without photo
   * WHEN: Multipart POST missing photo
   * THEN: Server returns 400 VALIDATION_ERROR
   */
  test('missing photo part is rejected with validation error', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const { deviceId, attestation } = await registerTestDevice(apiContext);

    const depthMap = SampleDepthMaps.realIndoorScene();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      photoHash: 'fake-hash',
    };

    const signatureHeaders = createSignatureHeaders(
      deviceId,
      attestation.privateKey!,
      'fake-hash'
    );

    // WHEN: Upload without photo
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        ...signatureHeaders,
        'X-Test-Mode': 'mock-attestation',
      },
      multipart: {
        // Missing: photo
        depth_map: {
          name: 'depth.gz',
          mimeType: 'application/gzip',
          buffer: depthMap.compressedBuffer,
        },
        metadata: JSON.stringify(metadata),
      },
    });

    // THEN: Validation error
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(body.error.code).toBe('VALIDATION_ERROR');
    expect(body.error.message).toContain('photo');

    await apiContext.dispose();
  });

  /**
   * AC-4.1.6: Missing depth map is rejected
   *
   * GIVEN: Device attempts upload without depth map
   * WHEN: Multipart POST missing depth_map
   * THEN: Server returns 400 VALIDATION_ERROR
   */
  test('missing depth map is rejected with validation error', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const { deviceId, attestation } = await registerTestDevice(apiContext);

    const photo = SamplePhotos.validWithExif();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      photoHash: photo.hash,
    };

    const bodyHash = computeSha256(photo.buffer);
    const signatureHeaders = createSignatureHeaders(
      deviceId,
      attestation.privateKey!,
      bodyHash
    );

    // WHEN: Upload without depth map
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        ...signatureHeaders,
        'X-Test-Mode': 'mock-attestation',
      },
      multipart: {
        photo: {
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          buffer: photo.buffer,
        },
        // Missing: depth_map
        metadata: JSON.stringify(metadata),
      },
    });

    // THEN: Validation error
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(body.error.code).toBe('VALIDATION_ERROR');
    expect(body.error.message).toContain('depth');

    await apiContext.dispose();
  });

  /**
   * AC-4.1.7: Invalid signature is rejected
   *
   * GIVEN: Device with tampered signature
   * WHEN: Upload with wrong signature
   * THEN: Server returns 401 SIGNATURE_INVALID
   */
  test('invalid device signature is rejected', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const { deviceId } = await registerTestDevice(apiContext);

    const photo = SamplePhotos.validWithExif();
    const depthMap = SampleDepthMaps.realIndoorScene();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      photoHash: photo.hash,
    };

    // WHEN: Upload with invalid signature
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        'X-Device-Id': deviceId,
        'X-Device-Timestamp': Date.now().toString(),
        'X-Device-Signature': 'invalid-signature-base64',
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

    // THEN: Signature invalid
    expect(response.status()).toBe(401);
    const body = await response.json();
    expect(body.error.code).toBe('SIGNATURE_INVALID');

    await apiContext.dispose();
  });

  /**
   * AC-4.1.8: Unknown device is rejected
   *
   * GIVEN: Device ID that doesn't exist
   * WHEN: Upload attempt
   * THEN: Server returns 404 DEVICE_NOT_FOUND
   */
  test('unknown device ID is rejected', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    const photo = SamplePhotos.validWithExif();
    const depthMap = SampleDepthMaps.realIndoorScene();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      photoHash: photo.hash,
    };

    // WHEN: Upload with unknown device
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        'X-Device-Id': '00000000-0000-0000-0000-000000000000', // Fake UUID
        'X-Device-Timestamp': Date.now().toString(),
        'X-Device-Signature': 'any-signature',
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

    // THEN: Device not found
    expect(response.status()).toBe(404);
    const body = await response.json();
    expect(body.error.code).toBe('DEVICE_NOT_FOUND');

    await apiContext.dispose();
  });
});

test.describe('Story 4.1: S3 Storage Verification', () => {
  /**
   * AC-4.1.9: Files stored in S3 after upload
   *
   * GIVEN: Successful capture upload
   * WHEN: Checking S3 storage
   * THEN: Photo and depth map exist at expected paths
   *
   * Note: This test requires LocalStack S3 access
   */
  test.skip('files are stored in S3 after successful upload', async () => {
    // TODO: Implement S3 verification when LocalStack is configured
    // const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    // const { deviceId, attestation } = await registerTestDevice(apiContext);
    //
    // Upload capture...
    //
    // Verify S3 paths:
    // - captures/{capture_id}/original.jpg
    // - captures/{capture_id}/depth.gz
  });

  /**
   * AC-4.1.10: Database record created with correct status
   *
   * GIVEN: Successful capture upload
   * WHEN: Checking database
   * THEN: Capture record exists with status "processing"
   *
   * Note: This test requires direct DB access
   */
  test.skip('database record created with processing status', async () => {
    // TODO: Implement DB verification when direct access is configured
  });
});

test.describe('Upload Size & Performance', () => {
  /**
   * Upload should handle typical photo sizes (3-4MB)
   */
  test('handles typical photo size upload', async () => {
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const { deviceId, attestation } = await registerTestDevice(apiContext);

    // Create larger test photo buffer (~3MB)
    const photo = SamplePhotos.validWithExif();
    const largerBuffer = Buffer.concat([photo.buffer, Buffer.alloc(3 * 1024 * 1024)]);

    const depthMap = SampleDepthMaps.realIndoorScene();
    const metadata = {
      capturedAt: new Date().toISOString(),
      deviceModel: 'iPhone 15 Pro',
      photoHash: computeSha256(largerBuffer),
    };

    const signatureHeaders = createSignatureHeaders(
      deviceId,
      attestation.privateKey!,
      computeSha256(largerBuffer)
    );

    const startTime = Date.now();

    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        ...signatureHeaders,
        'X-Test-Mode': 'mock-attestation',
      },
      multipart: {
        photo: {
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          buffer: largerBuffer,
        },
        depth_map: {
          name: 'depth.gz',
          mimeType: 'application/gzip',
          buffer: depthMap.compressedBuffer,
        },
        metadata: JSON.stringify(metadata),
      },
      timeout: 30000, // 30s timeout for large upload
    });

    const uploadTime = Date.now() - startTime;

    expect(response.status()).toBe(200);
    // Upload should complete in reasonable time (< 15s for local)
    expect(uploadTime).toBeLessThan(15000);

    await apiContext.dispose();
  });
});
