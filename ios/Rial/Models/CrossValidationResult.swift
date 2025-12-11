//
//  CrossValidationResult.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Result structure for cross-validation analysis (Story 9-5).
//  Pairwise correlation, temporal consistency, and anomaly detection.
//

import Foundation

// MARK: - CrossValidationResult

/// Result of cross-validation analysis between detection methods.
///
/// This struct contains all metrics from analyzing consistency between
/// detection methods, temporal stability, and anomaly patterns.
///
/// ## Algorithm Overview
/// 1. Pairwise consistency: Check expected relationships between method pairs
/// 2. Temporal consistency: Analyze score stability across multiple frames
/// 3. Confidence intervals: Compute uncertainty bounds per method
/// 4. Anomaly detection: Flag contradictory, too-perfect, or suspicious patterns
///
/// ## Security Note
/// Enhanced cross-validation catches sophisticated attacks that:
/// - Pass individual methods but have wrong correlations
/// - Manipulate frame-by-frame in video
/// - Produce suspiciously perfect or boundary-hugging scores
///
/// ## Usage
/// ```swift
/// let result = await CrossValidationService.shared.validate(
///     depth: depthResult,
///     moire: moireResult,
///     texture: textureResult,
///     artifacts: artifactResult
/// )
/// if result.validationStatus == .fail {
///     // Significant anomalies detected
/// }
/// ```
public struct CrossValidationResult: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Overall validation status based on anomaly analysis.
    public let validationStatus: ValidationStatus

    /// Pairwise consistency checks between method pairs.
    /// Contains 6 pairs for 4 methods: LiDAR-Moire, LiDAR-Texture, etc.
    public let pairwiseConsistencies: [PairwiseConsistency]

    /// Temporal consistency analysis (nil for single-frame).
    public let temporalConsistency: TemporalConsistency?

    /// Confidence intervals per detection method.
    /// Keys are DetectionMethod rawValues for JSON compatibility.
    public let confidenceIntervals: [String: ConfidenceInterval]

    /// Aggregated confidence interval combining all methods.
    public let aggregatedInterval: ConfidenceInterval

    /// Detected anomaly patterns.
    public let anomalies: [AnomalyReport]

    /// Overall penalty to apply to confidence (0.0-0.5).
    /// Derived from anomaly severities.
    public let overallPenalty: Float

    /// Analysis processing time in milliseconds.
    public let analysisTimeMs: Int64

    /// Algorithm version for tracking/compatibility.
    public let algorithmVersion: String

    /// Timestamp when analysis was performed.
    public let computedAt: Date

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case validationStatus = "validation_status"
        case pairwiseConsistencies = "pairwise_consistencies"
        case temporalConsistency = "temporal_consistency"
        case confidenceIntervals = "confidence_intervals"
        case aggregatedInterval = "aggregated_interval"
        case anomalies
        case overallPenalty = "overall_penalty"
        case analysisTimeMs = "analysis_time_ms"
        case algorithmVersion = "algorithm_version"
        case computedAt = "computed_at"
    }

    // MARK: - Initialization

    /// Creates a new CrossValidationResult with all metrics.
    public init(
        validationStatus: ValidationStatus,
        pairwiseConsistencies: [PairwiseConsistency],
        temporalConsistency: TemporalConsistency?,
        confidenceIntervals: [DetectionMethod: ConfidenceInterval],
        aggregatedInterval: ConfidenceInterval,
        anomalies: [AnomalyReport],
        overallPenalty: Float,
        analysisTimeMs: Int64,
        algorithmVersion: String = CrossValidationConstants.algorithmVersion,
        computedAt: Date = Date()
    ) {
        self.validationStatus = validationStatus
        self.pairwiseConsistencies = pairwiseConsistencies
        self.temporalConsistency = temporalConsistency
        // Convert to string-keyed dictionary for Codable compatibility
        var stringDict: [String: ConfidenceInterval] = [:]
        for (key, value) in confidenceIntervals {
            stringDict[key.rawValue] = value
        }
        self.confidenceIntervals = stringDict
        self.aggregatedInterval = aggregatedInterval
        self.anomalies = anomalies
        self.overallPenalty = max(0, min(0.5, overallPenalty))
        self.analysisTimeMs = analysisTimeMs
        self.algorithmVersion = algorithmVersion
        self.computedAt = computedAt
    }

    // MARK: - Convenience Accessors

    /// Returns confidence intervals as DetectionMethod-keyed dictionary.
    public var confidenceIntervalsByMethod: [DetectionMethod: ConfidenceInterval] {
        var result: [DetectionMethod: ConfidenceInterval] = [:]
        for (key, value) in confidenceIntervals {
            if let method = DetectionMethod(rawValue: key) {
                result[method] = value
            }
        }
        return result
    }

    /// Gets confidence interval for a specific detection method.
    public func interval(for method: DetectionMethod) -> ConfidenceInterval? {
        confidenceIntervals[method.rawValue]
    }

    // MARK: - Factory Methods

    /// Creates a default pass result when no cross-validation is needed.
    public static func defaultPass(analysisTimeMs: Int64 = 0) -> CrossValidationResult {
        CrossValidationResult(
            validationStatus: .pass,
            pairwiseConsistencies: [],
            temporalConsistency: nil,
            confidenceIntervals: [:],
            aggregatedInterval: ConfidenceInterval(
                lowerBound: 0.5,
                pointEstimate: 0.5,
                upperBound: 0.5
            ),
            anomalies: [],
            overallPenalty: 0,
            analysisTimeMs: analysisTimeMs
        )
    }

    /// Creates an unavailable result when cross-validation cannot be performed.
    public static func unavailable() -> CrossValidationResult {
        CrossValidationResult(
            validationStatus: .pass,
            pairwiseConsistencies: [],
            temporalConsistency: nil,
            confidenceIntervals: [:],
            aggregatedInterval: ConfidenceInterval(
                lowerBound: 0,
                pointEstimate: 0,
                upperBound: 0
            ),
            anomalies: [],
            overallPenalty: 0,
            analysisTimeMs: 0
        )
    }
}

