# Epic 6: Native Swift Implementation - Technical Specification

**Author:** BMAD Epic Tech Context Workflow
**Date:** 2025-11-25
**Epic ID:** 6
**Status:** Tech Spec Complete

---

## 1. Epic Overview

### 1.1 Goal and User Value

Epic 6 re-implements the iOS mobile app in pure native Swift/SwiftUI, eliminating React Native/Expo and achieving maximum security posture through direct OS framework access. This epic provides captures processed entirely within compiled native code with no JavaScript bridge crossings for sensitive data.

**Key User Benefits:**
- Direct Secure Enclave access for cryptographic operations
- Unified RGB+depth capture with perfect synchronization (same ARFrame instant)
- Background uploads that continue even after app termination
- Smaller attack surface with single compiled binary
- Real AES-GCM encryption via CryptoKit (not SHA-256 stream cipher workaround)

### 1.2 Functional Requirements Covered

This epic provides native re-implementation of all mobile-side functional requirements:

| FR Category | FRs Covered | Description |
|-------------|-------------|-------------|
| Device & Attestation | FR1-FR3, FR41-FR43 | Device detection, key generation, attestation |
| Capture Flow | FR6-FR10 | Camera view, photo capture, depth map, GPS, attestation signature |
| Local Processing | FR11-FR13 | SHA-256 hash, depth compression, capture request construction |
| Upload & Sync | FR14-FR19 | Multipart upload, TLS 1.3, retry logic, offline storage, auto-upload |
| Privacy Controls | FR44-FR46 | Location coarsening, location opt-out, depth map protection |

### 1.3 Out-of-Scope for Epic 6

The following items are explicitly **not** part of Epic 6:

| Item | Reason |
|------|--------|
| **C2PA manifest generation/signing** | Backend responsibility (Epic 5) |
| **Verification web UI** | Web app responsibility (Epic 5) |
| **Backend evidence processing** | Backend-only changes |
| **Android/cross-platform** | Post-MVP - iOS-first approach |
| **Video capture** | Post-MVP - photo-only for MVP |
| **User accounts/authentication** | Out of scope - device-based identity only |

### 1.4 Security Improvements Over React Native

| Aspect | React Native Approach | Native Swift Approach | Security Improvement |
|--------|----------------------|----------------------|---------------------|
| **JS Bridge** | Photo bytes cross JS<->Native boundary | All processing in native memory | Eliminates data exposure at bridge |
| **Cryptography** | SHA-256 stream cipher workaround | Real AES-GCM via CryptoKit | Authenticated encryption |
| **Camera/Depth Sync** | Two modules + JS coordination timing | Single ARFrame (same instant) | Perfect synchronization |
| **Background Uploads** | Foreground only, dies if app killed | URLSession continues after termination | Reliable delivery |
| **Dependencies** | npm + native modules (supply chain risk) | Zero external packages | Minimal attack surface |
| **Security Audit** | Multiple languages, frameworks | Single language, known APIs | Easier verification |

---

## 2. Architecture Context

### 2.1 Native Swift Project Structure

```
ios/
├── Rial/
│   ├── App/
│   │   ├── RialApp.swift                    # @main entry point
│   │   └── AppDelegate.swift                # Background task handling
│   ├── Core/                                # Security-critical services
│   │   ├── Attestation/
│   │   │   ├── DeviceAttestation.swift      # DCAppAttest direct
│   │   │   └── CaptureAssertion.swift       # Per-capture signing
│   │   ├── Capture/
│   │   │   ├── ARCaptureSession.swift       # Unified RGB+Depth
│   │   │   └── DepthProcessor.swift         # Depth analysis prep
│   │   ├── Crypto/
│   │   │   ├── SecureKeychain.swift         # Keychain wrapper
│   │   │   ├── CaptureEncryption.swift      # AES-GCM offline
│   │   │   └── HashingService.swift         # CryptoKit SHA-256
│   │   ├── Networking/
│   │   │   ├── APIClient.swift              # URLSession + signing
│   │   │   ├── DeviceSignature.swift        # Request auth
│   │   │   └── UploadService.swift          # Background uploads
│   │   └── Storage/
│   │       ├── CaptureStore.swift           # Core Data persistence
│   │       └── OfflineQueue.swift           # Upload queue
│   ├── Features/                            # SwiftUI views + view models
│   │   ├── Capture/
│   │   │   ├── CaptureView.swift
│   │   │   ├── CaptureViewModel.swift
│   │   │   └── DepthOverlayView.swift       # Metal shader overlay
│   │   ├── Preview/
│   │   │   ├── PreviewView.swift
│   │   │   └── PreviewViewModel.swift
│   │   ├── History/
│   │   │   ├── HistoryView.swift
│   │   │   └── HistoryViewModel.swift
│   │   └── Result/
│   │       └── ResultView.swift
│   ├── Models/
│   │   ├── Capture.swift
│   │   ├── Device.swift
│   │   └── Evidence.swift
│   ├── Shaders/
│   │   └── DepthColormap.metal              # GPU depth visualization
│   └── Resources/
│       └── Assets.xcassets
├── RialTests/                               # XCTest unit tests
├── RialUITests/                             # XCUITest UI tests
└── Rial.xcodeproj
```

### 2.2 Key Frameworks

| Framework | Purpose | Usage |
|-----------|---------|-------|
| **DeviceCheck** | DCAppAttest hardware attestation | Direct Secure Enclave access for device/capture attestation |
| **CryptoKit** | SHA-256, AES-GCM, key management | Hardware-accelerated cryptographic operations |
| **ARKit** | RGB + LiDAR depth capture | Unified ARFrame for perfect synchronization |
| **Metal** | Depth visualization shaders | 60fps GPU-native real-time rendering |
| **Security** | Keychain services | Hardware-backed key storage |
| **Foundation/URLSession** | Networking | Background uploads, certificate pinning |
| **CoreData** | Local persistence | Offline capture queue management |
| **CoreLocation** | GPS coordinates | Location metadata capture |

### 2.3 Zero External Dependencies Philosophy

```swift
// Package.swift - intentionally minimal
dependencies: []  // No external packages for security-critical code
```

**Rationale:**
- Smaller attack surface (no supply chain risk from third-party packages)
- Direct OS API access (no abstraction layers to compromise)
- Easier security auditing (single language, known frameworks)
- No dependency version conflicts or breaking updates
- All security-critical functionality uses Apple's vetted frameworks

---

## 3. Story Dependency Graph

### 3.1 Visual Dependency Map

