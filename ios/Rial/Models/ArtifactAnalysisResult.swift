//
//  ArtifactAnalysisResult.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Result structure for artifact detection (Story 9-3).
//  Detects PWM flicker, specular reflections, and halftone patterns.
//

import Foundation

// MARK: - ArtifactAnalysisResult

/// Result of artifact detection analysis.
///
/// This struct contains metrics from analyzing visual artifacts that indicate
/// the image may be a recapture (photo of a screen or printed photo).
///
/// ## Algorithm Overview
/// 1. PWM Flicker: Analyze luminance profile for refresh rate patterns (60/90/120/144Hz)
/// 2. Specular Reflection: Detect screen glass reflection patterns (rectangular, uniform)
/// 3. Halftone Dots: Detect regular printing dot patterns via FFT
/// 4. Combined confidence from weighted artifact scores
///
/// ## Security Note
/// Per PRD research (USENIX Security 2025), artifact detection can be bypassed
/// by adversarial attacks (Chimera). Weight is limited to 15% in confidence
/// calculation. Always cross-validate with LiDAR (primary) and other signals.
///
/// ## Usage
/// ```swift
/// let result = await ArtifactDetectionService.shared.analyze(image: cgImage)
/// if result.isLikelyArtificial {
///     // Potential screen or print recapture detected
/// }
/// ```
public struct ArtifactAnalysisResult: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Whether PWM/flicker patterns were detected.
    /// True if periodic banding patterns match known refresh rates.
    public let pwmFlickerDetected: Bool

    /// Confidence in PWM flicker detection (0.0-1.0).
    public let pwmConfidence: Float

    /// Whether unnatural specular reflection patterns were detected.
    /// True if rectangular, uniform highlights characteristic of screen glass found.
    public let specularPatternDetected: Bool

    /// Confidence in specular pattern detection (0.0-1.0).
    public let specularConfidence: Float

    /// Whether halftone dot patterns were detected.
    /// True if regular printing dot patterns found via FFT.
    public let halftoneDetected: Bool

    /// Confidence in halftone detection (0.0-1.0).
    public let halftoneConfidence: Float

    /// Combined artifact confidence score (0.0-1.0).
    /// Weighted combination: PWM (0.35) + Specular (0.30) + Halftone (0.35)
    public let overallConfidence: Float

    /// Whether image is likely artificial (screen or print).
    /// True if any artifact detected with high confidence or combined > 0.6.
    public let isLikelyArtificial: Bool

    /// Analysis processing time in milliseconds.
    /// Target: 50ms, Acceptable: <100ms
    public let analysisTimeMs: Int64

    /// Analysis status indicating success or failure mode.
    public let status: ArtifactAnalysisStatus

    /// Algorithm version for tracking/compatibility.
    public let algorithmVersion: String

    /// Timestamp when analysis was performed.
    public let computedAt: Date

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case pwmFlickerDetected = "pwm_flicker_detected"
        case pwmConfidence = "pwm_confidence"
        case specularPatternDetected = "specular_pattern_detected"
        case specularConfidence = "specular_confidence"
        case halftoneDetected = "halftone_detected"
        case halftoneConfidence = "halftone_confidence"
        case overallConfidence = "overall_confidence"
        case isLikelyArtificial = "is_likely_artificial"
        case analysisTimeMs = "analysis_time_ms"
        case status
        case algorithmVersion = "algorithm_version"
        case computedAt = "computed_at"
    }

    // MARK: - Initialization

    /// Creates a new ArtifactAnalysisResult with all metrics.
    ///
    /// - Parameters:
    ///   - pwmFlickerDetected: Whether PWM flicker patterns found
    ///   - pwmConfidence: PWM detection confidence (0.0-1.0)
    ///   - specularPatternDetected: Whether specular patterns found
    ///   - specularConfidence: Specular detection confidence (0.0-1.0)
    ///   - halftoneDetected: Whether halftone patterns found
    ///   - halftoneConfidence: Halftone detection confidence (0.0-1.0)
    ///   - overallConfidence: Combined confidence score (0.0-1.0)
    ///   - isLikelyArtificial: Whether image likely contains artifacts
    ///   - analysisTimeMs: Processing duration in milliseconds
    ///   - status: Analysis status (defaults to .success)
    ///   - algorithmVersion: Algorithm version (defaults to current)
    ///   - computedAt: Analysis timestamp (defaults to now)
    public init(
        pwmFlickerDetected: Bool,
        pwmConfidence: Float,
        specularPatternDetected: Bool,
        specularConfidence: Float,
        halftoneDetected: Bool,
        halftoneConfidence: Float,
        overallConfidence: Float,
        isLikelyArtificial: Bool,
        analysisTimeMs: Int64,
        status: ArtifactAnalysisStatus = .success,
        algorithmVersion: String = ArtifactAnalysisConstants.algorithmVersion,
        computedAt: Date = Date()
    ) {
        self.pwmFlickerDetected = pwmFlickerDetected
        self.pwmConfidence = max(0, min(1, pwmConfidence))
        self.specularPatternDetected = specularPatternDetected
        self.specularConfidence = max(0, min(1, specularConfidence))
        self.halftoneDetected = halftoneDetected
        self.halftoneConfidence = max(0, min(1, halftoneConfidence))
        self.overallConfidence = max(0, min(1, overallConfidence))
        self.isLikelyArtificial = isLikelyArtificial
        self.analysisTimeMs = analysisTimeMs
        self.status = status
        self.algorithmVersion = algorithmVersion
        self.computedAt = computedAt
    }

    // MARK: - Factory Methods

    /// Creates a result indicating no artifacts detected.
    ///
    /// - Parameter analysisTimeMs: Processing duration in milliseconds
    /// - Returns: Result with all detections false and zero confidence
    public static func notDetected(analysisTimeMs: Int64) -> ArtifactAnalysisResult {
        ArtifactAnalysisResult(
            pwmFlickerDetected: false,
            pwmConfidence: 0,
            specularPatternDetected: false,
            specularConfidence: 0,
            halftoneDetected: false,
            halftoneConfidence: 0,
            overallConfidence: 0,
            isLikelyArtificial: false,
            analysisTimeMs: analysisTimeMs
        )
    }

    /// Creates a result when analysis cannot be performed.
    ///
    /// Used when:
    /// - Image format unsupported
    /// - FFT setup fails
    /// - Memory allocation fails
    ///
    /// - Returns: Result with status = .unavailable
    public static func unavailable() -> ArtifactAnalysisResult {
        ArtifactAnalysisResult(
            pwmFlickerDetected: false,
            pwmConfidence: 0,
            specularPatternDetected: false,
            specularConfidence: 0,
            halftoneDetected: false,
            halftoneConfidence: 0,
            overallConfidence: 0,
            isLikelyArtificial: false,
            analysisTimeMs: 0,
            status: .unavailable
        )
    }

    /// Creates a result when analysis fails with error.
    ///
    /// - Parameter analysisTimeMs: Processing duration before failure
    /// - Returns: Result with status = .error
    public static func error(analysisTimeMs: Int64) -> ArtifactAnalysisResult {
        ArtifactAnalysisResult(
            pwmFlickerDetected: false,
            pwmConfidence: 0,
            specularPatternDetected: false,
            specularConfidence: 0,
            halftoneDetected: false,
            halftoneConfidence: 0,
            overallConfidence: 0,
            isLikelyArtificial: false,
            analysisTimeMs: analysisTimeMs,
            status: .error
        )
    }
}

