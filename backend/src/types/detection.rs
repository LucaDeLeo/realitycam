//! Multi-signal detection types (Story 9-7)
//!
//! Defines types for receiving and storing iOS multi-signal detection data.
//! These types match the iOS DetectionResults payload structure exactly.
//!
//! ## Detection Signals
//! - Moire pattern detection (screen capture indicator)
//! - Texture classification (natural vs artificial)
//! - Artifact analysis (PWM flicker, specular patterns, halftone)
//! - Aggregated confidence with cross-validation
//!
//! ## JSON Format
//! Uses snake_case serde rename to match iOS JSON encoding.
//! DateTime fields use ISO 8601 format via chrono's default serde implementation.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ============================================================================
// Main Container
// ============================================================================

/// Complete detection results from iOS multi-signal analysis
///
/// Sent from iOS client as optional "detection" multipart field.
/// Contains results from all detection methods and aggregated confidence.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DetectionResults {
    /// Moire pattern detection results (screen capture indicator)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub moire: Option<MoireAnalysisResult>,

    /// Texture classification results (natural vs artificial surface)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub texture: Option<TextureClassificationResult>,

    /// Artifact analysis results (PWM, specular, halftone)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifacts: Option<ArtifactAnalysisResult>,

    /// Aggregated confidence from all detection methods
    #[serde(skip_serializing_if = "Option::is_none")]
    pub aggregated_confidence: Option<AggregatedConfidenceResult>,

    /// Cross-validation between detection methods
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cross_validation: Option<CrossValidationResult>,

    /// When the detection was computed (ISO 8601)
    pub computed_at: DateTime<Utc>,

    /// Total processing time for all detection methods (milliseconds)
    pub total_processing_time_ms: i64,
}

// ============================================================================
// Moire Analysis (matches iOS MoireAnalysisResult.swift)
// ============================================================================

/// Moire pattern analysis results
///
/// Detects screen capture artifacts by analyzing frequency peaks in the image.
/// High confidence moire detection indicates the photo may be of a screen.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct MoireAnalysisResult {
    /// Whether moire patterns were detected
    pub detected: bool,

    /// Confidence score (0.0 to 1.0)
    pub confidence: f32,

    /// Detected frequency peaks in the image
    #[serde(default)]
    pub peaks: Vec<FrequencyPeak>,

    /// Detected screen type (if moire detected)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub screen_type: Option<ScreenType>,

    /// Analysis time in milliseconds
    pub analysis_time_ms: i32,

    /// Algorithm version for compatibility
    pub algorithm_version: String,

    /// When analysis was computed (ISO 8601)
    pub computed_at: DateTime<Utc>,

    /// Analysis status
    pub status: MoireAnalysisStatus,
}

/// Detected frequency peak in moire analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct FrequencyPeak {
    /// Frequency value (cycles per pixel)
    pub frequency: f32,

    /// Peak magnitude
    pub magnitude: f32,

    /// Peak angle in radians
    pub angle: f32,

    /// Peak prominence relative to surrounding frequencies
    pub prominence: f32,
}

/// Detected screen type from moire analysis
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScreenType {
    Lcd,
    Oled,
    HighRefresh,
    Unknown,
}

/// Status of moire analysis
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MoireAnalysisStatus {
    Completed,
    Unavailable,
    Failed,
}

// ============================================================================
// Texture Classification (matches iOS TextureClassificationResult.swift)
// ============================================================================

/// Texture classification results
///
/// Classifies the surface texture to detect artificial sources
/// (screens, printed paper) vs natural real-world scenes.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TextureClassificationResult {
    /// Primary texture classification
    pub classification: TextureType,

    /// Confidence in the primary classification (0.0 to 1.0)
    pub confidence: f32,

    /// Confidence scores for all classification categories
    #[serde(default)]
    pub all_classifications: HashMap<String, f32>,

    /// Whether texture indicates recaptured content
    pub is_likely_recaptured: bool,

    /// Analysis time in milliseconds
    pub analysis_time_ms: i32,

    /// Algorithm version for compatibility
    pub algorithm_version: String,

    /// When analysis was computed (ISO 8601)
    pub computed_at: DateTime<Utc>,

    /// Analysis status
    pub status: TextureClassificationStatus,

    /// Reason for unavailability (if status is unavailable)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unavailability_reason: Option<String>,
}

