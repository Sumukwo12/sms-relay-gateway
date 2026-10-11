import { Socket, Channel } from 'phoenix';
import NetInfo from '@react-native-community/netinfo';
import Constants from 'expo-constants';
import {
  sendSms,
  addDeliveryListener,
  getDeviceInfo,
  DeliveredEvent,
} from 'sms-sender';
import {
  ConnectionStatus,
  LogEntry,
  RelaySettings,
  RelayStats,
  SmsPayload,
} from './types';
import {
  addLogEntry,
  calculateStats,
  getLogs,
  loadSettings,
  maskPhoneNumber,
  saveSettings,
  updateLogDelivery,
} from './storage';
import {
  stopForegroundService,
  updateForegroundNotification,
} from './foregroundService';

export function isPrivateNetworkUrl(urlStr: string): boolean {
  try {
    const parsed = new URL(urlStr);
    const host = parsed.hostname.toLowerCase();
    if (
      host === 'localhost' ||
      host === '127.0.0.1' ||
      host === '::1' ||
      host.endsWith('.local')
    ) {
      return true;
    }
    if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    const m172 = host.match(/^172\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/);
    if (m172) {
      const second = parseInt(m172[1], 10);
      if (second >= 16 && second <= 31) return true;
    }
    if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    return false;
  } catch {
    return false;
  }
}

export function getUrlSecurityWarning(urlStr: string): string | null {
  if (!urlStr) return null;
  const lower = urlStr.trim().toLowerCase();
  if (lower.startsWith('ws://') && !isPrivateNetworkUrl(urlStr)) {
    return 'Security Warning: Unencrypted ws:// on a public host. Use wss:// for production to prevent interception.';
  }
  return null;
}

export function isValidE164(phone: string): boolean {
  const cleaned = phone.replace(/[\s\-().]/g, '');
  return /^\+[1-9]\d{7,14}$/.test(cleaned);
}

class RelayManager {
  private socket: Socket | null = null;
  private channel: Channel | null = null;
  private status: ConnectionStatus = 'disconnected';
  private logs: LogEntry[] = [];
  private stats: RelayStats = { sentToday: 0, failedToday: 0 };
  private settings: RelaySettings = {
    serverUrl: '',
    token: '',
    selectedSubId: null,
  };

  private queue: SmsPayload[] = [];
  private isProcessingQueue = false;
  private handledMessageIds = new Set<string>();
  private isServiceRunning = false;
  private netInfoUnsubscribe: (() => void) | null = null;
  private deliverySubscription: any = null;
  private telemetryInterval: any = null;

  private listeners = new Set<() => void>();

  constructor() {
    this.setupDeliveryListener();
  }

  public subscribe(callback: () => void): () => void {
    this.listeners.add(callback);
    return () => {
      this.listeners.delete(callback);
    };
  }

  private notify() {
    this.listeners.forEach((fn) => fn());
  }

  public getStatus(): ConnectionStatus {
    return this.status;
  }

  public getLogs(): LogEntry[] {
    return this.logs;
  }

  public getStats(): RelayStats {
    return this.stats;
  }

  public getSettings(): RelaySettings {
    return this.settings;
  }

  public isRunning(): boolean {
    return this.isServiceRunning;
  }

  public async initialize(): Promise<void> {
    this.settings = await loadSettings();
    this.logs = await getLogs();
    this.stats = calculateStats(this.logs);

    // Populate handled ids from existing logs to prevent reprocessing
    this.logs.forEach((log) => this.handledMessageIds.add(log.id));
    this.notify();
  }

  public async updateSettings(newSettings: RelaySettings): Promise<void> {
    this.settings = newSettings;
    await saveSettings(newSettings);
    this.notify();

    // If service is currently active, restart connection with new settings
    if (this.isServiceRunning) {
      await this.startService();
    }
  }

  public async startService(): Promise<void> {
    this.isServiceRunning = true;
    await this.disconnect();
    this.setStatus('connecting');
    await updateForegroundNotification('Connecting to backend…');

    if (!this.settings.serverUrl || !this.settings.token) {
      this.setStatus('disconnected');
      await updateForegroundNotification('Disconnected: Missing Server URL or Token');
      return;
    }

    this.connectSocket();
    this.setupNetworkMonitor();
    this.notify();
  }

  public async stopService(): Promise<void> {
    this.isServiceRunning = false;
    this.clearTelemetryInterval();
    if (this.netInfoUnsubscribe) {
      this.netInfoUnsubscribe();
      this.netInfoUnsubscribe = null;
    }
    await this.disconnect();
    this.setStatus('disconnected');
    await stopForegroundService();
    this.notify();
  }

