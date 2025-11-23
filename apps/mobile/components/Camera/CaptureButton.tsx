/**
 * CaptureButton Component
 *
 * iOS-style shutter button with animations and haptic feedback.
 * Features scale animation on press and disabled state during capture.
 *
 * @see Story 3.2 - Photo Capture with Depth Map
 */

import React, { useRef, useCallback } from 'react';
import {
  TouchableWithoutFeedback,
  View,
  Animated,
  StyleSheet,
} from 'react-native';
import * as Haptics from 'expo-haptics';

interface CaptureButtonProps {
  /** Callback when capture button is pressed */
  onCapture: () => void;
  /** Whether the button should be disabled (e.g., not ready) */
  disabled?: boolean;
  /** Whether capture is currently in progress */
  isCapturing?: boolean;
}

/**
 * iOS-style shutter button for photo capture
 *
 * Features:
 * - 70px circular button with white ring border
 * - Scale animation (0.9x) on press
 * - Haptic feedback (Medium impact) on capture
 * - Disabled state with reduced opacity
 * - Prevents interaction during capture
 *
 * @example
 * ```tsx
 * <CaptureButton
 *   onCapture={() => console.log('Capture!')}
 *   isCapturing={false}
 *   disabled={!isReady}
 * />
 * ```
 */
export function CaptureButton({
  onCapture,
  disabled = false,
  isCapturing = false,
}: CaptureButtonProps) {
  // Animation value for scale effect
  const scaleAnim = useRef(new Animated.Value(1)).current;

  // Whether button is effectively disabled
  const isDisabled = disabled || isCapturing;

  /**
   * Handle press in - scale down
   */
  const handlePressIn = useCallback(() => {
    if (isDisabled) return;

    Animated.spring(scaleAnim, {
      toValue: 0.9,
      useNativeDriver: true,
      friction: 5,
      tension: 100,
    }).start();
  }, [isDisabled, scaleAnim]);

  /**
   * Handle press out - scale back to normal
   */
  const handlePressOut = useCallback(() => {
    Animated.spring(scaleAnim, {
      toValue: 1,
      useNativeDriver: true,
      friction: 5,
      tension: 100,
    }).start();
  }, [scaleAnim]);

  /**
   * Handle press - trigger capture with haptic feedback
   */
  const handlePress = useCallback(async () => {
    if (isDisabled) return;

    // Haptic feedback
    try {
      await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    } catch {
      // Haptics not available on simulator - continue silently
    }

    onCapture();
  }, [isDisabled, onCapture]);

  return (
    <TouchableWithoutFeedback
      onPressIn={handlePressIn}
      onPressOut={handlePressOut}
      onPress={handlePress}
      disabled={isDisabled}
      accessibilityLabel="Capture photo"
      accessibilityRole="button"
      accessibilityState={{ disabled: isDisabled }}
    >
      <Animated.View
        style={[
          styles.button,
          { transform: [{ scale: scaleAnim }] },
          isDisabled && styles.buttonDisabled,
        ]}
      >
        <View
          style={[
            styles.innerCircle,
            isCapturing && styles.innerCircleCapturing,
          ]}
        />
      </Animated.View>
    </TouchableWithoutFeedback>
  );
}

const styles = StyleSheet.create({
  button: {
    width: 70,
    height: 70,
    borderRadius: 35,
    borderWidth: 4,
    borderColor: '#FFFFFF',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    // Shadow for better visibility on camera preview
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 5,
  },
  innerCircle: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#FFFFFF',
  },
  innerCircleCapturing: {
    backgroundColor: '#CCCCCC',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
});
