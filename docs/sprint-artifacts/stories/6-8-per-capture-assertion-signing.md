# Story 6.8: Per-Capture Assertion Signing

**Story Key:** 6-8-per-capture-assertion-signing
**Epic:** 6 - Native Swift Implementation
**Status:** Done
**Created:** 2025-11-25
**Completed:** 2025-11-25

---

## User Story

As a **RealityCam backend system**,
I want **each photo capture to include a DCAppAttest assertion proving capture authenticity**,
So that **I can cryptographically verify that the photo+depth data came from a registered device's Secure Enclave at a specific moment in time**.

## Story Context

This story implements per-capture assertion generation using DCAppAttest, where each capture triggers a fresh hardware-backed cryptographic signature over the combined photo+depth hash. This assertion provides proof that the capture data was processed by the registered app on a verified device, binding the capture to the device's attestation key stored in Secure Enclave.

Unlike device attestation (Story 6.2) which happens once during registration, per-capture assertions happen for every photo taken. Each assertion includes a hash of the capture data (JPEG + compressed depth) and is signed by the device's Secure Enclave key, making it impossible to forge or replay from a different device.

### Key Assertion Features

1. **Per-Capture Binding**: Each assertion links to specific capture data via SHA-256 hash
2. **Hardware-Backed Signing**: Secure Enclave signs assertion, key never leaves hardware
3. **Freshness Guarantee**: Assertion counter increments with each generation, preventing replay
4. **Fast Generation**: < 50ms per assertion to avoid blocking capture flow
5. **Failure Resilience**: Captures queue without assertion if generation fails, retry later

### Assertion Flow

```
Capture Data (JPEG + Depth)
    ↓
SHA-256 Hash (Combined)
    ↓
DCAppAttest generateAssertion(keyId, clientData: hash)
    ↓ [Secure Enclave]
Assertion Data (CBOR-encoded signature + counter)
    ↓
Attached to Capture Metadata
    ↓
Uploaded to Backend for Verification
```

### Performance Targets

| Operation | Target | Rationale |
|-----------|--------|-----------|
| Hash computation (JPEG + depth) | < 30ms | ~4MB combined data, hardware-accelerated SHA-256 |
| Assertion generation | < 50ms | Secure Enclave operation, should not block UI |
| Total per-capture overhead | < 100ms | Combined hash + assertion time |
| Failure handling | Non-blocking | Capture saved without assertion if fails |
| Retry queue processing | Background | Retry assertion generation offline |

### Backend Verification

The backend uses the assertion to verify:
1. **Device Identity**: Assertion signed by registered device's public key
2. **Capture Binding**: Hash in assertion matches received photo+depth hash
3. **Freshness**: Assertion counter is sequential (no replay attacks)
4. **Integrity**: Apple's attestation server confirms signature validity

---

## Acceptance Criteria

### AC1: CaptureAssertion Service Implementation
**Given** a CaptureAssertion service initialized with device attestation key ID
**When** createAssertion(for: CaptureData) is called
**Then**:
- Service combines capture JPEG and depth data into single Data blob
- Service computes SHA-256 hash of combined data using CryptoService
- Service calls DeviceAttestation.generateAssertion(keyId, clientData: hash)
- DCAppAttest generateAssertion called with key ID and SHA-256 hash
- Assertion Data returned contains CBOR-encoded signature and counter
- Assertion data is non-empty (typically 1-2KB)
- Assertion generation completes in < 50ms (measured with XCTest.measure)

**And** error handling:
- If key ID not found in keychain, throw `.attestationKeyNotFound`
- If DCAppAttest fails, throw `.assertionGenerationFailed(Error)`
- If hash computation fails, throw `.hashComputationFailed`
- All errors logged with Logger.attestation
- Capture can proceed without assertion (marked for retry)

