import api from './client'

export interface LiveConnection {
  protocol: string
  interface: string
  client_name?: string
  public_key?: string
  endpoint?: string
  latest_handshake?: string
  connected_since?: string
  bytes_sent: number
  bytes_received: number
  is_active: boolean
  allowed_ips?: string
}

export interface MonitoringStats {
  active_connections: number
  total_bytes_sent: number
  total_bytes_received: number
}

export interface DailyTraffic {
  date: string
  bytes_sent: number
  bytes_received: number
  connections: number
}

export interface MonitoringOverview {
  stats: MonitoringStats
  live_connections: LiveConnection[]
  daily_traffic: DailyTraffic[]
}

export const monitoringApi = {
  getOverview: () =>
    api.get<MonitoringOverview>('/monitoring/overview'),

  getStats: () =>
    api.get<MonitoringStats>('/monitoring/stats'),

  getLiveConnections: () =>
    api.get<LiveConnection[]>('/monitoring/connections'),

  getDailyTraffic: (days = 7) =>
    api.get<DailyTraffic[]>('/monitoring/traffic', { params: { days } }),
}
