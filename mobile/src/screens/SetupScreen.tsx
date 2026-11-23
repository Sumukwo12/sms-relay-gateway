import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  ScrollView,
} from 'react-native';
import { getSimCards } from 'sms-sender';
import { relayManager } from '../relayManager';
import { SimCardInfo } from '../types';

interface SetupScreenProps {
  isDark: boolean;
}

export const SetupScreen: React.FC<SetupScreenProps> = ({ isDark }) => {
  const currentSettings = relayManager.getSettings();
  const [selectedSubId, setSelectedSubId] = useState<number | null>(currentSettings.selectedSubId);
  // The SIM choice is saved right away
  const chooseSim = async (subId: number) => {
    setSelectedSubId(subId);
    await relayManager.updateSettings({ ...relayManager.getSettings(), selectedSubId: subId });
  };

  const [simCards, setSimCards] = useState<SimCardInfo[]>([]);
  const [isLoadingSims, setIsLoadingSims] = useState(false);


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



  const themeStyles = isDark ? darkStyles : lightStyles;

  return (
    <ScrollView style={[styles.container, themeStyles.container]} contentContainerStyle={styles.content}>
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
          <ActivityIndicator color="#607938" style={{ marginVertical: 12 }} />
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
    backgroundColor: '#6B3F10',
    borderRadius: 8,
    padding: 10,
    marginBottom: 12,
  },
  warningText: {
    color: '#F5DFBF',
    fontSize: 12,
    lineHeight: 16,
  },
  testResultBox: {
    borderRadius: 8,
    padding: 10,
    marginBottom: 12,
  },
  testSuccessBox: {
    backgroundColor: '#2E3A1C',
  },
  testErrorBox: {
    backgroundColor: '#7F1D1D',
  },
  testResultText: {
    fontSize: 13,
  },
  testSuccessText: {
    color: '#A9BC78',
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
    borderColor: '#607938',
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
  },
  testButtonText: {
    color: '#607938',
    fontWeight: '700',
    fontSize: 14,
  },
  saveButton: {
    flex: 1,
    backgroundColor: '#607938',
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
    backgroundColor: '#60793820',
  },
  refreshButtonText: {
    color: '#607938',
    fontSize: 12,
    fontWeight: '600',
  },
  emptySimBox: {
    padding: 12,
    borderRadius: 8,
    backgroundColor: '#7D5E3D15',
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
    borderColor: '#607938',
    backgroundColor: '#60793815',
  },
  simRadio: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: '#607938',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  simRadioInner: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#607938',
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
    backgroundColor: '#2B1A0A',
  },
  card: {
    backgroundColor: '#3F270F',
    borderColor: '#5E4021',
  },
  text: {
    color: '#F6EDDF',
  },
  subText: {
    color: '#C7AA7E',
  },
  input: {
    backgroundColor: '#2B1A0A',
    borderColor: '#5E4021',
    color: '#F6EDDF',
  },
  simOption: {
    borderColor: '#5E4021',
    backgroundColor: '#2B1A0A',
  },
});

const lightStyles = StyleSheet.create({
  container: {
    backgroundColor: '#F6EDDF',
  },
  card: {
    backgroundColor: '#FFFFFF',
    borderColor: '#E8D6B8',
  },
  text: {
    color: '#2B1A0A',
  },
  subText: {
    color: '#7D5E3D',
  },
  input: {
    backgroundColor: '#F6EDDF',
    borderColor: '#DBC5A1',
    color: '#2B1A0A',
  },
  simOption: {
    borderColor: '#E8D6B8',
    backgroundColor: '#F6EDDF',
  },
});
