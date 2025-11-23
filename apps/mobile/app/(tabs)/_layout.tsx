import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useColorScheme } from 'react-native';
import { colors } from '../../constants/colors';
import { LogoHeader } from '../../components/Logo';

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
          borderTopWidth: 0, // Remove white line
          elevation: 0, // Remove shadow on Android
          shadowOpacity: 0, // Remove shadow on iOS
          height: 90, // Slightly reduced height
          paddingBottom: 30, // Reduced bottom padding to move icons up
          paddingTop: 8, // Reduced top padding
          alignItems: 'center', // Center icons vertically
          justifyContent: 'center', // Center icons horizontally
        },
        tabBarItemStyle: {
          paddingVertical: 0, // Remove vertical padding to center better
          alignItems: 'center', // Center icon in item
          justifyContent: 'center', // Center icon in item
        },
        tabBarIconStyle: {
          marginTop: 0, // Remove margin to center properly
          alignSelf: 'center', // Center icon
        },
        headerStyle: {
          backgroundColor: isDark ? colors.backgroundDark : colors.background,
          borderBottomWidth: 0, // Remove bottom border
          elevation: 0, // Remove shadow on Android
          shadowOpacity: 0, // Remove shadow on iOS
          height: 120, // Larger Apple-style header height
        },
        headerTitleContainerStyle: {
          paddingHorizontal: 20, // Horizontal padding for logo
          paddingBottom: 8, // Bottom padding
        },
        headerTintColor: isDark ? colors.textDark : colors.text,
        headerTitleStyle: {
          fontWeight: '600',
          fontSize: 0, // Hide default title since we use custom logo
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
          tabBarIcon: () => (
            <Ionicons name="camera-outline" size={32} color="#FFFFFF" />
          ),
        }}
      />
      <Tabs.Screen
        name="history"
        options={{
          title: 'History',
          tabBarLabel: '',
          tabBarIcon: () => (
            <Ionicons name="time-outline" size={32} color="#FFFFFF" />
          ),
        }}
      />
    </Tabs>
  );
}