```
Phase 1: Security Foundation
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  [6.1] Initialize Project                               │
│         │                                               │
│         ├──────────────┬──────────────┐                │
│         │              │              │                │
│         ▼              ▼              ▼                │
│      [6.3]          [6.4]          [6.9]               │
│    CryptoKit      Keychain       CoreData              │
│         │              │              │                │
│         └──────┬───────┘              │                │
│                │                      │                │
│                ▼                      │                │
│             [6.2]                     │                │
│          DCAppAttest  ◄───────────────┘                │
│                                                         │
└─────────────────────────────────────────────────────────┘

Phase 2: Capture Core
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  [6.5] ARKit Capture                                    │
│         │                                               │
│         ├──────────────┬──────────────┐                │
│         │              │              │                │
│         ▼              ▼              │                │
│      [6.6]          [6.7]             │                │
│   Frame Process    Metal Depth        │                │
│         │              │              │                │
│         └──────┬───────┘              │                │
│                │                      │                │
│                ▼                      │                │
│             [6.8] ◄───────────────────┘                │
│       Per-Capture Assertion                            │
│            (requires 6.2, 6.3)                         │
│                                                         │
└─────────────────────────────────────────────────────────┘

Phase 3: Storage & Upload
┌─────────────────────────────────────────────────────────┐
│                                                         │
│      [6.9] CoreData                                     │
│         │                                               │
│         │                                               │
│         ▼                                               │
│      [6.10]                                             │
│   iOS Data Protection                                   │
│    (requires 6.3, 6.4)                                 │
│         │                                               │
│         ▼                                               │
│      [6.11]                                             │
│   Background Uploads                                    │
│         │                                               │
│         ▼                                               │
│      [6.12]                                             │
│   Cert Pinning/Retry                                   │
│                                                         │
└─────────────────────────────────────────────────────────┘

Phase 4: User Experience
┌─────────────────────────────────────────────────────────┐
│                                                         │
│      [6.13] Capture Screen                              │
│    (requires 6.5, 6.6, 6.7)                            │
│         │                                               │
│         ▼                                               │
│      [6.14] History View                                │
│    (requires 6.9, 6.11)                                │
│         │                                               │
│         ▼                                               │
│      [6.15] Result Detail                               │
│         │                                               │
│         ▼                                               │
│      [6.16] Feature Parity Validation                   │
│    (requires ALL stories 6.1-6.15)                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Critical Path

The critical path through Epic 6 is:

```
6.1 → 6.4 → 6.2 → 6.5 → 6.6 → 6.8 → 6.9 → 6.10 → 6.11 → 6.12 → 6.13 → 6.14 → 6.15 → 6.16
```

**Total minimum sequential stories:** 14 (some parallelization possible)

### 3.3 Parallelization Opportunities

| Parallel Group | Stories | Notes |
|----------------|---------|-------|
| **Group A** | 6.3, 6.4, 6.9 | Can start after 6.1, independent of each other |
| **Group B** | 6.6, 6.7 | Both depend on 6.5, independent of each other |
| **Group C** | Phase 3 vs UI setup | Storage/upload can proceed while capture UI begins |

---

## 4. Technical Decisions

### 4.1 Why Native Swift vs React Native

| Factor | Decision Rationale |
|--------|-------------------|
| **Security** | Photo bytes, hashes, and keys never cross JS bridge boundary |
| **Synchronization** | ARKit provides RGB + depth in single ARFrame (same instant) |
| **Cryptography** | CryptoKit provides real AES-GCM, not SHA-256 workaround |
| **Background** | URLSession background uploads survive app termination |
| **Attack Surface** | Single compiled binary, no Hermes JS engine, no Metro bundler |
| **Auditability** | Single language (Swift), known Apple frameworks |

### 4.2 Why No Third-Party Dependencies

1. **Supply Chain Security:** No npm packages that could be compromised
2. **Direct API Access:** Apple's frameworks are the most secure path to hardware features
3. **Audit Simplicity:** Security reviewers only need Swift + Apple framework knowledge
4. **Stability:** No dependency updates breaking security-critical code
5. **Performance:** Native implementations are optimized for Apple hardware

### 4.3 Swift Version Requirement

**Swift 5.9+ required** for this implementation.

| Requirement | Swift 5.9 Feature |
|-------------|-------------------|
| Concurrency | Stable `async/await`, actors, structured concurrency |
| Macros | Observation framework macros for SwiftUI |
| Type Safety | Enhanced type inference and generics |
| Performance | Improved compiler optimizations |

### 4.4 Why iOS 15.0 Minimum

| Requirement | iOS 15.0 Feature |
|-------------|------------------|
| Swift Concurrency | `async/await` support (simplifies async code) |
| ARKit Improvements | Enhanced sceneDepth APIs for LiDAR |
| CryptoKit Updates | Improved Secure Enclave key operations |
| Device Coverage | All iPhone Pro models (12 Pro through current) support iOS 15+ |

**Device Compatibility Matrix:**

| Model | Released | LiDAR | iOS 15+ Support |
|-------|----------|-------|-----------------|
| iPhone 12 Pro / Pro Max | 2020 | Yes | Yes |
| iPhone 13 Pro / Pro Max | 2021 | Yes | Yes |
| iPhone 14 Pro / Pro Max | 2022 | Yes | Yes |
| iPhone 15 Pro / Pro Max | 2023 | Yes | Yes |
| iPhone 16 Pro / Pro Max | 2024 | Yes | Yes |
| iPhone 17 Pro / Pro Max | 2025 | Yes | Yes |

---

## 5. API Integration Points

### 5.1 Backend Endpoints

The native app will interact with these existing backend endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/devices/challenge` | GET | Request attestation challenge |
| `/api/v1/devices/register` | POST | Register device with attestation |
| `/api/v1/captures` | POST | Upload capture (multipart) |
| `/api/v1/captures/{id}` | GET | Get capture status and evidence |

### 5.2 Request/Response Formats

#### Device Challenge Request

```http
GET /api/v1/devices/challenge
```

Response:
```json
{
  "data": {
    "challenge": "base64-encoded-32-bytes",
    "expires_at": "2025-11-22T10:35:00Z"
  }
}
```

#### Device Registration Request

```http
POST /api/v1/devices/register
Content-Type: application/json

{
  "platform": "ios",
  "model": "iPhone 15 Pro",
  "has_lidar": true,
  "attestation": {
    "key_id": "base64...",
    "attestation_object": "base64...",
    "challenge": "base64..."
  }
}
```

Response (Success - 201):
```json
{
  "data": {
    "device_id": "uuid",
    "attestation_level": "secure_enclave",
    "has_lidar": true
  }
}
```

**Error Responses:**

| HTTP Code | Error | Description | Recovery Strategy |
|-----------|-------|-------------|-------------------|
| 400 | `invalid_attestation` | Attestation object malformed or invalid | Re-generate attestation key and retry |
| 409 | `device_already_registered` | Device ID already exists | Load existing device state from keychain |
| 422 | `unsupported_platform` | Platform not iOS | N/A (code bug) |
| 500 | `attestation_verification_failed` | Server-side verification failed | Retry with backoff |

Error JSON structure:
```json
{
  "error": {
    "code": "invalid_attestation",
    "message": "Attestation object verification failed",
    "details": { "reason": "signature_invalid" }
  }
}
```

#### Capture Upload Request

```http
POST /api/v1/captures
Content-Type: multipart/form-data
X-Device-Id: {device_uuid}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {ed25519_signature}

Parts:
- photo: binary (JPEG ~3MB)
- depth_map: binary (gzipped float32 ~1MB)
- metadata: JSON
```

Metadata JSON:
```json
{
  "captured_at": "2025-11-22T10:30:00.123Z",
  "device_model": "iPhone 15 Pro",
  "photo_hash": "sha256-hex-string",
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "altitude": 10.5,
    "accuracy": 5.0
  },
  "depth_map_dimensions": {
    "width": 256,
    "height": 192
  },
  "assertion": "base64-assertion-data"
}
```

Response (Success - 201):
```json
{
  "data": {
    "capture_id": "uuid",
    "status": "processing",
    "verification_url": "https://rial.app/verify/{uuid}"
  }
}
```

