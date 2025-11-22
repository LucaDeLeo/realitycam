/**
 * ATDD Test: Story 2.4 - Device Registration Endpoint
 *
 * Acceptance Criteria (from epics.md Story 2.4):
 * - Device can POST registration with platform, model, and attestation data
 * - Backend verifies DCAppAttest attestation object
 * - Backend stores device record with attestation_key_id (unique)
 * - Backend returns device_id, attestation_level, and has_lidar flag
 * - Duplicate registrations (same key_id) return existing device
 *
 * FR Coverage:
 * - FR4: Backend verifies DCAppAttest assertions against Apple's service
 * - FR5: System assigns attestation level: secure_enclave or unverified
 * - FR43: Device registration stores attestation key ID and capability flags
 *
 * Test Environment:
 * - Requires: Docker (PostgreSQL + LocalStack)
 * - API runs on localhost:3000
 * - Uses mock attestation for development testing
 */

import { test, expect, request } from '@playwright/test';
import {
  MockAttestations,
  buildDeviceRegistrationPayload,
  DeviceRegistrationPayload,
} from '../support/fixtures/atdd-test-data';

// Base URL for API (configurable via env)
const API_BASE_URL = process.env.API_BASE_URL || 'http://localhost:3000';

test.describe('Story 2.4: Device Registration', () => {
  /**
   * AC-2.4.1: Device registers with valid Secure Enclave attestation
   *
   * GIVEN: An iPhone Pro with valid DCAppAttest attestation
   * WHEN: Device POSTs to /api/v1/devices/register with attestation
   * THEN: Server returns device_id with attestation_level: secure_enclave
   */
  test('device registers with valid Secure Enclave attestation', async () => {
    // GIVEN: Valid attestation from iPhone 15 Pro
    const attestation = MockAttestations.validSecureEnclave();
    const payload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15 Pro',
      hasLidar: true,
    });

    // WHEN: Device registers with the backend
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const response = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation', // Signal backend to use mock verification
      },
      data: payload,
    });

    // THEN: Registration succeeds with Secure Enclave level
    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body.data).toBeDefined();
    expect(body.data.device_id).toMatch(/^[0-9a-f-]{36}$/); // UUID format
    expect(body.data.attestation_level).toBe('secure_enclave');
    expect(body.data.has_lidar).toBe(true);

    // Verify response includes request metadata
    expect(body.meta).toBeDefined();
    expect(body.meta.request_id).toBeTruthy();

    await apiContext.dispose();
  });

  /**
   * AC-2.4.2: Non-Pro device registers but flagged without LiDAR
   *
   * GIVEN: An iPhone (non-Pro) without LiDAR capability
   * WHEN: Device POSTs registration
   * THEN: Server accepts but returns has_lidar: false
   */
  test('non-Pro device registers without LiDAR capability', async () => {
    // GIVEN: Attestation from non-Pro iPhone
    const attestation = MockAttestations.nonProDevice();
    const payload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15', // Non-Pro
      hasLidar: false,
    });

    // WHEN: Device registers
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const response = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: payload,
    });

    // THEN: Registration succeeds but without LiDAR
    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body.data.device_id).toBeTruthy();
    expect(body.data.attestation_level).toBe('secure_enclave');
    expect(body.data.has_lidar).toBe(false); // Non-Pro = no LiDAR

    await apiContext.dispose();
  });

  /**
   * AC-2.4.3: Duplicate registration returns existing device
   *
   * GIVEN: A device that has already registered
   * WHEN: Same device (same attestation key_id) registers again
   * THEN: Server returns the existing device_id (idempotent)
   */
  test('duplicate registration returns existing device', async () => {
    // GIVEN: Initial registration
    const attestation = MockAttestations.validSecureEnclave();
    const payload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15 Pro',
    });

    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    // First registration
    const firstResponse = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: payload,
    });
    expect(firstResponse.status()).toBe(200);
    const firstBody = await firstResponse.json();
    const firstDeviceId = firstBody.data.device_id;

    // WHEN: Same device registers again (same key_id)
    const secondResponse = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: payload, // Same payload with same attestation.keyId
    });

    // THEN: Returns same device_id (idempotent)
    expect(secondResponse.status()).toBe(200);
    const secondBody = await secondResponse.json();
    expect(secondBody.data.device_id).toBe(firstDeviceId);

    await apiContext.dispose();
  });

  /**
   * AC-2.4.4: Invalid attestation is rejected
   *
   * GIVEN: An attestation with invalid certificate chain
   * WHEN: Device attempts registration
   * THEN: Server returns 401 with ATTESTATION_FAILED error
   */
  test('invalid attestation certificate chain is rejected', async () => {
    // GIVEN: Invalid attestation
    const attestation = MockAttestations.invalidCertChain();
    const payload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15 Pro',
    });

    // WHEN: Device attempts registration
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const response = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: payload,
    });

    // THEN: Registration fails with attestation error
    expect(response.status()).toBe(401);

    const body = await response.json();
    expect(body.error).toBeDefined();
    expect(body.error.code).toBe('ATTESTATION_FAILED');
    expect(body.error.message).toContain('verification failed');

    await apiContext.dispose();
  });

  /**
   * AC-2.4.5: Missing required fields return validation error
   *
   * GIVEN: A registration request missing required fields
   * WHEN: Device POSTs incomplete payload
   * THEN: Server returns 400 with VALIDATION_ERROR
   */
  test('missing required fields return validation error', async () => {
    // GIVEN: Incomplete payload (missing attestation)
    const incompletePayload = {
      platform: 'ios',
      model: 'iPhone 15 Pro',
      // Missing: attestation, capabilities
    };

    // WHEN: Device attempts registration
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const response = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
      },
      data: incompletePayload,
    });

    // THEN: Returns validation error
    expect(response.status()).toBe(400);

    const body = await response.json();
    expect(body.error).toBeDefined();
    expect(body.error.code).toBe('VALIDATION_ERROR');

    await apiContext.dispose();
  });

  /**
   * AC-2.4.6: Attestation with expired timestamp is handled
   *
   * GIVEN: An attestation with timestamp beyond acceptable window
   * WHEN: Device attempts registration
   * THEN: Server rejects or flags as unverified (implementation-dependent)
   */
  test('expired attestation timestamp is rejected', async () => {
    // GIVEN: Expired attestation
    const attestation = MockAttestations.expiredTimestamp();
    const payload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15 Pro',
    });

    // WHEN: Device attempts registration
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const response = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: payload,
    });

    // THEN: Registration fails or device flagged as unverified
    // Note: Exact behavior depends on backend implementation
    // Could be 401 rejection OR 200 with attestation_level: unverified
    const body = await response.json();

    if (response.status() === 401) {
      expect(body.error.code).toBe('ATTESTATION_FAILED');
    } else {
      expect(response.status()).toBe(200);
      expect(body.data.attestation_level).toBe('unverified');
    }

    await apiContext.dispose();
  });
});

