//
//  VideoAttestationService.swift
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  Service for generating DCAppAttest attestations for video captures.
//  Handles both normal completion and interrupted checkpoint attestations.
//

import Foundation
import os.log

// MARK: - VideoAttestation

/// Represents a DCAppAttest attestation for a video capture.
///
/// VideoAttestation contains the cryptographic proof that a video (or portion of video)
/// was captured on a registered device. For interrupted recordings, the attestation
/// covers only the portion up to the last completed checkpoint.
///
/// ## Normal Recording
/// ```swift
/// VideoAttestation(
///     finalHash: hashChainData.finalHash,
///     assertion: assertionData,
///     durationMs: 15000,
///     frameCount: 450,
///     isPartial: false,
///     checkpointIndex: nil
/// )
/// ```
///
/// ## Interrupted Recording (at 12s, last checkpoint at 10s)
/// ```swift
/// VideoAttestation(
///     finalHash: checkpoint1.hash,
///     assertion: assertionData,
///     durationMs: 10000,
///     frameCount: 300,
///     isPartial: true,
///     checkpointIndex: 1
/// )
/// ```
struct VideoAttestation: Codable, Equatable, Sendable {
    /// Hash that was attested (final hash for complete, checkpoint hash for partial)
    let finalHash: Data

    /// DCAppAttest signature (CBOR-encoded assertion)
    let assertion: Data

    /// Attested duration in milliseconds (may be partial if interrupted)
    let durationMs: Int64

    /// Attested frame count (may be partial if interrupted)
    let frameCount: Int

    /// True if recording was interrupted and only partial video is attested
    let isPartial: Bool

    /// Which checkpoint was attested (0=5s, 1=10s, 2=15s), nil for complete recordings
    let checkpointIndex: Int?

    /// Base64-encoded assertion for JSON serialization.
    var assertionBase64: String {
        assertion.base64EncodedString()
    }

    /// Base64-encoded final hash for logging and metadata.
    var finalHashBase64: String {
        finalHash.base64EncodedString()
    }

    /// Creates a new VideoAttestation.
    ///
    /// - Parameters:
    ///   - finalHash: Hash that was attested (32 bytes)
    ///   - assertion: DCAppAttest signature data
    ///   - durationMs: Attested duration in milliseconds
    ///   - frameCount: Attested frame count
    ///   - isPartial: Whether this is a partial recording
    ///   - checkpointIndex: Checkpoint index if partial, nil otherwise
    init(
        finalHash: Data,
        assertion: Data,
        durationMs: Int64,
        frameCount: Int,
        isPartial: Bool,
        checkpointIndex: Int?
    ) {
        self.finalHash = finalHash
        self.assertion = assertion
        self.durationMs = durationMs
        self.frameCount = frameCount
        self.isPartial = isPartial
        self.checkpointIndex = checkpointIndex
    }
}

// MARK: - VideoAttestationError

/// Errors that can occur during video attestation.
enum VideoAttestationError: Error, LocalizedError {
    /// No checkpoints available for interrupted recording
    case noCheckpointsAvailable

    /// DCAppAttest assertion generation failed
    case attestationFailed(Error)

    /// Invalid hash chain data (empty or malformed)
    case invalidHashChain

    var errorDescription: String? {
        switch self {
        case .noCheckpointsAvailable:
            return "No checkpoints available to attest interrupted recording"
        case .attestationFailed(let error):
            return "Failed to generate video attestation: \(error.localizedDescription)"
        case .invalidHashChain:
            return "Invalid or empty hash chain data"
        }
    }
}

// MARK: - VideoAttestationService

/// Service for generating DCAppAttest attestations for video captures.
///
/// VideoAttestationService wraps CaptureAssertionService to provide video-specific
/// attestation logic, including checkpoint selection for interrupted recordings.
///
/// ## Normal Completion Flow
/// 1. User completes 15-second recording
/// 2. Extract finalHash from hash chain
/// 3. Sign with DCAppAttest assertion
/// 4. Return VideoAttestation with isPartial=false
///
/// ## Interrupted Recording Flow
/// 1. Recording interrupted at 12 seconds
/// 2. Find last completed checkpoint (10s, checkpoint 1)
/// 3. Sign checkpoint hash with DCAppAttest
/// 4. Return VideoAttestation with isPartial=true, checkpointIndex=1
///
/// ## Usage
/// ```swift
/// let service = VideoAttestationService(assertionService: captureAssertionService)
///
/// // Normal completion
/// let attestation = try await service.attestCompletedRecording(
///     hashChainData: hashChainData,
///     durationMs: 15000
/// )
///
/// // Interrupted recording
/// let attestation = try await service.attestInterruptedRecording(
///     hashChainData: hashChainData,
///     interruptedAt: 12000
/// )
/// ```
final class VideoAttestationService {

    // MARK: - Properties

    /// Assertion service for DCAppAttest integration
    private let assertionService: CaptureAssertionService

    /// Logger for attestation events
    private static let logger = Logger(subsystem: "app.rial", category: "videoattestation")

    // MARK: - Initialization

    /// Creates a new VideoAttestationService.
    ///
    /// - Parameter assertionService: CaptureAssertionService for assertion generation
    init(assertionService: CaptureAssertionService) {
        self.assertionService = assertionService
        Self.logger.debug("VideoAttestationService initialized")
    }

