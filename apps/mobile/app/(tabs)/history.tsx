import { View, Text, StyleSheet, useColorScheme } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../../constants/colors';

export default function HistoryScreen() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  return (
    <View
      style={[
        styles.container,
        { backgroundColor: isDark ? colors.backgroundDark : colors.background },
      ]}
    >
      <Ionicons
        name="time-outline"
        size={80}
        color={colors.primary}
        style={styles.icon}
      />
      <Text style={[styles.title, { color: isDark ? colors.textDark : colors.text }]}>
        History
      </Text>
      <Text
        style={[
          styles.subtitle,
          { color: isDark ? colors.tabBarInactive : colors.textSecondary },
        ]}
      >
        View your verified capture history
      </Text>
      <Text
        style={[
          styles.hint,
          { color: isDark ? colors.tabBarInactive : colors.textSecondary },
        ]}
      >
        History functionality coming soon
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  icon: {
    marginBottom: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  subtitle: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 8,
    lineHeight: 22,
  },
  hint: {
    fontSize: 14,
    textAlign: 'center',
    fontStyle: 'italic',
  },
});
