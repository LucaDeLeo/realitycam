//
//  VideoProcessingPipeline.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  Pipeline for processing video recordings into upload-ready packages.
//

import Foundation
import AVFoundation
import UIKit
import os.log

// MARK: - VideoProcessingError

/// Errors that can occur during video processing.
public enum VideoProcessingError: Error, LocalizedError {
    /// Depth data compression failed
    case compressionFailed

    /// Thumbnail generation failed
    case thumbnailGenerationFailed

    /// JSON serialization failed
    case serializationFailed(Error)

    /// Invalid input (missing required data)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress depth data"
        case .thumbnailGenerationFailed:
            return "Failed to generate video thumbnail"
        case .serializationFailed(let error):
            return "Failed to serialize data: \(error.localizedDescription)"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        }
    }
}

// MARK: - VideoProcessingPipeline

/// Pipeline for processing video recordings into upload-ready packages.
///
/// Takes `VideoRecordingResult` and produces `ProcessedVideoCapture` containing:
/// - Video file (already encoded)
/// - Compressed depth data (gzip, already done by DepthKeyframeBuffer)
/// - Serialized hash chain (JSON with base64 hashes)
/// - Metadata with attestation (JSON with snake_case keys)
/// - Thumbnail (JPEG 640x360)
///
/// ## Performance Targets
/// - Total processing time: < 5 seconds for 15s video
/// - Memory: No additional spike above 50MB
/// - UI remains responsive (processing on background queue)
///
/// ## Key Design
/// - Depth data is already compressed by DepthKeyframeBuffer.finalize()
/// - VideoMetadata already has snake_case JSON serialization
/// - HashChainData needs custom serialization for base64 hashes
/// - Graceful degradation: continues if optional components fail
///
/// ## Usage
/// ```swift
/// let pipeline = VideoProcessingPipeline()
/// let processed = try await pipeline.process(result: recordingResult) { progress in
///     print("Progress: \(Int(progress * 100))%")
/// }
/// ```
public final class VideoProcessingPipeline: Sendable {

    // MARK: - Properties

    /// Logger for processing events
    private static let logger = Logger(subsystem: "com.rial.app", category: "videoprocessing")

    // MARK: - Progress Stages

    /// Progress stages and their weights for accurate progress reporting.
    ///
    /// Weights adjusted to match actual processing time:
    /// - Depth: Near-instant (pre-compressed by DepthKeyframeBuffer)
    /// - Thumbnail: Heaviest (AVAssetImageGenerator disk I/O + decode)
    /// - Serialization: Moderate (JSON encoding with base64)
    /// - Assembly: Minimal (struct creation)
    private enum ProcessingStage: CaseIterable {
        case depthCompression   // 5% (already compressed, just pass-through)
        case thumbnail          // 50% (AVAssetImageGenerator disk I/O)
        case hashChainSerialize // 25% (JSON encoding + base64)
        case metadataSerialize  // 15% (JSON encoding)
        case assembly           // 5% (final assembly)

        var weight: Double {
            switch self {
            case .depthCompression: return 0.05
            case .thumbnail: return 0.50
            case .hashChainSerialize: return 0.25
            case .metadataSerialize: return 0.15
            case .assembly: return 0.05
            }
        }

        var startProgress: Double {
            let allCases = ProcessingStage.allCases
            let index = allCases.firstIndex(of: self) ?? 0
            return allCases[..<index].reduce(0) { $0 + $1.weight }
        }
    }

    // MARK: - Initialization

    public init() {
        Self.logger.debug("VideoProcessingPipeline initialized")
    }

    // MARK: - Public Methods

