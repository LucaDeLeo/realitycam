export type ConfidenceLevel = 'high' | 'medium' | 'low' | 'suspicious';
export type EvidenceStatus = 'pass' | 'fail' | 'unavailable';

export interface HardwareAttestation {
  status: EvidenceStatus;
  level: 'secure_enclave' | 'unverified';
  device_model: string;
  /** Whether the per-capture assertion signature was verified (Story 4.4) */
  assertion_verified: boolean;
  /** Whether the assertion counter was valid (strictly increasing) (Story 4.4) */
  counter_valid: boolean;
}

export interface DepthAnalysis {
  status: EvidenceStatus;
  depth_variance: number;
  depth_layers: number;
  edge_coherence: number;
  min_depth: number;
  max_depth: number;
  is_likely_real_scene: boolean;
}

/** Metadata validation evidence (Story 4-6) */
export interface MetadataEvidence {
  /** Whether the timestamp is within acceptable bounds (15 min window) */
  timestamp_valid: boolean;
  /** Delta between captured_at and server time in seconds */
  timestamp_delta_seconds: number;
  /** Whether the device model is verified (iPhone Pro whitelist) */
  model_verified: boolean;
  /** The device model name */
  model_name: string;
  /** Whether depth map resolution matches known LiDAR formats */
  resolution_valid: boolean;
  /** Whether valid location data is available */
  location_available: boolean;
  /** Whether user opted out of location sharing */
  location_opted_out: boolean;
  /** Coarse location (city/region level, for display) */
  location_coarse?: string;
}

/** Processing information for evidence generation (Story 4-7) */
export interface ProcessingInfo {
  /** When processing completed (ISO 8601) */
  processed_at: string;
  /** Total processing time in milliseconds */
  processing_time_ms: number;
  /** Backend version that processed the capture */
  backend_version: string;
}

/** Metadata privacy flags for hash-only captures (Story 8-6) */
export interface MetadataFlags {
  location_included: boolean;
  location_level: 'none' | 'coarse' | 'precise';
  timestamp_included: boolean;
  timestamp_level: 'none' | 'day_only' | 'exact';
  device_info_included: boolean;
  device_info_level: 'none' | 'model_only' | 'full';
}

/** Temporal depth analysis for video privacy mode (Story 8-8) */
export interface TemporalDepthAnalysis {
  /** Mean depth variance across keyframes */
  mean_variance: number;
  /** Variance stability score (0-1+) */
  variance_stability: number;
  /** Temporal coherence score (0-1) */
  temporal_coherence: number;
  /** Overall scene authenticity determination */
  is_likely_real_scene: boolean;
  /** Number of keyframes analyzed */
  keyframe_count: number;
}

/** Hash chain evidence for video integrity (Story 8-8) */
export interface HashChainEvidence {
  /** Verification status */
  status: 'pass' | 'partial' | 'fail';
  /** Number of verified frames */
  verified_frames: number;
  /** Total frames in video */
  total_frames: number;
  /** Whether chain is intact */
  chain_intact: boolean;
  /** Whether attestation signature is valid */
  attestation_valid: boolean;
  /** Duration of verified portion in ms */
  verified_duration_ms: number;
  /** Whether checkpoint attestations were verified */
  checkpoint_verified?: boolean;
  /** Number of checkpoints */
  checkpoint_index?: number;
}

/** Complete evidence package for a capture (Story 4-7) */
export interface Evidence {
  hardware_attestation: HardwareAttestation;
  depth_analysis: DepthAnalysis;
  metadata: MetadataEvidence;
  processing: ProcessingInfo;

  // Video-specific fields (optional, Stories 7-13 and 8-8)
  /** Evidence type - 'photo' or 'video' */
  type?: 'photo' | 'video';
  /** Analysis source - 'server' or 'device' (privacy mode) */
  analysis_source?: 'server' | 'device';
  /** Video duration in milliseconds */
  duration_ms?: number;
  /** Total frame count for video */
  frame_count?: number;
  /** Temporal depth analysis for video privacy mode (Story 8-8) */
  temporal_depth_analysis?: TemporalDepthAnalysis;
  /** Hash chain evidence for video integrity (Story 8-8) */
  hash_chain?: HashChainEvidence;
}

// ============================================================================
// Detection Types (Epic 11 - Detection Transparency, Story 11-1)
// ============================================================================

/** Method status indicating the result of a detection method */
export type DetectionMethodStatus = 'pass' | 'fail' | 'warn' | 'not_detected' | 'unavailable';

/** Result for a single detection method in the breakdown */
export interface DetectionMethodResult {
  /** Whether the method was available and executed */
  available: boolean;
  /** Score from 0.0 to 1.0, null if unavailable */
  score: number | null;
  /** Weight in confidence calculation (0.0 to 1.0) */
  weight: number;
  /** Contribution to final score (score * weight) */
  contribution: number;
  /** Status string: "pass", "fail", "warn", "not_detected", "unavailable" */
  status: DetectionMethodStatus;
  /** Reason why method is unavailable (e.g., "Model not loaded", "Analysis timeout") */
  unavailable_reason?: string;
}

/** Aggregated confidence from multi-signal detection */
export interface AggregatedConfidence {
  /** Overall confidence score (0.0 to 1.0) */
  overall_confidence: number;
  /** Confidence level using 4-level scale (backend maps very_high -> high) */
  confidence_level: ConfidenceLevel;
  /** Breakdown by detection method */
  method_breakdown: Record<string, DetectionMethodResult>;
  /** Whether primary signal (LiDAR) is valid */
  primary_signal_valid: boolean;
  /** Whether supporting signals agree with primary */
  supporting_signals_agree: boolean;
  /** Any warning or info flags */
  flags: string[];
  /** Cross-validation result (Story 11-2 - alternative location, check both places) */
  cross_validation?: CrossValidationResult;
  /** Confidence interval bounds (Story 11-2) */
  confidence_interval?: ConfidenceInterval;
}

