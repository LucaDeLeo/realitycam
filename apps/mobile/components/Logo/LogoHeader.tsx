/**
 * LogoHeader Component
 *
 * Reusable logo component with gradient square and "rial." text.
 * Used across all screens in the app.
 */

import { View, Text, StyleSheet } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

interface LogoHeaderProps {
  /** Size of the logo square (default: 32) */
  size?: number;
  /** Font size for the text (default: 18) */
  fontSize?: number;
  /** Additional styles for container */
  style?: object;
}

/**
 * Logo component with gradient square and "rial." text
 */
export function LogoHeader({ size = 32, fontSize = 18, style }: LogoHeaderProps) {
  return (
    <View style={[styles.logoContainer, style]}>
      {/* Gradient square logo - pink (top-left) -> white (center) -> light blue (bottom-right) */}
      <View style={[styles.logoSquare, { width: size, height: size }]}>
        <LinearGradient
          colors={['#FF6B9D', '#FFFFFF', '#87CEEB']}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={styles.gradient}
        />
      </View>
      {/* "rial." text in white */}
      <Text style={[styles.logoText, { fontSize }]}>rial.</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  logoContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  logoSquare: {
    borderRadius: 8, // Rounded corners (squircle-like)
    overflow: 'hidden',
  },
  gradient: {
    width: '100%',
    height: '100%',
  },
  logoText: {
    color: '#FFFFFF', // White text
    fontWeight: '600',
    letterSpacing: -0.5,
    fontFamily: 'System', // Will use system font
  },
});

