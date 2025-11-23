import type { ApiResponse, ApiError, Capture, ConfidenceLevel } from '@realitycam/shared';

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080';

/**
 * Response structure for file verification
 */
export interface VerifyFileResponse {
  data: {
    status: 'verified' | 'c2pa_only' | 'no_record';
    capture_id?: string;
    confidence_level?: ConfidenceLevel;
    verification_url?: string;
  };
  meta: {
    request_id: string;
    timestamp: string;
  };
}

/**
 * Response structure for capture detail retrieval
 */
export interface CaptureDetailResponse {
  data: Capture | null;
  meta: {
    request_id: string;
    timestamp: string;
  };
}

/**
 * WebApiClient interface defining the API contract
 */
export interface WebApiClient {
  baseUrl: string;
  getCapture(id: string): Promise<CaptureDetailResponse>;
  verifyFile(file: File): Promise<VerifyFileResponse>;
}

/**
 * ApiClient - HTTP client for RealityCam API
 *
 * Provides methods for:
 * - getCapture: Retrieve capture details by ID
 * - verifyCapture: Verify a capture by ID
 * - verifyFile: Upload and verify a file (placeholder implementation)
 */
export class ApiClient implements WebApiClient {
  public baseUrl: string;

  constructor(baseUrl: string = API_URL) {
    this.baseUrl = baseUrl;
  }

  /**
   * Get capture details by ID
   * Returns full capture data including evidence and verification status
   */
  async getCapture(id: string): Promise<CaptureDetailResponse> {
    // In development, return mock data
    if (process.env.NODE_ENV === 'development') {
      return {
        data: null, // Will be populated when backend is connected
        meta: {
          request_id: `mock-${Date.now()}`,
          timestamp: new Date().toISOString(),
        },
      };
    }

    const response = await fetch(`${this.baseUrl}/api/v1/captures/${id}`);
    if (!response.ok) {
      const error: ApiError = await response.json();
      throw new Error(error.error.message);
    }
    return response.json();
  }

  /**
   * Verify a capture by ID (deprecated - use verifyFile for file uploads)
   */
  async verifyCapture(id: string): Promise<ApiResponse<Capture>> {
    const response = await fetch(`${this.baseUrl}/api/v1/captures/${id}/verify`);
    if (!response.ok) {
      const error: ApiError = await response.json();
      throw new Error(error.error.message);
    }
    return response.json();
  }

  /**
   * Verify a file by uploading it for hash verification
   *
   * This is a placeholder implementation that returns mock data.
   * The actual implementation will:
   * 1. Calculate the file hash
   * 2. Send the hash to the backend for lookup
   * 3. Return verification status and capture details if found
   *
   * @param file - The file to verify (JPEG, PNG, or HEIC)
   * @returns VerifyFileResponse with verification status
   */
  async verifyFile(file: File): Promise<VerifyFileResponse> {
    // Placeholder implementation - returns mock data for development
    console.log(`[API Mock] verifyFile called with file: ${file.name}, size: ${file.size}`);

    // Simulate network delay
    await new Promise((resolve) => setTimeout(resolve, 500));

    return {
      data: {
        status: 'no_record',
        // When a match is found, these will be populated:
        // capture_id: 'abc123',
        // confidence_level: 'high',
        // verification_url: '/verify/abc123',
      },
      meta: {
        request_id: `mock-verify-${Date.now()}`,
        timestamp: new Date().toISOString(),
      },
    };
  }
}

/**
 * Singleton API client instance
 */
export const apiClient = new ApiClient();
