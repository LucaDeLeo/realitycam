/**
 * Vitest Setup for RealityCam Mobile
 *
 * Configures testing-library and mocks for React Native/Expo
 */

import { vi } from 'vitest';

// Mock React Native modules that aren't available in jsdom
vi.mock('react-native', () => ({
  Platform: {
    OS: 'ios',
    select: (obj: Record<string, unknown>) => obj.ios,
  },
  StyleSheet: {
    create: (styles: Record<string, unknown>) => styles,
    flatten: (style: unknown) => style,
  },
  Dimensions: {
    get: () => ({ width: 390, height: 844 }), // iPhone 14 Pro dimensions
  },
  PixelRatio: {
    get: () => 3,
    getFontScale: () => 1,
  },
  NativeModules: {},
  NativeEventEmitter: vi.fn(() => ({
    addListener: vi.fn(),
    removeListeners: vi.fn(),
  })),
}));

// Mock Expo modules
vi.mock('expo-camera', () => ({
  Camera: {
    requestCameraPermissionsAsync: vi.fn(() =>
      Promise.resolve({ status: 'granted' })
    ),
    getCameraPermissionsAsync: vi.fn(() =>
      Promise.resolve({ status: 'granted' })
    ),
  },
  CameraType: {
    back: 'back',
    front: 'front',
  },
}));

vi.mock('expo-secure-store', () => ({
  getItemAsync: vi.fn(),
  setItemAsync: vi.fn(),
  deleteItemAsync: vi.fn(),
}));

vi.mock('expo-crypto', () => ({
  digestStringAsync: vi.fn(() => Promise.resolve('mock-sha256-hash')),
  CryptoDigestAlgorithm: {
    SHA256: 'SHA-256',
  },
}));

vi.mock('expo-file-system', () => ({
  documentDirectory: '/mock/documents/',
  cacheDirectory: '/mock/cache/',
  writeAsStringAsync: vi.fn(),
  readAsStringAsync: vi.fn(),
  deleteAsync: vi.fn(),
  getInfoAsync: vi.fn(() => Promise.resolve({ exists: false })),
}));

vi.mock('expo-location', () => ({
  requestForegroundPermissionsAsync: vi.fn(() =>
    Promise.resolve({ status: 'granted' })
  ),
  getCurrentPositionAsync: vi.fn(() =>
    Promise.resolve({
      coords: {
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 10,
        accuracy: 5,
      },
    })
  ),
}));

// Mock custom device attestation module
vi.mock('./modules/device-attestation', () => ({
  DeviceAttestation: {
    isSupported: vi.fn(() => Promise.resolve(true)),
    hasLiDAR: vi.fn(() => Promise.resolve(true)),
    generateAttestationKey: vi.fn(() =>
      Promise.resolve({
        keyId: 'mock-key-id',
        publicKey: 'mock-public-key',
      })
    ),
    createAttestation: vi.fn(() =>
      Promise.resolve({
        attestationObject: 'mock-attestation-object',
      })
    ),
    signData: vi.fn(() => Promise.resolve('mock-signature')),
  },
  LiDARCapture: {
    isAvailable: vi.fn(() => Promise.resolve(true)),
    captureDepthMap: vi.fn(() =>
      Promise.resolve({
        depthData: new Float32Array(1000),
        width: 256,
        height: 192,
      })
    ),
  },
}));

// Mock Zustand store (reset between tests)
const mockStore = new Map();

vi.mock('zustand', () => ({
  create: (initializer: Function) => {
    const store = initializer(() => {}, () => {}, {});
    mockStore.set(initializer, store);
    return () => store;
  },
}));

// Environment variables
process.env.EXPO_PUBLIC_API_URL = 'http://localhost:3001/api';

// Reset mocks between tests
afterEach(() => {
  vi.clearAllMocks();
  mockStore.clear();
});
