import type { APIRequestContext } from '@playwright/test';

/**
 * Evidence Factory
 *
 * Creates test evidence data via API with auto-cleanup.
 * Follows data-factories.md knowledge base patterns.
 */

/**
 * Detection summary data from multi-signal analysis (Story 9-8)
 */
export interface DetectionSummary {
  detectionAvailable: boolean;
  confidenceLevel?: 'high' | 'medium' | 'low' | 'suspicious';
  primaryValid: boolean;
  signalsAgree: boolean;
  methodCount: number;
}

export interface EvidenceData {
  id: string;
  captureId: string;
  deviceId: string;
  confidenceScore: number;
  status: 'pending' | 'processing' | 'complete' | 'failed';
  type?: 'photo' | 'video';
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
  /** Multi-signal detection results (Story 9-8) */
  detection?: DetectionSummary;
}

export interface CreateEvidenceOptions {
  confidenceScore?: number;
  status?: EvidenceData['status'];
  type?: 'photo' | 'video';
  hasDepth?: boolean;
  depthLayers?: number;
  hasClaim?: boolean;
  signatureValid?: boolean;
  deviceModel?: string;
}

/**
 * Options for creating evidence with detection data (Story 9-8)
 */
export interface CreateWithDetectionOptions extends CreateEvidenceOptions {
  hasDetection?: boolean;
  detectionConfidenceLevel?: 'high' | 'medium' | 'low' | 'suspicious';
  detectionPrimaryValid?: boolean;
  detectionSignalsAgree?: boolean;
  detectionMethodCount?: number;
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
   * Create evidence with multi-signal detection data (Story 9-8)
   *
   * Creates evidence that includes detection summary from iOS multi-signal
   * analysis (moire, texture, artifacts, cross-validation).
   *
   * @param overrides - Override default detection options
   * @returns Evidence with detection summary attached
   */
  async createWithDetection(
    overrides: CreateWithDetectionOptions = {}
  ): Promise<EvidenceData & { detection: DetectionSummary }> {
    const detectionDefaults = {
      hasDetection: true,
      detectionConfidenceLevel: 'high' as const,
      detectionPrimaryValid: true,
      detectionSignalsAgree: true,
      detectionMethodCount: 3,
    };

    const options = { ...detectionDefaults, ...overrides };

    // Create base evidence data
    const evidenceData = {
      confidenceScore: options.confidenceScore ?? 0.9,
      status: options.status ?? ('complete' as const),
      type: options.type ?? ('photo' as const),
      depthAnalysis: {
        hasDepth: options.hasDepth ?? true,
        depthLayers: options.depthLayers ?? 5,
        variance: 0.45,
        coherence: 0.82,
      },
      c2pa: {
        hasClaim: options.hasClaim ?? true,
        claimGenerator: 'RealityCam/1.0',
        signatureValid: options.signatureValid ?? true,
      },
      metadata: {
        timestamp: new Date().toISOString(),
        deviceModel: options.deviceModel ?? 'iPhone 15 Pro',
      },
      // Detection data (Story 9-8)
      detection: options.hasDetection
        ? {
            detectionAvailable: true,
            confidenceLevel: options.detectionConfidenceLevel,
            primaryValid: options.detectionPrimaryValid,
            signalsAgree: options.detectionSignalsAgree,
            methodCount: options.detectionMethodCount,
          }
        : undefined,
    };

    const response = await this.request.post(`${this.baseURL}/api/v1/test/evidence`, {
      data: evidenceData,
      headers: { 'Content-Type': 'application/json' },
    });

    if (!response.ok()) {
      throw new Error(`Failed to create test evidence with detection: ${response.status()}`);
    }

    const responseBody = (await response.json()) as { data: EvidenceData };
    const created = responseBody.data;
    this.createdIds.push(created.id);

    // Ensure detection is present in return type
    return {
      ...created,
      detection: created.detection ?? {
        detectionAvailable: options.hasDetection ?? true,
        confidenceLevel: options.detectionConfidenceLevel,
        primaryValid: options.detectionPrimaryValid ?? true,
        signalsAgree: options.detectionSignalsAgree ?? true,
        methodCount: options.detectionMethodCount ?? 3,
      },
    };
  }

  /**
   * Create verified evidence with high detection confidence (Story 9-8)
   */
  async createVerifiedWithDetection(): Promise<EvidenceData & { detection: DetectionSummary }> {
    return this.createWithDetection({
      confidenceScore: 0.95,
      hasDepth: true,
      depthLayers: 5,
      hasDetection: true,
      detectionConfidenceLevel: 'high',
      detectionPrimaryValid: true,
      detectionSignalsAgree: true,
      detectionMethodCount: 3,
    });
  }

  /**
   * Create suspicious evidence with low detection confidence (Story 9-8)
   */
  async createSuspiciousWithDetection(): Promise<EvidenceData & { detection: DetectionSummary }> {
    return this.createWithDetection({
      confidenceScore: 0.25,
      hasDepth: false,
      depthLayers: 0,
      hasDetection: true,
      detectionConfidenceLevel: 'suspicious',
      detectionPrimaryValid: false,
      detectionSignalsAgree: true, // All methods agree it's suspicious
      detectionMethodCount: 3,
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