// MARK: - ArtifactAnalysisStatus

/// Status of artifact analysis computation.
public enum ArtifactAnalysisStatus: String, Codable, Sendable {
    /// Analysis completed successfully
    case success

    /// Analysis could not be performed (invalid image, resource unavailable)
    case unavailable

    /// Analysis failed during processing
    case error
}

// MARK: - ArtifactAnalysisConstants

/// Configuration constants for artifact detection.
///
/// These values define thresholds and parameters for
/// PWM, specular, and halftone artifact detection.
public enum ArtifactAnalysisConstants {
    /// Current algorithm version
    public static let algorithmVersion = "1.0"

    // MARK: - Detection Weights

    /// Weight of PWM flicker in combined confidence.
    /// Strong indicator of screen recapture.
    public static let pwmWeight: Float = 0.35

    /// Weight of specular patterns in combined confidence.
    /// Screens have characteristic glass reflections.
    public static let specularWeight: Float = 0.30

    /// Weight of halftone detection in combined confidence.
    /// Strong indicator of printed photo.
    public static let halftoneWeight: Float = 0.35

    // MARK: - Detection Thresholds

    /// Minimum individual confidence to flag as detected.
    public static let minDetectionConfidence: Float = 0.5

    /// Threshold for individual high-confidence detection.
    /// If any artifact exceeds this, isLikelyArtificial = true.
    public static let highConfidenceThreshold: Float = 0.7

