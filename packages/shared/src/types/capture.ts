import { ConfidenceLevel, Evidence } from './evidence';

export interface Capture {
  id: string;
  confidence_level: ConfidenceLevel;
  captured_at: string;
  media_url: string;
  evidence: Evidence;
  c2pa_manifest_url?: string;
  depth_visualization_url?: string;
}
