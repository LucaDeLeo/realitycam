/**
 * useSecureEnclaveKey Hook
 *
 * Manages Secure Enclave key generation and retrieval lifecycle.
 * Uses @expo/app-integrity for key generation and expo-secure-store for persistence.
 *
 * State Machine:
 * - idle -> checking (on hook mount when device is supported)
 * - checking -> ready (if existing key found in SecureStore)
 * - checking -> generating (if no existing key)
 * - generating -> ready (on successful key generation)
 * - generating -> failed (on error)
 *
 * Error Handling:
 * - Key generation failures set attestationLevel to "unverified"
 * - App continues functioning without attestation capability
 * - Specific error messages for different failure types
 *
 * @see Story 2.2 - Secure Enclave Key Generation
 */

import { useEffect, useRef, useCallback } from 'react';
import * as AppIntegrity from '@expo/app-integrity';
import * as SecureStore from 'expo-secure-store';
import { useDeviceStore } from '../store/deviceStore';

/**
 * SecureStore key for the attestation key ID
 * Uses WHEN_UNLOCKED_THIS_DEVICE_ONLY for maximum security
 */
const SECURE_STORE_KEY_ID = 'attestation_key_id';

/**
 * Timeout for key generation (5 seconds as per spec)
 */
const KEY_GENERATION_TIMEOUT_MS = 5000;

/**
 * Error messages for different failure scenarios
 */
const ERROR_MESSAGES = {
  GENERATION_FAILED: 'Unable to generate secure key. Device attestation unavailable.',
  SECURITY_FAILED: 'Device security verification failed. Captures will be marked as unverified.',
  STORAGE_FAILED: 'Unable to save security credentials. Please restart the app.',
  TIMEOUT: 'Key generation timed out. Please try again.',
  INVALID_KEY: 'Stored key is invalid. Regenerating...',
} as const;

/**
 * Checks if an error indicates a jailbreak or security restriction
 */
function isSecurityError(error: Error): boolean {
  const message = error.message.toLowerCase();
  return (
    message.includes('jailbreak') ||
    message.includes('security') ||
    message.includes('tamper') ||
    message.includes('compromised') ||
    message.includes('restriction') ||
    message.includes('not supported')
  );
}

/**
 * Retrieves the stored key ID from SecureStore
 */
async function getStoredKeyId(): Promise<string | null> {
  try {
    const keyId = await SecureStore.getItemAsync(SECURE_STORE_KEY_ID);
    return keyId;
  } catch (error) {
    console.error('[useSecureEnclaveKey] Failed to retrieve stored key:', error);
    return null;
  }
}

/**
 * Stores the key ID in SecureStore with maximum security options
 */
async function storeKeyId(keyId: string): Promise<void> {
  await SecureStore.setItemAsync(SECURE_STORE_KEY_ID, keyId, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  });
}

/**
 * Clears the stored key ID (for regeneration scenarios)
 */
async function clearStoredKeyId(): Promise<void> {
  try {
    await SecureStore.deleteItemAsync(SECURE_STORE_KEY_ID);
  } catch (error) {
    console.error('[useSecureEnclaveKey] Failed to clear stored key:', error);
  }
}

/**
 * Validates that a key ID is valid (non-empty string)
 */
function isValidKeyId(keyId: string | null): keyId is string {
  return typeof keyId === 'string' && keyId.length > 0;
}

/**
 * Generates a new key with timeout protection
 */
async function generateKeyWithTimeout(): Promise<string> {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error(ERROR_MESSAGES.TIMEOUT));
    }, KEY_GENERATION_TIMEOUT_MS);

    AppIntegrity.generateKeyAsync()
      .then((keyId) => {
        clearTimeout(timeoutId);
        resolve(keyId);
      })
      .catch((error) => {
        clearTimeout(timeoutId);
        reject(error);
      });
  });
}

/**
 * Hook for Secure Enclave key generation and management
 *
 * Automatically initiates key check/generation when:
 * 1. Device capabilities indicate support (hasDCAppAttest)
 * 2. Hydration from AsyncStorage is complete
 *
 * @returns Object containing key state and control functions
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const { isAttestationReady, keyGenerationStatus, error } = useSecureEnclaveKey();
 *
 *   if (keyGenerationStatus === 'checking' || keyGenerationStatus === 'generating') {
 *     return <Text>Setting up secure key...</Text>;
 *   }
 *
 *   if (keyGenerationStatus === 'failed') {
 *     return <WarningBanner message={error} />;
 *   }
 *
 *   return <MainContent attestationReady={isAttestationReady} />;
 * }
 * ```
 */