  private connectSocket() {
    try {
      const url = this.settings.serverUrl.trim();
      const token = this.settings.token.trim();

      this.socket = new Socket(url, {
        params: { token },
        reconnectAfterMs: (tries) => {
          if (!this.isServiceRunning || this.status === 'invalid_token') {
            return null as any;
          }
          this.setStatus('connecting');
          this.updateNotificationText('Reconnecting…');
          return Math.min(1000 * Math.pow(1.5, tries - 1), 30000);
        },
      });

      this.socket.onOpen(() => {
        // Socket connection established, join phone gateway channel
        this.joinChannel();
      });

      this.socket.onError((error: any) => {
        console.warn('[RelayManager] Socket error:', error);
        if (this.status !== 'invalid_token' && this.isServiceRunning) {
          this.setStatus('connecting');
          this.updateNotificationText('Reconnecting…');
        }
      });

      this.socket.onClose(() => {
        if (this.isServiceRunning && this.status !== 'invalid_token') {
          this.setStatus('connecting');
          this.updateNotificationText('Reconnecting…');
        }
      });

      this.socket.connect();
    } catch (err) {
      console.error('[RelayManager] Failed to create socket:', err);
      this.setStatus('disconnected');
    }
  }

  private joinChannel() {
    if (!this.socket) return;

    this.channel = this.socket.channel('gateway:phone', {});

    this.channel
      .join()
      .receive('ok', () => {
        this.setStatus('connected');
        this.updateNotificationText(`Connected · ${this.stats.sentToday} sent today`);
        this.sendDeviceTelemetry();
        this.startTelemetryInterval();
      })
      .receive('error', (resp: any) => {
        console.warn('[RelayManager] Channel join error:', resp);
        if (resp?.reason === 'invalid_token' || resp?.reason === 'unauthorized') {
          this.setStatus('invalid_token');
          this.updateNotificationText('Invalid gateway token');
          // A1: Stop retrying immediately so Phoenix doesn't rejoin forever
          this.isServiceRunning = false;
          this.clearTelemetryInterval();
          if (this.channel) {
            try {
              this.channel.leave();
            } catch {}
            this.channel = null;
          }
          if (this.socket) {
            try {
              this.socket.disconnect();
            } catch {}
            this.socket = null;
          }
        } else {
          this.setStatus('connecting');
          this.updateNotificationText('Reconnecting…');
        }
      });

    // SECURITY: strictly accept ONLY "send_sms" event from the backend
    this.channel.on('send_sms', (payload: any) => {
      this.handleIncomingSmsRequest(payload);
    });
  }

  private handleIncomingSmsRequest(payload: any) {
    if (!payload || !payload.id || !payload.to || !payload.body) {
      console.warn('[RelayManager] Malformed send_sms payload:', payload);
      return;
    }

    const { id, to, body } = payload;

    // Check if ID was already handled or duplicate
    if (this.handledMessageIds.has(id)) {
      console.warn(`[RelayManager] Ignoring duplicate SMS request id=${id}`);
      return;
    }

    this.handledMessageIds.add(id);
    this.queue.push({ id, to, body });
    this.processQueue();
  }

  private async processQueue() {
    if (this.isProcessingQueue || this.queue.length === 0) {
      return;
    }

    this.isProcessingQueue = true;

    while (this.queue.length > 0) {
      const msg = this.queue.shift()!;
      await this.executeSend(msg);
    }

    this.isProcessingQueue = false;
  }

  private async executeSend(msg: SmsPayload) {
    const maskedPhone = maskPhoneNumber(msg.to);

    // Validate E.164 phone format
    if (!isValidE164(msg.to)) {
      const errorMsg = 'Recipient number must be valid E.164 format (e.g. +254...)';
      this.channel?.push('sms_result', {
        id: msg.id,
        status: 'failed',
        error: errorMsg,
      });
      await this.recordLog(msg.id, maskedPhone, 'failed', errorMsg);
      return;
    }

    // Validate message length cap (480 characters)
    if (msg.body.length > 480) {
      const errorMsg = 'Message body exceeds 480 characters limit';
      this.channel?.push('sms_result', {
        id: msg.id,
        status: 'failed',
        error: errorMsg,
      });
      await this.recordLog(msg.id, maskedPhone, 'failed', errorMsg);
      return;
    }

    try {
      const subId = this.settings.selectedSubId ?? undefined;
      const sendResult = await sendSms(msg.to, msg.body, subId, msg.id);

      // Report result back to server
      this.channel?.push('sms_result', {
        id: msg.id,
        status: sendResult.status,
        error: sendResult.error || null,
      });

      await this.recordLog(
        msg.id,
        maskedPhone,
        sendResult.status,
        sendResult.error
      );
    } catch (err: any) {
      const errorMsg = err?.message || 'Native SMS dispatch failure';
      this.channel?.push('sms_result', {
        id: msg.id,
        status: 'failed',
        error: errorMsg,
      });
      await this.recordLog(msg.id, maskedPhone, 'failed', errorMsg);
    }
  }

  private async recordLog(
    id: string,
    maskedRecipient: string,
    status: 'sent' | 'failed' | 'delivered',
    error?: string
  ) {
    const entry: LogEntry = {
      id,
      maskedRecipient,
      status,
      error,
      timestamp: Date.now(),
    };

    this.logs = await addLogEntry(entry);
    this.stats = calculateStats(this.logs);

    if (this.status === 'connected') {
      this.updateNotificationText(`Connected · ${this.stats.sentToday} sent today`);
    }

    this.notify();
  }

