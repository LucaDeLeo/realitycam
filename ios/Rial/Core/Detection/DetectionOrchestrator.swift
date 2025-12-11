//
//  DetectionOrchestrator.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Orchestrates parallel execution of all detection services (Story 9-6).
//  Aggregates results via ConfidenceAggregator with enhanced cross-validation.
//

import Foundation
import CoreImage
import CoreVideo
import ImageIO
import os.log

// MARK: - DetectionOrchestrator

/// Orchestrates parallel execution of multi-signal detection services.
///
/// This service runs Moire, Texture, and Artifact detection in parallel,
/// then aggregates results via ConfidenceAggregator with enhanced cross-validation.
///
/// ## Algorithm Overview
/// 1. Extract CGImage from JPEG data or accept CGImage directly
/// 2. Run three detection services in parallel (async let)
/// 3. Aggregate results via ConfidenceAggregator with enableEnhancedCrossValidation=true
/// 4. Return combined DetectionResults
///
/// ## Performance Targets
/// - Total detection time: <200ms (parallel execution)
/// - Individual service targets:
///   - Moire: <30ms
///   - Texture: <50ms
///   - Artifacts: <20ms
///   - Aggregation + Cross-validation: <15ms
///
/// ## Graceful Degradation
/// If individual services fail, others continue:
/// - Partial results are returned
/// - Aggregator handles nil inputs appropriately
/// - No exceptions thrown from public API
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because:
/// 1. It has no mutable state (stateless orchestration)
/// 2. All work delegated to thread-safe detection services
/// 3. Public API uses async/await
///
/// ## Usage
/// ```swift
/// let results = await DetectionOrchestrator.shared.runAllDetections(image: cgImage)
/// if results.hasAnyResults {
///     captureData.detectionResults = results
/// }
/// ```
public final class DetectionOrchestrator: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance.
    public static let shared = DetectionOrchestrator()

    // MARK: - Properties

    /// Logger for detection orchestration events.
    private static let logger = Logger(subsystem: "app.rial", category: "detection-orchestrator")

    /// Signpost log for performance tracking.
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    // MARK: - Initialization

    /// Private initializer for singleton pattern.
    private init() {
        Self.logger.debug("DetectionOrchestrator initialized")
    }

    // MARK: - Public API

    /// Runs all detection services in parallel and aggregates results.
    ///
    /// This is the primary entry point for multi-signal detection.
    /// Services run concurrently and results are aggregated with enhanced cross-validation.
    ///
    /// - Parameter image: CGImage to analyze
    /// - Returns: Combined DetectionResults with all available detection outputs
    ///
    /// - Note: If all services fail, returns DetectionResults.unavailable()
    public func runAllDetections(image: CGImage) async -> DetectionResults {
        let startTime = CFAbsoluteTimeGetCurrent()
        let signpostID = OSSignpostID(log: Self.signpostLog)

        os_signpost(.begin, log: Self.signpostLog, name: "DetectionOrchestration", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "DetectionOrchestration", signpostID: signpostID)
        }

        Self.logger.info("Starting parallel detection for image \(image.width)x\(image.height)")

        // Run all detection services in parallel
        async let moireTask = runMoireDetection(image: image)
        async let textureTask = runTextureClassification(image: image)
        async let artifactsTask = runArtifactDetection(image: image)

        // Await all results
        let moireResult = await moireTask
        let textureResult = await textureTask
        let artifactsResult = await artifactsTask

        // Log individual results
        Self.logger.debug("""
            Detection results:
            moire=\(moireResult != nil ? "available" : "nil"),
            texture=\(textureResult != nil ? "available" : "nil"),
            artifacts=\(artifactsResult != nil ? "available" : "nil")
            """)

        // Aggregate results with enhanced cross-validation
        // Note: depth is nil here - depth analysis is handled separately by FrameProcessor/LiDAR
        let aggregated = await ConfidenceAggregator.shared.aggregate(
            depth: nil,
            moire: moireResult,
            texture: textureResult,
            artifacts: artifactsResult,
            enableEnhancedCrossValidation: true
        )

        let totalTimeMs = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        Self.logger.info("""
            Detection orchestration complete in \(totalTimeMs)ms:
            overallConfidence=\(String(format: "%.3f", aggregated.overallConfidence)),
            level=\(aggregated.confidenceLevel.rawValue),
            status=\(aggregated.status.rawValue)
            """)

        // Warn if exceeded target
        if totalTimeMs > DetectionOrchestratorConstants.targetTimeMs {
            Self.logger.warning("""
                Detection exceeded target time: \(totalTimeMs)ms > \(DetectionOrchestratorConstants.targetTimeMs)ms
                """)
        }

        return DetectionResults(
            moire: moireResult,
            texture: textureResult,
            artifacts: artifactsResult,
            aggregatedConfidence: aggregated,
            crossValidation: aggregated.crossValidation,
            totalProcessingTimeMs: totalTimeMs
        )
    }

    /// Runs all detection services from JPEG data.
    ///
    /// Convenience method that extracts CGImage from JPEG data before detection.
    ///
    /// - Parameter jpegData: JPEG image data
    /// - Returns: Combined DetectionResults, or unavailable if image extraction fails
    public func runAllDetections(jpegData: Data) async -> DetectionResults {
        guard let image = extractCGImage(from: jpegData) else {
            Self.logger.error("Failed to extract CGImage from JPEG data")
            return .unavailable()
        }
        return await runAllDetections(image: image)
    }

    /// Runs all detection services from CVPixelBuffer.
    ///
    /// Convenience method for integration with ARKit frame processing.
    ///
    /// - Parameter pixelBuffer: CVPixelBuffer from ARFrame.capturedImage
    /// - Returns: Combined DetectionResults, or unavailable if conversion fails
    public func runAllDetections(pixelBuffer: CVPixelBuffer) async -> DetectionResults {
        guard let image = extractCGImage(from: pixelBuffer) else {
            Self.logger.error("Failed to extract CGImage from pixel buffer")
            return .unavailable()
        }
        return await runAllDetections(image: image)
    }

    // MARK: - Private Detection Methods

    /// Runs moire detection with error handling.
    private func runMoireDetection(image: CGImage) async -> MoireAnalysisResult? {
        let startTime = CFAbsoluteTimeGetCurrent()

        let result = await MoireDetectionService.shared.analyze(image: image)

        let timeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        Self.logger.debug("Moire detection completed in \(timeMs)ms, detected=\(result.detected)")

        // Return nil for unavailable/failed status
        guard result.status == .completed else {
            Self.logger.warning("Moire detection unavailable: status=\(result.status.rawValue)")
            return nil
        }

        return result
    }

    /// Runs texture classification with error handling.
    private func runTextureClassification(image: CGImage) async -> TextureClassificationResult? {
        let startTime = CFAbsoluteTimeGetCurrent()

        let result = await TextureClassificationService.shared.classify(image: image)

        let timeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        Self.logger.debug("Texture classification completed in \(timeMs)ms, classification=\(result.classification.rawValue)")

        // Return nil for unavailable/error status
        guard result.status == .success else {
            Self.logger.warning("Texture classification unavailable: status=\(result.status.rawValue)")
            return nil
        }

        return result
    }

    /// Runs artifact detection with error handling.
    private func runArtifactDetection(image: CGImage) async -> ArtifactAnalysisResult? {
        let startTime = CFAbsoluteTimeGetCurrent()

        let result = await ArtifactDetectionService.shared.analyze(image: image)

        let timeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        Self.logger.debug("Artifact detection completed in \(timeMs)ms, isLikelyArtificial=\(result.isLikelyArtificial)")

        // Return nil for unavailable/error status
        guard result.status == .success else {
            Self.logger.warning("Artifact detection unavailable: status=\(result.status.rawValue)")
            return nil
        }

        return result
    }

    // MARK: - Image Extraction

    /// Extracts CGImage from JPEG data.
    private func extractCGImage(from jpegData: Data) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        return cgImage
    }

    /// Extracts CGImage from CVPixelBuffer.
    private func extractCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - DetectionOrchestratorConstants

/// Configuration constants for detection orchestration.
public enum DetectionOrchestratorConstants {
    /// Target total detection time in milliseconds.
    /// Individual services run in parallel, so total should be close to slowest.
    public static let targetTimeMs: Int64 = 200

    /// Maximum acceptable detection time in milliseconds.
    public static let maxTimeMs: Int64 = 500

    /// Individual service targets (for reference):
    /// - Moire: 30ms
    /// - Texture: 50ms
    /// - Artifacts: 20ms
    /// - Aggregation: 10ms
    /// - Cross-validation: 5ms
}
