import api from './client'
import type { ConfigCreateRequest, ConfigListResponse, ConfigDetail } from '../types'

export interface ClientLinks {
  google_play_url: string | null
  app_store_url: string | null
  apk_url: string | null
  windows_url: string | null
  wireguard_backup_enabled?: boolean
  escape_enabled?: boolean
}

export interface DownloadOptions {
  backup?: boolean
  bypass?: boolean
}

function buildParams(opts: DownloadOptions): Record<string, boolean> | undefined {
  const params: Record<string, boolean> = {}
  if (opts.backup) params.backup = true
  if (opts.bypass) params.bypass = true
  return Object.keys(params).length > 0 ? params : undefined
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

  download: (id: string, opts: DownloadOptions = {}) =>
    api.get<Blob>(`/configs/${id}/download`, {
      responseType: 'blob',
      params: buildParams(opts),
    }),

  getQR: (id: string, opts: DownloadOptions = {}) =>
    api.get<Blob>(`/configs/${id}/qr`, {
      responseType: 'blob',
      params: buildParams(opts),
    }),

  delete: (id: string) =>
    api.delete(`/configs/${id}`),

  getClientLinks: () =>
    api.get<ClientLinks>('/configs/client-links'),
}
