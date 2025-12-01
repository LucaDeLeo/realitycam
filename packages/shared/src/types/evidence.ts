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