/// Texture type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextureType {
    RealScene,
    LcdScreen,
    OledScreen,
    PrintedPaper,
    Unknown,
}

/// Status of texture classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextureClassificationStatus {
    Success,
    Unavailable,
    Error,
}

// ============================================================================
// Artifact Analysis (matches iOS ArtifactAnalysisResult.swift)
// ============================================================================

/// Artifact analysis results
///
/// Detects artificial artifacts that indicate non-natural capture:
/// - PWM flicker from screens
/// - Specular patterns from glossy surfaces
/// - Halftone patterns from printed materials
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ArtifactAnalysisResult {
    /// Whether PWM flicker was detected (screen indicator)
    pub pwm_flicker_detected: bool,

    /// Confidence in PWM detection (0.0 to 1.0)
    pub pwm_confidence: f32,

    /// Whether specular reflection patterns were detected
    pub specular_pattern_detected: bool,

    /// Confidence in specular detection (0.0 to 1.0)
    pub specular_confidence: f32,

    /// Whether halftone patterns were detected (print indicator)
    pub halftone_detected: bool,

    /// Confidence in halftone detection (0.0 to 1.0)
    pub halftone_confidence: f32,

    /// Overall artifact confidence (0.0 to 1.0)
    pub overall_confidence: f32,

    /// Whether artifacts indicate artificial source
    pub is_likely_artificial: bool,

    /// Analysis time in milliseconds
    pub analysis_time_ms: i64,

    /// Analysis status
    pub status: ArtifactAnalysisStatus,

    /// Algorithm version for compatibility
    pub algorithm_version: String,

    /// When analysis was computed (ISO 8601)
    pub computed_at: DateTime<Utc>,
}

/// Status of artifact analysis
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactAnalysisStatus {
    Success,
    Unavailable,
    Error,
}

// ============================================================================
// Aggregated Confidence (matches iOS AggregatedConfidenceResult.swift)
// ============================================================================

/// Aggregated confidence from all detection methods
///
/// Combines results from all detection signals with weighted contributions
/// to produce an overall authenticity confidence score.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct AggregatedConfidenceResult {
    /// Overall confidence score (0.0 to 1.0)
    pub overall_confidence: f32,

    /// Confidence level classification
    pub confidence_level: AggregatedConfidenceLevel,

    /// Per-method breakdown of contributions
    #[serde(default)]
    pub method_breakdown: HashMap<String, MethodResult>,

    /// Whether primary signal (LiDAR) passed validation
    pub primary_signal_valid: bool,

    /// Whether supporting signals agree with primary
    pub supporting_signals_agree: bool,

    /// Flags indicating confidence concerns
    #[serde(default)]
    pub flags: Vec<ConfidenceFlag>,

    /// Analysis time in milliseconds
    pub analysis_time_ms: i64,

    /// When analysis was computed (ISO 8601)
    pub computed_at: DateTime<Utc>,

    /// Algorithm version for compatibility
    pub algorithm_version: String,

    /// Aggregation status
    pub status: AggregationStatus,

    /// Cross-validation result (may be nested or top-level)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cross_validation: Option<CrossValidationResult>,

    /// Confidence interval bounds
    #[serde(skip_serializing_if = "Option::is_none")]
    pub confidence_interval: Option<ConfidenceInterval>,
}

/// Per-method result breakdown
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct MethodResult {
    /// Whether this method was available/executed
    pub available: bool,

    /// Method score (0.0 to 1.0, None if unavailable)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub score: Option<f32>,

    /// Weight applied to this method in aggregation
    pub weight: f32,

    /// Contribution to overall confidence
    pub contribution: f32,

    /// Status description (e.g., "pass", "fail", "not_detected")
    pub status: String,
}