**Error Responses:**

| HTTP Code | Error | Description | Recovery Strategy |
|-----------|-------|-------------|-------------------|
| 401 | `signature_invalid` | Device signature verification failed | Re-sign request with current timestamp |
| 401 | `device_not_registered` | Device ID not found | Trigger device re-registration flow |
| 401 | `timestamp_expired` | Request timestamp outside 5-minute window | Sync device clock, re-sign with fresh timestamp |
| 413 | `payload_too_large` | Upload exceeds 20MB limit | Compress images more aggressively |
| 422 | `invalid_metadata` | Required metadata fields missing/invalid | Validate metadata before upload |
| 422 | `invalid_depth_format` | Depth map format incorrect | Check depth compression pipeline |
| 422 | `invalid_assertion` | Per-capture assertion invalid | Re-capture with fresh assertion |
| 429 | `rate_limited` | Too many requests | Exponential backoff |
| 500 | `processing_failed` | Server-side processing error | Retry with backoff |

Error JSON structure:
```json
{
  "error": {
    "code": "signature_invalid",
    "message": "Device signature verification failed",
    "details": { "expected_device": "uuid", "signature_algorithm": "ed25519" }
  }
}
```

### 5.3 Authentication Headers

Every authenticated request includes:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Device-Id` | UUID | Identifies registered device |
| `X-Device-Timestamp` | Unix milliseconds | Request freshness (5-minute window) |
| `X-Device-Signature` | Base64 Ed25519 | Signature over `timestamp|sha256(body)` |

Signature computation:
```swift
let message = "\(timestamp)|\(sha256(requestBody))"
let signature = sign(message, deviceKey)  // Using Secure Enclave key
```

---

## 6. Data Models

### 6.1 CoreData Entities

#### CaptureEntity

```swift
@objc(CaptureEntity)
public class CaptureEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var jpeg: Data                    // Photo JPEG data
    @NSManaged public var depth: Data                   // Gzipped Float32 depth map
    @NSManaged public var metadata: Data                // JSON-encoded CaptureMetadata
    @NSManaged public var assertion: Data?              // DCAppAttest assertion
    @NSManaged public var status: String                // pending|uploading|uploaded|failed
    @NSManaged public var createdAt: Date
    @NSManaged public var attemptCount: Int16
    @NSManaged public var lastAttemptAt: Date?
    @NSManaged public var serverCaptureId: UUID?        // Set after successful upload
    @NSManaged public var verificationUrl: String?      // Set after successful upload
    @NSManaged public var confidenceLevel: String?      // HIGH|MEDIUM|LOW|SUSPICIOUS
    @NSManaged public var thumbnail: Data?              // Cached thumbnail
}
```

### 6.2 Swift Structs

#### CaptureData

```swift
struct CaptureData: Codable {
    let id: UUID
    let jpeg: Data
    let depth: Data                    // Gzipped Float32 array
    let metadata: CaptureMetadata
    let assertion: Data?
    let timestamp: Date
}
```

#### CaptureMetadata

```swift
struct CaptureMetadata: Codable {
    let capturedAt: Date
    let deviceModel: String
    let photoHash: String              // SHA-256 hex
    let location: LocationData?
    let depthMapDimensions: DepthDimensions
}

struct LocationData: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double
}

struct DepthDimensions: Codable {
    let width: Int
    let height: Int
}
```

#### DepthFrame

```swift
struct DepthFrame {
    let depthMap: [Float]              // Width x Height float values (meters)
    let width: Int
    let height: Int
    let timestamp: TimeInterval
    let confidenceMap: [UInt8]?        // Per-pixel confidence
    let intrinsics: simd_float3x3
    let transform: simd_float4x4
}
```

#### DeviceState

```swift
struct DeviceState: Codable {
    let deviceId: UUID
    let attestationKeyId: String
    let attestationLevel: AttestationLevel
    let hasLidar: Bool
    let deviceModel: String
    let registeredAt: Date
}

enum AttestationLevel: String, Codable {
    case secureEnclave = "secure_enclave"
    case unverified = "unverified"
}
```

### 6.3 Keychain Storage Keys

| Key | Value Type | Purpose |
|-----|------------|---------|
| `rial.attestation.keyId` | String | DCAppAttest key identifier |
| `rial.device.id` | UUID string | Registered device UUID |
| `rial.device.state` | JSON | Full DeviceState |
| `rial.encryption.key` | SymmetricKey (256-bit) | Offline capture encryption |

---

## 7. Per-Story Technical Breakdown

### Story 6.1: Initialize Native iOS Project

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-1-initialize-native-ios-project |
| **Title** | Initialize Native iOS Project |
| **Dependencies** | None (first story) |
| **Complexity** | Simple |

**Technical Implementation:**
- Create Xcode project with SwiftUI app lifecycle
- Configure bundle identifier (`app.rial.ios`)
- Set minimum deployment iOS 15.0
- Enable App Attest capability in Signing & Capabilities
- Create folder structure: App/, Core/, Features/, Models/, Shaders/, Resources/
- Configure Info.plist with usage descriptions
- Add test targets (RialTests, RialUITests)

**Files to Create:**
- `ios/Rial.xcodeproj`
- `ios/Rial/App/RialApp.swift`
- `ios/Rial/App/AppDelegate.swift`
- Folder structure as per architecture

**Acceptance Criteria:**
1. Xcode project builds successfully for iOS 15.0+
2. App Attest capability enabled
3. Test targets compile
4. Folder structure matches architecture document
5. Info.plist includes UIBackgroundModes with background-fetch

---

### Story 6.2: DCAppAttest Direct Integration

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-2-dcappattest-direct-integration |
| **Title** | DCAppAttest Direct Integration |
| **Dependencies** | 6.1, 6.4 |
| **Complexity** | Complex |

**Technical Implementation:**
```swift
import DeviceCheck

class DeviceAttestation {
    private let service = DCAppAttestService.shared

    func generateKey() async throws -> String {
        guard service.isSupported else {
            throw AttestationError.unsupported
        }
        return try await service.generateKey()
    }

    func attestKey(_ keyId: String, challenge: Data) async throws -> Data {
        let hash = SHA256.hash(data: challenge)
        return try await service.attestKey(keyId, clientDataHash: Data(hash))
    }

    func generateAssertion(_ keyId: String, clientData: Data) async throws -> Data {
        let hash = SHA256.hash(data: clientData)
        return try await service.generateAssertion(keyId, clientDataHash: Data(hash))
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Attestation/DeviceAttestation.swift`
- `ios/RialTests/Attestation/DeviceAttestationTests.swift`

**Acceptance Criteria:**
1. Key generation succeeds on supported devices
2. Attestation object produced for backend verification
3. Per-capture assertions complete in < 50ms
4. Graceful degradation on unsupported devices
5. Key ID persisted in Keychain

**FR Coverage:** FR2, FR3, FR10

---

### Story 6.3: CryptoKit Integration

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-3-cryptokit-integration |
| **Title** | CryptoKit Integration |
| **Dependencies** | 6.1 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
import CryptoKit

struct CryptoService {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sha256Data(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Crypto/CryptoService.swift`
- `ios/Rial/Core/Crypto/HashingService.swift`
- `ios/Rial/Core/Crypto/CaptureEncryption.swift`
- `ios/RialTests/Crypto/CryptoServiceTests.swift`

**Acceptance Criteria:**
1. SHA-256 produces correct hex digest
2. SHA-256 of 10MB file completes in < 100ms
3. AES-GCM encryption/decryption round-trip successful
4. Streaming hash for large files available
5. Unit tests pass

**FR Coverage:** FR11, FR17

---

### Story 6.4: Keychain Services Integration

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-4-keychain-services-integration |
| **Title** | Keychain Services Integration |
| **Dependencies** | 6.1 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
import Security

class KeychainService {
    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case itemNotFound
    }

    func save(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "app.rial.keychain",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try update(data, forKey: key)
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(status)
        }
    }

