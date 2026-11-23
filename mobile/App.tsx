import React, { useState, useEffect } from 'react';
import {
  SafeAreaView,
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  StatusBar,
  useColorScheme,
  Modal,
} from 'react-native';
import { DashboardScreen } from './src/screens/DashboardScreen';
import { SetupScreen } from './src/screens/SetupScreen';
import { LogScreen } from './src/screens/LogScreen';
import { AccountScreen } from './src/screens/AccountScreen';
import { WelcomeScreen } from './src/screens/WelcomeScreen';
import Constants from 'expo-constants';
import { relayManager } from './src/relayManager';
import {
  checkPermissions,
  requestAllPermissions,
  openAppSettings,
  PermissionStatus,
} from './src/permissions';

type TabType = 'dashboard' | 'logs' | 'account' | 'setup';

const TABS: { key: TabType; label: string }[] = [
  { key: 'dashboard', label: 'Dashboard' },
  { key: 'logs', label: 'Logs' },
  { key: 'account', label: 'Account' },
  { key: 'setup', label: 'Setup' },
];

export default function App() {
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';

  const [activeTab, setActiveTab] = useState<TabType>('dashboard');
  const [permissions, setPermissions] = useState<PermissionStatus | null>(null);
  const [showPermissionModal, setShowPermissionModal] = useState(false);
  // null until storage is loaded; nothing but the welcome screen works signed out
  const [signedIn, setSignedIn] = useState<boolean | null>(null);

  useEffect(() => {
    // Follow sign-in / sign-out; land on the dashboard after signing in
    const unsubscribe = relayManager.subscribe(() => {
      const now = relayManager.getAccount() !== null;
      setSignedIn((before) => {
        if (before === false && now) setActiveTab('dashboard');
        return now;
      });
    });

    // Initialize Relay state and storage, then resume the relay if it was on
    relayManager.initialize().then(() => {
      setSignedIn(relayManager.getAccount() !== null);
      return relayManager.resumeIfEnabled();
    });

    // Check runtime permissions on launch
    checkPermissions().then((status) => {
      setPermissions(status);
      if (!status.allGranted) {
        setShowPermissionModal(true);
      }
    });

    return unsubscribe;
  }, []);

  const handleGrantPermissions = async () => {
    const status = await requestAllPermissions();
    setPermissions(status);
    if (status.allGranted) {
      setShowPermissionModal(false);
      // Re-initialize SIM cards after permission is granted
      relayManager.initialize();
    }
  };

  const themeStyles = isDark ? darkStyles : lightStyles;

  return (
    <SafeAreaView style={[styles.safeArea, themeStyles.safeArea]}>
      <StatusBar barStyle={isDark ? 'light-content' : 'dark-content'} />

      {/* Top Header */}
      <View style={[styles.appHeader, themeStyles.header]}>
        <View style={styles.brandRow}>
          <View style={styles.brandBadge}>
            <Text style={styles.brandBadgeText}>SMS</Text>
          </View>
          <Text style={[styles.appTitle, themeStyles.text]}>Relay</Text>
        </View>
        <Text style={[styles.appVersion, themeStyles.subText]}>
          v{Constants.expoConfig?.version ?? '1.0.0'}
        </Text>
      </View>

      {/* Permissions Warning Strip if not all granted */}
      {permissions && !permissions.allGranted && (
        <TouchableOpacity
          style={styles.permissionStrip}
          onPress={() => setShowPermissionModal(true)}
          activeOpacity={0.8}
        >
          <Text style={styles.permissionStripText}>
            ⚠️ Permissions incomplete. Tap to grant SMS & SIM access.
          </Text>
        </TouchableOpacity>
      )}

      {/* Screen Container */}
      <View style={styles.screenContainer}>
        {signedIn === false && <WelcomeScreen isDark={isDark} />}
        {signedIn && activeTab === 'dashboard' && <DashboardScreen isDark={isDark} />}
        {signedIn && activeTab === 'logs' && <LogScreen isDark={isDark} />}
        {signedIn && activeTab === 'account' && <AccountScreen isDark={isDark} />}
        {signedIn && activeTab === 'setup' && <SetupScreen isDark={isDark} />}
      </View>

      {/* Bottom Navigation Bar (signed in only) */}
      {signedIn && (
      <View style={[styles.tabBar, themeStyles.tabBar]}>
        {TABS.map(({ key, label }) => (
          <TouchableOpacity
            key={key}
            style={[styles.tabItem, activeTab === key && styles.tabItemActive]}
            onPress={() => setActiveTab(key)}
          >
            <Text
              style={[
                styles.tabText,
                activeTab === key ? styles.tabTextActive : themeStyles.tabTextInactive,
              ]}
            >
              {label}
            </Text>
          </TouchableOpacity>
        ))}
      </View>
      )}

      {/* Permissions Explanation Modal */}
      <Modal
        visible={showPermissionModal}
        transparent
        animationType="fade"
        onRequestClose={() => setShowPermissionModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={[styles.modalCard, themeStyles.modalCard]}>
            <Text style={[styles.modalTitle, themeStyles.text]}>Permissions Required</Text>
            <Text style={[styles.modalSubtitle, themeStyles.subText]}>
              SMS Relay functions as a hardware-level gateway for OTP verification codes and requires:
            </Text>

            <View style={styles.permissionList}>
              <View style={styles.permissionItem}>
                <Text style={styles.permissionItemBullet}>•</Text>
                <View style={styles.permissionItemContent}>
                  <Text style={[styles.permissionItemTitle, themeStyles.text]}>Send SMS (SEND_SMS)</Text>
                  <Text style={[styles.permissionItemDesc, themeStyles.subText]}>
                    Dispatches OTP verification text messages silently to users.
                  </Text>
                </View>
              </View>

              <View style={styles.permissionItem}>
                <Text style={styles.permissionItemBullet}>•</Text>
                <View style={styles.permissionItemContent}>
                  <Text style={[styles.permissionItemTitle, themeStyles.text]}>SIM & Phone State (READ_PHONE_STATE)</Text>
                  <Text style={[styles.permissionItemDesc, themeStyles.subText]}>
                    Enables dual-SIM detection and carrier subscription selection.
                  </Text>
                </View>
              </View>

              <View style={styles.permissionItem}>
                <Text style={styles.permissionItemBullet}>•</Text>
                <View style={styles.permissionItemContent}>
                  <Text style={[styles.permissionItemTitle, themeStyles.text]}>Notifications (POST_NOTIFICATIONS)</Text>
                  <Text style={[styles.permissionItemDesc, themeStyles.subText]}>
                    Maintains the Android foreground service so texts send while the phone is asleep.
                  </Text>
                </View>
              </View>
            </View>

            <TouchableOpacity style={styles.grantButton} onPress={handleGrantPermissions}>
              <Text style={styles.grantButtonText}>Grant Permissions</Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.settingsButton} onPress={openAppSettings}>
              <Text style={styles.settingsButtonText}>Open Android Settings</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.closeButton}
              onPress={() => setShowPermissionModal(false)}
            >
              <Text style={styles.closeButtonText}>Dismiss</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  appHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderBottomWidth: 1,
  },
  brandRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  brandBadge: {
    backgroundColor: '#607938',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
    marginRight: 8,
  },
  brandBadgeText: {
    color: '#FFFFFF',
    fontWeight: '800',
    fontSize: 12,
    letterSpacing: 0.5,
  },
  appTitle: {
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
  appVersion: {
    fontSize: 12,
    fontWeight: '600',
  },
  permissionStrip: {
    backgroundColor: '#8C5314',
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  permissionStripText: {
    color: '#F5DFBF',
    fontSize: 12,
    fontWeight: '600',
    textAlign: 'center',
  },
  screenContainer: {
    flex: 1,
  },
  tabBar: {
    flexDirection: 'row',
    borderTopWidth: 1,
    paddingBottom: 6,
    paddingTop: 8,
    paddingHorizontal: 12,
  },
  tabItem: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 8,
    borderRadius: 8,
  },
  tabItemActive: {
    backgroundColor: '#60793815',
  },
  tabText: {
    fontSize: 14,
    fontWeight: '600',
  },
  tabTextActive: {
    color: '#607938',
    fontWeight: '700',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.75)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  modalCard: {
    width: '100%',
    borderRadius: 20,
    padding: 24,
    elevation: 5,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: '800',
    marginBottom: 6,
  },
  modalSubtitle: {
    fontSize: 13,
    lineHeight: 18,
    marginBottom: 16,
  },
  permissionList: {
    marginBottom: 20,
  },
  permissionItem: {
    flexDirection: 'row',
    marginBottom: 12,
  },
  permissionItemBullet: {
    color: '#607938',
    fontSize: 18,
    marginRight: 8,
    lineHeight: 20,
  },
  permissionItemContent: {
    flex: 1,
  },
  permissionItemTitle: {
    fontSize: 14,
    fontWeight: '700',
    marginBottom: 2,
  },
  permissionItemDesc: {
    fontSize: 12,
    lineHeight: 16,
  },
  grantButton: {
    backgroundColor: '#607938',
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
    marginBottom: 10,
  },
  grantButtonText: {
    color: '#FFFFFF',
    fontWeight: '700',
    fontSize: 15,
  },
  settingsButton: {
    borderWidth: 1.5,
    borderColor: '#6F8A40',
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: 'center',
    marginBottom: 10,
  },
  settingsButtonText: {
    color: '#6F8A40',
    fontWeight: '600',
    fontSize: 14,
  },
  closeButton: {
    paddingVertical: 8,
    alignItems: 'center',
  },
  closeButtonText: {
    color: '#C7AA7E',
    fontSize: 13,
  },
});

const darkStyles = StyleSheet.create({
  safeArea: {
    backgroundColor: '#2B1A0A',
  },
  header: {
    backgroundColor: '#2B1A0A',
    borderBottomColor: '#3F270F',
  },
  text: {
    color: '#F6EDDF',
  },
  subText: {
    color: '#C7AA7E',
  },
  tabBar: {
    backgroundColor: '#2B1A0A',
    borderTopColor: '#3F270F',
  },
  tabTextInactive: {
    color: '#7D5E3D',
  },
  modalCard: {
    backgroundColor: '#3F270F',
  },
});

const lightStyles = StyleSheet.create({
  safeArea: {
    backgroundColor: '#FFFFFF',
  },
  header: {
    backgroundColor: '#FFFFFF',
    borderBottomColor: '#E8D6B8',
  },
  text: {
    color: '#2B1A0A',
  },
  subText: {
    color: '#7D5E3D',
  },
  tabBar: {
    backgroundColor: '#FFFFFF',
    borderTopColor: '#E8D6B8',
  },
  tabTextInactive: {
    color: '#C7AA7E',
  },
  modalCard: {
    backgroundColor: '#FFFFFF',
  },
});
