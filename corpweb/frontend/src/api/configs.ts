import api from './client'
import type { ConfigCreateRequest, ConfigListResponse, ConfigDetail } from '../types'

export const configsApi = {
  list: () =>
    api.get<ConfigListResponse>('/configs'),

  create: (data: ConfigCreateRequest) =>
    api.post('/configs', data),

  getDetail: (id: string) =>
    api.get<ConfigDetail>(`/configs/${id}`),

  download: (id: string) =>
    api.get<string>(`/configs/${id}/download`, { responseType: 'text' }),

  delete: (id: string) =>
    api.delete(`/configs/${id}`),
}
