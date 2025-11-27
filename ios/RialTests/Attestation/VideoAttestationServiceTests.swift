//
//  VideoAttestationServiceTests.swift
//  RialTests
//
//  Created by RealityCam on 2025-11-26.
//
//  Unit tests for VideoAttestationService.
//

import XCTest
@testable import Rial

/// Unit tests for VideoAttestationService.
///
/// Tests both normal completion and interrupted recording attestation flows,
/// including error cases and Codable/Equatable conformance.
final class VideoAttestationServiceTests: XCTestCase {

    var sut: VideoAttestationService!
    var mockAssertionService: MockCaptureAssertionService!

    override func setUp() {
        super.setUp()
        mockAssertionService = MockCaptureAssertionService()
        sut = VideoAttestationService(assertionService: mockAssertionService)
    }

    override func tearDown() {
        sut = nil
        mockAssertionService = nil
        super.tearDown()
    }

    // MARK: - Normal Completion Tests

    /// Test that normal completion attestation succeeds with valid hash chain
    func testNormalCompletionAttestationSucceeds() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 450, checkpointCount: 3)
        let durationMs: Int64 = 15000

        // Configure mock to return valid assertion
        mockAssertionService.assertionToReturn = Data(repeating: 0x42, count: 1024)

        // When
        let attestation = try await sut.attestCompletedRecording(
            hashChainData: hashChainData,
            durationMs: durationMs
        )

        // Then
        XCTAssertEqual(attestation.frameCount, 450, "Frame count should match hash chain")
        XCTAssertEqual(attestation.durationMs, 15000, "Duration should match input")
        XCTAssertEqual(attestation.finalHash, hashChainData.finalHash, "Final hash should match")
        XCTAssertFalse(attestation.isPartial, "Should not be partial")
        XCTAssertNil(attestation.checkpointIndex, "Checkpoint index should be nil for complete recording")
        XCTAssertEqual(attestation.assertion.count, 1024, "Assertion should be returned")
    }

    /// Test that completed attestation has isPartial=false
    func testCompletedAttestationIsNotPartial() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 300, checkpointCount: 2)
        mockAssertionService.assertionToReturn = Data(repeating: 0x42, count: 1024)

        // When
        let attestation = try await sut.attestCompletedRecording(
            hashChainData: hashChainData,
            durationMs: 10000
        )

        // Then
        XCTAssertFalse(attestation.isPartial, "Completed recording should not be partial")
    }

    /// Test that completed attestation has nil checkpointIndex
    func testCompletedAttestationHasNilCheckpointIndex() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 450, checkpointCount: 3)
        mockAssertionService.assertionToReturn = Data(repeating: 0x42, count: 1024)

        // When
        let attestation = try await sut.attestCompletedRecording(
            hashChainData: hashChainData,
            durationMs: 15000
        )

        // Then
        XCTAssertNil(attestation.checkpointIndex, "Checkpoint index should be nil for complete recording")
    }

    /// Test that completed attestation frame count matches hash chain
    func testCompletedAttestationFrameCountMatchesHashChain() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 360, checkpointCount: 2)
        mockAssertionService.assertionToReturn = Data(repeating: 0x42, count: 1024)

        // When
        let attestation = try await sut.attestCompletedRecording(
            hashChainData: hashChainData,
            durationMs: 12000
        )

        // Then
        XCTAssertEqual(attestation.frameCount, 360, "Frame count should match hash chain")
        XCTAssertEqual(attestation.frameCount, hashChainData.frameCount, "Frame count should match hash chain")
    }

    /// Test that empty hash chain throws error
    func testEmptyHashChainThrowsError() async {
        // Given
        let emptyHashChain = HashChainData(frameHashes: [], checkpoints: [], finalHash: Data())

        // When/Then
        do {
            _ = try await sut.attestCompletedRecording(
                hashChainData: emptyHashChain,
                durationMs: 0
            )
            XCTFail("Should throw invalidHashChain error")
        } catch let error as VideoAttestationError {
            if case .invalidHashChain = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Interrupted Recording Tests

    /// Test that interrupted attestation uses last checkpoint
    func testInterruptedAttestationUsesLastCheckpoint() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 360, checkpointCount: 2)
        let interruptedAt: Int64 = 12000  // 12 seconds
        mockAssertionService.assertionToReturn = Data(repeating: 0x43, count: 1024)

        // When
        let attestation = try await sut.attestInterruptedRecording(
            hashChainData: hashChainData,
            interruptedAt: interruptedAt
        )

        // Then
        let lastCheckpoint = hashChainData.checkpoints.last!
        XCTAssertEqual(attestation.finalHash, lastCheckpoint.hash, "Should use last checkpoint hash")
        XCTAssertEqual(attestation.checkpointIndex, lastCheckpoint.index, "Should use last checkpoint index")
    }

    /// Test that interrupted attestation has isPartial=true
    func testInterruptedAttestationIsPartial() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 360, checkpointCount: 2)
        mockAssertionService.assertionToReturn = Data(repeating: 0x43, count: 1024)

        // When
        let attestation = try await sut.attestInterruptedRecording(
            hashChainData: hashChainData,
            interruptedAt: 12000
        )

        // Then
        XCTAssertTrue(attestation.isPartial, "Interrupted recording should be partial")
    }

    /// Test that interrupted attestation has correct checkpointIndex
    func testInterruptedAttestationHasCorrectCheckpointIndex() async throws {
        // Given - Recording interrupted at 12s, last checkpoint at 10s (index 1)
        let hashChainData = createMockHashChainData(frameCount: 360, checkpointCount: 2)
        mockAssertionService.assertionToReturn = Data(repeating: 0x43, count: 1024)

        // When
        let attestation = try await sut.attestInterruptedRecording(
            hashChainData: hashChainData,
            interruptedAt: 12000
        )

        // Then
        XCTAssertEqual(attestation.checkpointIndex, 1, "Should be checkpoint 1 (10s)")
    }

    /// Test that interrupted attestation frame count matches checkpoint
    func testInterruptedAttestationFrameCountMatchesCheckpoint() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 360, checkpointCount: 2)
        mockAssertionService.assertionToReturn = Data(repeating: 0x43, count: 1024)

        // When
        let attestation = try await sut.attestInterruptedRecording(
            hashChainData: hashChainData,
            interruptedAt: 12000
        )

        // Then
        let lastCheckpoint = hashChainData.checkpoints.last!
        XCTAssertEqual(attestation.frameCount, lastCheckpoint.frameNumber, "Frame count should match checkpoint")
        XCTAssertEqual(attestation.frameCount, 300, "Should be 300 frames for 10s checkpoint")
    }

    /// Test that interrupted attestation duration matches checkpoint timestamp
    func testInterruptedAttestationDurationMatchesCheckpoint() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 360, checkpointCount: 2)
        mockAssertionService.assertionToReturn = Data(repeating: 0x43, count: 1024)

        // When
        let attestation = try await sut.attestInterruptedRecording(
            hashChainData: hashChainData,
            interruptedAt: 12000
        )

        // Then
        XCTAssertEqual(attestation.durationMs, 10000, "Duration should be 10s (checkpoint 1)")
    }

    /// Test that interrupted recording with no checkpoints returns error
    func testInterruptedRecordingWithNoCheckpointsReturnsError() async {
        // Given - Hash chain with no checkpoints (interrupted before 5s)
        let hashChainData = createMockHashChainData(frameCount: 120, checkpointCount: 0)

        // When/Then
        do {
            _ = try await sut.attestInterruptedRecording(
                hashChainData: hashChainData,
                interruptedAt: 4000
            )
            XCTFail("Should throw noCheckpointsAvailable error")
        } catch let error as VideoAttestationError {
            if case .noCheckpointsAvailable = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Error Propagation Tests

    /// Test that attestation service errors are propagated
    func testAttestationServiceErrorsPropagated() async {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 450, checkpointCount: 3)
        mockAssertionService.shouldThrowError = true
        mockAssertionService.errorToThrow = CaptureAssertionError.attestationKeyNotFound

        // When/Then
        do {
            _ = try await sut.attestCompletedRecording(
                hashChainData: hashChainData,
                durationMs: 15000
            )
            XCTFail("Should throw attestationFailed error")
        } catch let error as VideoAttestationError {
            if case .attestationFailed = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - VideoAttestation Tests

    /// Test VideoAttestation Codable conformance (encode/decode)
    func testVideoAttestationCodable() throws {
        // Given
        let attestation = VideoAttestation(
            finalHash: Data(repeating: 0x42, count: 32),
            assertion: Data(repeating: 0x43, count: 1024),
            durationMs: 15000,
            frameCount: 450,
            isPartial: false,
            checkpointIndex: nil
        )

        // When - Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(attestation)

        // Then - Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VideoAttestation.self, from: data)

        XCTAssertEqual(decoded, attestation, "Decoded attestation should equal original")
    }

    /// Test VideoAttestation Equatable conformance
    func testVideoAttestationEquatable() {
        // Given
        let attestation1 = VideoAttestation(
            finalHash: Data(repeating: 0x42, count: 32),
            assertion: Data(repeating: 0x43, count: 1024),
            durationMs: 15000,
            frameCount: 450,
            isPartial: false,
            checkpointIndex: nil
        )

        let attestation2 = VideoAttestation(
            finalHash: Data(repeating: 0x42, count: 32),
            assertion: Data(repeating: 0x43, count: 1024),
            durationMs: 15000,
            frameCount: 450,
            isPartial: false,
            checkpointIndex: nil
        )

        let attestation3 = VideoAttestation(
            finalHash: Data(repeating: 0x44, count: 32),  // Different hash
            assertion: Data(repeating: 0x43, count: 1024),
            durationMs: 15000,
            frameCount: 450,
            isPartial: false,
            checkpointIndex: nil
        )

        // Then
        XCTAssertEqual(attestation1, attestation2, "Same attestations should be equal")
        XCTAssertNotEqual(attestation1, attestation3, "Different attestations should not be equal")
    }

    /// Test assertionBase64 property encoding
    func testAssertionBase64PropertyEncoding() {
        // Given
        let assertionData = Data(repeating: 0x42, count: 64)
        let attestation = VideoAttestation(
            finalHash: Data(repeating: 0x41, count: 32),
            assertion: assertionData,
            durationMs: 15000,
            frameCount: 450,
            isPartial: false,
            checkpointIndex: nil
        )

        // When
        let base64 = attestation.assertionBase64

        // Then
        XCTAssertEqual(base64, assertionData.base64EncodedString(), "Base64 should match Data encoding")
        XCTAssertFalse(base64.isEmpty, "Base64 should not be empty")
    }

    /// Test finalHashBase64 property encoding
    func testFinalHashBase64PropertyEncoding() {
        // Given
        let hashData = Data(repeating: 0x42, count: 32)
        let attestation = VideoAttestation(
            finalHash: hashData,
            assertion: Data(repeating: 0x43, count: 1024),
            durationMs: 15000,
            frameCount: 450,
            isPartial: false,
            checkpointIndex: nil
        )

        // When
        let base64 = attestation.finalHashBase64

        // Then
        XCTAssertEqual(base64, hashData.base64EncodedString(), "Base64 should match Data encoding")
        XCTAssertFalse(base64.isEmpty, "Base64 should not be empty")
    }

    // MARK: - Performance Tests

    /// Test that attestation completes within performance target
    func testAttestationPerformance() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 450, checkpointCount: 3)
        mockAssertionService.assertionToReturn = Data(repeating: 0x42, count: 1024)
        mockAssertionService.simulatedDelay = 0.05  // 50ms simulated delay

        // When
        let startTime = Date()
        _ = try await sut.attestCompletedRecording(
            hashChainData: hashChainData,
            durationMs: 15000
        )
        let duration = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(duration, 0.1, "Normal attestation should complete in less than 100ms")
    }

    /// Test that checkpoint attestation completes within performance target
    func testCheckpointAttestationPerformance() async throws {
        // Given
        let hashChainData = createMockHashChainData(frameCount: 360, checkpointCount: 2)
        mockAssertionService.assertionToReturn = Data(repeating: 0x43, count: 1024)
        mockAssertionService.simulatedDelay = 0.1  // 100ms simulated delay

        // When
        let startTime = Date()
        _ = try await sut.attestInterruptedRecording(
            hashChainData: hashChainData,
            interruptedAt: 12000
        )
        let duration = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(duration, 0.2, "Checkpoint attestation should complete in less than 200ms")
    }

    // MARK: - Helper Methods

    /// Create mock HashChainData for testing
    private func createMockHashChainData(frameCount: Int, checkpointCount: Int) -> HashChainData {
        // Create frame hashes
        var frameHashes: [Data] = []
        for _ in 0..<frameCount {
            frameHashes.append(Data(repeating: 0x42, count: 32))
        }

        // Create checkpoints
        var checkpoints: [HashCheckpoint] = []
        for index in 0..<checkpointCount {
            let checkpoint = HashCheckpoint(
                index: index,
                frameNumber: (index + 1) * 150,
                hash: Data(repeating: UInt8(index), count: 32),
                timestamp: TimeInterval((index + 1) * 5)
            )
            checkpoints.append(checkpoint)
        }

        let finalHash = frameHashes.last ?? Data()
        return HashChainData(
            frameHashes: frameHashes,
            checkpoints: checkpoints,
            finalHash: finalHash
        )
    }
}

// MARK: - MockCaptureAssertionService

/// Mock CaptureAssertionService for testing
class MockCaptureAssertionService: CaptureAssertionService {

    var assertionToReturn: Data?
    var shouldThrowError = false
    var errorToThrow: Error = CaptureAssertionError.attestationKeyNotFound
    var simulatedDelay: TimeInterval = 0

    init() {
        // Initialize with dummy services (not used in mock)
        super.init(
            attestation: DeviceAttestationService(),
            keychain: KeychainService()
        )
    }

    override func generateAssertion(for hash: Data) async throws -> Data {
        // Simulate network/crypto delay if configured
        if simulatedDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
        }

        if shouldThrowError {
            throw errorToThrow
        }

        guard let assertion = assertionToReturn else {
            throw CaptureAssertionError.attestationKeyNotFound
        }

        return assertion
    }
}
