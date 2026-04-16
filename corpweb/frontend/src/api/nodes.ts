import api from './client'

export interface NodeInfo {
  id: number
  hostname: string
  private_ip: string
  health: string | null
  last_seen: string | null
  metrics: Record<string, number> | null
  applied_sha: Record<string, string> | null
  enroll_token?: string
}

export interface NodeCreateResponse {
  id: number
  hostname: string
  enroll_token: string
}

export const listNodes = () =>
  api.get<NodeInfo[]>('/nodes').then(r => r.data)

export const getNode = (id: number) =>
  api.get<NodeInfo>(`/nodes/${id}`).then(r => r.data)

export const createNode = (hostname: string, private_ip: string) =>
  api.post<NodeCreateResponse>('/nodes', { hostname, private_ip }).then(r => r.data)

export const deleteNode = (id: number) =>
  api.delete(`/nodes/${id}`).then(r => r.data)