  private setupDeliveryListener() {
    this.deliverySubscription = addDeliveryListener((event: DeliveredEvent) => {
      if (!event?.id) return;

      // Report delivery confirmation to server
      if (this.channel && this.status === 'connected') {
        this.channel.push('sms_delivered', { id: event.id });
      }

      // Update local storage log entry
      updateLogDelivery(event.id).then((updatedLogs) => {
        this.logs = updatedLogs;
        this.stats = calculateStats(this.logs);
        this.notify();
      });
    });
  }

  private setupNetworkMonitor() {
    if (this.netInfoUnsubscribe) {
      this.netInfoUnsubscribe();
    }

    let previousIsConnected: boolean | null = null;

    this.netInfoUnsubscribe = NetInfo.addEventListener((state) => {
      const isConnected = !!state.isConnected && !!state.isInternetReachable;

      if (previousIsConnected === false && isConnected && this.isServiceRunning) {
        // Network returned from offline state, reconnect immediately
        if (this.socket && !this.socket.isConnected()) {
          this.setStatus('connecting');
          this.updateNotificationText('Network restored · Reconnecting…');
          this.socket.disconnect();
          this.socket.connect();
        }
      }

      previousIsConnected = isConnected;
    });
  }

  private startTelemetryInterval() {
    this.clearTelemetryInterval();
    // A4: Send telemetry every 5 minutes while connected
    this.telemetryInterval = setInterval(() => {
      this.sendDeviceTelemetry();
    }, 5 * 60 * 1000);
  }

  private clearTelemetryInterval() {
    if (this.telemetryInterval) {
      clearInterval(this.telemetryInterval);
      this.telemetryInterval = null;
    }
  }

  private async sendDeviceTelemetry() {
    if (!this.channel || this.status !== 'connected') return;

    try {
      const info = await getDeviceInfo();
      const appVersion = Constants.expoConfig?.version || '1.0.0';

      this.channel.push('device_info', {
        battery: info.battery,
        is_charging: info.isCharging,
        signal: info.signal,
        app_version: appVersion,
      });
    } catch (err) {
      console.warn('[RelayManager] Error reporting telemetry:', err);
    }
  }

  private setStatus(newStatus: ConnectionStatus) {
    this.status = newStatus;
    this.notify();
  }

  private updateNotificationText(bodyText: string) {
    if (this.isServiceRunning) {
      updateForegroundNotification(bodyText).catch(() => {});
    }
  }

  private async disconnect(): Promise<void> {
    this.clearTelemetryInterval();

    if (this.channel) {
      try {
        this.channel.leave();
      } catch {}
      this.channel = null;
    }

    if (this.socket) {
      try {
        this.socket.disconnect();
      } catch {}
      this.socket = null;
    }
  }

  /**
   * One-off test connection for Setup screen
   */
  public async testConnection(
    url: string,
    token: string
  ): Promise<{ success: boolean; message: string }> {
    return new Promise((resolve) => {
      const testSocket = new Socket(url.trim(), {
        params: { token: token.trim() },
        timeout: 8000,
      });

      let isResolved = false;

      const finish = (success: boolean, message: string) => {
        if (isResolved) return;
        isResolved = true;
        try {
          testSocket.disconnect();
        } catch {}
        resolve({ success, message });
      };

      const timer = setTimeout(() => {
        finish(false, 'Connection timed out. Check server URL and network.');
      }, 9000);

      testSocket.onError(() => {
        clearTimeout(timer);
        finish(false, 'Cannot reach server. Check URL, network, or firewall.');
      });

      testSocket.onOpen(() => {
        const testChannel = testSocket.channel('gateway:phone', {});
        testChannel
          .join()
          .receive('ok', () => {
            clearTimeout(timer);
            try {
              testChannel.leave();
            } catch {}
            finish(true, 'Connected successfully to Phoenix gateway channel!');
          })
          .receive('error', (resp: any) => {
            clearTimeout(timer);
            if (resp?.reason === 'invalid_token' || resp?.reason === 'unauthorized') {
              finish(false, 'Invalid token: Authentication rejected by server.');
            } else {
              finish(
                false,
                `Channel rejected connection: ${resp?.reason || 'unauthorized'}`
              );
            }
          });
      });

      testSocket.connect();
    });
  }

  public async sendManualTestSms(
    to: string,
    body: string
  ): Promise<{ status: 'sent' | 'failed'; error?: string }> {
    const subId = this.settings.selectedSubId ?? undefined;
    const testId = `test-${Date.now()}`;
    const maskedPhone = maskPhoneNumber(to);

    const result = await sendSms(to, body, subId, testId);
    await this.recordLog(testId, maskedPhone, result.status, result.error);
    return result;
  }
}

export const relayManager = new RelayManager();
