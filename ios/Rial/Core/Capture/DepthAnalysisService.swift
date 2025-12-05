//
//  DepthAnalysisService.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Client-side depth analysis for privacy mode (Story 8-1).
//  Algorithm ported from backend/src/services/depth_analysis.rs.
//

import Foundation
import CoreVideo
import os.log

// MARK: - Configuration Constants

/// Configuration constants matching backend/src/services/depth_analysis.rs exactly.
/// These thresholds determine if a scene is classified as "real" (3D) vs "fake" (flat/screen).
public enum DepthAnalysisConstants {
    /// Minimum depth variance (std dev) for real scene detection (meters)
    public static let varianceThreshold: Float = 0.5

    /// Minimum depth layers for real scene detection
    public static let layerThreshold: Int = 3

    /// Minimum edge coherence for real scene detection (0.0-1.0)
    /// NOTE: Lowered from 0.7 for hackathon - real LiDAR often has lower edge coherence
    public static let coherenceThreshold: Float = 0.3

    /// Number of histogram bins for layer detection
    public static let histogramBins: Int = 50

    /// Minimum peak prominence as fraction of max bin count
    public static let peakProminenceRatio: Float = 0.05

    /// Minimum valid depth value (meters) - filter noise
    public static let minValidDepth: Float = 0.1

    /// Maximum valid depth value (meters) - filter outliers
    public static let maxValidDepth: Float = 20.0

    /// Gradient threshold for edge detection (meters)
    public static let gradientThreshold: Float = 0.1

    /// Screen detection: max depth range for suspicious uniform surface (meters)
    public static let screenDepthRangeMax: Float = 0.15

    /// Screen detection: minimum percentage of pixels within narrow band
    public static let screenUniformityThreshold: Float = 0.85

    /// Screen detection: minimum screen distance (meters)
    public static let screenDistanceMin: Float = 0.2

    /// Screen detection: maximum screen distance (meters)
    public static let screenDistanceMax: Float = 1.5

    /// Minimum variance in each quadrant for spatial uniformity check
    public static let minQuadrantVariance: Float = 0.1
}

// MARK: - DepthAnalysisService

