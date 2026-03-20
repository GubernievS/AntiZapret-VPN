import api from './client'
import type {
  UserListResponse, UserCreateRequest, UserUpdateRequest, User, UserBlockResponse,
  SystemSettings, SystemSettingsUpdate, DashboardStats, ConfigListResponse
} from '../types'

export const adminApi = {
  // Users
  listUsers: (skip = 0, limit = 20, search?: string) =>
    api.get<UserListResponse>('/admin/users', {
      params: { skip, limit, ...(search ? { search } : {}) }
    }),

  getUser: (id: string) =>
    api.get<User>(`/admin/users/${id}`),

  getUserConfigs: (userId: string) =>
    api.get<ConfigListResponse>(`/admin/users/${userId}/configs`),

  createUser: (data: UserCreateRequest) =>
    api.post<User>('/admin/users', data),

  updateUser: (id: string, data: UserUpdateRequest) =>
    api.put<User>(`/admin/users/${id}`, data),

  toggleBlock: (id: string) =>
    api.patch<UserBlockResponse>(`/admin/users/${id}/block`),

  deleteUser: (id: string) =>
    api.delete(`/admin/users/${id}`),

  // Settings
  getSettings: () =>
    api.get<SystemSettings>('/admin/settings'),

  updateSettings: (data: SystemSettingsUpdate) =>
    api.patch<SystemSettings>('/admin/settings', data),

  // Dashboard
  getDashboard: () =>
    api.get<DashboardStats>('/admin/dashboard'),
}
