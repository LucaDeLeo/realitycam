# Migration Guide: expo-camera to react-native-vision-camera

This guide documents the migration from `expo-camera` to `react-native-vision-camera` for RealityCam, enabling physical lens switching (ultra-wide 0.5x, wide 1x, telephoto 2x).

## Why Migrate?

| Feature | expo-camera | react-native-vision-camera |
|---------|------------|---------------------------|
| Physical lens switching | No (digital zoom only) | Yes (physicalDevices API) |
| Ultra-wide (0.5x) | No | Yes |
| Telephoto (2x/3x) | No | Yes |
| Frame processors | No | Yes (ML, filters, etc.) |
| Performance | Good | Excellent (native perf) |
| Expo Go support | Yes | No (requires dev build) |

**Bottom line:** vision-camera gives us real 0.5x ultra-wide lens access, which expo-camera cannot provide.

---

## Prerequisites

- **Development build required** - No Expo Go support
- Node.js 18+
- Xcode 15+ (for iOS)
- Physical iOS device for testing (simulators don't show multiple lenses)

---

## Phase 1: Installation

### 1.1 Install Dependencies

```bash
# From apps/mobile directory
pnpm add react-native-vision-camera

# Optional: for smooth zoom animations
pnpm add react-native-reanimated
```

### 1.2 Configure Expo Plugin

Update `app.json` or `app.config.ts`:

```json
{
  "expo": {
    "plugins": [
      [
        "react-native-vision-camera",
        {
          "cameraPermissionText": "RealityCam needs camera access to capture verified photos.",
          "enableMicrophonePermission": false,
          "enableLocation": false
        }
      ]
    ]
  }
}
```

### 1.3 Prebuild and Run

```bash
# Generate native projects
npx expo prebuild --platform ios --clean

# Run on device (NOT simulator for lens testing)
npx expo run:ios --device
```

---

## Phase 2: API Migration Reference

### Permissions

**Before (expo-camera):**
```typescript
import { useCameraPermissions } from 'expo-camera';

const [permission, requestPermission] = useCameraPermissions();
if (!permission?.granted) {
  await requestPermission();
}
```

**After (vision-camera):**
```typescript
import { useCameraPermission } from 'react-native-vision-camera';

const { hasPermission, requestPermission } = useCameraPermission();
if (!hasPermission) {
  await requestPermission();
}
```

### Camera Device Selection

**Before (expo-camera):**
```typescript
// No device selection - just front/back
<CameraView facing="back" />
```

**After (vision-camera):**
```typescript
import { useCameraDevice, Camera } from 'react-native-vision-camera';

// Get device with all physical lenses
const device = useCameraDevice('back', {
  physicalDevices: [
    'ultra-wide-angle-camera',  // 0.5x
    'wide-angle-camera',        // 1x
    'telephoto-camera'          // 2x/3x
  ]
});

<Camera device={device} isActive={true} />
```

### Zoom Control

**Before (expo-camera):**
```typescript
// zoom prop: 0-1 (digital zoom only)
<CameraView zoom={0.5} />  // This is digital zoom, NOT 0.5x lens
```

**After (vision-camera):**
```typescript
// zoom prop: minZoom to maxZoom (physical + digital)
// device.neutralZoom = 1x (e.g., 2.0 on iPhone Pro)
// zoom < neutralZoom = ultra-wide
// zoom > neutralZoom = telephoto

const device = useCameraDevice('back', {
  physicalDevices: ['ultra-wide-angle-camera', 'wide-angle-camera', 'telephoto-camera']
});

// Example zoom values for iPhone 15 Pro:
// zoom = 1.0 → ultra-wide (0.5x)
// zoom = 2.0 → wide (1x) - this is device.neutralZoom
// zoom = 4.0 → telephoto (2x)
// zoom = 10.0 → telephoto + digital (5x)

<Camera device={device} zoom={zoomValue} isActive={true} />
```

### Photo Capture

**Before (expo-camera):**
```typescript
const cameraRef = useRef<CameraView>(null);

const photo = await cameraRef.current?.takePictureAsync({
  quality: 1,
  base64: false,
});
// photo.uri contains the file path
```

**After (vision-camera):**
```typescript
const cameraRef = useRef<Camera>(null);

const photo = await cameraRef.current?.takePhoto({
  qualityPrioritization: 'quality',
  enableShutterSound: true,
});
// photo.path contains the file path (no 'file://' prefix)
const uri = `file://${photo.path}`;
```

---

## Phase 3: CameraView.tsx Migration

### 3.1 Updated Imports

```typescript
// Remove
import { CameraView as ExpoCameraView, CameraType, useCameraPermissions } from 'expo-camera';

// Add
import {
  Camera,
  useCameraDevice,
  useCameraPermission,
  CameraPosition,
} from 'react-native-vision-camera';
```

### 3.2 Permission Hook

```typescript
// Remove
const [permission, requestPermission] = useCameraPermissions();

// Add
const { hasPermission, requestPermission } = useCameraPermission();

// Update permission checks
if (!hasPermission) {
  return <PermissionScreen onRequest={requestPermission} />;
}
```

### 3.3 Device Selection with Physical Lenses

```typescript
// Add state for camera position
const [position, setPosition] = useState<CameraPosition>('back');

// Get device with all physical lenses
const device = useCameraDevice(position, {
  physicalDevices: [
    'ultra-wide-angle-camera',
    'wide-angle-camera',
    'telephoto-camera',
  ],
});

// Handle flip camera
const handleFlipCamera = useCallback(() => {
  setPosition((p) => (p === 'back' ? 'front' : 'back'));
}, []);
```

### 3.4 Zoom State Management

```typescript
// Zoom levels for UI buttons
type ZoomLevel = '0.5' | '1' | '2';
const [zoomLevel, setZoomLevel] = useState<ZoomLevel>('1');

// Actual zoom value for camera
const [zoom, setZoom] = useState<number>(1);

// Map UI zoom level to camera zoom value
const handleZoomChange = useCallback((level: ZoomLevel) => {
  if (!device) return;

  setZoomLevel(level);

  // device.neutralZoom is the 1x position (e.g., 2.0 on iPhone Pro)
  const neutralZoom = device.neutralZoom ?? 1;

  switch (level) {
    case '0.5':
      // Ultra-wide: half of neutral zoom
      setZoom(neutralZoom * 0.5);
      break;
    case '1':
      // Wide: neutral zoom
      setZoom(neutralZoom);
      break;
    case '2':
      // Telephoto: double neutral zoom
      setZoom(neutralZoom * 2);
      break;
  }
}, [device]);

// Initialize zoom to 1x when device changes
useEffect(() => {
  if (device?.neutralZoom) {
    setZoom(device.neutralZoom);
  }
}, [device]);
```

### 3.5 Camera Component

```typescript
// Remove
<ExpoCameraView
  ref={setCameraRef}
  style={styles.camera}
  facing={facing}
  mode="picture"
  zoom={zoom}
  onCameraReady={() => setCameraReady(true)}
/>

// Add
{device && (
  <Camera
    ref={cameraRef}
    style={StyleSheet.absoluteFill}
    device={device}
    isActive={true}
    photo={true}
    zoom={zoom}
    onInitialized={() => setCameraReady(true)}
    onError={(error) => console.error('Camera error:', error)}
  />
)}
```

### 3.6 Photo Capture Update

Update `useCapture.ts` or wherever photo capture happens:

```typescript
// Remove
const photo = await cameraRef.current?.takePictureAsync({ quality: 1 });
const uri = photo?.uri;

// Add
const photo = await cameraRef.current?.takePhoto({
  qualityPrioritization: 'quality',
});
const uri = photo ? `file://${photo.path}` : null;
```

---

## Phase 4: Full CameraView.tsx Example

```typescript
import React, { useRef, useState, useCallback, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Platform } from 'react-native';
import {
  Camera,
  useCameraDevice,
  useCameraPermission,
  CameraPosition,
} from 'react-native-vision-camera';
import { Ionicons } from '@expo/vector-icons';
import { CaptureButton } from './CaptureButton';

type ZoomLevel = '0.5' | '1' | '2';

export function CameraView({ onCapture, isCapturing }: CameraViewProps) {
  const cameraRef = useRef<Camera>(null);
  const [cameraReady, setCameraReady] = useState(false);
  const [position, setPosition] = useState<CameraPosition>('back');
  const [zoomLevel, setZoomLevel] = useState<ZoomLevel>('1');
  const [zoom, setZoom] = useState<number>(1);

  // Permissions
  const { hasPermission, requestPermission } = useCameraPermission();

  // Device with all physical lenses
  const device = useCameraDevice(position, {
    physicalDevices: [
      'ultra-wide-angle-camera',
      'wide-angle-camera',
      'telephoto-camera',
    ],
  });

  // Initialize zoom to neutral (1x) when device changes
  useEffect(() => {
    if (device?.neutralZoom) {
      setZoom(device.neutralZoom);
    }
  }, [device]);

  // Handle zoom level change
  const handleZoomChange = useCallback((level: ZoomLevel) => {
    if (!device) return;

    setZoomLevel(level);
    const neutralZoom = device.neutralZoom ?? 1;

    switch (level) {
      case '0.5':
        setZoom(Math.max(device.minZoom, neutralZoom * 0.5));
        break;
      case '1':
        setZoom(neutralZoom);
        break;
      case '2':
        setZoom(Math.min(device.maxZoom, neutralZoom * 2));
        break;
    }
  }, [device]);

  // Handle flip camera
  const handleFlipCamera = useCallback(() => {
    setPosition((p) => (p === 'back' ? 'front' : 'back'));
  }, []);

  // Permission not granted
  if (!hasPermission) {
    return (
      <View style={styles.centered}>
        <Text style={styles.text}>Camera permission required</Text>
        <TouchableOpacity onPress={requestPermission}>
          <Text style={styles.link}>Grant Permission</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // No device available
  if (!device) {
    return (
      <View style={styles.centered}>
        <Text style={styles.text}>No camera device found</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Camera */}
      <Camera
        ref={cameraRef}
        style={StyleSheet.absoluteFill}
        device={device}
        isActive={true}
        photo={true}
        zoom={zoom}
        onInitialized={() => setCameraReady(true)}
        onError={(error) => console.error('Camera error:', error)}
      />

      {/* Controls */}
      <View style={styles.controls}>
        {/* Zoom Selector */}
        <View style={styles.zoomSelector}>
          {(['0.5', '1', '2'] as ZoomLevel[]).map((level) => (
            <TouchableOpacity
              key={level}
              style={[
                styles.zoomButton,
                zoomLevel === level && styles.zoomButtonActive,
              ]}
              onPress={() => handleZoomChange(level)}
            >
              <Text
                style={[
                  styles.zoomText,
                  zoomLevel === level && styles.zoomTextActive,
                ]}
              >
                {level === '0.5' ? '0.5x' : `${level}x`}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* Capture Row */}
        <View style={styles.captureRow}>
          <View style={styles.spacer} />
          <CaptureButton
            onCapture={onCapture}
            isCapturing={isCapturing}
            disabled={!cameraReady}
          />
          <TouchableOpacity
            style={styles.flipButton}
            onPress={handleFlipCamera}
          >
            <Ionicons name="camera-reverse-outline" size={28} color="#FFF" />
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  centered: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  text: { color: '#FFF', fontSize: 16 },
  link: { color: '#FFD60A', fontSize: 16, marginTop: 12 },
  controls: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'flex-end',
    paddingBottom: Platform.OS === 'ios' ? 40 : 30,
  },
  zoomSelector: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 12,
    marginBottom: 20,
  },
  zoomButton: {
    width: 48,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
  },
  zoomButtonActive: {
    backgroundColor: 'rgba(255,255,255,0.9)',
  },
  zoomText: { color: '#FFF', fontSize: 15, fontWeight: '600' },
  zoomTextActive: { color: '#000', fontWeight: '700' },
  captureRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 40,
  },
  spacer: { width: 60 },
  flipButton: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.2)',
  },
});
```

---

## Phase 5: useCapture Hook Migration

Update photo capture to use vision-camera's API:

```typescript
// In useCapture.ts or similar

