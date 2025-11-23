/**
 * Device Store - Zustand store for device capabilities
 *
 * Manages device capability state with AsyncStorage persistence.
 * Used to track device support status across app sessions.
 */

import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type { DeviceCapabilities } from '@realitycam/shared';

/**
 * Device store state interface
 */
interface DeviceState {
  /** Detected device capabilities (null before detection) */
  capabilities: DeviceCapabilities | null;
  /** Loading state during capability detection */
  isLoading: boolean;
  /** Whether hydration from AsyncStorage is complete */
  hasHydrated: boolean;
  /** Set capabilities after detection completes */
  setCapabilities: (capabilities: DeviceCapabilities) => void;
  /** Clear stored capabilities (useful for re-detection) */
  clearCapabilities: () => void;
  /** Set hydration status */
  setHasHydrated: (hydrated: boolean) => void;
}

/**
 * Device store with persistence to AsyncStorage
 *
 * Usage:
 * ```tsx
 * const { capabilities, isLoading } = useDeviceStore();
 *
 * if (isLoading) return <LoadingScreen />;
 * if (!capabilities?.isSupported) return <UnsupportedDeviceScreen />;
 * ```
 */
export const useDeviceStore = create<DeviceState>()(
  persist(
    (set) => ({
      capabilities: null,
      isLoading: true,
      hasHydrated: false,
      setCapabilities: (capabilities) =>
        set({ capabilities, isLoading: false }),
      clearCapabilities: () =>
        set({ capabilities: null, isLoading: true }),
      setHasHydrated: (hydrated) => set({ hasHydrated: hydrated }),
    }),
    {
      name: 'realitycam-device-storage',
      storage: createJSONStorage(() => AsyncStorage),
      // Only persist capabilities, not loading state
      partialize: (state) => ({ capabilities: state.capabilities }),
      onRehydrateStorage: () => (state) => {
        // Called when hydration completes
        state?.setHasHydrated(true);
      },
    }
  )
);