    // MARK: - Public Methods

    /// Attest a completed video recording.
    ///
    /// Signs the final hash from the hash chain with a DCAppAttest assertion.
    /// Used for recordings that completed normally (user released button or hit max duration).
    ///
    /// - Parameters:
    ///   - hashChainData: Complete hash chain from recording
    ///   - durationMs: Total recording duration in milliseconds
    /// - Returns: VideoAttestation with final hash attested
    /// - Throws: `VideoAttestationError` if attestation fails
    ///
    /// ## Performance
    /// Target: < 100ms total
    ///
    /// ## Example
    /// ```swift
    /// let attestation = try await attestCompletedRecording(
    ///     hashChainData: hashChainData,
    ///     durationMs: 15000
    /// )
    /// // attestation.isPartial == false
    /// // attestation.checkpointIndex == nil
    /// // attestation.frameCount == 450
    /// ```
    func attestCompletedRecording(
        hashChainData: HashChainData,
        durationMs: Int64
    ) async throws -> VideoAttestation {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Validate hash chain
        guard !hashChainData.frameHashes.isEmpty else {
            Self.logger.error("Cannot attest empty hash chain")
            throw VideoAttestationError.invalidHashChain
        }

        let finalHash = hashChainData.finalHash
        let frameCount = hashChainData.frameCount

        // Generate assertion for final hash
        do {
            let assertion = try await assertionService.generateAssertion(for: finalHash)

            let attestation = VideoAttestation(
                finalHash: finalHash,
                assertion: assertion,
                durationMs: durationMs,
                frameCount: frameCount,
                isPartial: false,
                checkpointIndex: nil
            )

            let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            let hashPrefix = finalHash.prefix(8).map { String(format: "%02x", $0) }.joined()

            Self.logger.info("""
                Normal attestation completed: \
                frames=\(frameCount), \
                duration=\(durationMs)ms, \
                hash=\(hashPrefix)..., \
                time=\(String(format: "%.1f", elapsedTime))ms
                """)

            // Warn if exceeded target
            if elapsedTime > 100 {
                Self.logger.warning("Normal attestation exceeded 100ms target: \(String(format: "%.1f", elapsedTime))ms")
            }

            return attestation

        } catch {
            Self.logger.error("Normal attestation failed: \(error.localizedDescription)")
            throw VideoAttestationError.attestationFailed(error)
        }
    }

    /// Attest an interrupted video at the last completed checkpoint.
    ///
    /// When recording is interrupted (phone call, backgrounding), this method
    /// finds the last completed checkpoint and signs its hash. This preserves
    /// partial evidence even when recording doesn't complete.
    ///
    /// - Parameters:
    ///   - hashChainData: Partial hash chain from recording
    ///   - interruptedAt: Duration when interruption occurred (milliseconds)
    /// - Returns: VideoAttestation with checkpoint hash attested
    /// - Throws: `VideoAttestationError` if no checkpoints available or attestation fails
    ///
    /// ## Performance
    /// Target: < 200ms total (includes checkpoint selection)
    ///
    /// ## Example
    /// ```swift
    /// // Recording interrupted at 12.3 seconds
    /// let attestation = try await attestInterruptedRecording(
    ///     hashChainData: hashChainData,
    ///     interruptedAt: 12300
    /// )
    /// // attestation.isPartial == true
    /// // attestation.checkpointIndex == 1 (10-second checkpoint)
    /// // attestation.durationMs == 10000
    /// // attestation.frameCount == 300
    /// ```
    func attestInterruptedRecording(
        hashChainData: HashChainData,
        interruptedAt: Int64
    ) async throws -> VideoAttestation {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Find last completed checkpoint
        guard let lastCheckpoint = hashChainData.checkpoints.last else {
            Self.logger.error("No checkpoints available for interrupted recording at \(interruptedAt)ms")
            throw VideoAttestationError.noCheckpointsAvailable
        }

        let checkpointHash = lastCheckpoint.hash
        let checkpointIndex = lastCheckpoint.index
        let frameCount = lastCheckpoint.frameNumber
        let durationMs = Int64(lastCheckpoint.timestamp * 1000)

        // Generate assertion for checkpoint hash
        do {
            let assertion = try await assertionService.generateAssertion(for: checkpointHash)

            let attestation = VideoAttestation(
                finalHash: checkpointHash,
                assertion: assertion,
                durationMs: durationMs,
                frameCount: frameCount,
                isPartial: true,
                checkpointIndex: checkpointIndex
            )

            let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            let hashPrefix = checkpointHash.prefix(8).map { String(format: "%02x", $0) }.joined()

            Self.logger.info("""
                Checkpoint attestation completed: \
                checkpoint=\(checkpointIndex), \
                frames=\(frameCount), \
                verifiedDuration=\(durationMs)ms, \
                interruptedAt=\(interruptedAt)ms, \
                hash=\(hashPrefix)..., \
                time=\(String(format: "%.1f", elapsedTime))ms
                """)

            // Warn if exceeded target
            if elapsedTime > 200 {
                Self.logger.warning("Checkpoint attestation exceeded 200ms target: \(String(format: "%.1f", elapsedTime))ms")
            }

            return attestation

        } catch {
            Self.logger.error("Checkpoint attestation failed: \(error.localizedDescription)")
            throw VideoAttestationError.attestationFailed(error)
        }
    }
}
