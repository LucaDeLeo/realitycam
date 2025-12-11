//
//  AggregatedConfidenceResult.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Result structure for confidence aggregation (Story 9-4).
//  Combines LiDAR, Moire, Texture, and Artifact detection signals.
//

import Foundation

// MARK: - AggregatedConfidenceResult

/// Result of confidence aggregation from all detection methods.
///
/// This struct combines results from multiple detection services into a single
/// weighted confidence score with detailed breakdown and flags.
///
/// ## Algorithm Overview
/// 1. Normalize each detection method's result to 0.0-1.0 authenticity score
/// 2. Apply PRD-specified weights (LiDAR 55%, others 15% each)
/// 3. Redistribute weights if any method unavailable
/// 4. Compute weighted average
/// 5. Apply cross-validation bonus/penalty
/// 6. Determine confidence level from thresholds
///
/// ## Trust Hierarchy (from PRD)
/// - PRIMARY: LiDAR (55%) - hardware-based physical signal
/// - SUPPORTING: Moire, Texture, Artifacts (15% each) - software detection
///
/// ## Security Note
/// Per PRD research (USENIX Security 2025), single detection methods can be bypassed.
/// This aggregator implements defense-in-depth by combining multiple signals with
/// cross-validation. LiDAR is PRIMARY (hardware signal), detection algorithms are
/// SUPPORTING (can be bypassed with effort).
///
/// ## Usage
/// ```swift
/// let result = await ConfidenceAggregator.shared.aggregate(
///     depth: depthResult,
///     moire: moireResult,
///     texture: textureResult,
///     artifacts: artifactResult
/// )
/// if result.confidenceLevel >= .high {
///     // Scene verified with high confidence
/// }
/// ```
public struct AggregatedConfidenceResult: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Overall weighted confidence score (0.0-1.0).
    /// 1.0 = Strong evidence of authentic real scene.
    /// 0.0 = Strong evidence of artificial/recaptured scene.
    public let overallConfidence: Float

    /// Confidence level classification based on thresholds.
    public let confidenceLevel: AggregatedConfidenceLevel

    /// Individual method scores and contributions stored as string-keyed dictionary.
    /// Keys are DetectionMethod rawValues for JSON compatibility.
    public let methodBreakdown: [String: MethodResult]

    /// Whether the primary LiDAR signal passed verification.
    /// True if LiDAR isLikelyRealScene is true.
    public let primarySignalValid: Bool

    /// Whether all supporting signals agree with the primary signal.
    /// True if no disagreement between LiDAR and supporting methods.
    public let supportingSignalsAgree: Bool

    /// Array of flags indicating concerns or disagreements.
    public let flags: [ConfidenceFlag]

    /// Total aggregation processing time in milliseconds.
    public let analysisTimeMs: Int64

    /// Timestamp when aggregation was performed.
    public let computedAt: Date

    /// Algorithm version for tracking/compatibility.
    public let algorithmVersion: String

    /// Aggregation status indicating success or failure mode.
    public let status: AggregationStatus

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case overallConfidence = "overall_confidence"
        case confidenceLevel = "confidence_level"
        case methodBreakdown = "method_breakdown"
        case primarySignalValid = "primary_signal_valid"
        case supportingSignalsAgree = "supporting_signals_agree"
        case flags
        case analysisTimeMs = "analysis_time_ms"
        case computedAt = "computed_at"
        case algorithmVersion = "algorithm_version"
        case status
    }

    // MARK: - Initialization

    /// Creates a new AggregatedConfidenceResult with all fields.
    ///
    /// - Parameters:
    ///   - overallConfidence: Weighted confidence score (0.0-1.0)
    ///   - confidenceLevel: Classification based on thresholds
    ///   - methodBreakdown: Individual method results keyed by DetectionMethod
    ///   - primarySignalValid: Whether LiDAR passed
    ///   - supportingSignalsAgree: Whether signals agree
    ///   - flags: Array of concern flags
    ///   - analysisTimeMs: Processing duration in milliseconds
    ///   - computedAt: Analysis timestamp (defaults to now)
    ///   - algorithmVersion: Algorithm version (defaults to current)
    ///   - status: Aggregation status (defaults to .success)
    public init(
        overallConfidence: Float,
        confidenceLevel: AggregatedConfidenceLevel,
        methodBreakdown: [DetectionMethod: MethodResult],
        primarySignalValid: Bool,
        supportingSignalsAgree: Bool,
        flags: [ConfidenceFlag],
        analysisTimeMs: Int64,
        computedAt: Date = Date(),
        algorithmVersion: String = ConfidenceAggregationConstants.algorithmVersion,
        status: AggregationStatus = .success
    ) {
        self.overallConfidence = max(0, min(1, overallConfidence))
        self.confidenceLevel = confidenceLevel
        // Convert to string-keyed dictionary for Codable compatibility
        var stringDict: [String: MethodResult] = [:]
        for (key, value) in methodBreakdown {
            stringDict[key.rawValue] = value
        }
        self.methodBreakdown = stringDict
        self.primarySignalValid = primarySignalValid
        self.supportingSignalsAgree = supportingSignalsAgree
        self.flags = flags
        self.analysisTimeMs = analysisTimeMs
        self.computedAt = computedAt
        self.algorithmVersion = algorithmVersion
        self.status = status
    }

    // MARK: - Convenience Accessors

    /// Returns method breakdown as DetectionMethod-keyed dictionary.
    public var methodBreakdownByMethod: [DetectionMethod: MethodResult] {
        var result: [DetectionMethod: MethodResult] = [:]
        for (key, value) in methodBreakdown {
            if let method = DetectionMethod(rawValue: key) {
                result[method] = value
            }
        }
        return result
    }

    /// Gets result for a specific detection method.
    public func result(for method: DetectionMethod) -> MethodResult? {
        methodBreakdown[method.rawValue]
    }

    // MARK: - Factory Methods

    /// Creates a result with updated analysis time.
    /// Used internally after timing the aggregation.
    public func with(analysisTimeMs: Int64) -> AggregatedConfidenceResult {
        AggregatedConfidenceResult(
            overallConfidence: overallConfidence,
            confidenceLevel: confidenceLevel,
            methodBreakdown: methodBreakdownByMethod,
            primarySignalValid: primarySignalValid,
            supportingSignalsAgree: supportingSignalsAgree,
            flags: flags,
            analysisTimeMs: analysisTimeMs,
            computedAt: computedAt,
            algorithmVersion: algorithmVersion,
            status: status
        )
    }

    /// Creates a result when no detection methods are available.
    ///
    /// - Returns: Result with status = .unavailable
    public static func unavailable() -> AggregatedConfidenceResult {
        AggregatedConfidenceResult(
            overallConfidence: 0,
            confidenceLevel: .suspicious,
            methodBreakdown: [:],
            primarySignalValid: false,
            supportingSignalsAgree: false,
            flags: [.partialAnalysis],
            analysisTimeMs: 0,
            computedAt: Date(),
            algorithmVersion: ConfidenceAggregationConstants.algorithmVersion,
            status: .unavailable
        )
    }

    /// Creates a result when aggregation fails with error.
    ///
    /// - Parameter analysisTimeMs: Processing duration before failure
    /// - Returns: Result with status = .error
    public static func error(analysisTimeMs: Int64) -> AggregatedConfidenceResult {
        AggregatedConfidenceResult(
            overallConfidence: 0,
            confidenceLevel: .suspicious,
            methodBreakdown: [:],
            primarySignalValid: false,
            supportingSignalsAgree: false,
            flags: [],
            analysisTimeMs: analysisTimeMs,
            computedAt: Date(),
            algorithmVersion: ConfidenceAggregationConstants.algorithmVersion,
            status: .error
        )
    }
}

