//
//  TextureClassificationResult.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Result structure for texture classification via CoreML (Story 9-2).
//  Distinguishes real materials from screen/print surfaces.
//

import Foundation

// MARK: - TextureClassificationResult

/// Result of texture classification via CoreML/heuristic analysis.
///
/// This struct contains all metrics from texture analysis used to
/// detect recaptured images (photos of screens or printed photos).
///
/// ## Algorithm Overview
/// 1. Extract image statistics (color variance, edge patterns)
/// 2. Analyze texture features (homogeneity, contrast, periodicity)
/// 3. Classify into texture types (real_scene, lcd_screen, oled_screen, printed_paper, unknown)
/// 4. Compute classification confidence
///
/// ## Security Note
/// Per PRD research (USENIX Security 2025), texture classification alone can be
/// bypassed by adversarial attacks (Chimera). Weight is limited to 15% in confidence
/// calculation. Always cross-validate with LiDAR (primary) and other signals.
///
/// ## Usage
/// ```swift
/// let result = await TextureClassificationService.shared.classify(image: cgImage)
/// if result.isLikelyRecaptured {
///     // Potential recapture detected
/// }
/// ```
public struct TextureClassificationResult: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Primary texture classification.
    public let classification: TextureType

    /// Confidence in primary classification (0.0 - 1.0).
    /// Higher values indicate stronger classification certainty.
    /// - 0.0-0.3: Low confidence (ambiguous texture)
    /// - 0.3-0.6: Medium confidence (texture hints present)
    /// - 0.6-1.0: High confidence (clear texture signature detected)
    public let confidence: Float

    /// Probabilities for all texture classes.
    /// Sum may not equal 1.0 if using independent classifiers.
    public let allClassifications: [TextureType: Float]

    /// Whether the image is likely a recapture (screen or print).
    /// True if lcd_screen, oled_screen, or printed_paper has confidence > 0.7
    public let isLikelyRecaptured: Bool

    /// Analysis processing time in milliseconds.
    /// Target: 15ms (per PRD), Acceptable: <50ms
    public let analysisTimeMs: Int

    /// Algorithm version for tracking/compatibility.
    public let algorithmVersion: String

    /// Timestamp when analysis was performed.
    public let computedAt: Date

    /// Analysis status indicating success or failure mode.
    public let status: TextureClassificationStatus

    /// Reason for unavailability (only set when status != .success)
    public let unavailabilityReason: String?

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case classification
        case confidence
        case allClassifications = "all_classifications"
        case isLikelyRecaptured = "is_likely_recaptured"
        case analysisTimeMs = "analysis_time_ms"
        case algorithmVersion = "algorithm_version"
        case computedAt = "computed_at"
        case status
        case unavailabilityReason = "unavailability_reason"
    }

    // MARK: - Initialization

    /// Creates a new TextureClassificationResult with all metrics.
    ///
    /// - Parameters:
    ///   - classification: Primary texture classification
    ///   - confidence: Confidence in classification (0.0-1.0)
    ///   - allClassifications: All class probabilities
    ///   - isLikelyRecaptured: Whether recapture is suspected
    ///   - analysisTimeMs: Processing duration in milliseconds
    ///   - algorithmVersion: Algorithm version (defaults to current)
    ///   - computedAt: Analysis timestamp (defaults to now)
    ///   - status: Analysis status (defaults to .success)
    ///   - unavailabilityReason: Reason if unavailable (optional)
    public init(
        classification: TextureType,
        confidence: Float,
        allClassifications: [TextureType: Float],
        isLikelyRecaptured: Bool,
        analysisTimeMs: Int,
        algorithmVersion: String = TextureClassificationConstants.algorithmVersion,
        computedAt: Date = Date(),
        status: TextureClassificationStatus = .success,
        unavailabilityReason: String? = nil
    ) {
        self.classification = classification
        self.confidence = max(0, min(1, confidence)) // Clamp to 0-1
        self.allClassifications = allClassifications
        self.isLikelyRecaptured = isLikelyRecaptured
        self.analysisTimeMs = analysisTimeMs
        self.algorithmVersion = algorithmVersion
        self.computedAt = computedAt
        self.status = status
        self.unavailabilityReason = unavailabilityReason
    }

    // MARK: - Factory Methods

    /// Creates a result indicating analysis completed with no recapture detected.
    ///
    /// - Parameter analysisTimeMs: Processing duration in milliseconds
    /// - Returns: Result with classification=.real_scene
    public static func realScene(
        confidence: Float,
        allClassifications: [TextureType: Float],
        analysisTimeMs: Int
    ) -> TextureClassificationResult {
        TextureClassificationResult(
            classification: .realScene,
            confidence: confidence,
            allClassifications: allClassifications,
            isLikelyRecaptured: false,
            analysisTimeMs: analysisTimeMs
        )
    }

    /// Creates a result when analysis cannot be performed.
    ///
    /// Used when:
    /// - Image format unsupported
    /// - Model load fails
    /// - Memory allocation fails
    ///
    /// - Parameter reason: Description of why analysis is unavailable
    /// - Returns: Result with status = .unavailable
    public static func unavailable(reason: String) -> TextureClassificationResult {
        TextureClassificationResult(
            classification: .unknown,
            confidence: 0,
            allClassifications: [:],
            isLikelyRecaptured: false,
            analysisTimeMs: 0,
            status: .unavailable,
            unavailabilityReason: reason
        )
    }

    /// Creates a result when analysis fails with error.
    ///
    /// - Parameters:
    ///   - reason: Description of the error
    ///   - analysisTimeMs: Processing duration before failure
    /// - Returns: Result with status = .error
    public static func error(reason: String, analysisTimeMs: Int) -> TextureClassificationResult {
        TextureClassificationResult(
            classification: .unknown,
            confidence: 0,
            allClassifications: [:],
            isLikelyRecaptured: false,
            analysisTimeMs: analysisTimeMs,
            status: .error,
            unavailabilityReason: reason
        )
    }
}

