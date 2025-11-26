//
//  DepthKeyframeBuffer.swift
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  Thread-safe buffer for accumulating depth keyframes during video recording.
//  Extracts depth data at 10fps (every 3rd frame from 30fps video) and
//  compresses the final blob with gzip for storage efficiency.
//

import Foundation
import ARKit
import Compression
import os.log

// MARK: - DepthKeyframe

/// Individual depth keyframe with index and location in blob.
///
/// Each keyframe represents a single depth capture at a specific point
/// in the video timeline. The offset indicates where the keyframe's
/// Float32 data begins in the uncompressed blob.
public struct DepthKeyframe: Codable, Sendable, Equatable {
    /// 0-based frame index (0, 1, 2, ... up to 149)
    public let index: Int

    /// Video timestamp from ARFrame (seconds since recording start)
    public let timestamp: TimeInterval

    /// Byte offset in the uncompressed blob where this keyframe's data begins
    public let offset: Int

    /// Creates a new DepthKeyframe.
    ///
    /// - Parameters:
    ///   - index: 0-based keyframe index
    ///   - timestamp: Video timestamp in seconds
    ///   - offset: Byte offset in the uncompressed depth blob
    public init(index: Int, timestamp: TimeInterval, offset: Int) {
        self.index = index
        self.timestamp = timestamp
        self.offset = offset
    }
}

// MARK: - DepthKeyframeData

/// Container for all depth keyframes captured during video recording.
///
/// Represents the complete depth capture for a video recording session.
/// The compressed blob contains Float32 depth values for all keyframes,
/// concatenated in order and gzip-compressed for storage efficiency.
///
/// ## Usage
/// ```swift
/// let buffer = DepthKeyframeBuffer()
/// // ... capture keyframes during recording ...
/// let depthData = buffer.finalize()
///
/// // depthData.frames contains index/timestamp/offset for each keyframe
/// // depthData.compressedBlob contains gzipped Float32 depth values
/// ```
public struct DepthKeyframeData: Codable, Sendable {
    /// Array of keyframe metadata (10fps, up to 150 frames for 15s video)
    public let frames: [DepthKeyframe]

    /// Depth map resolution (typically 256x192 for LiDAR)
    public let resolution: CGSize

    /// Gzip-compressed Float32 depth data for all frames
    public let compressedBlob: Data

    /// Uncompressed size in bytes (for decompression buffer allocation)
    public let uncompressedSize: Int

    /// Creates a new DepthKeyframeData container.
    ///
    /// - Parameters:
    ///   - frames: Array of keyframe metadata
    ///   - resolution: Depth map resolution
    ///   - compressedBlob: Gzip-compressed depth data
    ///   - uncompressedSize: Original uncompressed size
    public init(
        frames: [DepthKeyframe],
        resolution: CGSize,
        compressedBlob: Data,
        uncompressedSize: Int
    ) {
        self.frames = frames
        self.resolution = resolution
        self.compressedBlob = compressedBlob
        self.uncompressedSize = uncompressedSize
    }

    /// Number of keyframes captured
    public var keyframeCount: Int {
        frames.count
    }

    /// Compression ratio achieved (uncompressed / compressed)
    public var compressionRatio: Double {
        guard compressedBlob.count > 0 else { return 0 }
        return Double(uncompressedSize) / Double(compressedBlob.count)
    }
}

// MARK: - DepthKeyframeError

/// Errors that can occur during depth keyframe extraction and compression.
public enum DepthKeyframeError: Error, LocalizedError, Equatable {
    /// Depth buffer has invalid pixel format (expected Float32)
    case invalidPixelFormat

    /// Failed to access depth buffer memory
    case bufferAccessFailed

    /// Gzip compression failed
    case compressionFailed

    /// Maximum keyframe limit reached (150 for 15s video)
    case maxKeyframesReached

    /// Buffer is not in recording state
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .invalidPixelFormat:
            return "Invalid depth buffer pixel format (expected Float32)"
        case .bufferAccessFailed:
            return "Failed to access depth buffer memory"
        case .compressionFailed:
            return "Failed to compress depth data"
        case .maxKeyframesReached:
            return "Maximum keyframe limit reached (150 frames)"
        case .notRecording:
            return "Buffer is not in recording state"
        }
    }
}

