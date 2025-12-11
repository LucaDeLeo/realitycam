//
//  ConfidenceAggregator.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Confidence aggregation service (Story 9-4).
//  Combines LiDAR, Moire, Texture, and Artifact detection signals
//  into a single weighted confidence score per PRD specifications.
//

import Foundation
import os.log

// MARK: - ConfidenceAggregator

/// Service for aggregating detection method results into unified confidence.
///
/// ## Algorithm Overview
/// The aggregator combines multiple detection signals using PRD-specified weights:
/// 1. LiDAR (PRIMARY): 55% weight - hardware-based physical signal
/// 2. Moire (SUPPORTING): 15% weight - screen pixel grid detection
/// 3. Texture (SUPPORTING): 15% weight - material classification
/// 4. Artifacts (SUPPORTING): 15% weight - PWM/halftone/specular detection
///
/// The process:
/// 1. Normalize each detection result to 0.0-1.0 authenticity score
/// 2. Determine available methods and redistribute weights proportionally
/// 3. Compute weighted sum
/// 4. Check cross-validation agreement between methods
/// 5. Apply agreement bonus (+5%) or disagreement cap (MEDIUM)
/// 6. Determine confidence level from thresholds
///
/// ## Trust Model (from PRD)
/// Per USENIX Security 2025 Chimera attack research:
/// - LiDAR is PRIMARY (hardware signal, prohibitively expensive to spoof)
/// - Detection algorithms are SUPPORTING (can be bypassed with effort)
/// - Cross-validation catches inconsistencies
/// - Disagreement flags potential manipulation
///
/// ## Performance
/// - Target: <10ms (pure computation, no I/O)
/// - Memory: <5MB during aggregation
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because:
/// 1. It has no mutable state (stateless computation)
/// 2. All work is performed on background queues
/// 3. Public API uses async/await with proper continuation handling
///
/// ## Usage
/// ```swift
/// let result = await ConfidenceAggregator.shared.aggregate(
///     depth: depthResult,
///     moire: moireResult,
///     texture: textureResult,
///     artifacts: artifactResult
/// )
/// ```
public final class ConfidenceAggregator: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance.
    public static let shared = ConfidenceAggregator()

    // MARK: - Properties

    /// Logger for confidence aggregation events.
    private static let logger = Logger(subsystem: "app.rial", category: "confidenceaggregation")

    /// Signpost log for performance tracking.
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    // MARK: - Initialization

    /// Private initializer for singleton pattern.
    private init() {
        Self.logger.debug("ConfidenceAggregator initialized")
    }

    // MARK: - Public API

    /// Aggregates all detection method results into unified confidence.
    ///
    /// This method combines results from LiDAR depth analysis, moire pattern detection,
    /// texture classification, and artifact detection using PRD-specified weights.
    ///
    /// Handles graceful degradation when some methods are unavailable:
    /// - Weights are redistributed proportionally to available methods
    /// - Partial analysis flag is added
    /// - Confidence level may be capped based on available signal quality
    ///
    /// - Parameters:
    ///   - depth: LiDAR depth analysis result (optional, 55% weight)
    ///   - moire: Moire pattern detection result (optional, 15% weight)
    ///   - texture: Texture classification result (optional, 15% weight)
    ///   - artifacts: Artifact detection result (optional, 15% weight)
    /// - Returns: Aggregated confidence result with overall score and breakdown
    public func aggregate(
        depth: DepthAnalysisResult? = nil,
        moire: MoireAnalysisResult? = nil,
        texture: TextureClassificationResult? = nil,
        artifacts: ArtifactAnalysisResult? = nil
    ) async -> AggregatedConfidenceResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let startTime = CFAbsoluteTimeGetCurrent()

                let result = self.performAggregation(
                    depth: depth,
                    moire: moire,
                    texture: texture,
                    artifacts: artifacts
                )

                let elapsed = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                let finalResult = result.with(analysisTimeMs: elapsed)

                Self.logger.info("""
                    Confidence aggregation complete in \(elapsed)ms:
                    overallConfidence=\(String(format: "%.3f", finalResult.overallConfidence)),
                    level=\(finalResult.confidenceLevel.rawValue),
                    primary=\(finalResult.primarySignalValid),
                    agree=\(finalResult.supportingSignalsAgree),
                    flags=\(finalResult.flags.map(\.rawValue))
                    """)

                if elapsed > ConfidenceAggregationConstants.maxTimeMs {
                    Self.logger.warning("""
                        Aggregation exceeded target time: \(elapsed)ms > \(ConfidenceAggregationConstants.maxTimeMs)ms
                        """)
                }

                continuation.resume(returning: finalResult)
            }
        }
    }

    // MARK: - Internal Aggregation

    /// Performs the actual aggregation computation.
    private func performAggregation(
        depth: DepthAnalysisResult?,
        moire: MoireAnalysisResult?,
        texture: TextureClassificationResult?,
        artifacts: ArtifactAnalysisResult?
    ) -> AggregatedConfidenceResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "ConfidenceAggregation", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "ConfidenceAggregation", signpostID: signpostID)
        }

        // Check if any methods available
        let hasDepth = depth != nil && depth?.status == .completed
        let hasMoire = moire != nil && moire?.status == .completed
        let hasTexture = texture != nil && texture?.status == .success
        let hasArtifacts = artifacts != nil && artifacts?.status == .success

        if !hasDepth && !hasMoire && !hasTexture && !hasArtifacts {
            Self.logger.warning("No detection methods available for aggregation")
            return .unavailable()
        }

        // Normalize scores
        let depthScore = normalizeDepth(depth)
        let moireScore = normalizeMoire(moire)
        let textureScore = normalizeTexture(texture)
        let artifactsScore = normalizeArtifacts(artifacts)

        Self.logger.debug("""
            Normalized scores:
            depth=\(depthScore.map { String(format: "%.3f", $0) } ?? "nil"),
            moire=\(moireScore.map { String(format: "%.3f", $0) } ?? "nil"),
            texture=\(textureScore.map { String(format: "%.3f", $0) } ?? "nil"),
            artifacts=\(artifactsScore.map { String(format: "%.3f", $0) } ?? "nil")
            """)

        // Calculate redistributed weights
        let weights = redistributeWeights(
            hasDepth: hasDepth,
            hasMoire: hasMoire,
            hasTexture: hasTexture,
            hasArtifacts: hasArtifacts
        )

        // Build method breakdown
        var methodBreakdown: [DetectionMethod: MethodResult] = [:]

        // LiDAR
        let lidarWeight = weights[.lidar] ?? 0
        let lidarContribution = (depthScore ?? 0) * lidarWeight
        methodBreakdown[.lidar] = MethodResult(
            available: hasDepth,
            score: depthScore,
            weight: lidarWeight,
            contribution: lidarContribution,
            status: hasDepth ? (depth!.isLikelyRealScene ? "pass" : "fail") : "unavailable"
        )

        // Moire
        let moireWeight = weights[.moire] ?? 0
        let moireContribution = (moireScore ?? 0) * moireWeight
        methodBreakdown[.moire] = MethodResult(
            available: hasMoire,
            score: moireScore,
            weight: moireWeight,
            contribution: moireContribution,
            status: hasMoire ? (moire!.detected ? "fail" : "pass") : "unavailable"
        )

        // Texture
        let textureWeight = weights[.texture] ?? 0
        let textureContribution = (textureScore ?? 0) * textureWeight
        methodBreakdown[.texture] = MethodResult(
            available: hasTexture,
            score: textureScore,
            weight: textureWeight,
            contribution: textureContribution,
            status: hasTexture ? (texture!.isLikelyRecaptured ? "fail" : "pass") : "unavailable"
        )

        // Artifacts
        let artifactsWeight = weights[.artifacts] ?? 0
        let artifactsContribution = (artifactsScore ?? 0) * artifactsWeight
        methodBreakdown[.artifacts] = MethodResult(
            available: hasArtifacts,
            score: artifactsScore,
            weight: artifactsWeight,
            contribution: artifactsContribution,
            status: hasArtifacts ? (artifacts!.isLikelyArtificial ? "fail" : "pass") : "unavailable"
        )

        // Compute weighted sum
        var overallConfidence = lidarContribution + moireContribution + textureContribution + artifactsContribution

        // Check cross-validation
        let (agree, crossFlags) = checkCrossValidation(
            depth: depth,
            moire: moire,
            texture: texture,
            artifacts: artifacts
        )

        // Apply agreement boost or disagreement cap
        var flags = crossFlags
        let supportingSignalsAgree = agree && crossFlags.isEmpty

        if supportingSignalsAgree && hasDepth && hasMoire && hasTexture && hasArtifacts {
            // Full agreement across all methods: +5% boost
            overallConfidence = min(1.0, overallConfidence + ConfidenceAggregationConstants.agreementBoost)
            Self.logger.debug("Applied +5% agreement boost")
        }

        // Determine primary signal validity
        let primarySignalValid = depth?.isLikelyRealScene ?? false

        // Generate additional flags
        flags.append(contentsOf: generateFlags(
            depth: depth,
            moire: moire,
            texture: texture,
            artifacts: artifacts,
            hasDepth: hasDepth,
            hasMoire: hasMoire,
            hasTexture: hasTexture,
            hasArtifacts: hasArtifacts,
            depthScore: depthScore,
            moireScore: moireScore,
            textureScore: textureScore,
            artifactsScore: artifactsScore
        ))

        // Remove duplicates
        flags = Array(Set(flags))

        // Determine confidence level
        var confidenceLevel = determineConfidenceLevel(
            confidence: overallConfidence,
            primaryValid: primarySignalValid,
            allMethodsAvailable: hasDepth && hasMoire && hasTexture && hasArtifacts,
            allAgree: supportingSignalsAgree
        )

        // Apply caps based on detected issues
        if flags.contains(.screenDetected) || flags.contains(.printDetected) {
            if confidenceLevel > .medium {
                confidenceLevel = .medium
                Self.logger.debug("Capped confidence at MEDIUM due to screen/print detection")
            }
        }

        if flags.contains(.methodsDisagree) || flags.contains(.primarySupportingDisagree) {
            if confidenceLevel > ConfidenceAggregationConstants.disagreementCap {
                confidenceLevel = ConfidenceAggregationConstants.disagreementCap
                Self.logger.debug("Capped confidence at \(confidenceLevel.rawValue) due to disagreement")
            }
        }

        // Determine status
        let status: AggregationStatus
        if hasDepth && hasMoire && hasTexture && hasArtifacts {
            status = .success
        } else if hasDepth || hasMoire || hasTexture || hasArtifacts {
            status = .partial
        } else {
            status = .unavailable
        }

        return AggregatedConfidenceResult(
            overallConfidence: overallConfidence,
            confidenceLevel: confidenceLevel,
            methodBreakdown: methodBreakdown,
            primarySignalValid: primarySignalValid,
            supportingSignalsAgree: supportingSignalsAgree,
            flags: flags.sorted { $0.rawValue < $1.rawValue },
            analysisTimeMs: 0, // Will be updated after timing
            status: status
        )
    }

    // MARK: - Score Normalization

    /// Normalizes LiDAR depth result to 0.0-1.0 authenticity score.
    ///
    /// Score interpretation:
    /// - 1.0 = Strong evidence of real 3D scene
    /// - 0.0 = Flat scene (likely screen/print)
    ///
    /// Scoring:
    /// - Real scene: Base 0.8 + bonuses for variance/layers (up to 1.0)
    /// - Not real scene: Base 0.2 - penalties for flatness (down to 0.0)
    private func normalizeDepth(_ result: DepthAnalysisResult?) -> Float? {
        guard let result = result, result.status == .completed else {
            return nil
        }

        if result.isLikelyRealScene {
            // Real scene: base 0.8, add bonuses
            let baseScore: Float = 0.8
            // Bonus from depth variance (higher = more 3D structure)
            let varianceBonus = min(result.depthVariance / 2.0, 0.1)
            // Bonus from depth layers (more layers = more complex scene)
            let layerBonus = min(Float(result.depthLayers) / 10.0, 0.1)
            return min(baseScore + varianceBonus + layerBonus, 1.0)
        } else {
            // Not real scene: base 0.2, lower if especially flat
            let baseScore: Float = 0.2
            // Penalty if very flat (low variance and layers)
            let flatnessPenalty: Float
            if result.depthVariance < 0.2 && result.depthLayers <= 2 {
                flatnessPenalty = 0.1
            } else {
                flatnessPenalty = 0.0
            }
            return max(baseScore - flatnessPenalty, 0.0)
        }
    }

    /// Normalizes Moire detection result to 0.0-1.0 authenticity score.
    ///
    /// INVERTED: Screen detected = LOW score (less authentic)
    /// - No screen detected -> 1.0
    /// - Screen detected with high confidence -> low score
    private func normalizeMoire(_ result: MoireAnalysisResult?) -> Float? {
        guard let result = result, result.status == .completed else {
            return nil
        }

        if result.detected {
            // Screen detected: invert confidence
            // High confidence screen = low authenticity
            return 1.0 - result.confidence
        } else {
            // No screen: high authenticity
            return 1.0
        }
    }

    /// Normalizes Texture classification result to 0.0-1.0 authenticity score.
    ///
    /// Real scene = high score, screen/print = low score
    private func normalizeTexture(_ result: TextureClassificationResult?) -> Float? {
        guard let result = result, result.status == .success else {
            return nil
        }

        // Check primary classification
        if result.classification == .realScene {
            return result.confidence
        } else if result.isLikelyRecaptured {
            // Screen or print detected: invert
            return 1.0 - result.confidence
        } else {
            // Unknown or ambiguous: return moderate score
            return 0.5
        }
    }

    /// Normalizes Artifact detection result to 0.0-1.0 authenticity score.
    ///
    /// INVERTED: Artifacts detected = LOW score (less authentic)
    private func normalizeArtifacts(_ result: ArtifactAnalysisResult?) -> Float? {
        guard let result = result, result.status == .success else {
            return nil
        }

        if result.isLikelyArtificial {
            // Artifacts detected: invert confidence
            return 1.0 - result.overallConfidence
        } else {
            // Clean: high authenticity
            return 1.0
        }
    }

    // MARK: - Weight Redistribution

    /// Redistributes weights from unavailable methods proportionally.
    ///
    /// If a method is unavailable, its weight is distributed to available methods
    /// in proportion to their base weights.
    private func redistributeWeights(
        hasDepth: Bool,
        hasMoire: Bool,
        hasTexture: Bool,
        hasArtifacts: Bool
    ) -> [DetectionMethod: Float] {
        let baseWeights: [DetectionMethod: Float] = [
            .lidar: ConfidenceAggregationConstants.lidarWeight,
            .moire: ConfidenceAggregationConstants.moireWeight,
            .texture: ConfidenceAggregationConstants.textureWeight,
            .artifacts: ConfidenceAggregationConstants.artifactsWeight
        ]

        let available: [DetectionMethod: Bool] = [
            .lidar: hasDepth,
            .moire: hasMoire,
            .texture: hasTexture,
            .artifacts: hasArtifacts
        ]

        // Calculate total available weight
        let totalAvailable = available.reduce(Float(0)) { sum, pair in
            pair.value ? sum + (baseWeights[pair.key] ?? 0) : sum
        }

        guard totalAvailable > 0 else {
            return [:]
        }

        // Normalize to sum = 1.0
        var redistributed: [DetectionMethod: Float] = [:]
        for method in DetectionMethod.allCases {
            if available[method] == true {
                redistributed[method] = (baseWeights[method] ?? 0) / totalAvailable
            } else {
                redistributed[method] = 0
            }
        }

        Self.logger.debug("""
            Weight redistribution:
            lidar=\(String(format: "%.3f", redistributed[.lidar] ?? 0)),
            moire=\(String(format: "%.3f", redistributed[.moire] ?? 0)),
            texture=\(String(format: "%.3f", redistributed[.texture] ?? 0)),
            artifacts=\(String(format: "%.3f", redistributed[.artifacts] ?? 0))
            """)

        return redistributed
    }

    // MARK: - Cross-Validation

    /// Checks cross-validation agreement between detection methods.
    ///
    /// Returns (allAgree, flags) tuple:
    /// - allAgree: true if no contradictions found
    /// - flags: array of specific disagreement flags
    private func checkCrossValidation(
        depth: DepthAnalysisResult?,
        moire: MoireAnalysisResult?,
        texture: TextureClassificationResult?,
        artifacts: ArtifactAnalysisResult?
    ) -> (agree: Bool, flags: [ConfidenceFlag]) {
        var flags: [ConfidenceFlag] = []

        // Get binary determinations from each method
        let lidarSaysReal: Bool? = depth?.status == .completed ? depth!.isLikelyRealScene : nil
        let moireSaysNoScreen: Bool? = moire?.status == .completed ? !moire!.detected : nil
        let textureSaysNatural: Bool? = texture?.status == .success ?
            (texture!.classification == .realScene && !texture!.isLikelyRecaptured) : nil
        let artifactsSaysClean: Bool? = artifacts?.status == .success ? !artifacts!.isLikelyArtificial : nil

        // Check primary vs supporting agreement
        if let real = lidarSaysReal {
            if let noScreen = moireSaysNoScreen, noScreen != real {
                flags.append(.primarySupportingDisagree)
            }
            if let natural = textureSaysNatural, natural != real {
                flags.append(.primarySupportingDisagree)
            }
            if let clean = artifactsSaysClean, clean != real {
                flags.append(.primarySupportingDisagree)
            }
        }

        // Check supporting vs supporting agreement
        let supportingSignals = [moireSaysNoScreen, textureSaysNatural, artifactsSaysClean].compactMap { $0 }
        if supportingSignals.count >= 2 {
            let allSame = supportingSignals.allSatisfy { $0 == supportingSignals.first }
            if !allSame {
                flags.append(.methodsDisagree)
            }
        }

        // Remove duplicates
        let uniqueFlags = Array(Set(flags))

        return (uniqueFlags.isEmpty, uniqueFlags)
    }

    // MARK: - Flag Generation

    /// Generates additional flags based on detection results.
    private func generateFlags(
        depth: DepthAnalysisResult?,
        moire: MoireAnalysisResult?,
        texture: TextureClassificationResult?,
        artifacts: ArtifactAnalysisResult?,
        hasDepth: Bool,
        hasMoire: Bool,
        hasTexture: Bool,
        hasArtifacts: Bool,
        depthScore: Float?,
        moireScore: Float?,
        textureScore: Float?,
        artifactsScore: Float?
    ) -> [ConfidenceFlag] {
        var flags: [ConfidenceFlag] = []

        // Primary signal failed
        if let depth = depth, depth.status == .completed, !depth.isLikelyRealScene {
            flags.append(.primarySignalFailed)
        }

        // Screen detected (moire or texture)
        if let moire = moire, moire.status == .completed, moire.detected, moire.confidence > 0.5 {
            flags.append(.screenDetected)
        }
        if let texture = texture, texture.status == .success {
            if texture.classification == .lcdScreen || texture.classification == .oledScreen {
                flags.append(.screenDetected)
            }
        }

        // Print detected (halftone)
        if let artifacts = artifacts, artifacts.status == .success,
           artifacts.halftoneDetected, artifacts.halftoneConfidence > 0.5 {
            flags.append(.printDetected)
        }
        if let texture = texture, texture.status == .success,
           texture.classification == .printedPaper {
            flags.append(.printDetected)
        }

        // Partial analysis
        if !hasDepth || !hasMoire || !hasTexture || !hasArtifacts {
            flags.append(.partialAnalysis)
        }

        // Low confidence primary
        if let score = depthScore, score < ConfidenceAggregationConstants.lowConfidenceLidarThreshold,
           depth?.isLikelyRealScene == true {
            flags.append(.lowConfidencePrimary)
        }

        // Ambiguous results (multiple borderline scores)
        var ambiguousCount = 0
        let scores = [depthScore, moireScore, textureScore, artifactsScore].compactMap { $0 }
        for score in scores {
            if score >= ConfidenceAggregationConstants.ambiguousScoreLow &&
               score <= ConfidenceAggregationConstants.ambiguousScoreHigh {
                ambiguousCount += 1
            }
        }
        if ambiguousCount >= 2 {
            flags.append(.ambiguousResults)
        }

        return flags
    }

    // MARK: - Confidence Level Determination

    /// Determines confidence level from score and conditions.
    private func determineConfidenceLevel(
        confidence: Float,
        primaryValid: Bool,
        allMethodsAvailable: Bool,
        allAgree: Bool
    ) -> AggregatedConfidenceLevel {
        // VERY_HIGH requires: threshold + all available + all agree + primary pass
        if confidence >= ConfidenceAggregationConstants.veryHighThreshold &&
           allMethodsAvailable && allAgree && primaryValid {
            return .veryHigh
        }

        // HIGH requires: threshold + primary pass
        if confidence >= ConfidenceAggregationConstants.highThreshold && primaryValid {
            return .high
        }

        // MEDIUM requires: threshold
        if confidence >= ConfidenceAggregationConstants.mediumThreshold {
            return .medium
        }

        // LOW requires: threshold
        if confidence >= ConfidenceAggregationConstants.lowThreshold {
            return .low
        }

        // SUSPICIOUS: below all thresholds
        return .suspicious
    }
}
