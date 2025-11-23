import { ExpoConfig, ConfigContext } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'RealityCam',
  slug: 'realitycam',
  version: '0.1.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  userInterfaceStyle: 'automatic',
  newArchEnabled: true,
  scheme: 'realitycam',
  splash: {
    image: './assets/splash-icon.png',
    resizeMode: 'contain',
    backgroundColor: '#ffffff',
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: 'com.realitycam.app',
    infoPlist: {
      NSCameraUsageDescription: 'RealityCam needs camera access to capture authenticated photos.',
      NSLocationWhenInUseUsageDescription: 'RealityCam needs location access to include GPS data in photo evidence.',
    },
  },
  plugins: [
    'expo-router',
    'expo-secure-store',
    [
      'expo-camera',
      {
        cameraPermission: 'RealityCam needs camera access to capture authenticated photos.',
      },
    ],
    [
      'expo-build-properties',
      {
        ios: {
          deploymentTarget: '15.1',
        },
      },
    ],
  ],
  experiments: {
    typedRoutes: true,
  },
});
