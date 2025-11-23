# Epic Technical Specification: Photo Capture with LiDAR Depth

Date: 2025-11-23
Author: Luca
Epic ID: 3
Status: Draft

---

## Overview

Epic 3 implements the core photo capture experience with simultaneous LiDAR depth sensing - the primary authenticity signal that distinguishes RealityCam from simple photo provenance tools. This epic delivers the mobile capture workflow where users photograph real 3D scenes, with depth maps proving the camera pointed at physical reality rather than flat screens or printed images.

The epic is entirely mobile-focused (Expo/React Native with custom Swift module), building upon the device attestation infrastructure from Epic 2. It establishes the capture pipeline that feeds into Epic 4's upload and evidence processing. The LiDAR depth capture requires a custom Expo Module (~400 lines Swift) to access ARKit's depth APIs - no existing library provides this capability.

**Business Value:** Users can capture photos that include 3D depth data proving they photographed a real scene (not a screen or flat image). Each capture is cryptographically signed by the attested device, creating an unbroken chain of trust from hardware to evidence.

**FRs Covered:** FR6-FR13 (Capture Flow and Local Processing)

## Objectives and Scope

### Objectives

1. **Create Custom LiDAR Module** - Build Expo Module in Swift to access ARKit depth APIs
2. **Camera View with Depth Overlay** - Display real-time LiDAR visualization during capture
3. **Synchronized Photo + Depth Capture** - Capture photo and depth map within 100ms of each other
4. **GPS Metadata Collection** - Record location with user permission (optional)
5. **Per-Capture Attestation** - Generate device assertion for each photo using @expo/app-integrity
6. **Local Processing Pipeline** - Compute hash, compress depth map, construct structured payload
7. **Capture Preview Screen** - Show captured photo with depth visualization before upload

### In Scope

| Component | Scope |
|-----------|-------|
| Mobile | Camera view, depth overlay, capture button, preview screen |
| Custom Module | Swift LiDAR module using ARKit (iOS only) |
| State Management | Capture state, pending captures queue |
| Local Storage | Temporary capture storage before upload |
| Location Services | GPS capture with permission handling |
| Cryptography | SHA-256 hashing, per-capture assertions |

### Out of Scope

- Upload to backend (Epic 4)
- Offline encrypted storage (Epic 4)
- Backend depth analysis (Epic 4)
- C2PA manifest generation (Epic 5)
- Video capture (post-MVP)
- Gyroscope/accelerometer data (post-MVP)

## System Architecture Alignment

### Components Referenced

| Component | Location | Role |
|-----------|----------|------|
| Mobile App | `apps/mobile/` | All capture UI and logic |
| LiDAR Module | `apps/mobile/modules/lidar-depth/` | Custom ARKit depth capture |
| Camera Screen | `apps/mobile/app/(tabs)/capture.tsx` | Main capture interface |
| Preview Screen | `apps/mobile/app/preview.tsx` | Pre-upload review |
| Shared Types | `packages/shared/` | Capture and metadata types |

### Architecture Patterns Applied

1. **Expo Modules API for LiDAR (ADR-002):** Custom Swift module for ARKit depth - no existing library provides this
2. **@expo/app-integrity (ADR-007):** Per-capture assertions via `generateAssertionAsync()`
3. **iPhone Pro Only (ADR-001):** LiDAR check gates capture flow
4. **Device-Based Auth (ADR-005):** Assertions bound to attested device key

### Technology Stack

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| Camera | expo-camera | ~17.0.0 | Photo capture |
| LiDAR | Custom Expo Module | - | ARKit depth access |
| Location | expo-location | ~19.0.0 | GPS coordinates |
| Crypto | expo-crypto | ~15.0.0 | SHA-256 hashing |
| Storage | expo-file-system | ~19.0.0 | Temporary capture storage |
| Attestation | @expo/app-integrity | ~1.0.0 | Per-capture assertions |
| State | zustand | ^5.0.0 | Capture state management |
| Compression | pako | ^2.1.0 | Gzip depth map compression |

### Constraints

- ARKit requires iOS 14.0+ and iPhone Pro hardware
- LiDAR depth resolution is typically 256x192 pixels
- Depth capture adds ~100-200ms to capture time
- Location requires explicit user permission (optional)
- Photo resolution varies by device (up to 4032x3024)