// MARK: - TextureType

/// Classification of detected texture type.
///
/// Different surfaces have distinct texture characteristics:
/// - Real scenes: Natural material textures (skin, fabric, wood, grass)
/// - LCD screens: Visible pixel grid, backlight uniformity
/// - OLED screens: Different subpixel arrangement, potential burn-in patterns
/// - Printed paper: Halftone patterns, paper texture, ink absorption
public enum TextureType: String, Codable, Sendable, CaseIterable {
    /// Natural real-world surface (not a recapture).
    /// Exhibits varied texture patterns, depth cues, natural noise.
    case realScene = "real_scene"

    /// LCD display surface.
    /// Characteristics: RGB stripe subpixels, backlight uniformity,
    /// visible pixel grid at macro distances.
    case lcdScreen = "lcd_screen"

    /// OLED display surface.
    /// Characteristics: Pentile/diamond subpixel arrangement,
    /// true blacks, potential screen artifacts.
    case oledScreen = "oled_screen"

    /// Printed paper/photo surface.
    /// Characteristics: Halftone patterns, paper texture,
    /// ink absorption artifacts, limited color gamut.
    case printedPaper = "printed_paper"

    /// Unknown or unclassifiable texture.
    /// Used when confidence is too low or pattern is ambiguous.
    case unknown = "unknown"
}

// MARK: - TextureClassificationStatus

/// Status of texture classification analysis.
public enum TextureClassificationStatus: String, Codable, Sendable {
    /// Analysis completed successfully
    case success

    /// Analysis could not be performed (invalid image, model unavailable)
    case unavailable

    /// Analysis failed during processing
    case error
}

// MARK: - TextureClassificationConstants

/// Configuration constants for texture classification.
///
/// These values define thresholds and parameters for
/// texture analysis and classification.
public enum TextureClassificationConstants {
    /// Current algorithm version
    public static let algorithmVersion = "1.0"

    // MARK: - Image Requirements

    /// Minimum image dimension for analysis.
    /// Images smaller than this are rejected.
    public static let minImageDimension: Int = 64

    /// Target image size for analysis (224x224 for model compatibility).
    public static let targetImageSize: Int = 224

