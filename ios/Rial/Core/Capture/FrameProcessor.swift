//
//  FrameProcessor.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Frame processing pipeline for converting ARKit frames to upload-ready format.
//

import Foundation
import ARKit
import CoreImage
import CoreLocation
import Compression
import UIKit
import os.log

// MARK: - FrameProcessor

/// Processes ARKit frames into upload-ready CaptureData format.
///
/// FrameProcessor converts ARFrame (RGB photo + LiDAR depth) into structured
/// CaptureData with JPEG compression, depth map compression, SHA-256 hashing,
/// and metadata assembly.
///
/// ## Performance Targets
/// - Base processing: < 200ms (P95)
/// - JPEG conversion: < 100ms
/// - Depth compression: < 50ms
/// - SHA-256 hash: < 30ms
/// - Detection (optional): < 200ms additional (parallel)
/// - Total with detection: < 500ms
///
/// ## Usage
/// ```swift
/// let processor = FrameProcessor()
/// let frame = captureSession.captureCurrentFrame()!
///
/// // Without detection
/// let captureData = try await processor.process(frame, location: currentLocation)
///
/// // With multi-signal detection (Story 9-6)
/// let captureData = try await processor.process(frame, location: currentLocation, runDetection: true)
/// // captureData.detectionResults contains moire, texture, artifacts, and aggregated confidence
/// ```
///
/// - Important: Processing runs on background queues to avoid blocking UI.
public final class FrameProcessor: @unchecked Sendable {

    // MARK: - Properties

    /// Logger for frame processing events
    private static let logger = Logger(subsystem: "app.rial", category: "frameprocessor")

    /// Reusable CIContext for JPEG conversion (thread-safe)
    private let ciContext: CIContext

    /// JPEG compression quality (0.0 - 1.0)
    public let jpegQuality: CGFloat

    /// Processing timeout in seconds
    public let processingTimeout: TimeInterval

    // MARK: - Initialization