## Detailed Design

### Services and Modules

#### Custom LiDAR Module (Swift)

| File | Location | Responsibilities |
|------|----------|------------------|
| LiDARDepthModule.swift | `modules/lidar-depth/ios/` | Expo Module entry point, TypeScript bridge |
| DepthCaptureSession.swift | `modules/lidar-depth/ios/` | ARSession management, depth extraction |
| index.ts | `modules/lidar-depth/` | TypeScript exports and types |
| expo-module.config.json | `modules/lidar-depth/` | Expo module configuration |

**Module API:**

```typescript
// modules/lidar-depth/index.ts
export interface DepthFrame {
  depthMap: Float32Array;     // Width x Height float32 values (meters)
  width: number;              // Typically 256
  height: number;             // Typically 192
  timestamp: number;          // Unix ms
  intrinsics: CameraIntrinsics;
}

export interface CameraIntrinsics {
  fx: number;  // Focal length X
  fy: number;  // Focal length Y
  cx: number;  // Principal point X
  cy: number;  // Principal point Y
}

export interface LiDARModule {
  isLiDARAvailable(): Promise<boolean>;
  startDepthCapture(): Promise<void>;
  stopDepthCapture(): Promise<void>;
  captureDepthFrame(): Promise<DepthFrame>;
  addDepthFrameListener(callback: (frame: DepthFrame) => void): Subscription;
}
```

#### Mobile Hooks

| Hook | Location | Responsibilities |
|------|----------|------------------|
| useLiDAR | `hooks/useLiDAR.ts` | Wrap LiDAR module, manage ARSession lifecycle |
| useCapture | `hooks/useCapture.ts` | Orchestrate photo + depth capture |
| useLocation | `hooks/useLocation.ts` | GPS permission and capture |
| useCaptureAssertion | `hooks/useCaptureAssertion.ts` | Generate per-capture device assertions |
| useCaptureProcessor | `hooks/useCaptureProcessor.ts` | Hash, compress, construct payload |

#### Mobile Components

| Component | Location | Responsibilities |
|-----------|----------|------------------|
| CameraView | `components/Camera/CameraView.tsx` | Camera preview container |
| DepthOverlay | `components/Camera/DepthOverlay.tsx` | Real-time depth visualization |
| CaptureButton | `components/Camera/CaptureButton.tsx` | Shutter button with haptic |
| DepthToggle | `components/Camera/DepthToggle.tsx` | Toggle depth overlay on/off |
| PreviewImage | `components/Preview/PreviewImage.tsx` | Photo with optional depth overlay |
| MetadataDisplay | `components/Preview/MetadataDisplay.tsx` | Capture time, location, device |
| ActionButtons | `components/Preview/ActionButtons.tsx` | Upload, discard, capture another |

#### State Management

| Store | Location | Responsibilities |
|-------|----------|------------------|
| captureStore | `store/captureStore.ts` | Capture state, pending queue, current capture |

### Data Models and Contracts

#### TypeScript Types (Capture)

```typescript
// packages/shared/src/types/capture.ts

// Capture status lifecycle
type CaptureStatus =
  | 'capturing'      // Photo + depth being taken
  | 'processing'     // Local processing (hash, compress)
  | 'ready'          // Ready for upload
  | 'uploading'      // Upload in progress (Epic 4)
  | 'completed'      // Upload successful
  | 'failed';        // Upload failed

// Raw capture from device
interface RawCapture {
  id: string;                    // Local UUID
  photoUri: string;              // Local file URI
  photoBytes: Uint8Array;        // JPEG bytes
  depthFrame: DepthFrame;        // From LiDAR module
  capturedAt: string;            // ISO timestamp
  deviceModel: string;           // "iPhone 15 Pro"
}

// Location data (optional)
interface CaptureLocation {
  latitude: number;              // 6 decimal places
  longitude: number;
  altitude?: number;             // Meters above sea level
  accuracy: number;              // Horizontal accuracy in meters
  timestamp: string;             // GPS fix time
}

// Processed capture ready for upload
interface ProcessedCapture {
  id: string;
  photoUri: string;
  photoHash: string;             // SHA-256 base64
  compressedDepthMap: Uint8Array; // Gzipped float32 array
  depthDimensions: {
    width: number;
    height: number;
  };
  metadata: CaptureMetadata;
  assertion: string;             // Base64 device assertion
  status: CaptureStatus;
  createdAt: string;
}

// Metadata for upload payload
interface CaptureMetadata {
  captured_at: string;           // ISO timestamp
  device_model: string;
  photo_hash: string;            // SHA-256 base64
  depth_map_dimensions: {
    width: number;
    height: number;
  };
  location?: CaptureLocation;
  assertion: string;             // Base64 per-capture assertion
}

// Capture store state
interface CaptureState {
  currentCapture: ProcessedCapture | null;
  pendingCaptures: ProcessedCapture[];
  isCapturing: boolean;
  isProcessing: boolean;
  error: string | null;

  // Actions
  startCapture: () => void;
  setRawCapture: (raw: RawCapture) => void;
  setProcessedCapture: (processed: ProcessedCapture) => void;
  discardCurrentCapture: () => void;
  moveToPending: () => void;
  removePending: (id: string) => void;
}
```