/// Aggregated confidence level classification
///
/// iOS has 5 levels; backend maps very_high -> high for storage.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AggregatedConfidenceLevel {
    VeryHigh,
    High,
    Medium,
    Low,
    Suspicious,
}

impl AggregatedConfidenceLevel {
    /// Map to backend ConfidenceLevel (4 levels) for storage/display
    pub fn to_backend_level(&self) -> &'static str {
        match self {
            Self::VeryHigh | Self::High => "high",
            Self::Medium => "medium",
            Self::Low => "low",
            Self::Suspicious => "suspicious",
        }
    }
}

/// Confidence flags indicating concerns or issues
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConfidenceFlag {
    PrimarySignalFailed,
    ScreenDetected,
    PrintDetected,
    MethodsDisagree,
    PrimarySupportingDisagree,
    PartialAnalysis,
    LowConfidencePrimary,
    AmbiguousResults,
    ConsistencyAnomaly,
    TemporalInconsistency,
    HighUncertainty,
}

/// Aggregation status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AggregationStatus {
    Success,
    Partial,
    Unavailable,
    Error,
}

/// Confidence interval bounds
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ConfidenceInterval {
    /// Lower bound (0.0 to 1.0)
    pub lower_bound: f32,

    /// Point estimate (0.0 to 1.0)
    pub point_estimate: f32,

    /// Upper bound (0.0 to 1.0)
    pub upper_bound: f32,
}

// ============================================================================
// Cross-Validation (matches iOS CrossValidationResult.swift)
// ============================================================================

/// Cross-validation results between detection methods
///
/// Validates consistency between different detection signals
/// and identifies anomalies that may indicate tampering.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct CrossValidationResult {
    /// Overall validation status
    pub validation_status: ValidationStatus,

    /// Pairwise consistency checks between methods
    #[serde(default)]
    pub pairwise_consistencies: Vec<PairwiseConsistency>,

    /// Temporal consistency analysis (for video)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temporal_consistency: Option<TemporalConsistency>,

    /// Per-method confidence intervals
    #[serde(default)]
    pub confidence_intervals: HashMap<String, ConfidenceInterval>,

    /// Aggregated confidence interval
    pub aggregated_interval: ConfidenceInterval,

    /// Detected anomalies
    #[serde(default)]
    pub anomalies: Vec<AnomalyReport>,

    /// Overall penalty applied to confidence
    pub overall_penalty: f32,

    /// Analysis time in milliseconds
    pub analysis_time_ms: i64,

    /// Algorithm version for compatibility
    pub algorithm_version: String,

    /// When analysis was computed (ISO 8601)
    pub computed_at: DateTime<Utc>,
}

/// Validation status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ValidationStatus {
    Pass,
    Warn,
    Fail,
}

/// Pairwise consistency check between two methods
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct PairwiseConsistency {
    /// First method in comparison
    pub method_a: String,

    /// Second method in comparison
    pub method_b: String,

    /// Expected relationship between methods
    pub expected_relationship: ExpectedRelationship,

    /// Actual agreement score (0.0 to 1.0)
    pub actual_agreement: f32,

    /// Anomaly score (0.0 = normal, higher = more anomalous)
    pub anomaly_score: f32,

    /// Whether this pair is flagged as anomalous
    pub is_anomaly: bool,
}

/// Expected relationship between detection methods
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExpectedRelationship {
    Positive,
    Negative,
    Neutral,
}

/// Temporal consistency analysis for video captures
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TemporalConsistency {
    /// Number of frames analyzed
    pub frame_count: i32,

    /// Per-method stability scores (0.0 to 1.0)
    #[serde(default)]
    pub stability_scores: HashMap<String, f32>,

    /// Detected temporal anomalies
    #[serde(default)]
    pub anomalies: Vec<TemporalAnomaly>,

    /// Overall temporal stability (0.0 to 1.0)
    pub overall_stability: f32,
}

/// Temporal anomaly detected in video analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TemporalAnomaly {
    /// Frame index where anomaly occurred
    pub frame_index: i32,

    /// Detection method that flagged the anomaly
    pub method: String,

    /// Score change that triggered the anomaly
    pub delta_score: f32,

    /// Type of temporal anomaly
    pub anomaly_type: TemporalAnomalyType,
}

