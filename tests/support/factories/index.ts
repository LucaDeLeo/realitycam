/**
 * Test Data Factories for RealityCam
 *
 * Usage:
 *   import { deviceFactory, captureFactory } from '../support/factories';
 *
 *   const device = deviceFactory.withSecureEnclave().build();
 *   const capture = captureFactory.forDevice(device.id).withRealSceneDepth().build();
 */

export { DeviceFactory, deviceFactory } from './device.factory';
export type { Device, DeviceRegistrationRequest } from './device.factory';

export { CaptureFactory, captureFactory } from './capture.factory';
export type { Capture, CaptureMetadata, Evidence, DepthMap } from './capture.factory';

// Re-export faker for custom data generation
export { faker } from '@faker-js/faker';