// MARK: - DepthKeyframeBuffer

/// Thread-safe buffer for accumulating depth keyframes during video recording.
///
/// DepthKeyframeBuffer extracts and stores LiDAR depth data at 10fps during
/// video recording. It handles the conversion from CVPixelBuffer to raw Float32
/// data, maintains frame indexing, and provides gzip compression on finalization.
///
/// ## Usage
/// ```swift
/// let buffer = DepthKeyframeBuffer()
/// buffer.startRecording()
///
/// // During frame callback (every 3rd frame)
/// if buffer.shouldExtractDepth(frameNumber: frameNumber) {
///     if let depthMap = frame.sceneDepth?.depthMap {
///         buffer.processFrame(frame, frameNumber: frameNumber)
///     }
/// }
///
/// // On recording complete
/// let depthData = try buffer.finalize()
/// ```
///
/// ## Thread Safety
/// All public methods are thread-safe and can be called from any queue.
/// Uses NSLock for synchronized access to internal state.
///
/// ## Performance
/// - Depth extraction: < 10ms per frame
/// - Memory: Contributes to < 300MB total recording budget
/// - Compression: Lazy (performed in finalize(), not during recording)
public final class DepthKeyframeBuffer: @unchecked Sendable {

    // MARK: - Constants

    /// Maximum number of keyframes (10fps x 15s = 150)
    public static let maxKeyframes: Int = 150

    /// Target keyframe rate (10fps from 30fps video = every 3rd frame)
    public static let keyframeInterval: Int = 3

    // MARK: - Properties

    /// Logger for depth keyframe events
    private static let logger = Logger(subsystem: "app.rial", category: "depthkeyframe")

    /// Lock for thread-safe state access
    private let lock = NSLock()

    /// Accumulated raw depth data (uncompressed Float32 values)
    private var _accumulatedData = Data()

    /// Array of keyframe metadata
    private var _keyframes: [DepthKeyframe] = []

    /// Depth map resolution (set from first extracted frame)
    private var _resolution: CGSize = .zero

    /// Whether buffer is actively recording
    private var _isRecording: Bool = false

    /// Recording start timestamp for relative timing
    private var _recordingStartTimestamp: TimeInterval?

    // MARK: - Public Computed Properties

