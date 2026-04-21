import api from './client'

export type FileType =
  | 'include_hosts'
  | 'exclude_hosts'
  | 'include_ips'
  | 'exclude_ips'
  | 'allow_ips'
  | 'forward_ips'
  | 'include_adblock_hosts'
  | 'exclude_adblock_hosts'
  | 'remove_hosts'

export interface FileContentResponse {
  file_type: string
  content: string
}

export interface AntizapretSettings {
  ROUTE_ALL: string | null
  DISCORD_INCLUDE: string | null
  CLOUDFLARE_INCLUDE: string | null
  AMAZON_INCLUDE: string | null
  GOOGLE_INCLUDE: string | null
  WHATSAPP_INCLUDE: string | null
  TELEGRAM_INCLUDE: string | null
  HETZNER_INCLUDE: string | null
  DIGITALOCEAN_INCLUDE: string | null
  OVH_INCLUDE: string | null
  AKAMAI_INCLUDE: string | null
  ROBLOX_INCLUDE: string | null
  BLOCK_ADS: string | null
  CLEAR_HOSTS: string | null
  WIREGUARD_HOST: string | null
  SSH_PROTECTION: string | null
  ATTACK_PROTECTION: string | null
  TORRENT_GUARD: string | null
  RESTRICT_FORWARD: string | null
  ANTIZAPRET_DNS: string | null
  VPN_DNS: string | null
  ALTERNATIVE_CLIENT_IP: string | null
  ALTERNATIVE_FAKE_IP: string | null
  CLIENT_ISOLATION: string | null
  WARP_OUTBOUND: string | null
  WIREGUARD_BACKUP: string | null
  ESCAPE_ENABLED: string | null
}

export interface DoallResponse {
  status: string
  output: string
  changed?: number
}

export const antizapretApi = {
  getFile: (fileType: FileType) =>
    api.get<FileContentResponse>(`/antizapret/files/${fileType}`).then(r => r.data),

  saveFile: (fileType: FileType, content: string) =>
    api.put<FileContentResponse>(`/antizapret/files/${fileType}`, { content }).then(r => r.data),

  getSettings: () =>
    api.get<AntizapretSettings>('/antizapret/settings').then(r => r.data),

  updateSettings: (settings: Record<string, string>) =>
    api.patch<DoallResponse>('/antizapret/settings', { settings }).then(r => r.data),

  regenerateObfuscation: () =>
    api.post('/antizapret/obfuscation/regenerate').then(r => r.data),
}