**Implementation Reference:**
```swift
import DeviceCheck
import CryptoKit
import Foundation

class CaptureAssertion {
    private let attestation: DeviceAttestation
    private let keychain: KeychainService

    enum AssertionError: Error, LocalizedError {
        case attestationKeyNotFound
        case assertionGenerationFailed(Error)
        case hashComputationFailed

        var errorDescription: String? {
            switch self {
            case .attestationKeyNotFound:
                return "Device attestation key not found in keychain"
            case .assertionGenerationFailed(let error):
                return "Failed to generate assertion: \(error.localizedDescription)"
            case .hashComputationFailed:
                return "Failed to compute capture data hash"
            }
        }
    }

    init(attestation: DeviceAttestation, keychain: KeychainService) {
        self.attestation = attestation
        self.keychain = keychain
    }

    func createAssertion(for capture: CaptureData) async throws -> Data {
        // Get key ID from keychain
        guard let keyIdData = try? keychain.load(forKey: "rial.attestation.keyId"),
              let keyId = String(data: keyIdData, encoding: .utf8) else {
            throw AssertionError.attestationKeyNotFound
        }

        // Combine JPEG + depth for hash
        var combinedData = Data()
        combinedData.append(capture.jpeg)
        combinedData.append(capture.depth)

        // Compute SHA-256 hash
        let hash = CryptoService.sha256Data(combinedData)

        // Generate assertion from Secure Enclave
        do {
            let assertion = try await attestation.generateAssertion(keyId, clientData: hash)

            Logger.attestation.info("""
                Assertion generated: \
                captureId=\(capture.id.uuidString, privacy: .public), \
                assertionSize=\(assertion.count), \
                dataSize=\(combinedData.count)
                """)

            return assertion
        } catch {
            Logger.attestation.error("""
                Assertion generation failed: \
                captureId=\(capture.id.uuidString, privacy: .public), \
                error=\(error.localizedDescription, privacy: .public)
                """)
            throw AssertionError.assertionGenerationFailed(error)
        }
    }
}
```

### AC2: Assertion Integration in Capture Flow
**Given** FrameProcessor completes capture processing (Story 6.6)
**When** capture is ready to be saved
**Then**:
- FrameProcessor calls CaptureAssertion.createAssertion(for: captureData)
- Assertion generation runs on background queue (not main thread)
- If assertion succeeds, CaptureData.assertion field populated with assertion Data
- If assertion fails, CaptureData.assertion remains nil
- Capture saved to CoreData regardless of assertion success/failure
- Failed assertions marked for retry in upload queue

**And** capture status tracking:
- Status: `.pending` if assertion succeeded
- Status: `.assertionPending` if assertion failed (needs retry)
- Upload queue prioritizes captures with assertions
- Background task retries assertion generation for `.assertionPending` captures

**Implementation in FrameProcessor:**
```swift
class FrameProcessor {
    private let captureAssertion: CaptureAssertion

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

        // Create initial capture data without assertion
        var captureData = CaptureData(
            id: UUID(),
            jpeg: jpeg,
            depth: depth,
            metadata: metadata,
            assertion: nil,
            timestamp: Date()
        )

        // Generate assertion on background queue
        do {
            let assertion = try await captureAssertion.createAssertion(for: captureData)
            captureData.assertion = assertion

            Logger.capture.info("""
                Capture with assertion: \
                id=\(captureData.id.uuidString, privacy: .public)
                """)
        } catch {
            Logger.capture.warning("""
                Capture without assertion (will retry): \
                id=\(captureData.id.uuidString, privacy: .public), \
                error=\(error.localizedDescription, privacy: .public)
                """)
        }

        return captureData
    }
}
```

### AC3: Assertion Data Structure Validation
**Given** assertion Data returned from DCAppAttest
**When** assertion is inspected
**Then**:
- Data is CBOR-encoded (binary format)
- Data size between 500 bytes and 5KB (typical: 1-2KB)
- Data contains signature component (signed by Secure Enclave key)
- Data contains counter component (increments with each assertion)
- Data is opaque to client app (parsed by backend only)

**And** backend verification requirements:
- Assertion sent in capture upload metadata JSON
- Base64-encoded for JSON transmission
- Backend decodes and verifies with Apple's attestation API
- Backend checks counter is greater than previous counter for this device
- Backend validates signature over clientData hash

**Metadata JSON Structure:**
```json
{
  "captured_at": "2025-11-25T10:30:00.123Z",
  "device_model": "iPhone 15 Pro",
  "photo_hash": "sha256-hex-string",
  "location": { ... },
  "depth_map_dimensions": { ... },
  "assertion": "base64-encoded-assertion-data"
}
```

### AC4: Assertion Generation Performance
**Given** CaptureAssertion.createAssertion called with 4MB capture data
**When** performance is measured with XCTest.measure
**Then**:
- SHA-256 hash computation: < 30ms (median)
- DCAppAttest generateAssertion: < 50ms (median)
- Total createAssertion time: < 100ms (median)
- P95 latency: < 150ms
- No UI blocking during assertion generation

**And** performance characteristics:
- Hash computation scales linearly with data size (~7ms per MB)
- Assertion generation time relatively constant (Secure Enclave operation)
- Background queue dispatch overhead < 5ms
- Performance consistent across captures (no degradation)
- Profiled on iPhone 12 Pro (oldest target device)