// MARK: - AggregatedConfidenceLevel

/// Classification of overall confidence level for aggregated detection results.
///
/// This differs from the backend `ConfidenceLevel` which uses uppercase values
/// for API responses. This enum is for internal client-side aggregation.
///
/// Thresholds from PRD:
/// - veryHigh: >= 0.90 AND all methods available AND all agree
/// - high: >= 0.75
/// - medium: >= 0.50
/// - low: >= 0.25
/// - suspicious: < 0.25 OR significant disagreement
public enum AggregatedConfidenceLevel: String, Codable, Sendable, Comparable {
    /// Very high confidence (>= 0.90) with full agreement.
    /// All detection methods available and agree on authentic scene.
    case veryHigh = "very_high"

    /// High confidence (>= 0.75).
    /// Primary signal passes and most supporting signals agree.
    case high

    /// Medium confidence (>= 0.50).
    /// Primary passes OR strong supporting consensus.
    case medium

    /// Low confidence (>= 0.25).
    /// Weak signals or significant disagreement.
    case low

    /// Suspicious (< 0.25 or screen/print detected).
    /// Failed primary OR methods disagree significantly.
    case suspicious

    /// Ordering for comparison
    private var order: Int {
        switch self {
        case .veryHigh: return 4
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .suspicious: return 0
        }
    }