#### Depth Visualization Types

```typescript
// Depth colormap for visualization
interface DepthColormap {
  name: 'viridis' | 'plasma' | 'thermal';
  minDepth: number;   // Meters (default 0)
  maxDepth: number;   // Meters (default 5)
  opacity: number;    // 0-1 (default 0.4)
}

// Depth overlay configuration
interface DepthOverlayConfig {
  enabled: boolean;
  colormap: DepthColormap;
  showDepthValues: boolean;  // Show numeric depth on tap
}
```

### APIs and Interfaces

#### LiDAR Module Swift Implementation

```swift
// modules/lidar-depth/ios/LiDARDepthModule.swift
import ExpoModulesCore
import ARKit

public class LiDARDepthModule: Module {
  private var session: ARSession?
  private var depthDelegate: DepthCaptureDelegate?

  public func definition() -> ModuleDefinition {
    Name("LiDARDepth")

    // Check if LiDAR is available
    AsyncFunction("isLiDARAvailable") { () -> Bool in
      return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // Start depth capture session
    AsyncFunction("startDepthCapture") { () in
      guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
        throw LiDARError.notAvailable
      }

      let config = ARWorldTrackingConfiguration()
      config.frameSemantics = .sceneDepth

      self.session = ARSession()
      self.depthDelegate = DepthCaptureDelegate(module: self)
      self.session?.delegate = self.depthDelegate
      self.session?.run(config)
    }

    // Stop depth capture session
    AsyncFunction("stopDepthCapture") { () in
      self.session?.pause()
      self.session = nil
    }

    // Capture single depth frame
    AsyncFunction("captureDepthFrame") { () -> [String: Any] in
      guard let frame = self.session?.currentFrame,
            let depthData = frame.sceneDepth else {
        throw LiDARError.noDepthData
      }

      let depthMap = self.extractDepthMap(from: depthData.depthMap)
      let intrinsics = frame.camera.intrinsics

      return [
        "depthMap": depthMap.base64EncodedString(),
        "width": CVPixelBufferGetWidth(depthData.depthMap),
        "height": CVPixelBufferGetHeight(depthData.depthMap),
        "timestamp": Int64(frame.timestamp * 1000),
        "intrinsics": [
          "fx": intrinsics[0][0],
          "fy": intrinsics[1][1],
          "cx": intrinsics[2][0],
          "cy": intrinsics[2][1]
        ]
      ]
    }

    // Event for real-time depth frames
    Events("onDepthFrame")
  }

  private func extractDepthMap(from pixelBuffer: CVPixelBuffer) -> Data {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!

    // Convert Float32 depth values to Data
    let floatPointer = baseAddress.assumingMemoryBound(to: Float32.self)
    let count = width * height
    let data = Data(bytes: floatPointer, count: count * MemoryLayout<Float32>.size)

    return data
  }
}

// modules/lidar-depth/ios/DepthCaptureSession.swift
class DepthCaptureDelegate: NSObject, ARSessionDelegate {
  weak var module: LiDARDepthModule?
  private var frameCount = 0

  init(module: LiDARDepthModule) {
    self.module = module
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // Emit depth frames at ~30fps for overlay
    frameCount += 1
    if frameCount % 2 == 0 { // 30fps from 60fps ARKit
      guard let depthData = frame.sceneDepth else { return }

      // Send event to JS for real-time overlay
      module?.sendEvent("onDepthFrame", [
        "timestamp": Int64(frame.timestamp * 1000),
        "hasDepth": true
      ])
    }
  }
}

enum LiDARError: Error {
  case notAvailable
  case noDepthData
}
```