/** LiDAR depth analysis details for tooltip display */
export interface LidarDepthDetails {
  /** Depth variance indicating scene complexity */
  depth_variance?: number;
  /** Number of distinct depth layers detected */
  depth_layers?: number;
  /** Edge coherence score (0.0 to 1.0) */
  edge_coherence?: number;
}

/** Screen type detected by moire analysis */
export type MoireScreenType = 'lcd' | 'oled' | 'high_refresh' | 'unknown';

/** Moire detection result from screen pattern analysis */
export interface MoireDetectionResult {
  /** Whether moire patterns were detected */
  detected: boolean;
  /** Confidence in detection (0.0 to 1.0) */
  confidence: number;
  /** Type of screen detected if moire found */
  screen_type?: MoireScreenType;
  /** Analysis status */
  status: 'completed' | 'unavailable' | 'failed';
}

/** Classification result from texture analysis */
export type TextureClassification = 'real_scene' | 'lcd_screen' | 'oled_screen' | 'printed_paper' | 'unknown';

/** Texture classification result */
export interface TextureClassificationResult {
  /** Classification of the texture */
  classification: TextureClassification;
  /** Confidence in classification (0.0 to 1.0) */
  confidence: number;
  /** Whether the scene is likely recaptured */
  is_likely_recaptured: boolean;
  /** Analysis status */
  status: 'success' | 'unavailable' | 'error';
}

/** Artifact analysis result (PWM, specular, halftone detection) */
export interface ArtifactAnalysisResult {
  /** Whether PWM flicker patterns were detected */
  pwm_flicker_detected: boolean;
  /** Whether specular reflection patterns were detected */
  specular_pattern_detected: boolean;
  /** Whether halftone printing patterns were detected */
  halftone_detected: boolean;
  /** Overall confidence in artifact detection (0.0 to 1.0) */
  overall_confidence: number;
  /** Whether the scene is likely artificial/recaptured */
  is_likely_artificial: boolean;
  /** Analysis status */
  status: 'success' | 'unavailable' | 'error';
}

/** Complete detection results from multi-signal analysis */
export interface DetectionResults {
  /** Moire pattern detection result */
  moire?: MoireDetectionResult;
  /** Texture classification result */
  texture?: TextureClassificationResult;
  /** Artifact analysis result */
  artifacts?: ArtifactAnalysisResult;
  /** LiDAR depth analysis details for tooltip display */
  lidar?: LidarDepthDetails;
  /** Aggregated confidence from all methods */
  aggregated_confidence?: AggregatedConfidence;
  /** Cross-validation results (Story 11-2) - may be top-level or nested in aggregated_confidence */
  cross_validation?: CrossValidationResult;
  /** When detection was computed (ISO 8601) */
  computed_at: string;
  /** Total processing time in milliseconds */
  total_processing_time_ms: number;
}

// ============================================================================
// Cross-Validation Types (Epic 11 - Detection Transparency, Story 11-2)
// ============================================================================

/** Cross-validation result between detection methods */
export interface CrossValidationResult {
  /** Overall validation status */
  validation_status: 'pass' | 'warn' | 'fail';
  /** Pairwise consistency checks */
  pairwise_consistencies: PairwiseConsistency[];
  /** Temporal consistency (video only) */
  temporal_consistency?: TemporalConsistency;
  /** Per-method confidence intervals (keys: lidar_depth, moire, texture, artifacts) */
  confidence_intervals: Record<string, ConfidenceInterval>;
  /** Aggregated confidence interval */
  aggregated_interval: ConfidenceInterval;
  /** Detected anomalies */
  anomalies: AnomalyReport[];
  /** Overall penalty applied to confidence */
  overall_penalty: number;
  /** Analysis time in milliseconds */
  analysis_time_ms: number;
  /** Algorithm version */
  algorithm_version: string;
  /** When computed (ISO 8601) */
  computed_at: string;
}

/** Pairwise consistency between two methods */
export interface PairwiseConsistency {
  method_a: string;
  method_b: string;
  expected_relationship: 'positive' | 'negative' | 'neutral';
  actual_agreement: number;
  anomaly_score: number;
  is_anomaly: boolean;
}

/** Temporal consistency for video captures */
export interface TemporalConsistency {
  frame_count: number;
  stability_scores: Record<string, number>;
  anomalies: TemporalAnomaly[];
  overall_stability: number;
}

/** Temporal anomaly in video analysis */
export interface TemporalAnomaly {
  frame_index: number;
  method: string;
  delta_score: number;
  anomaly_type: 'sudden_jump' | 'oscillation' | 'drift';
}

/** Confidence interval bounds (matches backend ConfidenceInterval) */
export interface ConfidenceInterval {
  lower_bound: number;
  point_estimate: number;
  upper_bound: number;
}

/** Anomaly report from cross-validation */
export interface AnomalyReport {
  anomaly_type: 'contradictory_signals' | 'too_high_agreement' | 'isolated_disagreement' | 'boundary_cluster' | 'correlation_anomaly';
  severity: 'low' | 'medium' | 'high';
  affected_methods: string[];
  details: string;
  confidence_impact: number;
}