    /// Creates a new FrameProcessor instance.
    ///
    /// - Parameters:
    ///   - jpegQuality: JPEG compression quality (default: 0.85)
    ///   - processingTimeout: Maximum processing time before timeout (default: 1.0s)
    public init(
        jpegQuality: CGFloat = 0.85,
        processingTimeout: TimeInterval = 1.0
    ) {
        self.jpegQuality = jpegQuality
        self.processingTimeout = processingTimeout

        // Create CIContext optimized for JPEG rendering
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true
        ])

        Self.logger.debug("FrameProcessor initialized with JPEG quality: \(jpegQuality)")
    }

    // MARK: - Public Methods

    /// Process an ARFrame into upload-ready CaptureData.
    ///
    /// Converts the ARFrame's RGB photo to JPEG, compresses the depth map,
    /// computes SHA-256 hash, assembles metadata, and optionally runs
    /// multi-signal detection (Story 9-6).
    ///
    /// - Parameters:
    ///   - frame: ARFrame with capturedImage and sceneDepth
    ///   - location: Optional GPS location (nil if unavailable/denied)
    ///   - runDetection: If true, runs moire/texture/artifact detection (default: false)
    /// - Returns: Complete CaptureData ready for storage and upload
    /// - Throws: `FrameProcessingError` if processing fails
    ///
    /// - Note: This method runs on a background queue and is async.
    /// - Note: When `runDetection` is true, processing time increases by ~200ms but
    ///         detection runs in parallel with base processing when possible.
    public func process(_ frame: ARFrame, location: CLLocation?, runDetection: Bool = false) async throws -> CaptureData {
        let startTime = CFAbsoluteTimeGetCurrent()
        Self.logger.info("Starting frame processing (detection=\(runDetection))")

        // Validate depth data is available
        guard let depthData = frame.sceneDepth, let depthBuffer = Optional(depthData.depthMap) else {
            Self.logger.error("Frame missing depth data")
            throw FrameProcessingError.noDepthData
        }

        // Process in parallel where possible
        async let jpegTask = convertToJPEG(frame.capturedImage)

        // Depth compression can run synchronously while JPEG converts
        let compressedDepth = try compressDepth(depthBuffer)

        // Wait for JPEG conversion
        let jpegData = try await jpegTask

        // Compute hash of JPEG data
        let photoHash = CryptoService.sha256(jpegData)

        // Build metadata
        let metadata = buildMetadata(
            frame: frame,
            jpeg: jpegData,
            depthBuffer: depthBuffer,
            location: location,
            photoHash: photoHash
        )

        // Run detection if enabled (Story 9-6)
        var detectionResults: DetectionResults?
        if runDetection {
            let detectionStartTime = CFAbsoluteTimeGetCurrent()
            detectionResults = await DetectionOrchestrator.shared.runAllDetections(jpegData: jpegData)
            let detectionTime = CFAbsoluteTimeGetCurrent() - detectionStartTime

            Self.logger.info("""
                Detection completed in \(String(format: "%.1f", detectionTime * 1000))ms:
                hasResults=\(detectionResults?.hasAnyResults ?? false),
                confidenceLevel=\(detectionResults?.confidenceLevel?.rawValue ?? "nil")
                """)
        }

        // Construct final CaptureData (assertion added separately by CaptureAssertionService)
        // Note: frame.timestamp is seconds since device boot, NOT Unix timestamp
        // Use Date() for current wall-clock time
        let captureData = CaptureData(
            jpeg: jpegData,
            depth: compressedDepth,
            metadata: metadata,
            assertion: nil,
            assertionStatus: .none,
            assertionAttemptCount: 0,
            timestamp: Date(),
            detectionResults: detectionResults
        )

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("Frame processing complete in \(String(format: "%.1f", processingTime * 1000))ms - JPEG: \(jpegData.count) bytes, Depth: \(compressedDepth.count) bytes, Detection: \(detectionResults != nil ? "included" : "skipped")")

        // Warn if processing exceeded target (200ms without detection, 500ms with)
        let targetTime = runDetection ? 0.5 : 0.2
        if processingTime > targetTime {
            Self.logger.warning("Processing exceeded \(Int(targetTime * 1000))ms target: \(String(format: "%.1f", processingTime * 1000))ms")
        }

        return captureData
    }

    // MARK: - JPEG Conversion

    /// Convert CVPixelBuffer to JPEG data.
    ///
    /// Uses CIContext for hardware-accelerated JPEG encoding.
    /// Applies proper orientation correction for ARKit's camera output.
    ///
    /// - Parameter pixelBuffer: RGB pixel buffer from ARFrame.capturedImage
    /// - Returns: JPEG data (typically 2-4MB for 12MP photo)
    /// - Throws: `FrameProcessingError.jpegConversionFailed` if conversion fails
    private func convertToJPEG(_ pixelBuffer: CVPixelBuffer) async throws -> Data {
        let startTime = CFAbsoluteTimeGetCurrent()

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // ARKit's capturedImage needs orientation correction.
        // Apply 90° clockwise rotation for portrait orientation.
        ciImage = ciImage.oriented(.right)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            Self.logger.error("Failed to create sRGB color space")
            throw FrameProcessingError.jpegConversionFailed
        }

        guard let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality]
        ) else {
            Self.logger.error("JPEG representation failed")
            throw FrameProcessingError.jpegConversionFailed
        }

        let conversionTime = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.debug("JPEG conversion: \(String(format: "%.1f", conversionTime * 1000))ms, size: \(jpegData.count) bytes")

        return jpegData
    }

    // MARK: - Depth Compression

    /// Compress depth map using zlib compression.
    ///
    /// Extracts raw Float32 depth values and compresses with zlib.
    /// Typical compression ratio is 3-5x.
    ///
    /// - Parameter buffer: Depth CVPixelBuffer from ARFrame.sceneDepth.depthMap
    /// - Returns: Zlib-compressed depth data
    /// - Throws: `FrameProcessingError.depthCompressionFailed` if compression fails
    private func compressDepth(_ buffer: CVPixelBuffer) throws -> Data {
        let startTime = CFAbsoluteTimeGetCurrent()

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            Self.logger.error("Failed to get depth buffer base address")
            throw FrameProcessingError.depthCompressionFailed
        }

        let dataSize = width * height * MemoryLayout<Float>.size
        let rawData = Data(bytes: baseAddress, count: dataSize)

        // Compress using zlib
        let compressedData: Data
        do {
            compressedData = try (rawData as NSData).compressed(using: .zlib) as Data
        } catch {
            Self.logger.error("Zlib compression failed: \(error.localizedDescription)")
            throw FrameProcessingError.depthCompressionFailed
        }

        let compressionTime = CFAbsoluteTimeGetCurrent() - startTime
        let ratio = Double(rawData.count) / Double(compressedData.count)
        Self.logger.debug("Depth compression: \(String(format: "%.1f", compressionTime * 1000))ms, \(rawData.count) -> \(compressedData.count) bytes (ratio: \(String(format: "%.1f", ratio))x)")

        return compressedData
    }

    // MARK: - Metadata Assembly

    /// Build capture metadata from frame components.
    ///
    /// - Parameters:
    ///   - frame: Source ARFrame
    ///   - jpeg: JPEG data for size information
    ///   - depthBuffer: Depth buffer for dimensions
    ///   - location: Optional GPS location
    ///   - photoHash: Pre-computed SHA-256 hash
    /// - Returns: Complete CaptureMetadata
    private func buildMetadata(
        frame: ARFrame,
        jpeg: Data,
        depthBuffer: CVPixelBuffer,
        location: CLLocation?,
        photoHash: String
    ) -> CaptureMetadata {
        let deviceModel = UIDevice.current.model

        let locationData = location.map { LocationData(from: $0) }

        let depthDimensions = DepthDimensions(
            width: CVPixelBufferGetWidth(depthBuffer),
            height: CVPixelBufferGetHeight(depthBuffer)
        )

        // Note: frame.timestamp is seconds since device boot, NOT Unix timestamp
        // Use Date() for current wall-clock time
        return CaptureMetadata(
            capturedAt: Date(),
            deviceModel: deviceModel,
            photoHash: photoHash,
            location: locationData,
            depthMapDimensions: depthDimensions
        )
    }
}

