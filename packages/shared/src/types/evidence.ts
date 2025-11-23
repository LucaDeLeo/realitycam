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

export interface Evidence {
  hardware_attestation: HardwareAttestation;
  depth_analysis: DepthAnalysis;
  metadata: {
    timestamp_valid: boolean;
    model_verified: boolean;
    location_available: boolean;
    location_coarse?: string;
  };
}
