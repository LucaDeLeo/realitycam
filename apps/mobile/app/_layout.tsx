/**
 * Root Layout
 *
 * Entry point for the app navigation. Performs device capability check
 * before allowing access to main app features.
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
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { useDeviceCapabilities } from '../hooks/useDeviceCapabilities';
import { UnsupportedDeviceScreen } from '../components/Device/UnsupportedDeviceScreen';
import { colors } from '../constants/colors';

/**
 * Loading screen shown during capability detection
 */
function LoadingScreen() {
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
        Checking device capabilities...
      </Text>
    </View>
  );
}

export default function RootLayout() {
  const { capabilities, isLoading, hasHydrated } = useDeviceCapabilities();

  // Show loading screen during hydration and capability detection
  if (!hasHydrated || isLoading) {
    return (
      <SafeAreaProvider>
        <StatusBar style="auto" />
        <LoadingScreen />
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

  // Supported device - render normal app navigation
  return (
    <SafeAreaProvider>
      <StatusBar style="auto" />
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
});
