import { Socket, Channel } from 'phoenix';
import NetInfo from '@react-native-community/netinfo';
import Constants from 'expo-constants';
import {
  sendSms,
  addDeliveryListener,
  getDeviceInfo,
  setAutoStart,
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
  addPendingDeliveryId,
  calculateStats,
  getLogs,
  getPendingDeliveries,
  isServiceEnabled,
  loadSettings,
  maskPhoneNumber,
  removePendingDeliveryId,
  saveSettings,
  setServiceEnabled,
  updateLogDelivery,
} from './storage';
import { isValidE164, resultsFromLogs, SmsOutcome } from './relayLogic';
import {
  stopForegroundService,
  updateForegroundNotification,
} from './foregroundService';

export { getUrlSecurityWarning, isPrivateNetworkUrl, isValidE164 } from './relayLogic';

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
  // Final result per handled id, so a server retry of an id we already sent
  // gets the result again instead of a second SMS.
  // Rebuilt from the log on startup, so this survives app restarts.
  private resultsById = new Map<string, SmsOutcome>();
  // Delivery reports pushed but not yet acknowledged by the server
  private deliveriesInFlight = new Set<string>();
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

    // Populate handled ids and their results from existing logs, so a server
    // retry after an app restart gets the earlier result instead of hanging
    this.logs.forEach((log) => this.handledMessageIds.add(log.id));
    for (const [id, result] of resultsFromLogs(this.logs)) {
      if (!this.resultsById.has(id)) this.resultsById.set(id, result);
    }
    this.notify();
  }

  /**
   * Start the relay if it was running before the app was closed or the phone
   * rebooted. Called on app launch and from the boot task.
   */
  public async resumeIfEnabled(): Promise<void> {
    if (this.isServiceRunning || !(await isServiceEnabled())) return;
    if (!this.settings.serverUrl || !this.settings.token) return;
    await this.startService();
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
    await setServiceEnabled(true);
    setAutoStart(true);
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
    await setServiceEnabled(false);
    setAutoStart(false);
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
        this.flushPendingDeliveries();
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
      const known = this.resultsById.get(id);
      if (known) {
        // The server retried (e.g. our earlier result was lost): re-report it
        this.channel?.push('sms_result', { id, status: known.status, error: known.error });
      } else {
        console.warn(`[RelayManager] Ignoring duplicate SMS request id=${id} (still sending)`);
      }
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
      this.reportResult(msg.id, 'failed', errorMsg);
      await this.recordLog(msg.id, maskedPhone, 'failed', errorMsg);
      return;
    }

    // Validate message length cap (480 characters)
    if (msg.body.length > 480) {
      const errorMsg = 'Message body exceeds 480 characters limit';
      this.reportResult(msg.id, 'failed', errorMsg);
      await this.recordLog(msg.id, maskedPhone, 'failed', errorMsg);
      return;
    }

    try {
      const subId = this.settings.selectedSubId ?? undefined;
      const sendResult = await sendSms(msg.to, msg.body, subId, msg.id);

      // Report result back to server
      this.reportResult(msg.id, sendResult.status, sendResult.error || null);

      await this.recordLog(
        msg.id,
        maskedPhone,
        sendResult.status,
        sendResult.error
      );
    } catch (err: any) {
      const errorMsg = err?.message || 'Native SMS dispatch failure';
      this.reportResult(msg.id, 'failed', errorMsg);
      await this.recordLog(msg.id, maskedPhone, 'failed', errorMsg);
    }
  }

  private reportResult(id: string, status: 'sent' | 'failed', error: string | null) {
    this.resultsById.set(id, { status, error });
    // Bound memory: Maps iterate in insertion order, so drop the oldest
    if (this.resultsById.size > 500) {
      const oldest = this.resultsById.keys().next().value;
      if (oldest !== undefined) this.resultsById.delete(oldest);
    }
    this.channel?.push('sms_result', { id, status, error });
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

      // Buffer the report until the server acknowledges it, so reports that
      // arrive while offline are sent after reconnecting
      addPendingDeliveryId(event.id).then(() => this.flushPendingDeliveries());

      // Update local storage log entry
      updateLogDelivery(event.id).then((updatedLogs) => {
        this.logs = updatedLogs;
        this.stats = calculateStats(this.logs);
        this.notify();
      });
    });
  }

  private async flushPendingDeliveries() {
    const pending = await getPendingDeliveries();

    for (const id of pending) {
      if (!this.channel || this.status !== 'connected') return;
      if (this.deliveriesInFlight.has(id)) continue;

      this.deliveriesInFlight.add(id);
      this.channel
        .push('sms_delivered', { id })
        .receive('ok', () => {
          this.deliveriesInFlight.delete(id);
          removePendingDeliveryId(id);
        })
        .receive('error', () => this.deliveriesInFlight.delete(id))
        .receive('timeout', () => this.deliveriesInFlight.delete(id));
    }
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
