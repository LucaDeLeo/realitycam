//
//  HashChainService.swift
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  Thread-safe actor for computing frame hash chain during video recording.
//  Chains each frame's hash with the previous frame's hash for tamper detection.
//

import Foundation
import ARKit
import CryptoKit
import os.log

// MARK: - HashCheckpoint

/// Checkpoint hash at 5-second intervals for partial attestation.
///
/// Checkpoints allow partial verification of video integrity if recording
/// is interrupted, and enable efficient incremental attestation.
///
/// ## Checkpoint Intervals
/// - Index 0: Frame 150 (5 seconds at 30fps)
/// - Index 1: Frame 300 (10 seconds at 30fps)
/// - Index 2: Frame 450 (15 seconds at 30fps)
public struct HashCheckpoint: Codable, Sendable, Equatable {
    /// Checkpoint index (0=5s, 1=10s, 2=15s)
    public let index: Int

    /// Frame number at checkpoint (150, 300, 450)
    public let frameNumber: Int

    /// Chain hash at this checkpoint (32 bytes SHA256)
    public let hash: Data

    /// Video timestamp in seconds (relative to recording start)
    public let timestamp: TimeInterval

    /// Creates a new HashCheckpoint.
    ///
    /// - Parameters:
    ///   - index: Checkpoint index (0-2)
    ///   - frameNumber: Frame number at checkpoint
    ///   - hash: Chain hash at this point
    ///   - timestamp: Video timestamp in seconds
    public init(index: Int, frameNumber: Int, hash: Data, timestamp: TimeInterval) {
        self.index = index
        self.frameNumber = frameNumber
        self.hash = hash
        self.timestamp = timestamp
    }
}

// MARK: - HashChainData

/// Container for all frame hashes and checkpoints from a video recording.
///
/// HashChainData encapsulates the complete cryptographic chain for a recorded
/// video, including all frame hashes, periodic checkpoints, and the final hash
/// used for attestation signing.
///
/// ## Hash Chain Formula
/// - H(1) = SHA256(frame1 + depth1 + timestamp1)
/// - H(n) = SHA256(frameN + depthN + timestampN + H(n-1))
///
/// ## Usage
/// ```swift
/// let chainData = await hashChainService.getChainData()
/// let finalHash = chainData.finalHash  // For attestation signing
/// let checkpoints = chainData.checkpoints  // For partial verification
/// ```
public struct HashChainData: Codable, Sendable {
    /// All frame hashes at 30fps (up to 450 for 15-second video)
    public let frameHashes: [Data]

    /// Checkpoint hashes every 5 seconds (up to 3)
    public let checkpoints: [HashCheckpoint]

    /// Last frame hash for attestation signing (32 bytes)
    public let finalHash: Data

    /// Total number of frames in chain
    public var frameCount: Int { frameHashes.count }

    /// Number of checkpoints stored
    public var checkpointCount: Int { checkpoints.count }

    /// Creates a new HashChainData container.
    ///
    /// - Parameters:
    ///   - frameHashes: Array of all frame hashes
    ///   - checkpoints: Array of checkpoint data
    ///   - finalHash: Last frame hash for attestation
    public init(frameHashes: [Data], checkpoints: [HashCheckpoint], finalHash: Data) {
        self.frameHashes = frameHashes
        self.checkpoints = checkpoints
        self.finalHash = finalHash
    }
}

// MARK: - HashChainService

