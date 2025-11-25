# Story 6.6: Frame Processing Pipeline

**Story Key:** 6-6-frame-processing-pipeline
**Epic:** 6 - Native Swift Implementation
**Status:** Done
**Created:** 2025-11-25

---

## User Story

As a **photographer using RealityCam**,
I want **captured ARFrames automatically processed into upload-ready format**,
So that **photo, depth map, and metadata are prepared in under 200ms without blocking the UI**.

## Story Context

This story implements the frame processing pipeline that converts ARKit's ARFrame (containing RGB photo and LiDAR depth) into the structured CaptureData format required for upload. The pipeline performs JPEG conversion, depth map compression, SHA-256 hashing, metadata collection, and runs entirely on background queues to maintain smooth UI performance.

FrameProcessor bridges the gap between ARKit's native frame format and the backend API's requirements, ensuring data is properly formatted, compressed, and hashed before storage or upload.

### Key Processing Steps

1. **RGB Conversion**: CVPixelBuffer (YCbCr420) → JPEG with quality settings
2. **Depth Compression**: CVPixelBuffer Float32 depth map → gzip compressed binary
3. **Photo Hashing**: SHA-256 digest of JPEG data (for backend verification)
4. **Metadata Assembly**: Timestamp, device model, GPS coordinates, depth dimensions
5. **CaptureData Construction**: Unified structure ready for CoreData persistence

### Performance Targets

| Operation | Target | Rationale |
|-----------|--------|-----------|
| Total processing time | < 200ms | User expects immediate preview transition |
| JPEG conversion | < 100ms | Largest data transformation |
| Depth compression | < 50ms | Gzip compression of Float32 array |
| SHA-256 hash (5MB) | < 30ms | Hardware-accelerated hashing |
| Background execution | Required | UI must remain responsive during capture |

---

## Acceptance Criteria

