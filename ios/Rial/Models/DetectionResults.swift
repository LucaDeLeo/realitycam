//
//  DetectionResults.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Aggregated detection results container (Story 9-6).
//  Combines all multi-signal detection outputs for capture payload integration.
//

import Foundation

// MARK: - DetectionResults

/// Container for all multi-signal detection outputs.
///
/// This struct aggregates results from Moire, Texture, Artifact detection,
/// confidence aggregation, and cross-validation into a single payload
/// suitable for inclusion in CaptureData and upload to backend.
///
/// ## Payload Structure
/// When encoded to JSON, uses snake_case keys to match Rust backend conventions:
/// - `moire`: MoireAnalysisResult (optional)
/// - `texture`: TextureClassificationResult (optional)
/// - `artifacts`: ArtifactAnalysisResult (optional)
/// - `aggregated_confidence`: AggregatedConfidenceResult (optional)
/// - `cross_validation`: CrossValidationResult (optional)
///
/// ## Size Estimate
/// Typical serialized size: 2-5KB
/// - MoireAnalysisResult: ~500 bytes
/// - TextureClassificationResult: ~300 bytes
/// - ArtifactAnalysisResult: ~400 bytes
/// - AggregatedConfidenceResult: ~1KB
/// - CrossValidationResult: ~2KB
///
/// ## Usage
/// ```swift
/// let results = await DetectionOrchestrator.shared.runAllDetections(image: cgImage)
/// captureData.detectionResults = results
/// ```
public struct DetectionResults: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Moire pattern detection result (optional).
    /// Nil if moire detection was not run or failed.
    public let moire: MoireAnalysisResult?

    /// Texture classification result (optional).
    /// Nil if texture classification was not run or failed.
    public let texture: TextureClassificationResult?

    /// Artifact detection result (optional).
    /// Nil if artifact detection was not run or failed.
    public let artifacts: ArtifactAnalysisResult?

    /// Aggregated confidence result combining all signals (optional).
    /// Nil if aggregation was not run or no methods available.
    public let aggregatedConfidence: AggregatedConfidenceResult?

    /// Cross-validation result from enhanced mode (optional).
    /// Nil if cross-validation was not run.
    public let crossValidation: CrossValidationResult?

    /// Timestamp when detection was performed.
    public let computedAt: Date

    /// Total detection processing time in milliseconds.
    public let totalProcessingTimeMs: Int64

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case moire
        case texture
        case artifacts
        case aggregatedConfidence = "aggregated_confidence"
        case crossValidation = "cross_validation"
        case computedAt = "computed_at"
        case totalProcessingTimeMs = "total_processing_time_ms"
    }

    // MARK: - Initialization

    /// Creates a new DetectionResults with all detection outputs.
    ///
    /// - Parameters:
    ///   - moire: Moire pattern detection result (optional)
    ///   - texture: Texture classification result (optional)
    ///   - artifacts: Artifact detection result (optional)
    ///   - aggregatedConfidence: Aggregated confidence result (optional)
    ///   - crossValidation: Cross-validation result (optional)
    ///   - computedAt: Timestamp when detection was performed (defaults to now)
    ///   - totalProcessingTimeMs: Total processing time in milliseconds (defaults to 0)
    public init(
        moire: MoireAnalysisResult? = nil,
        texture: TextureClassificationResult? = nil,
        artifacts: ArtifactAnalysisResult? = nil,
        aggregatedConfidence: AggregatedConfidenceResult? = nil,
        crossValidation: CrossValidationResult? = nil,
        computedAt: Date = Date(),
        totalProcessingTimeMs: Int64 = 0
    ) {
        self.moire = moire
        self.texture = texture
        self.artifacts = artifacts
        self.aggregatedConfidence = aggregatedConfidence
        self.crossValidation = crossValidation
        self.computedAt = computedAt
        self.totalProcessingTimeMs = totalProcessingTimeMs
    }

    // MARK: - Computed Properties

    /// Whether at least one detection result is available.
    public var hasAnyResults: Bool {
        moire != nil || texture != nil || artifacts != nil || aggregatedConfidence != nil
    }

    /// Count of available detection methods.
    public var availableMethodCount: Int {
        var count = 0
        if moire != nil { count += 1 }
        if texture != nil { count += 1 }
        if artifacts != nil { count += 1 }
        return count
    }

    /// Overall confidence level from aggregated result.
    /// Returns nil if aggregation not available.
    public var confidenceLevel: AggregatedConfidenceLevel? {
        aggregatedConfidence?.confidenceLevel
    }

    /// Overall confidence score (0.0-1.0) from aggregated result.
    /// Returns nil if aggregation not available.
    public var overallConfidence: Float? {
        aggregatedConfidence?.overallConfidence
    }

    /// Whether LiDAR primary signal passed verification.
    /// Returns nil if aggregation not available.
    public var primarySignalValid: Bool? {
        aggregatedConfidence?.primarySignalValid
    }

    /// Whether supporting signals agree with each other.
    /// Returns nil if aggregation not available.
    public var signalsAgree: Bool? {
        aggregatedConfidence?.supportingSignalsAgree
    }

    /// List of detection methods that were executed.
    public var methodsUsed: [String] {
        var methods: [String] = []
        if moire != nil { methods.append("moire") }
        if texture != nil { methods.append("texture") }
        if artifacts != nil { methods.append("artifacts") }
        return methods
    }

    /// Estimated serialized size in bytes.
    public var estimatedSize: Int {
        // Rough estimates based on typical JSON output
        var size = 100 // Base overhead (braces, keys, etc.)
        if moire != nil { size += 500 }
        if texture != nil { size += 300 }
        if artifacts != nil { size += 400 }
        if aggregatedConfidence != nil { size += 1000 }
        if crossValidation != nil { size += 2000 }
        return size
    }

    // MARK: - Factory Methods

    /// Creates an empty result when no detections were run.
    ///
    /// - Returns: DetectionResults with all fields nil
    public static func empty() -> DetectionResults {
        DetectionResults()
    }

    /// Creates an unavailable result when detection cannot be performed.
    ///
    /// Use when:
    /// - Image format unsupported
    /// - All detection services failed
    /// - Detection explicitly disabled
    ///
    /// - Returns: DetectionResults with unavailable indicators
    public static func unavailable() -> DetectionResults {
        DetectionResults(
            moire: .unavailable(),
            texture: .unavailable(reason: "Detection unavailable"),
            artifacts: .unavailable(),
            aggregatedConfidence: .unavailable(),
            crossValidation: .unavailable()
        )
    }

    /// Creates a partial result with only available detection outputs.
    ///
    /// - Parameters:
    ///   - moire: Moire result if available
    ///   - texture: Texture result if available
    ///   - artifacts: Artifact result if available
    ///   - aggregated: Aggregated result from available methods
    ///   - crossValidation: Cross-validation result if available
    ///   - processingTimeMs: Total processing time
    /// - Returns: DetectionResults with partial data
    public static func partial(
        moire: MoireAnalysisResult? = nil,
        texture: TextureClassificationResult? = nil,
        artifacts: ArtifactAnalysisResult? = nil,
        aggregated: AggregatedConfidenceResult? = nil,
        crossValidation: CrossValidationResult? = nil,
        processingTimeMs: Int64 = 0
    ) -> DetectionResults {
        DetectionResults(
            moire: moire,
            texture: texture,
            artifacts: artifacts,
            aggregatedConfidence: aggregated,
            crossValidation: crossValidation,
            totalProcessingTimeMs: processingTimeMs
        )
    }
}

// MARK: - CustomStringConvertible

extension DetectionResults: CustomStringConvertible {
    public var description: String {
        """
        DetectionResults(
            hasResults: \(hasAnyResults),
            methods: \(methodsUsed.joined(separator: ", ")),
            confidenceLevel: \(confidenceLevel?.rawValue ?? "nil"),
            overallConfidence: \(overallConfidence.map { String(format: "%.3f", $0) } ?? "nil"),
            primaryValid: \(primarySignalValid.map { String($0) } ?? "nil"),
            signalsAgree: \(signalsAgree.map { String($0) } ?? "nil"),
            processingTimeMs: \(totalProcessingTimeMs),
            estimatedSize: \(estimatedSize) bytes
        )
        """
    }
}