export function useSecureEnclaveKey() {
  const {
    capabilities,
    hasHydrated,
    keyId,
    keyGenerationStatus,
    keyGenerationError,
    isAttestationReady,
    setKeyId,
    setKeyStatus,
    setKeyError,
    resetKeyState,
  } = useDeviceStore();

  // Prevent multiple initialization attempts
  const hasInitialized = useRef(false);

  /**
   * Main initialization logic
   * Checks for existing key or generates new one
   */
  const initializeKey = useCallback(async () => {
    // Transition: idle -> checking
    setKeyStatus('checking');
    console.log('[useSecureEnclaveKey] Starting key check...');

    try {
      // Step 1: Check for existing key in SecureStore
      const existingKeyId = await getStoredKeyId();

      if (isValidKeyId(existingKeyId)) {
        // Existing key found - validate and use it
        console.log('[useSecureEnclaveKey] Found existing key ID');

        // AC-9: Validate stored key ID is usable
        // For now, we just check it's a non-empty string
        // Full validation would require attempting to use the key
        setKeyId(existingKeyId);
        setKeyStatus('ready');
        console.log('[useSecureEnclaveKey] Key ready (from storage)');
        return;
      }

      // No existing key - generate new one
      console.log('[useSecureEnclaveKey] No existing key, generating new one...');

      // Transition: checking -> generating
      setKeyStatus('generating');

      // Step 2: Generate new key in Secure Enclave
      const newKeyId = await generateKeyWithTimeout();

      if (!isValidKeyId(newKeyId)) {
        throw new Error('Key generation returned invalid key ID');
      }

      // Step 3: Store the key ID in SecureStore
      console.log('[useSecureEnclaveKey] Storing key ID in SecureStore...');
      try {
        await storeKeyId(newKeyId);
      } catch (storageError) {
        console.error('[useSecureEnclaveKey] Failed to store key:', storageError);
        throw new Error(ERROR_MESSAGES.STORAGE_FAILED);
      }

      // Step 4: Update store with new key
      setKeyId(newKeyId);
      setKeyStatus('ready');
      console.log('[useSecureEnclaveKey] Key generated and stored successfully');
    } catch (error) {
      // Handle different error types with specific messages
      const err = error instanceof Error ? error : new Error(String(error));
      console.error('[useSecureEnclaveKey] Key generation failed:', err.message);

      let userMessage: string;
      if (err.message === ERROR_MESSAGES.TIMEOUT) {
        userMessage = ERROR_MESSAGES.TIMEOUT;
      } else if (err.message === ERROR_MESSAGES.STORAGE_FAILED) {
        userMessage = ERROR_MESSAGES.STORAGE_FAILED;
      } else if (isSecurityError(err)) {
        userMessage = ERROR_MESSAGES.SECURITY_FAILED;
      } else {
        userMessage = ERROR_MESSAGES.GENERATION_FAILED;
      }

      // Transition: checking/generating -> failed
      setKeyError(userMessage);
      console.log('[useSecureEnclaveKey] Status set to failed:', userMessage);
    }
  }, [setKeyId, setKeyStatus, setKeyError]);

  /**
   * Force regeneration of key
   * Used when stored key is invalid/corrupted (AC-9)
   */
  const regenerateKey = useCallback(async () => {
    console.log('[useSecureEnclaveKey] Regenerating key...');

    // Clear existing state
    resetKeyState();
    await clearStoredKeyId();

    // Reset initialization flag and reinitialize
    hasInitialized.current = false;
    await initializeKey();
  }, [resetKeyState, initializeKey]);

  // Effect to trigger key initialization when device is ready
  useEffect(() => {
    // Guard conditions
    if (!hasHydrated) {
      console.log('[useSecureEnclaveKey] Waiting for hydration...');
      return;
    }

    if (hasInitialized.current) {
      console.log('[useSecureEnclaveKey] Already initialized');
      return;
    }

    // Check if device supports attestation
    if (!capabilities?.hasDCAppAttest) {
      console.log('[useSecureEnclaveKey] Device does not support DCAppAttest');
      setKeyError(ERROR_MESSAGES.GENERATION_FAILED);
      hasInitialized.current = true;
      return;
    }

    // Don't reinitialize if we already have a ready key from previous session
    // But we still need to load the keyId from SecureStore
    if (keyGenerationStatus === 'ready' && isAttestationReady) {
      console.log('[useSecureEnclaveKey] Key already ready from previous session, loading keyId');
      // Load keyId from SecureStore to restore full state
      hasInitialized.current = true;
      getStoredKeyId().then((storedKeyId) => {
        if (isValidKeyId(storedKeyId)) {
          setKeyId(storedKeyId);
        } else {
          // Key status says ready but no valid key in storage - regenerate
          console.log('[useSecureEnclaveKey] Status ready but no valid key found, regenerating');
          resetKeyState();
          hasInitialized.current = false;
        }
      });
      return;
    }

    // Start initialization
    hasInitialized.current = true;
    initializeKey();
  }, [
    hasHydrated,
    capabilities,
    keyGenerationStatus,
    isAttestationReady,
    setKeyId,
    setKeyError,
    resetKeyState,
    initializeKey,
  ]);

  return {
    // State
    keyId,
    keyGenerationStatus,
    keyGenerationError,
    isAttestationReady,

    // Computed
    isKeyReady: keyGenerationStatus === 'ready' && keyId !== null,
    isKeyLoading: keyGenerationStatus === 'checking' || keyGenerationStatus === 'generating',
    isKeyFailed: keyGenerationStatus === 'failed',

    // Actions
    regenerateKey,
  };
}
