/**
 * UnsupportedDeviceScreen Component
 *
 * Blocking screen displayed when device does not meet RealityCam requirements.
 * Supports dark mode and displays helpful information about supported devices.
 */

import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  useColorScheme,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { colors } from '../../constants/colors';
import { getSupportedModels } from '../../utils/lidarDetection';

interface UnsupportedDeviceScreenProps {
  /** Specific reason why the device is not supported */
  reason?: string;
}

/**
 * Full-screen blocking component for unsupported devices
 *
 * Displays:
 * - Title explaining requirement
 * - Explanation of why LiDAR is needed
 * - List of supported iPhone models
 * - Specific unsupported reason if available
 */
export function UnsupportedDeviceScreen({
  reason,
}: UnsupportedDeviceScreenProps) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const supportedModels = getSupportedModels();

  return (
    <SafeAreaView
      style={[
        styles.container,
        { backgroundColor: isDark ? colors.backgroundDark : colors.background },
      ]}
    >
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        {/* Icon placeholder - using text for MVP */}
        <View style={styles.iconContainer}>
          <Text style={styles.iconText}>!</Text>
        </View>

        {/* Main title */}
        <Text
          style={[
            styles.title,
            { color: isDark ? colors.textDark : colors.text },
          ]}
        >
          RealityCam requires iPhone Pro with LiDAR sensor
        </Text>

        {/* Explanation */}
        <Text
          style={[
            styles.explanation,
            { color: isDark ? colors.textDark : colors.text },
          ]}
        >
          LiDAR enables real 3D scene verification that proves your photos are
          authentic. This hardware-level depth sensing cannot be faked or
          manipulated by software.
        </Text>

        {/* Supported devices section */}
        <View style={styles.supportedSection}>
          <Text
            style={[
              styles.supportedTitle,
              { color: isDark ? colors.textDark : colors.text },
            ]}
          >
            Supported Devices
          </Text>
          {supportedModels.map((model, index) => (
            <View key={index} style={styles.modelRow}>
              <Text style={styles.bullet}>{'   \u2022   '}</Text>
              <Text
                style={[
                  styles.modelText,
                  { color: isDark ? colors.textDark : colors.text },
                ]}
              >
                {model}
              </Text>
            </View>
          ))}
        </View>

        {/* Specific reason if provided */}
        {reason && (
          <View
            style={[
              styles.reasonContainer,
              {
                backgroundColor: isDark
                  ? 'rgba(255,59,48,0.15)'
                  : 'rgba(255,59,48,0.1)',
              },
            ]}
          >
            <Text style={styles.reasonLabel}>Your device:</Text>
            <Text style={styles.reasonText}>{reason}</Text>
          </View>
        )}

        {/* Footer message */}
        <Text
          style={[
            styles.footer,
            { color: colors.textSecondary },
          ]}
        >
          RealityCam is designed to provide cryptographic proof of photo
          authenticity using specialized hardware available only in iPhone Pro
          models.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flexGrow: 1,
    paddingHorizontal: 24,
    paddingVertical: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconContainer: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(255,59,48,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
  },
  iconText: {
    fontSize: 40,
    fontWeight: '700',
    color: '#FF3B30', // iOS system red
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 16,
    lineHeight: 32,
  },
  explanation: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 32,
    lineHeight: 24,
    opacity: 0.9,
  },
  supportedSection: {
    alignSelf: 'stretch',
    marginBottom: 32,
  },
  supportedTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
    textAlign: 'center',
  },
  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 4,
    justifyContent: 'center',
  },
  bullet: {
    color: colors.primary,
    fontSize: 16,
  },
  modelText: {
    fontSize: 15,
    opacity: 0.8,
  },
  reasonContainer: {
    alignSelf: 'stretch',
    padding: 16,
    borderRadius: 12,
    marginBottom: 24,
  },
  reasonLabel: {
    fontSize: 13,
    color: '#FF3B30',
    fontWeight: '500',
    marginBottom: 4,
  },
  reasonText: {
    fontSize: 15,
    color: '#FF3B30',
    fontWeight: '600',
  },
  footer: {
    fontSize: 13,
    textAlign: 'center',
    lineHeight: 20,
  },
});
