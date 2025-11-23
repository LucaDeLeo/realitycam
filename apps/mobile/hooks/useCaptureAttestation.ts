/**
 * useCaptureAttestation Hook
 *
 * Generates per-capture device attestation assertions using @expo/app-integrity.
 * Each capture is signed with an assertion that binds the photo hash, depth hash,
 * timestamp, and optional location hash to the attested device.
 *
 * Features:
 * - Generates assertions using generateAssertionAsync(keyId, clientDataHash)
 * - Computes SHA-256 clientDataHash from AssertionMetadata
 * - Graceful degradation - assertion failure never blocks capture
 * - Uses keyId from deviceStore (from Story 2.3)
 *
 * @see Story 3.4 - Capture Attestation Signature
 * @see Epic 3 Tech Spec - AC-3.6 Per-Capture Assertion
 */

import { useCallback, useState } from 'react';
import * as AppIntegrity from '@expo/app-integrity';
import * as Crypto from 'expo-crypto';
import type {
  AssertionMetadata,
  CaptureAssertion,
  CaptureAssertionError,
  CaptureAssertionErrorCode,
} from '@realitycam/shared';
import { useDeviceStore } from '../store/deviceStore';

/**
 * useCaptureAttestation hook return type
 */
export interface UseCaptureAttestationReturn {
  /** Generate per-capture assertion for given metadata */
  generateAssertion: (metadata: AssertionMetadata) => Promise<CaptureAssertion | null>;
  /** True when device is attested and can generate assertions */
  isReady: boolean;
  /** True during assertion generation */
  isGenerating: boolean;
  /** Error from last assertion operation (null if none) */
  error: CaptureAssertionError | null;
  /** Clear the last error */
  clearError: () => void;
}

/**
 * Create typed assertion error
 */
function createAssertionError(
  code: CaptureAssertionErrorCode,
  message: string
): CaptureAssertionError {
  return { code, message };
}

/**
 * Hook for per-capture device attestation assertions
 *
 * Generates assertions that bind capture metadata (photo hash, depth hash,
 * timestamp, location hash) to the attested device key.
 *
 * @example
 * ```tsx
 * function CaptureScreen() {
 *   const { generateAssertion, isReady, isGenerating, error } = useCaptureAttestation();
 *
 *   const handleCapture = async (metadata: AssertionMetadata) => {
 *     if (isReady) {
 *       const assertion = await generateAssertion(metadata);
 *       if (assertion) {
 *         console.log('Assertion generated:', assertion.assertion);
 *       } else {
 *         console.log('Proceeding without assertion (unverified mode)');
 *       }
 *     }
 *   };
 *
 *   return <CameraView onCapture={handleCapture} />;
 * }
 * ```
 */
export function useCaptureAttestation(): UseCaptureAttestationReturn {
  // Get attestation state from device store
  const { keyId, isAttested } = useDeviceStore();

  // Local state
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<CaptureAssertionError | null>(null);

  // Compute readiness - device must be attested with valid keyId
  const isReady = isAttested && keyId !== null;

  /**
   * Clear error state
   */
  const clearError = useCallback(() => {
    setError(null);
  }, []);

  /**
   * Generate per-capture assertion for given metadata
   *
   * @param metadata - AssertionMetadata containing hashes and timestamp
   * @returns CaptureAssertion object or null if assertion failed/unavailable
   */
  const generateAssertion = useCallback(
    async (metadata: AssertionMetadata): Promise<CaptureAssertion | null> => {
      // Clear previous error
      setError(null);

      // Check readiness - return null if not attested (graceful degradation)
      if (!isReady || !keyId) {
        console.log(
          '[useCaptureAttestation] Device not attested, skipping assertion generation'
        );
        setError(
          createAssertionError(
            'NOT_ATTESTED',
            'Device not attested. Capture will proceed without hardware verification.'
          )
        );
        return null;
      }

      setIsGenerating(true);

      try {
        // Step 1: Compute clientDataHash from metadata JSON
        console.log('[useCaptureAttestation] Computing clientDataHash...');
        const metadataJson = JSON.stringify(metadata);

        let clientDataHash: string;
        try {
          clientDataHash = await Crypto.digestStringAsync(
            Crypto.CryptoDigestAlgorithm.SHA256,
            metadataJson,
            { encoding: Crypto.CryptoEncoding.BASE64 }
          );
        } catch (hashError) {
          console.error(
            '[useCaptureAttestation] Hash computation failed:',
            hashError
          );
          setError(
            createAssertionError(
              'HASH_FAILED',
              'Failed to compute capture hash. Capture will proceed without hardware verification.'
            )
          );
          setIsGenerating(false);
          return null;
        }

        console.log(
          `[useCaptureAttestation] clientDataHash computed: ${clientDataHash.substring(0, 20)}...`
        );

        // Step 2: Generate assertion using @expo/app-integrity
        console.log('[useCaptureAttestation] Calling generateAssertionAsync...');
        const assertionResult = await AppIntegrity.generateAssertionAsync(
          keyId,
          clientDataHash
        );

        // Step 3: Build CaptureAssertion object
        const captureAssertion: CaptureAssertion = {
          assertion: assertionResult,
          clientDataHash,
          timestamp: new Date().toISOString(),
        };

        console.log('[useCaptureAttestation] Assertion generated successfully');
        setIsGenerating(false);

        return captureAssertion;
      } catch (assertionError) {
        // Log error and return null (graceful degradation)
        const errorMessage =
          assertionError instanceof Error
            ? assertionError.message
            : String(assertionError);

        console.error(
          '[useCaptureAttestation] Assertion generation failed:',
          errorMessage
        );

        setError(
          createAssertionError(
            'ASSERTION_FAILED',
            'Failed to generate device assertion. Capture will proceed without hardware verification.'
          )
        );
        setIsGenerating(false);

        return null;
      }
    },
    [isReady, keyId]
  );

  return {
    generateAssertion,
    isReady,
    isGenerating,
    error,
    clearError,
  };
}