### AC1: JPEG Conversion from CVPixelBuffer
**Given** an ARFrame with capturedImage (CVPixelBuffer in YCbCr420 format)
**When** FrameProcessor processes the frame
**Then**:
- CVPixelBuffer is converted to JPEG data
- JPEG quality set to 0.85 (85%) for balance of quality and size
- Typical JPEG size: 2-4MB for 12MP photo
- Conversion handles all ARKit pixel formats (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
- Original aspect ratio preserved
- EXIF orientation tag set correctly
- No memory leaks (CVPixelBuffer properly released)

**And** JPEG data is:
- Valid (can be loaded by UIImage)
- Compressed (smaller than raw pixel buffer)
- Ready for multipart upload
- Hash-ready (binary data suitable for SHA-256)

### AC2: Depth Map Compression
**Given** an ARFrame with sceneDepth.depthMap (CVPixelBuffer with Float32 values)
**When** depth map is compressed
**Then**:
- CVPixelBuffer locked for read access
- Raw Float32 data extracted (width × height × 4 bytes)
- Data compressed using zlib compression
- Compressed depth map size ≤ 1MB (typical: 256×192×4 = 196KB raw → ~50-100KB compressed)
- CVPixelBuffer unlocked after extraction
- Original dimensions preserved in metadata
- Compression is lossless (depth values exactly preserved)

**And** compressed format:
- Compatible with backend decompress expectations
- Uses standard zlib/gzip format
- Can be decompressed with standard tools
- Includes depth dimensions in metadata for reconstruction

### AC3: Processing Completes in Under 200ms
**Given** a captured ARFrame on iPhone Pro (12 Pro minimum)
**When** FrameProcessor.process() executes
**Then**:
- Total processing time measured via Instruments Time Profiler
- P95 latency < 200ms (95th percentile)
- P50 latency < 150ms (median)
- No frame processing exceeds 500ms
- Processing happens on background queue (not main queue)
- UI remains responsive during processing

**And** performance breakdown:
- JPEG conversion: 60-100ms
- Depth compression: 20-50ms
- SHA-256 hash: 10-30ms
- Metadata assembly: < 5ms
- CaptureData construction: < 5ms

### AC4: GPS Metadata Inclusion
**Given** location services are enabled and authorized
**When** processing a frame with location data
**Then**:
- GPS coordinates included in CaptureMetadata
- LocationData contains:
  - `latitude: Double` (decimal degrees)
  - `longitude: Double` (decimal degrees)
  - `altitude: Double?` (meters above sea level, optional)
  - `accuracy: Double` (horizontal accuracy in meters)
- Timestamp matches ARFrame capture time
- Location is fresh (captured within 5 seconds of frame)

**And** when location services are disabled or denied:
- Location field is `nil` in CaptureMetadata
- Processing continues successfully (location optional)
- No errors thrown for missing location
- User can opt-out of location tracking

### AC5: Background Queue Execution
**Given** FrameProcessor needs to avoid blocking the UI
**When** process() is called
**Then**:
- Processing dispatches to background queue
- Uses `async/await` for structured concurrency
- Main queue never blocked during processing
- Camera preview rendering continues at 60fps
- User can interact with UI during processing

**And** concurrency guarantees:
- Multiple frame processing requests queue properly
- No race conditions on shared resources
- CVPixelBuffer access properly synchronized
- Memory pressure managed (old frames released)

### AC6: SHA-256 Photo Hash
**Given** JPEG photo data is generated
**When** computing the photo hash
**Then**:
- CryptoService.sha256() used (Story 6.3)
- Hash computed on JPEG binary data
- Result is hex-encoded string (64 characters)
- Hash included in CaptureMetadata
- Hash computation uses hardware acceleration
- Same photo produces identical hash (deterministic)

**And** hash is used for:
- Backend verification of photo integrity
- Duplicate detection
- Tamper detection
- Per-capture attestation signing (Story 6.8)

### AC7: CaptureData Structure Output
**Given** all processing steps complete successfully
**When** FrameProcessor.process() returns
**Then** CaptureData contains:
- `id: UUID` - Unique capture identifier
- `jpeg: Data` - Compressed JPEG photo (2-4MB)
- `depth: Data` - Compressed depth map (~50-100KB)
- `metadata: CaptureMetadata` - Complete metadata structure
- `assertion: Data?` - Nil at this stage (added by Story 6.8)
- `timestamp: Date` - Capture instant

**And** CaptureMetadata contains:
- `capturedAt: Date` - ARFrame timestamp
- `deviceModel: String` - "iPhone 15 Pro" (UIDevice.current.model)
- `photoHash: String` - SHA-256 hex digest
- `location: LocationData?` - GPS coordinates (optional)
- `depthMapDimensions: DepthDimensions` - Width and height

### AC8: Error Handling
**Given** frame processing can encounter errors
**When** errors occur
**Then** appropriate CaptureError thrown:
- `.noDepthData` - ARFrame missing sceneDepth
- `.jpegConversionFailed` - CVPixelBuffer to JPEG failed
- `.depthCompressionFailed` - Zlib compression failed
- `.processingTimeout` - Processing exceeded 1 second (fallback)

**And** error handling:
- Errors are logged with details
- CVPixelBuffer resources released even on error
- Partial CaptureData not saved
- User notified of processing failure
- Retry possible (capture button remains enabled)

---

## Tasks

### Task 1: Create FrameProcessor Core Class (AC7)
- [ ] Create `ios/Rial/Core/Capture/FrameProcessor.swift`
- [ ] Import ARKit, CoreLocation, Compression frameworks
- [ ] Define class with async processing method
- [ ] Add background queue for processing
- [ ] Import CryptoService for SHA-256 hashing
- [ ] Document with DocC comments
- [ ] Add logging with os.log Logger

### Task 2: Implement JPEG Conversion (AC1)
- [ ] Create `convertToJPEG(_ pixelBuffer: CVPixelBuffer) async throws -> Data`
- [ ] Lock CVPixelBuffer for read access
- [ ] Create CIImage from CVPixelBuffer
- [ ] Use CIContext to render JPEG with quality 0.85
- [ ] Unlock CVPixelBuffer after conversion
- [ ] Validate JPEG data size (should be 2-4MB for typical photo)
- [ ] Handle conversion failures with proper error
- [ ] Test memory usage with Instruments Allocations

**JPEG Conversion Implementation:**
```swift
private func convertToJPEG(_ pixelBuffer: CVPixelBuffer) async throws -> Data {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw CaptureError.jpegConversionFailed
    }

    let options: [CIImageRepresentationOption: Any] = [
        .jpegCompressionQuality: 0.85
    ]

    guard let jpegData = context.jpegRepresentation(
        of: ciImage,
        colorSpace: colorSpace,
        options: options
    ) else {
        throw CaptureError.jpegConversionFailed
    }

    return jpegData
}
```

### Task 3: Implement Depth Map Compression (AC2)
- [ ] Create `compressDepth(_ buffer: CVPixelBuffer?) throws -> Data`
- [ ] Verify buffer is not nil (throw `.noDepthData` if missing)
- [ ] Lock CVPixelBuffer for read-only access
- [ ] Extract raw Float32 data from base address
- [ ] Calculate buffer size: width × height × 4 bytes
- [ ] Convert to Data object
- [ ] Compress using zlib compression algorithm
- [ ] Unlock CVPixelBuffer in defer block
- [ ] Validate compressed size ≤ 1MB
- [ ] Log compression ratio for monitoring

**Depth Compression Implementation:**
```swift
private func compressDepth(_ buffer: CVPixelBuffer?) throws -> Data {
    guard let buffer = buffer else {
        throw CaptureError.noDepthData
    }

    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let baseAddress = CVPixelBufferGetBaseAddress(buffer)!

    let dataSize = width * height * MemoryLayout<Float>.size
    let data = Data(bytes: baseAddress, count: dataSize)

    // Compress using zlib
    let compressedData = try (data as NSData).compressed(using: .zlib) as Data

    Self.logger.debug("Depth compressed: \(data.count) bytes → \(compressedData.count) bytes")

    return compressedData
}
```

### Task 4: Implement Metadata Assembly (AC4, AC6)
- [ ] Create `buildMetadata(frame:, jpeg:, depth:, location:) -> CaptureMetadata`
- [ ] Extract timestamp from ARFrame
- [ ] Get device model from UIDevice.current.model
- [ ] Compute SHA-256 hash of JPEG using CryptoService
- [ ] Convert CLLocation to LocationData (if provided)
- [ ] Extract depth dimensions from CVPixelBuffer
- [ ] Construct CaptureMetadata with all fields
- [ ] Validate all required fields present

**Metadata Assembly Implementation:**
```swift
private func buildMetadata(
    frame: ARFrame,
    jpeg: Data,
    depth: CVPixelBuffer,
    location: CLLocation?
) -> CaptureMetadata {
    let photoHash = CryptoService.sha256(jpeg)

    let locationData = location.map { loc in
        LocationData(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            altitude: loc.altitude,
            accuracy: loc.horizontalAccuracy
        )
    }

    let depthDimensions = DepthDimensions(
        width: CVPixelBufferGetWidth(depth),
        height: CVPixelBufferGetHeight(depth)
    )

    return CaptureMetadata(
        capturedAt: Date(timeIntervalSince1970: frame.timestamp),
        deviceModel: UIDevice.current.model,
        photoHash: photoHash,
        location: locationData,
        depthMapDimensions: depthDimensions
    )
}
```

### Task 5: Implement Main Processing Pipeline (AC3, AC5, AC7)
- [ ] Create `process(_ frame: ARFrame, location: CLLocation?) async throws -> CaptureData`
- [ ] Dispatch to background queue using `async`
- [ ] Call convertToJPEG() for RGB conversion
- [ ] Call compressDepth() for depth compression
- [ ] Call buildMetadata() for metadata assembly
- [ ] Generate UUID for capture
- [ ] Construct CaptureData with all components
- [ ] Measure total processing time
- [ ] Log performance metrics
- [ ] Return CaptureData ready for persistence

**Main Pipeline Implementation:**
```swift
func process(_ frame: ARFrame, location: CLLocation?) async throws -> CaptureData {
    let startTime = Date()

    // Convert RGB to JPEG (background queue via async)
    let jpeg = try await convertToJPEG(frame.capturedImage)

    // Extract and compress depth
    let depth = try compressDepth(frame.sceneDepth?.depthMap)

    // Build metadata
    let metadata = buildMetadata(
        frame: frame,
        jpeg: jpeg,
        depth: frame.sceneDepth!.depthMap,
        location: location
    )

    let processingTime = Date().timeIntervalSince(startTime) * 1000
    Self.logger.info("Frame processed in \(processingTime, format: .fixed(precision: 1))ms")

    return CaptureData(
        id: UUID(),
        jpeg: jpeg,
        depth: depth,
        metadata: metadata,
        assertion: nil,
        timestamp: Date()
    )
}
```

### Task 6: Create CaptureData Model (AC7)
- [ ] Create `ios/Rial/Models/CaptureData.swift`
- [ ] Define CaptureData struct conforming to Codable
- [ ] Define CaptureMetadata struct conforming to Codable
- [ ] Define LocationData struct conforming to Codable
- [ ] Define DepthDimensions struct conforming to Codable
- [ ] Add DocC documentation for all types
- [ ] Add convenience initializers if needed

**CaptureData Models:**
```swift
struct CaptureData: Codable {
    let id: UUID
    let jpeg: Data
    let depth: Data                    // Gzipped Float32 array
    let metadata: CaptureMetadata
    let assertion: Data?               // Added later by Story 6.8
    let timestamp: Date
}

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

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.accuracy = location.horizontalAccuracy
    }
}

struct DepthDimensions: Codable {
    let width: Int
    let height: Int
}
```

### Task 7: Error Handling (AC8)
- [ ] Update CaptureError enum with new cases:
  - `.noDepthData` - ARFrame missing sceneDepth
  - `.jpegConversionFailed` - CVPixelBuffer to JPEG failed
  - `.depthCompressionFailed` - Compression failed
  - `.processingTimeout` - Exceeded time limit
- [ ] Implement LocalizedError for user-friendly messages
- [ ] Add logging for all error scenarios
- [ ] Ensure CVPixelBuffer resources released on error
- [ ] Test all error paths

### Task 8: Performance Optimization (AC3)
- [ ] Ensure JPEG conversion happens on background queue
- [ ] Reuse CIContext across multiple conversions
- [ ] Use autoreleasepool for memory-intensive operations
- [ ] Profile with Instruments Time Profiler
- [ ] Verify P95 latency < 200ms on iPhone 12 Pro
- [ ] Optimize compression buffer sizes if needed
- [ ] Document performance characteristics

### Task 9: Unit Tests (AC1-AC8)
- [ ] Create `ios/RialTests/Capture/FrameProcessorTests.swift`
- [ ] Test JPEG conversion with mock ARFrame
- [ ] Test depth compression with mock CVPixelBuffer
- [ ] Test metadata assembly with all fields
- [ ] Test metadata assembly with missing location
- [ ] Test processing pipeline end-to-end
- [ ] Test error handling (no depth data, conversion failures)
- [ ] Test performance with large frames
- [ ] Verify background queue execution
- [ ] Achieve 90%+ code coverage

**Note**: Full ARFrame testing requires physical device with LiDAR. Unit tests can use mock CVPixelBuffers for initial testing.

### Task 10: Integration with ARCaptureSession (AC5)
- [ ] Test integration with Story 6.5 (ARCaptureSession)
- [ ] Verify ARFrame.capturedImage compatibility
- [ ] Verify ARFrame.sceneDepth.depthMap compatibility
- [ ] Test full capture flow: ARFrame → process() → CaptureData
- [ ] Verify UI remains responsive during processing
- [ ] Test on physical device with real LiDAR data
- [ ] Document usage example with ARCaptureSession

---

## Technical Implementation Details

### FrameProcessor.swift Structure

```swift
import Foundation
import ARKit
import CoreLocation
import Compression
import CoreImage
import os.log

/// Processes ARFrames into upload-ready CaptureData
class FrameProcessor {
    private static let logger = Logger(subsystem: "app.rial", category: "capture")

    // Reuse CIContext for better performance
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    // MARK: - Public API

    /// Process ARFrame into CaptureData ready for upload
    /// - Parameters:
    ///   - frame: ARFrame with RGB photo and LiDAR depth
    ///   - location: Optional GPS location from CoreLocation
    /// - Returns: CaptureData with JPEG, compressed depth, and metadata
    /// - Throws: CaptureError if processing fails
    func process(_ frame: ARFrame, location: CLLocation?) async throws -> CaptureData {
        let startTime = Date()

        // Convert RGB to JPEG (background queue via async)
        let jpeg = try await convertToJPEG(frame.capturedImage)

        // Extract and compress depth
        let depth = try compressDepth(frame.sceneDepth?.depthMap)

        // Build metadata
        let metadata = buildMetadata(
            frame: frame,
            jpeg: jpeg,
            depth: frame.sceneDepth!.depthMap,
            location: location
        )

        let processingTime = Date().timeIntervalSince(startTime) * 1000
        Self.logger.info("Frame processed in \(processingTime, format: .fixed(precision: 1))ms")

        // Enforce performance requirement
        if processingTime > 1000 {
            Self.logger.warning("Processing exceeded 1 second: \(processingTime)ms")
        }

        return CaptureData(
            id: UUID(),
            jpeg: jpeg,
            depth: depth,
            metadata: metadata,
            assertion: nil,
            timestamp: Date()
        )
    }

    // MARK: - JPEG Conversion

    private func convertToJPEG(_ pixelBuffer: CVPixelBuffer) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            autoreleasepool {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

                guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                    continuation.resume(throwing: CaptureError.jpegConversionFailed)
                    return
                }

                let options: [CIImageRepresentationOption: Any] = [
                    .jpegCompressionQuality: 0.85
                ]

                guard let jpegData = ciContext.jpegRepresentation(
                    of: ciImage,
                    colorSpace: colorSpace,
                    options: options
                ) else {
                    Self.logger.error("JPEG conversion failed")
                    continuation.resume(throwing: CaptureError.jpegConversionFailed)
                    return
                }

                Self.logger.debug("JPEG size: \(jpegData.count / 1024 / 1024)MB")
                continuation.resume(returning: jpegData)
            }
        }
    }

    // MARK: - Depth Compression

    private func compressDepth(_ buffer: CVPixelBuffer?) throws -> Data {
        guard let buffer = buffer else {
            Self.logger.error("No depth data in ARFrame")
            throw CaptureError.noDepthData
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!

        let dataSize = width * height * MemoryLayout<Float>.size
        let data = Data(bytes: baseAddress, count: dataSize)

        // Compress using zlib
        guard let compressedData = try? (data as NSData).compressed(using: .zlib) as Data else {
            Self.logger.error("Depth compression failed")
            throw CaptureError.depthCompressionFailed
        }

        let compressionRatio = Double(data.count) / Double(compressedData.count)
        Self.logger.debug("Depth compressed: \(data.count) → \(compressedData.count) bytes (ratio: \(compressionRatio, format: .fixed(precision: 1))x)")

        // Verify size constraint
        if compressedData.count > 1_048_576 { // 1MB
            Self.logger.warning("Compressed depth exceeds 1MB: \(compressedData.count) bytes")
        }

        return compressedData
    }

    // MARK: - Metadata Assembly

    private func buildMetadata(
        frame: ARFrame,
        jpeg: Data,
        depth: CVPixelBuffer,
        location: CLLocation?
    ) -> CaptureMetadata {
        // Compute SHA-256 hash of JPEG (using Story 6.3 CryptoService)
        let photoHash = CryptoService.sha256(jpeg)

        // Convert location if available
        let locationData = location.map { LocationData(from: $0) }

        // Extract depth dimensions
        let depthDimensions = DepthDimensions(
            width: CVPixelBufferGetWidth(depth),
            height: CVPixelBufferGetHeight(depth)
        )

        return CaptureMetadata(
            capturedAt: Date(timeIntervalSince1970: frame.timestamp),
            deviceModel: UIDevice.current.model,
            photoHash: photoHash,
            location: locationData,
            depthMapDimensions: depthDimensions
        )
    }
}

// MARK: - Error Extensions

extension CaptureError {
    static let noDepthData = CaptureError.custom("No depth data in ARFrame")
    static let jpegConversionFailed = CaptureError.custom("Failed to convert CVPixelBuffer to JPEG")
    static let depthCompressionFailed = CaptureError.custom("Failed to compress depth map")
    static let processingTimeout = CaptureError.custom("Frame processing exceeded timeout")
}
```

### Usage Example

```swift
// Initialize frame processor
let frameProcessor = FrameProcessor()

// Initialize AR capture session (Story 6.5)
let captureSession = ARCaptureSession()
try captureSession.start()

// When user taps capture button
if let frame = captureSession.captureCurrentFrame() {
    // Get current location (if authorized)
    let location = locationManager.location

    // Process frame in background
    let captureData = try await frameProcessor.process(frame, location: location)

    // CaptureData now contains:
    // - JPEG photo (2-4MB)
    // - Compressed depth (~50-100KB)
    // - Complete metadata with SHA-256 hash
    // - Ready for CoreData persistence (Story 6.9)

    // Next: Generate assertion (Story 6.8)
    // Next: Save to CoreData (Story 6.9)
    // Next: Upload to backend (Story 6.11)
}
```

### Unit Test Examples

```swift
import XCTest
import ARKit
@testable import Rial

class FrameProcessorTests: XCTestCase {
    var sut: FrameProcessor!

    override func setUp() {
        super.setUp()
        sut = FrameProcessor()
    }

    // MARK: - JPEG Conversion Tests

    func testConvertToJPEG_ValidPixelBuffer_ReturnsJPEGData() async throws {
        // Note: Requires mock CVPixelBuffer or physical device testing
        // This test demonstrates the expected behavior

        let mockPixelBuffer = createMockPixelBuffer(width: 1920, height: 1080)
        let jpegData = try await sut.convertToJPEG(mockPixelBuffer)

        XCTAssertGreaterThan(jpegData.count, 0, "JPEG data should not be empty")
        XCTAssertLessThan(jpegData.count, 10_000_000, "JPEG should be < 10MB")

        // Verify JPEG is valid
        let image = UIImage(data: jpegData)
        XCTAssertNotNil(image, "JPEG data should create valid UIImage")
    }

    // MARK: - Depth Compression Tests

    func testCompressDepth_ValidDepthMap_ReturnsCompressedData() throws {
        let mockDepthBuffer = createMockDepthBuffer(width: 256, height: 192)
        let compressedData = try sut.compressDepth(mockDepthBuffer)

        XCTAssertGreaterThan(compressedData.count, 0, "Compressed data should not be empty")
        XCTAssertLessThan(compressedData.count, 1_048_576, "Compressed depth should be < 1MB")
    }

    func testCompressDepth_NilBuffer_ThrowsError() {
        XCTAssertThrowsError(try sut.compressDepth(nil)) { error in
            guard let captureError = error as? CaptureError else {
                XCTFail("Expected CaptureError")
                return
            }
            // Verify correct error type
            XCTAssertEqual(captureError, .noDepthData)
        }
    }

    // MARK: - Metadata Assembly Tests

    func testBuildMetadata_WithLocation_IncludesLocationData() {
        let mockFrame = createMockARFrame()
        let mockJPEG = Data(repeating: 0x42, count: 1_000_000)
        let mockDepth = createMockDepthBuffer(width: 256, height: 192)
        let mockLocation = CLLocation(
            latitude: 37.7749,
            longitude: -122.4194
        )

        let metadata = sut.buildMetadata(
            frame: mockFrame,
            jpeg: mockJPEG,
            depth: mockDepth,
            location: mockLocation
        )

        XCTAssertNotNil(metadata.location, "Location should be included")
        XCTAssertEqual(metadata.location?.latitude, 37.7749)
        XCTAssertEqual(metadata.location?.longitude, -122.4194)
    }

    func testBuildMetadata_WithoutLocation_LocationIsNil() {
        let mockFrame = createMockARFrame()
        let mockJPEG = Data(repeating: 0x42, count: 1_000_000)
        let mockDepth = createMockDepthBuffer(width: 256, height: 192)

        let metadata = sut.buildMetadata(
            frame: mockFrame,
            jpeg: mockJPEG,
            depth: mockDepth,
            location: nil
        )

        XCTAssertNil(metadata.location, "Location should be nil when not provided")
        XCTAssertFalse(metadata.photoHash.isEmpty, "Photo hash should still be computed")
    }

    // MARK: - Performance Tests

    func testProcess_CompletesInUnder200ms() async throws {
        // Note: Requires physical device with LiDAR for accurate testing
        let mockFrame = createMockARFrame()
        let mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        let startTime = Date()
        let captureData = try await sut.process(mockFrame, location: mockLocation)
        let duration = Date().timeIntervalSince(startTime) * 1000

        XCTAssertLessThan(duration, 200, "Processing should complete in < 200ms")
        XCTAssertNotNil(captureData.jpeg)
        XCTAssertNotNil(captureData.depth)
        XCTAssertNotNil(captureData.metadata)
    }

    // MARK: - Helper Methods

    private func createMockPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        // Create mock CVPixelBuffer for testing
        // Note: Actual implementation requires CoreVideo APIs
        fatalError("Mock implementation needed")
    }

    private func createMockDepthBuffer(width: Int, height: Int) -> CVPixelBuffer {
        // Create mock depth buffer with Float32 values
        fatalError("Mock implementation needed")
    }

    private func createMockARFrame() -> ARFrame {
        // Create mock ARFrame for testing
        // Note: Actual implementation requires ARKit APIs or physical device
        fatalError("Mock implementation needed")
    }
}
```

---

## Dependencies

### Prerequisites
- **Story 6.5**: ARKit Unified Capture Session (provides ARFrame with RGB and depth)
- **Story 6.3**: CryptoKit Integration (provides SHA-256 hashing for photo hash)
- **Story 6.1**: Initialize Native iOS Project (provides project structure)

### Blocks
- **Story 6.8**: Per-Capture Assertion Signing (consumes CaptureData for assertion generation)
- **Story 6.9**: CoreData Capture Queue (persists CaptureData to local storage)
- **Story 6.13**: SwiftUI Capture Screen (triggers frame processing on capture button tap)

### External Dependencies
- **ARKit.framework**: For ARFrame type
- **CoreLocation.framework**: For CLLocation type
- **Compression.framework**: For zlib compression (built-in iOS)
- **CoreImage.framework**: For CIContext and JPEG conversion
- **UIKit.framework**: For UIDevice (device model)

---

## Testing Strategy

### Unit Tests (Limited Simulator Support)
Frame processing can be partially tested in simulator:
- Data structure creation (CaptureData, CaptureMetadata)
- Metadata assembly logic
- Error handling paths
- SHA-256 integration with CryptoService
- CVPixelBuffer mock handling

**Cannot test in simulator:**
- Actual JPEG conversion (requires real CVPixelBuffer from ARKit)
- Actual depth compression (requires real LiDAR depth data)
- Performance measurements (simulator not representative)

### Physical Device Testing (Required)
Full testing requires iPhone Pro with LiDAR:
- End-to-end frame processing with real ARFrame
- JPEG conversion with actual camera data
- Depth compression with actual LiDAR data
- Performance benchmarking (< 200ms target)
- Memory profiling with Instruments
- Background queue execution verification

### Integration Testing
- Story 6.5: ARCaptureSession provides valid ARFrame
- Story 6.3: CryptoService correctly hashes JPEG
- Story 6.9: CaptureData persists to CoreData
- Story 6.8: CaptureData used for assertion generation

### Performance Testing
Measure with Instruments Time Profiler on iPhone 12 Pro:
- Total processing time P95 < 200ms
- Total processing time P50 < 150ms
- JPEG conversion < 100ms
- Depth compression < 50ms
- SHA-256 hash < 30ms
- Memory usage spike < 50MB during processing
- No memory leaks after processing

---

## Definition of Done

- [ ] All acceptance criteria verified and passing
- [ ] All tasks completed
- [ ] FrameProcessor.swift implemented and documented
- [ ] CaptureData.swift models defined and documented
- [ ] CaptureError extended with processing errors
- [ ] Unit tests achieve 90%+ coverage (where testable)
- [ ] Physical device testing confirms:
  - [ ] JPEG conversion works with real ARFrame
  - [ ] Depth compression produces < 1MB output
  - [ ] Processing completes in < 200ms (P95)
  - [ ] Background queue execution verified
  - [ ] No memory leaks (Instruments Allocations)
- [ ] Integration with Story 6.5 (ARCaptureSession) tested
- [ ] Integration with Story 6.3 (CryptoService) tested
- [ ] Performance benchmarks documented
- [ ] Code reviewed and approved
- [ ] Documentation updated
- [ ] Code committed to feature branch

---

## FR Coverage

| Functional Requirement | Implementation |
|----------------------|----------------|
| **FR7**: Capture photo | JPEG conversion from ARFrame.capturedImage |
| **FR8**: Capture LiDAR depth map | Depth compression from ARFrame.sceneDepth |
| **FR9**: Record GPS coordinates | LocationData in CaptureMetadata |
| **FR11**: Compute SHA-256 hash | CryptoService.sha256() on JPEG data |
| **FR12**: Compress depth map | Zlib compression of Float32 depth buffer |
| **FR13**: Construct capture request | CaptureData structure with all components |

---

## References

### Source Documents
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#Story-6.6-Frame-Processing-Pipeline]
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-6.md#Data-Models]
- [User Request: Create story for 6-6-frame-processing-pipeline]

### Apple Documentation
- [CVPixelBuffer](https://developer.apple.com/documentation/corevideo/cvpixelbuffer)
- [CIContext JPEG Representation](https://developer.apple.com/documentation/coreimage/cicontext/1437759-jpegrepresentation)
- [NSData Compression](https://developer.apple.com/documentation/foundation/nsdata/3174960-compressed)
- [ARFrame](https://developer.apple.com/documentation/arkit/arframe)
- [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)

### Standards
- JPEG (ISO/IEC 10918-1)
- Zlib/Gzip Compression (RFC 1950, RFC 1951)
- SHA-256 (FIPS 180-4)

---

## Notes

### Important Implementation Considerations

1. **JPEG Quality Balance**
   - Quality 0.85 balances file size (2-4MB) and visual quality
   - Lower quality (0.7) reduces size but introduces artifacts
   - Higher quality (0.95) increases size without significant benefit
   - Backend expects ~3MB JPEG uploads

2. **Depth Compression Efficiency**
   - Float32 depth data is highly compressible (typical 3-5x ratio)
   - 256×192×4 = 196KB raw → ~50-70KB compressed
   - Zlib chosen for standard compatibility and good compression
   - Backend can decompress with standard gzip tools

3. **Performance Optimization**
   - CIContext reused across multiple conversions (expensive to create)
   - autoreleasepool wraps memory-intensive operations
   - async/await provides natural background execution
   - CVPixelBuffer access minimized (expensive to lock/unlock)

4. **Memory Management**
   - ARFrame holds references to large CVPixelBuffers
   - Must release frame references promptly to avoid memory pressure
   - JPEG conversion creates temporary buffers (managed by autoreleasepool)
   - Compression creates temporary buffers (released after completion)

5. **Location Privacy**
   - Location is optional (nil if denied or unavailable)
   - Backend applies coarsening for public views (FR44)
   - User can opt-out entirely (FR45)
   - Accuracy field helps backend determine precision level

### React Native Migration

This FrameProcessor replaces:
- Custom photo compression logic in React Native
- Separate LiDAR depth extraction module
- JavaScript-based metadata assembly
- Bridge crossings for large binary data

The native implementation provides:
- **Better performance**: No bridge overhead, native processing
- **Better quality**: Direct CIContext JPEG encoding
- **Better reliability**: No timing issues or synchronization bugs
- **Simpler code**: Single pipeline, no coordination between modules

### Common Processing Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| JPEG too large (> 10MB) | Quality too high or resolution issue | Verify quality 0.85, check source resolution |
| Depth compression fails | CVPixelBuffer format unexpected | Verify kCVPixelFormatType_DepthFloat32 |
| Processing timeout (> 1s) | Blocking main queue or slow device | Verify background queue, profile with Instruments |
| Memory pressure | Not releasing ARFrame references | Release frame after CaptureData creation |
| Photo hash mismatch | Non-deterministic JPEG encoding | Use fixed compression quality, check CIContext options |

### Testing Notes

**Simulator Limitations:**
- Cannot test actual JPEG conversion (no real CVPixelBuffer from ARKit)
- Cannot test actual depth compression (no LiDAR data)
- Performance measurements not representative
- Useful for data model tests and error handling

**Physical Device Requirements:**
- iPhone Pro (12 Pro or later) with LiDAR
- iOS 15.0 or later
- Camera and location permissions granted
- Sufficient storage for temporary processing buffers

---

## Dev Agent Record

### Context Reference

Story Context XML: `docs/sprint-artifacts/story-contexts/6-6-frame-processing-pipeline-context.xml`

### Agent Model Used

Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Implementation Notes

_To be filled during implementation_

### Completion Notes

_To be filled when story is complete_

### File List

**Created:**
- `ios/Rial/Core/Capture/FrameProcessor.swift` - Frame processing pipeline with JPEG conversion, depth compression, and metadata assembly
- `ios/Rial/Models/CaptureData.swift` - Data models for CaptureData, CaptureMetadata, LocationData, and DepthDimensions
- `ios/RialTests/Capture/FrameProcessorTests.swift` - Unit tests for frame processing pipeline

**Modified:**
- `ios/Rial/Core/Capture/CaptureError.swift` - Extended with processing error cases (or create if doesn't exist)
- `ios/Rial.xcodeproj/project.pbxproj` - Added FrameProcessor and CaptureData to Rial target, tests to RialTests target

### Code Review Result

_To be filled after code review_
