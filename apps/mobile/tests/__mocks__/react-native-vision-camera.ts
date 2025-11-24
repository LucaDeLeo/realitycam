/**
 * Mock for react-native-vision-camera
 *
 * Provides mock implementations for camera functions that
 * require physical device hardware.
 */

import type { PhotoFile, CameraDevice } from 'react-native-vision-camera';

// Mock photo result
const mockPhotoFile: PhotoFile = {
  path: '/mock/photos/captured.jpg',
  width: 4032,
  height: 3024,
  orientation: 'portrait',
  isMirrored: false,
  isRawPhoto: false,
  metadata: {
    Orientation: 1,
    DPIHeight: 72,
    DPIWidth: 72,
  },
};

// Mock camera device
const mockCameraDevice: CameraDevice = {
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

// Mock Camera component
export const Camera = jest.fn().mockImplementation(({ children }) => children);

// Mock camera ref methods
Camera.prototype.takePhoto = jest.fn().mockResolvedValue(mockPhotoFile);
Camera.prototype.focus = jest.fn().mockResolvedValue(undefined);
Camera.prototype.getAvailableCameraDevices = jest.fn().mockReturnValue([mockCameraDevice]);

// Hook mocks
export const useCameraDevice = jest.fn().mockReturnValue(mockCameraDevice);

export const useCameraDevices = jest.fn().mockReturnValue({
  back: mockCameraDevice,
  front: { ...mockCameraDevice, position: 'front', name: 'Mock Camera (Front)' },
});

export const useCameraFormat = jest.fn().mockReturnValue({
  photoHeight: 3024,
  photoWidth: 4032,
  videoHeight: 1080,
  videoWidth: 1920,
  maxISO: 3200,
  minISO: 50,
  maxFps: 60,
  minFps: 1,
  supportsPhotoHdr: true,
  supportsVideoHdr: false,
  autoFocusSystem: 'phase-detection',
  fieldOfView: 69,
});

export const useCameraPermission = jest.fn().mockReturnValue({
  hasPermission: true,
  requestPermission: jest.fn().mockResolvedValue(true),
});

export const useMicrophonePermission = jest.fn().mockReturnValue({
  hasPermission: true,
  requestPermission: jest.fn().mockResolvedValue(true),
});

// Frame processor mocks
export const useFrameProcessor = jest.fn().mockReturnValue(undefined);
export const runAtTargetFps = jest.fn((fps, callback) => callback);
export const useRunOnJS = jest.fn((callback) => callback);

// Worklet mocks
export function createWorkletRuntime() {
  return {};
}

// Static methods
export const getCameraDevice = jest.fn().mockReturnValue(mockCameraDevice);
export const getAvailableCameraDevices = jest.fn().mockReturnValue([mockCameraDevice]);

// Permission utilities
export const requestCameraPermission = jest.fn().mockResolvedValue('granted');
export const requestMicrophonePermission = jest.fn().mockResolvedValue('granted');
export const getCameraPermissionStatus = jest.fn().mockReturnValue('granted');
export const getMicrophonePermissionStatus = jest.fn().mockReturnValue('granted');

// Constants
export const CameraPosition = {
  back: 'back',
  front: 'front',
} as const;

export const Orientation = {
  portrait: 'portrait',
  portraitUpsideDown: 'portrait-upside-down',
  landscapeLeft: 'landscape-left',
  landscapeRight: 'landscape-right',
} as const;

// Export mock data for tests
export const __mockPhotoFile = mockPhotoFile;
export const __mockCameraDevice = mockCameraDevice;

// Helper to customize mock behavior in tests
export const __setMockPhoto = (photo: Partial<PhotoFile>) => {
  Camera.prototype.takePhoto.mockResolvedValue({ ...mockPhotoFile, ...photo });
};

export const __setMockDevice = (device: Partial<CameraDevice>) => {
  useCameraDevice.mockReturnValue({ ...mockCameraDevice, ...device });
};