    /// Process a video recording result into an upload-ready package.
    ///
    /// - Parameters:
    ///   - result: `VideoRecordingResult` from recording session
    ///   - onProgress: Progress callback (0.0 - 1.0), dispatched to main thread
    /// - Returns: `ProcessedVideoCapture` ready for upload
    /// - Throws: `VideoProcessingError` if critical processing fails
    public func process(
        result: VideoRecordingResult,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> ProcessedVideoCapture {
        let startTime = CFAbsoluteTimeGetCurrent()

        Self.logger.info("Processing video: \(result.frameCount) frames, \(result.depthKeyframeCount) depth keyframes, \(String(format: "%.1f", result.duration))s")

        // Helper to report progress on main thread
        let reportProgress: (Double) -> Void = { progress in
            if let callback = onProgress {
                DispatchQueue.main.async {
                    callback(progress)
                }
            }
        }

        // Report initial progress
        reportProgress(0.0)

        // Stage 1: Depth data (10%) - already compressed by DepthKeyframeBuffer
        let compressedDepth: Data
        if let depthData = result.depthKeyframeData {
            Self.logger.debug("Using pre-compressed depth data: \(depthData.compressedBlob.count) bytes, ratio: \(String(format: "%.1f", depthData.compressionRatio))x")
            compressedDepth = depthData.compressedBlob
        } else {
            Self.logger.warning("No depth keyframe data available")
            compressedDepth = Data()
        }
        reportProgress(ProcessingStage.depthCompression.startProgress + ProcessingStage.depthCompression.weight)

        // Stage 2: Generate thumbnail (30%)
        let thumbnailData: Data
        do {
            thumbnailData = try await generateThumbnail(from: result.videoURL)
            Self.logger.debug("Thumbnail generated: \(thumbnailData.count) bytes")
        } catch {
            Self.logger.warning("Thumbnail generation failed, using empty data: \(error.localizedDescription)")
            thumbnailData = Data()  // Continue without thumbnail (graceful degradation)
        }
        reportProgress(ProcessingStage.thumbnail.startProgress + ProcessingStage.thumbnail.weight)

        // Stage 3: Serialize hash chain (30%)
        let hashChainJSON: Data
        if let hashChain = result.hashChainData {
            do {
                hashChainJSON = try serializeHashChain(hashChain)
                Self.logger.debug("Hash chain serialized: \(hashChainJSON.count) bytes, \(hashChain.frameCount) hashes")
            } catch {
                Self.logger.warning("Hash chain serialization failed: \(error.localizedDescription)")
                hashChainJSON = Data()
            }
        } else {
            Self.logger.warning("No hash chain data available")
            hashChainJSON = Data()
        }
        reportProgress(ProcessingStage.hashChainSerialize.startProgress + ProcessingStage.hashChainSerialize.weight)

        // Stage 4: Serialize metadata (20%)
        let metadataJSON: Data
        do {
            metadataJSON = try serializeMetadata(result.metadata)
            Self.logger.debug("Metadata serialized: \(metadataJSON.count) bytes")
        } catch {
            Self.logger.error("Metadata serialization failed: \(error.localizedDescription)")
            throw VideoProcessingError.serializationFailed(error)
        }
        reportProgress(ProcessingStage.metadataSerialize.startProgress + ProcessingStage.metadataSerialize.weight)

        // Stage 5: Assembly (10%)
        let processed = ProcessedVideoCapture(
            videoURL: result.videoURL,
            compressedDepthData: compressedDepth,
            hashChainJSON: hashChainJSON,
            metadataJSON: metadataJSON,
            thumbnailData: thumbnailData,
            createdAt: result.startedAt,
            status: .pendingUpload,
            frameCount: result.frameCount,
            depthKeyframeCount: result.depthKeyframeCount,
            durationMs: Int64(result.duration * 1000),
            isPartial: result.isPartial
        )
        reportProgress(1.0)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("Video processing complete: \(String(format: "%.2f", totalTime))s, total size: \(processed.totalSizeFormatted)")

        // Warn if exceeded target
        if totalTime > 5.0 {
            Self.logger.warning("Processing exceeded 5s target: \(String(format: "%.2f", totalTime))s")
        }

        return processed
    }

    // MARK: - Component Methods

    /// Generate thumbnail from video first frame.
    ///
    /// Extracts the first frame from the video and converts it to a JPEG
    /// thumbnail at 640x360 resolution with 80% quality.
    ///
    /// - Parameter videoURL: URL to video file
    /// - Returns: JPEG data (640x360, 80% quality)
    /// - Throws: `VideoProcessingError.thumbnailGenerationFailed`
    public func generateThumbnail(from videoURL: URL) async throws -> Data {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let time = CMTime(seconds: 0, preferredTimescale: 600)

        do {
            let cgImage: CGImage
            if #available(iOS 16.0, *) {
                cgImage = try await generator.image(at: time).image
            } else {
                // Fallback for iOS 15
                cgImage = try await withCheckedThrowingContinuation { continuation in
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let image = image {
                            continuation.resume(returning: image)
                        } else {
                            continuation.resume(throwing: VideoProcessingError.thumbnailGenerationFailed)
                        }
                    }
                }
            }

            let uiImage = UIImage(cgImage: cgImage)

            guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
                throw VideoProcessingError.thumbnailGenerationFailed
            }