// MARK: - ValidationStatus

/// Overall validation status from cross-validation analysis.
public enum ValidationStatus: String, Codable, Sendable {
    /// All checks passed, no significant anomalies.
    case pass

    /// Minor anomalies detected, proceed with caution.
    case warn

    /// Significant anomalies detected, likely manipulation.
    case fail
}

// MARK: - PairwiseConsistency

/// Consistency check between a pair of detection methods.
///
/// Analyzes whether two methods agree according to expected relationships.
/// For example, LiDAR and Moire should be inversely related: real depth implies
/// no screen moire pattern.
public struct PairwiseConsistency: Codable, Sendable, Equatable {

    /// First method in the pair.
    public let methodA: DetectionMethod

    /// Second method in the pair.
    public let methodB: DetectionMethod

    /// Expected relationship between methods.
    /// Positive = should correlate, Negative = should be inverse.
    public let expectedRelationship: ExpectedRelationship

    /// Actual agreement score observed (-1.0 to 1.0).
    /// Positive = agreeing, Negative = disagreeing.
    public let actualAgreement: Float

    /// Anomaly score (0.0-1.0) indicating deviation from expected.
    /// Higher = more anomalous.
    public let anomalyScore: Float

    /// Whether this pair's consistency is flagged as anomalous.
    public let isAnomaly: Bool

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case methodA = "method_a"
        case methodB = "method_b"
        case expectedRelationship = "expected_relationship"
        case actualAgreement = "actual_agreement"
        case anomalyScore = "anomaly_score"
        case isAnomaly = "is_anomaly"
    }

    // MARK: - Initialization

    public init(
        methodA: DetectionMethod,
        methodB: DetectionMethod,
        expectedRelationship: ExpectedRelationship,
        actualAgreement: Float,
        anomalyScore: Float,
        isAnomaly: Bool
    ) {
        self.methodA = methodA
        self.methodB = methodB
        self.expectedRelationship = expectedRelationship
        self.actualAgreement = max(-1, min(1, actualAgreement))
        self.anomalyScore = max(0, min(1, anomalyScore))
        self.isAnomaly = isAnomaly
    }
}

// MARK: - ExpectedRelationship

/// Expected relationship type between two detection methods.
public enum ExpectedRelationship: String, Codable, Sendable {
    /// Methods should positively correlate (both high or both low).
    case positive

    /// Methods should negatively correlate (one high implies other low).
    case negative

    /// Methods have weak or no expected correlation.
    case neutral
}

// MARK: - TemporalConsistency

/// Temporal consistency analysis for multi-frame captures.
///
/// Tracks how detection scores change across frames to identify
/// instabilities or manipulation.
public struct TemporalConsistency: Codable, Sendable, Equatable {

    /// Number of frames analyzed.
    public let frameCount: Int

