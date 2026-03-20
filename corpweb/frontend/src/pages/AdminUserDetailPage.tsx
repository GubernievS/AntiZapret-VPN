import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, Ban, Unlock, Download, Trash2, QrCode, Loader2, AlertCircle, AlertTriangle, Shield, Globe, X } from 'lucide-react'
import { adminApi } from '../api/admin'
import { configsApi } from '../api/configs'
import type { User, VPNConfig } from '../types'

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

export default function AdminUserDetailPage() {
  const { userId } = useParams<{ userId: string }>()
  const navigate = useNavigate()

  const [user, setUser] = useState<User | null>(null)
  const [configs, setConfigs] = useState<VPNConfig[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [warning, setWarning] = useState('')
  const [blockLoading, setBlockLoading] = useState(false)
  const [deletingId, setDeletingId] = useState<string | null>(null)

  // QR state
  const [qrConfig, setQrConfig] = useState<VPNConfig | null>(null)
  const [qrUrl, setQrUrl] = useState<string | null>(null)
  const [qrLoading, setQrLoading] = useState(false)
  const [qrError, setQrError] = useState<string | null>(null)
  const [qrType, setQrType] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    if (!userId) return
    try {
      const [userRes, configsRes] = await Promise.all([
        adminApi.getUser(userId),
        adminApi.getUserConfigs(userId),
      ])
      setUser(userRes.data)
      setConfigs(configsRes.data.items)
    } catch {
      setError('Не удалось загрузить данные пользователя')
    } finally {
      setLoading(false)
    }
  }, [userId])

  useEffect(() => { loadData() }, [loadData])

  const handleToggleBlock = async () => {
    if (!userId || !user) return
    setBlockLoading(true)
    setWarning('')
    setError('')
    try {
      const { data } = await adminApi.toggleBlock(userId)
      if (data.vpn_warnings && data.vpn_warnings.length > 0) {
        const action = data.is_active ? 'разблокирован' : 'заблокирован'
        setWarning(`Пользователь ${action}, но возникли ошибки VPN: ${data.vpn_warnings.join('; ')}`)
      }
      await loadData()
    } catch (err: unknown) {
      const message = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail || 'Ошибка'
      setError(message)
    } finally {
      setBlockLoading(false)
    }
  }

  const handleDownload = async (config: VPNConfig) => {
    try {
      const response = await configsApi.download(config.id)
      const disposition = response.headers['content-disposition'] || ''
      const match = disposition.match(/filename="?(.+?)"?$/i)
      const filename = match?.[1] || `${config.client_name}.zip`
      const url = URL.createObjectURL(response.data)
      const a = document.createElement('a')
      a.href = url
      a.download = filename
      a.click()
      URL.revokeObjectURL(url)
    } catch {
      setError('Ошибка скачивания конфигурации')
    }
  }

  const handleShowQR = async (config: VPNConfig) => {
    setQrConfig(config)
    setQrUrl(null)
    setQrError(null)
    setQrType(null)
    setQrLoading(true)
    try {
      const response = await configsApi.getQR(config.id)
      const url = URL.createObjectURL(response.data)
      setQrUrl(url)
      setQrType(response.headers['x-qr-type'] || 'config')
    } catch (err: unknown) {
      let message = 'Ошибка загрузки QR кода'
      try {
        const response = (err as { response?: { data?: Blob } }).response
        if (response?.data instanceof Blob) {
          const text = await response.data.text()
          const json = JSON.parse(text)
          if (json?.detail) message = json.detail
        }
      } catch {
        // ignore parse errors
      }
      setQrError(message)
    } finally {
      setQrLoading(false)
    }
  }

  const handleCloseQR = () => {
    if (qrUrl) URL.revokeObjectURL(qrUrl)
    setQrConfig(null)
    setQrUrl(null)
    setQrError(null)
    setQrType(null)
  }

  const handleDeleteConfig = async (configId: string) => {
    if (!confirm('Удалить конфигурацию? Это действие необратимо.')) return
    setDeletingId(configId)
    setError('')
    try {
      await configsApi.delete(configId)
      await loadData()
    } catch (err: unknown) {
      const message = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail || 'Ошибка удаления'
      setError(message)
    } finally {
      setDeletingId(null)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
      </div>
    )
  }

  if (!user) {
    return (
      <div className="text-center py-20">
        <p className="text-gray-500">Пользователь не найден</p>
        <button onClick={() => navigate('/admin/users')} className="mt-4 text-blue-600 hover:text-blue-700 text-sm font-medium">
          Назад к списку
        </button>
      </div>
    )
  }

  return (
    <div>
      {/* Back button */}
      <button
        onClick={() => navigate('/admin/users')}
        className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4 transition"
      >
        <ArrowLeft className="w-4 h-4" />
        Пользователи
      </button>

      {/* User info header */}
      <div className="bg-white rounded-xl border border-gray-200 p-5 mb-6">
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-xl font-bold text-gray-900">{user.username}</h1>
            <p className="text-sm text-gray-500 mt-0.5">{user.email}</p>
            <div className="flex items-center gap-2 mt-3">
              <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${
                user.is_active ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
              }`}>
                {user.is_active ? 'Активен' : 'Заблокирован'}
              </span>
              <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${
                user.auth_provider === 'google' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-700'
              }`}>
                {user.auth_provider === 'google' ? 'Google' : 'Local'}
              </span>
            </div>
            <div className="flex items-center gap-4 mt-3 text-xs text-gray-400">
              <span>Создан: {new Date(user.created_at).toLocaleDateString('ru-RU')}</span>
              <span>Вход: {user.last_login ? new Date(user.last_login).toLocaleDateString('ru-RU') : 'Не входил'}</span>
              <span>
                Конфигов: {user.config_count}
                {user.blocked_config_count > 0 && (
                  <span className="text-gray-400"> (+{user.blocked_config_count} заблок.)</span>
                )}
              </span>
            </div>
          </div>
          {user.role !== 'admin' && (
            <button
              onClick={handleToggleBlock}
              disabled={blockLoading}
              className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition disabled:opacity-50 ${
                user.is_active
                  ? 'bg-red-50 text-red-700 hover:bg-red-100'
                  : 'bg-green-50 text-green-700 hover:bg-green-100'
              }`}
            >
              {blockLoading ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : user.is_active ? (
                <Ban className="w-4 h-4" />
              ) : (
                <Unlock className="w-4 h-4" />
              )}
              {user.is_active ? 'Заблокировать' : 'Разблокировать'}
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          {error}
          <button onClick={() => setError('')} className="ml-auto text-red-500 hover:text-red-700">&times;</button>
        </div>
      )}

      {warning && (
        <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-700 flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 flex-shrink-0" />
          {warning}
          <button onClick={() => setWarning('')} className="ml-auto text-amber-500 hover:text-amber-700">&times;</button>
        </div>
      )}

      {/* Configs section */}
      <h2 className="text-lg font-semibold text-gray-900 mb-4">
        Конфигурации
        <span className="text-sm font-normal text-gray-400 ml-2">({configs.length})</span>
      </h2>

      {configs.length === 0 ? (
        <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
          <Shield className="w-10 h-10 text-gray-300 mx-auto mb-3" />
          <p className="text-sm text-gray-500">У пользователя нет конфигураций</p>
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
                  <div className="flex items-center gap-2">
                    {config.connection_status === 'connected' && (
                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-100 text-emerald-700">
                        <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                        Онлайн
                      </span>
                    )}
                    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                      config.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
                    }`}>
                      {config.is_active ? 'Активен' : 'Отключен'}
                    </span>
                  </div>
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
                    Скачать
                  </button>
                  <button
                    onClick={() => handleShowQR(config)}
                    title="Показать QR код для импорта в приложение"
                    className="flex items-center justify-center gap-2 px-3 py-2 bg-violet-50 text-violet-700 rounded-lg hover:bg-violet-100 transition text-sm font-medium"
                  >
                    <QrCode className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDeleteConfig(config.id)}
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

      {/* QR Code Modal */}
      {qrConfig && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={handleCloseQR}>
          <div className="bg-white rounded-2xl shadow-xl max-w-sm w-full p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <div>
                <h2 className="text-lg font-bold text-gray-900">QR код для импорта</h2>
                <p className="text-sm text-gray-500">{qrConfig.client_name}</p>
              </div>
              <button
                onClick={handleCloseQR}
                className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="flex items-center justify-center bg-gray-50 rounded-xl p-4 mb-4 min-h-[280px]">
              {qrLoading ? (
                <Loader2 className="w-8 h-8 text-violet-500 animate-spin" />
              ) : qrUrl ? (
                <img src={qrUrl} alt="QR код конфигурации" className="w-full max-w-[260px]" />
              ) : qrError ? (
                <div className="text-center px-2">
                  <p className="text-sm text-red-600 font-medium mb-1">Не удалось создать QR код</p>
                  <p className="text-xs text-gray-500">{qrError}</p>
                </div>
              ) : null}
            </div>

            {!qrError && qrType === 'download-link' ? (
              <p className="text-xs text-gray-500 text-center">
                Отсканируйте QR <span className="font-medium">камерой телефона</span>. Скачайте файл и импортируйте
                в <span className="font-medium">AmneziaWG</span> через «+» &rarr; «Импорт из файла»
              </p>
            ) : !qrError && qrUrl ? (
              <p className="text-xs text-gray-500 text-center">
                Откройте приложение <span className="font-medium">AmneziaWG</span> &rarr; «+» &rarr; «Сканировать QR код»
              </p>
            ) : null}
          </div>
        </div>
      )}
    </div>
  )
}