    /// Threshold for combined confidence to flag as artificial.
    public static let combinedConfidenceThreshold: Float = 0.6

    // MARK: - PWM Detection Parameters

    /// Known display refresh rates to detect (Hz).
    /// Rolling shutter creates banding at these frequencies.
    public static let refreshRates: [Float] = [60, 90, 120, 144]

    /// Minimum number of consistent bands to flag PWM.
    public static let minPWMBandCount: Int = 3

    /// Minimum band strength ratio to noise floor.
    public static let minPWMBandStrength: Float = 2.0

    /// Frequency tolerance for matching refresh rates (as fraction).
    public static let pwmFrequencyTolerance: Float = 0.15

    // MARK: - Specular Detection Parameters

    /// Minimum highlight luminance threshold (0-1 normalized).
    public static let highlightLuminanceThreshold: Float = 0.85

    /// Maximum saturation for highlight to be considered specular.
    public static let highlightSaturationThreshold: Float = 0.25

    /// Minimum rectangularity score for screen-like highlight.
    public static let minRectangularity: Float = 0.6

    /// Minimum aspect ratio for screen reflection (wider than tall or vice versa).
    public static let minAspectRatio: Float = 1.5

    /// Minimum highlight area as fraction of image.
    public static let minHighlightAreaFraction: Float = 0.005

    /// Maximum highlight area as fraction of image.
    public static let maxHighlightAreaFraction: Float = 0.15

    // MARK: - Halftone Detection Parameters

    /// Tile size for FFT analysis.
    public static let halftoneTileSize: Int = 128

    /// Minimum tiles with halftone pattern to flag.
    public static let minHalftoneTiles: Int = 4

    /// Halftone frequency range (LPI equivalent in FFT bins).
    /// Typical print: 100-200 LPI
    public static let halftoneMinFrequency: Float = 10

    public static let halftoneMaxFrequency: Float = 50

    /// Minimum peak magnitude for halftone detection.
    public static let halftoneMinPeakMagnitude: Float = 0.1

    /// Expected angles for CMYK rosette (degrees).
    public static let rosetteAngles: [Float] = [15, 45, 75, 90]

    /// Angle tolerance for rosette pattern matching (degrees).
    public static let rosetteAngleTolerance: Float = 10

    // MARK: - Image Requirements

    /// Minimum image dimension for analysis.
    public static let minImageDimension: Int = 64

    /// Target image dimension for analysis.
    public static let targetImageDimension: Int = 512

    /// Maximum image dimension before downsampling.
    public static let maxImageDimension: Int = 4096

    // MARK: - Performance

    /// Target analysis time in milliseconds.
    public static let targetTimeMs: Int64 = 50

    /// Maximum acceptable analysis time in milliseconds.
    public static let maxTimeMs: Int64 = 100

    /// Maximum memory usage during analysis (bytes).
    public static let maxMemoryBytes: Int = 75 * 1024 * 1024 // 75MB
}

// MARK: - CustomStringConvertible

extension ArtifactAnalysisResult: CustomStringConvertible {
    public var description: String {
        """
        ArtifactAnalysisResult(
            pwm: \(pwmFlickerDetected) (\(String(format: "%.3f", pwmConfidence))),
            specular: \(specularPatternDetected) (\(String(format: "%.3f", specularConfidence))),
            halftone: \(halftoneDetected) (\(String(format: "%.3f", halftoneConfidence))),
            overall: \(String(format: "%.3f", overallConfidence)),
            isLikelyArtificial: \(isLikelyArtificial),
            analysisTimeMs: \(analysisTimeMs),
            status: \(status.rawValue),
            version: \(algorithmVersion)
        )
        """
    }
}