// MARK: - FrameProcessingError

/// Errors that can occur during frame processing.
public enum FrameProcessingError: Error, LocalizedError, Equatable {
    /// ARFrame missing sceneDepth data (LiDAR not available or not configured)
    case noDepthData

    /// CVPixelBuffer to JPEG conversion failed
    case jpegConversionFailed

    /// Depth map zlib compression failed
    case depthCompressionFailed

    /// Processing exceeded timeout threshold
    case processingTimeout

    /// Invalid pixel buffer format
    case invalidPixelFormat

    public var errorDescription: String? {
        switch self {
        case .noDepthData:
            return "Frame missing depth data (LiDAR required)"
        case .jpegConversionFailed:
            return "Failed to convert photo to JPEG format"
        case .depthCompressionFailed:
            return "Failed to compress depth map"
        case .processingTimeout:
            return "Frame processing exceeded timeout"
        case .invalidPixelFormat:
            return "Invalid pixel buffer format"
        }
    }
}

// MARK: - Utility Extensions

extension CVPixelBuffer {
    /// Get pixel buffer dimensions as tuple
    var dimensions: (width: Int, height: Int) {
        (CVPixelBufferGetWidth(self), CVPixelBufferGetHeight(self))
    }

    /// Get pixel format type
    var pixelFormatType: OSType {
        CVPixelBufferGetPixelFormatType(self)
    }
}
