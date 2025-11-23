/**
 * useDeviceAttestation Hook
 *
 * Manages DCAppAttest attestation lifecycle after Secure Enclave key generation.
 * Orchestrates challenge retrieval from backend and attestKeyAsync call.
 *
 * State Machine:
 * - idle -> fetching_challenge (when initiateAttestation called)
 * - fetching_challenge -> attesting (when challenge received)
 * - fetching_challenge -> failed (on network error)
 * - attesting -> attested (on successful attestation)
 * - attesting -> failed (on attestation error)
 * - failed -> fetching_challenge (on retry)
 *
 * Error Handling:
 * - Network errors trigger retry with exponential backoff (1s, 2s, 4s)
 * - Security errors (jailbreak/compromised) set unverified mode and continue
 * - After 3 retries, proceeds in unverified mode
 *
 * @see Story 2.3 - DCAppAttest Integration
 */

import { useEffect, useRef, useCallback, useState } from 'react';
import * as AppIntegrity from '@expo/app-integrity';
import type { AttestationStatus } from '@realitycam/shared';
import { useDeviceStore } from '../store/deviceStore';
import {
  fetchChallenge,
  base64ToUint8Array,
  ApiError,
  API_ERROR_CODES,
} from '../services/api';

/**
 * Attestation timeout in milliseconds (5 seconds as per spec)
 */
const ATTESTATION_TIMEOUT_MS = 5_000;

/**
 * Maximum retry attempts for network failures
 */
const MAX_RETRY_ATTEMPTS = 3;

/**
 * Base delay for exponential backoff (1 second)
 */
const BASE_RETRY_DELAY_MS = 1_000;

/**
 * Error messages for different failure scenarios
 */
export const ATTESTATION_ERROR_MESSAGES = {
  NETWORK_ERROR:
    'Unable to verify device. Please check your connection.',
  RATE_LIMITED:
    'Too many requests. Please wait a moment and try again.',
  SECURITY_FAILED:
    'Device security verification failed. Captures will be marked as unverified.',
  CHALLENGE_EXPIRED:
    'Refreshing security token...',
  GENERAL_FAILURE:
    'Unable to complete device verification. Captures will be marked as unverified.',
  ATTESTATION_TIMEOUT:
    'Device verification timed out. Please try again.',
} as const;

/**
 * Checks if an error indicates a security/compromise issue
 * Based on pattern from useSecureEnclaveKey
 */
function isSecurityError(error: Error): boolean {
  const message = error.message.toLowerCase();
  return (
    message.includes('jailbreak') ||
    message.includes('security') ||
    message.includes('tamper') ||
    message.includes('compromised') ||
    message.includes('restriction') ||
    message.includes('not supported') ||
    message.includes('device not supported')
  );
}

/**
 * Checks if the challenge has expired
 */
function isChallengeExpired(expiresAt: number | null): boolean {
  if (expiresAt === null) return true;
  return Date.now() >= expiresAt;
}

/**
 * Performs attestation with timeout protection
 * Note: attestKeyAsync expects challenge as Uint8Array, returns base64 string
 */
async function attestWithTimeout(
  keyId: string,
  challengeBytes: Uint8Array
): Promise<string> {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error(ATTESTATION_ERROR_MESSAGES.ATTESTATION_TIMEOUT));
    }, ATTESTATION_TIMEOUT_MS);

    // Convert Uint8Array to string for the API (base64 encode the challenge bytes)
    // The @expo/app-integrity API expects the challenge as a string
    const challengeString = Array.from(challengeBytes)
      .map((b) => String.fromCharCode(b))
      .join('');

    AppIntegrity.attestKeyAsync(keyId, challengeString)
      .then((attestationObject) => {
        clearTimeout(timeoutId);
        resolve(attestationObject);
      })
      .catch((error) => {
        clearTimeout(timeoutId);
        reject(error);
      });
  });
}

/**
 * Sleep utility for exponential backoff
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Hook return type
 */
