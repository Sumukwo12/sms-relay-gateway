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
import { relayManager } from './src/relayManager';
import {
  checkPermissions,
  requestAllPermissions,
  openAppSettings,
  PermissionStatus,
} from './src/permissions';

type TabType = 'dashboard' | 'logs' | 'setup';

export default function App() {
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';

  const [activeTab, setActiveTab] = useState<TabType>('dashboard');
  const [permissions, setPermissions] = useState<PermissionStatus | null>(null);
  const [showPermissionModal, setShowPermissionModal] = useState(false);

  useEffect(() => {
    // Initialize Relay state and storage, then resume the relay if it was on
    relayManager.initialize().then(() => relayManager.resumeIfEnabled());

    // Check runtime permissions on launch
    checkPermissions().then((status) => {
      setPermissions(status);
      if (!status.allGranted) {
        setShowPermissionModal(true);
      }
    });
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
        <Text style={[styles.appVersion, themeStyles.subText]}>v1.0.0</Text>
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
        {activeTab === 'dashboard' && <DashboardScreen isDark={isDark} />}
        {activeTab === 'logs' && <LogScreen isDark={isDark} />}
        {activeTab === 'setup' && <SetupScreen isDark={isDark} />}
      </View>

      {/* Bottom Navigation Bar */}
      <View style={[styles.tabBar, themeStyles.tabBar]}>
        <TouchableOpacity
          style={[styles.tabItem, activeTab === 'dashboard' && styles.tabItemActive]}
          onPress={() => setActiveTab('dashboard')}
        >
          <Text
            style={[
              styles.tabText,
              activeTab === 'dashboard' ? styles.tabTextActive : themeStyles.tabTextInactive,
            ]}
          >
            Dashboard
          </Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.tabItem, activeTab === 'logs' && styles.tabItemActive]}
          onPress={() => setActiveTab('logs')}
        >
          <Text
            style={[
              styles.tabText,
              activeTab === 'logs' ? styles.tabTextActive : themeStyles.tabTextInactive,
            ]}
          >
            Logs
          </Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.tabItem, activeTab === 'setup' && styles.tabItemActive]}
          onPress={() => setActiveTab('setup')}
        >
          <Text
            style={[
              styles.tabText,
              activeTab === 'setup' ? styles.tabTextActive : themeStyles.tabTextInactive,
            ]}
          >
            Setup
          </Text>
        </TouchableOpacity>
      </View>

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
    backgroundColor: '#2563EB',
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
    backgroundColor: '#B45309',
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  permissionStripText: {
    color: '#FEF3C7',
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
    backgroundColor: '#2563EB15',
  },
  tabText: {
    fontSize: 14,
    fontWeight: '600',
  },
  tabTextActive: {
    color: '#2563EB',
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
    color: '#2563EB',
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
    backgroundColor: '#2563EB',
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
    borderColor: '#3B82F6',
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: 'center',
    marginBottom: 10,
  },
  settingsButtonText: {
    color: '#3B82F6',
    fontWeight: '600',
    fontSize: 14,
  },
  closeButton: {
    paddingVertical: 8,
    alignItems: 'center',
  },
  closeButtonText: {
    color: '#94A3B8',
    fontSize: 13,
  },
});

const darkStyles = StyleSheet.create({
  safeArea: {
    backgroundColor: '#0F172A',
  },
  header: {
    backgroundColor: '#0F172A',
    borderBottomColor: '#1E293B',
  },
  text: {
    color: '#F8FAFC',
  },
  subText: {
    color: '#94A3B8',
  },
  tabBar: {
    backgroundColor: '#0F172A',
    borderTopColor: '#1E293B',
  },
  tabTextInactive: {
    color: '#64748B',
  },
  modalCard: {
    backgroundColor: '#1E293B',
  },
});

const lightStyles = StyleSheet.create({
  safeArea: {
    backgroundColor: '#FFFFFF',
  },
  header: {
    backgroundColor: '#FFFFFF',
    borderBottomColor: '#E2E8F0',
  },
  text: {
    color: '#0F172A',
  },
  subText: {
    color: '#64748B',
  },
  tabBar: {
    backgroundColor: '#FFFFFF',
    borderTopColor: '#E2E8F0',
  },
  tabTextInactive: {
    color: '#94A3B8',
  },
  modalCard: {
    backgroundColor: '#FFFFFF',
  },
});