    /// Number of keyframes currently stored (thread-safe)
    public var keyframeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _keyframes.count
    }

    /// Whether buffer is actively recording (thread-safe)
    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRecording
    }

    /// Current depth resolution (thread-safe)
    public var resolution: CGSize {
        lock.lock()
        defer { lock.unlock() }
        return _resolution
    }

    /// Current accumulated data size in bytes (thread-safe)
    public var accumulatedDataSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return _accumulatedData.count
    }

    // MARK: - Initialization

    public init() {
        Self.logger.debug("DepthKeyframeBuffer initialized")
    }

    deinit {
        Self.logger.debug("DepthKeyframeBuffer deinitialized")
    }

    // MARK: - Public Methods

    /// Determine if depth should be extracted for this frame.
    ///
    /// Depth is extracted every 3rd frame to achieve 10fps from 30fps video.
    /// Frame numbers are 1-based (first frame is 1), so we extract when
    /// (frameNumber - 1) % 3 == 0, i.e., frames 1, 4, 7, 10...
    ///
    /// - Parameter frameNumber: 1-based frame number from VideoRecordingSession
    /// - Returns: `true` if depth should be extracted for this frame
    public func shouldExtractDepth(frameNumber: Int) -> Bool {
        // Frame numbers are 1-based, extract on frames 1, 4, 7, 10...
        // This gives us 10fps from 30fps (every 3rd frame)
        return (frameNumber - 1) % Self.keyframeInterval == 0
    }

    /// Start recording session.
    ///
    /// Resets all accumulated data and prepares buffer for new recording.
    /// Must be called before processing frames.
    public func startRecording() {
        lock.lock()
        defer { lock.unlock() }

        _accumulatedData = Data()
        _keyframes = []
        _resolution = .zero
        _isRecording = true
        _recordingStartTimestamp = nil

        Self.logger.info("DepthKeyframeBuffer started recording")
    }

    /// Process an ARFrame and extract depth if appropriate.
    ///
    /// Handles the complete depth extraction workflow including:
    /// - Frame number validation (every 3rd frame)
    /// - Nil depth data handling (logs warning, continues)
    /// - Resolution validation
    /// - Float32 data extraction
    /// - Keyframe metadata creation
    ///
    /// - Parameters:
    ///   - frame: ARFrame containing sceneDepth data
    ///   - frameNumber: 1-based frame number from VideoRecordingSession
    public func processFrame(_ frame: ARFrame, frameNumber: Int) {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Check if we should extract this frame
        guard shouldExtractDepth(frameNumber: frameNumber) else {
            return
        }

        lock.lock()

        // Verify recording state
        guard _isRecording else {
            lock.unlock()
            Self.logger.warning("processFrame called but not recording")
            return
        }

        // Check max keyframes
        guard _keyframes.count < Self.maxKeyframes else {
            lock.unlock()
            Self.logger.warning("Max keyframes reached (\(Self.maxKeyframes)), skipping frame \(frameNumber)")
            return
        }

        // Set recording start timestamp from first frame
        if _recordingStartTimestamp == nil {
            _recordingStartTimestamp = frame.timestamp
        }

        let recordingStart = _recordingStartTimestamp ?? frame.timestamp
        lock.unlock()

        // Check for depth data
        guard let depthData = frame.sceneDepth else {
            Self.logger.warning("Frame \(frameNumber) missing sceneDepth (nil)")
            return
        }

        // Extract depth data
        do {
            let extractedData = try extractDepthData(from: depthData.depthMap)

            // Calculate relative timestamp
            let relativeTimestamp = frame.timestamp - recordingStart

            // Append to buffer
            lock.lock()

            let offset = _accumulatedData.count
            let keyframeIndex = _keyframes.count

            _accumulatedData.append(extractedData)
            _keyframes.append(DepthKeyframe(
                index: keyframeIndex,
                timestamp: relativeTimestamp,
                offset: offset
            ))

            let currentCount = _keyframes.count
            lock.unlock()

            let processingTime = CFAbsoluteTimeGetCurrent() - startTime

            // Log periodically (every 10 keyframes)
            if currentCount % 10 == 0 || currentCount == 1 {
                Self.logger.debug("Extracted keyframe \(currentCount) at \(String(format: "%.2f", relativeTimestamp))s (processing: \(String(format: "%.1f", processingTime * 1000))ms)")
            }

            // Warn if processing exceeded target
            if processingTime > 0.010 {
                Self.logger.warning("Depth extraction exceeded 10ms target: \(String(format: "%.1f", processingTime * 1000))ms")
            }

        } catch {
            Self.logger.error("Failed to extract depth from frame \(frameNumber): \(error.localizedDescription)")
        }
    }

    /// Extract raw Float32 depth data from a CVPixelBuffer.
    ///
    /// Converts the depth map from CVPixelBuffer format to a contiguous
    /// Data object containing Float32 depth values in meters.
    ///
    /// - Parameter depthMap: CVPixelBuffer with kCVPixelFormatType_DepthFloat32
    /// - Returns: Raw Float32 depth data
    /// - Throws: `DepthKeyframeError` if extraction fails
    public func extractDepthData(from depthMap: CVPixelBuffer) throws -> Data {
        // Validate pixel format
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        guard pixelFormat == kCVPixelFormatType_DepthFloat32 else {
            Self.logger.error("Invalid pixel format: \(pixelFormat) (expected DepthFloat32)")
            throw DepthKeyframeError.invalidPixelFormat
        }

        // Lock buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            Self.logger.error("Failed to get depth buffer base address")
            throw DepthKeyframeError.bufferAccessFailed
        }

        // Update resolution on first frame
        lock.lock()
        if _resolution == .zero {
            _resolution = CGSize(width: width, height: height)
            Self.logger.info("Depth resolution set: \(width)x\(height)")
        }
        lock.unlock()

        // Calculate data size and copy
        let pixelCount = width * height
        let dataSize = pixelCount * MemoryLayout<Float32>.size

        // Copy Float32 data directly
        let data = Data(bytes: baseAddress, count: dataSize)

        return data
    }

    /// Reset buffer to initial state.
    ///
    /// Clears all accumulated data and keyframes. Call this when starting
    /// a new recording or when canceling the current recording.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        _accumulatedData = Data()
        _keyframes = []
        _resolution = .zero
        _isRecording = false
        _recordingStartTimestamp = nil

        Self.logger.info("DepthKeyframeBuffer reset")
    }

    /// Finalize recording and produce compressed DepthKeyframeData.
    ///
    /// Compresses the accumulated depth data using gzip and creates
    /// the final DepthKeyframeData structure. This should be called
    /// when video recording completes (normal or interrupted).
    ///
    /// - Returns: Complete `DepthKeyframeData` with compressed blob, or `nil` if no keyframes
    /// - Note: Compression happens synchronously and may take 100-500ms for full 15s video
    public func finalize() -> DepthKeyframeData? {
        let startTime = CFAbsoluteTimeGetCurrent()

        lock.lock()
        let keyframes = _keyframes
        let resolution = _resolution
        let uncompressedData = _accumulatedData
        _isRecording = false
        lock.unlock()

        // Return nil if no keyframes
        guard !keyframes.isEmpty else {
            Self.logger.warning("Finalize called with no keyframes")
            return nil
        }

        let uncompressedSize = uncompressedData.count

        // Compress the data
        let compressedData: Data
        do {
            compressedData = try compressBlob(uncompressedData)
        } catch {
            Self.logger.error("Compression failed: \(error.localizedDescription)")
            // Return uncompressed data as fallback
            compressedData = uncompressedData
        }

        let compressionTime = CFAbsoluteTimeGetCurrent() - startTime
        let ratio = Double(uncompressedSize) / Double(max(compressedData.count, 1))

        Self.logger.info("DepthKeyframeBuffer finalized: \(keyframes.count) keyframes, \(uncompressedSize) -> \(compressedData.count) bytes (ratio: \(String(format: "%.1f", ratio))x, time: \(String(format: "%.0f", compressionTime * 1000))ms)")

        return DepthKeyframeData(
            frames: keyframes,
            resolution: resolution,
            compressedBlob: compressedData,
            uncompressedSize: uncompressedSize
        )
    }

    // MARK: - Private Methods

    /// Compress data using gzip (COMPRESSION_ZLIB).
    ///
    /// - Parameter data: Raw data to compress
    /// - Returns: Gzip-compressed data
    /// - Throws: `DepthKeyframeError.compressionFailed` if compression fails
    private func compressBlob(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        // Allocate destination buffer (same size as source - compression will shrink it)
        let destinationBufferSize = data.count
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePointer = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }

            return compression_encode_buffer(
                destinationBuffer,
                destinationBufferSize,
                sourcePointer,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            Self.logger.error("compression_encode_buffer returned 0")
            throw DepthKeyframeError.compressionFailed
        }

        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Decompress gzip data (for testing/verification).
    ///
    /// - Parameters:
    ///   - data: Compressed data
    ///   - uncompressedSize: Expected uncompressed size
    /// - Returns: Decompressed data
    /// - Throws: `DepthKeyframeError.compressionFailed` if decompression fails
    public func decompressBlob(_ data: Data, uncompressedSize: Int) throws -> Data {
        guard !data.isEmpty, uncompressedSize > 0 else {
            return Data()
        }

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePointer = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }

            return compression_decode_buffer(
                destinationBuffer,
                uncompressedSize,
                sourcePointer,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize == uncompressedSize else {
            Self.logger.error("Decompression size mismatch: expected \(uncompressedSize), got \(decompressedSize)")
            throw DepthKeyframeError.compressionFailed
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}