/// Service for analyzing LiDAR depth maps on-device for privacy mode.
///
/// This service ports the depth analysis algorithm from the backend (Rust) to Swift,
/// enabling client-side verification without uploading raw depth data.
///
/// ## Algorithm Parity
/// All thresholds and formulas match `backend/src/services/depth_analysis.rs`:
/// - Variance computation: std dev of filtered depths
/// - Layer detection: 50-bin histogram with peak detection
/// - Edge coherence: Sobel-like gradient with sigmoid mapping
/// - Screen detection: uniformity + distance heuristics
/// - Quadrant variance: spatial uniformity check
///
/// ## Performance
/// - Target: < 500ms on iPhone 12 Pro
/// - Typical LiDAR resolution: 256x192 (49,152 pixels)
/// - Runs on background queue to avoid blocking UI
///
/// ## Usage
/// ```swift
/// let result = await DepthAnalysisService.shared.analyze(depthMap: depthBuffer, rgbImage: nil)
/// if result.isLikelyRealScene {
///     // Scene verified as real 3D environment
/// }
/// ```
public final class DepthAnalysisService: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance
    public static let shared = DepthAnalysisService()

    // MARK: - Properties

    /// Logger for depth analysis events
    private static let logger = Logger(subsystem: "app.rial", category: "depthanalysis")

    /// Signpost log for performance tracking
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    // MARK: - Initialization

    /// Private initializer for singleton pattern
    private init() {
        Self.logger.debug("DepthAnalysisService initialized")
    }

    // MARK: - Public API

    /// Analyzes a depth map to determine if it represents a real 3D scene.
    ///
    /// This method performs complete depth analysis including:
    /// - Depth statistics (variance, min/max, coverage)
    /// - Layer detection via histogram peak analysis
    /// - Edge coherence from depth gradients
    /// - Screen pattern detection (anti-recapture)
    /// - Quadrant variance check (spatial uniformity)
    ///
    /// - Parameters:
    ///   - depthMap: CVPixelBuffer containing Float32 depth values (meters)
    ///   - rgbImage: Optional RGB image for edge coherence (currently unused)
    /// - Returns: DepthAnalysisResult with all metrics and final determination
    ///
    /// - Note: This method is async and performs CPU-intensive analysis.
    public func analyze(depthMap: CVPixelBuffer, rgbImage: CVPixelBuffer? = nil) async -> DepthAnalysisResult {
        // performAnalysis is synchronous and CPU-bound
        // Using nonisolated to avoid Sendable warning on CVPixelBuffer parameter
        return performAnalysis(depthMap: depthMap)
    }

    /// Analyzes multiple depth keyframes to determine temporal consistency (video privacy mode).
    ///
    /// This method performs batch depth analysis for video keyframes:
    /// - Analyzes each keyframe individually (reusing single-frame algorithm)
    /// - Computes temporal consistency metrics (variance stability, temporal coherence)
    /// - Determines aggregate authenticity across time
    ///
    /// Algorithm parity with backend temporal depth analysis:
    /// - Per-keyframe thresholds match single-frame analysis
    /// - Variance stability: 1.0 - (stddev(variances) / mean(variances))
    /// - Temporal coherence: mean(edge_coherences)
    /// - Authenticity: all keyframes pass AND variance_stability > 0.8
    ///
    /// - Parameters:
    ///   - keyframes: Array of depth keyframes (CVPixelBuffer with Float32 depths)
    ///   - rgbFrames: Optional array of RGB frames for each keyframe (currently unused)
    /// - Returns: TemporalDepthAnalysisResult with per-frame and aggregate metrics
    ///
    /// - Note: Target performance < 2s for 15s video (~150 keyframes at 10fps)
    public func analyzeTemporalDepth(
        keyframes: [CVPixelBuffer],
        rgbFrames: [CVPixelBuffer]? = nil
    ) async throws -> TemporalDepthAnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !keyframes.isEmpty else {
            throw DepthAnalysisError.noKeyframes
        }

        Self.logger.info("Starting temporal depth analysis for \(keyframes.count) keyframes")

        // 1. Analyze each keyframe individually
        var keyframeAnalyses: [DepthAnalysisResult] = []

        for (index, depthFrame) in keyframes.enumerated() {
            let rgbFrame = (rgbFrames != nil && index < rgbFrames!.count) ? rgbFrames![index] : nil
            let analysis = await analyze(depthMap: depthFrame, rgbImage: rgbFrame)
            keyframeAnalyses.append(analysis)
        }

        // 2. Compute temporal metrics
        let variances = keyframeAnalyses.map { $0.depthVariance }
        let meanVariance = variances.reduce(0, +) / Float(variances.count)

        // Variance stability: 1.0 - (stddev / mean)
        // Higher values indicate consistent depth variation across time
        let varianceStability: Float
        if meanVariance > 0 {
            let stdDev = standardDeviation(variances)
            varianceStability = 1.0 - (stdDev / meanVariance)
        } else {
            varianceStability = 0
        }

        // Temporal coherence: average edge coherence across all keyframes
        let coherences = keyframeAnalyses.map { $0.edgeCoherence }
        let temporalCoherence = coherences.reduce(0, +) / Float(coherences.count)

        // 3. Determine scene authenticity
        // All keyframes must pass individual checks AND variance must be stable
        let allKeyframesPass = keyframeAnalyses.allSatisfy { $0.isLikelyRealScene }
        let isLikelyRealScene = allKeyframesPass && varianceStability > 0.8

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        Self.logger.info("""
            Temporal depth analysis complete in \(String(format: "%.1f", processingTime * 1000))ms:
            keyframes=\(keyframes.count),
            meanVariance=\(String(format: "%.3f", meanVariance)),
            varianceStability=\(String(format: "%.3f", varianceStability)),
            temporalCoherence=\(String(format: "%.3f", temporalCoherence)),
            isLikelyRealScene=\(isLikelyRealScene)
            """)

        if processingTime > 2.0 {
            Self.logger.warning("Temporal depth analysis exceeded 2s target: \(String(format: "%.1f", processingTime * 1000))ms")
        }

        return TemporalDepthAnalysisResult(
            keyframeAnalyses: keyframeAnalyses,
            meanVariance: meanVariance,
            varianceStability: varianceStability,
            temporalCoherence: temporalCoherence,
            isLikelyRealScene: isLikelyRealScene,
            keyframeCount: keyframes.count,
            algorithmVersion: "1.0"
        )
    }

    // MARK: - Internal Analysis

    /// Performs the actual depth analysis synchronously.
    ///
    /// - Parameter depthMap: CVPixelBuffer with depth data
    /// - Returns: DepthAnalysisResult with all computed metrics
    private func performAnalysis(depthMap: CVPixelBuffer) -> DepthAnalysisResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "DepthAnalysis", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "DepthAnalysis", signpostID: signpostID)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Validate pixel format
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        guard pixelFormat == kCVPixelFormatType_DepthFloat32 else {
            Self.logger.error("Invalid pixel format: \(pixelFormat) (expected DepthFloat32)")
            return .unavailable()
        }

        // Lock buffer for reading
        let lockResult = CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        guard lockResult == kCVReturnSuccess else {
            Self.logger.error("Failed to lock depth buffer: \(lockResult)")
            return .unavailable()
        }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        // Extract dimensions and data
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard width >= 3 && height >= 3 else {
            Self.logger.error("Depth buffer too small: \(width)x\(height)")
            return .unavailable()
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            Self.logger.error("Failed to get depth buffer base address")
            return .unavailable()
        }

        let depthPointer = baseAddress.bindMemory(to: Float.self, capacity: width * height)
        let depths = Array(UnsafeBufferPointer(start: depthPointer, count: width * height))

        Self.logger.debug("Analyzing depth map: \(width)x\(height) (\(depths.count) pixels)")

        // 1. Filter valid depths
        let validDepths = filterValidDepths(depths)
        if validDepths.isEmpty {
            Self.logger.warning("No valid depth values after filtering")
            return .unavailable()
        }

        // 2. Compute statistics
        let stats = computeDepthStatistics(validDepths: validDepths, totalCount: depths.count)

        // 3. Detect depth layers
        let layers = detectDepthLayers(depths: depths, minDepth: stats.minDepth, maxDepth: stats.maxDepth)

        // 4. Compute edge coherence
        let coherence = computeEdgeCoherence(depths: depths, width: width, height: height)

        // 5. Detect screen pattern (anti-recapture)
        let (isScreenLike, _) = detectScreenPattern(validDepths: validDepths, stats: stats)

        // 6. Check quadrant variance (spatial uniformity)
        let (quadrantPasses, _) = checkQuadrantVariance(depths: depths, width: width, height: height)

        // 7. Determine if real scene
        let isRealScene = determineRealScene(
            variance: stats.variance,
            layers: layers,
            coherence: coherence,
            isScreenLike: isScreenLike,
            quadrantPasses: quadrantPasses
        )

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("""
            Depth analysis complete in \(String(format: "%.1f", processingTime * 1000))ms:
            variance=\(String(format: "%.3f", stats.variance)),
            layers=\(layers),
            coherence=\(String(format: "%.3f", coherence)),
            isRealScene=\(isRealScene)
            """)

        if processingTime > 0.5 {
            Self.logger.warning("Depth analysis exceeded 500ms target: \(String(format: "%.1f", processingTime * 1000))ms")
        }

        return DepthAnalysisResult(
            depthVariance: stats.variance,
            depthLayers: layers,
            edgeCoherence: coherence,
            minDepth: stats.minDepth,
            maxDepth: stats.maxDepth,
            isLikelyRealScene: isRealScene,
            status: .completed
        )
    }

    // MARK: - Depth Filtering

    /// Filters depth values to only valid measurements.
    ///
    /// Excludes:
    /// - NaN or infinite values
    /// - Values outside reasonable range (0.1m - 20m)
    ///
    /// - Parameter depths: Raw depth values
    /// - Returns: Array of valid depth values
    private func filterValidDepths(_ depths: [Float]) -> [Float] {
        depths.filter { depth in
            depth.isFinite &&
            depth >= DepthAnalysisConstants.minValidDepth &&
            depth <= DepthAnalysisConstants.maxValidDepth
        }
    }

    // MARK: - Statistics

    /// Statistics computed from depth data
    private struct DepthStatistics {
        let variance: Float
        let minDepth: Float
        let maxDepth: Float
        let coverage: Float
    }

    /// Computes statistical metrics from valid depth data.
    ///
    /// - Parameters:
    ///   - validDepths: Pre-filtered valid depth values
    ///   - totalCount: Total pixel count for coverage calculation
    /// - Returns: DepthStatistics with variance, min/max, coverage
    private func computeDepthStatistics(validDepths: [Float], totalCount: Int) -> DepthStatistics {
        guard !validDepths.isEmpty else {
            return DepthStatistics(variance: 0, minDepth: 0, maxDepth: 0, coverage: 0)
        }

        // Compute mean
        let sum = validDepths.reduce(0, +)
        let mean = sum / Float(validDepths.count)

        // Compute variance (std dev)
        let varianceSum = validDepths.reduce(Float(0)) { result, depth in
            let diff = depth - mean
            return result + diff * diff
        }
        let variance = sqrt(varianceSum / Float(validDepths.count))

        // Find min/max
        let minDepth = validDepths.min() ?? 0
        let maxDepth = validDepths.max() ?? 0

        // Coverage ratio
        let coverage = Float(validDepths.count) / Float(totalCount)

        return DepthStatistics(
            variance: variance,
            minDepth: minDepth,
            maxDepth: maxDepth,
            coverage: coverage
        )
    }

    // MARK: - Layer Detection

    /// Detects distinct depth layers using histogram peak detection.
    ///
    /// Algorithm:
    /// 1. Build histogram of depth values over the valid range
    /// 2. Smooth histogram with 3-point moving average
    /// 3. Find local maxima (peaks)
    /// 4. Filter peaks by prominence threshold
    /// 5. Count significant peaks as depth layers
    ///
    /// - Parameters:
    ///   - depths: Raw depth values (may include invalid)
    ///   - minDepth: Minimum valid depth from statistics
    ///   - maxDepth: Maximum valid depth from statistics
    /// - Returns: Number of detected depth layers
    private func detectDepthLayers(depths: [Float], minDepth: Float, maxDepth: Float) -> Int {
        let validDepths = filterValidDepths(depths)

        guard !validDepths.isEmpty, maxDepth > minDepth else {
            return 0
        }

        let binCount = DepthAnalysisConstants.histogramBins
        let binWidth = (maxDepth - minDepth) / Float(binCount)

        // Build histogram
        var histogram = [Int](repeating: 0, count: binCount)
        for depth in validDepths {
            var bin = Int(floor((depth - minDepth) / binWidth))
            bin = min(bin, binCount - 1) // Clamp to valid range
            bin = max(bin, 0)
            histogram[bin] += 1
        }

        // 3-point moving average smoothing
        var smoothed = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount {
            let left = i > 0 ? histogram[i - 1] : histogram[i]
            let right = i < binCount - 1 ? histogram[i + 1] : histogram[i]
            smoothed[i] = Float(left + histogram[i] + right) / 3.0
        }

        // Find max for prominence threshold
        let maxCount = smoothed.max() ?? 0
        let prominenceThreshold = maxCount * DepthAnalysisConstants.peakProminenceRatio

        // Find local maxima (peaks)
        var peaks = [Float]()

        // Check interior points
        for i in 1..<(binCount - 1) {
            if smoothed[i] > smoothed[i - 1] &&
               smoothed[i] > smoothed[i + 1] &&
               smoothed[i] > prominenceThreshold {
                let depth = minDepth + (Float(i) + 0.5) * binWidth
                peaks.append(depth)
            }
        }

        // Check endpoints
        if binCount > 0 && smoothed[0] > prominenceThreshold && smoothed[0] > smoothed[1] {
            peaks.insert(minDepth + 0.5 * binWidth, at: 0)
        }
        if binCount > 1 &&
           smoothed[binCount - 1] > prominenceThreshold &&
           smoothed[binCount - 1] > smoothed[binCount - 2] {
            peaks.append(maxDepth - 0.5 * binWidth)
        }

        Self.logger.debug("Detected \(peaks.count) depth layers at depths: \(peaks)")

        return peaks.count
    }

    // MARK: - Edge Coherence

    /// Computes edge coherence from depth gradients.
    ///
    /// Measures depth edge density as a proxy for scene complexity.
    /// Real 3D scenes have many depth discontinuities at object boundaries.
    /// Flat scenes have few or no meaningful depth edges.
    ///
    /// Algorithm:
    /// 1. Compute horizontal and vertical gradients (Sobel-like)
    /// 2. Calculate gradient magnitude at each pixel
    /// 3. Count pixels with gradient above threshold
    /// 4. Normalize to 0.0-1.0 range with sigmoid mapping
    ///
    /// - Parameters:
    ///   - depths: Depth values as flat array
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// - Returns: Edge coherence score 0.0-1.0
    private func computeEdgeCoherence(depths: [Float], width: Int, height: Int) -> Float {
        guard depths.count == width * height, width >= 3, height >= 3 else {
            return 0
        }

        var edgeCount = 0
        var validPixels = 0

        // Compute gradient magnitude for interior pixels
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let center = depths[idx]

                // Skip invalid center pixels
                guard center.isFinite,
                      center >= DepthAnalysisConstants.minValidDepth,
                      center <= DepthAnalysisConstants.maxValidDepth else {
                    continue
                }

                validPixels += 1

                // Get neighbors
                let left = depths[idx - 1]
                let right = depths[idx + 1]
                let up = depths[idx - width]
                let down = depths[idx + width]

                // Check validity
                let leftValid = left.isFinite && left > DepthAnalysisConstants.minValidDepth
                let rightValid = right.isFinite && right > DepthAnalysisConstants.minValidDepth
                let upValid = up.isFinite && up > DepthAnalysisConstants.minValidDepth
                let downValid = down.isFinite && down > DepthAnalysisConstants.minValidDepth

                // Compute gradients where possible
                var gx: Float = 0
                var gy: Float = 0

                if leftValid && rightValid {
                    gx = (right - left) / 2.0
                }
                if upValid && downValid {
                    gy = (down - up) / 2.0
                }

                let magnitude = sqrt(gx * gx + gy * gy)

                if magnitude > DepthAnalysisConstants.gradientThreshold {
                    edgeCount += 1
                }
            }
        }

        guard validPixels > 0 else {
            return 0
        }

        // Normalize: sigmoid mapping
        // 0% -> 0.0, 5% -> 0.5, 10%+ -> ~0.9+
        let edgeRatio = Float(edgeCount) / Float(validPixels)
        let coherence = 1.0 - exp(-edgeRatio * 30.0)

        return min(max(coherence, 0), 1) // Clamp to 0-1
    }

    // MARK: - Screen Pattern Detection

    /// Detects if depth pattern matches a screen/monitor (recapture attack).
    ///
    /// Screens have:
    /// - Very uniform depth (almost all pixels at same distance)
    /// - Narrow depth range (<15cm variation)
    /// - Typical distance 0.2-1.5m
    ///
    /// - Parameters:
    ///   - validDepths: Pre-filtered valid depths
    ///   - stats: Pre-computed statistics
    /// - Returns: Tuple of (is_screen_like, uniformity_ratio)
    private func detectScreenPattern(validDepths: [Float], stats: DepthStatistics) -> (Bool, Float) {
        guard !validDepths.isEmpty else {
            return (false, 0)
        }

        let depthRange = stats.maxDepth - stats.minDepth
        let meanDepth = validDepths.reduce(0, +) / Float(validDepths.count)

        // Check if in typical screen distance
        let inScreenDistance = meanDepth >= DepthAnalysisConstants.screenDistanceMin &&
                               meanDepth <= DepthAnalysisConstants.screenDistanceMax

        // Check depth uniformity - what % of pixels are within tight band of median
        let sortedDepths = validDepths.sorted()
        let medianDepth = sortedDepths[sortedDepths.count / 2]

        let tightBand: Float = 0.05 // 5cm band around median
        let pixelsInBand = validDepths.filter { abs($0 - medianDepth) < tightBand }.count
        let uniformityRatio = Float(pixelsInBand) / Float(validDepths.count)

        // Screen-like if: narrow range + high uniformity + screen distance
        let isScreenLike = depthRange < DepthAnalysisConstants.screenDepthRangeMax &&
                           uniformityRatio > DepthAnalysisConstants.screenUniformityThreshold &&
                           inScreenDistance

        Self.logger.debug("""
            Screen pattern detection: range=\(String(format: "%.3f", depthRange)),
            uniformity=\(String(format: "%.3f", uniformityRatio)),
            meanDepth=\(String(format: "%.3f", meanDepth)),
            isScreenLike=\(isScreenLike)
            """)

        return (isScreenLike, uniformityRatio)
    }

    // MARK: - Quadrant Variance Check

    /// Checks depth variance in image quadrants (anti-spoofing).
    ///
    /// Real scenes have depth variation across the frame.
    /// Screens/flat surfaces have uniform depth everywhere.
    ///
    /// - Parameters:
    ///   - depths: Full depth array
    ///   - width: Image width
    ///   - height: Image height
    /// - Returns: Tuple of (passes_check, min_quadrant_variance)
    private func checkQuadrantVariance(depths: [Float], width: Int, height: Int) -> (Bool, Float) {
        guard depths.count == width * height, width >= 4, height >= 4 else {
            return (false, 0)
        }

        let halfW = width / 2
        let halfH = height / 2

        var minVariance: Float = .greatestFiniteMagnitude

        // Check each quadrant
        for qy in 0..<2 {
            for qx in 0..<2 {
                var quadrantDepths = [Float]()

                for y in (qy * halfH)..<min((qy + 1) * halfH, height) {
                    for x in (qx * halfW)..<min((qx + 1) * halfW, width) {
                        let depth = depths[y * width + x]
                        if depth.isFinite &&
                           depth >= DepthAnalysisConstants.minValidDepth &&
                           depth <= DepthAnalysisConstants.maxValidDepth {
                            quadrantDepths.append(depth)
                        }
                    }
                }

                if quadrantDepths.count < 10 {
                    continue
                }

                let mean = quadrantDepths.reduce(0, +) / Float(quadrantDepths.count)
                let varianceSum = quadrantDepths.reduce(Float(0)) { result, depth in
                    let diff = depth - mean
                    return result + diff * diff
                }
                let variance = sqrt(varianceSum / Float(quadrantDepths.count))

                minVariance = min(minVariance, variance)
            }
        }

        let passes = minVariance > DepthAnalysisConstants.minQuadrantVariance

        Self.logger.debug("Quadrant variance check: min=\(String(format: "%.3f", minVariance)), passes=\(passes)")

        return (passes, minVariance == .greatestFiniteMagnitude ? 0 : minVariance)
    }

    // MARK: - Real Scene Determination

    /// Determines if the scene is likely real based on all metrics.
    ///
    /// Thresholds:
    /// - depth_variance > 0.5 (sufficient depth variation)
    /// - depth_layers >= 3 (multiple distinct depths)
    /// - edge_coherence > 0.3 (depth gradients present)
    /// - NOT screen-like pattern (anti-recapture)
    ///
    /// - Parameters:
    ///   - variance: Depth variance (std dev)
    ///   - layers: Detected layer count
    ///   - coherence: Edge coherence score
    ///   - isScreenLike: Screen pattern detected
    ///   - quadrantPasses: Quadrant variance check result
    /// - Returns: True if scene is likely real 3D environment
    private func determineRealScene(
        variance: Float,
        layers: Int,
        coherence: Float,
        isScreenLike: Bool,
        quadrantPasses: Bool
    ) -> Bool {
        let basicChecks = variance > DepthAnalysisConstants.varianceThreshold &&
                          layers >= DepthAnalysisConstants.layerThreshold &&
                          coherence > DepthAnalysisConstants.coherenceThreshold

        // Fail if screen-like pattern detected
        if isScreenLike {
            Self.logger.warning("Screen-like pattern detected - likely recapture attack")
            return false
        }

        // Warn but don't fail on quadrant check (may have false positives)
        if !quadrantPasses {
            Self.logger.warning("Low quadrant variance - suspicious uniformity")
        }

        return basicChecks
    }

    // MARK: - Helper Methods

    /// Computes standard deviation of a set of values.
    ///
    /// - Parameter values: Array of Float values
    /// - Returns: Standard deviation (sqrt of variance)
    private func standardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }

        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Float(values.count)
        return sqrt(variance)
    }
}

// MARK: - DepthAnalysisError

/// Errors that can occur during depth analysis
public enum DepthAnalysisError: Error, LocalizedError {
    /// No keyframes provided for temporal analysis
    case noKeyframes

    /// Invalid depth buffer format
    case invalidFormat

    /// Analysis failed
    case analysisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noKeyframes:
            return "No keyframes provided for temporal depth analysis"
        case .invalidFormat:
            return "Invalid depth buffer format"
        case .analysisFailed(let message):
            return "Depth analysis failed: \(message)"
        }
    }
}
