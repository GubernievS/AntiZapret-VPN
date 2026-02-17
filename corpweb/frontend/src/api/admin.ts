import api from './client'
import type {
  UserListResponse, UserCreateRequest, UserUpdateRequest, User,
  SystemSettings, SystemSettingsUpdate, DashboardStats
} from '../types'

export const adminApi = {
  // Users
  listUsers: (skip = 0, limit = 100) =>
    api.get<UserListResponse>('/admin/users', { params: { skip, limit } }),

  createUser: (data: UserCreateRequest) =>
    api.post<User>('/admin/users', data),

  updateUser: (id: string, data: UserUpdateRequest) =>
    api.put<User>(`/admin/users/${id}`, data),

  toggleBlock: (id: string) =>
    api.patch<User>(`/admin/users/${id}/block`),

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
