/**
 * DepthToggle Component
 *
 * Toggle button for depth overlay visibility.
 * Includes haptic feedback on toggle action.
 *
 * @see Story 3.1 - Camera View with LiDAR Depth Overlay
 */

import React from 'react';
import {
  TouchableOpacity,
  StyleSheet,
  useColorScheme,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { colors } from '../../constants/colors';

interface DepthToggleProps {
  /** Whether depth overlay is currently enabled */
  enabled: boolean;
  /** Callback when toggle is pressed */
  onToggle: () => void;
  /** Whether the toggle should be disabled */
  disabled?: boolean;
}

/**
 * Toggle button for depth overlay visibility
 *
 * @example
 * ```tsx
 * const [overlayEnabled, setOverlayEnabled] = useState(true);
 *
 * <DepthToggle
 *   enabled={overlayEnabled}
 *   onToggle={() => setOverlayEnabled(!overlayEnabled)}
 * />
 * ```
 */
export function DepthToggle({ enabled, onToggle, disabled = false }: DepthToggleProps) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const handlePress = async () => {
    if (disabled) return;

    // Haptic feedback
    try {
      await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    } catch {
      // Haptics may not be available on simulator
    }

    onToggle();
  };

  return (
    <TouchableOpacity
      style={[
        styles.button,
        {
          backgroundColor: isDark
            ? 'rgba(255, 255, 255, 0.2)'
            : 'rgba(0, 0, 0, 0.3)',
        },
        enabled && styles.buttonActive,
        disabled && styles.buttonDisabled,
      ]}
      onPress={handlePress}
      disabled={disabled}
      activeOpacity={0.7}
      accessibilityLabel={enabled ? 'Hide depth overlay' : 'Show depth overlay'}
      accessibilityRole="button"
      accessibilityState={{ disabled, selected: enabled }}
    >
      <Ionicons
        name={enabled ? 'eye' : 'eye-off'}
        size={24}
        color={disabled ? colors.systemGray : '#FFFFFF'}
      />
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  button: {
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
  },
  buttonActive: {
    backgroundColor: colors.primary,
  },
  buttonDisabled: {
    opacity: 0.5,
  },
});
