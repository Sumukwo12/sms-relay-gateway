import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Alert,
} from 'react-native';
import { relayManager } from '../relayManager';
import { clearLogs } from '../storage';
import { LogEntry } from '../types';

interface LogScreenProps {
  isDark: boolean;
}

export const LogScreen: React.FC<LogScreenProps> = ({ isDark }) => {
  const [logs, setLogs] = useState<LogEntry[]>(relayManager.getLogs());

  useEffect(() => {
    const unsubscribe = relayManager.subscribe(() => {
      setLogs(relayManager.getLogs());
    });
    return () => unsubscribe();
  }, []);

  const handleClearLogs = () => {
    Alert.alert(
      'Clear Logs',
      'Are you sure you want to delete all stored message logs?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear',
          style: 'destructive',
          onPress: async () => {
            await clearLogs();
            await relayManager.initialize();
          },
        },
      ]
    );
  };

  const formatTimestamp = (timestamp: number) => {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  };

  const getStatusBadge = (status: LogEntry['status']) => {
    switch (status) {
      case 'delivered':
        return { text: 'DELIVERED', color: '#10B981', bg: '#064E3B25' };
      case 'sent':
        return { text: 'SENT', color: '#3B82F6', bg: '#1D4ED825' };
      case 'failed':
        return { text: 'FAILED', color: '#EF4444', bg: '#991B1B25' };
    }
  };

  const themeStyles = isDark ? darkStyles : lightStyles;

  const renderLogItem = ({ item }: { item: LogEntry }) => {
    const badge = getStatusBadge(item.status);

    return (
      <View style={[styles.logCard, themeStyles.card]}>
        <View style={styles.logHeader}>
          <Text style={[styles.phoneText, themeStyles.text]}>{item.maskedRecipient}</Text>
          <View style={[styles.statusBadge, { backgroundColor: badge.bg }]}>
            <Text style={[styles.statusText, { color: badge.color }]}>{badge.text}</Text>
          </View>
        </View>

        <View style={styles.logFooter}>
          <Text style={[styles.timeText, themeStyles.subText]}>
            {formatTimestamp(item.timestamp)}
          </Text>
          <Text style={[styles.idText, themeStyles.subText]}>ID: {item.id}</Text>
        </View>

        {item.error && (
          <View style={styles.errorBox}>
            <Text style={styles.errorText}>{item.error}</Text>
          </View>
        )}
      </View>
    );
  };

  return (
    <View style={[styles.container, themeStyles.container]}>
      <View style={[styles.header, themeStyles.headerBorder]}>
        <Text style={[styles.title, themeStyles.text]}>Message Logs ({logs.length})</Text>
        {logs.length > 0 && (
          <TouchableOpacity onPress={handleClearLogs} style={styles.clearButton}>
            <Text style={styles.clearButtonText}>Clear</Text>
          </TouchableOpacity>
        )}
      </View>

      {logs.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Text style={[styles.emptyTitle, themeStyles.text]}>No Messages Logged</Text>
          <Text style={[styles.emptySubtitle, themeStyles.subText]}>
            Outgoing SMS verification requests will be logged here. For security, OTP bodies are never stored.
          </Text>
        </View>
      ) : (
        <FlatList
          data={logs}
          keyExtractor={(item) => item.id}
          renderItem={renderLogItem}
          contentContainerStyle={styles.listContent}
        />
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
  },
  clearButton: {
    paddingVertical: 4,
    paddingHorizontal: 10,
    borderRadius: 6,
    backgroundColor: '#EF444420',
  },
  clearButtonText: {
    color: '#EF4444',
    fontSize: 13,
    fontWeight: '600',
  },
  listContent: {
    padding: 16,
    paddingBottom: 40,
  },
  logCard: {
    borderRadius: 12,
    padding: 14,
    marginBottom: 10,
    borderWidth: 1,
  },
  logHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  phoneText: {
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  statusText: {
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  logFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  timeText: {
    fontSize: 12,
  },
  idText: {
    fontSize: 11,
    fontFamily: 'monospace',
  },
  errorBox: {
    marginTop: 8,
    padding: 8,
    borderRadius: 6,
    backgroundColor: '#991B1B15',
  },
  errorText: {
    color: '#EF4444',
    fontSize: 12,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 8,
  },
  emptySubtitle: {
    fontSize: 13,
    textAlign: 'center',
    lineHeight: 18,
  },
});

const darkStyles = StyleSheet.create({
  container: {
    backgroundColor: '#0F172A',
  },
  headerBorder: {
    borderBottomColor: '#1E293B',
  },
  card: {
    backgroundColor: '#1E293B',
    borderColor: '#334155',
  },
  text: {
    color: '#F8FAFC',
  },
  subText: {
    color: '#94A3B8',
  },
});

const lightStyles = StyleSheet.create({
  container: {
    backgroundColor: '#F8FAFC',
  },
  headerBorder: {
    borderBottomColor: '#E2E8F0',
  },
  card: {
    backgroundColor: '#FFFFFF',
    borderColor: '#E2E8F0',
  },
  text: {
    color: '#0F172A',
  },
  subText: {
    color: '#64748B',
  },
});