    func load(forKey key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "app.rial.keychain",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return data
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Storage/KeychainService.swift`
- `ios/RialTests/Storage/KeychainServiceTests.swift`

**Acceptance Criteria:**
1. Save/load/delete operations work correctly
2. Data accessible after device unlock
3. Data NOT accessible on other devices (ThisDeviceOnly)
4. Proper error handling with typed errors
5. Unit tests verify round-trip

**FR Coverage:** FR2, FR17, FR41

---

### Story 6.5: ARKit Unified Capture Session

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-5-arkit-unified-capture-session |
| **Title** | ARKit Unified Capture Session |
| **Dependencies** | 6.1 |
| **Complexity** | Complex |

**Technical Implementation:**
```swift
import ARKit

class ARCaptureSession: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private var currentFrame: ARFrame?

    var onFrameUpdate: ((ARFrame) -> Void)?

    func start() throws {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            throw CaptureError.lidarNotAvailable
        }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth)

        session.delegate = self
        session.run(config)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        currentFrame = frame
        onFrameUpdate?(frame)
    }

    func captureCurrentFrame() -> ARFrame? {
        return currentFrame
    }

    func stop() {
        session.pause()
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Capture/ARCaptureSession.swift`
- `ios/RialTests/Capture/ARCaptureSessionTests.swift`

**Acceptance Criteria:**
1. LiDAR availability check before starting
2. ARFrame contains both capturedImage and sceneDepth
3. Frame updates at 30fps+
4. Session handles interruptions gracefully
5. Proper cleanup on deinit (no memory leaks)

**FR Coverage:** FR1, FR6, FR7, FR8

---

### Story 6.6: Frame Processing Pipeline

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-6-frame-processing-pipeline |
| **Title** | Frame Processing Pipeline |
| **Dependencies** | 6.5 |
| **Complexity** | Complex |

**Technical Implementation:**
```swift
import ARKit
import CoreLocation
import Compression

class FrameProcessor {
    func process(_ frame: ARFrame, location: CLLocation?) async throws -> CaptureData {
        // Convert RGB to JPEG
        let jpeg = try await convertToJPEG(frame.capturedImage)

        // Extract and compress depth
        let depth = try compressDepth(frame.sceneDepth?.depthMap)

        // Build metadata
        let metadata = CaptureMetadata(
            capturedAt: Date(),
            deviceModel: UIDevice.current.model,
            photoHash: CryptoService.sha256(jpeg),
            location: location.map { LocationData(from: $0) },
            depthMapDimensions: DepthDimensions(
                width: CVPixelBufferGetWidth(frame.sceneDepth!.depthMap),
                height: CVPixelBufferGetHeight(frame.sceneDepth!.depthMap)
            )
        )

        return CaptureData(
            id: UUID(),
            jpeg: jpeg,
            depth: depth,
            metadata: metadata,
            assertion: nil,
            timestamp: Date()
        )
    }

    private func compressDepth(_ buffer: CVPixelBuffer?) throws -> Data {
        guard let buffer = buffer else { throw CaptureError.noDepthData }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!
        let data = Data(bytes: baseAddress, count: width * height * 4)

        // Gzip compress
        return try (data as NSData).compressed(using: .zlib) as Data
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Capture/FrameProcessor.swift`
- `ios/RialTests/Capture/FrameProcessorTests.swift`

**Acceptance Criteria:**
1. JPEG conversion from CVPixelBuffer successful
2. Depth map compressed to ~1MB or less
3. Processing completes in < 200ms
4. GPS metadata included when permitted
5. Runs on background queue (not blocking UI)

**FR Coverage:** FR7, FR8, FR9, FR12, FR13

---

### Story 6.7: Metal Depth Visualization

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-7-metal-depth-visualization |
| **Title** | Metal Depth Visualization |
| **Dependencies** | 6.5 |
| **Complexity** | Complex |

**Technical Implementation:**

Metal Shader (`DepthVisualization.metal`):
```metal
#include <metal_stdlib>
using namespace metal;

constant float3 nearColor = float3(1.0, 0.0, 0.0);   // Red
constant float3 farColor = float3(0.0, 0.0, 1.0);    // Blue

fragment float4 depthFragment(
    VertexOut in [[stage_in]],
    texture2d<float> depthTex [[texture(0)]],
    constant float &nearPlane [[buffer(0)]],
    constant float &farPlane [[buffer(1)]],
    constant float &opacity [[buffer(2)]]
) {
    constexpr sampler s(filter::linear);
    float depth = depthTex.sample(s, in.texCoord).r;

    float normalized = saturate((depth - nearPlane) / (farPlane - nearPlane));
    float3 color = mix(nearColor, farColor, normalized);

    return float4(color, opacity);
}
```

**Files to Create:**
- `ios/Rial/Shaders/DepthVisualization.metal`
- `ios/Rial/Features/Capture/DepthOverlayView.swift`
- `ios/Rial/Core/Capture/DepthVisualizer.swift`

**Acceptance Criteria:**
1. Depth renders as color gradient (near=warm, far=cool)
2. Rendering at 60fps with < 2ms per frame
3. Opacity adjustable 0-100%
4. Toggle on/off without restarting ARSession
5. Works in portrait and landscape

**FR Coverage:** FR6

---

### Story 6.8: Per-Capture Assertion Signing

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-8-per-capture-assertion-signing |
| **Title** | Per-Capture Assertion Signing |
| **Dependencies** | 6.2, 6.3, 6.6 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
class CaptureAssertion {
    private let attestation: DeviceAttestation
    private let keyId: String

    func createAssertion(for capture: CaptureData) async throws -> Data {
        // Combine JPEG + depth for hash
        let combinedData = capture.jpeg + capture.depth
        let hash = CryptoService.sha256Data(combinedData)

        return try await attestation.generateAssertion(keyId, clientData: hash)
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Attestation/CaptureAssertion.swift`
- `ios/RialTests/Attestation/CaptureAssertionTests.swift`

**Acceptance Criteria:**
1. Assertion includes hash of JPEG + depth
2. Assertion generation completes in < 50ms
3. Assertion failure doesn't block capture (queued for retry)
4. Backend can verify assertion

**FR Coverage:** FR10

---

### Story 6.9: CoreData Capture Queue

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-9-coredata-capture-queue |
| **Title** | CoreData Capture Queue |
| **Dependencies** | 6.1 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
import CoreData

class CaptureStore {
    private let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "RialModel")

        // Configure data protection
        let storeURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Rial.sqlite")

        let description = NSPersistentStoreDescription(url: storeURL)
        description.setOption(
            FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("CoreData load failed: \(error)")
            }
        }
    }

    func saveCapture(_ capture: CaptureData, status: CaptureStatus = .pending) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            let entity = CaptureEntity(context: context)
            entity.id = capture.id
            entity.jpeg = capture.jpeg
            entity.depth = capture.depth
            entity.metadata = try JSONEncoder().encode(capture.metadata)
            entity.assertion = capture.assertion
            entity.status = status.rawValue
            entity.createdAt = Date()
            entity.attemptCount = 0
            try context.save()
        }
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Storage/CaptureStore.swift`
- `ios/Rial/Core/Storage/OfflineQueue.swift`
- `ios/Rial/Models/RialModel.xcdatamodeld`
- `ios/RialTests/Storage/CaptureStoreTests.swift`

**Acceptance Criteria:**
1. Captures persist across app restarts
2. Status tracking: pending, uploading, uploaded, failed
3. Automatic cleanup of uploaded captures after 7 days
4. Storage quota warning at 500MB
5. Migration support for future schema changes

**FR Coverage:** FR17, FR18, FR19

---

### Story 6.10: iOS Data Protection Encryption

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-10-ios-data-protection-encryption |
| **Title** | iOS Data Protection Encryption |
| **Dependencies** | 6.3, 6.4, 6.9 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
class EncryptedCaptureStore: CaptureStore {
    private let keychain: KeychainService
    private var encryptionKey: SymmetricKey?

    func getOrCreateEncryptionKey() throws -> SymmetricKey {
        if let key = encryptionKey {
            return key
        }

        do {
            let keyData = try keychain.load(forKey: "rial.encryption.key")
            encryptionKey = SymmetricKey(data: keyData)
        } catch {
            // Generate new key
            let key = CryptoService.generateKey()
            let keyData = key.withUnsafeBytes { Data($0) }
            try keychain.save(keyData, forKey: "rial.encryption.key")
            encryptionKey = key
        }

        return encryptionKey!
    }

    func encryptBeforeSave(_ data: Data) throws -> Data {
        let key = try getOrCreateEncryptionKey()
        return try CryptoService.encrypt(data, using: key)
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Storage/EncryptedCaptureStore.swift`
- `ios/RialTests/Storage/EncryptedCaptureStoreTests.swift`