    /// Stability score per method (0.0-1.0).
    /// 1.0 = perfectly stable, 0.0 = highly variable.
    /// Keys are DetectionMethod rawValues for JSON compatibility.
    public let stabilityScores: [String: Float]

    /// Detected temporal anomalies (sudden jumps, oscillations).
    public let anomalies: [TemporalAnomaly]

    /// Overall temporal stability score (0.0-1.0).
    public let overallStability: Float

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case frameCount = "frame_count"
        case stabilityScores = "stability_scores"
        case anomalies
        case overallStability = "overall_stability"
    }

    // MARK: - Initialization

    public init(
        frameCount: Int,
        stabilityScores: [DetectionMethod: Float],
        anomalies: [TemporalAnomaly],
        overallStability: Float
    ) {
        self.frameCount = frameCount
        // Convert to string-keyed dictionary
        var stringDict: [String: Float] = [:]
        for (key, value) in stabilityScores {
            stringDict[key.rawValue] = value
        }
        self.stabilityScores = stringDict
        self.anomalies = anomalies
        self.overallStability = max(0, min(1, overallStability))
    }

    // MARK: - Convenience

    /// Returns stability scores as DetectionMethod-keyed dictionary.
    public var stabilityScoresByMethod: [DetectionMethod: Float] {
        var result: [DetectionMethod: Float] = [:]
        for (key, value) in stabilityScores {
            if let method = DetectionMethod(rawValue: key) {
                result[method] = value
            }
        }
        return result
    }

    /// Creates neutral temporal consistency for single-frame analysis.
    public static func singleFrame() -> TemporalConsistency {
        TemporalConsistency(
            frameCount: 1,
            stabilityScores: [:],
            anomalies: [],
            overallStability: 1.0
        )
    }
}

// MARK: - TemporalAnomaly

/// A detected temporal anomaly in multi-frame analysis.
public struct TemporalAnomaly: Codable, Sendable, Equatable {

    /// Frame index where anomaly occurred.
    public let frameIndex: Int

    /// Detection method exhibiting the anomaly.
    public let method: DetectionMethod

    /// Score delta that triggered the anomaly.
    public let deltaScore: Float

    /// Type of temporal anomaly.
    public let type: TemporalAnomalyType

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case frameIndex = "frame_index"
        case method
        case deltaScore = "delta_score"
        case type
    }

    // MARK: - Initialization

    public init(
        frameIndex: Int,
        method: DetectionMethod,
        deltaScore: Float,
        type: TemporalAnomalyType
    ) {
        self.frameIndex = frameIndex
        self.method = method
        self.deltaScore = deltaScore
        self.type = type
    }
}

// MARK: - TemporalAnomalyType

/// Type of temporal anomaly detected.
public enum TemporalAnomalyType: String, Codable, Sendable {
    /// Sudden large jump in score (>0.3 delta).
    case suddenJump = "sudden_jump"

    /// Oscillating scores (high-low-high pattern).
    case oscillation

    /// Gradual drift in one direction.
    case drift
}

// MARK: - ConfidenceInterval

/// Confidence interval for a point estimate.
///
/// Represents uncertainty bounds around a detection score,
/// acknowledging that methods have different reliabilities.
public struct ConfidenceInterval: Codable, Sendable, Equatable {

    /// Lower bound (95% confidence).
    public let lowerBound: Float

    /// Point estimate (central value).
    public let pointEstimate: Float

    /// Upper bound (95% confidence).
    public let upperBound: Float

    /// Interval width (uncertainty measure).
    public var width: Float {
        upperBound - lowerBound
    }

    /// Whether this interval has high uncertainty (width > 0.3).
    public var isHighUncertainty: Bool {
        width > CrossValidationConstants.highUncertaintyThreshold
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case lowerBound = "lower_bound"
        case pointEstimate = "point_estimate"
        case upperBound = "upper_bound"
    }

    // MARK: - Initialization

    public init(
        lowerBound: Float,
        pointEstimate: Float,
        upperBound: Float
    ) {
        self.lowerBound = max(0, min(1, lowerBound))
        self.pointEstimate = max(0, min(1, pointEstimate))
        self.upperBound = max(0, min(1, upperBound))
    }
}

// MARK: - AnomalyReport

/// Report of a detected anomaly pattern.
public struct AnomalyReport: Codable, Sendable, Equatable {

    /// Type of anomaly detected.
    public let anomalyType: AnomalyType

    /// Severity of the anomaly.
    public let severity: AnomalySeverity