    public static func < (lhs: AggregatedConfidenceLevel, rhs: AggregatedConfidenceLevel) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - DetectionMethod

/// Enumeration of detection methods used in confidence aggregation.
public enum DetectionMethod: String, Codable, Sendable, CaseIterable {
    /// LiDAR depth analysis - PRIMARY signal (55% weight).
    /// Hardware-based physical measurement, most reliable.
    case lidar

    /// Moire pattern detection - SUPPORTING signal (15% weight).
    /// Detects screen pixel grids via FFT.
    case moire

    /// Texture classification - SUPPORTING signal (15% weight).
    /// Distinguishes real materials from screens/prints.
    case texture

    /// Artifact detection - SUPPORTING signal (15% weight).
    /// Detects PWM flicker, specular reflections, halftone.
    case artifacts
}

// MARK: - MethodResult

/// Result details for an individual detection method.
public struct MethodResult: Codable, Sendable, Equatable {

    /// Whether this method was executed/available.
    public let available: Bool

    /// Normalized score (0.0-1.0), nil if unavailable.
    /// 1.0 = authentic, 0.0 = artificial/recaptured.
    public let score: Float?

    /// Actual weight applied after redistribution.
    public let weight: Float

    /// Contribution to overall score (score * weight).
    public let contribution: Float

    /// Status string: "pass", "fail", "unavailable", "error".
    public let status: String

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case available
        case score
        case weight
        case contribution
        case status
    }

    // MARK: - Initialization

    public init(
        available: Bool,
        score: Float?,
        weight: Float,
        contribution: Float,
        status: String
    ) {
        self.available = available
        self.score = score
        self.weight = weight
        self.contribution = contribution
        self.status = status
    }

    /// Creates an unavailable method result.
    public static func unavailable() -> MethodResult {
        MethodResult(
            available: false,
            score: nil,
            weight: 0,
            contribution: 0,
            status: "unavailable"
        )
    }
}

// MARK: - ConfidenceFlag

/// Flags indicating concerns or issues detected during aggregation.
public enum ConfidenceFlag: String, Codable, Sendable, Hashable {
    /// LiDAR depth analysis did not pass (isLikelyRealScene = false).
    case primarySignalFailed = "primary_signal_failed"

    /// Moire or texture detected screen recapture.
    case screenDetected = "screen_detected"

    /// Artifact halftone detection triggered (print detected).
    case printDetected = "print_detected"

    /// Supporting signals contradict each other.
    case methodsDisagree = "methods_disagree"

