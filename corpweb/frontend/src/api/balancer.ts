import api from './client'

export interface BalancerNode {
  id: number
  hostname: string
  ip: string
  health: string | null
  weight: number
  enabled: boolean
}

export const getBalancer = () =>
  api.get<{ nodes: BalancerNode[]; cp_ip: string }>('/nodes/balancer').then(r => r.data)

export const updateBalancer = (nodes: { ip: string; weight: number; enabled: boolean }[]) =>
  api.put<{ nodes: BalancerNode[]; cp_ip: string }>('/nodes/balancer', { nodes }).then(r => r.data)

export const updateCpIp = (cp_ip: string) =>
  api.put<{ cp_ip: string }>('/nodes/balancer/cp-ip', { cp_ip }).then(r => r.data)