/// Type of temporal anomaly
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TemporalAnomalyType {
    SuddenJump,
    Oscillation,
    Drift,
}

/// Anomaly report from cross-validation
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct AnomalyReport {
    /// Type of anomaly detected
    pub anomaly_type: AnomalyType,

    /// Severity of the anomaly
    pub severity: AnomalySeverity,

    /// Methods affected by this anomaly
    #[serde(default)]
    pub affected_methods: Vec<String>,

    /// Human-readable description
    pub details: String,

    /// Impact on confidence score (penalty applied)
    pub confidence_impact: f32,
}

/// Type of cross-validation anomaly
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnomalyType {
    ContradictorySignals,
    TooHighAgreement,
    IsolatedDisagreement,
    BoundaryCluster,
    CorrelationAnomaly,
}

/// Severity of anomaly
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnomalySeverity {
    Low,
    Medium,
    High,
}

// ============================================================================
// Validation
// ============================================================================

impl DetectionResults {
    /// Validates the detection results payload.
    ///
    /// Checks:
    /// - Confidence values are in 0.0-1.0 range
    /// - Processing times are non-negative
    /// - Required fields are present in nested structures
    ///
    /// Returns validation warnings but does NOT reject - detection is optional.
    pub fn validate(&self) -> Vec<String> {
        let mut warnings = Vec::new();

        // Validate processing time
        if self.total_processing_time_ms < 0 {
            warnings.push("total_processing_time_ms must be non-negative".to_string());
        }

        // Validate moire results
        if let Some(ref moire) = self.moire {
            if !is_valid_confidence(moire.confidence) {
                warnings.push(format!(
                    "moire.confidence out of range: {}",
                    moire.confidence
                ));
            }
            if moire.analysis_time_ms < 0 {
                warnings.push("moire.analysis_time_ms must be non-negative".to_string());
            }
        }

        // Validate texture results
        if let Some(ref texture) = self.texture {
            if !is_valid_confidence(texture.confidence) {
                warnings.push(format!(
                    "texture.confidence out of range: {}",
                    texture.confidence
                ));
            }
            if texture.analysis_time_ms < 0 {
                warnings.push("texture.analysis_time_ms must be non-negative".to_string());
            }
        }

        // Validate artifact results
        if let Some(ref artifacts) = self.artifacts {
            if !is_valid_confidence(artifacts.overall_confidence) {
                warnings.push(format!(
                    "artifacts.overall_confidence out of range: {}",
                    artifacts.overall_confidence
                ));
            }
            if !is_valid_confidence(artifacts.pwm_confidence) {
                warnings.push(format!(
                    "artifacts.pwm_confidence out of range: {}",
                    artifacts.pwm_confidence
                ));
            }
            if !is_valid_confidence(artifacts.specular_confidence) {
                warnings.push(format!(
                    "artifacts.specular_confidence out of range: {}",
                    artifacts.specular_confidence
                ));
            }
            if !is_valid_confidence(artifacts.halftone_confidence) {
                warnings.push(format!(
                    "artifacts.halftone_confidence out of range: {}",
                    artifacts.halftone_confidence
                ));
            }
            if artifacts.analysis_time_ms < 0 {
                warnings.push("artifacts.analysis_time_ms must be non-negative".to_string());
            }
        }

        // Validate aggregated confidence
        if let Some(ref agg) = self.aggregated_confidence {
            if !is_valid_confidence(agg.overall_confidence) {
                warnings.push(format!(
                    "aggregated_confidence.overall_confidence out of range: {}",
                    agg.overall_confidence
                ));
            }
            if agg.analysis_time_ms < 0 {
                warnings.push(
                    "aggregated_confidence.analysis_time_ms must be non-negative".to_string(),
                );
            }
        }

        // Validate cross-validation
        if let Some(ref cv) = self.cross_validation {
            if cv.overall_penalty < 0.0 {
                warnings.push(format!(
                    "cross_validation.overall_penalty must be non-negative: {}",
                    cv.overall_penalty
                ));
            }
            if cv.analysis_time_ms < 0 {
                warnings.push("cross_validation.analysis_time_ms must be non-negative".to_string());
            }
        }

        warnings
    }

