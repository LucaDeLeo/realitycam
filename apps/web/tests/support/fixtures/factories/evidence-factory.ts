import type { APIRequestContext } from '@playwright/test';

/**
 * Evidence Factory
 *
 * Creates test evidence data via API with auto-cleanup.
 * Follows data-factories.md knowledge base patterns.
 */

export interface EvidenceData {
  id: string;
  captureId: string;
  deviceId: string;
  confidenceScore: number;
  status: 'pending' | 'processing' | 'complete' | 'failed';
  depthAnalysis: {
    hasDepth: boolean;
    depthLayers: number;
    variance: number;
    coherence: number;
  };
  c2pa: {
    hasClaim: boolean;
    claimGenerator: string;
    signatureValid: boolean;
  };
  metadata: {
    timestamp: string;
    latitude?: number;
    longitude?: number;
    deviceModel: string;
  };
}

export interface CreateEvidenceOptions {
  confidenceScore?: number;
  status?: EvidenceData['status'];
  hasDepth?: boolean;
  depthLayers?: number;
  hasClaim?: boolean;
  signatureValid?: boolean;
  deviceModel?: string;
}

export class EvidenceFactory {
  private createdIds: string[] = [];
  private baseURL: string;

  constructor(private request: APIRequestContext) {
    this.baseURL = process.env.API_URL || 'http://localhost:8080';
  }

  /**
   * Create evidence with sensible defaults and optional overrides
   */
  async create(overrides: CreateEvidenceOptions = {}): Promise<EvidenceData> {
    const defaults: CreateEvidenceOptions = {
      confidenceScore: 0.85,
      status: 'complete',
      hasDepth: true,
      depthLayers: 4,
      hasClaim: true,
      signatureValid: true,
      deviceModel: 'iPhone 15 Pro',
    };

    const options = { ...defaults, ...overrides };

    const evidenceData = {
      confidenceScore: options.confidenceScore,
      status: options.status,
      depthAnalysis: {
        hasDepth: options.hasDepth,
        depthLayers: options.depthLayers,
        variance: 0.42,
        coherence: 0.78,
      },
      c2pa: {
        hasClaim: options.hasClaim,
        claimGenerator: 'RealityCam/1.0',
        signatureValid: options.signatureValid,
      },
      metadata: {
        timestamp: new Date().toISOString(),
        deviceModel: options.deviceModel,
      },
    };

    const response = await this.request.post(`${this.baseURL}/api/v1/test/evidence`, {
      data: evidenceData,
      headers: { 'Content-Type': 'application/json' },
    });

    if (!response.ok()) {
      throw new Error(`Failed to create test evidence: ${response.status()}`);
    }

    // Backend wraps response in { data: ..., meta: ... }
    const responseBody = (await response.json()) as { data: EvidenceData };
    const created = responseBody.data;
    this.createdIds.push(created.id);

    return created;
  }

  /**
   * Create evidence with high confidence (verified photo)
   */
  async createVerified(): Promise<EvidenceData> {
    return this.create({
      confidenceScore: 0.95,
      status: 'complete',
      hasDepth: true,
      depthLayers: 5,
      hasClaim: true,
      signatureValid: true,
    });
  }

  /**
   * Create evidence with low confidence (suspicious photo)
   */
  async createSuspicious(): Promise<EvidenceData> {
    return this.create({
      confidenceScore: 0.35,
      status: 'complete',
      hasDepth: false,
      depthLayers: 0,
      hasClaim: true,
      signatureValid: false,
    });
  }

  /**
   * Create evidence that's still processing
   */
  async createPending(): Promise<EvidenceData> {
    return this.create({
      status: 'processing',
      confidenceScore: 0,
    });
  }

  /**
   * Auto-cleanup: Delete all created evidence
   */
  async cleanup(): Promise<void> {
    for (const id of this.createdIds) {
      try {
        await this.request.delete(`${this.baseURL}/api/v1/test/evidence/${id}`);
      } catch {
        // Ignore cleanup errors (resource may already be deleted)
      }
    }
    this.createdIds = [];
  }
}