**Performance Test:**
```swift
func testAssertionGenerationPerformance() async throws {
    let mockCapture = createMockCapture(jpegSize: 3_000_000, depthSize: 1_000_000)

    measure {
        let expectation = expectation(description: "Assertion generated")

        Task {
            _ = try await sut.createAssertion(for: mockCapture)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.2) // 200ms max
    }
}
```

### AC5: Assertion Retry Logic for Failed Captures
**Given** assertion generation failed during initial capture
**When** background retry task runs
**Then**:
- CaptureStore queries for captures with status `.assertionPending`
- For each capture, load JPEG and depth from CoreData
- Retry CaptureAssertion.createAssertion(for: capture)
- If successful, update CaptureData.assertion and set status to `.pending`
- If failed again, increment attemptCount
- If attemptCount > 3, set status to `.assertionFailed` (manual intervention needed)
- Log all retry attempts

**And** retry scheduling:
- Retry triggered on app foreground
- Retry triggered on network reachability change
- Retry scheduled with exponential backoff (1s, 2s, 4s)
- Max 3 retry attempts per capture
- Captures with `.assertionFailed` status shown in UI with warning

**Retry Implementation:**
```swift
class AssertionRetryService {
    private let captureStore: CaptureStore
    private let captureAssertion: CaptureAssertion

    func retryPendingAssertions() async {
        let pendingCaptures = await captureStore.fetchCaptures(status: .assertionPending)

        for capture in pendingCaptures {
            guard capture.attemptCount < 3 else {
                await captureStore.updateStatus(capture.id, to: .assertionFailed)
                continue
            }

            do {
                let assertion = try await captureAssertion.createAssertion(for: capture.toCaptureData())
                await captureStore.updateAssertion(capture.id, assertion: assertion, status: .pending)

                Logger.attestation.info("Retry succeeded: captureId=\(capture.id.uuidString, privacy: .public)")
            } catch {
                await captureStore.incrementAttemptCount(capture.id)

                Logger.attestation.warning("""
                    Retry failed: \
                    captureId=\(capture.id.uuidString, privacy: .public), \
                    attempt=\(capture.attemptCount + 1)
                    """)
            }

            // Backoff between retries
            try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(capture.attemptCount)) * 1_000_000_000))
        }
    }
}
```

### AC6: Assertion Verification Mock for Testing
**Given** unit tests need to verify assertion logic without real DCAppAttest
**When** tests run in simulator or with mock
**Then**:
- MockDCAppAttestService generates synthetic assertion data
- Assertion data matches expected structure (CBOR-like format)
- Assertion includes encoded clientData hash
- Assertion includes mock counter (increments per call)
- Mock supports error injection for testing failure paths

**And** test coverage:
- Test successful assertion generation
- Test assertion failure handling
- Test capture save with/without assertion
- Test retry logic
- Test performance within targets
- All error paths covered

**Mock Implementation:**
```swift
class MockDCAppAttestService: AppAttestServiceProtocol {
    var isSupported: Bool = true
    var shouldFailAssertion: Bool = false
    private var assertionCounter: Int = 0

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        guard isSupported else {
            throw AttestationError.unsupported
        }
        guard !shouldFailAssertion else {
            throw AttestationError.assertionFailed
        }

        assertionCounter += 1

        // Create mock CBOR-like structure
        var mockAssertion = Data()
        mockAssertion.append(keyId.data(using: .utf8)!)
        mockAssertion.append(clientDataHash)
        mockAssertion.append(Data([UInt8(assertionCounter)]))

        return mockAssertion
    }
}
```

### AC7: Keychain Key ID Retrieval
**Given** device completed registration (Story 6.2)
**When** CaptureAssertion needs key ID
**Then**:
- Key ID loaded from keychain with key `"rial.attestation.keyId"`
- Key ID is non-empty string (UUID format)
- If key ID not found, error thrown with `.attestationKeyNotFound`
- Key ID cached in memory after first load (performance optimization)
- Error logged if keychain read fails