#### Capture Flow Hook

```typescript
// hooks/useCapture.ts
import { useCallback, useState } from 'react';
import { Camera } from 'expo-camera';
import * as Crypto from 'expo-crypto';
import * as FileSystem from 'expo-file-system';
import * as AppIntegrity from '@expo/app-integrity';
import pako from 'pako';

import { useLiDAR } from './useLiDAR';
import { useLocation } from './useLocation';
import { useCaptureStore } from '../store/captureStore';
import { useDeviceStore } from '../store/deviceStore';

export function useCapture() {
  const { captureDepthFrame, isDepthReady } = useLiDAR();
  const { getCurrentLocation, hasPermission: hasLocationPermission } = useLocation();
  const { keyId, deviceModel } = useDeviceStore();
  const {
    setRawCapture,
    setProcessedCapture,
    isCapturing,
    isProcessing
  } = useCaptureStore();

  const [cameraRef, setCameraRef] = useState<Camera | null>(null);

  const capture = useCallback(async () => {
    if (!cameraRef || !isDepthReady || !keyId) {
      throw new Error('Capture not ready');
    }

    // 1. Capture photo
    const photo = await cameraRef.takePictureAsync({
      quality: 1,
      base64: false,
      exif: true,
    });

    // 2. Capture depth (within 100ms)
    const depthFrame = await captureDepthFrame();

    // 3. Get location if permitted
    let location = undefined;
    if (hasLocationPermission) {
      try {
        location = await getCurrentLocation();
      } catch (e) {
        console.warn('Location capture failed:', e);
      }
    }

    const captureId = Crypto.randomUUID();
    const capturedAt = new Date().toISOString();

    // 4. Read photo bytes for hashing
    const photoBase64 = await FileSystem.readAsStringAsync(photo.uri, {
      encoding: FileSystem.EncodingType.Base64,
    });
    const photoBytes = Uint8Array.from(atob(photoBase64), c => c.charCodeAt(0));

    // Set raw capture
    const raw: RawCapture = {
      id: captureId,
      photoUri: photo.uri,
      photoBytes,
      depthFrame,
      capturedAt,
      deviceModel,
    };
    setRawCapture(raw);

    // 5. Process capture
    await processCapture(raw, location);
  }, [cameraRef, isDepthReady, keyId]);

  const processCapture = async (raw: RawCapture, location?: CaptureLocation) => {
    // Compute SHA-256 hash
    const photoHash = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      raw.photoBytes.toString(),
      { encoding: Crypto.CryptoEncoding.BASE64 }
    );

    // Compress depth map with gzip
    const depthMapBytes = new Uint8Array(raw.depthFrame.depthMap.buffer);
    const compressedDepthMap = pako.gzip(depthMapBytes);

    // Build metadata for assertion
    const metadata: CaptureMetadata = {
      captured_at: raw.capturedAt,
      device_model: raw.deviceModel,
      photo_hash: photoHash,
      depth_map_dimensions: {
        width: raw.depthFrame.width,
        height: raw.depthFrame.height,
      },
      location,
      assertion: '', // Will be filled below
    };

    // Generate per-capture assertion
    const clientDataHash = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      JSON.stringify(metadata),
      { encoding: Crypto.CryptoEncoding.BASE64 }
    );

    const assertion = await AppIntegrity.generateAssertionAsync(keyId!, clientDataHash);
    metadata.assertion = assertion;

    // Create processed capture
    const processed: ProcessedCapture = {
      id: raw.id,
      photoUri: raw.photoUri,
      photoHash,
      compressedDepthMap,
      depthDimensions: {
        width: raw.depthFrame.width,
        height: raw.depthFrame.height,
      },
      metadata,
      assertion,
      status: 'ready',
      createdAt: raw.capturedAt,
    };

    setProcessedCapture(processed);
  };

  return {
    capture,
    setCameraRef,
    isCapturing,
    isProcessing,
    isReady: !!cameraRef && isDepthReady && !!keyId,
  };
}
```

### Workflows and Sequencing

#### Capture Flow Sequence

