# Camera Zoom Implementation Notes

## Current Status (Expo Go)

### Working:
- ✅ **1x zoom** - Default camera lens
- ✅ **2x zoom** - Digital zoom (zoom value: 0.5)

### Limited:
- ⚠️ **0.5x (Ultra-wide)** - NOT available in Expo Go
  - Requires native module to access iPhone's ultra-wide lens
  - Currently shows button but doesn't change lens

## Why 0.5x doesn't work in Expo Go

Expo Camera in Expo Go doesn't expose the multiple physical lenses of iPhone Pro:
- **Ultra-wide lens (0.5x)** - Separate physical camera
- **Wide lens (1x)** - Main camera  
- **Telephoto lens (2x/3x)** - Separate physical camera (on some models)

The `zoom` prop in `expo-camera` only does **digital zoom** (0-1 range), not lens switching.

## Solution: Development Build with Native Module

To access native iPhone lenses (including ultra-wide 0.5x), you need:

### Option A: Use `expo-camera` with device types (Future)
Wait for Expo SDK to add device type support similar to React Native Vision Camera.

### Option B: Create Native Module (Recommended for now)

1. **Create native module** `CameraLensModule` in Swift:
```swift
import AVFoundation

class CameraLensModule {
    func getAvailableDevices() -> [String] {
        // Return: ["ultra-wide", "wide", "telephoto"]
    }
    
    func switchToLens(type: String) {
        // Switch between .builtInUltraWideCamera, .builtInWideAngleCamera, etc.
    }
}
```

2. **Make development build:**
```bash
cd apps/mobile
npx expo prebuild --platform ios
npx expo run:ios --device
```

3. **Use in app:**
```typescript
import CameraLensModule from './modules/camera-lens';

// Switch to ultra-wide
await CameraLensModule.switchToLens('ultra-wide');
```

### Option C: Use React Native Vision Camera

Alternative: Replace `expo-camera` with `react-native-vision-camera` which has full native lens support:

```bash
npm install react-native-vision-camera
```

```typescript
import { Camera, useCameraDevice } from 'react-native-vision-camera';

const device = useCameraDevice('back', {
  physicalDevices: ['ultra-wide-angle-camera']
});
```

## Current Implementation

File: `apps/mobile/components/Camera/CameraView.tsx`

```typescript
const handleZoomChange = (level: '0.5' | '1' | '2') => {
  if (level === '0.5') {
    console.warn('Ultra-wide (0.5x) not available in Expo Go');
    // Would need: await CameraLensModule.switchToLens('ultra-wide');
  } else if (level === '1') {
    setZoom(0); // Main lens, no digital zoom
  } else if (level === '2') {
    setZoom(0.5); // 2x digital zoom
  }
};
```

## Testing

### In Expo Go:
- 0.5x button shows but doesn't switch lens (logs warning)
- 1x works (default)
- 2x works (digital zoom)

### In Development Build (after native module):
- 0.5x switches to ultra-wide physical lens ✅
- 1x switches to main physical lens ✅  
- 2x switches to telephoto or uses digital zoom ✅

## Recommendation

For production app with full camera control:
1. Build native module for lens switching OR
2. Switch to `react-native-vision-camera`
3. Create development build (not Expo Go)

For now in Expo Go:
- Keep 0.5x button for UI consistency
- Show visual feedback that it's selected
- But lens won't actually switch until development build
