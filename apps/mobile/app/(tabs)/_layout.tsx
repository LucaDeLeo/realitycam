import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useColorScheme, View, Text, StyleSheet } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { colors } from '../../constants/colors';

// Logo component with gradient square and "rial." text
function LogoHeader() {
  return (
    <View style={styles.logoContainer}>
      {/* Gradient square logo - pink (top-left) -> white (center) -> light blue (bottom-right) */}
      <View style={styles.logoSquare}>
        <LinearGradient
          colors={['#FF6B9D', '#FFFFFF', '#87CEEB']}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={styles.gradient}
        />
      </View>
      {/* "rial." text in white */}
      <Text style={styles.logoText}>rial.</Text>
    </View>
  );
}

export default function TabLayout() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: colors.tabBarActive,
        tabBarInactiveTintColor: colors.tabBarInactive,
        tabBarStyle: {
          backgroundColor: isDark ? colors.backgroundDark : colors.background,
        },
        headerStyle: {
          backgroundColor: isDark ? colors.backgroundDark : colors.background,
        },
        headerTintColor: isDark ? colors.textDark : colors.text,
        headerTitleStyle: {
          fontWeight: '600',
        },
        headerShown: true,
        headerTitle: () => <LogoHeader />,
      }}
    >
      <Tabs.Screen
        name="capture"
        options={{
          title: 'Capture',
          tabBarLabel: '',
          tabBarIcon: ({ size }) => (
            <Ionicons name="camera-outline" size={size} color="#FFFFFF" />
          ),
        }}
      />
      <Tabs.Screen
        name="history"
        options={{
          title: 'History',
          tabBarLabel: '',
          tabBarIcon: ({ size }) => (
            <Ionicons name="time-outline" size={size} color="#FFFFFF" />
          ),
        }}
      />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  logoContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  logoSquare: {
    width: 32,
    height: 32,
    borderRadius: 8, // Rounded corners (squircle-like)
    overflow: 'hidden',
  },
  gradient: {
    width: '100%',
    height: '100%',
  },
  logoText: {
    color: '#FFFFFF', // White text
    fontSize: 18,
    fontWeight: '600',
    letterSpacing: -0.5,
    // Custom font styling to match "rial." appearance
    fontFamily: 'System', // Will use system font
  },
});