export interface UseDeviceAttestationReturn {
  /** Current attestation status */
  attestationStatus: AttestationStatus;
  /** Whether attestation has completed successfully */
  isAttested: boolean;
  /** Whether attestation is in progress (fetching challenge or attesting) */
  isAttesting: boolean;
  /** Whether attestation failed */
  isAttestationFailed: boolean;
  /** Error message if attestation failed */
  attestationError: string | undefined;
  /** Current retry attempt (0 if not retrying) */
  retryAttempt: number;
  /** Manually trigger attestation (for retry button) */
  initiateAttestation: () => Promise<void>;
}

/**
 * Hook for DCAppAttest attestation management
 *
 * Automatically initiates attestation when:
 * 1. isAttestationReady is true (key generation complete)
 * 2. isAttested is false (not already attested)
 * 3. hasHydrated is true (persisted state loaded)
 *
 * @returns Object containing attestation state and control functions
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const {
 *     attestationStatus,
 *     isAttested,
 *     isAttesting,
 *     isAttestationFailed,
 *     attestationError,
 *     initiateAttestation,
 *   } = useDeviceAttestation();
 *
 *   if (isAttesting) {
 *     return <LoadingScreen message="Verifying device security..." />;
 *   }
 *
 *   if (isAttestationFailed) {
 *     return (
 *       <View>
 *         <Text>{attestationError}</Text>
 *         <Button title="Retry" onPress={initiateAttestation} />
 *       </View>
 *     );
 *   }
 *
 *   return <MainContent />;
 * }
 * ```
 */
