/**
 * RealityCam Web API Client
 *
 * Provides methods for:
 * - getCapture: Retrieve capture details by ID
 * - verifyFile: Upload and verify a file against the database
 */

import type {
  ConfidenceLevel,
  EvidenceStatus,
  HardwareAttestation,
  DepthAnalysis,
  MetadataEvidence,
  ProcessingInfo,
} from '@realitycam/shared';

import {
  generateCorrelationId,
  logApiRequest,
  logApiResponse,
  logApiError,
} from './debug-logger';

// Re-export shared types for backwards compatibility
export type {
  ConfidenceLevel,
  HardwareAttestation,
  DepthAnalysis,
  MetadataEvidence,
  ProcessingInfo,
};

// Alias for backwards compatibility (CheckStatus was the old name)
// TODO: Remove this alias once all consumers migrate to EvidenceStatus
export type CheckStatus = EvidenceStatus;

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080';

/** Request timeout in milliseconds (10 seconds) */
const REQUEST_TIMEOUT_MS = 10_000;

/**
 * Creates an AbortController with timeout
 */
function createTimeoutController(timeoutMs: number = REQUEST_TIMEOUT_MS): {
  controller: AbortController;
  timeoutId: NodeJS.Timeout;
} {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  return { controller, timeoutId };
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
    // Epic 8: Hash-Only Fields (Story 8-7)
    capture_mode?: 'full' | 'hash_only';
    media_stored?: boolean;
    media_hash?: string;
    evidence?: EvidencePackage;
    metadata_flags?: {
      location_included: boolean;
      location_level: 'none' | 'coarse' | 'precise';
      timestamp_included: boolean;
      timestamp_level: 'none' | 'day_only' | 'exact';
      device_info_included: boolean;
      device_info_level: 'none' | 'model_only' | 'full';
    };
    captured_at?: string;
    media_type?: 'photo' | 'video';
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
    const correlationId = generateCorrelationId();
    const startTime = Date.now();
    const url = `${this.baseUrl}/api/v1/captures/${id}`;

    logApiRequest(url, 'GET', correlationId);

    const { controller, timeoutId } = createTimeoutController();
    try {
      const response = await fetch(url, {
        cache: 'no-store',
        signal: controller.signal,
        headers: {
          'X-Correlation-ID': correlationId,
        },
      });

      clearTimeout(timeoutId);
      const durationMs = Date.now() - startTime;
      logApiResponse(url, response.status, durationMs, correlationId);

      if (!response.ok) {
        if (response.status === 404) {
          return null;
        }
        throw new Error(`API error: ${response.status}`);
      }

      return response.json();
    } catch (error) {
      clearTimeout(timeoutId);
      const err = error instanceof Error ? error : new Error('Unknown error');
      logApiError(url, err, correlationId);
      if (err.name === 'AbortError') {
        console.error('Request timed out fetching capture:', id);
      } else {
        console.error('Failed to fetch capture:', error);
      }
      return null;
    }
  }

  /**
   * Get public capture details by ID (for web verification page)
   * Uses the public /api/v1/verify/{id} endpoint
   */
  async getCapturePublic(id: string): Promise<CapturePublicResponse | null> {
    const correlationId = generateCorrelationId();
    const startTime = Date.now();
    const url = `${this.baseUrl}/api/v1/verify/${id}`;

    logApiRequest(url, 'GET', correlationId);

    const { controller, timeoutId } = createTimeoutController();
    try {
      const response = await fetch(url, {
        cache: 'no-store',
        signal: controller.signal,
        headers: {
          'X-Correlation-ID': correlationId,
        },
      });

      clearTimeout(timeoutId);
      const durationMs = Date.now() - startTime;
      logApiResponse(url, response.status, durationMs, correlationId);

      if (!response.ok) {
        if (response.status === 404) {
          return null;
        }
        throw new Error(`API error: ${response.status}`);
      }

      return response.json();
    } catch (error) {
      clearTimeout(timeoutId);
      const err = error instanceof Error ? error : new Error('Unknown error');
      logApiError(url, err, correlationId);
      if (err.name === 'AbortError') {
        console.error('Request timed out fetching public capture:', id);
      } else {
        console.error('Failed to fetch capture public:', error);
      }
      return null;
    }
  }

  /**
   * Verify a file by uploading it for hash verification
   */
  async verifyFile(file: File): Promise<FileVerificationResponse> {
    const correlationId = generateCorrelationId();
    const startTime = Date.now();
    const url = `${this.baseUrl}/api/v1/verify-file`;

    logApiRequest(url, 'POST', correlationId);

    // Use longer timeout for file uploads (30 seconds)
    const { controller, timeoutId } = createTimeoutController(30_000);
    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await fetch(url, {
        method: 'POST',
        body: formData,
        signal: controller.signal,
        headers: {
          'X-Correlation-ID': correlationId,
        },
      });

      clearTimeout(timeoutId);
      const durationMs = Date.now() - startTime;
      logApiResponse(url, response.status, durationMs, correlationId);

      if (!response.ok) {
        const error = await response.json().catch(() => ({ error: { message: 'Unknown error' } }));
        throw new Error(error.error?.message ?? 'Verification failed');
      }

      return response.json();
    } catch (error) {
      clearTimeout(timeoutId);
      const err = error instanceof Error ? error : new Error('Unknown error');
      logApiError(url, err, correlationId);
      if (err.name === 'AbortError') {
        throw new Error('Request timed out. Please try again.');
      }
      throw error;
    }
  }
}

/**
 * Singleton API client instance
 */
export const apiClient = new ApiClient();

// ============================================================================
// Helper Functions (re-exported from @/lib/status for backwards compatibility)
// ============================================================================

// Re-export confidence helpers from status module
export {
  getConfidenceFullColor as getConfidenceColor,
  getConfidenceLabel,
} from './status';


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

/**
 * Format date for day-only display (privacy mode)
 */
export function formatDateDayOnly(dateString: string): string {
  try {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  } catch {
    return dateString;
  }
}
