/**
 * RealityCam Mobile - Example Unit Tests
 *
 * Minimal tests that work with RN 0.81 + pnpm.
 * For hooks/components requiring React, use separate test files
 * that explicitly import the necessary providers.
 */

// Test utilities from setup
const { createMockPhoto, createMockDepthMap, waitForNextTick } = global.testUtils;

describe('Test Setup Verification', () => {
  test('test utilities are available', () => {
    expect(createMockPhoto).toBeDefined();
    expect(createMockDepthMap).toBeDefined();
    expect(waitForNextTick).toBeDefined();
  });

  test('mock photo has expected structure', () => {
    const photo = createMockPhoto();
    expect(photo.path).toBeDefined();
    expect(photo.width).toBe(4032);
    expect(photo.height).toBe(3024);
  });

  test('mock depth map has expected structure', () => {
    const depthMap = createMockDepthMap();
    expect(depthMap.width).toBe(256);
    expect(depthMap.height).toBe(192);
    expect(depthMap.data).toBeInstanceOf(Float32Array);
    expect(depthMap.data.length).toBe(256 * 192);
  });

  test('custom mock values work', () => {
    const photo = createMockPhoto({ width: 1920, height: 1080 });
    expect(photo.width).toBe(1920);
    expect(photo.height).toBe(1080);
  });
});

describe('Camera Mock Verification', () => {
  test('vision-camera mock is loaded', () => {
    const visionCamera = require('react-native-vision-camera');
    expect(visionCamera.useCameraDevice).toBeDefined();
    expect(visionCamera.Camera).toBeDefined();
  });

  test('camera device returns mock data', () => {
    const { useCameraDevice } = require('react-native-vision-camera');
    const device = useCameraDevice('back');
    expect(device).toBeDefined();
    expect(device.position).toBe('back');
    expect(device.hasFlash).toBe(true);
  });

  test('takePhoto returns mock photo', async () => {
    const { Camera } = require('react-native-vision-camera');
    const photo = await Camera.prototype.takePhoto();
    expect(photo.path).toContain('.jpg');
    expect(photo.width).toBe(4032);
  });
});

describe('Expo Module Mocks', () => {
  test('expo-secure-store mock works', async () => {
    const SecureStore = require('expo-secure-store');
    await SecureStore.setItemAsync('key', 'value');
    expect(SecureStore.setItemAsync).toHaveBeenCalledWith('key', 'value');
  });

  test('expo-crypto mock works', async () => {
    const Crypto = require('expo-crypto');
    const hash = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, 'test');
    expect(hash).toBe('mock-hash-abc123');
  });

  test('expo-file-system mock works', async () => {
    const FileSystem = require('expo-file-system');
    expect(FileSystem.documentDirectory).toBe('/mock/documents/');
    const content = await FileSystem.readAsStringAsync('/path');
    expect(content).toBe('mock-file-content');
  });

  test('expo-location mock works', async () => {
    const Location = require('expo-location');
    const position = await Location.getCurrentPositionAsync();
    expect(position.coords.latitude).toBe(37.7749);
    expect(position.coords.longitude).toBe(-122.4194);
  });

  test('app-integrity mock works', async () => {
    const AppIntegrity = require('@expo/app-integrity');
    const attestation = await AppIntegrity.attestKey('keyId');
    expect(attestation).toBe('mock-attestation-data');
  });
});

describe('Async Operations', () => {
  test('waitForNextTick works', async () => {
    let executed = false;
    setTimeout(() => {
      executed = true;
    }, 0);

    await waitForNextTick();
    expect(executed).toBe(true);
  });

  test('async/await works correctly', async () => {
    const asyncFn = async () => {
      return { success: true };
    };

    const result = await asyncFn();
    expect(result.success).toBe(true);
  });

  test('promise rejection handled', async () => {
    const failingFn = async () => {
      throw new Error('Expected error');
    };

    await expect(failingFn()).rejects.toThrow('Expected error');
  });
});

describe('Zustand Store Pattern', () => {
  test('zustand can create and update stores', () => {
    // Use require instead of dynamic import for Jest compatibility
    // Use dynamic import to get typed create function
    const zustand = require('zustand') as typeof import('zustand');
    const { create } = zustand;

    interface TestStore {
      count: number;
      increment: () => void;
    }

    const useStore = create<TestStore>()((set) => ({
      count: 0,
      increment: () => set((state) => ({ count: state.count + 1 })),
    }));

    expect(useStore.getState().count).toBe(0);
    useStore.getState().increment();
    expect(useStore.getState().count).toBe(1);
  });
});
