import { create } from 'zustand'
import { authApi } from '../api/auth'
import type { MeResponse } from '../types'

interface AuthState {
  user: MeResponse | null
  isLoading: boolean
  isAuthenticated: boolean

  login: (login: string, password: string) => Promise<void>
  logout: () => Promise<void>
  fetchMe: () => Promise<void>
  setTokenFromCallback: (token: string) => void
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  isLoading: true,
  isAuthenticated: false,

  login: async (login: string, password: string) => {
    const { data } = await authApi.login({ login, password })
    localStorage.setItem('access_token', data.access_token)

    // Fetch user profile
    const { data: me } = await authApi.getMe()
    set({ user: me, isAuthenticated: true, isLoading: false })
  },

  logout: async () => {
    try {
      await authApi.logout()
    } catch {
      // Ignore errors on logout
    }
    localStorage.removeItem('access_token')
    set({ user: null, isAuthenticated: false, isLoading: false })
  },

  fetchMe: async () => {
    const token = localStorage.getItem('access_token')
    if (!token) {
      set({ user: null, isAuthenticated: false, isLoading: false })
      return
    }

    try {
      const { data } = await authApi.getMe()
      set({ user: data, isAuthenticated: true, isLoading: false })
    } catch {
      localStorage.removeItem('access_token')
      set({ user: null, isAuthenticated: false, isLoading: false })
    }
  },

  setTokenFromCallback: (token: string) => {
    localStorage.setItem('access_token', token)
  },
}))