```
User                    CaptureScreen         LiDARModule           expo-camera           expo-location         AppIntegrity
  |                          |                     |                     |                     |                     |
  |  Press capture button    |                     |                     |                     |                     |
  |------------------------->|                     |                     |                     |                     |
  |                          |  captureDepthFrame()|                     |                     |                     |
  |                          |-------------------->|                     |                     |                     |
  |                          |                     |  ARFrame.sceneDepth |                     |                     |
  |                          |                     |<--------------------|                     |                     |
  |                          |  DepthFrame         |                     |                     |                     |
  |                          |<--------------------|                     |                     |                     |
  |                          |                     |                     |                     |                     |
  |                          |  takePictureAsync() |                     |                     |                     |
  |                          |-------------------->|-------------------->|                     |                     |
  |                          |                     |                     |  Photo URI          |                     |
  |                          |<-------------------|---------------------|                     |                     |
  |                          |                     |                     |                     |                     |
  |                          |  getCurrentLocation()|                    |                     |                     |
  |                          |-------------------->|-------------------->|-------------------->|                     |
  |                          |                     |                     |  GPS Coords         |                     |
  |                          |<-------------------|---------------------|---------------------|                     |
  |                          |                     |                     |                     |                     |
  |                          |  [LOCAL PROCESSING]  |                    |                     |                     |
  |                          |  - SHA-256 hash     |                     |                     |                     |
  |                          |  - gzip depth map   |                     |                     |                     |
  |                          |  - build metadata   |                     |                     |                     |
  |                          |                     |                     |                     |                     |
  |                          |  generateAssertionAsync(keyId, clientDataHash)                  |                     |
  |                          |-------------------->|-------------------->|-------------------->|-------------------->|
  |                          |                     |                     |                     |  Assertion (base64) |
  |                          |<-------------------|---------------------|---------------------|---------------------|
  |                          |                     |                     |                     |                     |
  |                          |  Navigate to Preview|                     |                     |                     |
  |<-------------------------|                     |                     |                     |                     |
```

#### ARSession Lifecycle

```
App Launch                  Capture Tab Active             Capture Tab Inactive           App Background
     |                            |                              |                              |
     |                            |  startDepthCapture()         |                              |
     |                            |------------------------->    |                              |
     |                            |  ARSession.run(config)       |                              |
     |                            |  config.frameSemantics =     |                              |
     |                            |    .sceneDepth               |                              |
     |                            |                              |                              |
     |                            |  <depth frames at 30fps>     |                              |
     |                            |                              |                              |
     |                            |                              |  stopDepthCapture()          |
     |                            |                              |------------------------->    |
     |                            |                              |  ARSession.pause()           |
     |                            |                              |                              |
     |                            |                              |                              |  AppState.background
     |                            |                              |                              |----------------->
     |                            |                              |                              |  stopDepthCapture()
     |                            |                              |                              |  (auto)
```

## Non-Functional Requirements

### Performance

| Metric | Target | Measurement |
|--------|--------|-------------|
| Depth overlay frame rate | >= 30 FPS | Time between onDepthFrame events |
| Capture latency (button to preview) | < 2 seconds | Timestamp delta |
| Photo + depth sync | < 100ms difference | Timestamp comparison |
| SHA-256 hash computation | < 500ms | For ~3MB JPEG |
| Depth map compression | < 500ms | 256x192 float32 -> gzip |
| Total local processing | < 2 seconds | Hash + compress + assertion |
| Memory usage during capture | < 200MB | ARKit + camera + overlay |

**Performance Strategies:**

1. **Depth overlay optimization:** Use React Native Skia or GL view for 30fps overlay rendering
2. **Background processing:** Hash and compress on background thread after UI update
3. **Incremental depth frames:** Only process every 2nd ARKit frame for overlay (30fps from 60fps)
4. **Memory management:** Release photo bytes after hashing, depth frame after compression

### Security

**Capture Integrity:**

| Aspect | Implementation | Rationale |
|--------|----------------|-----------|
| Per-capture assertion | `generateAssertionAsync(keyId, clientDataHash)` | Binds capture to attested device |
| Photo hash binding | Hash included in assertion clientDataHash | Proves photo wasn't modified |
| Timestamp binding | Capture timestamp in assertion payload | Proves when photo was taken |
| Local storage security | Temporary files in app sandbox | No encryption needed (not offline storage) |

