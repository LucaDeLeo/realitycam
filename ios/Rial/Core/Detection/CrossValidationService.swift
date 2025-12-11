//
//  CrossValidationService.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Cross-validation service for enhanced detection (Story 9-5).
//  Pairwise correlation, temporal consistency, and anomaly detection.
//

import Foundation
import os.log

// MARK: - CrossValidationService

/// Service for cross-validating detection method results.
///
/// ## Algorithm Overview
/// Enhanced cross-validation catches sophisticated attacks by:
/// 1. **Pairwise consistency** - Verify expected relationships between method pairs
/// 2. **Temporal consistency** - Track score stability across frames (video/burst)
/// 3. **Confidence intervals** - Communicate uncertainty, not just point estimates
/// 4. **Anomaly detection** - Flag contradictory, too-perfect, or suspicious patterns
///
/// ## Performance
/// - Single-frame analysis: <5ms
/// - Multi-frame (30 frames): <20ms
/// - Memory: <5MB during analysis
///
/// ## Security Note
/// This service specifically targets attacks that:
/// - Pass individual methods but have wrong correlations
/// - Manipulate frame-by-frame in video
/// - Produce suspiciously perfect or boundary-hugging scores
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because:
/// 1. It has no mutable state (stateless computation)
/// 2. All work is performed on background queues
/// 3. Public API uses async/await with proper continuation handling
///
/// ## Usage
/// ```swift
/// let result = await CrossValidationService.shared.validate(
///     depth: depthResult,
///     moire: moireResult,
///     texture: textureResult,
///     artifacts: artifactResult
/// )
/// ```
public final class CrossValidationService: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance.
    public static let shared = CrossValidationService()

    // MARK: - Properties

    /// Logger for cross-validation events.
    private static let logger = Logger(subsystem: "app.rial", category: "crossvalidation")

    /// Signpost log for performance tracking.
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    // MARK: - Initialization

    /// Private initializer for singleton pattern.
    private init() {
        Self.logger.debug("CrossValidationService initialized")
    }

    // MARK: - Public API

    /// Validates single-frame detection results through cross-validation.
    ///
    /// - Parameters:
    ///   - depth: LiDAR depth analysis result (optional)
    ///   - moire: Moire pattern detection result (optional)
    ///   - texture: Texture classification result (optional)
    ///   - artifacts: Artifact detection result (optional)
    /// - Returns: CrossValidationResult with consistency analysis
    public func validate(
        depth: DepthAnalysisResult? = nil,
        moire: MoireAnalysisResult? = nil,
        texture: TextureClassificationResult? = nil,
        artifacts: ArtifactAnalysisResult? = nil
    ) async -> CrossValidationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let startTime = CFAbsoluteTimeGetCurrent()

                let result = self.performValidation(
                    depth: depth,
                    moire: moire,
                    texture: texture,
                    artifacts: artifacts
                )

                let elapsed = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

                Self.logger.info("""
                    Cross-validation complete in \(elapsed)ms:
                    status=\(result.validationStatus.rawValue),
                    anomalies=\(result.anomalies.count),
                    penalty=\(String(format: "%.3f", result.overallPenalty))
                    """)

                if elapsed > CrossValidationConstants.targetSingleFrameTimeMs {
                    Self.logger.warning("""
                        Cross-validation exceeded target time: \(elapsed)ms > \(CrossValidationConstants.targetSingleFrameTimeMs)ms
                        """)
                }

                // Update with actual elapsed time
                let finalResult = CrossValidationResult(
                    validationStatus: result.validationStatus,
                    pairwiseConsistencies: result.pairwiseConsistencies,
                    temporalConsistency: result.temporalConsistency,
                    confidenceIntervals: result.confidenceIntervalsByMethod,
                    aggregatedInterval: result.aggregatedInterval,
                    anomalies: result.anomalies,
                    overallPenalty: result.overallPenalty,
                    analysisTimeMs: elapsed
                )

                continuation.resume(returning: finalResult)
            }
        }
    }

    /// Validates multi-frame detection results for temporal consistency.
    ///
    /// - Parameter frames: Set of detection frames to analyze
    /// - Returns: CrossValidationResult with temporal consistency analysis
    public func validateMultiFrame(frames: DetectionFrameSet) async -> CrossValidationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let startTime = CFAbsoluteTimeGetCurrent()

                let result = self.performMultiFrameValidation(frames: frames)

                let elapsed = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

                Self.logger.info("""
                    Multi-frame cross-validation complete in \(elapsed)ms:
                    frames=\(frames.frames.count),
                    status=\(result.validationStatus.rawValue),
                    temporalStability=\(String(format: "%.3f", result.temporalConsistency?.overallStability ?? 1.0))
                    """)

                if elapsed > CrossValidationConstants.targetMultiFrameTimeMs {
                    Self.logger.warning("""
                        Multi-frame validation exceeded target: \(elapsed)ms > \(CrossValidationConstants.targetMultiFrameTimeMs)ms
                        """)
                }

                // Update with actual elapsed time
                let finalResult = CrossValidationResult(
                    validationStatus: result.validationStatus,
                    pairwiseConsistencies: result.pairwiseConsistencies,
                    temporalConsistency: result.temporalConsistency,
                    confidenceIntervals: result.confidenceIntervalsByMethod,
                    aggregatedInterval: result.aggregatedInterval,
                    anomalies: result.anomalies,
                    overallPenalty: result.overallPenalty,
                    analysisTimeMs: elapsed
                )

                continuation.resume(returning: finalResult)
            }
        }
    }

    // MARK: - Internal Validation

    /// Performs single-frame validation.
    private func performValidation(
        depth: DepthAnalysisResult?,
        moire: MoireAnalysisResult?,
        texture: TextureClassificationResult?,
        artifacts: ArtifactAnalysisResult?
    ) -> CrossValidationResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "CrossValidation", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "CrossValidation", signpostID: signpostID)
        }

        // Normalize scores
        let depthScore = normalizeDepth(depth)
        let moireScore = normalizeMoire(moire)
        let textureScore = normalizeTexture(texture)
        let artifactsScore = normalizeArtifacts(artifacts)

        let scores: [DetectionMethod: Float?] = [
            .lidar: depthScore,
            .moire: moireScore,
            .texture: textureScore,
            .artifacts: artifactsScore
        ]

        Self.logger.debug("""
            Normalized scores for cross-validation:
            depth=\(depthScore.map { String(format: "%.3f", $0) } ?? "nil"),
            moire=\(moireScore.map { String(format: "%.3f", $0) } ?? "nil"),
            texture=\(textureScore.map { String(format: "%.3f", $0) } ?? "nil"),
            artifacts=\(artifactsScore.map { String(format: "%.3f", $0) } ?? "nil")
            """)

        // Pairwise consistency analysis
        let pairwiseConsistencies = computePairwiseConsistencies(scores: scores)

        // Confidence intervals
        let intervals = computeConfidenceIntervals(scores: scores)
        let aggregatedInterval = computeAggregatedInterval(intervals: intervals)

        // Anomaly detection
        var anomalies: [AnomalyReport] = []
        anomalies.append(contentsOf: detectContradictorySignals(scores: scores))
        anomalies.append(contentsOf: detectTooPerfectAgreement(scores: scores))
        anomalies.append(contentsOf: detectIsolatedDisagreement(scores: scores))
        anomalies.append(contentsOf: detectBoundaryClustering(scores: scores))
        anomalies.append(contentsOf: detectCorrelationAnomalies(pairwiseConsistencies: pairwiseConsistencies))

        // Compute overall penalty and status
        let overallPenalty = computeOverallPenalty(anomalies: anomalies)
        let validationStatus = determineValidationStatus(anomalies: anomalies)

        return CrossValidationResult(
            validationStatus: validationStatus,
            pairwiseConsistencies: pairwiseConsistencies,
            temporalConsistency: nil,
            confidenceIntervals: intervals,
            aggregatedInterval: aggregatedInterval,
            anomalies: anomalies,
            overallPenalty: overallPenalty,
            analysisTimeMs: 0
        )
    }

    /// Performs multi-frame validation with temporal analysis.
    private func performMultiFrameValidation(frames: DetectionFrameSet) -> CrossValidationResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "MultiFrameCrossValidation", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "MultiFrameCrossValidation", signpostID: signpostID)
        }

        guard !frames.frames.isEmpty else {
            return .unavailable()
        }

        // Use last frame for single-frame analysis
        let lastFrame = frames.frames.last!
        let singleFrameResult = performValidation(
            depth: lastFrame.depth,
            moire: lastFrame.moire,
            texture: lastFrame.texture,
            artifacts: lastFrame.artifacts
        )

        // Compute temporal consistency
        let temporalConsistency = computeTemporalConsistency(frames: frames)

        // Add temporal anomalies to anomaly list
        var allAnomalies = singleFrameResult.anomalies
        if !temporalConsistency.anomalies.isEmpty {
            allAnomalies.append(AnomalyReport(
                anomalyType: .correlationAnomaly,
                severity: temporalConsistency.anomalies.count >= 3 ? .high : .medium,
                affectedMethods: Array(Set(temporalConsistency.anomalies.map(\.method))),
                details: "Temporal instability: \(temporalConsistency.anomalies.count) anomalies detected",
                confidenceImpact: Float(temporalConsistency.anomalies.count) * 0.05
            ))
        }

        // Recompute penalty and status with temporal anomalies
        let overallPenalty = computeOverallPenalty(anomalies: allAnomalies)
        let validationStatus = determineValidationStatus(anomalies: allAnomalies)

        return CrossValidationResult(
            validationStatus: validationStatus,
            pairwiseConsistencies: singleFrameResult.pairwiseConsistencies,
            temporalConsistency: temporalConsistency,
            confidenceIntervals: singleFrameResult.confidenceIntervalsByMethod,
            aggregatedInterval: singleFrameResult.aggregatedInterval,
            anomalies: allAnomalies,
            overallPenalty: overallPenalty,
            analysisTimeMs: 0
        )
    }

    // MARK: - Score Normalization

    /// Normalizes LiDAR depth result to 0.0-1.0 authenticity score.
    /// Delegates to ConfidenceAggregator's shared implementation.
    private func normalizeDepth(_ result: DepthAnalysisResult?) -> Float? {
        ConfidenceAggregator.normalizeDepth(result)
    }

    /// Normalizes Moire detection result to 0.0-1.0 authenticity score.
    /// Delegates to ConfidenceAggregator's shared implementation.
    private func normalizeMoire(_ result: MoireAnalysisResult?) -> Float? {
        ConfidenceAggregator.normalizeMoire(result)
    }

    /// Normalizes Texture classification result to 0.0-1.0 authenticity score.
    /// Delegates to ConfidenceAggregator's shared implementation.
    private func normalizeTexture(_ result: TextureClassificationResult?) -> Float? {
        ConfidenceAggregator.normalizeTexture(result)
    }

    /// Normalizes Artifact detection result to 0.0-1.0 authenticity score.
    /// Delegates to ConfidenceAggregator's shared implementation.
    private func normalizeArtifacts(_ result: ArtifactAnalysisResult?) -> Float? {
        ConfidenceAggregator.normalizeArtifacts(result)
    }

    // MARK: - Pairwise Consistency Analysis

    /// Computes pairwise consistency for all method pairs.
    private func computePairwiseConsistencies(scores: [DetectionMethod: Float?]) -> [PairwiseConsistency] {
        var results: [PairwiseConsistency] = []

        // Define all pairs with expected relationships
        let pairs: [(DetectionMethod, DetectionMethod, Float, ExpectedRelationship)] = [
            (.lidar, .moire, CrossValidationConstants.lidarMoireExpected, .negative),
            (.lidar, .texture, CrossValidationConstants.lidarTextureExpected, .positive),
            (.lidar, .artifacts, CrossValidationConstants.lidarArtifactsExpected, .negative),
            (.moire, .texture, CrossValidationConstants.moireTextureExpected, .positive),
            (.moire, .artifacts, CrossValidationConstants.moireArtifactsExpected, .positive),
            (.texture, .artifacts, CrossValidationConstants.textureArtifactsExpected, .negative)
        ]

        for (methodA, methodB, expectedValue, relationship) in pairs {
            guard let scoreA = scores[methodA] ?? nil,
                  let scoreB = scores[methodB] ?? nil else {
                continue
            }

            // Compute actual agreement based on score similarity
            // For positive relationship: similar scores = agreement
            // For negative relationship: opposite scores = agreement
            let actualAgreement: Float
            switch relationship {
            case .positive:
                // Higher when both high or both low
                actualAgreement = 1.0 - abs(scoreA - scoreB)
            case .negative:
                // Higher when one high and one low
                actualAgreement = abs(scoreA - scoreB)
            case .neutral:
                actualAgreement = 0.5
            }

            // Normalize to -1 to 1 range for comparison
            let normalizedActual = (actualAgreement - 0.5) * 2.0

            // Compute anomaly score as deviation from expected
            let expectedNormalized = expectedValue
            let deviation = abs(normalizedActual - expectedNormalized)
            let anomalyScore = deviation

            let isAnomaly = anomalyScore > CrossValidationConstants.pairwiseAnomalyThreshold

            results.append(PairwiseConsistency(
                methodA: methodA,
                methodB: methodB,
                expectedRelationship: relationship,
                actualAgreement: normalizedActual,
                anomalyScore: anomalyScore,
                isAnomaly: isAnomaly
            ))
        }

        return results
    }

    // MARK: - Confidence Interval Computation

    /// Computes confidence intervals for each detection method.
    private func computeConfidenceIntervals(scores: [DetectionMethod: Float?]) -> [DetectionMethod: ConfidenceInterval] {
        var intervals: [DetectionMethod: ConfidenceInterval] = [:]

        for (method, score) in scores {
            guard let pointEstimate = score else {
                continue
            }

            // Base interval width per method
            let baseWidth: Float
            switch method {
            case .lidar:
                baseWidth = CrossValidationConstants.lidarIntervalWidth
            case .moire:
                baseWidth = CrossValidationConstants.moireIntervalWidth
            case .texture:
                baseWidth = CrossValidationConstants.textureIntervalWidth
            case .artifacts:
                baseWidth = CrossValidationConstants.artifactsIntervalWidth
            }

            // Widen interval for mid-range scores (more uncertain)
            let uncertaintyFactor: Float
            if pointEstimate >= 0.4 && pointEstimate <= 0.6 {
                uncertaintyFactor = 1.0 + CrossValidationConstants.midRangeUncertaintyBoost
            } else {
                uncertaintyFactor = 1.0
            }

            let halfWidth = (baseWidth * uncertaintyFactor) / 2.0
            let lowerBound = max(0, pointEstimate - halfWidth)
            let upperBound = min(1, pointEstimate + halfWidth)

            intervals[method] = ConfidenceInterval(
                lowerBound: lowerBound,
                pointEstimate: pointEstimate,
                upperBound: upperBound
            )
        }

        return intervals
    }

    /// Computes aggregated confidence interval from individual intervals.
    private func computeAggregatedInterval(intervals: [DetectionMethod: ConfidenceInterval]) -> ConfidenceInterval {
        guard !intervals.isEmpty else {
            return ConfidenceInterval(lowerBound: 0, pointEstimate: 0, upperBound: 0)
        }

        // Weighted combination based on method reliability
        var weightedLower: Float = 0
        var weightedPoint: Float = 0
        var weightedUpper: Float = 0
        var totalWeight: Float = 0

        let weights: [DetectionMethod: Float] = [
            .lidar: ConfidenceAggregationConstants.lidarWeight,
            .moire: ConfidenceAggregationConstants.moireWeight,
            .texture: ConfidenceAggregationConstants.textureWeight,
            .artifacts: ConfidenceAggregationConstants.artifactsWeight
        ]

        for (method, interval) in intervals {
            let weight = weights[method] ?? 0.25
            weightedLower += interval.lowerBound * weight
            weightedPoint += interval.pointEstimate * weight
            weightedUpper += interval.upperBound * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            return ConfidenceInterval(lowerBound: 0, pointEstimate: 0, upperBound: 0)
        }

        return ConfidenceInterval(
            lowerBound: weightedLower / totalWeight,
            pointEstimate: weightedPoint / totalWeight,
            upperBound: weightedUpper / totalWeight
        )
    }

    // MARK: - Temporal Consistency Analysis

    /// Computes temporal consistency from multi-frame detection results.
    private func computeTemporalConsistency(frames: DetectionFrameSet) -> TemporalConsistency {
        guard frames.frames.count > 1 else {
            return .singleFrame()
        }

        // Extract scores per method across frames
        var methodScores: [DetectionMethod: [Float]] = [
            .lidar: [],
            .moire: [],
            .texture: [],
            .artifacts: []
        ]

        for frame in frames.frames {
            if let depthScore = normalizeDepth(frame.depth) {
                methodScores[.lidar]?.append(depthScore)
            }
            if let moireScore = normalizeMoire(frame.moire) {
                methodScores[.moire]?.append(moireScore)
            }
            if let textureScore = normalizeTexture(frame.texture) {
                methodScores[.texture]?.append(textureScore)
            }
            if let artifactsScore = normalizeArtifacts(frame.artifacts) {
                methodScores[.artifacts]?.append(artifactsScore)
            }
        }

        // Compute stability score and detect anomalies per method
        var stabilityScores: [DetectionMethod: Float] = [:]
        var anomalies: [TemporalAnomaly] = []

        for (method, scores) in methodScores {
            guard scores.count > 1 else {
                continue
            }

            // Compute variance
            let mean = scores.reduce(0, +) / Float(scores.count)
            let variance = scores.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(scores.count)

            // Stability score: 1.0 - normalized variance
            let stabilityScore = max(0, 1.0 - (variance / CrossValidationConstants.maxExpectedVariance))
            stabilityScores[method] = stabilityScore

            // Detect sudden jumps
            for i in 1..<scores.count {
                let delta = abs(scores[i] - scores[i - 1])
                if delta > CrossValidationConstants.suddenJumpThreshold {
                    anomalies.append(TemporalAnomaly(
                        frameIndex: i,
                        method: method,
                        deltaScore: delta,
                        type: .suddenJump
                    ))
                }
            }

            // Detect oscillations (alternating high-low pattern)
            if scores.count >= 4 {
                var oscillationCount = 0
                for i in 2..<scores.count {
                    let prevDelta = scores[i - 1] - scores[i - 2]
                    let currDelta = scores[i] - scores[i - 1]
                    if prevDelta * currDelta < 0 && abs(currDelta) > 0.1 {
                        oscillationCount += 1
                    }
                }
                if oscillationCount >= scores.count / 2 {
                    anomalies.append(TemporalAnomaly(
                        frameIndex: scores.count - 1,
                        method: method,
                        deltaScore: Float(oscillationCount),
                        type: .oscillation
                    ))
                }
            }
        }

        // Overall stability is weighted average
        let weights: [DetectionMethod: Float] = [
            .lidar: 0.55,
            .moire: 0.15,
            .texture: 0.15,
            .artifacts: 0.15
        ]

        var overallStability: Float = 0
        var totalWeight: Float = 0
        for (method, stability) in stabilityScores {
            let weight = weights[method] ?? 0.25
            overallStability += stability * weight
            totalWeight += weight
        }

        if totalWeight > 0 {
            overallStability /= totalWeight
        } else {
            overallStability = 1.0
        }

        return TemporalConsistency(
            frameCount: frames.frames.count,
            stabilityScores: stabilityScores,
            anomalies: anomalies,
            overallStability: overallStability
        )
    }

    // MARK: - Anomaly Detection

    /// Detects contradictory signals between methods.
    private func detectContradictorySignals(scores: [DetectionMethod: Float?]) -> [AnomalyReport] {
        var anomalies: [AnomalyReport] = []

        // LiDAR says flat but texture says real
        if let lidar = scores[.lidar] ?? nil,
           let texture = scores[.texture] ?? nil {
            if lidar < 0.3 && texture > 0.7 {
                anomalies.append(AnomalyReport(
                    anomalyType: .contradictorySignals,
                    severity: .high,
                    affectedMethods: [.lidar, .texture],
                    details: "LiDAR indicates flat surface but texture indicates real material",
                    confidenceImpact: CrossValidationConstants.highSeverityPenalty
                ))
            }
        }

        // LiDAR says real but moire says screen
        if let lidar = scores[.lidar] ?? nil,
           let moire = scores[.moire] ?? nil {
            if lidar > 0.7 && moire < 0.3 {
                anomalies.append(AnomalyReport(
                    anomalyType: .contradictorySignals,
                    severity: .high,
                    affectedMethods: [.lidar, .moire],
                    details: "LiDAR indicates real scene but moire indicates screen",
                    confidenceImpact: CrossValidationConstants.highSeverityPenalty
                ))
            }
        }

        return anomalies
    }

    /// Detects too-perfect agreement (all methods exactly agree).
    private func detectTooPerfectAgreement(scores: [DetectionMethod: Float?]) -> [AnomalyReport] {
        let availableScores = scores.compactMap { $0.value }
        guard availableScores.count >= 3 else {
            return []
        }

        let minScore = availableScores.min() ?? 0
        let maxScore = availableScores.max() ?? 0
        let spread = maxScore - minScore

        if spread < CrossValidationConstants.tooPerfectThreshold {
            return [AnomalyReport(
                anomalyType: .tooHighAgreement,
                severity: .medium,
                affectedMethods: DetectionMethod.allCases,
                details: "All methods agree within \(String(format: "%.3f", spread)) - suspiciously identical",
                confidenceImpact: CrossValidationConstants.mediumSeverityPenalty
            )]
        }

        return []
    }

    /// Detects isolated disagreement (one method strongly differs).
    private func detectIsolatedDisagreement(scores: [DetectionMethod: Float?]) -> [AnomalyReport] {
        let availableScores = scores.compactMapValues { $0 }
        guard availableScores.count >= 3 else {
            return []
        }

        let scoreValues = Array(availableScores.values)
        let mean = scoreValues.reduce(0, +) / Float(scoreValues.count)

        var anomalies: [AnomalyReport] = []
        for (method, score) in availableScores {
            let deviation = abs(score - mean)
            if deviation > CrossValidationConstants.isolatedDisagreementThreshold {
                anomalies.append(AnomalyReport(
                    anomalyType: .isolatedDisagreement,
                    severity: deviation > 0.5 ? .high : .medium,
                    affectedMethods: [method],
                    details: "\(method.rawValue) differs by \(String(format: "%.3f", deviation)) from mean",
                    confidenceImpact: deviation > 0.5 ?
                        CrossValidationConstants.highSeverityPenalty :
                        CrossValidationConstants.mediumSeverityPenalty
                ))
            }
        }

        return anomalies
    }

    /// Detects boundary clustering (scores at 0.0, 0.5, or 1.0).
    private func detectBoundaryClustering(scores: [DetectionMethod: Float?]) -> [AnomalyReport] {
        let availableScores = scores.compactMap { $0.value }
        guard availableScores.count >= CrossValidationConstants.minBoundaryClusterCount else {
            return []
        }

        let boundaries: [Float] = [0.0, 0.5, 1.0]
        var boundaryCount = 0

        for score in availableScores {
            for boundary in boundaries {
                if abs(score - boundary) < CrossValidationConstants.boundaryClusterThreshold {
                    boundaryCount += 1
                    break
                }
            }
        }

        if boundaryCount >= CrossValidationConstants.minBoundaryClusterCount {
            return [AnomalyReport(
                anomalyType: .boundaryCluster,
                severity: .medium,
                affectedMethods: DetectionMethod.allCases,
                details: "\(boundaryCount) scores clustered at decision boundaries",
                confidenceImpact: CrossValidationConstants.mediumSeverityPenalty
            )]
        }

        return []
    }

    /// Detects correlation anomalies from pairwise analysis.
    private func detectCorrelationAnomalies(pairwiseConsistencies: [PairwiseConsistency]) -> [AnomalyReport] {
        let anomalousPairs = pairwiseConsistencies.filter { $0.isAnomaly }

        if anomalousPairs.isEmpty {
            return []
        }

        // Group by affected methods
        var affectedMethods = Set<DetectionMethod>()
        for pair in anomalousPairs {
            affectedMethods.insert(pair.methodA)
            affectedMethods.insert(pair.methodB)
        }

        let severity: AnomalySeverity = anomalousPairs.count >= 3 ? .high : .medium

        return [AnomalyReport(
            anomalyType: .correlationAnomaly,
            severity: severity,
            affectedMethods: Array(affectedMethods),
            details: "\(anomalousPairs.count) method pairs show unexpected correlations",
            confidenceImpact: severity == .high ?
                CrossValidationConstants.highSeverityPenalty :
                CrossValidationConstants.mediumSeverityPenalty
        )]
    }

    // MARK: - Penalty and Status Computation

    /// Computes overall penalty from all detected anomalies.
    private func computeOverallPenalty(anomalies: [AnomalyReport]) -> Float {
        let totalImpact = anomalies.reduce(Float(0)) { $0 + $1.confidenceImpact }
        return min(totalImpact, CrossValidationConstants.maxOverallPenalty)
    }

    /// Determines validation status from anomaly analysis.
    private func determineValidationStatus(anomalies: [AnomalyReport]) -> ValidationStatus {
        let highCount = anomalies.filter { $0.severity == .high }.count
        let mediumCount = anomalies.filter { $0.severity == .medium }.count

        if highCount > 0 {
            return .fail
        }

        if mediumCount > CrossValidationConstants.maxMediumAnomaliesForWarn {
            return .fail
        }

        if mediumCount > 0 {
            return .warn
        }

        let lowCount = anomalies.filter { $0.severity == .low }.count
        if lowCount > CrossValidationConstants.maxLowAnomaliesForPass {
            return .warn
        }

        return .pass
    }
}
