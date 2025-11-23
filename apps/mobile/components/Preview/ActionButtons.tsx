/**
 * ActionButtons Component
 *
 * Upload and Discard buttons for the capture preview screen.
 * Handles confirmation dialogs and disabled states during actions.
 *
 * @see Story 3.6 - Capture Preview Screen
 */

import { View, Text, StyleSheet, TouchableOpacity, Alert, useColorScheme } from 'react-native';
import { colors } from '../../constants/colors';

interface ActionButtonsProps {
  /** Called when user confirms discard */
  onDiscard: () => void;
  /** Called when user taps upload (placeholder for Epic 4) */
  onUpload: () => void;
  /** Whether buttons should be disabled */
  disabled?: boolean;
  /** Additional styles for container */
  style?: object;
}

/**
 * Action buttons component for preview screen
 */
export function ActionButtons({
  onDiscard,
  onUpload,
  disabled = false,
  style,
}: ActionButtonsProps) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  /**
   * Handle discard button press with confirmation
   */
  const handleDiscardPress = () => {
    Alert.alert(
      'Discard Capture',
      'Are you sure you want to discard this capture? This cannot be undone.',
      [
        {
          text: 'Cancel',
          style: 'cancel',
        },
        {
          text: 'Discard',
          style: 'destructive',
          onPress: onDiscard,
        },
      ],
      { cancelable: true }
    );
  };

  /**
   * Handle upload button press (placeholder for Epic 4)
   */
  const handleUploadPress = () => {
    // Placeholder - Epic 4 will implement actual upload
    Alert.alert(
      'Coming Soon',
      'Upload functionality will be implemented in Epic 4.',
      [{ text: 'OK' }]
    );
    onUpload();
  };

  return (
    <View style={[styles.container, style]}>
      {/* Discard Button */}
      <TouchableOpacity
        style={[
          styles.button,
          styles.discardButton,
          disabled && styles.buttonDisabled,
        ]}
        onPress={handleDiscardPress}
        disabled={disabled}
        activeOpacity={0.7}
      >
        <Text style={[styles.buttonText, styles.discardButtonText]}>Discard</Text>
      </TouchableOpacity>

      {/* Upload Button */}
      <TouchableOpacity
        style={[
          styles.button,
          styles.uploadButton,
          disabled && styles.buttonDisabled,
        ]}
        onPress={handleUploadPress}
        disabled={disabled}
        activeOpacity={0.7}
      >
        <Text style={[styles.buttonText, styles.uploadButtonText]}>Upload</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    padding: 16,
    gap: 12,
  },
  button: {
    flex: 1,
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    fontSize: 17,
    fontWeight: '600',
  },
  discardButton: {
    backgroundColor: 'transparent', // No background
  },
  discardButtonText: {
    color: '#FFFFFF', // White text
  },
  uploadButton: {
    backgroundColor: '#FFFFFF', // White background
  },
  uploadButtonText: {
    color: '#000000', // Black text
  },
});
