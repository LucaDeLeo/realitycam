/**
 * Custom Assertions for RealityCam Tests
 *
 * Domain-specific assertions for evidence verification.
 */

import type { Evidence } from '../factories/capture.factory';

/**
 * Assert confidence level matches expected
 */
export function assertConfidenceLevel(
  evidence: Evidence | undefined,
  expected: 'high' | 'medium' | 'low' | 'suspicious'
): void {
  const actual = calculateConfidence(evidence);
  if (actual !== expected) {
    throw new Error(`Expected confidence '${expected}', got '${actual}'`);
  }
}

/**
 * Calculate confidence level from evidence
 */
function calculateConfidence(evidence: Evidence | undefined): string {
  if (!evidence) return 'low';

  const hwPass = evidence.hardwareAttestation.status === 'pass';
  const depthPass = evidence.depthAnalysis.isLikelyRealScene;
  const anyFail = evidence.hardwareAttestation.status === 'fail' ||
                  evidence.depthAnalysis.status === 'fail';

  if (anyFail) return 'suspicious';
  if (hwPass && depthPass) return 'high';
  if (hwPass || depthPass) return 'medium';
  return 'low';
}

/**
 * Assert hardware attestation passed
 */
export function assertHardwareAttestationPass(evidence: Evidence): void {
  if (evidence.hardwareAttestation.status !== 'pass') {
    throw new Error(
      `Expected hardware attestation to pass, got '${evidence.hardwareAttestation.status}'`
    );
  }
}

/**
 * Assert depth analysis indicates real scene
 */
export function assertRealScene(evidence: Evidence): void {
  if (!evidence.depthAnalysis.isLikelyRealScene) {
    throw new Error('Expected depth analysis to indicate real scene');
  }
}

/**
 * Assert depth analysis indicates flat surface
 */
export function assertFlatSurface(evidence: Evidence): void {
  if (evidence.depthAnalysis.isLikelyRealScene) {
    throw new Error('Expected depth analysis to indicate flat surface');
  }
}

/**
 * Assert depth variance is above threshold
 */
export function assertDepthVarianceAbove(evidence: Evidence, threshold: number): void {
  const variance = evidence.depthAnalysis.depthVariance;
  if (variance <= threshold) {
    throw new Error(`Expected depth variance > ${threshold}, got ${variance}`);
  }
}

/**
 * Assert depth layers count
 */
export function assertDepthLayersAtLeast(evidence: Evidence, minLayers: number): void {
  const layers = evidence.depthAnalysis.depthLayers;
  if (layers < minLayers) {
    throw new Error(`Expected at least ${minLayers} depth layers, got ${layers}`);
  }
}

/**
 * Assert edge coherence above threshold
 */
export function assertEdgeCoherenceAbove(evidence: Evidence, threshold: number): void {
  const coherence = evidence.depthAnalysis.edgeCoherence;
  if (coherence <= threshold) {
    throw new Error(`Expected edge coherence > ${threshold}, got ${coherence}`);
  }
}

/**
 * Assert metadata timestamp is valid
 */
export function assertTimestampValid(evidence: Evidence): void {
  if (!evidence.metadata.timestampValid) {
    throw new Error('Expected timestamp to be valid');
  }
}
