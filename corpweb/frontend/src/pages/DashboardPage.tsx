import { useState, useEffect, useCallback } from 'react'
import { Plus, Download, Trash2, Shield, Globe, Loader2, AlertCircle, Smartphone, Monitor, ExternalLink } from 'lucide-react'
import { configsApi } from '../api/configs'
import type { ClientLinks } from '../api/configs'
import { useAuthStore } from '../store/authStore'
import type { VPNConfig } from '../types'

const CONFIG_TYPE_LABELS: Record<string, { label: string; desc: string; icon: typeof Shield }> = {
  awg_antizapret: {
    label: 'AWG-AntiZapret',
    desc: 'Точечная маршрутизация — только заблокированные сайты через VPN',
    icon: Shield,
  },
  awg_vpn: {
    label: 'AWG-VPN',
    desc: 'Весь трафик устройства через VPN',
    icon: Globe,
  },
}

export default function DashboardPage() {
  const { user, fetchMe } = useAuthStore()
  const [configs, setConfigs] = useState<VPNConfig[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [creating, setCreating] = useState(false)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [clientLinks, setClientLinks] = useState<ClientLinks | null>(null)

  const loadConfigs = useCallback(async () => {
    try {
      const { data } = await configsApi.list()
      setConfigs(data.items)
    } catch {
      setError('Не удалось загрузить конфигурации')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadConfigs()
    configsApi.getClientLinks().then(({ data }) => setClientLinks(data)).catch(() => {})
  }, [loadConfigs])

  const handleCreate = async (configType: 'awg_antizapret' | 'awg_vpn') => {
    setCreating(true)
    setError('')
    try {
      await configsApi.create({ config_type: configType })
      await loadConfigs()
      await fetchMe()
      setShowCreateModal(false)
    } catch (err: unknown) {
      const message = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
        || 'Ошибка создания конфигурации'
      setError(message)
    } finally {
      setCreating(false)
    }
  }

  const handleDownload = async (config: VPNConfig) => {
    try {
      const { data } = await configsApi.download(config.id)
      const blob = new Blob([data], { type: 'text/plain' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `${config.client_name}.conf`
      a.click()
      URL.revokeObjectURL(url)
    } catch {
      setError('Ошибка скачивания конфигурации')
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Удалить конфигурацию? Это действие необратимо.')) return
    setDeletingId(id)
    setError('')
    try {
      await configsApi.delete(id)
      await loadConfigs()
      await fetchMe()
    } catch (err: unknown) {
      const message = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
        || 'Ошибка удаления'
      setError(message)
    } finally {
      setDeletingId(null)
    }
  }

  const canCreate = user && user.config_count < user.max_configs

  // Determine which client links are present
  const hasLinks = clientLinks && (
    clientLinks.google_play_url ||
    clientLinks.app_store_url ||
    clientLinks.apk_url ||
    clientLinks.windows_url
  )

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Мои конфигурации</h1>
          <p className="text-sm text-gray-500 mt-1">
            {user?.config_count ?? 0} из {user?.max_configs ?? 2} конфигураций
          </p>
        </div>
        {canCreate && (
          <button
            onClick={() => setShowCreateModal(true)}
            className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-lg transition font-medium"
          >
            <Plus className="w-4 h-4" />
            Создать конфиг
          </button>
        )}
      </div>

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          {error}
        </div>
      )}

      {configs.length === 0 ? (
        <div className="bg-white rounded-xl border border-gray-200 p-12 text-center">
          <Shield className="w-12 h-12 text-gray-300 mx-auto mb-4" />
          <h3 className="text-lg font-medium text-gray-900 mb-1">Нет конфигураций</h3>
          <p className="text-sm text-gray-500 mb-6">Создайте первый VPN конфиг для подключения</p>
          {canCreate && (
            <button
              onClick={() => setShowCreateModal(true)}
              className="inline-flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-lg transition font-medium"
            >
              <Plus className="w-4 h-4" />
              Создать конфиг
            </button>
          )}
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {configs.map((config) => {
            const typeInfo = CONFIG_TYPE_LABELS[config.config_type]
            const Icon = typeInfo?.icon ?? Shield
            return (
              <div key={config.id} className="bg-white rounded-xl border border-gray-200 p-5">
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 bg-blue-50 rounded-lg flex items-center justify-center">
                      <Icon className="w-5 h-5 text-blue-600" />
                    </div>
                    <div>
                      <h3 className="font-semibold text-gray-900">{config.client_name}</h3>
                      <p className="text-xs text-gray-500">{typeInfo?.label}</p>
                    </div>
                  </div>
                  <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                    config.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
                  }`}>
                    {config.is_active ? 'Активен' : 'Отключен'}
                  </span>
                </div>

                <p className="text-sm text-gray-500 mb-4">{typeInfo?.desc}</p>

                <div className="text-xs text-gray-400 mb-4">
                  Создан: {new Date(config.created_at).toLocaleDateString('ru-RU')}
                </div>

                <div className="flex gap-2">
                  <button
                    onClick={() => handleDownload(config)}
                    className="flex-1 flex items-center justify-center gap-2 px-3 py-2 bg-blue-50 text-blue-700 rounded-lg hover:bg-blue-100 transition text-sm font-medium"
                  >
                    <Download className="w-4 h-4" />
                    Скачать .conf
                  </button>
                  <button
                    onClick={() => handleDelete(config.id)}
                    disabled={deletingId === config.id}
                    className="flex items-center justify-center gap-2 px-3 py-2 bg-red-50 text-red-600 rounded-lg hover:bg-red-100 transition text-sm font-medium disabled:opacity-50"
                  >
                    {deletingId === config.id ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <Trash2 className="w-4 h-4" />
                    )}
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Client App Download Links */}
      {hasLinks && (
        <div className="mt-8">
          <h2 className="text-lg font-semibold text-gray-900 mb-1">Клиентские приложения</h2>
          <p className="text-sm text-gray-500 mb-4">
            Для использования конфигурации установите приложение AmneziaWG на своё устройство
          </p>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {clientLinks?.google_play_url && (
              <a
                href={clientLinks.google_play_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-3 p-4 bg-white border border-gray-200 rounded-xl hover:border-green-300 hover:bg-green-50/40 transition group"
              >
                <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <Smartphone className="w-5 h-5 text-green-700" />
                </div>
                <div className="min-w-0">
                  <p className="text-xs text-gray-500">Android</p>
                  <p className="text-sm font-medium text-gray-900 group-hover:text-green-700 transition flex items-center gap-1">
                    Google Play
                    <ExternalLink className="w-3 h-3 opacity-50" />
                  </p>
                </div>
              </a>
            )}

            {clientLinks?.app_store_url && (
              <a
                href={clientLinks.app_store_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-3 p-4 bg-white border border-gray-200 rounded-xl hover:border-blue-300 hover:bg-blue-50/40 transition group"
              >
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <Smartphone className="w-5 h-5 text-blue-700" />
                </div>
                <div className="min-w-0">
                  <p className="text-xs text-gray-500">iOS</p>
                  <p className="text-sm font-medium text-gray-900 group-hover:text-blue-700 transition flex items-center gap-1">
                    App Store
                    <ExternalLink className="w-3 h-3 opacity-50" />
                  </p>
                </div>
              </a>
            )}

            {clientLinks?.apk_url && (
              <a
                href={clientLinks.apk_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-3 p-4 bg-white border border-gray-200 rounded-xl hover:border-orange-300 hover:bg-orange-50/40 transition group"
              >
                <div className="w-10 h-10 bg-orange-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <Download className="w-5 h-5 text-orange-700" />
                </div>
                <div className="min-w-0">
                  <p className="text-xs text-gray-500">Android APK</p>
                  <p className="text-sm font-medium text-gray-900 group-hover:text-orange-700 transition flex items-center gap-1">
                    Скачать APK
                    <ExternalLink className="w-3 h-3 opacity-50" />
                  </p>
                </div>
              </a>
            )}

            {clientLinks?.windows_url && (
              <a
                href={clientLinks.windows_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-3 p-4 bg-white border border-gray-200 rounded-xl hover:border-indigo-300 hover:bg-indigo-50/40 transition group"
              >
                <div className="w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <Monitor className="w-5 h-5 text-indigo-700" />
                </div>
                <div className="min-w-0">
                  <p className="text-xs text-gray-500">Windows</p>
                  <p className="text-sm font-medium text-gray-900 group-hover:text-indigo-700 transition flex items-center gap-1">
                    Скачать .exe
                    <ExternalLink className="w-3 h-3 opacity-50" />
                  </p>
                </div>
              </a>
            )}
          </div>
        </div>
      )}

      {/* Create Config Modal */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl shadow-xl max-w-lg w-full p-6">
            <h2 className="text-xl font-bold text-gray-900 mb-2">Новая конфигурация</h2>
            <p className="text-sm text-gray-500 mb-6">Выберите тип VPN подключения</p>

            <div className="space-y-3">
              <button
                onClick={() => handleCreate('awg_antizapret')}
                disabled={creating}
                className="w-full p-4 border border-gray-200 rounded-xl hover:border-blue-300 hover:bg-blue-50/50 transition text-left disabled:opacity-50"
              >
                <div className="flex items-center gap-3 mb-1">
                  <Shield className="w-5 h-5 text-blue-600" />
                  <span className="font-semibold text-gray-900">AWG-AntiZapret</span>
                </div>
                <p className="text-sm text-gray-500 ml-8">
                  Раздельное туннелирование — только заблокированные сайты идут через VPN.
                  Остальной трафик — напрямую.
                </p>
              </button>

              <button
                onClick={() => handleCreate('awg_vpn')}
                disabled={creating}
                className="w-full p-4 border border-gray-200 rounded-xl hover:border-blue-300 hover:bg-blue-50/50 transition text-left disabled:opacity-50"
              >
                <div className="flex items-center gap-3 mb-1">
                  <Globe className="w-5 h-5 text-blue-600" />
                  <span className="font-semibold text-gray-900">AWG-VPN</span>
                </div>
                <p className="text-sm text-gray-500 ml-8">
                  Полный VPN — весь трафик устройства проходит через VPN-сервер.
                </p>
              </button>
            </div>

            {creating && (
              <div className="flex items-center justify-center gap-2 mt-4 text-sm text-blue-600">
                <Loader2 className="w-4 h-4 animate-spin" />
                Создание конфигурации...
              </div>
            )}

            <button
              onClick={() => setShowCreateModal(false)}
              disabled={creating}
              className="w-full mt-4 px-4 py-2.5 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition font-medium disabled:opacity-50"
            >
              Отмена
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
