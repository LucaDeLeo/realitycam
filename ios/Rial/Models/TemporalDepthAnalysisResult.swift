//
//  TemporalDepthAnalysisResult.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Result structure for temporal depth analysis across video keyframes (Story 8-8).
//  Provides algorithm parity with backend/src/services/depth_analysis.rs for video.
//

import Foundation

// MARK: - TemporalDepthAnalysisResult

/// Result of temporal depth analysis for video privacy mode.
///
/// This struct contains per-keyframe and aggregate metrics computed from
/// video depth keyframes, matching the server-side temporal algorithm for
/// trust model compatibility.
///
/// ## Algorithm Parity
/// Formulas match `backend/src/services/depth_analysis.rs`:
/// - Per-keyframe: variance > 0.5, layers >= 3, coherence > 0.3
/// - Variance stability: 1.0 - (stddev(variances) / mean(variances))
/// - Temporal coherence: mean(edge_coherences)
/// - Authenticity: all keyframes pass AND variance_stability > 0.8
///
/// ## Usage
/// ```swift
/// let result = try await DepthAnalysisService.shared.analyzeTemporalDepth(
///     keyframes: depthKeyframes,
///     rgbFrames: rgbKeyframes
/// )
/// if result.isLikelyRealScene {
///     // Video verified across time
/// }
/// ```
public struct TemporalDepthAnalysisResult: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Per-keyframe depth analysis results.
    /// Each element is the full DepthAnalysisResult for one depth keyframe.
    public let keyframeAnalyses: [DepthAnalysisResult]

    /// Mean depth variance across all keyframes (meters).
    /// Average of all per-frame variance values.
    public let meanVariance: Float

    /// Variance stability score (0.0 - 1.0+).
    /// Measures consistency of depth variation across time.
    /// Formula: 1.0 - (stddev(variances) / mean(variances))
    /// Threshold: > 0.8 for real scene
    public let varianceStability: Float

    /// Temporal edge coherence score (0.0 - 1.0).
    /// Average edge coherence across all keyframes.
    /// Higher values indicate consistent depth gradients over time.
    public let temporalCoherence: Float

    /// Final determination: does the video represent a real 3D scene over time?
    /// Requires: all keyframes pass individual checks AND variance_stability > 0.8
    public let isLikelyRealScene: Bool

    /// Number of keyframes analyzed (typically ~10 fps for video).
    /// Expected: ~150 keyframes for 15s video at 10fps
    public let keyframeCount: Int

    /// Algorithm version for server compatibility verification.
    /// Must match backend temporal analysis version ("1.0").
    public let algorithmVersion: String

    // MARK: - Initialization

    /// Creates a new TemporalDepthAnalysisResult with all metrics.
    ///
    /// - Parameters:
    ///   - keyframeAnalyses: Per-keyframe analysis results
    ///   - meanVariance: Average depth variance across keyframes (meters)
    ///   - varianceStability: Variance stability score (0.0-1.0+)
    ///   - temporalCoherence: Average temporal edge coherence (0.0-1.0)
    ///   - isLikelyRealScene: Final temporal authenticity determination
    ///   - keyframeCount: Number of keyframes analyzed
    ///   - algorithmVersion: Algorithm version (defaults to "1.0")
    public init(
        keyframeAnalyses: [DepthAnalysisResult],
        meanVariance: Float,
        varianceStability: Float,
        temporalCoherence: Float,
        isLikelyRealScene: Bool,
        keyframeCount: Int,
        algorithmVersion: String = "1.0"
    ) {
        self.keyframeAnalyses = keyframeAnalyses
        self.meanVariance = meanVariance
        self.varianceStability = varianceStability
        self.temporalCoherence = temporalCoherence
        self.isLikelyRealScene = isLikelyRealScene
        self.keyframeCount = keyframeCount
        self.algorithmVersion = algorithmVersion
    }
}

// MARK: - CustomStringConvertible

extension TemporalDepthAnalysisResult: CustomStringConvertible {
    public var description: String {
        """
        TemporalDepthAnalysisResult(
            keyframeCount: \(keyframeCount),
            meanVariance: \(String(format: "%.3f", meanVariance))m,
            varianceStability: \(String(format: "%.3f", varianceStability)),
            temporalCoherence: \(String(format: "%.3f", temporalCoherence)),
            isRealScene: \(isLikelyRealScene),
            version: \(algorithmVersion)
        )
        """
    }
}