import { Camera } from 'react-native-vision-camera';

const takePhoto = async (cameraRef: React.RefObject<Camera>) => {
  if (!cameraRef.current) return null;

  try {
    const photo = await cameraRef.current.takePhoto({
      qualityPrioritization: 'quality',
      enableShutterSound: true,
    });

    // vision-camera returns path without 'file://' prefix
    return {
      uri: `file://${photo.path}`,
      width: photo.width,
      height: photo.height,
    };
  } catch (error) {
    console.error('Photo capture failed:', error);
    return null;
  }
};
```

---

## Phase 6: Testing Checklist

### Device Testing (Required)
- [ ] Test on physical iPhone (simulators don't show multiple lenses)
- [ ] Verify 0.5x shows ultra-wide perspective
- [ ] Verify 1x shows standard perspective
- [ ] Verify 2x shows telephoto perspective
- [ ] Test smooth transitions between zoom levels

### Functional Testing
- [ ] Camera permission request works
- [ ] Photo capture returns valid file path
- [ ] Front/back camera switching works
- [ ] Camera initializes without errors
- [ ] No memory leaks on component unmount

### Integration Testing
- [ ] Photos upload correctly to backend
- [ ] Attestation still works with new capture flow
- [ ] Depth capture integration (if applicable)

---

## Troubleshooting

### "No camera device found"
- Ensure you're on a physical device, not simulator
- Check that permissions are granted
- Verify the app was rebuilt after adding the plugin

### Zoom not reaching 0.5x
- Check `device.minZoom` - some devices have different limits
- Ultra-wide may not be available on all device positions (front camera)

### Build failures
```bash
# Clean and rebuild
rm -rf ios/build
npx expo prebuild --platform ios --clean
npx expo run:ios --device
```

### Camera black screen
- Ensure `isActive={true}` is set
- Check that `device` is not null before rendering Camera
- Verify no other app is using the camera

---

## Rollback Plan

If issues arise, revert to expo-camera:

1. Remove vision-camera: `pnpm remove react-native-vision-camera`
2. Remove plugin from app.json
3. Restore original CameraView.tsx from git
4. Rebuild: `npx expo prebuild --clean`

---

## References

- [react-native-vision-camera Docs](https://react-native-vision-camera.com/docs/guides)
- [Device Selection Guide](https://react-native-vision-camera.com/docs/guides/devices)
- [Taking Photos Guide](https://react-native-vision-camera.com/docs/guides/taking-photos)
- [Zooming Guide](https://react-native-vision-camera.com/docs/guides/zooming)
- [Expo Config Plugin](https://react-native-vision-camera.com/docs/guides/getting-started)

---

## Estimated Migration Time

| Task | Time |
|------|------|
| Installation & config | 30 min |
| CameraView.tsx migration | 2-3 hours |
| useCapture hook updates | 1-2 hours |
| Testing & debugging | 2-3 hours |
| **Total** | **6-8 hours** |