    /// Methods affected by this anomaly.
    public let affectedMethods: [DetectionMethod]

    /// Human-readable details of the anomaly.
    public let details: String

    /// Suggested confidence impact (penalty).
    public let confidenceImpact: Float

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case anomalyType = "anomaly_type"
        case severity
        case affectedMethods = "affected_methods"
        case details
        case confidenceImpact = "confidence_impact"
    }

    // MARK: - Initialization

    public init(
        anomalyType: AnomalyType,
        severity: AnomalySeverity,
        affectedMethods: [DetectionMethod],
        details: String,
        confidenceImpact: Float
    ) {
        self.anomalyType = anomalyType
        self.severity = severity
        self.affectedMethods = affectedMethods
        self.details = details
        self.confidenceImpact = max(0, min(0.5, confidenceImpact))
    }
}

// MARK: - AnomalyType

/// Types of anomaly patterns detected during cross-validation.
public enum AnomalyType: String, Codable, Sendable {
    /// Contradictory signals between methods.
    /// Example: LiDAR says flat but texture says real material.
    case contradictorySignals = "contradictory_signals"

    /// All methods agree too perfectly (possible adversarial input).
    /// Suspiciously identical scores across all methods.
    case tooHighAgreement = "too_high_agreement"

    /// One method strongly differs from all others.
    case isolatedDisagreement = "isolated_disagreement"

    /// Scores clustered at boundaries (0.0, 0.5, 1.0).
    case boundaryCluster = "boundary_cluster"

    /// Expected correlations absent or unexpected correlations present.
    case correlationAnomaly = "correlation_anomaly"
}

// MARK: - AnomalySeverity

/// Severity level of a detected anomaly.
public enum AnomalySeverity: String, Codable, Sendable, Comparable {
    /// Minor concern, likely noise or edge case.
    case low

    /// Moderate concern, warrants attention.
    case medium

    /// Severe concern, likely manipulation.
    case high

    /// Ordering for comparison
    private var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: AnomalySeverity, rhs: AnomalySeverity) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - DetectionFrameSet

/// Input type for multi-frame temporal analysis.
public struct DetectionFrameSet: Sendable {

    /// Array of detection frames to analyze.
    public let frames: [DetectionFrame]

    // MARK: - Initialization

    public init(frames: [DetectionFrame]) {
        self.frames = frames
    }
}

// MARK: - DetectionFrame

/// Detection results for a single frame in multi-frame analysis.
public struct DetectionFrame: Sendable {

    /// Frame index in sequence.
    public let index: Int

    /// Frame timestamp (relative to capture start).
    public let timestamp: TimeInterval

    /// LiDAR depth analysis result (optional).
    public let depth: DepthAnalysisResult?

    /// Moire pattern detection result (optional).
    public let moire: MoireAnalysisResult?

    /// Texture classification result (optional).
    public let texture: TextureClassificationResult?

    /// Artifact detection result (optional).
    public let artifacts: ArtifactAnalysisResult?

    // MARK: - Initialization

    public init(
        index: Int,
        timestamp: TimeInterval,
        depth: DepthAnalysisResult? = nil,
        moire: MoireAnalysisResult? = nil,
        texture: TextureClassificationResult? = nil,
        artifacts: ArtifactAnalysisResult? = nil
    ) {
        self.index = index
        self.timestamp = timestamp
        self.depth = depth
        self.moire = moire
        self.texture = texture
        self.artifacts = artifacts
    }
}

// MARK: - CrossValidationConstants

/// Configuration constants for cross-validation analysis.
public enum CrossValidationConstants {
    /// Current algorithm version.
    public static let algorithmVersion = "1.0"

    // MARK: - Pairwise Consistency Thresholds

    /// Expected relationship matrix values (initial heuristic estimates).
    /// LiDAR-Moire: should be inverse (real depth = no screen moire).
    public static let lidarMoireExpected: Float = -0.7

    /// LiDAR-Texture: should correlate (real depth = real texture).
    public static let lidarTextureExpected: Float = 0.6

    /// LiDAR-Artifacts: should be inverse (real depth = no artifacts).
    public static let lidarArtifactsExpected: Float = -0.5

    /// Moire-Texture: should correlate (both 2D signals).
    public static let moireTextureExpected: Float = 0.4

    /// Moire-Artifacts: should correlate (screen has both).
    public static let moireArtifactsExpected: Float = 0.6

    /// Texture-Artifacts: weak inverse relationship.
    public static let textureArtifactsExpected: Float = -0.3

