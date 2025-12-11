//
//  MoireAnalysisResult.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Result structure for moire pattern detection (Story 9-1).
//  Detects screen pixel grids via 2D FFT frequency analysis.
//

import Foundation

// MARK: - MoireAnalysisResult

/// Result of moire pattern detection via 2D FFT analysis.
///
/// This struct contains all metrics from frequency domain analysis
/// used to detect screen recapture attacks.
///
/// ## Algorithm Overview
/// 1. Convert image to grayscale
/// 2. Perform 2D FFT using Accelerate framework
/// 3. Detect periodic frequency peaks in moire range
/// 4. Classify screen type based on pattern characteristics
/// 5. Compute detection confidence
///
/// ## Security Note
/// Per PRD research (USENIX Security 2025), moire detection can be bypassed
/// by adversarial attacks (Chimera). Weight is limited to 15% in confidence
/// calculation. Always cross-validate with LiDAR (primary) and other signals.
///
/// ## Usage
/// ```swift
/// let result = await MoireDetectionService.shared.analyze(image: cgImage)
/// if result.detected {
///     // Potential screen recapture detected
/// }
/// ```
public struct MoireAnalysisResult: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Whether moire pattern was detected in the image.
    /// True if characteristic frequency peaks found in moire range.
    public let detected: Bool

    /// Detection confidence score (0.0 - 1.0).
    /// Higher values indicate stronger moire pattern detection.
    /// - 0.0-0.3: Low confidence (ambiguous or weak pattern)
    /// - 0.3-0.6: Medium confidence (pattern present but not definitive)
    /// - 0.6-1.0: High confidence (clear screen pattern detected)
    public let confidence: Float

    /// Detected frequency peaks from FFT analysis.
    /// Each peak represents a periodic pattern at specific frequency.
    public let peaks: [FrequencyPeak]

    /// Classified screen type based on peak pattern.
    /// Nil if no screen detected or pattern unrecognizable.
    public let screenType: ScreenType?

    /// Analysis processing time in milliseconds.
    /// Target: 30ms, Acceptable: <100ms
    public let analysisTimeMs: Int

    /// Algorithm version for tracking/compatibility.
    public let algorithmVersion: String

    /// Timestamp when analysis was performed.
    public let computedAt: Date

    /// Analysis status indicating success or failure mode.
    public let status: MoireAnalysisStatus

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case detected
        case confidence
        case peaks
        case screenType = "screen_type"
        case analysisTimeMs = "analysis_time_ms"
        case algorithmVersion = "algorithm_version"
        case computedAt = "computed_at"
        case status
    }

    // MARK: - Initialization

    /// Creates a new MoireAnalysisResult with all metrics.
    ///
    /// - Parameters:
    ///   - detected: Whether moire pattern was detected
    ///   - confidence: Detection confidence (0.0-1.0)
    ///   - peaks: Array of detected frequency peaks
    ///   - screenType: Classified screen type (optional)
    ///   - analysisTimeMs: Processing duration in milliseconds
    ///   - algorithmVersion: Algorithm version (defaults to "1.0")
    ///   - computedAt: Analysis timestamp (defaults to now)
    ///   - status: Analysis status (defaults to .completed)
    public init(
        detected: Bool,
        confidence: Float,
        peaks: [FrequencyPeak],
        screenType: ScreenType?,
        analysisTimeMs: Int,
        algorithmVersion: String = MoireAnalysisConstants.algorithmVersion,
        computedAt: Date = Date(),
        status: MoireAnalysisStatus = .completed
    ) {
        self.detected = detected
        self.confidence = max(0, min(1, confidence)) // Clamp to 0-1
        self.peaks = peaks
        self.screenType = screenType
        self.analysisTimeMs = analysisTimeMs
        self.algorithmVersion = algorithmVersion
        self.computedAt = computedAt
        self.status = status
    }

    // MARK: - Factory Methods

    /// Creates a result indicating no moire pattern detected.
    ///
    /// - Parameter analysisTimeMs: Processing duration in milliseconds
    /// - Returns: Result with detected=false and no peaks
    public static func notDetected(analysisTimeMs: Int) -> MoireAnalysisResult {
        MoireAnalysisResult(
            detected: false,
            confidence: 0,
            peaks: [],
            screenType: nil,
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
    public static func unavailable() -> MoireAnalysisResult {
        MoireAnalysisResult(
            detected: false,
            confidence: 0,
            peaks: [],
            screenType: nil,
            analysisTimeMs: 0,
            status: .unavailable
        )
    }

    /// Creates a result when analysis fails with error.
    ///
    /// - Parameter analysisTimeMs: Processing duration before failure
    /// - Returns: Result with status = .failed
    public static func failed(analysisTimeMs: Int) -> MoireAnalysisResult {
        MoireAnalysisResult(
            detected: false,
            confidence: 0,
            peaks: [],
            screenType: nil,
            analysisTimeMs: analysisTimeMs,
            status: .failed
        )
    }
}

// MARK: - FrequencyPeak

/// A detected frequency peak in the FFT magnitude spectrum.
///
/// Represents a periodic pattern at a specific spatial frequency.
/// Screen pixel grids produce characteristic peaks at specific frequencies.
public struct FrequencyPeak: Codable, Sendable, Equatable {

    /// Spatial frequency in cycles per image width.
    /// Typical screen moire range: 50-300 cycles/width.
    public let frequency: Float

    /// Peak magnitude (normalized 0.0-1.0).
    /// Higher values indicate stronger periodic signal.
    public let magnitude: Float

    /// Direction angle in radians (0 = horizontal, pi/2 = vertical).
    /// Screen grids produce peaks at 0, pi/2 (horizontal + vertical lines).
    public let angle: Float

    /// Peak prominence relative to surrounding frequencies.
    /// Higher values indicate sharper, more distinct peaks (characteristic of screens).
    public let prominence: Float

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case frequency
        case magnitude
        case angle
        case prominence
    }

    // MARK: - Initialization

    /// Creates a new FrequencyPeak.
    ///
    /// - Parameters:
    ///   - frequency: Spatial frequency in cycles per image width
    ///   - magnitude: Peak magnitude (0.0-1.0)
    ///   - angle: Direction angle in radians
    ///   - prominence: Peak prominence relative to neighbors
    public init(frequency: Float, magnitude: Float, angle: Float, prominence: Float) {
        self.frequency = frequency
        self.magnitude = max(0, min(1, magnitude))
        self.angle = angle
        self.prominence = max(0, prominence)
    }
}

