import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useColorScheme } from 'react-native';
import { colors } from '../../constants/colors';

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
      }}
    >
      <Tabs.Screen
        name="capture"
        options={{
          title: 'Capture',
          tabBarLabel: 'Capture',
          tabBarIcon: ({ color, size }) => (
            <Ionicons name="camera-outline" size={size} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="history"
        options={{
          title: 'History',
          tabBarLabel: 'History',
          tabBarIcon: ({ color, size }) => (
            <Ionicons name="time-outline" size={size} color={color} />
          ),
        }}
      />
    </Tabs>
  );
}