**Acceptance Criteria:**
1. CoreData store uses completeUntilFirstUserAuthentication
2. Capture data encrypted with AES-GCM before storage
3. Encryption key in Keychain (hardware-backed)
4. Decryption happens lazily on access
5. Data encrypted in device backups

**FR Coverage:** FR17

---

### Story 6.11: URLSession Background Uploads

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-11-urlsession-background-uploads |
| **Title** | URLSession Background Uploads |
| **Dependencies** | 6.1, 6.9 |
| **Complexity** | Complex |

**Technical Implementation:**
```swift
class UploadService: NSObject, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "app.rial.upload")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    var backgroundCompletionHandler: (() -> Void)?

    func upload(_ capture: CaptureData, deviceId: UUID, signature: String) async throws {
        let url = URL(string: "\(baseURL)/api/v1/captures")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Add auth headers
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        request.addValue(deviceId.uuidString, forHTTPHeaderField: "X-Device-Id")
        request.addValue(String(timestamp), forHTTPHeaderField: "X-Device-Timestamp")
        request.addValue(signature, forHTTPHeaderField: "X-Device-Signature")

        // Create multipart body
        let body = try createMultipartBody(capture)

        // Write to temp file for background upload
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(capture.id.uuidString)
        try body.write(to: tempFile)

        let task = session.uploadTask(with: request, fromFile: tempFile)
        task.resume()
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Networking/UploadService.swift`
- `ios/Rial/Core/Networking/APIClient.swift`
- `ios/Rial/Core/Networking/DeviceSignature.swift`
- `ios/RialTests/Networking/UploadServiceTests.swift`

**Acceptance Criteria:**
1. Uploads continue in background after app closure
2. App woken on completion to update status
3. Incomplete uploads resume on app relaunch
4. Multipart form-data properly formatted
5. Progress tracked via delegate

**FR Coverage:** FR14, FR16, FR18

---