    /// Maximum image dimension before downsampling.
    public static let maxImageDimension: Int = 4096

    // MARK: - Classification Thresholds

    /// Threshold for isLikelyRecaptured determination.
    /// If screen or print confidence exceeds this, flag as recaptured.
    public static let recaptureConfidenceThreshold: Float = 0.7

    /// Minimum confidence to report any classification.
    /// Below this, classification is set to .unknown.
    public static let minClassificationConfidence: Float = 0.3

    // MARK: - Heuristic Parameters

    /// Color variance threshold for screen detection.
    /// Screens tend to have more uniform color distributions.
    public static let screenColorVarianceThreshold: Float = 0.15

    /// Edge sharpness threshold for print detection.
    /// Prints have softer edges due to ink spread.
    public static let printEdgeSharpnessThreshold: Float = 0.4

    /// Periodicity threshold for screen pixel grid detection.
    public static let screenPeriodicityThreshold: Float = 0.3

    /// High frequency content threshold for real scenes.
    /// Real scenes have more natural high-frequency detail.
    public static let realSceneHighFreqThreshold: Float = 0.25

    // MARK: - Performance

    /// Target analysis time in milliseconds.
    public static let targetTimeMs: Int = 15

    /// Maximum acceptable analysis time in milliseconds.
    public static let maxTimeMs: Int = 50

    /// Maximum memory usage during analysis (bytes).
    public static let maxMemoryBytes: Int = 50 * 1024 * 1024 // 50MB

    // MARK: - Weights

    /// Weight of texture classification in overall detection confidence.
    /// Per PRD: texture is a SUPPORTING signal with 15% weight.
    public static let detectionWeight: Float = 0.15
}

// MARK: - CustomStringConvertible

extension TextureClassificationResult: CustomStringConvertible {
    public var description: String {
        """
        TextureClassificationResult(
            classification: \(classification.rawValue),
            confidence: \(String(format: "%.3f", confidence)),
            isLikelyRecaptured: \(isLikelyRecaptured),
            analysisTimeMs: \(analysisTimeMs),
            status: \(status.rawValue),
            version: \(algorithmVersion)
        )
        """
    }
}

// MARK: - Dictionary Coding for TextureType keys

extension TextureClassificationResult {
    /// Custom encoding to handle TextureType dictionary keys
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(classification, forKey: .classification)
        try container.encode(confidence, forKey: .confidence)

        // Convert TextureType keys to String keys for JSON compatibility
        var stringDict: [String: Float] = [:]
        for (key, value) in allClassifications {
            stringDict[key.rawValue] = value
        }
        try container.encode(stringDict, forKey: .allClassifications)

        try container.encode(isLikelyRecaptured, forKey: .isLikelyRecaptured)
        try container.encode(analysisTimeMs, forKey: .analysisTimeMs)
        try container.encode(algorithmVersion, forKey: .algorithmVersion)
        try container.encode(computedAt, forKey: .computedAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(unavailabilityReason, forKey: .unavailabilityReason)
    }

    /// Custom decoding to handle TextureType dictionary keys
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        classification = try container.decode(TextureType.self, forKey: .classification)
        confidence = try container.decode(Float.self, forKey: .confidence)

        // Convert String keys back to TextureType keys
        let stringDict = try container.decode([String: Float].self, forKey: .allClassifications)
        var textureDict: [TextureType: Float] = [:]
        for (key, value) in stringDict {
            if let textureType = TextureType(rawValue: key) {
                textureDict[textureType] = value
            }
        }
        allClassifications = textureDict

        isLikelyRecaptured = try container.decode(Bool.self, forKey: .isLikelyRecaptured)
        analysisTimeMs = try container.decode(Int.self, forKey: .analysisTimeMs)
        algorithmVersion = try container.decode(String.self, forKey: .algorithmVersion)
        computedAt = try container.decode(Date.self, forKey: .computedAt)
        status = try container.decode(TextureClassificationStatus.self, forKey: .status)
        unavailabilityReason = try container.decodeIfPresent(String.self, forKey: .unavailabilityReason)
    }
}
