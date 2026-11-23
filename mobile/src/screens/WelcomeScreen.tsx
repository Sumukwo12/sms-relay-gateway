import React, { useState } from 'react';
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { SignInForm } from './AccountScreen';

interface WelcomeScreenProps {
  isDark: boolean;
}

const STEPS = [
  ['Create an account', 'Here or on the website. An administrator approves new accounts.'],
  ['Sign in on this phone', 'It becomes your SMS gateway; messages go out through its SIM.'],
  ['Connect your systems', 'Get API keys on the website and send codes or any SMS from your apps.'],
];

/** What signed-out users see: what the app is for, and sign-in / sign-up. Nothing else works until then. */
export const WelcomeScreen: React.FC<WelcomeScreenProps> = ({ isDark }) => {
  const [form, setForm] = useState<'signin' | 'signup' | null>(null);
  const theme = isDark ? darkStyles : lightStyles;

  if (form) {
    return (
      <ScrollView style={[styles.container, theme.container]} contentContainerStyle={styles.content}>
        <SignInForm
          key={form}
          isDark={isDark}
          initialMode={form}
          onBack={() => setForm(null)}
        />
      </ScrollView>
    );
  }

  return (
    <ScrollView style={[styles.container, theme.container]} contentContainerStyle={styles.content}>
      <View style={styles.hero}>
        <View style={styles.badge}>
          <Text style={styles.badgeText}>SMS</Text>
        </View>
        <Text style={[styles.title, theme.text]}>Your own SMS gateway</Text>
        <Text style={[styles.subtitle, theme.subText]}>
          SMS Relay turns this Android phone into a gateway for your websites and apps: they send
          verification codes and notifications, and this phone delivers them from its own SIM —
          no per-message fees to an SMS provider.
        </Text>
      </View>

      <View style={[styles.card, theme.card]}>
        <Text style={[styles.cardTitle, theme.text]}>How it works</Text>
        {STEPS.map(([title, text], i) => (
          <View key={title} style={styles.step}>
            <View style={styles.stepNumber}>
              <Text style={styles.stepNumberText}>{i + 1}</Text>
            </View>
            <View style={styles.stepBody}>
              <Text style={[styles.stepTitle, theme.text]}>{title}</Text>
              <Text style={[styles.stepText, theme.subText]}>{text}</Text>
            </View>
          </View>
        ))}
      </View>

      <TouchableOpacity style={styles.primaryButton} onPress={() => setForm('signin')}>
        <Text style={styles.primaryButtonText}>Sign in</Text>
      </TouchableOpacity>
      <TouchableOpacity style={styles.secondaryButton} onPress={() => setForm('signup')}>
        <Text style={styles.secondaryButtonText}>Create an account</Text>
      </TouchableOpacity>

      <Text style={[styles.footnote, theme.subText]}>
        Keep the phone charged and online while it works as your gateway.
      </Text>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: 20, paddingBottom: 40 },
  hero: { alignItems: 'center', marginTop: 12, marginBottom: 20 },
  badge: {
    backgroundColor: '#607938',
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 10,
    marginBottom: 16,
  },
  badgeText: { color: '#FFFFFF', fontWeight: '800', fontSize: 18 },
  title: { fontSize: 24, fontWeight: '800', textAlign: 'center' },
  subtitle: { fontSize: 14, lineHeight: 21, textAlign: 'center', marginTop: 10 },
  card: { borderRadius: 16, padding: 18, marginBottom: 20 },
  cardTitle: { fontSize: 16, fontWeight: '700', marginBottom: 12 },
  step: { flexDirection: 'row', marginBottom: 12 },
  stepNumber: {
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: '#60793820',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  stepNumberText: { color: '#607938', fontWeight: '700' },
  stepBody: { flex: 1 },
  stepTitle: { fontSize: 14, fontWeight: '700' },
  stepText: { fontSize: 13, lineHeight: 18, marginTop: 2 },
  primaryButton: {
    backgroundColor: '#607938',
    borderRadius: 12,
    paddingVertical: 15,
    alignItems: 'center',
  },
  primaryButtonText: { color: '#FFFFFF', fontWeight: '700', fontSize: 16 },
  secondaryButton: {
    borderWidth: 1.5,
    borderColor: '#607938',
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
    marginTop: 12,
  },
  secondaryButtonText: { color: '#607938', fontWeight: '700', fontSize: 16 },
  footnote: { fontSize: 12, textAlign: 'center', marginTop: 18 },
});

const darkStyles = StyleSheet.create({
  container: { backgroundColor: '#2B1A0A' },
  card: { backgroundColor: '#3F270F' },
  text: { color: '#F6EDDF' },
  subText: { color: '#C7AA7E' },
});

const lightStyles = StyleSheet.create({
  container: { backgroundColor: '#F6EDDF' },
  card: { backgroundColor: '#FFFFFF' },
  text: { color: '#2B1A0A' },
  subText: { color: '#7D5E3D' },
});