**Threat Mitigations (Capture Phase):**

| Threat | Mitigation |
|--------|------------|
| Capture replay | Assertion includes fresh clientDataHash |
| Photo substitution | SHA-256 hash bound to assertion |
| Depth map fabrication | Depth captured from ARKit (hardware) |
| Timestamp manipulation | Server validates against receipt time (Epic 4) |

### Reliability/Availability

| Scenario | Behavior | Recovery |
|----------|----------|----------|
| LiDAR session interrupted | Show error, retry start | User can retry from capture screen |
| Camera permission denied | Block capture, show permission prompt | User grants permission |
| Location permission denied | Proceed without location | Evidence notes "location unavailable" |
| Assertion generation fails | Show error, retry | User can retry capture |
| Low storage | Warn user, block capture | User frees space |

**Error Handling:**

```typescript
// Error types for capture flow
type CaptureError =
  | { type: 'LIDAR_NOT_AVAILABLE'; message: string }
  | { type: 'CAMERA_PERMISSION_DENIED'; message: string }
  | { type: 'DEPTH_CAPTURE_FAILED'; message: string }
  | { type: 'PHOTO_CAPTURE_FAILED'; message: string }
  | { type: 'ASSERTION_FAILED'; message: string }
  | { type: 'PROCESSING_FAILED'; message: string };
```

### Observability

**Logging Events:**

| Event | Data | Level |
|-------|------|-------|
| capture_started | captureId, timestamp | INFO |
| depth_frame_captured | width, height, timestamp | DEBUG |
| photo_captured | width, height, fileSize | INFO |
| location_captured | accuracy, hasAltitude | INFO |
| hash_computed | photoHash, durationMs | DEBUG |
| depth_compressed | originalSize, compressedSize | DEBUG |
| assertion_generated | durationMs | INFO |
| capture_completed | captureId, totalDurationMs | INFO |
| capture_failed | captureId, errorType, message | ERROR |

**Metrics:**

- `capture_duration_ms` - Histogram of total capture time
- `depth_overlay_fps` - Gauge of current overlay frame rate
- `processing_duration_ms` - Histogram of local processing time
- `capture_success_rate` - Counter of successful vs failed captures

## Dependencies and Integrations

### External Dependencies

| Dependency | Version | Purpose | Size Impact |
|------------|---------|---------|-------------|
| expo-camera | ~17.0.0 | Photo capture | ~2MB |
| expo-location | ~19.0.0 | GPS coordinates | ~1MB |
| expo-crypto | ~15.0.0 | SHA-256 hashing | ~500KB |
| expo-file-system | ~19.0.0 | File operations | ~1MB |
| @expo/app-integrity | ~1.0.0 | Per-capture assertions | ~500KB |
| pako | ^2.1.0 | Gzip compression | ~50KB |
| zustand | ^5.0.0 | State management | ~10KB |
| react-native-skia (optional) | ^1.0.0 | Depth overlay rendering | ~5MB |

### Internal Dependencies (From Epic 2)

| Dependency | Location | Usage |
|------------|----------|-------|
| deviceStore | `store/deviceStore.ts` | Get keyId, deviceModel |
| useDeviceAttestation | `hooks/useDeviceAttestation.ts` | Verify device is attested |
| DeviceCapabilities | `types/device.ts` | Check LiDAR availability |

### iOS Framework Dependencies

| Framework | Purpose |
|-----------|---------|
| ARKit | LiDAR depth capture |
| AVFoundation | Camera access |
| CoreLocation | GPS coordinates |
| Accelerate | Depth map processing (optional) |

### Development Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| expo-dev-client | ~6.0.0 | Custom native modules |
| jest | ^29.0.0 | Unit testing |
| @testing-library/react-native | ^12.0.0 | Component testing |

## Acceptance Criteria (Authoritative)

### AC-3.1: LiDAR Module Availability Check

**Given** a user launches the app on an iPhone Pro device
**When** the capture screen initializes
**Then** `isLiDARAvailable()` returns `true`

**Given** a user launches the app on a non-Pro iPhone (no LiDAR)
**When** the capture screen initializes
**Then** `isLiDARAvailable()` returns `false`
**And** capture is blocked with clear message

### AC-3.2: Depth Capture Session Management

