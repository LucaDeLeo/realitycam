# Native Swift Migration Guide

This document outlines the migration from the Expo/React Native mobile app to the native Swift implementation (Epic 6).

## Overview

The native Swift implementation provides several security and performance improvements over the React Native version:

| Aspect | React Native | Native Swift | Improvement |
|--------|-------------|--------------|-------------|
| **JS Bridge** | Photo bytes cross JS<->Native | All processing in native memory | Eliminates data exposure |
| **Cryptography** | SHA-256 stream cipher workaround | Real AES-GCM via CryptoKit | Authenticated encryption |
| **Camera/Depth Sync** | Two modules + JS timing | Single ARFrame (same instant) | Perfect synchronization |
| **Background Uploads** | Foreground only | URLSession background | Survives app termination |
| **Dependencies** | npm + native modules | Zero external packages | Minimal attack surface |

## Architecture

### Project Structure

```
ios/Rial/
├── App/                      # Entry points
│   ├── RialApp.swift        # @main SwiftUI entry
│   ├── AppDelegate.swift    # Background task handling
│   └── ContentView.swift    # Root view
├── Core/                     # Security-critical services
│   ├── Attestation/
│   │   ├── DeviceAttestationService.swift
│   │   └── CaptureAssertionService.swift
│   ├── Capture/
│   │   ├── ARCaptureSession.swift
│   │   ├── FrameProcessor.swift
│   │   └── DepthVisualizer.swift
│   ├── Crypto/
│   │   └── CryptoService.swift
│   ├── Networking/
│   │   ├── APIClient.swift
│   │   ├── CertificatePinning.swift
│   │   ├── DeviceSignature.swift
│   │   ├── NetworkMonitor.swift
│   │   ├── RetryManager.swift
│   │   └── UploadService.swift
│   └── Storage/
│       ├── CaptureEncryption.swift
│       ├── CaptureStore.swift
│       ├── KeychainService.swift
│       └── OfflineQueue.swift
├── Features/                 # SwiftUI views
│   ├── Capture/
│   │   ├── ARViewContainer.swift
│   │   ├── CaptureButton.swift
│   │   ├── CaptureView.swift
│   │   ├── CaptureViewModel.swift
│   │   └── DepthOverlayView.swift
│   ├── History/
│   │   ├── CaptureThumbnailView.swift
│   │   ├── EmptyHistoryView.swift
│   │   ├── HistoryView.swift
│   │   └── HistoryViewModel.swift
│   └── Result/
│       ├── ConfidenceBadge.swift
│       ├── EvidenceSummaryView.swift
│       ├── ResultDetailView.swift
│       └── ZoomableImageView.swift
├── Models/
│   └── CaptureData.swift
└── Shaders/
    └── DepthVisualization.metal
```

## Key Frameworks

| Framework | Purpose |
|-----------|---------|
| **DeviceCheck** | DCAppAttest hardware attestation |
| **CryptoKit** | SHA-256, AES-GCM, key management |
| **ARKit** | RGB + LiDAR depth capture |
| **Metal** | GPU depth visualization |
| **Security** | Keychain services |
| **URLSession** | Background uploads, certificate pinning |
| **CoreData** | Local persistence |
| **CoreLocation** | GPS coordinates |

## Migration Steps

### 1. Device Registration

The native app uses the same backend endpoints but with direct DCAppAttest integration:

```swift
// Native approach
let service = DeviceAttestationService(keychain: keychain)
let keyId = try await service.generateKey()
let attestation = try await service.generateAttestation(challenge: challenge)
```

### 2. Capture Flow

ARKit provides synchronized RGB + depth in a single ARFrame:

```swift
// Native approach - perfect sync
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let photo = frame.capturedImage
    let depth = frame.sceneDepth?.depthMap
    // Same instant, no timing coordination needed
}
```

### 3. Storage & Upload

Captures are encrypted at rest with AES-GCM:

```swift
// Native approach - real authenticated encryption
let encrypted = try CaptureEncryption.encrypt(captureData)
try captureStore.save(encrypted)

// Background upload survives app termination
let task = session.downloadTask(with: uploadRequest)
task.resume()
```

## API Compatibility

The native app uses the same backend API endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/devices/challenge` | GET | Request attestation challenge |
| `/api/v1/devices/register` | POST | Register device with attestation |
| `/api/v1/captures` | POST | Upload capture (multipart) |
| `/api/v1/captures/{id}` | GET | Get capture status |

### Request Headers

```
X-Device-Id: {device_uuid}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {ed25519_signature}
```

## Testing

### Unit Tests

All core services have comprehensive unit tests:

- `CryptoServiceTests` - SHA-256 hashing
- `KeychainServiceTests` - Keychain operations
- `DeviceAttestationServiceTests` - DCAppAttest
- `ARCaptureSessionTests` - Capture session
- `FrameProcessorTests` - Frame processing
- `DepthVisualizerTests` - Metal shaders
- `CaptureAssertionServiceTests` - Per-capture signing
- `CaptureStoreTests` - CoreData persistence
- `CaptureEncryptionTests` - AES-GCM encryption
- `RetryManagerTests` - Upload retry logic
- `UploadServiceTests` - Background uploads

### UI Tests

Feature parity tests in `RialUITests/FeatureParityTests.swift`:

- App launch validation
- Navigation elements
- Accessibility labels
- Performance benchmarks

### Running Tests

```bash
# Unit tests
xcodebuild test -project Rial.xcodeproj -scheme Rial \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:RialTests

# UI tests (simulator)
xcodebuild test -project Rial.xcodeproj -scheme Rial \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:RialUITests
```

## Deployment Requirements

- **iOS Version**: 15.0+
- **Swift Version**: 5.9+
- **Device**: iPhone Pro models (12 Pro through current) with LiDAR
- **Capabilities**: Camera, Location, App Attest

## Feature Parity Checklist

- [x] Device registration with DCAppAttest
- [x] Secure Enclave key generation
- [x] SHA-256 photo hashing
- [x] AES-GCM offline encryption
- [x] ARKit RGB + depth capture
- [x] LiDAR depth visualization
- [x] Per-capture assertion signing
- [x] CoreData capture queue
- [x] Background URLSession uploads
- [x] Certificate pinning with retry
- [x] SwiftUI capture interface
- [x] Capture history grid
- [x] Result detail with zoom
- [x] Share functionality
