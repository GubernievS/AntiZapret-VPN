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
  api.get<{ nodes: BalancerNode[] }>('/nodes/balancer').then(r => r.data)

export const updateBalancer = (nodes: { ip: string; weight: number; enabled: boolean }[]) =>
  api.put<{ nodes: BalancerNode[]; applied: boolean }>('/nodes/balancer', { nodes }).then(r => r.data)