            Self.logger.info("Generated thumbnail: \(jpegData.count) bytes (\(Int(uiImage.size.width))x\(Int(uiImage.size.height)))")
            return jpegData

        } catch let error as VideoProcessingError {
            throw error
        } catch {
            Self.logger.error("Thumbnail generation failed: \(error.localizedDescription)")
            throw VideoProcessingError.thumbnailGenerationFailed
        }
    }

    /// Serialize hash chain to JSON.
    ///
    /// Produces JSON with base64-encoded hashes for backend compatibility:
    /// ```json
    /// {
    ///   "frame_hashes": ["base64...", "base64...", ...],
    ///   "checkpoints": [...],
    ///   "final_hash": "base64...",
    ///   "frame_count": 450,
    ///   "checkpoint_count": 3
    /// }
    /// ```
    ///
    /// - Parameter chain: HashChainData from recording
    /// - Returns: JSON data with snake_case keys
    /// - Throws: `VideoProcessingError.serializationFailed`
    public func serializeHashChain(_ chain: HashChainData) throws -> Data {
        do {
            // Create serializable structure with base64-encoded hashes
            let serializable = SerializableHashChain(
                frameHashes: chain.frameHashes.map { $0.base64EncodedString() },
                checkpoints: chain.checkpoints.map { checkpoint in
                    SerializableCheckpoint(
                        index: checkpoint.index,
                        frameNumber: checkpoint.frameNumber,
                        hash: checkpoint.hash.base64EncodedString(),
                        timestamp: checkpoint.timestamp
                    )
                },
                finalHash: chain.finalHash.base64EncodedString(),
                frameCount: chain.frameCount,
                checkpointCount: chain.checkpointCount
            )

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]

            return try encoder.encode(serializable)

        } catch {
            Self.logger.error("Hash chain serialization failed: \(error.localizedDescription)")
            throw VideoProcessingError.serializationFailed(error)
        }
    }

    /// Serialize metadata to JSON.
    ///
    /// Uses VideoMetadata's built-in Codable with custom encode()
    /// that handles snake_case keys and ISO8601 date formatting.
    ///
    /// - Parameter metadata: VideoMetadata from recording
    /// - Returns: JSON data
    /// - Throws: `VideoProcessingError.serializationFailed`
    public func serializeMetadata(_ metadata: VideoMetadata) throws -> Data {
        do {
            let encoder = JSONEncoder()
            // Note: VideoMetadata has custom encode() that handles snake_case and ISO8601
            return try encoder.encode(metadata)

        } catch {
            Self.logger.error("Metadata serialization failed: \(error.localizedDescription)")
            throw VideoProcessingError.serializationFailed(error)
        }
    }
}

// MARK: - Serializable Types

/// Serializable hash chain for JSON encoding.
///
/// Converts Data hashes to base64 strings for JSON compatibility.
private struct SerializableHashChain: Codable {
    let frameHashes: [String]
    let checkpoints: [SerializableCheckpoint]
    let finalHash: String
    let frameCount: Int
    let checkpointCount: Int
}

/// Serializable checkpoint for JSON encoding.
private struct SerializableCheckpoint: Codable {
    let index: Int
    let frameNumber: Int
    let hash: String
    let timestamp: TimeInterval
}

// MARK: - Deferred Features (Story 7-8)

// TODO: [Story 7-8] CoreData Persistence (MEDIUM-1)
// CoreData entity for video captures will be implemented in Story 7-8 when upload flow is built.
// Interface contract: ProcessedVideoCapture will be saved via CaptureStore extension methods.
// Expected methods:
//   - func saveVideoCapture(_ capture: ProcessedVideoCapture) async throws
//   - func loadVideoCapture(id: UUID) async throws -> ProcessedVideoCapture?
//   - func updateVideoCaptureStatus(_ id: UUID, status: VideoCaptureStatus) async throws
// The ProcessedVideoCapture model is already designed to be CoreData-compatible.

// TODO: [Story 7-8] VideoRecordingSession Integration (MEDIUM-2)
// Integration with VideoRecordingSession.stopRecording() will be done in Story 7-8.
// VideoRecordingSession will call pipeline.process() and save result to CoreData.
// This separation keeps recording and processing concerns independent.

// TODO: [MVP Out-of-Scope] Progress Cancellation (MEDIUM-3)
// Cancellation support for pipeline processing is out-of-scope for MVP.
// For future implementation:
//   - Accept CancellationToken parameter in process()
//   - Check cancellation between stages
//   - Clean up partial results on cancellation
