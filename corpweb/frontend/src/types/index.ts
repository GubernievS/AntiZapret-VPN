// === User types ===
export interface User {
  id: string
  email: string
  username: string
  role: 'admin' | 'user'
  auth_provider: 'local' | 'google'
  is_active: boolean
  created_at: string
  last_login: string | null
  config_count: number
}

export interface MeResponse extends User {
  max_configs: number
}

export interface UserCreateRequest {
  email: string
  username: string
  password: string
}

export interface UserUpdateRequest {
  email?: string
  username?: string
  is_active?: boolean
}

export interface UserListResponse {
  items: User[]
  total: number
}

// === Auth types ===
export interface LoginRequest {
  login: string
  password: string
}

export interface TokenResponse {
  access_token: string
  token_type: string
  expires_in: number
}

export interface ChangePasswordRequest {
  current_password: string
  new_password: string
}

// === Config types ===
export interface VPNConfig {
  id: string
  user_id: string
  client_name: string
  config_type: 'awg_antizapret' | 'awg_vpn'
  is_active: boolean
  created_at: string
  updated_at: string
  connection_status: 'connected' | 'disconnected' | null
}

export interface ConfigDetail extends VPNConfig {
  config_metadata: Record<string, unknown> | null
  config_file_path: string | null
  owner_username?: string
  owner_email?: string
}

export interface ConfigCreateRequest {
  config_type: 'awg_antizapret' | 'awg_vpn'
}

export interface ConfigListResponse {
  items: VPNConfig[]
  total: number
}

// === Settings types ===
export interface SystemSettings {
  max_configs_per_user: number
  updated_at: string
  updated_by: string | null
}

export interface SystemSettingsUpdate {
  max_configs_per_user: number
}

// === Dashboard types ===
export interface DashboardStats {
  users: {
    total: number
    active: number
    blocked: number
    google: number
    local: number
  }
  configs: {
    total: number
    active: number
    awg_antizapret: number
    awg_vpn: number
  }
  connections: {
    active: number
  }
  settings: {
    max_configs_per_user: number
  }
}
