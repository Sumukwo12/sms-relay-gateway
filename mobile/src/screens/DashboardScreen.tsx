import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  Switch,
  ActivityIndicator,
  ScrollView,
  Alert,
} from 'react-native';
import { relayManager } from '../relayManager';
import {
  checkBatteryOptimization,
  requestBatteryOptimizationExemption,
} from '../foregroundService';
import { ConnectionStatus, RelayStats } from '../types';

interface DashboardScreenProps {
  isDark: boolean;
}

export const DashboardScreen: React.FC<DashboardScreenProps> = ({ isDark }) => {
  const [status, setStatus] = useState<ConnectionStatus>(relayManager.getStatus());
  const [isRunning, setIsRunning] = useState<boolean>(relayManager.isRunning());
  const [stats, setStats] = useState<RelayStats>(relayManager.getStats());
  const [batteryOptimizationActive, setBatteryOptimizationActive] = useState(false);

  // Test SMS fields
  const [testPhone, setTestPhone] = useState('');
  const [testMessage, setTestMessage] = useState('SMS Relay verification test');
  const [isSendingTest, setIsSendingTest] = useState(false);

  useEffect(() => {
    const unsubscribe = relayManager.subscribe(() => {
      setStatus(relayManager.getStatus());
      setIsRunning(relayManager.isRunning());
      setStats(relayManager.getStats());
    });

    checkBatteryOptimization().then((active) => {
      setBatteryOptimizationActive(active);
    });

    return () => unsubscribe();
  }, []);

  const handleToggleService = async (value: boolean) => {
    if (value) {
      const settings = relayManager.getSettings();
      if (!settings.serverUrl || !settings.token) {
        Alert.alert(
          'Setup Required',
          'Please configure the Server URL and Token in the Setup tab first.'
        );
        return;
      }
      await relayManager.startService();
    } else {
      await relayManager.stopService();
    }
  };

  const handleSendTestSms = async () => {
    if (!testPhone.trim()) {
      Alert.alert('Missing Number', 'Please enter a recipient phone number in E.164 format (+254...).');
      return;
    }

    setIsSendingTest(true);
    try {
      const res = await relayManager.sendManualTestSms(testPhone.trim(), testMessage.trim());
      if (res.status === 'sent') {
        Alert.alert('Success', `SMS sent successfully to ${testPhone}!`);
      } else {
        Alert.alert('Send Failed', res.error || 'Failed to dispatch SMS through SIM.');
      }
    } catch (err: any) {
      Alert.alert('Error', err?.message || 'Error executing SMS send');
    } finally {
      setIsSendingTest(false);
    }
  };

  const getStatusBadge = () => {
    switch (status) {
      case 'connected':
        return {
          title: 'Connected',
          description: 'Listening for outgoing verification requests',
          bgColor: '#064E3B',
          borderColor: '#059669',
          textColor: '#34D399',
          dotColor: '#10B981',
        };
      case 'connecting':
        return {
          title: 'Connecting…',
          description: 'Establishing WebSocket connection to backend',
          bgColor: '#78350F',
          borderColor: '#D97706',
          textColor: '#FBBF24',
          dotColor: '#F59E0B',
        };
      case 'invalid_token':
        return {
          title: 'Invalid Token',
          description: 'Server rejected authentication token',
          bgColor: '#7F1D1D',
          borderColor: '#DC2626',
          textColor: '#FCA5A5',
          dotColor: '#EF4444',
        };
      default:
        return {
          title: 'Disconnected',
          description: isRunning ? 'Reconnecting to backend…' : 'Service is currently paused',
          bgColor: isDark ? '#1E293B' : '#F1F5F9',
          borderColor: isDark ? '#334155' : '#CBD5E1',
          textColor: isDark ? '#94A3B8' : '#64748B',
          dotColor: '#94A3B8',
        };
    }
  };

  const badge = getStatusBadge();

  const themeStyles = isDark ? darkStyles : lightStyles;

  return (
    <ScrollView style={[styles.container, themeStyles.container]} contentContainerStyle={styles.content}>
      {/* Battery Optimization Notice */}
      {batteryOptimizationActive && (
        <TouchableOpacity
          style={[styles.banner, themeStyles.batteryBanner]}
          activeOpacity={0.8}
          onPress={() => requestBatteryOptimizationExemption()}
        >
          <Text style={styles.batteryBannerTitle}>⚡ Battery Optimization Active</Text>
          <Text style={styles.batteryBannerText}>
            Android may terminate the relay when the screen is turned off. Tap here to exempt SMS Relay.
          </Text>
        </TouchableOpacity>
      )}

      {/* Connection Status Card */}
      <View style={[styles.card, themeStyles.card, { borderColor: badge.borderColor, borderWidth: 1.5 }]}>
        <View style={styles.statusHeader}>
          <View style={styles.statusTitleRow}>
            <View style={[styles.statusDot, { backgroundColor: badge.dotColor }]} />
            <Text style={[styles.statusTitle, { color: badge.textColor }]}>{badge.title}</Text>
          </View>
          <Switch
            value={isRunning}
            onValueChange={handleToggleService}
            thumbColor={isRunning ? '#10B981' : '#94A3B8'}
            trackColor={{ false: '#475569', true: '#065F46' }}
          />
        </View>
        <Text style={[styles.statusDescription, themeStyles.subText]}>{badge.description}</Text>
      </View>

      {/* Counters Grid */}
      <View style={styles.statsRow}>
        <View style={[styles.statCard, themeStyles.card]}>
          <Text style={[styles.statValue, { color: '#10B981' }]}>{stats.sentToday}</Text>
          <Text style={[styles.statLabel, themeStyles.subText]}>Sent Today</Text>
        </View>
        <View style={[styles.statCard, themeStyles.card]}>
          <Text style={[styles.statValue, { color: '#EF4444' }]}>{stats.failedToday}</Text>
          <Text style={[styles.statLabel, themeStyles.subText]}>Failed Today</Text>
        </View>
      </View>

      {/* Send Test SMS Card */}
      <View style={[styles.card, themeStyles.card]}>
        <Text style={[styles.cardTitle, themeStyles.text]}>Send Test SMS</Text>
        <Text style={[styles.cardSubtitle, themeStyles.subText]}>
          Verify that your device and SIM card can dispatch SMS messages.
        </Text>

        <Text style={[styles.inputLabel, themeStyles.subText]}>Recipient Phone (E.164)</Text>
        <TextInput
          style={[styles.input, themeStyles.input]}
          placeholder="+254712345678"
          placeholderTextColor={isDark ? '#64748B' : '#94A3B8'}
          value={testPhone}
          onChangeText={setTestPhone}
          keyboardType="phone-pad"
          autoCapitalize="none"
        />

        <Text style={[styles.inputLabel, themeStyles.subText]}>Test Message</Text>
        <TextInput
          style={[styles.input, themeStyles.input]}
          placeholder="Message body"
          placeholderTextColor={isDark ? '#64748B' : '#94A3B8'}
          value={testMessage}
          onChangeText={setTestMessage}
          autoCapitalize="none"
        />

        <TouchableOpacity
          style={[styles.button, isSendingTest && styles.buttonDisabled]}
          onPress={handleSendTestSms}
          disabled={isSendingTest}
        >
          {isSendingTest ? (
            <ActivityIndicator color="#FFFFFF" size="small" />
          ) : (
            <Text style={styles.buttonText}>Send Test SMS</Text>
          )}
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 16,
    paddingBottom: 40,
  },
  banner: {
    borderRadius: 12,
    padding: 14,
    marginBottom: 16,
  },
  batteryBannerTitle: {
    color: '#F59E0B',
    fontWeight: '700',
    fontSize: 14,
    marginBottom: 4,
  },
  batteryBannerText: {
    color: '#D1D5DB',
    fontSize: 13,
    lineHeight: 18,
  },
  card: {
    borderRadius: 16,
    padding: 18,
    marginBottom: 16,
    elevation: 2,
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
  },
  statusHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  statusTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: 10,
  },
  statusTitle: {
    fontSize: 20,
    fontWeight: '700',
  },
  statusDescription: {
    fontSize: 14,
    marginTop: 2,
  },
  statsRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 16,
  },
  statCard: {
    flex: 1,
    borderRadius: 16,
    padding: 18,
    alignItems: 'center',
  },
  statValue: {
    fontSize: 32,
    fontWeight: '800',
    marginBottom: 4,
  },
  statLabel: {
    fontSize: 13,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  cardTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 4,
  },
  cardSubtitle: {
    fontSize: 13,
    marginBottom: 16,
  },
  inputLabel: {
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 6,
    textTransform: 'uppercase',
  },
  input: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 15,
    marginBottom: 14,
  },
  button: {
    backgroundColor: '#2563EB',
    borderRadius: 10,
    paddingVertical: 13,
    alignItems: 'center',
    marginTop: 4,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: '#FFFFFF',
    fontWeight: '700',
    fontSize: 15,
  },
});

const darkStyles = StyleSheet.create({
  container: {
    backgroundColor: '#0F172A',
  },
  card: {
    backgroundColor: '#1E293B',
    borderColor: '#334155',
  },
  batteryBanner: {
    backgroundColor: '#451A03',
    borderColor: '#B45309',
    borderWidth: 1,
  },
  text: {
    color: '#F8FAFC',
  },
  subText: {
    color: '#94A3B8',
  },
  input: {
    backgroundColor: '#0F172A',
    borderColor: '#334155',
    color: '#F8FAFC',
  },
});

const lightStyles = StyleSheet.create({
  container: {
    backgroundColor: '#F8FAFC',
  },
  card: {
    backgroundColor: '#FFFFFF',
    borderColor: '#E2E8F0',
  },
  batteryBanner: {
    backgroundColor: '#FEF3C7',
    borderColor: '#F59E0B',
    borderWidth: 1,
  },
  text: {
    color: '#0F172A',
  },
  subText: {
    color: '#64748B',
  },
  input: {
    backgroundColor: '#F8FAFC',
    borderColor: '#CBD5E1',
    color: '#0F172A',
  },
});
