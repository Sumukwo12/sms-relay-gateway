import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  ActivityIndicator,
  ScrollView,
  Alert,
} from 'react-native';
import { getSimCards } from 'sms-sender';
import { relayManager, getUrlSecurityWarning } from '../relayManager';
import { SimCardInfo } from '../types';

interface SetupScreenProps {
  isDark: boolean;
}

export const SetupScreen: React.FC<SetupScreenProps> = ({ isDark }) => {
  const currentSettings = relayManager.getSettings();
  const [serverUrl, setServerUrl] = useState(currentSettings.serverUrl);
  const [token, setToken] = useState(currentSettings.token);
  const [selectedSubId, setSelectedSubId] = useState<number | null>(currentSettings.selectedSubId);
  const signedIn = relayManager.getAccount() !== null;
  // Manual URL + server token: the legacy setup, for servers without accounts
  const [showAdvanced, setShowAdvanced] = useState(!signedIn && !!currentSettings.token);

  // The SIM choice is saved right away (with or without an account)
  const chooseSim = async (subId: number) => {
    setSelectedSubId(subId);
    await relayManager.updateSettings({ ...relayManager.getSettings(), selectedSubId: subId });
  };

  const [simCards, setSimCards] = useState<SimCardInfo[]>([]);
  const [isLoadingSims, setIsLoadingSims] = useState(false);
  const [isTesting, setIsTesting] = useState(false);
  const [testResult, setTestResult] = useState<{ success: boolean; message: string } | null>(null);

  const securityWarning = getUrlSecurityWarning(serverUrl);

  const refreshSimList = async () => {
    setIsLoadingSims(true);
    try {
      const cards = await getSimCards();
      setSimCards(cards);
      if (cards.length > 0 && selectedSubId === null) {
        setSelectedSubId(cards[0].subscriptionId);
      }
    } catch (err) {
      console.warn('[Setup] Error loading SIM cards:', err);
    } finally {
      setIsLoadingSims(false);
    }
  };

  useEffect(() => {
    let isMounted = true;
    getSimCards()
      .then((cards) => {
        if (!isMounted) return;
        setSimCards(cards);
        if (cards.length > 0 && selectedSubId === null) {
          setSelectedSubId(cards[0].subscriptionId);
        }
      })
      .catch((err) => {
        console.warn('[Setup] Error loading SIM cards:', err);
      });

    return () => {
      isMounted = false;
    };
  }, [selectedSubId]);



  const handleTestConnection = async () => {
    if (!serverUrl.trim() || !token.trim()) {
      Alert.alert('Required Fields', 'Please enter both the Server URL and Gateway Token to test.');
      return;
    }

    setIsTesting(true);
    setTestResult(null);

    const result = await relayManager.testConnection(serverUrl, token);
    setTestResult(result);
    setIsTesting(false);
  };

  const handleSave = async () => {
    if (!serverUrl.trim()) {
      Alert.alert('Validation Error', 'Server URL is required.');
      return;
    }

    await relayManager.updateSettings({
      serverUrl: serverUrl.trim(),
      token: token.trim(),
      selectedSubId,
    });

    Alert.alert('Settings Saved', 'Connection settings have been securely stored.');
  };

  const themeStyles = isDark ? darkStyles : lightStyles;

  return (
    <ScrollView style={[styles.container, themeStyles.container]} contentContainerStyle={styles.content}>
      {/* Server Configuration (advanced: most people sign in on the Account tab) */}
      <View style={[styles.card, themeStyles.card]}>
        <TouchableOpacity onPress={() => setShowAdvanced(!showAdvanced)} activeOpacity={0.7}>
          <View style={styles.simHeader}>
            <Text style={[styles.cardTitle, themeStyles.text]}>Advanced: server token</Text>
            <Text style={styles.refreshButtonText}>{showAdvanced ? 'Hide' : 'Show'}</Text>
          </View>
          <Text style={[styles.cardSubtitle, themeStyles.subText]}>
            {signedIn
              ? 'Not needed: this phone is connected through your account.'
              : 'Only for servers set up with a shared PHONE_GATEWAY_TOKEN. Otherwise sign in on the Account tab.'}
          </Text>
        </TouchableOpacity>

        {showAdvanced && (
        <>
        <Text style={[styles.inputLabel, themeStyles.subText]}>WebSocket URL</Text>
        <TextInput
          style={[styles.input, themeStyles.input]}
          placeholder="wss://sms.example.com/phone"
          placeholderTextColor={isDark ? '#64748B' : '#94A3B8'}
          value={serverUrl}
          onChangeText={setServerUrl}
          autoCapitalize="none"
          autoCorrect={false}
        />

        {securityWarning && (
          <View style={styles.warningBox}>
            <Text style={styles.warningText}>{securityWarning}</Text>
          </View>
        )}

        <Text style={[styles.inputLabel, themeStyles.subText]}>Phone Gateway Token</Text>
        <TextInput
          style={[styles.input, themeStyles.input]}
          placeholder="Secret token matching PHONE_GATEWAY_TOKEN"
          placeholderTextColor={isDark ? '#64748B' : '#94A3B8'}
          value={token}
          onChangeText={setToken}
          secureTextEntry
          autoCapitalize="none"
          autoCorrect={false}
        />

        {testResult && (
          <View
            style={[
              styles.testResultBox,
              testResult.success ? styles.testSuccessBox : styles.testErrorBox,
            ]}
          >
            <Text
              style={[
                styles.testResultText,
                testResult.success ? styles.testSuccessText : styles.testErrorText,
              ]}
            >
              {testResult.message}
            </Text>
          </View>
        )}

        <View style={styles.actionRow}>
          <TouchableOpacity
            style={[styles.testButton, isTesting && styles.buttonDisabled]}
            onPress={handleTestConnection}
            disabled={isTesting}
          >
            {isTesting ? (
              <ActivityIndicator color="#2563EB" size="small" />
            ) : (
              <Text style={styles.testButtonText}>Test Connection</Text>
            )}
          </TouchableOpacity>

          <TouchableOpacity style={styles.saveButton} onPress={handleSave}>
            <Text style={styles.saveButtonText}>Save Settings</Text>
          </TouchableOpacity>
        </View>
        </>
        )}
      </View>

      {/* SIM Selection Card */}
      <View style={[styles.card, themeStyles.card]}>
        <View style={styles.simHeader}>
          <View>
            <Text style={[styles.cardTitle, themeStyles.text]}>Outgoing SIM Card</Text>
            <Text style={[styles.cardSubtitle, themeStyles.subText]}>
              The SIM your messages are sent from. Saved as soon as you pick one.
            </Text>
          </View>
          <TouchableOpacity style={styles.refreshButton} onPress={refreshSimList} disabled={isLoadingSims}>
            <Text style={styles.refreshButtonText}>Refresh</Text>
          </TouchableOpacity>
        </View>

        {isLoadingSims ? (
          <ActivityIndicator color="#2563EB" style={{ marginVertical: 12 }} />
        ) : simCards.length === 0 ? (
          <View style={styles.emptySimBox}>
            <Text style={[styles.emptySimText, themeStyles.subText]}>
              No active SIM detected or READ_PHONE_STATE permission pending. Default system SIM will be used.
            </Text>
          </View>
        ) : (
          simCards.map((sim) => {
            const isSelected = selectedSubId === sim.subscriptionId;
            return (
              <TouchableOpacity
                key={sim.subscriptionId}
                style={[
                  styles.simOption,
                  themeStyles.simOption,
                  isSelected && styles.simOptionSelected,
                ]}
                onPress={() => chooseSim(sim.subscriptionId)}
              >
                <View style={styles.simRadio}>
                  {isSelected && <View style={styles.simRadioInner} />}
                </View>
                <View style={styles.simInfo}>
                  <Text style={[styles.simName, themeStyles.text]}>
                    {sim.displayName} {sim.carrierName ? `(${sim.carrierName})` : ''}
                  </Text>
                  <Text style={[styles.simDetail, themeStyles.subText]}>
                    Slot {sim.slotIndex + 1} {sim.number ? `· ${sim.number}` : ''}
                  </Text>
                </View>
              </TouchableOpacity>
            );
          })
        )}
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
    marginBottom: 12,
  },
  warningBox: {
    backgroundColor: '#78350F',
    borderRadius: 8,
    padding: 10,
    marginBottom: 12,
  },
  warningText: {
    color: '#FEF3C7',
    fontSize: 12,
    lineHeight: 16,
  },
  testResultBox: {
    borderRadius: 8,
    padding: 10,
    marginBottom: 12,
  },
  testSuccessBox: {
    backgroundColor: '#064E3B',
  },
  testErrorBox: {
    backgroundColor: '#7F1D1D',
  },
  testResultText: {
    fontSize: 13,
  },
  testSuccessText: {
    color: '#34D399',
  },
  testErrorText: {
    color: '#FCA5A5',
  },
  actionRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 6,
  },
  testButton: {
    flex: 1,
    borderWidth: 1.5,
    borderColor: '#2563EB',
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
  },
  testButtonText: {
    color: '#2563EB',
    fontWeight: '700',
    fontSize: 14,
  },
  saveButton: {
    flex: 1,
    backgroundColor: '#2563EB',
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
  },
  saveButtonText: {
    color: '#FFFFFF',
    fontWeight: '700',
    fontSize: 14,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  simHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 8,
  },
  refreshButton: {
    paddingVertical: 4,
    paddingHorizontal: 10,
    borderRadius: 6,
    backgroundColor: '#2563EB20',
  },
  refreshButtonText: {
    color: '#2563EB',
    fontSize: 12,
    fontWeight: '600',
  },
  emptySimBox: {
    padding: 12,
    borderRadius: 8,
    backgroundColor: '#64748B15',
  },
  emptySimText: {
    fontSize: 13,
    lineHeight: 18,
  },
  simOption: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    borderRadius: 10,
    borderWidth: 1,
    marginBottom: 8,
  },
  simOptionSelected: {
    borderColor: '#2563EB',
    backgroundColor: '#2563EB15',
  },
  simRadio: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: '#2563EB',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  simRadioInner: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#2563EB',
  },
  simInfo: {
    flex: 1,
  },
  simName: {
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 2,
  },
  simDetail: {
    fontSize: 12,
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
  simOption: {
    borderColor: '#334155',
    backgroundColor: '#0F172A',
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
  simOption: {
    borderColor: '#E2E8F0',
    backgroundColor: '#F8FAFC',
  },
});
