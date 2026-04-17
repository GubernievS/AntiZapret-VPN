import api from './client'

export interface ActiveConnection {
  node: string
  interface: string
  client_name: string | null
  endpoint: string | null
  allowed_ips: string
  handshake_age: number
  rx_bytes: number
  tx_bytes: number
}

export interface TrafficStats {
  total_rx_bytes_per_sec: number
  total_tx_bytes_per_sec: number
  per_node: { hostname: string; rx_bytes_per_sec: number; tx_bytes_per_sec: number }[]
}

export const getConnections = (node?: string) =>
  api.get<ActiveConnection[]>('/monitoring/connections', { params: node ? { node } : {} }).then(r => r.data)

export const getTraffic = () =>
  api.get<TrafficStats>('/monitoring/traffic').then(r => r.data)