    /// Returns a summary of detection results for API response
    pub fn summary(&self) -> DetectionSummary {
        let method_count = [
            self.moire.is_some(),
            self.texture.is_some(),
            self.artifacts.is_some(),
        ]
        .iter()
        .filter(|&&x| x)
        .count() as u8;

        let (confidence_level, primary_valid, signals_agree) =
            if let Some(ref agg) = self.aggregated_confidence {
                (
                    Some(agg.confidence_level.to_backend_level().to_string()),
                    agg.primary_signal_valid,
                    agg.supporting_signals_agree,
                )
            } else {
                (None, false, false)
            };

        DetectionSummary {
            detection_available: true,
            detection_confidence_level: confidence_level,
            detection_primary_valid: primary_valid,
            detection_signals_agree: signals_agree,
            detection_method_count: method_count,
        }
    }
}

/// Summary of detection results for API response
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DetectionSummary {
    /// Whether detection data is available
    pub detection_available: bool,

    /// Confidence level: "high", "medium", "low", or "suspicious"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detection_confidence_level: Option<String>,

    /// Whether primary signal (LiDAR) passed validation
    pub detection_primary_valid: bool,

    /// Whether supporting signals agree
    pub detection_signals_agree: bool,

    /// Number of detection methods used
    pub detection_method_count: u8,
}