**Given** the capture tab becomes active
**When** the screen mounts
**Then** `startDepthCapture()` is called
**And** ARSession starts with `.sceneDepth` frame semantics

**Given** the capture tab becomes inactive
**When** the user navigates away
**Then** `stopDepthCapture()` is called
**And** ARSession is paused

### AC-3.3: Real-time Depth Overlay

**Given** depth capture is active
**When** the camera preview is displayed
**Then** a depth heatmap overlay is shown at >= 30 FPS
**And** near objects appear in warm colors (red/orange)
**And** far objects appear in cool colors (blue/purple)
**And** depth range is 0-5 meters

**Given** the depth toggle is tapped
**When** overlay is currently visible
**Then** overlay is hidden
**And** camera preview shows without overlay

### AC-3.4: Photo Capture with Depth

**Given** depth capture is active and camera is ready
**When** user taps the capture button
**Then** photo is captured at full resolution (up to 4032x3024)
**And** depth frame is captured within 100ms of photo
**And** haptic feedback confirms capture

### AC-3.5: GPS Location Capture

**Given** location permission is granted
**When** a capture is taken
**Then** GPS coordinates are recorded with 6 decimal places
**And** accuracy estimate is included
**And** altitude is included if available

**Given** location permission is denied
**When** a capture is taken
**Then** capture proceeds without location
**And** metadata notes `location: undefined`

### AC-3.6: Per-Capture Assertion

**Given** a photo + depth capture is complete
**When** local processing runs
**Then** `generateAssertionAsync(keyId, clientDataHash)` is called
**And** clientDataHash includes: timestamp, photo_hash, device_model
**And** assertion is base64 encoded string

### AC-3.7: Photo Hash Computation

**Given** a photo has been captured
**When** local processing runs
**Then** SHA-256 hash is computed from JPEG bytes
**And** hash is base64 encoded
**And** computation completes in < 500ms

### AC-3.8: Depth Map Compression

**Given** a depth frame has been captured
**When** local processing runs
**Then** Float32Array is gzip compressed
**And** original size ~192KB (256*192*4 bytes)
**And** compressed size ~100-150KB (typical)

### AC-3.9: Capture Metadata Construction

**Given** photo, depth, location, and assertion are ready
**When** metadata is constructed
**Then** JSON structure matches:
```json
{
  "captured_at": "ISO timestamp",
  "device_model": "string",
  "photo_hash": "base64 SHA-256",
  "depth_map_dimensions": { "width": 256, "height": 192 },
  "location": { "lat": number, "lng": number } | undefined,
  "assertion": "base64 string"
}
```

### AC-3.10: Capture Preview Screen

**Given** local processing is complete
**When** preview screen displays
**Then** full-resolution photo is shown
**And** depth overlay toggle is available
**And** capture metadata summary is displayed
**And** "Upload", "Discard", "Capture Another" buttons are present

### AC-3.11: Discard Capture

**Given** preview screen is displayed
**When** user taps "Discard"
**Then** capture files are deleted from temporary storage
**And** user returns to capture screen
**And** capture state is cleared

### AC-3.12: Camera Permission Handling

**Given** camera permission has not been requested
**When** capture screen loads
**Then** permission is requested
**And** capture is blocked until granted

## Traceability Mapping

| AC | FR | Spec Section | Component | Test Approach |
|----|-----|--------------|-----------|---------------|
| AC-3.1 | FR1, FR6 | LiDAR Module | `isLiDARAvailable()` | Unit test with mock ARKit |
| AC-3.2 | FR6 | ARSession Lifecycle | `DepthCaptureSession` | Integration test on device |
| AC-3.3 | FR6 | Depth Overlay | `DepthOverlay.tsx` | Visual regression test |
| AC-3.4 | FR7, FR8 | Capture Flow | `useCapture.ts` | Integration test on device |
| AC-3.5 | FR9 | Location Capture | `useLocation.ts` | Unit test with mock location |
| AC-3.6 | FR10 | Per-Capture Assertion | `useCaptureAssertion.ts` | Integration test on device |
| AC-3.7 | FR11 | Local Processing | `useCaptureProcessor.ts` | Unit test with fixture |
| AC-3.8 | FR12 | Local Processing | `useCaptureProcessor.ts` | Unit test with fixture |
| AC-3.9 | FR13 | Local Processing | CaptureMetadata type | Unit test schema validation |
| AC-3.10 | FR6 | Preview Screen | `preview.tsx` | Component test |
| AC-3.11 | - | Preview Screen | `preview.tsx` | Component test |
| AC-3.12 | - | Permission Handling | `capture.tsx` | Integration test |

