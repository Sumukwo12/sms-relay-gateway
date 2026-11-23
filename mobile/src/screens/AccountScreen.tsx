import React, { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { relayManager } from '../relayManager';
import { httpBaseFromInput } from '../relayLogic';
import { DEFAULT_SERVER, fetchMe, signIn, signUp, type AccountUser } from '../account';

interface AccountScreenProps {
  isDark: boolean;
}

export const AccountScreen: React.FC<AccountScreenProps> = ({ isDark }) => {
  const [account, setAccount] = useState(relayManager.getAccount());
  const [status, setStatus] = useState(relayManager.getStatus());

  useEffect(() => {
    return relayManager.subscribe(() => {
      setAccount(relayManager.getAccount());
      setStatus(relayManager.getStatus());
    });
  }, []);

  const theme = isDark ? darkStyles : lightStyles;

  return (
    <ScrollView style={[styles.container, theme.container]} contentContainerStyle={styles.content}>
      {account ? (
        <SignedIn isDark={isDark} signedOutRemotely={status === 'invalid_token'} />
      ) : (
        <SignInForm isDark={isDark} />
      )}
    </ScrollView>
  );
};

const SignedIn: React.FC<{ isDark: boolean; signedOutRemotely: boolean }> = ({
  isDark,
  signedOutRemotely,
}) => {
  const account = relayManager.getAccount()!;
  const [user, setUser] = useState<AccountUser | null>(null);
  const [busy, setBusy] = useState(false);
  const theme = isDark ? darkStyles : lightStyles;

  useEffect(() => {
    const token = relayManager.getSettings().token;
    if (!token) return;
    let cancelled = false;
    fetchMe(account.server, token).then((res) => {
      if (!cancelled && res.ok) setUser(res.data.user);
    });
    return () => {
      cancelled = true;
    };
  }, [account.server]);

  const confirmSignOut = () => {
    Alert.alert('Sign out?', 'This phone stops sending SMS for your account until you sign in again.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign out',
        style: 'destructive',
        onPress: async () => {
          setBusy(true);
          await relayManager.signOut();
          setBusy(false);
        },
      },
    ]);
  };

  return (
    <View style={[styles.card, theme.card]}>
      <Text style={[styles.cardTitle, theme.text]}>Signed in</Text>
      <Text style={[styles.cardSubtitle, theme.subText]}>
        This phone sends SMS for your account. Manage it and get API keys on the website.
      </Text>

      {signedOutRemotely && (
        <View style={[styles.banner, styles.bannerError]}>
          <Text style={styles.bannerErrorText}>
            This phone was signed out from the dashboard (or the account was suspended). Sign out
            here, then sign in again.
          </Text>
        </View>
      )}

      {user?.status === 'pending' && (
        <View style={[styles.banner, styles.bannerWarning]}>
          <Text style={styles.bannerWarningText}>
            Your account is waiting for an administrator&apos;s approval. The phone stays connected;
            messages are sent once you&apos;re approved.
          </Text>
        </View>
      )}

      <Row label="Account" value={account.email} theme={theme} />
      <Row label="This phone" value={account.deviceName} theme={theme} />
      <Row label="Server" value={account.server} theme={theme} />
      {user && <Row label="Daily limit" value={`${user.daily_limit} SMS parts`} theme={theme} />}

      <TouchableOpacity
        style={[styles.secondaryButton, busy && styles.disabled]}
        onPress={confirmSignOut}
        disabled={busy}
      >
        {busy ? (
          <ActivityIndicator color="#DC2626" />
        ) : (
          <Text style={styles.secondaryButtonText}>Sign out this phone</Text>
        )}
      </TouchableOpacity>
    </View>
  );
};

const Row: React.FC<{ label: string; value: string; theme: typeof darkStyles }> = ({
  label,
  value,
  theme,
}) => (
  <View style={styles.row}>
    <Text style={[styles.rowLabel, theme.subText]}>{label}</Text>
    <Text style={[styles.rowValue, theme.text]} numberOfLines={1}>
      {value}
    </Text>
  </View>
);

