import api from './client'
import type { ConfigCreateRequest, ConfigListResponse, ConfigDetail } from '../types'

export interface ClientLinks {
  google_play_url: string | null
  app_store_url: string | null
  apk_url: string | null
  windows_url: string | null
  wireguard_backup_enabled?: boolean
}

export const configsApi = {
  list: (skip?: number, limit?: number) =>
    api.get<ConfigListResponse>('/configs', {
      params: {
        ...(skip !== undefined ? { skip } : {}),
        ...(limit !== undefined ? { limit } : {}),
      }
    }),

  create: (data: ConfigCreateRequest) =>
    api.post('/configs', data),

  getDetail: (id: string) =>
    api.get<ConfigDetail>(`/configs/${id}`),

  download: (id: string, backup = false) =>
    api.get<Blob>(`/configs/${id}/download`, {
      responseType: 'blob',
      params: backup ? { backup: true } : undefined,
    }),

  getQR: (id: string, backup = false) =>
    api.get<Blob>(`/configs/${id}/qr`, {
      responseType: 'blob',
      params: backup ? { backup: true } : undefined,
    }),

  delete: (id: string) =>
    api.delete(`/configs/${id}`),

  getClientLinks: () =>
    api.get<ClientLinks>('/configs/client-links'),
}
