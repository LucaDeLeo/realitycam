/**
 * RealityCam Web API Client
 *
 * Provides methods for:
 * - getCapture: Retrieve capture details by ID
 * - verifyFile: Upload and verify a file against the database
 */

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080';

// ============================================================================
// Types
// ============================================================================

export type ConfidenceLevel = 'high' | 'medium' | 'low' | 'suspicious';
export type CheckStatus = 'pass' | 'fail' | 'unavailable';

export interface HardwareAttestation {
  status: CheckStatus;
  level: 'secure_enclave' | 'unverified';
  device_model: string;
  assertion_verified: boolean;
  counter_valid: boolean;
}

export interface DepthAnalysis {
  status: CheckStatus;
  depth_variance: number;
  depth_layers: number;
  edge_coherence: number;
  min_depth: number;
  max_depth: number;
  is_likely_real_scene: boolean;
}

export interface MetadataEvidence {
  timestamp_valid: boolean;
  timestamp_delta_seconds: number;
  model_verified: boolean;
  model_name: string;
  resolution_valid: boolean;
  location_available: boolean;
  location_opted_out: boolean;
  location_coarse?: string;
}

export interface ProcessingInfo {
  processed_at: string;
  processing_time_ms: number;
  backend_version: string;
}

export interface EvidencePackage {
  hardware_attestation: HardwareAttestation;
  depth_analysis: DepthAnalysis;
  metadata: MetadataEvidence;
  processing: ProcessingInfo;
}

export interface CaptureData {
  id: string;
  confidence_level: ConfidenceLevel;
  status: 'pending' | 'processing' | 'complete' | 'failed';
  captured_at: string;
  uploaded_at: string;
  media_url?: string;
  thumbnail_url?: string;
  depth_preview_url?: string;
  c2pa_media_url?: string;
  c2pa_manifest_url?: string;
  evidence: EvidencePackage;
  location_coarse?: string;
}

export interface CaptureResponse {
  data: CaptureData;
  meta: {
    request_id: string;
    timestamp: string;
  };
}

export interface CapturePublicData {
  capture_id: string;
  confidence_level: string;
  captured_at: string;
  uploaded_at: string;
  location_coarse?: string;
  evidence: EvidencePackage;
  photo_url?: string;
  depth_map_url?: string;
}

export interface CapturePublicResponse {
  data: CapturePublicData;
  meta: {
    request_id: string;
    timestamp: string;
  };
}

export type VerificationStatus = 'verified' | 'c2pa_only' | 'no_record';

export interface C2paManifestInfo {
  claim_generator: string;
  created_at?: string;
  assertions?: {
    confidence_level?: string;
    hardware_attestation?: {
      status: string;
      level?: string;
      verified?: boolean;
    };
    depth_analysis?: {
      status: string;
      is_real_scene?: boolean;
      depth_layers?: number;
    };
    device_model?: string;
    captured_at?: string;
  };
}

export interface FileVerificationResponse {
  data: {
    status: VerificationStatus;
    capture_id?: string;
    confidence_level?: ConfidenceLevel;
    verification_url?: string;
    manifest_info?: C2paManifestInfo;
    note?: string;
    file_hash: string;
  };
  meta: {
    request_id: string;
    timestamp: string;
  };
}

// ============================================================================
// API Client
// ============================================================================

export class ApiClient {
  public baseUrl: string;

  constructor(baseUrl: string = API_URL) {
    this.baseUrl = baseUrl;
  }

  /**
   * Get capture details by ID (requires device auth - for mobile app)
   */
  async getCapture(id: string): Promise<CaptureResponse | null> {
    try {
      const response = await fetch(`${this.baseUrl}/api/v1/captures/${id}`, {
        cache: 'no-store',
      });

      if (!response.ok) {
        if (response.status === 404) {
          return null;
        }
        throw new Error(`API error: ${response.status}`);
      }

      return response.json();
    } catch (error) {
      console.error('Failed to fetch capture:', error);
      return null;
    }
  }

  /**
   * Get public capture details by ID (for web verification page)
   * Uses the public /api/v1/verify/{id} endpoint
   */
  async getCapturePublic(id: string): Promise<CapturePublicResponse | null> {
    try {
      const response = await fetch(`${this.baseUrl}/api/v1/verify/${id}`, {
        cache: 'no-store',
      });

      if (!response.ok) {
        if (response.status === 404) {
          return null;
        }
        throw new Error(`API error: ${response.status}`);
      }

      return response.json();
    } catch (error) {
      console.error('Failed to fetch capture public:', error);
      return null;
    }
  }

  /**
   * Verify a file by uploading it for hash verification
   */
  async verifyFile(file: File): Promise<FileVerificationResponse> {
    const formData = new FormData();
    formData.append('file', file);

    const response = await fetch(`${this.baseUrl}/api/v1/verify-file`, {
      method: 'POST',
      body: formData,
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: 'Unknown error' }));
      throw new Error(error.error?.message ?? 'Verification failed');
    }

    return response.json();
  }
}

/**
 * Singleton API client instance
 */
export const apiClient = new ApiClient();

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Get confidence level color
 */
export function getConfidenceColor(level: ConfidenceLevel): string {
  switch (level) {
    case 'high':
      return 'text-green-600 bg-green-50 border-green-200 dark:text-green-400 dark:bg-green-900/20 dark:border-green-800';
    case 'medium':
      return 'text-yellow-600 bg-yellow-50 border-yellow-200 dark:text-yellow-400 dark:bg-yellow-900/20 dark:border-yellow-800';
    case 'low':
      return 'text-orange-600 bg-orange-50 border-orange-200 dark:text-orange-400 dark:bg-orange-900/20 dark:border-orange-800';
    case 'suspicious':
      return 'text-red-600 bg-red-50 border-red-200 dark:text-red-400 dark:bg-red-900/20 dark:border-red-800';
    default:
      return 'text-zinc-600 bg-zinc-50 border-zinc-200 dark:text-zinc-400 dark:bg-zinc-900/20 dark:border-zinc-800';
  }
}

/**
 * Get confidence level label
 */
export function getConfidenceLabel(level: ConfidenceLevel): string {
  switch (level) {
    case 'high':
      return 'HIGH CONFIDENCE';
    case 'medium':
      return 'MEDIUM CONFIDENCE';
    case 'low':
      return 'LOW CONFIDENCE';
    case 'suspicious':
      return 'SUSPICIOUS';
    default:
      return 'UNKNOWN';
  }
}

/**
 * Get check status icon and color
 */
export function getStatusDisplay(status: CheckStatus): { icon: string; color: string; label: string } {
  switch (status) {
    case 'pass':
      return { icon: 'check', color: 'text-green-600 dark:text-green-400', label: 'Pass' };
    case 'fail':
      return { icon: 'x', color: 'text-red-600 dark:text-red-400', label: 'Fail' };
    case 'unavailable':
      return { icon: 'minus', color: 'text-zinc-400 dark:text-zinc-500', label: 'Unavailable' };
    default:
      return { icon: 'minus', color: 'text-zinc-400', label: 'Unknown' };
  }
}

/**
 * Format date for display
 */
export function formatDate(dateString: string): string {
  try {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return dateString;
  }
}
