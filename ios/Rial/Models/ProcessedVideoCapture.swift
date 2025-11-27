//
//  ProcessedVideoCapture.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Processed video capture ready for upload to backend.
//

import Foundation

// MARK: - ProcessedVideoCapture

/// Processed video capture ready for upload.
///
/// Contains all components needed for backend video verification:
/// - Video file (already encoded by AVAssetWriter)
/// - Compressed depth data (gzip)
/// - Serialized hash chain (JSON)
/// - Metadata with attestation (JSON)
/// - Thumbnail (JPEG)
///
/// ## Usage
/// ```swift
/// let pipeline = VideoProcessingPipeline()
/// let processed = try await pipeline.process(result: videoResult) { progress in
///     updateUI(progress: progress)
/// }
/// // processed.status == .pendingUpload
/// ```
public struct ProcessedVideoCapture: Identifiable, Sendable {
    /// Unique identifier for this capture
    public let id: UUID

    /// URL to local video file (H.264/HEVC encoded)
    public let videoURL: URL

    /// Gzip-compressed depth keyframe data (already compressed by DepthKeyframeBuffer)
    public let compressedDepthData: Data

    /// Serialized hash chain as JSON (base64-encoded hashes)
    public let hashChainJSON: Data

    /// Serialized metadata with attestation as JSON (snake_case keys)
    public let metadataJSON: Data

    /// JPEG thumbnail (640x360, 80% quality)
    public let thumbnailData: Data

    /// Capture creation timestamp
    public let createdAt: Date

    /// Current upload status
    public var status: VideoCaptureStatus

    /// Frame count from recording (30fps)
    public let frameCount: Int

    /// Depth keyframe count (10fps)
    public let depthKeyframeCount: Int

    /// Duration in milliseconds
    public let durationMs: Int64

    /// Whether this is a partial (interrupted) recording
    public let isPartial: Bool

    /// Creates a new ProcessedVideoCapture.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - videoURL: URL to local video file
    ///   - compressedDepthData: Gzip-compressed depth data
    ///   - hashChainJSON: Serialized hash chain JSON
    ///   - metadataJSON: Serialized metadata JSON
    ///   - thumbnailData: JPEG thumbnail data
    ///   - createdAt: Capture creation timestamp (defaults to now)
    ///   - status: Upload status (defaults to .pendingUpload)
    ///   - frameCount: Total frames captured at 30fps
    ///   - depthKeyframeCount: Depth keyframes captured at 10fps
    ///   - durationMs: Duration in milliseconds
    ///   - isPartial: Whether recording was interrupted
    public init(
        id: UUID = UUID(),
        videoURL: URL,
        compressedDepthData: Data,
        hashChainJSON: Data,
        metadataJSON: Data,
        thumbnailData: Data,
        createdAt: Date = Date(),
        status: VideoCaptureStatus = .pendingUpload,
        frameCount: Int,
        depthKeyframeCount: Int,
        durationMs: Int64,
        isPartial: Bool
    ) {
        self.id = id
        self.videoURL = videoURL
        self.compressedDepthData = compressedDepthData
        self.hashChainJSON = hashChainJSON
        self.metadataJSON = metadataJSON
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
        self.status = status
        self.frameCount = frameCount
        self.depthKeyframeCount = depthKeyframeCount
        self.durationMs = durationMs
        self.isPartial = isPartial
    }

    /// Total size of all data in bytes (approximate for upload estimation).
    ///
    /// Includes video file size, compressed depth, hash chain JSON,
    /// metadata JSON, and thumbnail.
    public var totalSizeBytes: Int {
        let videoSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
        return videoSize + compressedDepthData.count + hashChainJSON.count + metadataJSON.count + thumbnailData.count
    }

    /// Human-readable size string (e.g., "15.2 MB").
    public var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSizeBytes), countStyle: .file)
    }

    /// Duration in seconds (convenience).
    public var durationSeconds: TimeInterval {
        TimeInterval(durationMs) / 1000.0
    }

    /// Whether the capture has valid depth data.
    public var hasDepthData: Bool {
        !compressedDepthData.isEmpty
    }

    /// Whether the capture has a thumbnail.
    public var hasThumbnail: Bool {
        !thumbnailData.isEmpty
    }

    /// Whether the capture has hash chain data.
    public var hasHashChain: Bool {
        !hashChainJSON.isEmpty
    }
}

// MARK: - VideoCaptureStatus

/// Status of a video capture in the processing/upload queue.
///
/// Tracks the lifecycle from processing through upload completion.
public enum VideoCaptureStatus: String, Codable, Sendable, CaseIterable {
    /// Video is being processed (compression, serialization)
    case processing

    /// Processing complete, ready for upload
    case pendingUpload = "pending_upload"

    /// Currently uploading to backend
    case uploading

    /// Upload paused (network unavailable, app backgrounded)
    case paused

    /// Upload completed successfully
    case uploaded

    /// Processing or upload failed
    case failed

    /// Whether this status indicates the capture is complete.
    public var isComplete: Bool {
        self == .uploaded
    }

    /// Whether this status indicates work is in progress.
    public var isInProgress: Bool {
        self == .processing || self == .uploading
    }

    /// Whether this capture can be retried.
    public var canRetry: Bool {
        self == .failed || self == .paused
    }
}