// MARK: - ScreenType

/// Classification of detected screen type based on moire pattern.
///
/// Different display technologies produce distinct pixel arrangements
/// that create characteristic moire patterns when photographed.
public enum ScreenType: String, Codable, Sendable {
    /// LCD display with RGB stripe subpixel arrangement.
    /// Creates regular vertical stripes at ~100-150 ppi equivalent.
    case lcd

    /// OLED display with pentile/diamond subpixel arrangement.
    /// Creates diamond-shaped pattern with different frequency ratios.
    case oled

    /// High refresh rate display (90Hz, 120Hz+).
    /// May produce additional temporal artifacts/sidebands.
    case highRefresh

    /// Screen detected but type not classifiable.
    /// Pattern present but doesn't match known display types.
    case unknown
}

// MARK: - MoireAnalysisStatus

/// Status of moire analysis computation.
public enum MoireAnalysisStatus: String, Codable, Sendable {
    /// Analysis completed successfully
    case completed

    /// Analysis could not be performed (invalid image, FFT setup failed)
    case unavailable

    /// Analysis failed during processing
    case failed
}

// MARK: - MoireAnalysisConstants

/// Configuration constants for moire pattern detection.
///
/// These values define the frequency ranges and thresholds
/// for detecting screen pixel grids via FFT analysis.
public enum MoireAnalysisConstants {
    /// Current algorithm version
    public static let algorithmVersion = "1.0"

    // MARK: - Frequency Range