**And** dependency on device registration:
- Device registration (Story 6.2) saves key ID to keychain
- Key ID persists across app restarts
- Key ID tied to device (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
- If device re-registers, new key ID replaces old one

### AC8: Integration with Upload Service (Story 6.11)
**Given** UploadService prepares capture for backend upload
**When** capture metadata is serialized to JSON
**Then**:
- If CaptureData.assertion is not nil, include "assertion" field in JSON
- Assertion Data encoded as Base64 string
- If CaptureData.assertion is nil, omit "assertion" field from JSON
- Backend handles both cases: captures with/without assertions
- Backend prioritizes verification for captures with assertions
- Captures without assertions flagged for manual review

**And** backend API contract:**
```swift
struct CaptureMetadataUpload: Codable {
    let capturedAt: String
    let deviceModel: String
    let photoHash: String
    let location: LocationData?
    let depthMapDimensions: DepthDimensions
    let assertion: String?  // Base64-encoded, optional

    init(from metadata: CaptureMetadata, assertion: Data?) {
        self.capturedAt = ISO8601DateFormatter().string(from: metadata.capturedAt)
        self.deviceModel = metadata.deviceModel
        self.photoHash = metadata.photoHash
        self.location = metadata.location
        self.depthMapDimensions = metadata.depthMapDimensions
        self.assertion = assertion?.base64EncodedString()
    }
}
```

---

## Tasks

### Task 1: Create CaptureAssertion Service Class (AC1)
- [ ] Create `ios/Rial/Core/Attestation/CaptureAssertion.swift`
- [ ] Import DeviceCheck, CryptoKit, Foundation frameworks
- [ ] Define AssertionError enum with all error cases
- [ ] Implement init with DeviceAttestation and KeychainService dependencies
- [ ] Implement createAssertion(for: CaptureData) async method
- [ ] Load attestation key ID from keychain
- [ ] Combine JPEG + depth data into single Data blob
- [ ] Compute SHA-256 hash using CryptoService.sha256Data
- [ ] Call DeviceAttestation.generateAssertion with key ID and hash
- [ ] Return assertion Data
- [ ] Add error handling for all failure paths
- [ ] Add Logger.attestation logging for success/failure
- [ ] Document with DocC comments

### Task 2: Integrate CaptureAssertion into FrameProcessor (AC2)
- [ ] Update `ios/Rial/Core/Capture/FrameProcessor.swift`
- [ ] Add CaptureAssertion dependency injection
- [ ] In process() method, call createAssertion after capture data creation
- [ ] Run assertion generation on background queue (Task.detached)
- [ ] Populate CaptureData.assertion if successful
- [ ] Leave CaptureData.assertion nil if failed
- [ ] Log success/failure with capture ID
- [ ] Ensure capture save proceeds regardless of assertion result
- [ ] Test integration with Story 6.5 ARCaptureSession

### Task 3: Update CaptureData Model (AC3)
- [ ] Update `ios/Rial/Models/CaptureData.swift`
- [ ] Ensure CaptureData.assertion field is `Data?` (optional)
- [ ] Add computed property for base64EncodedAssertion
- [ ] Document assertion field purpose
- [ ] Verify CaptureData conforms to Codable
- [ ] Test serialization with/without assertion

**Model Update:**
```swift
struct CaptureData: Codable {
    let id: UUID
    let jpeg: Data
    let depth: Data
    let metadata: CaptureMetadata
    var assertion: Data?          // DCAppAttest assertion (optional)
    let timestamp: Date

    var base64EncodedAssertion: String? {
        assertion?.base64EncodedString()
    }
}
```

### Task 4: Add Assertion Field to CoreData (AC2)
- [ ] Update `ios/Rial/Models/RialModel.xcdatamodeld`
- [ ] Add `assertion` attribute to CaptureEntity
- [ ] Type: Binary Data (Transformable)
- [ ] Optional: Yes
- [ ] Allows External Storage: Yes (for large assertions)
- [ ] Add `assertionStatus` attribute: String (enum)
- [ ] Values: "none", "generated", "pending", "failed"
- [ ] Create lightweight migration mapping
- [ ] Test migration from previous schema

### Task 5: Update CaptureStore for Assertion Status (AC5)
- [ ] Update `ios/Rial/Core/Storage/CaptureStore.swift`
- [ ] Add fetchCaptures(status: AssertionStatus) query method
- [ ] Add updateAssertion(_:assertion:status:) method
- [ ] Add incrementAttemptCount(_:) method
- [ ] Add query for captures needing assertion retry
- [ ] Test CoreData queries with various statuses

**Assertion Status Enum:**
```swift
enum AssertionStatus: String, Codable {
    case none = "none"              // Capture saved without assertion attempt
    case generated = "generated"    // Assertion successfully generated
    case pending = "pending"        // Assertion generation failed, retry needed
    case failed = "failed"          // Retry limit exceeded
}
```

### Task 6: Create AssertionRetryService (AC5)
- [ ] Create `ios/Rial/Core/Attestation/AssertionRetryService.swift`
- [ ] Add CaptureStore and CaptureAssertion dependencies
- [ ] Implement retryPendingAssertions() async method
- [ ] Query captures with `.pending` status
- [ ] Retry assertion generation for each
- [ ] Update CoreData on success/failure
- [ ] Implement exponential backoff between retries
- [ ] Implement max retry limit (3 attempts)
- [ ] Log all retry attempts
- [ ] Document with DocC comments

### Task 7: Schedule Assertion Retry Background Task (AC5)
- [ ] Update `ios/Rial/App/AppDelegate.swift`
- [ ] Register background task for assertion retry
- [ ] Task identifier: `"app.rial.assertion-retry"`
- [ ] Schedule task on app foreground
- [ ] Schedule task on network reachability change
- [ ] Call AssertionRetryService.retryPendingAssertions()
- [ ] Test background task execution

**Background Task Implementation:**
```swift
import BackgroundTasks

extension AppDelegate {
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "app.rial.assertion-retry",
            using: nil
        ) { task in
            self.handleAssertionRetry(task: task as! BGProcessingTask)
        }
    }

    func handleAssertionRetry(task: BGProcessingTask) {
        let retryService = AssertionRetryService(
            captureStore: captureStore,
            captureAssertion: captureAssertion
        )

        Task {
            await retryService.retryPendingAssertions()
            task.setTaskCompleted(success: true)
        }
    }

    func scheduleAssertionRetry() {
        let request = BGProcessingTaskRequest(identifier: "app.rial.assertion-retry")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        try? BGTaskScheduler.shared.submit(request)
    }
}
```

### Task 8: Performance Testing (AC4)
- [ ] Create `ios/RialTests/Attestation/CaptureAssertionPerformanceTests.swift`
- [ ] Use XCTest.measure for performance benchmarks
- [ ] Test SHA-256 hash computation time (target: < 30ms)
- [ ] Test DCAppAttest generateAssertion time (target: < 50ms)
- [ ] Test total createAssertion time (target: < 100ms)
- [ ] Test with various data sizes (1MB, 4MB, 8MB)
- [ ] Profile on iPhone 12 Pro (oldest target)
- [ ] Document performance characteristics

**Performance Test Implementation:**
```swift
import XCTest
@testable import Rial

class CaptureAssertionPerformanceTests: XCTestCase {
    var sut: CaptureAssertion!

    override func setUp() async throws {
        // Setup with real or mock dependencies
    }

    func testHashComputationPerformance() {
        let jpeg = Data(repeating: 0x42, count: 3_000_000) // 3MB
        let depth = Data(repeating: 0x43, count: 1_000_000) // 1MB
        var combined = Data()

        measure {
            combined = Data()
            combined.append(jpeg)
            combined.append(depth)
            _ = CryptoService.sha256Data(combined)
        }

        // Should complete in < 30ms
    }

    func testAssertionGenerationPerformance() async throws {
        let capture = createMockCapture()

        measure {
            let expectation = expectation(description: "Assertion")
            Task {
                _ = try await sut.createAssertion(for: capture)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.15) // 150ms P95
        }
    }
}
```

### Task 9: Unit Tests (AC1, AC6)
- [ ] Create `ios/RialTests/Attestation/CaptureAssertionTests.swift`
- [ ] Test successful assertion generation
- [ ] Test assertion with real CryptoService hash
- [ ] Test error handling: key ID not found
- [ ] Test error handling: DCAppAttest failure
- [ ] Test error handling: hash computation failure
- [ ] Test assertion data is non-empty
- [ ] Use MockDCAppAttestService for testability
- [ ] Test assertion counter increments
- [ ] Achieve 90%+ code coverage

**Unit Test Structure:**
```swift
class CaptureAssertionTests: XCTestCase {
    var sut: CaptureAssertion!
    var mockAttestation: MockDeviceAttestation!
    var mockKeychain: MockKeychainService!

    override func setUp() {
        mockAttestation = MockDeviceAttestation()
        mockKeychain = MockKeychainService()
        mockKeychain.store["rial.attestation.keyId"] = "test-key-id".data(using: .utf8)

        sut = CaptureAssertion(attestation: mockAttestation, keychain: mockKeychain)
    }

    func testCreateAssertionSuccess() async throws {
        let capture = createMockCapture()

        let assertion = try await sut.createAssertion(for: capture)

        XCTAssertFalse(assertion.isEmpty)
        XCTAssertGreaterThan(assertion.count, 100)
    }

    func testCreateAssertionThrowsWhenKeyNotFound() async {
        mockKeychain.store.removeAll()

        do {
            _ = try await sut.createAssertion(for: createMockCapture())
            XCTFail("Expected error")
        } catch CaptureAssertion.AssertionError.attestationKeyNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testCreateAssertionThrowsWhenDCAppAttestFails() async {
        mockAttestation.shouldFailAssertion = true

        do {
            _ = try await sut.createAssertion(for: createMockCapture())
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }
}
```

### Task 10: Integration Tests with FrameProcessor (AC2)
- [ ] Create `ios/RialTests/Capture/FrameProcessorAssertionTests.swift`
- [ ] Test FrameProcessor includes assertion in successful case
- [ ] Test FrameProcessor handles assertion failure gracefully
- [ ] Test capture saved to CoreData with assertion
- [ ] Test capture saved to CoreData without assertion (failure case)
- [ ] Test assertion status tracking
- [ ] Verify no main thread blocking

### Task 11: Upload Metadata Serialization (AC8)
- [ ] Update `ios/Rial/Core/Networking/APIClient.swift`
- [ ] Create CaptureMetadataUpload struct with assertion field
- [ ] Implement init(from:assertion:) converting CaptureMetadata + assertion Data
- [ ] Base64-encode assertion for JSON
- [ ] Test JSON serialization with/without assertion
- [ ] Verify backend API contract compatibility

### Task 12: UI Status Indicators for Failed Assertions (AC5)
- [ ] Update `ios/Rial/Features/History/HistoryView.swift`
- [ ] Add badge for captures with `.assertionFailed` status
- [ ] Badge color: yellow/orange for warning
- [ ] Badge icon: SF Symbol `exclamationmark.triangle`
- [ ] Add retry button for failed assertions
- [ ] Test UI updates when retry succeeds

### Task 13: Documentation and Code Comments (All ACs)
- [ ] Add DocC documentation to CaptureAssertion class
- [ ] Add DocC documentation to AssertionRetryService
- [ ] Document assertion flow in inline comments
- [ ] Update README with assertion feature description
- [ ] Document performance characteristics
- [ ] Document error handling strategy
- [ ] Add code examples for common usage

### Task 14: Integration Testing with Backend (AC3, AC8)
- [ ] Test end-to-end: capture → assertion → upload → backend verification
- [ ] Verify backend accepts assertion format
- [ ] Verify backend validates assertion signature
- [ ] Test backend rejects replayed assertions (counter check)
- [ ] Test backend handles captures without assertions
- [ ] Test backend error responses for invalid assertions
- [ ] Document backend verification requirements

---

## Technical Implementation Details

### DCAppAttest Assertion Format

```
Assertion Data (CBOR-encoded)
├── authenticatorData (32+ bytes)
│   ├── RP ID hash (32 bytes)
│   ├── Flags (1 byte)
│   └── Counter (4 bytes) - Increments with each assertion
├── clientDataHash (32 bytes) - SHA-256 of capture data
└── signature (64+ bytes) - Secure Enclave signature (ECDSA P-256)
```

### Hash Computation Details

```swift
// Combine JPEG + depth into single data blob
var combinedData = Data()
combinedData.append(capture.jpeg)      // ~3MB
combinedData.append(capture.depth)     // ~1MB compressed
// Total: ~4MB

// Compute SHA-256 (hardware-accelerated)
let hash = SHA256.hash(data: combinedData)  // ~30ms
let hashData = Data(hash)                    // 32 bytes
```

### Assertion Counter Security

The assertion counter prevents replay attacks:
1. **Counter Initialization**: Set to 0 when key generated
2. **Counter Increment**: Increases by 1 with each assertion
3. **Backend Tracking**: Backend stores last seen counter per device
4. **Verification**: Backend rejects assertions with counter ≤ last seen
5. **Reset**: Only possible by re-generating attestation key (re-registration)

### Retry Strategy

```
Attempt 1: Immediate (during capture)
    ↓ (fails)
Attempt 2: 1 second delay (app foreground)
    ↓ (fails)
Attempt 3: 2 seconds delay (network change)
    ↓ (fails)
Attempt 4: 4 seconds delay (background task)
    ↓ (fails)
Status: .assertionFailed (manual intervention)
```

### Performance Optimization

1. **Hash Computation**: Use CryptoKit's hardware-accelerated SHA-256
2. **Background Queue**: Run assertion on background queue to avoid UI blocking
3. **Memory Management**: Release combined data immediately after hashing
4. **Keychain Caching**: Cache key ID in memory after first load
5. **Batch Retry**: Process multiple pending assertions in single background task

---

## Dependencies

### Prerequisites
- **Story 6.2**: DCAppAttest Direct Integration (provides DeviceAttestation service and key ID)
- **Story 6.3**: CryptoKit Integration (provides CryptoService.sha256Data)
- **Story 6.4**: Keychain Services Integration (provides KeychainService for key ID storage)
- **Story 6.6**: Frame Processing Pipeline (provides FrameProcessor to integrate assertion)

### Blocks
- **Story 6.9**: CoreData Capture Queue (uses assertion data in CoreData entity)
- **Story 6.11**: URLSession Background Uploads (uploads assertion in metadata)

### External Dependencies
- **DeviceCheck.framework**: DCAppAttest assertion generation
- **CryptoKit.framework**: SHA-256 hash computation
- **Security.framework**: Keychain access for key ID
- **Foundation.framework**: Data, async/await
- **BackgroundTasks.framework**: Retry scheduling

---

## Testing Strategy

### Unit Tests (Simulator Compatible)
Tests that can run in Xcode simulator:
- CaptureAssertion logic with MockDCAppAttestService
- Hash computation correctness
- Error handling paths
- Keychain key ID retrieval
- Data structure validation
- Retry logic
- Status transitions

### Physical Device Tests (Required)
Tests requiring iPhone Pro with Secure Enclave:
- Real DCAppAttest assertion generation
- Assertion data format validation
- Performance benchmarks (< 50ms target)
- Integration with real Secure Enclave
- Counter increment verification
- Backend verification end-to-end

### Performance Tests
Benchmarks on iPhone 12 Pro:
- SHA-256 hash: < 30ms for 4MB data
- generateAssertion: < 50ms
- Total createAssertion: < 100ms
- P95 latency: < 150ms
- No UI blocking

### Integration Tests
- FrameProcessor includes assertion in capture flow
- CoreData saves captures with/without assertions
- Upload service includes assertion in metadata
- Backend verification succeeds for valid assertions
- Retry service processes pending assertions

---

## Definition of Done

- [ ] All acceptance criteria verified and passing
- [ ] All tasks completed
- [ ] CaptureAssertion.swift implemented and documented
- [ ] AssertionRetryService.swift implemented
- [ ] FrameProcessor integration completed
- [ ] CaptureData model updated with assertion field
- [ ] CoreData schema updated with assertion attributes
- [ ] Background task registered for retry
- [ ] Unit tests achieve 90%+ coverage
- [ ] Performance tests confirm:
  - [ ] Hash computation < 30ms
  - [ ] Assertion generation < 50ms
  - [ ] Total overhead < 100ms
  - [ ] No main thread blocking
- [ ] Physical device testing confirms:
  - [ ] Real DCAppAttest assertions generated
  - [ ] Backend verification succeeds
  - [ ] Counter increments correctly
  - [ ] Retry logic works
- [ ] Integration with Stories 6.2, 6.3, 6.4, 6.6 tested
- [ ] Upload metadata includes base64-encoded assertion
- [ ] UI shows assertion status in history view
- [ ] Error handling tested and graceful
- [ ] Documentation complete with examples
- [ ] Code reviewed and approved
- [ ] Code committed to feature branch

---

## FR Coverage

| Functional Requirement | Implementation |
|----------------------|----------------|
| **FR10**: Capture attestation signature | Per-capture DCAppAttest assertion generated with SHA-256 hash of JPEG+depth, signed by Secure Enclave |

---

## References

### Source Documents
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#Story-6.8-Per-Capture-Assertion-Signing]
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#API-Integration-Points]
- [User Request: Create story for 6-8-per-capture-assertion-signing]

### Apple Documentation
- [DCAppAttestService](https://developer.apple.com/documentation/devicecheck/dcappattestservice)
- [generateAssertion(_:clientDataHash:)](https://developer.apple.com/documentation/devicecheck/dcappattestservice/3573911-generateassertion)
- [Validating Apps That Connect to Your Server](https://developer.apple.com/documentation/devicecheck/validating_apps_that_connect_to_your_server)
- [CryptoKit SHA256](https://developer.apple.com/documentation/cryptokit/sha256)
- [Background Tasks Framework](https://developer.apple.com/documentation/backgroundtasks)

### Related Stories
- Story 6.2: DCAppAttest Direct Integration - Provides DeviceAttestation service
- Story 6.3: CryptoKit Integration - Provides SHA-256 hashing
- Story 6.4: Keychain Services - Stores attestation key ID
- Story 6.6: Frame Processing Pipeline - Integrates assertion generation

---

## Notes

### Important Implementation Considerations

1. **Assertion vs Attestation**
   - **Attestation**: One-time device verification during registration (Story 6.2)
   - **Assertion**: Per-capture proof binding capture data to device
   - Assertion requires prior attestation to be valid
   - Assertion counter prevents replay attacks

2. **Performance Trade-offs**
   - Hash computation is CPU-bound (~30ms for 4MB)
   - Assertion generation is I/O-bound (Secure Enclave call ~50ms)
   - Combined overhead ~100ms acceptable for capture flow
   - Background queue prevents UI blocking

3. **Failure Resilience**
   - Captures proceed even if assertion fails
   - Assertion generation retried in background
   - Backend can process captures without assertions (lower confidence)
   - Manual intervention required after 3 failed retry attempts

4. **Security Benefits**
   - Binds capture data to device via cryptographic signature
   - Counter prevents reusing old assertions for different captures
   - Secure Enclave signature impossible to forge
   - Backend can trust capture originated from verified device

5. **Backend Verification Flow**
   ```
   Backend Receives Capture
       ↓
   Extract assertion from metadata
       ↓
   Decode CBOR assertion structure
       ↓
   Verify signature against device public key
       ↓
   Check counter > last seen counter for device
       ↓
   Verify clientDataHash matches uploaded photo+depth hash
       ↓
   Call Apple attestation API for validation
       ↓
   Update device counter
       ↓
   Mark capture as verified
   ```

### Debugging Tips

**Common Assertion Issues:**

| Issue | Cause | Solution |
|-------|-------|----------|
| Assertion generation fails | Key ID not in keychain | Ensure device registration completed |
| Assertion too slow (> 100ms) | Main thread blocking | Move to background queue |
| Backend rejects assertion | Counter out of sync | Device re-registration may be needed |
| Assertion nil in upload | Generation failed silently | Check logs for error messages |
| Retry limit exceeded | Persistent DCAppAttest failure | Check device Secure Enclave health |

**Logging Strategy:**
- Log all assertion generation attempts (success/failure)
- Log assertion size and generation time
- Log retry attempts with capture ID
- Log backend verification results
- Use privacy-aware logging (no sensitive data)

### Testing Notes

**Simulator Limitations:**
- DCAppAttest not available (no Secure Enclave)
- Must use MockDCAppAttestService for unit tests
- Cannot test real assertion generation
- Cannot measure real performance

**Physical Device Requirements:**
- iPhone Pro (12 Pro or later)
- iOS 15.0+
- Device must be registered (Story 6.2)
- Secure Enclave functional
- Network access for backend verification tests

**Performance Profiling:**
- Use Time Profiler instrument
- Measure SHA-256 hash computation time
- Measure DCAppAttest call time
- Monitor background queue dispatch overhead
- Test on iPhone 12 Pro (worst-case performance)

### Migration from React Native

This native implementation replaces:
- Expo SecureStore for attestation data
- React Native bridge for assertion generation
- JavaScript-based hash computation
- Promise-based async patterns

Benefits of native implementation:
- **Direct Secure Enclave access**: No bridge overhead
- **Hardware-accelerated hashing**: CryptoKit faster than JS
- **Better error handling**: Swift structured concurrency
- **Type safety**: Compile-time guarantees
- **Performance**: 2-3x faster than RN equivalent

---

## Dev Agent Record

### Context Reference

Story Context XML: `docs/sprint-artifacts/story-contexts/6-8-per-capture-assertion-signing-context.xml`

### Agent Model Used

Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Implementation Notes

_To be filled during implementation_

### Completion Notes

_To be filled when story is complete_

### File List

**Created:**
- `ios/Rial/Core/Attestation/CaptureAssertion.swift` - Per-capture assertion service
- `ios/Rial/Core/Attestation/AssertionRetryService.swift` - Background retry service
- `ios/RialTests/Attestation/CaptureAssertionTests.swift` - Unit tests for assertion generation
- `ios/RialTests/Attestation/CaptureAssertionPerformanceTests.swift` - Performance benchmarks
- `ios/RialTests/Capture/FrameProcessorAssertionTests.swift` - Integration tests

**Modified:**
- `ios/Rial/Models/CaptureData.swift` - Added assertion field and base64 encoding
- `ios/Rial/Models/RialModel.xcdatamodeld` - Added assertion attributes to CaptureEntity
- `ios/Rial/Core/Capture/FrameProcessor.swift` - Integrated assertion generation
- `ios/Rial/Core/Storage/CaptureStore.swift` - Added assertion status queries
- `ios/Rial/Core/Networking/APIClient.swift` - Added assertion to upload metadata
- `ios/Rial/App/AppDelegate.swift` - Registered background task for retry
- `ios/Rial/Features/History/HistoryView.swift` - Added assertion status indicators

### Code Review Result

_To be filled after code review_