/// Thread-safe actor for computing frame hash chain during video recording.
///
/// HashChainService computes SHA256 hashes for each video frame, chaining
/// each hash with the previous frame's hash to create a tamper-evident
/// structure. Checkpoints are saved every 5 seconds for partial attestation.
///
/// ## Hash Chain Formula
/// - H(1) = SHA256(frame1 + depth1 + timestamp1)
/// - H(n) = SHA256(frameN + depthN + timestampN + H(n-1))
///
/// ## Security Properties
/// - **No frame insertion:** A foreign frame would break the chain
/// - **No frame removal:** Skipping a frame changes all subsequent hashes
/// - **No frame reordering:** Previous hash dependency prevents reordering
/// - **Temporal binding:** Timestamps embedded in hash prove capture order
///
/// ## Usage
/// ```swift
/// let hashService = HashChainService()
///
/// // During recording (called for each frame):
/// let hash = await hashService.processFrame(
///     rgbBuffer: frame.capturedImage,
///     depthBuffer: frame.sceneDepth?.depthMap,
///     timestamp: relativeTimestamp,
///     frameNumber: frameCount
/// )
///
/// // On recording complete:
/// let chainData = await hashService.getChainData()
/// ```
///
/// ## Performance
/// - Hash computation: < 5ms per frame target
/// - Memory: ~14KB for 450 frames (32 bytes per hash)
/// - Non-blocking: Actor ensures thread safety without locks
public actor HashChainService {

    // MARK: - Constants

    /// Checkpoint interval in frames (5 seconds at 30fps)
    public static let checkpointInterval: Int = 150

    /// Maximum checkpoints (3 for 15-second video)
    public static let maxCheckpoints: Int = 3

    /// Performance warning threshold in milliseconds
    private static let performanceThresholdMs: Double = 5.0

    // MARK: - Properties

    /// Logger for hash chain events
    private static let logger = Logger(subsystem: "app.rial", category: "hashchain")

    /// Previous frame's hash (nil for first frame)
    private var previousHash: Data?

    /// All computed frame hashes
    private var frameHashes: [Data] = []

    /// Checkpoint hashes at 5-second intervals
    private var checkpoints: [HashCheckpoint] = []

    // MARK: - Initialization

    /// Creates a new HashChainService.
    public init() {
        Self.logger.debug("HashChainService initialized")
    }

    // MARK: - Public Methods

    /// Process a frame and add to hash chain.
    ///
    /// Computes SHA256 hash including RGB data, optional depth data,
    /// timestamp, and previous hash (if not first frame). Creates
    /// checkpoint if at 5-second boundary.
    ///
    /// ## Hash Input Structure
    /// 1. RGB pixel data (from CVPixelBuffer)
    /// 2. Depth data (if available, Float32 array)
    /// 3. Timestamp (8 bytes, TimeInterval)
    /// 4. Previous hash (32 bytes, omitted for first frame)
    ///
    /// - Parameters:
    ///   - rgbBuffer: RGB pixel buffer from ARFrame.capturedImage
    ///   - depthBuffer: Optional depth buffer (available every 3rd frame at 10fps)
    ///   - timestamp: Relative frame timestamp (seconds since recording start)
    ///   - frameNumber: 1-based frame number
    /// - Returns: The computed hash for this frame (32 bytes)
    public func processFrame(
        rgbBuffer: CVPixelBuffer,
        depthBuffer: CVPixelBuffer?,
        timestamp: TimeInterval,
        frameNumber: Int
    ) -> Data {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Extract pixel data
        let rgbData = extractPixelData(rgbBuffer)
        let depthData = depthBuffer.flatMap { extractPixelData($0) }

        // Compute hash
        let hash = computeFrameHash(
            rgbData: rgbData,
            depthData: depthData,
            timestamp: timestamp,
            previousHash: previousHash
        )

        // Store hash
        frameHashes.append(hash)
        previousHash = hash

        // Check for checkpoint (frames 150, 300, 450)
        if frameNumber > 0 && frameNumber % Self.checkpointInterval == 0 {
            createCheckpoint(frameNumber: frameNumber, hash: hash, timestamp: timestamp)
        }

        // Performance logging
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let processingTimeMs = processingTime * 1000

        // Log every 30th frame to avoid spam
        if frameNumber % 30 == 0 {
            let hasDepth = depthData != nil
            Self.logger.debug("Frame \(frameNumber) hashed (depth: \(hasDepth), time: \(String(format: "%.2f", processingTimeMs))ms)")
        }

        // Warn if exceeded performance threshold
        if processingTimeMs > Self.performanceThresholdMs {
            Self.logger.warning("Hash computation exceeded \(Self.performanceThresholdMs)ms target: \(String(format: "%.2f", processingTimeMs))ms at frame \(frameNumber)")
        }

        return hash
    }

    /// Get the complete hash chain data.
    ///
    /// Returns a snapshot of all frame hashes, checkpoints, and the final
    /// hash for use in attestation signing and verification.
    ///
    /// - Returns: HashChainData containing all hashes and checkpoints,
    ///            or empty data if no frames processed
    public func getChainData() -> HashChainData {
        let finalHash = frameHashes.last ?? Data()

        if frameHashes.isEmpty {
            Self.logger.warning("getChainData called with no frames processed")
        } else {
            let hashPrefix = finalHash.prefix(8).map { String(format: "%02x", $0) }.joined()
            Self.logger.info("Hash chain finalized: \(self.frameHashes.count) frames, \(self.checkpoints.count) checkpoints, final hash: \(hashPrefix)...")
        }

        return HashChainData(
            frameHashes: frameHashes,
            checkpoints: checkpoints,
            finalHash: finalHash
        )
    }

    /// Reset all state for a new recording.
    ///
    /// Clears previous hash, all frame hashes, and checkpoints.
    /// Must be called before starting a new recording.
    public func reset() {
        previousHash = nil
        frameHashes = []
        checkpoints = []
        Self.logger.info("HashChainService reset")
    }

    /// Number of frames processed
    public var frameCount: Int { frameHashes.count }

    /// Most recent checkpoint (for interruption handling)
    public var lastCheckpoint: HashCheckpoint? { checkpoints.last }

    /// Whether the service has processed any frames
    public var hasFrames: Bool { !frameHashes.isEmpty }

    // MARK: - Private Methods

    /// Extract raw pixel data from CVPixelBuffer.
    ///
    /// Locks the buffer for read access, copies the raw bytes,
    /// and unlocks in a defer block for safety.
    ///
    /// - Parameter buffer: CVPixelBuffer to extract data from
    /// - Returns: Raw pixel data, or empty Data if extraction fails
    private func extractPixelData(_ buffer: CVPixelBuffer) -> Data {
        // Lock buffer for reading
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        // Get buffer properties
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            Self.logger.error("Failed to get pixel buffer base address")
            return Data()
        }

        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let dataSize = height * bytesPerRow

        // Copy data
        return Data(bytes: baseAddress, count: dataSize)
    }

    /// Compute SHA256 hash for a single frame.
    ///
    /// Constructs the hash input by concatenating:
    /// 1. RGB data
    /// 2. Depth data (if available)
    /// 3. Timestamp (8 bytes)
    /// 4. Previous hash (32 bytes, if not first frame)
    ///
    /// - Parameters:
    ///   - rgbData: RGB pixel data
    ///   - depthData: Optional depth data
    ///   - timestamp: Frame timestamp
    ///   - previousHash: Previous frame's hash (nil for first frame)
    /// - Returns: SHA256 hash (32 bytes)
    private func computeFrameHash(
        rgbData: Data,
        depthData: Data?,
        timestamp: TimeInterval,
        previousHash: Data?
    ) -> Data {
        var hasher = SHA256()

        // Add RGB data
        hasher.update(data: rgbData)

        // Add depth data if available
        if let depth = depthData {
            hasher.update(data: depth)
        }

        // Add timestamp (8 bytes for TimeInterval/Double)
        var ts = timestamp
        withUnsafeBytes(of: &ts) { bytes in
            hasher.update(bufferPointer: bytes)
        }

        // Chain with previous hash (if not first frame)
        if let prev = previousHash {
            hasher.update(data: prev)
        }

        return Data(hasher.finalize())
    }

    /// Create a checkpoint at the current frame.
    ///
    /// - Parameters:
    ///   - frameNumber: Current frame number (150, 300, 450)
    ///   - hash: Current frame's hash
    ///   - timestamp: Current timestamp
    private func createCheckpoint(frameNumber: Int, hash: Data, timestamp: TimeInterval) {
        // Calculate checkpoint index (0, 1, or 2)
        let index = (frameNumber / Self.checkpointInterval) - 1

        guard index >= 0 && checkpoints.count < Self.maxCheckpoints else {
            return
        }

        let checkpoint = HashCheckpoint(
            index: index,
            frameNumber: frameNumber,
            hash: hash,
            timestamp: timestamp
        )

        checkpoints.append(checkpoint)

        let hashPrefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        Self.logger.info("Checkpoint \(index) created at frame \(frameNumber) (\(String(format: "%.1f", timestamp))s): \(hashPrefix)...")
    }
}