/// Check if a confidence value is in valid range
fn is_valid_confidence(value: f32) -> bool {
    (0.0..=1.0).contains(&value)
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_detection_results() -> DetectionResults {
        DetectionResults {
            moire: Some(MoireAnalysisResult {
                detected: false,
                confidence: 0.0,
                peaks: vec![],
                screen_type: None,
                analysis_time_ms: 45,
                algorithm_version: "1.0".to_string(),
                computed_at: Utc::now(),
                status: MoireAnalysisStatus::Completed,
            }),
            texture: Some(TextureClassificationResult {
                classification: TextureType::RealScene,
                confidence: 0.92,
                all_classifications: HashMap::from([
                    ("real_scene".to_string(), 0.92),
                    ("lcd_screen".to_string(), 0.05),
                ]),
                is_likely_recaptured: false,
                analysis_time_ms: 23,
                algorithm_version: "1.0".to_string(),
                computed_at: Utc::now(),
                status: TextureClassificationStatus::Success,
                unavailability_reason: None,
            }),
            artifacts: Some(ArtifactAnalysisResult {
                pwm_flicker_detected: false,
                pwm_confidence: 0.0,
                specular_pattern_detected: false,
                specular_confidence: 0.0,
                halftone_detected: false,
                halftone_confidence: 0.0,
                overall_confidence: 0.0,
                is_likely_artificial: false,
                analysis_time_ms: 15,
                status: ArtifactAnalysisStatus::Success,
                algorithm_version: "1.0".to_string(),
                computed_at: Utc::now(),
            }),
            aggregated_confidence: Some(AggregatedConfidenceResult {
                overall_confidence: 0.95,
                confidence_level: AggregatedConfidenceLevel::High,
                method_breakdown: HashMap::from([
                    (
                        "lidar_depth".to_string(),
                        MethodResult {
                            available: true,
                            score: Some(0.98),
                            weight: 0.55,
                            contribution: 0.539,
                            status: "pass".to_string(),
                        },
                    ),
                    (
                        "moire".to_string(),
                        MethodResult {
                            available: true,
                            score: Some(0.0),
                            weight: 0.15,
                            contribution: 0.0,
                            status: "not_detected".to_string(),
                        },
                    ),
                ]),
                primary_signal_valid: true,
                supporting_signals_agree: true,
                flags: vec![],
                analysis_time_ms: 2,
                computed_at: Utc::now(),
                algorithm_version: "1.0".to_string(),
                status: AggregationStatus::Success,
                cross_validation: None,
                confidence_interval: Some(ConfidenceInterval {
                    lower_bound: 0.90,
                    point_estimate: 0.95,
                    upper_bound: 0.98,
                }),
            }),
            cross_validation: None,
            computed_at: Utc::now(),
            total_processing_time_ms: 85,
        }
    }

    #[test]
    fn test_detection_results_serialization() {
        let results = sample_detection_results();
        let json = serde_json::to_string(&results).expect("Failed to serialize");
        assert!(json.contains("moire"));
        assert!(json.contains("texture"));
        assert!(json.contains("aggregated_confidence"));
    }

    #[test]
    fn test_detection_results_deserialization() {
        let json = r#"{
            "moire": {
                "detected": false,
                "confidence": 0.0,
                "peaks": [],
                "analysis_time_ms": 45,
                "algorithm_version": "1.0",
                "computed_at": "2025-12-11T10:30:00.123Z",
                "status": "completed"
            },
            "computed_at": "2025-12-11T10:30:00.123Z",
            "total_processing_time_ms": 85
        }"#;

        let results: DetectionResults = serde_json::from_str(json).expect("Failed to deserialize");
        assert!(results.moire.is_some());
        assert_eq!(results.moire.unwrap().confidence, 0.0);
        assert!(results.texture.is_none());
    }

    #[test]
    fn test_validation_passes_for_valid_data() {
        let results = sample_detection_results();
        let warnings = results.validate();
        assert!(warnings.is_empty(), "Unexpected warnings: {warnings:?}");
    }

    #[test]
    fn test_validation_warns_on_invalid_confidence() {
        let mut results = sample_detection_results();
        if let Some(ref mut moire) = results.moire {
            moire.confidence = 1.5; // Out of range
        }
        let warnings = results.validate();
        assert!(!warnings.is_empty());
        assert!(warnings[0].contains("moire.confidence"));
    }

    #[test]
    fn test_validation_warns_on_negative_time() {
        let mut results = sample_detection_results();
        results.total_processing_time_ms = -100;
        let warnings = results.validate();
        assert!(!warnings.is_empty());
        assert!(warnings[0].contains("total_processing_time_ms"));
    }

    #[test]
    fn test_summary_generation() {
        let results = sample_detection_results();
        let summary = results.summary();

        assert!(summary.detection_available);
        assert_eq!(summary.detection_confidence_level, Some("high".to_string()));
        assert!(summary.detection_primary_valid);
        assert!(summary.detection_signals_agree);
        assert_eq!(summary.detection_method_count, 3);
    }

    #[test]
    fn test_confidence_level_mapping() {
        assert_eq!(
            AggregatedConfidenceLevel::VeryHigh.to_backend_level(),
            "high"
        );
        assert_eq!(AggregatedConfidenceLevel::High.to_backend_level(), "high");
        assert_eq!(
            AggregatedConfidenceLevel::Medium.to_backend_level(),
            "medium"
        );
        assert_eq!(AggregatedConfidenceLevel::Low.to_backend_level(), "low");
        assert_eq!(
            AggregatedConfidenceLevel::Suspicious.to_backend_level(),
            "suspicious"
        );
    }

    #[test]
    fn test_texture_type_serialization() {
        let texture_type = TextureType::RealScene;
        let json = serde_json::to_string(&texture_type).expect("Failed to serialize");
        assert_eq!(json, "\"real_scene\"");

        let deserialized: TextureType =
            serde_json::from_str("\"lcd_screen\"").expect("Failed to deserialize");
        assert_eq!(deserialized, TextureType::LcdScreen);
    }

    #[test]
    fn test_confidence_flag_serialization() {
        let flag = ConfidenceFlag::ScreenDetected;
        let json = serde_json::to_string(&flag).expect("Failed to serialize");
        assert_eq!(json, "\"screen_detected\"");
    }

    #[test]
    fn test_default_detection_summary() {
        let summary = DetectionSummary::default();
        assert!(!summary.detection_available);
        assert!(summary.detection_confidence_level.is_none());
        assert!(!summary.detection_primary_valid);
        assert_eq!(summary.detection_method_count, 0);
    }
}
