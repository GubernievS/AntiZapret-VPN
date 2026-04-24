import api from './client'

export interface DashboardNode {
  id: number
  hostname: string
  health: string | null
  active_peers_antizapret: number
  active_peers_vpn: number
  active_peers_az_escape: number
  active_peers_vpn_escape: number
  rx_bytes_per_sec: number
  tx_bytes_per_sec: number
  synced: boolean
  last_seen: string | null
}

export interface DashboardData {
  nodes: DashboardNode[]
  totals: { active_clients: number; total_configs: number; total_users: number }
}

export const getDashboard = () =>
  api.get<DashboardData>('/admin/dashboard').then(r => r.data)