### Story 6.12: Certificate Pinning & Retry Logic

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-12-certificate-pinning-retry-logic |
| **Title** | Certificate Pinning & Retry Logic |
| **Dependencies** | 6.11 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
extension UploadService: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust,
              let cert = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get server public key
        guard let serverKey = SecCertificateCopyKey(cert),
              let serverKeyData = SecKeyCopyExternalRepresentation(serverKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Compare against pinned key
        if serverKeyData == pinnedPublicKey {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

class RetryManager {
    private let maxAttempts = 5
    private let baseDelay: TimeInterval = 1.0

    func nextDelay(for attemptCount: Int) -> TimeInterval {
        min(pow(2.0, Double(attemptCount)) * baseDelay, 60.0)
    }

    func shouldRetry(attemptCount: Int) -> Bool {
        attemptCount < maxAttempts
    }
}
```

**Files to Create:**
- `ios/Rial/Core/Networking/CertificatePinning.swift`
- `ios/Rial/Core/Networking/RetryManager.swift`
- `ios/RialTests/Networking/RetryManagerTests.swift`

**Acceptance Criteria:**
1. Server certificate verified against pinned key
2. Pinning failure rejects connection
3. TLS 1.3 minimum enforced
4. Exponential backoff: 1s, 2s, 4s, 8s, 16s
5. Max 5 attempts before marking as failed
6. Network reachability change triggers retry

**FR Coverage:** FR15, FR16

---

### Story 6.13: SwiftUI Capture Screen

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-13-swiftui-capture-screen |
| **Title** | SwiftUI Capture Screen |
| **Dependencies** | 6.5, 6.6, 6.7 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
struct CaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @State private var showDepthOverlay = true

    var body: some View {
        ZStack {
            // AR Camera Preview
            ARViewContainer(session: viewModel.captureSession)
                .ignoresSafeArea()

            // Depth Overlay
            if showDepthOverlay {
                DepthOverlayView(depthFrame: viewModel.currentDepthFrame)
                    .opacity(0.4)
            }

            // Controls
            VStack {
                Spacer()

                HStack {
                    // Depth toggle
                    Button(action: { showDepthOverlay.toggle() }) {
                        Image(systemName: showDepthOverlay ? "eye" : "eye.slash")
                    }

                    Spacer()

                    // Capture button
                    CaptureButton(action: viewModel.capture)

                    Spacer()

                    // Placeholder for symmetry
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding()
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}
```

**Files to Create:**
- `ios/Rial/Features/Capture/CaptureView.swift`
- `ios/Rial/Features/Capture/CaptureViewModel.swift`
- `ios/Rial/Features/Capture/CaptureButton.swift`
- `ios/Rial/Features/Capture/ARViewContainer.swift`
- `ios/RialUITests/CaptureViewTests.swift`

**Acceptance Criteria:**
1. Full-screen AR camera preview
2. Depth overlay toggle with SF Symbol
3. Large capture button with haptic feedback
4. Preview shows captured photo with Use/Retake
5. Handles permission requests

**FR Coverage:** FR6, FR7

---

### Story 6.14: Capture History View

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-14-capture-history-view |
| **Title** | Capture History View |
| **Dependencies** | 6.9, 6.11 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
struct HistoryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CaptureEntity.createdAt, ascending: false)]
    ) private var captures: FetchedResults<CaptureEntity>

    let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        NavigationStack {
            ScrollView {
                if captures.isEmpty {
                    EmptyHistoryView()
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(captures) { capture in
                            NavigationLink(destination: ResultDetailView(capture: capture)) {
                                CaptureThumbnailView(capture: capture)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("History")
            .refreshable {
                await retryFailedUploads()
            }
        }
    }
}
```

**Files to Create:**
- `ios/Rial/Features/History/HistoryView.swift`
- `ios/Rial/Features/History/HistoryViewModel.swift`
- `ios/Rial/Features/History/CaptureThumbnailView.swift`
- `ios/Rial/Features/History/EmptyHistoryView.swift`
- `ios/RialUITests/HistoryViewTests.swift`

**Acceptance Criteria:**
1. Grid of thumbnails (3 columns)
2. Status badges: uploaded (green), uploading (blue), pending (gray), failed (red)
3. Sorted by date (newest first)
4. Empty state with capture CTA
5. Pull-to-refresh retries failed uploads

**FR Coverage:** FR19

---

### Story 6.15: Result Detail View

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-15-result-detail-view |
| **Title** | Result Detail View |
| **Dependencies** | 6.14, 6.11 |
| **Complexity** | Medium |

**Technical Implementation:**
```swift
struct ResultDetailView: View {
    let capture: CaptureEntity
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Full photo with zoom
                ZoomableImageView(data: capture.jpeg)
                    .aspectRatio(contentMode: .fit)

                // Status section
                if let level = capture.confidenceLevel {
                    ConfidenceBadge(level: level)
                }

                // Evidence summary
                if capture.status == "uploaded" {
                    EvidenceSummaryView(capture: capture)
                }

                // Verification URL
                if let url = capture.verificationUrl {
                    VStack {
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Copy Link") {
                                UIPasteboard.general.string = url
                            }

                            ShareLink(
                                item: URL(string: url)!,
                                preview: SharePreview("Verified photo", image: thumbnail)
                            )
                        }
                    }
                }

                // Retry for failed
                if capture.status == "failed" {
                    Button("Retry Upload") {
                        retryUpload()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Capture Details")
    }
}
```

**Files to Create:**
- `ios/Rial/Features/Result/ResultDetailView.swift`
- `ios/Rial/Features/Result/ConfidenceBadge.swift`
- `ios/Rial/Features/Result/EvidenceSummaryView.swift`
- `ios/Rial/Features/Result/ZoomableImageView.swift`
- `ios/RialUITests/ResultDetailViewTests.swift`

**Acceptance Criteria:**
1. Full photo with pinch-to-zoom
2. Confidence badge (HIGH/MEDIUM/LOW)
3. Evidence summary for uploaded captures
4. Copy link and Share buttons
5. Retry button for failed uploads

**FR Coverage:** FR19, FR31

---

### Story 6.16: Feature Parity Validation

| Attribute | Value |
|-----------|-------|
| **Story Key** | 6-16-feature-parity-validation |
| **Title** | Feature Parity Validation |
| **Dependencies** | ALL stories 6.1-6.15 |
| **Complexity** | Medium |

**Technical Implementation:**
- Side-by-side testing of native vs Expo app
- Performance benchmarking
- Backend compatibility verification
- XCUITest automation for critical flows

**Validation Checklist:**
- [ ] Device registration produces valid attestation (both apps)
- [ ] Capture produces valid JPEG + depth (format matches)
- [ ] Backend accepts uploads from native app
- [ ] Assertion verification passes
- [ ] History displays same server-side captures
- [ ] Share links work identically

**Files to Create:**
- `ios/RialUITests/FeatureParityTests.swift`
- `docs/native-migration-guide.md`

**Acceptance Criteria:**
1. All functionality matches Expo app
2. Performance documented (native should be faster)
3. Memory usage lower than Expo
4. Background upload reliability confirmed
5. XCUITest covers critical flows
6. Migration guide created

**FR Coverage:** All mobile FRs (validation)

---

## 8. Testing Strategy

### 8.1 XCTest Unit Tests

| Test Target | Coverage Areas |
|-------------|----------------|
| `CryptoServiceTests` | SHA-256, AES-GCM encryption/decryption |
| `KeychainServiceTests` | Save/load/delete, error handling |
| `FrameProcessorTests` | JPEG conversion, depth compression |
| `CaptureStoreTests` | CoreData operations, status transitions |
| `RetryManagerTests` | Exponential backoff calculations |
| `DeviceAttestationTests` | Key generation, attestation flow (mocked) |

**DCAppAttest Mock Example for XCTest:**

```swift
import XCTest
@testable import Rial

/// Mock DCAppAttestService for unit testing attestation flows
class MockDCAppAttestService {
    var isSupported: Bool = true
    var shouldFailKeyGeneration: Bool = false
    var shouldFailAttestation: Bool = false
    var shouldFailAssertion: Bool = false

    private var generatedKeyId: String?

    func generateKey() async throws -> String {
        guard isSupported else {
            throw AttestationError.unsupported
        }
        guard !shouldFailKeyGeneration else {
            throw AttestationError.keyGenerationFailed
        }
        let keyId = UUID().uuidString
        generatedKeyId = keyId
        return keyId
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        guard !shouldFailAttestation else {
            throw AttestationError.attestationFailed
        }
        // Return mock attestation object (CBOR-like structure)
        return Data("mock-attestation-\(keyId)-\(clientDataHash.base64EncodedString())".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        guard !shouldFailAssertion else {
            throw AttestationError.assertionFailed
        }
        // Return mock assertion
        return Data("mock-assertion-\(keyId)-\(clientDataHash.base64EncodedString())".utf8)
    }
}

/// Protocol for dependency injection
protocol AppAttestServiceProtocol {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

/// Usage in tests
class DeviceAttestationTests: XCTestCase {
    var mockService: MockDCAppAttestService!
    var sut: DeviceAttestation!

    override func setUp() {
        super.setUp()
        mockService = MockDCAppAttestService()
        sut = DeviceAttestation(service: mockService)
    }

    func testKeyGenerationSuccess() async throws {
        let keyId = try await sut.generateKey()
        XCTAssertFalse(keyId.isEmpty)
    }

    func testKeyGenerationFailsWhenUnsupported() async {
        mockService.isSupported = false
        do {
            _ = try await sut.generateKey()
            XCTFail("Expected error")
        } catch AttestationError.unsupported {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testAssertionGenerationSuccess() async throws {
        let keyId = try await sut.generateKey()
        let clientData = Data("test-capture-hash".utf8)
        let assertion = try await sut.generateAssertion(keyId, clientData: clientData)
        XCTAssertFalse(assertion.isEmpty)
    }
}
```

### 8.2 XCUITest UI Tests

| Test Suite | Scenarios |
|------------|-----------|
| `CaptureFlowTests` | Camera permission, capture, preview, confirm |
| `HistoryFlowTests` | View history, status badges, navigation |
| `ResultFlowTests` | View details, share link, retry upload |
| `FeatureParityTests` | End-to-end validation against Expo app |

### 8.3 Test Environment Split

**Simulator-Compatible Tests (CI Pipeline):**

| Test Type | Coverage | Environment |
|-----------|----------|-------------|
| Unit Tests | CryptoService, RetryManager, data models | Xcode Simulator (any) |
| CoreData Tests | Persistence, status transitions, queries | Xcode Simulator (any) |
| ViewModel Tests | Business logic, state management | Xcode Simulator (any) |
| API Client Tests | Request building, response parsing (mocked) | Xcode Simulator (any) |

**Physical Device Required Tests:**

| Test Type | Coverage | Environment |
|-----------|----------|-------------|
| DCAppAttest Tests | Key generation, attestation, assertions | iPhone Pro (physical) |
| ARKit/LiDAR Tests | Depth capture, frame synchronization | iPhone Pro with LiDAR |
| Background Upload Tests | URLSession background behavior | Physical device |
| Certificate Pinning Tests | TLS validation | Physical device with network |
| XCUITest E2E | Full capture flow | iPhone Pro with LiDAR |

**CI Pipeline Strategy:**
- CI runs simulator-compatible unit tests only
- Physical device tests require manual execution or dedicated device farm
- PR checks include: unit tests, linting, build verification
- Release validation includes full physical device test suite

### 8.4 Physical Device Requirements

**Required for Testing:**
- iPhone Pro (12 Pro or later) with LiDAR
- iOS 15.0 or later
- Apple Developer account for device provisioning
- Network access to backend API
- Xcode 16+ for Swift 5.9 support

**Cannot Test in Simulator:**
- DCAppAttest (requires Secure Enclave)
- LiDAR depth capture
- Background upload behavior
- Certificate pinning

### 8.5 Test Commands

```bash
# Run unit tests
xcodebuild test \
  -project ios/Rial.xcodeproj \
  -scheme Rial \
  -destination 'platform=iOS,name=iPhone 15 Pro'

# Run UI tests
xcodebuild test \
  -project ios/Rial.xcodeproj \
  -scheme RialUITests \
  -destination 'platform=iOS,name=iPhone 15 Pro'
```

### 8.6 Performance Measurement Approach

**Frame Rate Verification:**
- Use Xcode Instruments > Core Animation to verify 60fps rendering
- Look for > 95% frame rate consistency (57fps+ sustained)
- Monitor for dropped frames during depth overlay rendering
- Test on oldest supported device (iPhone 12 Pro) for worst-case performance

**Processing Benchmarks:**
- Use Time Profiler in Instruments for SHA-256 and frame processing benchmarks
- Target: SHA-256 of 10MB file < 100ms
- Target: Frame processing (JPEG + depth compression) < 200ms
- Target: Per-capture assertion generation < 50ms

**Memory Profiling:**
- Use Allocations instrument to track memory during capture flow
- Monitor for leaks in ARSession frame handling
- Target: Peak memory during capture < 300MB
- Ensure memory returns to baseline after capture completion

**Performance Test Automation:**
```swift
func testSHA256Performance() {
    let testData = Data(repeating: 0x42, count: 10_000_000) // 10MB
    measure {
        _ = CryptoService.sha256(testData)
    }
}

func testFrameProcessingPerformance() {
    // Requires physical device with mock ARFrame
    measure {
        // Frame processing benchmark
    }
}
```

---

## 9. Security Considerations

### 9.1 Secure Enclave Usage

| Operation | Secure Enclave Role |
|-----------|-------------------|
| Key Generation | DCAppAttest keys generated in hardware |
| Key Storage | Keys never leave Secure Enclave boundary |
| Signing | Assertions signed within hardware |
| Extraction | Impossible - keys are non-extractable |

### 9.2 Data Protection Levels

| Data Type | Protection Level | Implementation |
|-----------|-----------------|----------------|
| CoreData Store | completeUntilFirstUserAuthentication | NSPersistentStoreFileProtectionKey |
| Capture Data | AES-GCM encrypted | CryptoKit before CoreData save |
| Keychain Items | AfterFirstUnlockThisDeviceOnly | kSecAttrAccessible |
| Encryption Key | Secure Enclave backed | Keychain with hardware protection |

### 9.3 Certificate Pinning Approach

```swift
// Pinned public key (SPKI hash)
let pinnedPublicKey = Data(base64Encoded: "...")!

// Validation in URLSessionDelegate
func validateServerCertificate(_ trust: SecTrust) -> Bool {
    guard let cert = SecTrustGetCertificateAtIndex(trust, 0),
          let key = SecCertificateCopyKey(cert),
          let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
        return false
    }
    return keyData == pinnedPublicKey
}
```

**Key Rotation:** Store multiple pinned keys, remove old keys after transition period.

### 9.4 Logging and Observability

**Event Logging Strategy:**

Use Apple's unified logging framework (`os.log`) for consistent, privacy-aware logging across the app.

```swift
import os.log

extension Logger {
    static let capture = Logger(subsystem: "app.rial", category: "capture")
    static let upload = Logger(subsystem: "app.rial", category: "upload")
    static let attestation = Logger(subsystem: "app.rial", category: "attestation")
    static let crypto = Logger(subsystem: "app.rial", category: "crypto")
}

// Usage examples
Logger.capture.info("Capture initiated: \(captureId, privacy: .public)")
Logger.upload.error("Upload failed: \(error.localizedDescription, privacy: .public)")
Logger.attestation.debug("Assertion generated in \(duration)ms")
```

**Key Milestones to Log:**

| Event | Log Level | Category | Data Logged |
|-------|-----------|----------|-------------|
| Capture started | Info | capture | Capture ID, timestamp |
| Capture completed | Info | capture | Capture ID, duration, depth map size |
| Upload started | Info | upload | Capture ID, file size |
| Upload progress | Debug | upload | Capture ID, bytes sent, percentage |
| Upload completed | Info | upload | Capture ID, duration, server capture ID |
| Upload failed | Error | upload | Capture ID, error code, attempt count |
| Attestation key generated | Info | attestation | Key ID (redacted) |
| Assertion generated | Debug | attestation | Duration, capture ID |
| Encryption completed | Debug | crypto | Data size, duration |
| Network reachability change | Info | upload | New status |

**Metrics to Track:**

| Metric | Type | Target |
|--------|------|--------|
| Frame rate during capture | Gauge | > 57fps (95%) |
| Frame processing time | Histogram | P95 < 200ms |
| Upload success rate | Counter | > 99% |
| Upload duration | Histogram | P95 < 30s (5MB) |
| Assertion generation time | Histogram | P95 < 50ms |
| Retry count per upload | Counter | Average < 1.2 |
| Offline queue depth | Gauge | Alert if > 10 |

**Log Retention Policy:**
- Device logs: 30 days minimum (system managed)
- Use `OSLogStore` for programmatic access to recent logs
- Critical errors persisted to CoreData for crash recovery analysis
- No PII in logs (use `privacy: .private` for sensitive data)

**Observability Implementation:**

```swift
struct CaptureMetrics {
    static let shared = CaptureMetrics()

    private let frameRateSignpost = OSSignposter(subsystem: "app.rial", category: "performance")

    func trackFrameRate(_ interval: SignpostIntervalState) {
        frameRateSignpost.endInterval("frame", interval)
    }

    func logCaptureComplete(id: UUID, duration: TimeInterval, depthSize: Int) {
        Logger.capture.info("""
            Capture complete: \
            id=\(id.uuidString, privacy: .public), \
            duration=\(duration, format: .fixed(precision: 2))ms, \
            depthBytes=\(depthSize)
            """)
    }

    func logUploadMetrics(captureId: UUID, bytesUploaded: Int, duration: TimeInterval, success: Bool) {
        if success {
            Logger.upload.info("""
                Upload success: \
                id=\(captureId.uuidString, privacy: .public), \
                bytes=\(bytesUploaded), \
                duration=\(duration, format: .fixed(precision: 2))s
                """)
        }
    }
}
```

---

## 10. FR Traceability Matrix

| FR | Description | Story | Implementation Location |
|----|-------------|-------|------------------------|
| FR1 | Detect iPhone Pro with LiDAR | 6.5 | ARCaptureSession.swift |
| FR2 | Generate Secure Enclave keys | 6.2, 6.4 | DeviceAttestation.swift, KeychainService.swift |
| FR3 | Request DCAppAttest attestation | 6.2 | DeviceAttestation.swift |
| FR6 | Camera view with depth overlay | 6.5, 6.7, 6.13 | ARCaptureSession.swift, DepthOverlayView.swift, CaptureView.swift |
| FR7 | Capture photo | 6.5, 6.6, 6.13 | ARCaptureSession.swift, FrameProcessor.swift, CaptureView.swift |
| FR8 | Capture LiDAR depth map | 6.5, 6.6 | ARCaptureSession.swift, FrameProcessor.swift |
| FR9 | Record GPS coordinates | 6.6 | FrameProcessor.swift (metadata) |
| FR10 | Capture attestation signature | 6.8 | CaptureAssertion.swift |
| FR11 | Compute SHA-256 hash | 6.3 | CryptoService.swift |
| FR12 | Compress depth map | 6.6 | FrameProcessor.swift |
| FR13 | Construct capture request | 6.6 | FrameProcessor.swift |
| FR14 | Upload via multipart POST | 6.11 | UploadService.swift |
| FR15 | TLS 1.3 for API | 6.12 | CertificatePinning.swift |
| FR16 | Retry with exponential backoff | 6.12 | RetryManager.swift |
| FR17 | Encrypted offline storage | 6.3, 6.9, 6.10 | CaptureEncryption.swift, CaptureStore.swift, EncryptedCaptureStore.swift |
| FR18 | Auto-upload when online | 6.11 | UploadService.swift |
| FR19 | Pending upload status | 6.9, 6.14 | CaptureStore.swift, HistoryView.swift |
| FR31 | Shareable verify URL | 6.15 | ResultDetailView.swift |
| FR41 | Device pseudonymous ID | 6.4 | KeychainService.swift |
| FR42 | Anonymous capture | 6.2 | DeviceAttestation.swift |
| FR43 | Device registration storage | 6.4 | KeychainService.swift |
| FR44 | Coarse GPS in public view | 6.6 | FrameProcessor.swift (server-side coarsening) |
| FR45 | Location opt-out | 6.6 | FrameProcessor.swift (optional location) |
| FR46 | Depth map not downloadable | N/A | Backend only (not in native app scope) |

---

## 11. Risks, Assumptions, and Questions

### 11.1 Assumptions

| Assumption | Rationale | Impact if Wrong |
|------------|-----------|-----------------|
| **Xcode 16+ available** | Required for Swift 5.9 features and iOS 18 SDK | Cannot build project; downgrade Swift version |
| **iOS 15.0+ adoption** | All iPhone Pro models (12 Pro+) support iOS 15+ | Minimal - target devices all support iOS 15+ |
| **Swift 5.9+ compiler** | Needed for modern concurrency and observation macros | Refactor to older Swift patterns |
| **Secure Enclave availability** | All target devices (iPhone Pro) have Secure Enclave | No fallback - Secure Enclave required for attestation |
| **Physical device for testing** | Simulator cannot test DCAppAttest, LiDAR, background uploads | Testing coverage gaps; CI limited to unit tests |
| **Backend API compatibility** | Existing API endpoints support native app requests | API changes may require coordination |
| **LiDAR sensor present** | All iPhone Pro models include LiDAR | App cannot function without LiDAR |

### 11.2 Technical Risks

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| **Simulator cannot test DCAppAttest/LiDAR** | Certain | High | Establish physical device testing plan; dedicated test device; clear test split between simulator and device |
| **Background upload reliability** | Medium | Medium | Dependent on system resources; implement robust retry logic; monitor upload success rates |
| **ARKit frame rate inconsistency** | Low | Medium | Optimize frame processing; use background queues; profile on older devices (iPhone 12 Pro) |
| **Secure Enclave key loss** | Low | High | Implement device re-registration flow; keys cannot be backed up by design |
| **Certificate pinning rotation** | Medium | Medium | Store multiple pinned keys; implement rotation mechanism before expiry |
| **CoreData migration issues** | Low | Medium | Design schema carefully; test migrations; implement migration error recovery |
| **Memory pressure during capture** | Medium | Medium | Profile memory usage; optimize depth buffer handling; implement memory warnings |

### 11.3 Open Questions

| Question | Owner | Status | Resolution Path |
|----------|-------|--------|-----------------|
| **CI/CD strategy for device-only tests?** | DevOps | Open | Evaluate device farm options (Firebase Test Lab, AWS Device Farm, BrowserStack) |
| **Performance benchmarks vs Expo app?** | Engineering | Open | Establish baseline metrics during Story 6.16 validation |
| **App Store review for attestation usage?** | Product | Open | Review Apple guidelines; prepare justification for attestation |
| **Depth map format compatibility?** | Backend | Open | Verify gzip Float32 format matches existing Expo app output |
| **Background upload battery impact?** | Engineering | Open | Profile battery usage during extended upload sessions |

### 11.4 Dependencies

| Dependency | Type | Risk Level | Notes |
|------------|------|------------|-------|
| Apple Developer Program membership | External | Low | Required for device provisioning and App Attest |
| Backend API availability | Internal | Low | Existing endpoints; no changes needed |
| Physical test device | Hardware | Medium | At least one iPhone Pro with LiDAR required |
| Xcode 16+ | Tooling | Low | Standard development requirement |

---

## 12. Summary

### 12.1 Epic Statistics

| Metric | Value |
|--------|-------|
| Total Stories | 16 |
| Phase 1 (Security Foundation) | 4 stories |
| Phase 2 (Capture Core) | 4 stories |
| Phase 3 (Storage & Upload) | 4 stories |
| Phase 4 (User Experience) | 4 stories |
| Total Acceptance Criteria | 79 |
| FRs Covered | 19 (all mobile FRs) |

### 12.2 Story Complexity Distribution

| Complexity | Count | Stories |
|------------|-------|---------|
| Simple | 1 | 6.1 |
| Medium | 9 | 6.3, 6.4, 6.8, 6.9, 6.10, 6.12, 6.13, 6.14, 6.15, 6.16 |
| Complex | 6 | 6.2, 6.5, 6.6, 6.7, 6.11 |

### 12.3 Ready for Implementation

This tech spec provides complete technical context for implementing Epic 6. The native Swift implementation will provide:

1. **Maximum Security:** No JS bridge, direct Secure Enclave access
2. **Perfect Synchronization:** Unified ARFrame for RGB + depth
3. **Reliable Uploads:** Background URLSession survives termination
4. **Auditable Code:** Single language, zero external dependencies
5. **Better UX:** 60fps Metal rendering, native iOS patterns

---

_Generated by BMAD Epic Tech Context Workflow_
_Date: 2025-11-25_
_For: Epic 6 - Native Swift Implementation_
