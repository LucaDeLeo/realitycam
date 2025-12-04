import { ExpoConfig, ConfigContext } from 'expo/config';

// Extended iOS config to include developmentTeam (valid Expo option not in types)
interface ExtendedIOS extends NonNullable<ExpoConfig['ios']> {
  developmentTeam?: string;
}

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'rial.',
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
  android: {
    package: 'com.realitycam.app',
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: 'com.realitycam.app',
    developmentTeam: process.env.EXPO_DEVELOPMENT_TEAM,
    infoPlist: {
      NSCameraUsageDescription: 'rial. needs camera access to capture authenticated photos.',
      NSLocationWhenInUseUsageDescription: 'rial. needs location access to include GPS data in photo evidence.',
    },
  } as ExtendedIOS,
  plugins: [
    'expo-router',
    'expo-secure-store',
    // expo-haptics doesn't need a config plugin, it works without one
    [
      'react-native-vision-camera',
      {
        cameraPermissionText: 'rial. needs camera access to capture verified photos.',
        enableMicrophonePermission: false,
        enableLocation: false,
      },
    ],
    [
      'expo-location',
      {
        locationWhenInUsePermission: 'rial. uses your location to record where photos were captured. Location is optional and you can deny this permission.',
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
    // Note: LiDAR depth module is autolinked from modules/lidar-depth via expo-modules-autolinking
  ],
  experiments: {
    typedRoutes: true,
  },
});