export function useDeviceAttestation(): UseDeviceAttestationReturn {
  const {
    keyId,
    isAttestationReady,
    hasHydrated,
    attestationStatus,
    attestationObject,
    challenge,
    challengeExpiresAt,
    attestationError,
    isAttested,
    setAttestationStatus,
    setAttestationObject,
    setChallenge,
    setAttestationError,
    resetAttestationState,
  } = useDeviceStore();

  // Prevent multiple initialization attempts
  const hasInitialized = useRef(false);

  // Track retry attempts
  const [retryAttempt, setRetryAttempt] = useState(0);

  /**
   * Fetches challenge from backend with retry logic
   */
  const fetchChallengeWithRetry = useCallback(
    async (attempt: number = 0): Promise<{ challenge: string; expiresAt: string }> => {
      try {
        const response = await fetchChallenge();
        return {
          challenge: response.data.challenge,
          expiresAt: response.data.expires_at,
        };
      } catch (error) {
        // Check if we should retry
        if (
          error instanceof ApiError &&
          (error.code === API_ERROR_CODES.NETWORK_ERROR ||
            error.code === API_ERROR_CODES.TIMEOUT) &&
          attempt < MAX_RETRY_ATTEMPTS - 1
        ) {
          // Exponential backoff: 1s, 2s, 4s
          const delay = BASE_RETRY_DELAY_MS * Math.pow(2, attempt);
          console.log(
            `[useDeviceAttestation] Challenge fetch failed, retrying in ${delay}ms (attempt ${attempt + 1}/${MAX_RETRY_ATTEMPTS})`
          );
          await sleep(delay);
          return fetchChallengeWithRetry(attempt + 1);
        }
        throw error;
      }
    },
    []
  );

  /**
   * Main attestation flow
   */
  const initiateAttestation = useCallback(async () => {
    // Guard: need valid keyId
    if (!keyId) {
      console.log('[useDeviceAttestation] No keyId available, cannot attest');
      return;
    }

    // Guard: already attested (one-time enforcement)
    if (isAttested) {
      console.log('[useDeviceAttestation] Already attested, skipping');
      return;
    }

    console.log('[useDeviceAttestation] Starting attestation flow...');

    try {
      // Step 1: Fetch challenge from backend
      setAttestationStatus('fetching_challenge');
      console.log('[useDeviceAttestation] Fetching challenge from backend...');

      let challengeData: string;
      let challengeExpiresAtStr: string;

      // Check if we have a valid cached challenge
      if (challenge && !isChallengeExpired(challengeExpiresAt)) {
        console.log('[useDeviceAttestation] Using cached challenge');
        challengeData = challenge;
        challengeExpiresAtStr = new Date(challengeExpiresAt!).toISOString();
      } else {
        // Fetch new challenge
        const result = await fetchChallengeWithRetry();
        challengeData = result.challenge;
        challengeExpiresAtStr = result.expiresAt;
        setChallenge(challengeData, challengeExpiresAtStr);
        console.log('[useDeviceAttestation] Challenge received and stored');
      }

      // Step 2: Convert challenge to Uint8Array for attestKeyAsync
      const challengeBytes = base64ToUint8Array(challengeData);
      console.log(
        `[useDeviceAttestation] Challenge converted to ${challengeBytes.length} bytes`
      );

      // Step 3: Perform attestation
      setAttestationStatus('attesting');
      console.log('[useDeviceAttestation] Calling attestKeyAsync...');

      const attestationResult = await attestWithTimeout(keyId, challengeBytes);

      // Step 4: Store attestation result
      console.log('[useDeviceAttestation] Attestation successful');
      setAttestationObject(attestationResult);
      setAttestationStatus('attested');
      setRetryAttempt(0);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      console.error('[useDeviceAttestation] Attestation failed:', err.message);

      // Determine user message based on error type
      let userMessage: string;

      if (error instanceof ApiError) {
        switch (error.code) {
          case API_ERROR_CODES.RATE_LIMITED:
            userMessage = ATTESTATION_ERROR_MESSAGES.RATE_LIMITED;
            break;
          case API_ERROR_CODES.NETWORK_ERROR:
          case API_ERROR_CODES.TIMEOUT:
            userMessage = ATTESTATION_ERROR_MESSAGES.NETWORK_ERROR;
            break;
          default:
            userMessage = ATTESTATION_ERROR_MESSAGES.GENERAL_FAILURE;
        }
      } else if (isSecurityError(err)) {
        userMessage = ATTESTATION_ERROR_MESSAGES.SECURITY_FAILED;
      } else if (err.message === ATTESTATION_ERROR_MESSAGES.ATTESTATION_TIMEOUT) {
        userMessage = ATTESTATION_ERROR_MESSAGES.ATTESTATION_TIMEOUT;
      } else {
        userMessage = ATTESTATION_ERROR_MESSAGES.GENERAL_FAILURE;
      }

      setAttestationError(userMessage);
      setRetryAttempt((prev) => prev + 1);
      console.log('[useDeviceAttestation] Status set to failed:', userMessage);
    }
  }, [
    keyId,
    isAttested,
    challenge,
    challengeExpiresAt,
    fetchChallengeWithRetry,
    setAttestationStatus,
    setAttestationObject,
    setChallenge,
    setAttestationError,
  ]);

  /**
   * Manual retry with automatic backoff
   */
  const retryAttestation = useCallback(async () => {
    if (retryAttempt >= MAX_RETRY_ATTEMPTS) {
      console.log(
        '[useDeviceAttestation] Max retries reached, proceeding in unverified mode'
      );
      setAttestationError(ATTESTATION_ERROR_MESSAGES.GENERAL_FAILURE);
      return;
    }

    // Reset state for retry
    resetAttestationState();
    await initiateAttestation();
  }, [retryAttempt, resetAttestationState, initiateAttestation, setAttestationError]);

  // Effect to automatically initiate attestation when ready
  useEffect(() => {
    // Guard conditions
    if (!hasHydrated) {
      console.log('[useDeviceAttestation] Waiting for hydration...');
      return;
    }

    if (hasInitialized.current) {
      console.log('[useDeviceAttestation] Already initialized');
      return;
    }

    if (!isAttestationReady) {
      console.log('[useDeviceAttestation] Key not ready, waiting...');
      return;
    }

    if (isAttested) {
      console.log('[useDeviceAttestation] Already attested from previous session');
      hasInitialized.current = true;
      return;
    }

    // Start attestation
    hasInitialized.current = true;
    initiateAttestation();
  }, [hasHydrated, isAttestationReady, isAttested, initiateAttestation]);

  return {
    attestationStatus,
    isAttested,
    isAttesting:
      attestationStatus === 'fetching_challenge' ||
      attestationStatus === 'attesting',
    isAttestationFailed: attestationStatus === 'failed',
    attestationError,
    retryAttempt,
    initiateAttestation: retryAttestation,
  };
}
