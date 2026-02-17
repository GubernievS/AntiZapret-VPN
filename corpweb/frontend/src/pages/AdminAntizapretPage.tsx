import { useState, useEffect } from 'react'
import { Save, Loader2, AlertCircle, CheckCircle2, Play } from 'lucide-react'
import { antizapretApi, type AntizapretSettings } from '../api/antizapret'

// ── Helper components ──────────────────────────────────────────────────────

function Toggle({
  label,
  value,
  onChange,
}: {
  label: string
  value: boolean
  onChange: (v: boolean) => void
}) {
  return (
    <label className="flex items-center justify-between py-2 cursor-pointer group">
      <span className="text-sm text-gray-700 group-hover:text-gray-900">{label}</span>
      <button
        type="button"
        role="switch"
        aria-checked={value}
        onClick={() => onChange(!value)}
        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 ${
          value ? 'bg-blue-600' : 'bg-gray-300'
        }`}
      >
        <span
          className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow transition-transform ${
            value ? 'translate-x-4' : 'translate-x-0.5'
          }`}
        />
      </button>
    </label>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 shadow-sm">
      <div className="px-4 py-3 border-b border-gray-100">
        <h3 className="text-sm font-semibold text-gray-800">{title}</h3>
      </div>
      <div className="px-4 divide-y divide-gray-50">{children}</div>
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────

const isY = (v: string | null | undefined) => v === 'y'

export default function AdminAntizapretPage() {
  const [settings, setSettings] = useState<AntizapretSettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [applying, setApplying] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saveSuccess, setSaveSuccess] = useState(false)
  const [applySuccess, setApplySuccess] = useState(false)

  useEffect(() => {
    antizapretApi
      .getSettings()
      .then(data => setSettings(data))
      .catch(() => setError('Не удалось загрузить настройки'))
      .finally(() => setLoading(false))
  }, [])

  const setBool = (key: keyof AntizapretSettings, value: boolean) => {
    setSettings(prev => prev ? { ...prev, [key]: value ? 'y' : 'n' } : prev)
  }

  const setStr = (key: keyof AntizapretSettings, value: string) => {
    setSettings(prev => prev ? { ...prev, [key]: value } : prev)
  }

  const handleSave = async () => {
    if (!settings) return
    setSaving(true)
    setSaveSuccess(false)
    setError(null)
    const payload: Record<string, string> = {}
    for (const [k, v] of Object.entries(settings)) {
      if (v !== null) payload[k] = v as string
    }
    try {
      await antizapretApi.updateSettings(payload)
      setSaveSuccess(true)
      setTimeout(() => setSaveSuccess(false), 3000)
    } catch {
      setError('Ошибка при сохранении настроек')
    } finally {
      setSaving(false)
    }
  }

  const handleSaveAndApply = async () => {
    await handleSave()
    if (error) return
    setApplying(true)
    setApplySuccess(false)
    try {
      await antizapretApi.runDoall()
      setApplySuccess(true)
      setTimeout(() => setApplySuccess(false), 5000)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Ошибка при применении изменений'
      setError(msg)
    } finally {
      setApplying(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 className="w-7 h-7 animate-spin text-gray-400" />
      </div>
    )
  }

  if (!settings) {
    return (
      <div className="flex items-center gap-2 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
        <AlertCircle className="w-5 h-5" />
        {error ?? 'Не удалось загрузить настройки AntiZapret'}
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Настройки AntiZapret</h1>
        <p className="text-sm text-gray-500 mt-1">
          Параметры из <code className="bg-gray-100 px-1 rounded text-xs">/root/antizapret/setup</code>.
          После сохранения нажмите «Применить» для применения изменений.
        </p>
      </div>

      {error && (
        <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
          <AlertCircle className="w-4 h-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Routing */}
      <Section title="Маршрутизация">
        <Toggle
          label="Весь трафик через VPN (ROUTE_ALL)"
          value={isY(settings.ROUTE_ALL)}
          onChange={v => setBool('ROUTE_ALL', v)}
        />
        <Toggle
          label="Ограничить форвардинг трафика (RESTRICT_FORWARD)"
          value={isY(settings.RESTRICT_FORWARD)}
          onChange={v => setBool('RESTRICT_FORWARD', v)}
        />
      </Section>

      {/* Services */}
      <Section title="Включить CDN / сервисы в список">
        <Toggle label="Discord" value={isY(settings.DISCORD_INCLUDE)} onChange={v => setBool('DISCORD_INCLUDE', v)} />
        <Toggle label="Cloudflare" value={isY(settings.CLOUDFLARE_INCLUDE)} onChange={v => setBool('CLOUDFLARE_INCLUDE', v)} />
        <Toggle label="Amazon AWS" value={isY(settings.AMAZON_INCLUDE)} onChange={v => setBool('AMAZON_INCLUDE', v)} />
        <Toggle label="Google" value={isY(settings.GOOGLE_INCLUDE)} onChange={v => setBool('GOOGLE_INCLUDE', v)} />
        <Toggle label="WhatsApp" value={isY(settings.WHATSAPP_INCLUDE)} onChange={v => setBool('WHATSAPP_INCLUDE', v)} />
        <Toggle label="Telegram" value={isY(settings.TELEGRAM_INCLUDE)} onChange={v => setBool('TELEGRAM_INCLUDE', v)} />
        <Toggle label="Hetzner" value={isY(settings.HETZNER_INCLUDE)} onChange={v => setBool('HETZNER_INCLUDE', v)} />
        <Toggle label="DigitalOcean" value={isY(settings.DIGITALOCEAN_INCLUDE)} onChange={v => setBool('DIGITALOCEAN_INCLUDE', v)} />
        <Toggle label="OVH" value={isY(settings.OVH_INCLUDE)} onChange={v => setBool('OVH_INCLUDE', v)} />
        <Toggle label="Akamai CDN" value={isY(settings.AKAMAI_INCLUDE)} onChange={v => setBool('AKAMAI_INCLUDE', v)} />
        <Toggle label="Roblox" value={isY(settings.ROBLOX_INCLUDE)} onChange={v => setBool('ROBLOX_INCLUDE', v)} />
      </Section>

      {/* Features */}
      <Section title="Дополнительные функции">
        <Toggle
          label="Блокировка рекламы (BLOCK_ADS)"
          value={isY(settings.BLOCK_ADS)}
          onChange={v => setBool('BLOCK_ADS', v)}
        />
        <Toggle
          label="Очистка казино/гемблинг-хостов (CLEAR_HOSTS)"
          value={isY(settings.CLEAR_HOSTS)}
          onChange={v => setBool('CLEAR_HOSTS', v)}
        />
        <Toggle
          label="Защита от торрентов (TORRENT_GUARD)"
          value={isY(settings.TORRENT_GUARD)}
          onChange={v => setBool('TORRENT_GUARD', v)}
        />
      </Section>

      {/* Security */}
      <Section title="Безопасность">
        <Toggle
          label="Защита SSH от брутфорса (SSH_PROTECTION)"
          value={isY(settings.SSH_PROTECTION)}
          onChange={v => setBool('SSH_PROTECTION', v)}
        />
        <Toggle
          label="Защита от атак (ATTACK_PROTECTION)"
          value={isY(settings.ATTACK_PROTECTION)}
          onChange={v => setBool('ATTACK_PROTECTION', v)}
        />
      </Section>

      {/* OpenVPN */}
      <Section title="OpenVPN">
        <Toggle
          label="Порты TCP 80/443 (OPENVPN_80_443_TCP)"
          value={isY(settings.OPENVPN_80_443_TCP)}
          onChange={v => setBool('OPENVPN_80_443_TCP', v)}
        />
        <Toggle
          label="Порты UDP 80/443 (OPENVPN_80_443_UDP)"
          value={isY(settings.OPENVPN_80_443_UDP)}
          onChange={v => setBool('OPENVPN_80_443_UDP', v)}
        />
        <div className="py-2">
          <label className="text-sm text-gray-700 block mb-1">Хост OpenVPN (OPENVPN_HOST)</label>
          <input
            type="text"
            value={settings.OPENVPN_HOST ?? ''}
            onChange={e => setStr('OPENVPN_HOST', e.target.value)}
            placeholder="vpn.example.com"
            className="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
      </Section>

      {/* WireGuard */}
      <Section title="WireGuard / AmneziaWG">
        <div className="py-2">
          <label className="text-sm text-gray-700 block mb-1">Хост WireGuard (WIREGUARD_HOST)</label>
          <input
            type="text"
            value={settings.WIREGUARD_HOST ?? ''}
            onChange={e => setStr('WIREGUARD_HOST', e.target.value)}
            placeholder="vpn.example.com"
            className="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
      </Section>

      {/* Actions */}
      <div className="flex items-center gap-3 flex-wrap">
        <button
          onClick={handleSave}
          disabled={saving || applying}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
          Сохранить
        </button>

        <button
          onClick={handleSaveAndApply}
          disabled={saving || applying}
          className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {applying ? <Loader2 className="w-4 h-4 animate-spin" /> : <Play className="w-4 h-4" />}
          {applying ? 'Применяется...' : 'Сохранить и применить'}
        </button>

        {saveSuccess && !applySuccess && (
          <span className="flex items-center gap-1.5 text-sm text-green-600">
            <CheckCircle2 className="w-4 h-4" /> Настройки сохранены
          </span>
        )}
        {applySuccess && (
          <span className="flex items-center gap-1.5 text-sm text-green-600">
            <CheckCircle2 className="w-4 h-4" /> Изменения применены
          </span>
        )}
      </div>

      <p className="text-xs text-gray-400">
        «Сохранить и применить» запускает <code className="bg-gray-100 px-1 rounded">/root/antizapret/doall.sh</code> — операция занимает 1–5 минут.
      </p>
    </div>
  )
}
