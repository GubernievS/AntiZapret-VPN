import { useState, useEffect } from 'react'
import { Save, Loader2, AlertCircle, CheckCircle2 } from 'lucide-react'
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
const is1 = (v: string | null | undefined) => v === '1'

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

  const set1 = (key: keyof AntizapretSettings, value: boolean) => {
    setSettings(prev => prev ? { ...prev, [key]: value ? '1' : '0' } : prev)
  }

  const setStr = (key: keyof AntizapretSettings, value: string) => {
    setSettings(prev => prev ? { ...prev, [key]: value } : prev)
  }

  const handleSaveWithApply = async () => {
    if (!settings) return
    setSaving(true)
    setSaveSuccess(false)
    setApplySuccess(false)
    setError(null)

    const payload: Record<string, string> = {}
    for (const [k, v] of Object.entries(settings)) {
      if (v !== null) payload[k] = v as string
    }
    try {
      await antizapretApi.updateSettings(payload)
      setSaveSuccess(true)

      // Wait for nodes to apply
      setApplying(true)
      const { waitForApply } = await import('../api/applyStatus')
      const result = await waitForApply('/root/antizapret/setup')
      setApplying(false)
      if (result.warning) {
        setError(`Применено с предупреждением: ${result.warning}`)
      } else {
        setApplySuccess(true)
        setTimeout(() => setApplySuccess(false), 5000)
      }
    } catch {
      setError('Ошибка при сохранении настроек')
    } finally {
      setSaving(false)
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

      {/* Backup ports */}
      <Section title="Резервные порты">
        <Toggle
          label="Открыть резервные порты UDP 540/580 для обхода блокировок (WIREGUARD_BACKUP)"
          value={isY(settings.WIREGUARD_BACKUP)}
          onChange={v => setBool('WIREGUARD_BACKUP', v)}
        />
        <p className="py-2 text-xs text-gray-500 leading-relaxed">
          При включении на нодах дополнительно слушаются UDP 540 → 51443 (antizapret) и UDP 580 → 51080 (vpn).
          В ЛК клиента появляется опция «Использовать резервный порт» при скачивании конфига/QR.
          Балансировщик DNAT всегда проксирует обе группы портов — изменение не влияет на его настройки.
        </p>
      </Section>

      {/* DNS */}
      <Section title="DNS">
        <Toggle
          label="DNS-сервер для AntiZapret-режима. Вкл = knot-resolver на ноде, Выкл = системный DNS (ANTIZAPRET_DNS)"
          value={is1(settings.ANTIZAPRET_DNS)}
          onChange={v => set1('ANTIZAPRET_DNS', v)}
        />
        <Toggle
          label="DNS-сервер для VPN-режима. Вкл = knot-resolver, Выкл = системный DNS (VPN_DNS)"
          value={is1(settings.VPN_DNS)}
          onChange={v => set1('VPN_DNS', v)}
        />
      </Section>

      {/* Clients */}
      <Section title="Клиенты">
        <Toggle
          label="Альтернативные подсети для клиентов (при конфликте с локальной сетью) (ALTERNATIVE_CLIENT_IP)"
          value={isY(settings.ALTERNATIVE_CLIENT_IP)}
          onChange={v => setBool('ALTERNATIVE_CLIENT_IP', v)}
        />
        <Toggle
          label="Альтернативные фейковые IP для DNS-резолвинга заблокированных доменов (ALTERNATIVE_FAKE_IP)"
          value={isY(settings.ALTERNATIVE_FAKE_IP)}
          onChange={v => setBool('ALTERNATIVE_FAKE_IP', v)}
        />
        <Toggle
          label="Изоляция клиентов друг от друга. Вкл = клиенты VPN не видят друг друга (CLIENT_ISOLATION)"
          value={isY(settings.CLIENT_ISOLATION)}
          onChange={v => setBool('CLIENT_ISOLATION', v)}
        />
      </Section>

      {/* WARP */}
      <Section title="WARP">
        <div className="py-2">
          <label className="text-sm text-gray-700 block mb-1">
            Маршрутизация исходящего трафика через Cloudflare WARP. Пусто = выключен (WARP_OUTBOUND)
          </label>
          <input
            type="text"
            value={settings.WARP_OUTBOUND ?? ''}
            onChange={e => setStr('WARP_OUTBOUND', e.target.value)}
            placeholder=""
            className="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
      </Section>

      {/* Actions */}
      <div className="flex items-center gap-3 flex-wrap">
        <button
          onClick={handleSaveWithApply}
          disabled={saving || applying}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {(saving || applying) ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
          {applying ? 'Применяю на нодах...' : 'Сохранить'}
        </button>

        {saveSuccess && !applySuccess && (
          <span className="flex items-center gap-1.5 text-sm text-green-600">
            <CheckCircle2 className="w-4 h-4" /> Сохранено, ожидаю подтверждение от нод...
          </span>
        )}
        {applySuccess && (
          <span className="flex items-center gap-1.5 text-sm text-green-600">
            <CheckCircle2 className="w-4 h-4" /> Применено на всех нодах
          </span>
        )}
      </div>

      <p className="text-xs text-gray-400">
        «Сохранить и применить» запускает <code className="bg-gray-100 px-1 rounded">/root/antizapret/doall.sh</code> — операция занимает 1–5 минут.
      </p>
    </div>
  )
}