    /// Minimum frequency for moire detection (cycles per image width).
    /// Below this, patterns are too coarse to be screen pixels.
    public static let minFrequency: Float = 50.0

    /// Maximum frequency for moire detection (cycles per image width).
    /// Above this, patterns are likely sensor noise or aliasing.
    public static let maxFrequency: Float = 300.0

    // MARK: - Detection Thresholds

    /// Minimum peak magnitude to consider (normalized).
    /// Filters out noise floor.
    public static let minPeakMagnitude: Float = 0.05

    /// Minimum peak prominence to consider.
    /// Sharp peaks (screens) have high prominence, broad peaks (fabric) low.
    public static let minPeakProminence: Float = 3.0

    /// Noise floor multiplier for peak detection.
    /// Peak must be this many times above median magnitude.
    public static let noiseFloorMultiplier: Float = 3.0

    /// Minimum number of peaks for screen detection.
    /// Screens produce at least horizontal + vertical peak pairs.
    public static let minPeaksForDetection: Int = 2

    /// Maximum number of peaks to report.
    /// Limits output size, keeps most significant peaks.
    public static let maxPeaksToReport: Int = 10

    // MARK: - Confidence Thresholds

    /// Minimum confidence to report detection.
    /// Below this, pattern is too ambiguous to classify as screen.
    public static let minDetectionConfidence: Float = 0.3

    /// Confidence boost for matching screen pattern.
    public static let screenPatternBoost: Float = 0.2

    /// Confidence penalty for ambiguous patterns.
    public static let ambiguousPenalty: Float = 0.3

    // MARK: - FFT Configuration

    /// Target FFT size (power of 2 for efficiency).
    /// 1024x1024 sufficient for moire detection, saves memory.
    public static let targetFFTSize: Int = 1024

    /// Minimum image dimension for analysis.
    /// Images smaller than this are rejected.
    public static let minImageDimension: Int = 64

    /// Maximum image dimension before downsampling.
    /// Larger images are downsampled to targetFFTSize.
    public static let maxImageDimension: Int = 4096

    // MARK: - Screen Pattern Characteristics

    /// Expected frequency ratio for LCD RGB stripe (red:green:blue spacing).
    /// LCD subpixels create peaks at 1:1:1 ratio.
    public static let lcdFrequencyRatio: Float = 1.0

    /// Expected frequency ratio for OLED pentile.
    /// Pentile creates diamond pattern with sqrt(2) ratio.
    public static let oledFrequencyRatio: Float = 1.414

    /// Tolerance for frequency ratio matching.
    public static let frequencyRatioTolerance: Float = 0.15

    /// Expected angle for horizontal peaks (radians).
    public static let horizontalAngle: Float = 0

    /// Expected angle for vertical peaks (radians).
    public static let verticalAngle: Float = Float.pi / 2

    /// Angle tolerance for peak direction matching (radians).
    public static let angleTolerance: Float = 0.2

    // MARK: - Performance

    /// Target analysis time in milliseconds.
    public static let targetTimeMs: Int = 30

    /// Maximum acceptable analysis time in milliseconds.
    public static let maxTimeMs: Int = 100

    /// Maximum memory usage during analysis (bytes).
    public static let maxMemoryBytes: Int = 100 * 1024 * 1024 // 100MB
}

// MARK: - CustomStringConvertible

extension MoireAnalysisResult: CustomStringConvertible {
    public var description: String {
        """
        MoireAnalysisResult(
            detected: \(detected),
            confidence: \(String(format: "%.3f", confidence)),
            peaks: \(peaks.count),
            screenType: \(screenType?.rawValue ?? "nil"),
            analysisTimeMs: \(analysisTimeMs),
            status: \(status.rawValue),
            version: \(algorithmVersion)
        )
        """
    }
}

extension FrequencyPeak: CustomStringConvertible {
    public var description: String {
        String(format: "Peak(f=%.1f, mag=%.3f, angle=%.2frad, prom=%.2f)",
               frequency, magnitude, angle, prominence)
    }
}
