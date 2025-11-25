/**
 * RealityCam Mobile - Jest Test Setup
 *
 * Minimal setup that avoids RN 0.81 compatibility issues.
 * Full mocks are loaded lazily in tests that need them.
 */

// Only import RNTL extend-expect if it's being used
// This avoids triggering react-native setup issues
try {
  require('@testing-library/react-native/extend-expect');
} catch {
  // RNTL not available or not needed for this test
}

// Mock react-native-vision-camera (device-dependent)
// Use inline mock to avoid circular require
jest.mock('react-native-vision-camera', () => {
  const mockPhotoFile = {
    path: '/mock/photos/captured.jpg',
    width: 4032,
    height: 3024,
    orientation: 'portrait',
    isMirrored: false,
    isRawPhoto: false,
    metadata: { Orientation: 1, DPIHeight: 72, DPIWidth: 72 },
  };

  const mockCameraDevice = {
    id: 'mock-camera-id',
    devices: ['wide-angle-camera', 'ultra-wide-angle-camera'],
    hasFlash: true,
    hasTorch: true,
    isMultiCam: true,
    maxExposure: 8,
    maxZoom: 10,
    minExposure: -8,
    minFocusDistance: 0,
    minZoom: 1,
    name: 'Mock Camera (Back)',
    neutralZoom: 1,
    physicalDevices: ['wide-angle-camera', 'ultra-wide-angle-camera'],
    position: 'back',
    supportsFocus: true,
    supportsLowLightBoost: true,
    supportsRawCapture: false,
    formats: [],
    hardwareLevel: 'full',
    sensorOrientation: 'landscape-right',
  };

  const Camera = jest.fn().mockImplementation(({ children }) => children);
  Camera.prototype.takePhoto = jest.fn().mockResolvedValue(mockPhotoFile);
  Camera.prototype.focus = jest.fn().mockResolvedValue(undefined);

  return {
    Camera,
    useCameraDevice: jest.fn().mockReturnValue(mockCameraDevice),
    useCameraDevices: jest.fn().mockReturnValue({ back: mockCameraDevice, front: { ...mockCameraDevice, position: 'front' } }),
    useCameraFormat: jest.fn().mockReturnValue({ photoHeight: 3024, photoWidth: 4032 }),
    useCameraPermission: jest.fn().mockReturnValue({ hasPermission: true, requestPermission: jest.fn().mockResolvedValue(true) }),
    useFrameProcessor: jest.fn().mockReturnValue(undefined),
    getCameraDevice: jest.fn().mockReturnValue(mockCameraDevice),
    requestCameraPermission: jest.fn().mockResolvedValue('granted'),
  };
});

// Mock expo-secure-store
jest.mock('expo-secure-store', () => ({
  getItemAsync: jest.fn().mockResolvedValue(null),
  setItemAsync: jest.fn().mockResolvedValue(undefined),
  deleteItemAsync: jest.fn().mockResolvedValue(undefined),
}));

// Mock expo-crypto
jest.mock('expo-crypto', () => ({
  digestStringAsync: jest.fn().mockResolvedValue('mock-hash-abc123'),
  CryptoDigestAlgorithm: {
    SHA256: 'SHA-256',
    SHA512: 'SHA-512',
  },
}));

// Mock expo-file-system
jest.mock('expo-file-system', () => ({
  documentDirectory: '/mock/documents/',
  cacheDirectory: '/mock/cache/',
  readAsStringAsync: jest.fn().mockResolvedValue('mock-file-content'),
  writeAsStringAsync: jest.fn().mockResolvedValue(undefined),
  deleteAsync: jest.fn().mockResolvedValue(undefined),
  getInfoAsync: jest.fn().mockResolvedValue({ exists: true, size: 1024 }),
  makeDirectoryAsync: jest.fn().mockResolvedValue(undefined),
}));

// Mock expo-location
jest.mock('expo-location', () => ({
  requestForegroundPermissionsAsync: jest.fn().mockResolvedValue({ status: 'granted' }),
  getCurrentPositionAsync: jest.fn().mockResolvedValue({
    coords: {
      latitude: 37.7749,
      longitude: -122.4194,
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      speed: 0,
    },
    timestamp: Date.now(),
  }),
}));

// Mock @expo/app-integrity
jest.mock('@expo/app-integrity', () => ({
  attestKey: jest.fn().mockResolvedValue('mock-attestation-data'),
  generateAssertion: jest.fn().mockResolvedValue('mock-assertion'),
  isSupported: jest.fn().mockResolvedValue(true),
}));

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);

// Mock NetInfo
jest.mock('@react-native-community/netinfo', () => ({
  addEventListener: jest.fn(() => jest.fn()),
  fetch: jest.fn().mockResolvedValue({
    isConnected: true,
    isInternetReachable: true,
    type: 'wifi',
  }),
}));

// Global test utilities
global.testUtils = {
  waitForNextTick: () => new Promise((resolve) => setTimeout(resolve, 0)),

  createMockPhoto: (overrides = {}) => ({
    path: '/mock/photos/test.jpg',
    width: 4032,
    height: 3024,
    orientation: 'portrait',
    isMirrored: false,
    ...overrides,
  }),

  createMockDepthMap: (overrides = {}) => ({
    width: 256,
    height: 192,
    data: new Float32Array(256 * 192).fill(1.5),
    minDepth: 0.5,
    maxDepth: 5.0,
    ...overrides,
  }),
};

// TypeScript declaration for global test utilities
declare global {
  var testUtils: {
    waitForNextTick: () => Promise<void>;
    createMockPhoto: (overrides?: Record<string, unknown>) => {
      path: string;
      width: number;
      height: number;
      orientation: 'portrait' | 'landscape';
      isMirrored: boolean;
    };
    createMockDepthMap: (overrides?: Record<string, unknown>) => {
      width: number;
      height: number;
      data: Float32Array;
      minDepth: number;
      maxDepth: number;
    };
  };
}