test.describe('Story 2.5: DCAppAttest Verification (Backend)', () => {
  /**
   * AC-2.5.1: Verify attestation parses CBOR correctly
   *
   * This is more of an integration check - the backend should
   * successfully parse the mock CBOR structure we send
   */
  test('backend correctly parses attestation object structure', async () => {
    // GIVEN: Well-formed attestation
    const attestation = MockAttestations.validSecureEnclave();
    const payload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15 Pro',
    });

    // WHEN: Device registers
    const apiContext = await request.newContext({ baseURL: API_BASE_URL });
    const response = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: payload,
    });

    // THEN: Backend parsed and processed attestation
    expect(response.status()).toBe(200);
    const body = await response.json();

    // Backend should have extracted device info from attestation
    expect(body.data.attestation_level).toBeDefined();
    expect(body.data.has_lidar).toBeDefined();

    await apiContext.dispose();
  });
});

test.describe('Story 2.6: Device Authentication Middleware', () => {
  /**
   * AC-2.6.1: Authenticated endpoint requires valid device signature
   *
   * GIVEN: A registered device
   * WHEN: Device makes request without signature
   * THEN: Request is rejected with 401
   */
  test('request without device signature is rejected', async () => {
    // First, register a device
    const attestation = MockAttestations.validSecureEnclave();
    const regPayload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15 Pro',
    });

    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: regPayload,
    });

    // WHEN: Device makes authenticated request without signature headers
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        'Content-Type': 'multipart/form-data',
        // Missing: X-Device-Id, X-Device-Timestamp, X-Device-Signature
      },
    });

    // THEN: Request rejected
    expect(response.status()).toBe(401);

    await apiContext.dispose();
  });

  /**
   * AC-2.6.2: Request with invalid timestamp is rejected
   *
   * GIVEN: A registered device
   * WHEN: Device makes request with stale timestamp (> 5 min)
   * THEN: Request is rejected with TIMESTAMP_EXPIRED
   */
  test('request with expired timestamp is rejected', async () => {
    // Register device first
    const attestation = MockAttestations.validSecureEnclave();
    const regPayload = buildDeviceRegistrationPayload({
      attestation,
      model: 'iPhone 15 Pro',
    });

    const apiContext = await request.newContext({ baseURL: API_BASE_URL });

    const regResponse = await apiContext.post('/api/v1/devices/register', {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-Mode': 'mock-attestation',
      },
      data: regPayload,
    });
    const deviceId = (await regResponse.json()).data.device_id;

    // WHEN: Request with timestamp 10 minutes ago
    const staleTimestamp = Date.now() - 10 * 60 * 1000;
    const response = await apiContext.post('/api/v1/captures', {
      headers: {
        'Content-Type': 'multipart/form-data',
        'X-Device-Id': deviceId,
        'X-Device-Timestamp': staleTimestamp.toString(),
        'X-Device-Signature': 'mock-signature',
        'X-Test-Mode': 'mock-attestation',
      },
    });

    // THEN: Request rejected with timestamp error
    expect(response.status()).toBe(401);
    const body = await response.json();
    expect(body.error.code).toBe('TIMESTAMP_EXPIRED');

    await apiContext.dispose();
  });
});

/**
 * Helper to verify database state after registration
 * (Use when running with direct DB access)
 */
async function verifyDeviceInDatabase(deviceId: string): Promise<boolean> {
  // TODO: Implement direct DB check when running integration tests with DB access
  // For now, verify via API by checking if device can be used for capture
  return true;
}
