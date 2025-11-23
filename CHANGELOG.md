# Changelog

All notable changes to RealityCam will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Physical lens switching support (0.5x ultra-wide, 1x wide, 2x telephoto) via `react-native-vision-camera`
- Auto-permission request on camera view mount
- Loading states for permission request and camera initialization
- Depth toggle control in camera UI

### Changed
- **BREAKING**: Migrated from `expo-camera` to `react-native-vision-camera` v4.7.3
  - Requires development build (Expo Go no longer supported for camera features)
  - Photo capture API changed: `takePictureAsync()` → `takePhoto()`
  - Photo result format changed: `photo.uri` → `file://${photo.path}`
  - Permission hook changed: `useCameraPermissions()` → `useCameraPermission()`
- Increased photo/depth sync tolerance from 100ms to 250ms for vision-camera timing
- Zoom buttons now properly disabled when lens not available (vs showing alert)
- Camera device selection now auto-selects multi-camera setup on Pro devices

### Removed
- `expo-camera` dependency
- Expo Go camera support (now requires `npx expo prebuild` + `npx expo run:ios --device`)
- Digital-only zoom implementation (replaced with physical lens switching)

### Fixed
- Redundant `&&` guards in zoom button `onPress` handlers (already had `disabled` prop)
- Comment in `useCapture.ts` incorrectly stating 100ms sync window (now 250ms)
- Unused `isDepthReady` in capture hook dependency array

### Migration Notes

To test after this change:

```bash
cd apps/mobile
npx expo prebuild --platform ios --clean
npx expo run:ios --device
```

**Requirements:**
- Physical iPhone (simulators don't support multi-lens)
- Xcode installed with signing configured
- Apple Developer account (free tier works)

See `apps/mobile/VISION-CAMERA-MIGRATION.md` for detailed migration guide.

---

## [0.1.0] - 2025-11-22

### Added
- Initial MVP implementation
- iPhone Pro camera capture with LiDAR depth overlay
- Device attestation via DCAppAttest (@expo/app-integrity)
- Secure Enclave key generation
- Photo + depth + location synchronized capture
- Per-capture attestation signatures
- Local capture processing pipeline (hash, compress, metadata)
- Preview screen with capture details
- Upload to backend with device signature authentication
- Offline capture queue with encrypted local storage
- Verification result screen with shareable link