export const SignInForm: React.FC<{
  isDark: boolean;
  initialMode?: 'signin' | 'signup';
  onBack?: () => void;
}> = ({ isDark, initialMode = 'signin', onBack }) => {
  const [mode, setMode] = useState<'signin' | 'signup'>(initialMode);
  const [server, setServer] = useState(DEFAULT_SERVER);
  const [editServer, setEditServer] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const theme = isDark ? darkStyles : lightStyles;
  const placeholderColor = isDark ? '#7D5E3D' : '#C7AA7E';

  const submit = async () => {
    const base = httpBaseFromInput(server);
    if (!base) {
      setError('Enter the server address, e.g. sms.strand.co.ke');
      return;
    }
    if (!email.trim() || !password) {
      setError('Enter your email and password.');
      return;
    }

    setBusy(true);
    setError(null);
    const res =
      mode === 'signup'
        ? await signUp(base, email, password, name)
        : await signIn(base, email, password);

    if (res.ok) {
      await relayManager.signIn(base, res.data.user.email, res.data);
    } else {
      setError(res.message);
    }
    setBusy(false);
  };

  const isSignUp = mode === 'signup';

  return (
    <View style={[styles.card, theme.card]}>
      <Text style={[styles.cardTitle, theme.text]}>{isSignUp ? 'Create an account' : 'Sign in'}</Text>
      <Text style={[styles.cardSubtitle, theme.subText]}>
        {isSignUp
          ? 'Your account is reviewed by an administrator before it can send SMS. You can sign in and link this phone right away.'
          : 'Sign in to turn this phone into your SMS gateway. Your messages go out through its SIM.'}
      </Text>

      {editServer ? (
        <>
          <Text style={[styles.inputLabel, theme.subText]}>Server</Text>
          <TextInput
            style={[styles.input, theme.input]}
            value={server}
            onChangeText={setServer}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
            placeholderTextColor={placeholderColor}
          />
        </>
      ) : (
        <TouchableOpacity style={styles.serverRow} onPress={() => setEditServer(true)}>
          <Text style={[styles.rowLabel, theme.subText]} numberOfLines={1}>
            Server: {server.replace(/^https?:\/\//, '')}
          </Text>
          <Text style={styles.linkText}>Change</Text>
        </TouchableOpacity>
      )}

      {isSignUp && (
        <>
          <Text style={[styles.inputLabel, theme.subText]}>Name</Text>
          <TextInput
            style={[styles.input, theme.input]}
            value={name}
            onChangeText={setName}
            autoComplete="name"
            placeholderTextColor={placeholderColor}
          />
        </>
      )}

      <Text style={[styles.inputLabel, theme.subText]}>Email</Text>
      <TextInput
        style={[styles.input, theme.input]}
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        autoCorrect={false}
        autoComplete="email"
        keyboardType="email-address"
        placeholder="you@example.com"
        placeholderTextColor={placeholderColor}
      />

      <Text style={[styles.inputLabel, theme.subText]}>Password</Text>
      <TextInput
        style={[styles.input, theme.input]}
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoCapitalize="none"
        autoComplete={isSignUp ? 'password-new' : 'password'}
        placeholder={isSignUp ? 'At least 8 characters' : undefined}
        placeholderTextColor={placeholderColor}
      />

      {error && (
        <View style={[styles.banner, styles.bannerError]}>
          <Text style={styles.bannerErrorText}>{error}</Text>
        </View>
      )}

      <TouchableOpacity
        style={[styles.primaryButton, busy && styles.disabled]}
        onPress={submit}
        disabled={busy}
      >
        {busy ? (
          <ActivityIndicator color="#FFFFFF" />
        ) : (
          <Text style={styles.primaryButtonText}>{isSignUp ? 'Create account' : 'Sign in'}</Text>
        )}
      </TouchableOpacity>

      <TouchableOpacity
        style={styles.linkButton}
        onPress={() => {
          setMode(isSignUp ? 'signin' : 'signup');
          setError(null);
        }}
      >
        <Text style={styles.linkText}>
          {isSignUp ? 'Already have an account? Sign in' : 'New here? Create an account'}
        </Text>
      </TouchableOpacity>

      {onBack && (
        <TouchableOpacity style={styles.linkButton} onPress={onBack}>
          <Text style={[styles.rowLabel, theme.subText]}>Back</Text>
        </TouchableOpacity>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: 16, paddingBottom: 40 },
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
  cardTitle: { fontSize: 18, fontWeight: '700', marginBottom: 4 },
  cardSubtitle: { fontSize: 13, marginBottom: 16, lineHeight: 18 },
  inputLabel: { fontSize: 12, fontWeight: '600', marginBottom: 6, textTransform: 'uppercase' },
  input: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 15,
    marginBottom: 12,
  },
  banner: { borderRadius: 8, padding: 10, marginBottom: 12 },
  bannerError: { backgroundColor: '#7F1D1D' },
  bannerErrorText: { color: '#FECACA', fontSize: 13, lineHeight: 18 },
  bannerWarning: { backgroundColor: '#6B3F10' },
  bannerWarningText: { color: '#F5DFBF', fontSize: 13, lineHeight: 18 },
  primaryButton: {
    backgroundColor: '#607938',
    borderRadius: 10,
    paddingVertical: 13,
    alignItems: 'center',
    marginTop: 4,
  },
  primaryButtonText: { color: '#FFFFFF', fontWeight: '700', fontSize: 15 },
  secondaryButton: {
    borderWidth: 1.5,
    borderColor: '#DC2626',
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
    marginTop: 16,
  },
  secondaryButtonText: { color: '#DC2626', fontWeight: '700', fontSize: 14 },
  linkButton: { alignItems: 'center', paddingVertical: 14 },
  linkText: { color: '#607938', fontWeight: '600', fontSize: 14 },
  disabled: { opacity: 0.6 },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
    gap: 12,
  },
  rowLabel: { fontSize: 13 },
  serverRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 14,
    gap: 12,
  },
  rowValue: { fontSize: 14, fontWeight: '600', flexShrink: 1 },
});

const darkStyles = StyleSheet.create({
  container: { backgroundColor: '#2B1A0A' },
  card: { backgroundColor: '#3F270F', borderColor: '#5E4021' },
  text: { color: '#F6EDDF' },
  subText: { color: '#C7AA7E' },
  input: { backgroundColor: '#2B1A0A', borderColor: '#5E4021', color: '#F6EDDF' },
});

const lightStyles = StyleSheet.create({
  container: { backgroundColor: '#F6EDDF' },
  card: { backgroundColor: '#FFFFFF', borderColor: '#E8D6B8' },
  text: { color: '#2B1A0A' },
  subText: { color: '#7D5E3D' },
  input: { backgroundColor: '#F6EDDF', borderColor: '#DBC5A1', color: '#2B1A0A' },
});