    /// LiDAR contradicts supporting signals.
    case primarySupportingDisagree = "primary_supporting_disagree"

    /// Some detection methods were unavailable.
    case partialAnalysis = "partial_analysis"

    /// LiDAR passed but with low confidence.
    case lowConfidencePrimary = "low_confidence_primary"

    /// Multiple methods returned borderline scores (0.4-0.6).
    case ambiguousResults = "ambiguous_results"
}

// MARK: - AggregationStatus

/// Status of confidence aggregation computation.
public enum AggregationStatus: String, Codable, Sendable {
    /// Aggregation completed successfully with at least one method.
    case success

    /// Aggregation completed with only some methods available.
    case partial

    /// No detection methods available.
    case unavailable

    /// Aggregation failed due to error.
    case error
}

// MARK: - ConfidenceAggregationConstants

/// Configuration constants for confidence aggregation.
///
/// These values define the PRD-specified weights and thresholds
/// for combining detection method signals.
public enum ConfidenceAggregationConstants {
    /// Current algorithm version.
    public static let algorithmVersion = "1.0"

    // MARK: - PRD-Specified Weights

    /// LiDAR weight - PRIMARY signal.
    /// Hardware-based physical measurement, most reliable.
    public static let lidarWeight: Float = 0.55

    /// Moire detection weight - SUPPORTING signal.
    public static let moireWeight: Float = 0.15

    /// Texture classification weight - SUPPORTING signal.
    public static let textureWeight: Float = 0.15

    /// Artifact detection weight - SUPPORTING signal.
    public static let artifactsWeight: Float = 0.15

    // MARK: - Confidence Thresholds

    /// Threshold for VERY_HIGH confidence level.
    /// Requires all methods available and agreeing.
    public static let veryHighThreshold: Float = 0.90

    /// Threshold for HIGH confidence level.
    public static let highThreshold: Float = 0.75

    /// Threshold for MEDIUM confidence level.
    public static let mediumThreshold: Float = 0.50

    /// Threshold for LOW confidence level.
    public static let lowThreshold: Float = 0.25

    // MARK: - Cross-Validation

    /// Bonus added when all methods agree.
    public static let agreementBoost: Float = 0.05

    /// Confidence level cap when significant disagreement detected.
    public static let disagreementCap: AggregatedConfidenceLevel = .medium

    // MARK: - Score Normalization

    /// Threshold below which LiDAR is considered "low confidence".
    public static let lowConfidenceLidarThreshold: Float = 0.7

    /// Range for borderline/ambiguous scores.
    public static let ambiguousScoreLow: Float = 0.4
    public static let ambiguousScoreHigh: Float = 0.6

    // MARK: - Performance

    /// Target aggregation time in milliseconds.
    public static let targetTimeMs: Int64 = 10

    /// Maximum acceptable aggregation time in milliseconds.
    public static let maxTimeMs: Int64 = 50
}

// MARK: - CustomStringConvertible

extension AggregatedConfidenceResult: CustomStringConvertible {
    public var description: String {
        """
        AggregatedConfidenceResult(
            overallConfidence: \(String(format: "%.3f", overallConfidence)),
            confidenceLevel: \(confidenceLevel.rawValue),
            primarySignalValid: \(primarySignalValid),
            supportingSignalsAgree: \(supportingSignalsAgree),
            flags: \(flags.map(\.rawValue)),
            methods: \(methodBreakdown.count),
            analysisTimeMs: \(analysisTimeMs),
            status: \(status.rawValue),
            version: \(algorithmVersion)
        )
        """
    }
}

extension MethodResult: CustomStringConvertible {
    public var description: String {
        if let score = score {
            return String(format: "MethodResult(score=%.3f, weight=%.3f, contribution=%.3f, status=%@)",
                          score, weight, contribution, status)
        } else {
            return "MethodResult(unavailable)"
        }
    }
}
