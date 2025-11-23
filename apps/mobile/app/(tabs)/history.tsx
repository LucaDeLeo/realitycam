import { useState, useEffect } from 'react';
import { View, Text, StyleSheet, useColorScheme, ScrollView, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../../constants/colors';
import { getStoredCaptures } from '../../services/captureIndex';
import type { CaptureIndexEntry } from '@realitycam/shared';

export default function HistoryScreen() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  const [captures, setCaptures] = useState<CaptureIndexEntry[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    loadHistory();
  }, []);

  const loadHistory = async () => {
    try {
      setIsLoading(true);
      const stored = await getStoredCaptures();
      // Sort by queuedAt (newest first)
      const sorted = [...stored].sort(
        (a, b) => new Date(b.queuedAt).getTime() - new Date(a.queuedAt).getTime()
      );
      setCaptures(sorted);
    } catch (error) {
      console.error('[HistoryScreen] Failed to load history:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed':
        return '#34C759';
      case 'pending':
        return '#FF9500';
      case 'uploading':
        return '#007AFF';
      case 'failed':
      case 'permanently_failed':
        return '#FF3B30';
      default:
        return colors.textSecondary;
    }
  };

  if (isLoading) {
    return (
      <SafeAreaView
        style={[
          styles.container,
          { backgroundColor: isDark ? colors.backgroundDark : colors.background },
        ]}
      >
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text
            style={[
              styles.loadingText,
              { color: isDark ? colors.textDark : colors.text },
            ]}
          >
            Loading history...
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  if (captures.length === 0) {
    return (
      <SafeAreaView
        style={[
          styles.container,
          { backgroundColor: isDark ? colors.backgroundDark : colors.background },
        ]}
      >
        <View style={styles.emptyContainer}>
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
            No captures yet
          </Text>
          <Text
            style={[
              styles.hint,
              { color: isDark ? colors.tabBarInactive : colors.textSecondary },
            ]}
          >
            Your verified captures will appear here
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView
      style={[
        styles.container,
        { backgroundColor: isDark ? colors.backgroundDark : colors.background },
      ]}
    >
      <View style={styles.header}>
        <Text style={[styles.headerTitle, { color: isDark ? colors.textDark : colors.text }]}>
          History
        </Text>
        <Text
          style={[
            styles.headerSubtitle,
            { color: isDark ? colors.tabBarInactive : colors.textSecondary },
          ]}
        >
          {captures.length} {captures.length === 1 ? 'capture' : 'captures'}
        </Text>
      </View>
      <ScrollView style={styles.list} showsVerticalScrollIndicator={false}>
        {captures.map((capture) => (
          <View
            key={capture.captureId}
            style={[
              styles.captureItem,
              {
                backgroundColor: isDark
                  ? 'rgba(255, 255, 255, 0.05)'
                  : 'rgba(0, 0, 0, 0.02)',
              },
            ]}
          >
            <View style={styles.captureHeader}>
              <View style={styles.captureInfo}>
                <Text
                  style={[
                    styles.captureId,
                    { color: isDark ? colors.textDark : colors.text },
                  ]}
                  numberOfLines={1}
                >
                  {capture.captureId.substring(0, 8)}...
                </Text>
                <Text
                  style={[
                    styles.captureDate,
                    { color: isDark ? colors.tabBarInactive : colors.textSecondary },
                  ]}
                >
                  {formatDate(capture.queuedAt)}
                </Text>
              </View>
              <View
                style={[
                  styles.statusBadge,
                  { backgroundColor: getStatusColor(capture.status) + '20' },
                ]}
              >
                <Text
                  style={[
                    styles.statusText,
                    { color: getStatusColor(capture.status) },
                  ]}
                >
                  {capture.status}
                </Text>
              </View>
            </View>
            <View style={styles.captureFooter}>
              <Text
                style={[
                  styles.captureSize,
                  { color: isDark ? colors.tabBarInactive : colors.textSecondary },
                ]}
              >
                {(capture.totalSize / 1024 / 1024).toFixed(2)} MB
              </Text>
            </View>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    marginTop: 16,
    fontSize: 16,
  },
  emptyContainer: {
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
  header: {
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(0, 0, 0, 0.1)',
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  headerSubtitle: {
    fontSize: 14,
  },
  list: {
    flex: 1,
  },
  captureItem: {
    marginHorizontal: 20,
    marginTop: 12,
    padding: 16,
    borderRadius: 12,
  },
  captureHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 8,
  },
  captureInfo: {
    flex: 1,
    marginRight: 12,
  },
  captureId: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 4,
  },
  captureDate: {
    fontSize: 13,
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
  },
  statusText: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  captureFooter: {
    marginTop: 8,
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: 'rgba(0, 0, 0, 0.05)',
  },
  captureSize: {
    fontSize: 12,
  },
});
