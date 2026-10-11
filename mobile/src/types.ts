export type ConnectionStatus =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'invalid_token'
  | 'permission_required';

export interface LogEntry {
  id: string;
  maskedRecipient: string;
  status: 'sent' | 'failed' | 'delivered';
  error?: string;
  timestamp: number;
}

export interface SimCardInfo {
  subscriptionId: number;
  displayName: string;
  carrierName: string;
  slotIndex: number;
  number?: string;
}

export interface RelaySettings {
  serverUrl: string;
  token: string;
  selectedSubId: number | null;
}

export interface RelayStats {
  sentToday: number;
  failedToday: number;
}

export interface SmsPayload {
  id: string;
  to: string;
  body: string;
}