## Risks, Assumptions, Open Questions

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **R1:** ARKit depth capture timing varies | Medium | Medium | Buffer recent frames, use closest to photo timestamp |
| **R2:** Depth overlay impacts camera performance | Medium | Medium | Optimize rendering, use Skia/GL, reduce overlay resolution |
| **R3:** Large depth map compression time | Low | Medium | Process on background thread, show progress |
| **R4:** @expo/app-integrity assertion failures | Low | High | Graceful degradation, mark capture as "unasserted" |

### Assumptions

| Assumption | Validation |
|------------|------------|
| **A1:** All iPhone Pro models have consistent LiDAR resolution (256x192) | Verify on iPhone 12-17 Pro |
| **A2:** ARKit depth capture adds < 100ms latency | Benchmark on device |
| **A3:** pako gzip compression is fast enough for real-time | Benchmark with typical depth map |
| **A4:** expo-camera and ARKit can run simultaneously | Test integration |

### Open Questions

| Question | Owner | Target Resolution |
|----------|-------|-------------------|
| **Q1:** Should depth overlay use Skia, GL, or Canvas? | Dev | Story 3-1 implementation |
| **Q2:** What colormap provides best visibility? (viridis, plasma, thermal) | UX | Story 3-1 implementation |
| **Q3:** Should we cache depth frames for smoother overlay? | Dev | Story 3-1 implementation |
| **Q4:** How to handle ARKit session interruption gracefully? | Dev | Story 3-2 implementation |

## Test Strategy Summary

### Unit Tests

| Component | Coverage Target | Framework |
|-----------|-----------------|-----------|
| useLiDAR hook | 80% | Jest + RTL |
| useCapture hook | 80% | Jest + RTL |
| useLocation hook | 80% | Jest + RTL |
| useCaptureProcessor hook | 90% | Jest + RTL |
| captureStore | 90% | Jest |
| Type validators | 100% | Jest |

### Integration Tests

| Scenario | Framework | Device Required |
|----------|-----------|-----------------|
| LiDAR module lifecycle | Jest + Native | iPhone Pro |
| Photo + depth sync | Jest + Native | iPhone Pro |
| Assertion generation | Jest + Native | iPhone Pro |
| Location capture | Jest + Native | iPhone Pro |

### E2E Tests (Maestro)

| Flow | Steps |
|------|-------|
| Happy path capture | Open app -> Capture tab -> Tap capture -> View preview -> Verify elements |
| Depth overlay toggle | Capture tab -> Toggle overlay -> Verify visibility changes |
| Location denied | Deny permission -> Capture -> Verify proceeds without location |
| Discard capture | Capture -> Preview -> Discard -> Verify returned to capture screen |

### Device Testing Matrix

| Model | iOS Version | Status |
|-------|-------------|--------|
| iPhone 17 Pro | iOS 18.x | Primary test device |
| iPhone 15 Pro | iOS 17.x | Secondary test device |
| iPhone 12 Pro | iOS 17.x | Min supported device |
| iPhone 15 (non-Pro) | iOS 17.x | LiDAR not available test |

### Test Data Fixtures

- Sample depth frames (256x192 Float32Array)
- Sample photo JPEG (various resolutions)
- Mock location coordinates
- Expected compressed depth sizes
- Expected hash values

---

## Story Mapping

| Story ID | Title | ACs Covered |
|----------|-------|-------------|
| 3-1 | Camera view with LiDAR depth overlay | AC-3.1, AC-3.2, AC-3.3 |
| 3-2 | Photo capture with depth map | AC-3.4 |
| 3-3 | GPS metadata collection | AC-3.5 |
| 3-4 | Capture attestation signature | AC-3.6 |
| 3-5 | Local processing pipeline | AC-3.7, AC-3.8, AC-3.9 |
| 3-6 | Capture preview screen | AC-3.10, AC-3.11, AC-3.12 |

---

_Generated by BMAD Epic Tech Context Workflow_
_Date: 2025-11-23_
_Epic: 3 - Photo Capture with LiDAR Depth_
