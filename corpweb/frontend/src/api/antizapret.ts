import api from './client'

export type FileType = 'include_hosts' | 'exclude_hosts' | 'include_ips'

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
  OPENVPN_80_443_TCP: string | null
  OPENVPN_80_443_UDP: string | null
  OPENVPN_HOST: string | null
  WIREGUARD_HOST: string | null
  SSH_PROTECTION: string | null
  ATTACK_PROTECTION: string | null
  TORRENT_GUARD: string | null
  RESTRICT_FORWARD: string | null
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

}
