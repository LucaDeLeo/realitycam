/**
 * Device Store - Zustand store for device capabilities and key management
 *
 * Manages device capability state with AsyncStorage persistence.
 * Used to track device support status and Secure Enclave key state across app sessions.
 *
 * Story 2.1: Device capabilities (model, LiDAR, Secure Enclave, DCAppAttest)
 * Story 2.2: Key management (keyId, keyGenerationStatus, isAttestationReady)
 */

import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type {
  DeviceCapabilities,
  KeyGenerationStatus,
  AttestationStatus,
} from '@realitycam/shared';

/**
 * Device store state interface
 */
interface DeviceState {
  // --- Story 2.1: Device Capabilities ---
  /** Detected device capabilities (null before detection) */
  capabilities: DeviceCapabilities | null;
  /** Loading state during capability detection */
  isLoading: boolean;
  /** Whether hydration from AsyncStorage is complete */
  hasHydrated: boolean;

  // --- Story 2.2: Key Management ---
  /** Secure Enclave key ID (null if not generated) */
  keyId: string | null;
  /** Current key generation lifecycle status */
  keyGenerationStatus: KeyGenerationStatus;
  /** Error message if key generation failed */
  keyGenerationError: string | undefined;
  /** True when key is ready and device can perform attestation */
  isAttestationReady: boolean;

  // --- Story 2.1 Actions ---
  /** Set capabilities after detection completes */
  setCapabilities: (capabilities: DeviceCapabilities) => void;
  /** Clear stored capabilities (useful for re-detection) */
  clearCapabilities: () => void;
  /** Set hydration status */
  setHasHydrated: (hydrated: boolean) => void;

  // --- Story 2.2 Actions ---
  /** Set the Secure Enclave key ID */
  setKeyId: (keyId: string | null) => void;
  /** Set key generation status */
  setKeyStatus: (status: KeyGenerationStatus) => void;
  /** Set key generation error message */
  setKeyError: (error: string | undefined) => void;
  /** Reset key state (for regeneration scenarios) */
  resetKeyState: () => void;

  // --- Story 2.3: Attestation State ---
  /** Current attestation lifecycle status */
  attestationStatus: AttestationStatus;
  /** Base64-encoded CBOR attestation object from DCAppAttest */
  attestationObject: string | null;
  /** Base64-encoded challenge from backend (preserved for registration) */
  challenge: string | null;
  /** Unix timestamp when challenge expires */
  challengeExpiresAt: number | null;
  /** Error message if attestation failed */
  attestationError: string | undefined;
  /** True when attestation has completed successfully (persisted to prevent re-attestation) */
  isAttested: boolean;

  // --- Story 2.3 Actions ---
  /** Set attestation status */
  setAttestationStatus: (status: AttestationStatus) => void;
  /** Set attestation object (base64 CBOR) */
  setAttestationObject: (object: string | null) => void;
  /** Set challenge and its expiration time */
  setChallenge: (challenge: string | null, expiresAt?: string) => void;
  /** Set attestation error message */
  setAttestationError: (error: string | undefined) => void;
  /** Reset attestation state (for retry scenarios) */
  resetAttestationState: () => void;
}

/**
 * Device store with persistence to AsyncStorage
 *
 * Usage:
 * ```tsx
 * const { capabilities, isLoading, keyGenerationStatus } = useDeviceStore();
 *
 * if (isLoading) return <LoadingScreen />;
 * if (!capabilities?.isSupported) return <UnsupportedDeviceScreen />;
 * // Key generation happens automatically after capability check passes
 * ```
 */
export const useDeviceStore = create<DeviceState>()(
  persist(
    (set) => ({
      // Story 2.1 state
      capabilities: null,
      isLoading: true,
      hasHydrated: false,

      // Story 2.2 state
      keyId: null,
      keyGenerationStatus: 'idle',
      keyGenerationError: undefined,
      isAttestationReady: false,

      // Story 2.3 state
      attestationStatus: 'idle',
      attestationObject: null,
      challenge: null,
      challengeExpiresAt: null,
      attestationError: undefined,
      isAttested: false,

      // Story 2.1 actions
      setCapabilities: (capabilities) =>
        set({ capabilities, isLoading: false }),
      clearCapabilities: () =>
        set({ capabilities: null, isLoading: true }),
      setHasHydrated: (hydrated) => set({ hasHydrated: hydrated }),

      // Story 2.2 actions
      setKeyId: (keyId) =>
        set({
          keyId,
          isAttestationReady: keyId !== null,
        }),
      setKeyStatus: (status) =>
        set({
          keyGenerationStatus: status,
          // Clear error when transitioning away from failed state
          ...(status !== 'failed' ? { keyGenerationError: undefined } : {}),
        }),
      setKeyError: (error) =>
        set({
          keyGenerationError: error,
          keyGenerationStatus: 'failed',
          isAttestationReady: false,
        }),
      resetKeyState: () =>
        set({
          keyId: null,
          keyGenerationStatus: 'idle',
          keyGenerationError: undefined,
          isAttestationReady: false,
        }),

      // Story 2.3 actions
      setAttestationStatus: (status) =>
        set({
          attestationStatus: status,
          // Clear error when transitioning away from failed state
          ...(status !== 'failed' ? { attestationError: undefined } : {}),
          // Mark as attested when status is 'attested'
          ...(status === 'attested' ? { isAttested: true } : {}),
        }),
      setAttestationObject: (object) =>
        set({ attestationObject: object }),
      setChallenge: (challenge, expiresAt) =>
        set({
          challenge,
          challengeExpiresAt: expiresAt ? new Date(expiresAt).getTime() : null,
        }),
      setAttestationError: (error) =>
        set({
          attestationError: error,
          attestationStatus: 'failed',
        }),
      resetAttestationState: () =>
        set({
          attestationStatus: 'idle',
          attestationObject: null,
          challenge: null,
          challengeExpiresAt: null,
          attestationError: undefined,
          // Note: isAttested is NOT reset here - attestation is one-time per key
        }),
    }),
    {
      name: 'realitycam-device-storage',
      storage: createJSONStorage(() => AsyncStorage),
      // Persist capabilities and key state (keyId stored separately in SecureStore for security)
      // We persist keyGenerationStatus to know if we previously succeeded/failed
      // Story 2.3: Also persist isAttested to prevent re-attestation (one-time enforcement)
      partialize: (state) => ({
        capabilities: state.capabilities,
        keyGenerationStatus: state.keyGenerationStatus,
        isAttestationReady: state.isAttestationReady,
        isAttested: state.isAttested,
      }),
      onRehydrateStorage: () => (state) => {
        // Called when hydration completes
        state?.setHasHydrated(true);
      },
    }
  )
);
