import api from './client'
import type { LoginRequest, TokenResponse, MeResponse, ChangePasswordRequest } from '../types'

export const authApi = {
  login: (data: LoginRequest) =>
    api.post<TokenResponse>('/auth/login', data),

  refresh: () =>
    api.post<TokenResponse>('/auth/refresh'),

  logout: () =>
    api.post('/auth/logout'),

  getMe: () =>
    api.get<MeResponse>('/auth/me'),

  changePassword: (data: ChangePasswordRequest) =>
    api.post('/auth/change-password', data),
}
