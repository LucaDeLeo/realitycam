/**
 * Root Layout
 *
 * Entry point for the app navigation. Performs device capability check
 * and Secure Enclave key generation before allowing access to main app features.
 *
 * Flow:
 * 1. Hydrate persisted state from AsyncStorage
 * 2. Detect device capabilities (Story 2.1)
 * 3. Generate Secure Enclave key (Story 2.2)
 * 4. Render main app or error screens
 */

import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import {
  View,
  Text,
  ActivityIndicator,
  StyleSheet,
  useColorScheme,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { useDeviceCapabilities } from '../hooks/useDeviceCapabilities';
import { useSecureEnclaveKey } from '../hooks/useSecureEnclaveKey';
import { UnsupportedDeviceScreen } from '../components/Device/UnsupportedDeviceScreen';
import { colors } from '../constants/colors';

/**
 * Loading screen shown during capability detection and key generation
 */
function LoadingScreen({ message = 'Checking device capabilities...' }: { message?: string }) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  return (
    <View
      style={[
        styles.loadingContainer,
        { backgroundColor: isDark ? colors.backgroundDark : colors.background },
      ]}
    >
      <ActivityIndicator
        size="large"
        color={colors.primary}
      />
      <Text
        style={[
          styles.loadingText,
          { color: isDark ? colors.textDark : colors.text },
        ]}
      >
        {message}
      </Text>
    </View>
  );
}

/**
 * Warning banner shown when key generation fails
 * App continues to work but captures will be marked as unverified
 */
function AttestationWarningBanner({ message }: { message: string }) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  return (
    <SafeAreaView
      edges={['top']}
      style={[
        styles.warningBanner,
        { backgroundColor: isDark ? colors.warningDark : colors.warning },
      ]}
    >
      <Text
        style={[
          styles.warningText,
          { color: isDark ? colors.warningTextDark : colors.warningText },
        ]}
      >
        {message}
      </Text>
    </SafeAreaView>
  );
}

export default function RootLayout() {
  const { capabilities, isLoading, hasHydrated } = useDeviceCapabilities();

  // Initialize Secure Enclave key generation (Story 2.2)
  // This hook manages its own lifecycle and only runs after capability check passes
  const {
    keyGenerationStatus,
    keyGenerationError,
    isKeyLoading,
    isKeyFailed,
  } = useSecureEnclaveKey();

  // Show loading screen during hydration and capability detection
  if (!hasHydrated || isLoading) {
    return (
      <SafeAreaProvider>
        <StatusBar style="auto" />
        <LoadingScreen message="Checking device capabilities..." />
      </SafeAreaProvider>
    );
  }

  // Show blocking screen for unsupported devices
  if (!capabilities?.isSupported) {
    return (
      <SafeAreaProvider>
        <StatusBar style="auto" />
        <UnsupportedDeviceScreen reason={capabilities?.unsupportedReason} />
      </SafeAreaProvider>
    );
  }

  // Show loading screen during key generation (optional - could also proceed)
  // We show a brief loading state during key setup for better UX
  if (isKeyLoading && keyGenerationStatus === 'generating') {
    return (
      <SafeAreaProvider>
        <StatusBar style="auto" />
        <LoadingScreen message="Setting up secure key..." />
      </SafeAreaProvider>
    );
  }

  // Supported device - render normal app navigation
  // If key generation failed, show warning banner but don't block app
  return (
    <SafeAreaProvider>
      <StatusBar style="auto" />
      {isKeyFailed && keyGenerationError && (
        <AttestationWarningBanner message={keyGenerationError} />
      )}
      <Stack>
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      </Stack>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
  },
  loadingText: {
    fontSize: 16,
    marginTop: 16,
  },
  warningBanner: {
    padding: 12,
    paddingHorizontal: 16,
  },
  warningText: {
    fontSize: 14,
    textAlign: 'center',
    fontWeight: '500',
  },
});
