/**
 * useNetworkStatus Hook
 *
 * Network connectivity monitoring with debounced state updates.
 * Prevents network state flapping by debouncing changes by 300ms.
 *
 * @see Story 4.2 - Upload Queue with Retry Logic (AC-4)
 */

import { useEffect, useState, useCallback, useRef } from 'react';
import NetInfo, { NetInfoState, NetInfoStateType } from '@react-native-community/netinfo';

/**
 * Network connection type classification
 */
export type ConnectionType =
  | 'wifi'
  | 'cellular'
  | 'ethernet'
  | 'bluetooth'
  | 'other'
  | 'none'
  | 'unknown';

/**
 * Network status information
 */
export interface NetworkStatus {
  /** Whether device is connected to a network */
  isConnected: boolean | null;
  /** Whether internet is actually reachable (not just connected to network) */
  isInternetReachable: boolean | null;
  /** Type of connection (wifi, cellular, etc.) */
  connectionType: ConnectionType;
}

/**
 * useNetworkStatus hook return type
 */
export interface UseNetworkStatusReturn extends NetworkStatus {
  /** Manually refresh network status */
  refresh: () => Promise<void>;
}

/**
 * Debounce delay for network state changes
 * Prevents rapid state flapping during unstable connections
 */
const NETWORK_DEBOUNCE_MS = 300;

/**
 * Map NetInfo state type to our simplified connection type
 */
function mapConnectionType(type: NetInfoStateType): ConnectionType {
  switch (type) {
    case 'wifi':
      return 'wifi';
    case 'cellular':
      return 'cellular';
    case 'ethernet':
      return 'ethernet';
    case 'bluetooth':
      return 'bluetooth';
    case 'none':
      return 'none';
    case 'unknown':
      return 'unknown';
    default:
      return 'other';
  }
}

/**
 * Hook for monitoring network connectivity status
 *
 * Features:
 * - Debounced state updates (300ms) to prevent flapping
 * - Tracks both connection status and internet reachability
 * - Provides connection type (wifi, cellular, etc.)
 * - Automatically subscribes to network changes
 *
 * @example
 * ```tsx
 * const { isConnected, isInternetReachable, connectionType } = useNetworkStatus();
 *
 * if (!isConnected) {
 *   return <OfflineMessage />;
 * }
 *
 * // Only upload when internet is actually reachable
 * if (isInternetReachable) {
 *   startUpload();
 * }
 * ```
 */
export function useNetworkStatus(): UseNetworkStatusReturn {
  // Network state
  const [status, setStatus] = useState<NetworkStatus>({
    isConnected: null,
    isInternetReachable: null,
    connectionType: 'unknown',
  });

  // Debounce timer ref
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  /**
   * Process network state update with debouncing
   */
  const handleNetworkChange = useCallback((state: NetInfoState) => {
    // Clear any pending debounce
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
    }

    // Debounce the state update
    debounceTimerRef.current = setTimeout(() => {
      setStatus({
        isConnected: state.isConnected,
        isInternetReachable: state.isInternetReachable,
        connectionType: mapConnectionType(state.type),
      });
      console.log('[useNetworkStatus] Network state updated:', {
        isConnected: state.isConnected,
        isInternetReachable: state.isInternetReachable,
        type: state.type,
      });
    }, NETWORK_DEBOUNCE_MS);
  }, []);

  /**
   * Manually refresh network status
   */
  const refresh = useCallback(async () => {
    try {
      const state = await NetInfo.fetch();
      // Update immediately without debounce for manual refresh
      setStatus({
        isConnected: state.isConnected,
        isInternetReachable: state.isInternetReachable,
        connectionType: mapConnectionType(state.type),
      });
      console.log('[useNetworkStatus] Manual refresh:', {
        isConnected: state.isConnected,
        isInternetReachable: state.isInternetReachable,
        type: state.type,
      });
    } catch (error) {
      console.error('[useNetworkStatus] Failed to refresh network status:', error);
    }
  }, []);

  // Subscribe to network changes on mount
  useEffect(() => {
    console.log('[useNetworkStatus] Subscribing to network changes');

    // Initial fetch
    NetInfo.fetch().then((state) => {
      setStatus({
        isConnected: state.isConnected,
        isInternetReachable: state.isInternetReachable,
        connectionType: mapConnectionType(state.type),
      });
      console.log('[useNetworkStatus] Initial network state:', {
        isConnected: state.isConnected,
        isInternetReachable: state.isInternetReachable,
        type: state.type,
      });
    });

    // Subscribe to changes
    const unsubscribe = NetInfo.addEventListener(handleNetworkChange);

    // Cleanup
    return () => {
      console.log('[useNetworkStatus] Unsubscribing from network changes');
      unsubscribe();
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
    };
  }, [handleNetworkChange]);

  return {
    ...status,
    refresh,
  };
}
