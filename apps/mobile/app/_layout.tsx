/**
 * Root Layout
 *
 * Entry point for the app navigation. Performs device capability check,
 * Secure Enclave key generation, and DCAppAttest attestation before
 * allowing access to main app features.
 *
 * Flow:
 * 1. Hydrate persisted state from AsyncStorage
 * 2. Detect device capabilities (Story 2.1)
 * 3. Generate Secure Enclave key (Story 2.2)
 * 4. Perform DCAppAttest attestation (Story 2.3)
 * 5. Render main app or error screens
 */

import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import {
  View,
  Text,
  ActivityIndicator,
  StyleSheet,
  useColorScheme,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { useDeviceCapabilities } from '../hooks/useDeviceCapabilities';
import { useSecureEnclaveKey } from '../hooks/useSecureEnclaveKey';
import { useDeviceAttestation } from '../hooks/useDeviceAttestation';
import { UnsupportedDeviceScreen } from '../components/Device/UnsupportedDeviceScreen';
import { LogoHeader } from '../components/Logo';
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
 * Warning banner shown when key generation or attestation fails
 * App continues to work but captures will be marked as unverified
 */
function AttestationWarningBanner({
  message,
  onRetry,
  showRetry = false,
}: {
  message: string;
  onRetry?: () => void;
  showRetry?: boolean;
}) {
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
      <View style={styles.warningContent}>
        <Text
          style={[
            styles.warningText,
            { color: isDark ? colors.warningTextDark : colors.warningText },
          ]}
        >
          {message}
        </Text>
        {showRetry && onRetry && (
          <TouchableOpacity
            onPress={onRetry}
            style={[
              styles.retryButton,
              { borderColor: isDark ? colors.warningTextDark : colors.warningText },
            ]}
          >
            <Text
              style={[
                styles.retryButtonText,
                { color: isDark ? colors.warningTextDark : colors.warningText },
              ]}
            >
              Retry
            </Text>
          </TouchableOpacity>
        )}
      </View>
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

  // Initialize DCAppAttest attestation (Story 2.3)
  // This hook runs after key generation completes successfully
  const {
    attestationStatus,
    isAttesting,
    isAttestationFailed,
    attestationError,
    retryAttempt,
    initiateAttestation,
  } = useDeviceAttestation();

  // Show loading screen during hydration and capability detection
  if (!hasHydrated || isLoading) {
    return (
      <SafeAreaProvider>
        <StatusBar style="auto" />
        <LoadingScreen message="Checking device capabilities..." />
      </SafeAreaProvider>
    );
  }

  // DISABLED: Show blocking screen for unsupported devices
  // Temporarily disabled for development/testing in Expo Go
  // if (!capabilities?.isSupported) {
  //   return (
  //     <SafeAreaProvider>
  //       <StatusBar style="auto" />
  //       <UnsupportedDeviceScreen reason={capabilities?.unsupportedReason} />
  //     </SafeAreaProvider>
  //   );
  // }

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

  // Show loading screen during attestation (Story 2.3)
  // Display different messages based on attestation phase
  if (isAttesting) {
    const message =
      attestationStatus === 'fetching_challenge'
        ? 'Preparing security verification...'
        : 'Verifying device security...';
    return (
      <SafeAreaProvider>
        <StatusBar style="auto" />
        <LoadingScreen message={message} />
      </SafeAreaProvider>
    );
  }

  // Determine which warning to show (key generation or attestation failure)
  // DISABLED: Temporarily hide key generation warnings
  const showKeyWarning = false; // isKeyFailed && keyGenerationError;
  const showAttestationWarning = isAttestationFailed && attestationError;
  // For attestation failures, show retry button if under max retries (3)
  const showRetryButton = showAttestationWarning && retryAttempt < 3;

  // Supported device - render normal app navigation
  // If key generation or attestation failed, show warning banner but don't block app
  return (
    <SafeAreaProvider>
      <StatusBar style="auto" />
      {/* DISABLED: Key generation warning temporarily hidden */}
      {/* {showKeyWarning && (
        <AttestationWarningBanner message={keyGenerationError} />
      )} */}
      {showAttestationWarning && !showKeyWarning && (
        <AttestationWarningBanner
          message={attestationError}
          onRetry={initiateAttestation}
          showRetry={!!showRetryButton}
        />
      )}
      <Stack>
        <Stack.Screen name="index" options={{ headerShown: false }} />
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen
          name="preview"
          options={{
            title: 'Preview',
            headerShown: true,
            presentation: 'fullScreenModal',
            headerStyle: {
              backgroundColor: '#000000', // Black background
              height: 120, // Same height as tabs header
            },
            headerTitleContainerStyle: {
              paddingHorizontal: 20, // Horizontal padding for logo
              paddingBottom: 8, // Bottom padding (same as tabs)
            },
            headerTintColor: '#FFFFFF', // White text and icons
            headerTitleStyle: {
              color: '#FFFFFF', // White title text
              fontWeight: '600',
              fontSize: 0, // Hide default title since we use custom logo
            },
            headerTitle: () => <LogoHeader />,
          }}
        />
        <Stack.Screen
          name="result"
          options={{
            title: 'Upload Complete',
            headerShown: true,
            presentation: 'fullScreenModal',
            headerBackVisible: false,
            headerStyle: {
              backgroundColor: '#000000', // Black background
              height: 120, // Same height as tabs header
            },
            headerTitleContainerStyle: {
              paddingHorizontal: 20, // Horizontal padding for logo
              paddingBottom: 8, // Bottom padding (same as tabs)
            },
            headerTintColor: '#FFFFFF', // White text and icons
            headerTitleStyle: {
              color: '#FFFFFF', // White title text
              fontWeight: '600',
              fontSize: 0, // Hide default title since we use custom logo
            },
            headerTitle: () => <LogoHeader />,
          }}
        />
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
  warningContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  warningText: {
    fontSize: 14,
    textAlign: 'center',
    fontWeight: '500',
    flex: 1,
  },
  retryButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 4,
    borderWidth: 1,
  },
  retryButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
});
