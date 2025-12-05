//
//  DepthAnalysisResult.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Result structure for client-side depth analysis (Story 8-1).
//  Provides algorithm parity with backend/src/services/depth_analysis.rs.
//

import Foundation

// MARK: - DepthAnalysisResult

/// Result of client-side depth analysis for privacy mode.
///
/// This struct contains all metrics computed from LiDAR depth data,
/// matching the server-side algorithm exactly for trust model compatibility.
///
/// ## Algorithm Parity
/// All thresholds and formulas match `backend/src/services/depth_analysis.rs`:
/// - variance > 0.5 (std dev in meters)
/// - layers >= 3 (distinct histogram peaks)
/// - coherence > 0.3 (edge density score)
///
/// ## Usage
/// ```swift
/// let result = await DepthAnalysisService.shared.analyze(depthMap: depthBuffer)
/// if result.isLikelyRealScene {
///     // Scene passed depth verification
/// }
/// ```
public struct DepthAnalysisResult: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Standard deviation of valid depth values in meters.
    /// Higher values indicate more depth variation (real 3D scenes).
    /// Threshold: > 0.5 for real scene
    public let depthVariance: Float

    /// Number of distinct depth layers detected via histogram peak detection.
    /// Higher counts indicate complex scenes with multiple objects at different depths.
    /// Threshold: >= 3 for real scene
    public let depthLayers: Int

    /// Edge coherence score (0.0 - 1.0) measuring depth gradient density.
    /// Higher values indicate more depth edges at object boundaries.
    /// Threshold: > 0.3 for real scene
    public let edgeCoherence: Float

    /// Minimum valid depth value in meters (diagnostic metadata).
    /// Computed after filtering NaN/infinity/out-of-range values.
    public let minDepth: Float

    /// Maximum valid depth value in meters (diagnostic metadata).
    /// Computed after filtering NaN/infinity/out-of-range values.
    public let maxDepth: Float

    /// Final determination: does the depth data represent a real 3D scene?
    /// Combines all threshold checks and anti-spoofing measures.
    public let isLikelyRealScene: Bool

    /// Timestamp when analysis was computed.
    public let computedAt: Date

    /// Algorithm version for server compatibility verification.
    /// Bumped when algorithm changes to ensure server can validate.
    public let algorithmVersion: String

    /// Analysis status indicating success or failure mode.
    public let status: DepthAnalysisStatus

    // MARK: - CodingKeys

    /// Maps Swift property names to backend-expected JSON keys (snake_case).
    private enum CodingKeys: String, CodingKey {
        case depthVariance = "depth_variance"
        case depthLayers = "depth_layers"
        case edgeCoherence = "edge_coherence"
        case minDepth = "min_depth"
        case maxDepth = "max_depth"
        case isLikelyRealScene = "is_likely_real_scene"
        case algorithmVersion = "algorithm_version"
        case computedAt = "computed_at"
        case status
    }

    // MARK: - Custom Encoding

    /// Custom encoder that sends snake_case keys to backend.
    /// Note: Backend ignores unknown fields, so including computedAt/status is safe.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(depthVariance, forKey: .depthVariance)
        try container.encode(depthLayers, forKey: .depthLayers)
        try container.encode(edgeCoherence, forKey: .edgeCoherence)
        try container.encode(minDepth, forKey: .minDepth)
        try container.encode(maxDepth, forKey: .maxDepth)
        try container.encode(isLikelyRealScene, forKey: .isLikelyRealScene)
        try container.encode(algorithmVersion, forKey: .algorithmVersion)
        // Note: computedAt and status excluded from encoding - backend doesn't expect them
    }

    /// Custom decoder that handles snake_case keys from storage.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        depthVariance = try container.decode(Float.self, forKey: .depthVariance)
        depthLayers = try container.decode(Int.self, forKey: .depthLayers)
        edgeCoherence = try container.decode(Float.self, forKey: .edgeCoherence)
        minDepth = try container.decode(Float.self, forKey: .minDepth)
        maxDepth = try container.decode(Float.self, forKey: .maxDepth)
        isLikelyRealScene = try container.decode(Bool.self, forKey: .isLikelyRealScene)
        algorithmVersion = try container.decode(String.self, forKey: .algorithmVersion)
        // Provide defaults for fields not in JSON (e.g., when decoding backend response)
        computedAt = (try? container.decode(Date.self, forKey: .computedAt)) ?? Date()
        status = (try? container.decode(DepthAnalysisStatus.self, forKey: .status)) ?? .completed
    }

    // MARK: - Initialization

    /// Creates a new DepthAnalysisResult with all metrics.
    ///
    /// - Parameters:
    ///   - depthVariance: Standard deviation of depth values (meters)
    ///   - depthLayers: Count of detected depth layers
    ///   - edgeCoherence: Edge coherence score (0.0-1.0)
    ///   - minDepth: Minimum valid depth (meters)
    ///   - maxDepth: Maximum valid depth (meters)
    ///   - isLikelyRealScene: Final real scene determination
    ///   - computedAt: Analysis timestamp (defaults to now)
    ///   - algorithmVersion: Algorithm version (defaults to "1.0")
    ///   - status: Analysis status (defaults to .completed)
    public init(
        depthVariance: Float,
        depthLayers: Int,
        edgeCoherence: Float,
        minDepth: Float,
        maxDepth: Float,
        isLikelyRealScene: Bool,
        computedAt: Date = Date(),
        algorithmVersion: String = "1.0",
        status: DepthAnalysisStatus = .completed
    ) {
        self.depthVariance = depthVariance
        self.depthLayers = depthLayers
        self.edgeCoherence = edgeCoherence
        self.minDepth = minDepth
        self.maxDepth = maxDepth
        self.isLikelyRealScene = isLikelyRealScene
        self.computedAt = computedAt
        self.algorithmVersion = algorithmVersion
        self.status = status
    }

    // MARK: - Factory Methods

    /// Creates an unavailable result when analysis cannot be performed.
    ///
    /// Used when:
    /// - Depth map is missing or invalid
    /// - All depth values filtered out
    /// - Buffer access fails
    ///
    /// - Returns: Result with status = .unavailable and all metrics zeroed
    public static func unavailable() -> DepthAnalysisResult {
        DepthAnalysisResult(
            depthVariance: 0,
            depthLayers: 0,
            edgeCoherence: 0,
            minDepth: 0,
            maxDepth: 0,
            isLikelyRealScene: false,
            status: .unavailable
        )
    }
}

// MARK: - DepthAnalysisStatus

/// Status of depth analysis computation.
public enum DepthAnalysisStatus: String, Codable, Sendable {
    /// Analysis completed successfully
    case completed

    /// Analysis could not be performed (missing data, invalid format)
    case unavailable

    /// Analysis failed due to error
    case failed
}

// MARK: - CustomStringConvertible

extension DepthAnalysisResult: CustomStringConvertible {
    public var description: String {
        """
        DepthAnalysisResult(
            variance: \(String(format: "%.3f", depthVariance))m,
            layers: \(depthLayers),
            coherence: \(String(format: "%.3f", edgeCoherence)),
            depthRange: \(String(format: "%.2f", minDepth))-\(String(format: "%.2f", maxDepth))m,
            isRealScene: \(isLikelyRealScene),
            status: \(status.rawValue),
            version: \(algorithmVersion)
        )
        """
    }
}