    /// Threshold for flagging pair as anomalous (deviation from expected).
    public static let pairwiseAnomalyThreshold: Float = 0.5

    // MARK: - Temporal Consistency Thresholds

    /// Threshold for sudden jump detection (delta between frames).
    public static let suddenJumpThreshold: Float = 0.3

    /// Threshold for oscillation detection (variance).
    public static let oscillationThreshold: Float = 0.2

    /// Maximum expected variance for stability scoring.
    public static let maxExpectedVariance: Float = 0.1

    // MARK: - Confidence Interval Parameters

    /// Base interval width for LiDAR (high reliability).
    public static let lidarIntervalWidth: Float = 0.05

    /// Base interval width for Moire (medium reliability).
    public static let moireIntervalWidth: Float = 0.10

    /// Base interval width for Texture (medium reliability).
    public static let textureIntervalWidth: Float = 0.10

    /// Base interval width for Artifacts (wider due to heuristic nature).
    public static let artifactsIntervalWidth: Float = 0.12

    /// Threshold for high uncertainty flag.
    public static let highUncertaintyThreshold: Float = 0.3

    /// Uncertainty factor multiplier for mid-range scores (0.4-0.6).
    public static let midRangeUncertaintyBoost: Float = 0.5

    // MARK: - Anomaly Detection Thresholds

    /// Threshold for too-perfect agreement (all within this delta).
    public static let tooPerfectThreshold: Float = 0.02

    /// Threshold for isolated disagreement (one method differs by this much).
    public static let isolatedDisagreementThreshold: Float = 0.4

    /// Boundary clustering threshold (distance from 0.0, 0.5, or 1.0).
    public static let boundaryClusterThreshold: Float = 0.05

    /// Minimum score count for clustering detection.
    public static let minBoundaryClusterCount: Int = 3

    // MARK: - Anomaly Impact Values

    /// Confidence penalty for low severity anomaly.
    public static let lowSeverityPenalty: Float = 0.05

    /// Confidence penalty for medium severity anomaly.
    public static let mediumSeverityPenalty: Float = 0.15

    /// Confidence penalty for high severity anomaly.
    public static let highSeverityPenalty: Float = 0.30

    /// Maximum overall penalty cap.
    public static let maxOverallPenalty: Float = 0.5

    // MARK: - Validation Status Thresholds

    /// Max medium severity anomalies before .fail status.
    public static let maxMediumAnomaliesForWarn: Int = 2

    /// Max low severity anomalies before .warn status.
    /// Single low anomaly is acceptable; warn only when multiple accumulate.
    public static let maxLowAnomaliesForPass: Int = 1

    // MARK: - Performance

    /// Target analysis time for single-frame (milliseconds).
    public static let targetSingleFrameTimeMs: Int64 = 5

    /// Target analysis time for multi-frame 30 frames (milliseconds).
    public static let targetMultiFrameTimeMs: Int64 = 20

    /// Maximum memory usage during analysis (bytes).
    public static let maxMemoryBytes: Int = 5 * 1024 * 1024 // 5MB
}

// MARK: - CustomStringConvertible

extension CrossValidationResult: CustomStringConvertible {
    public var description: String {
        """
        CrossValidationResult(
            status: \(validationStatus.rawValue),
            pairwiseChecks: \(pairwiseConsistencies.count),
            anomalies: \(anomalies.count),
            overallPenalty: \(String(format: "%.3f", overallPenalty)),
            aggregatedInterval: [\(String(format: "%.3f", aggregatedInterval.lowerBound)), \(String(format: "%.3f", aggregatedInterval.upperBound))],
            analysisTimeMs: \(analysisTimeMs),
            version: \(algorithmVersion)
        )
        """
    }
}

extension PairwiseConsistency: CustomStringConvertible {
    public var description: String {
        String(format: "PairwiseConsistency(%@-%@, expected=%@, actual=%.2f, anomaly=%@)",
               methodA.rawValue, methodB.rawValue,
               expectedRelationship.rawValue,
               actualAgreement,
               isAnomaly ? "YES" : "NO")
    }
}

extension AnomalyReport: CustomStringConvertible {
    public var description: String {
        String(format: "AnomalyReport(%@, severity=%@, impact=%.2f, methods=%@, details=%@)",
               anomalyType.rawValue,
               severity.rawValue,
               confidenceImpact,
               affectedMethods.map(\.rawValue).joined(separator: ","),
               details)
    }
}
