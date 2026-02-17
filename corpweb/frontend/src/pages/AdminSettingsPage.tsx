import { useState, useEffect } from 'react'
import { Save, Loader2, AlertCircle, CheckCircle2 } from 'lucide-react'
import { adminApi } from '../api/admin'
import type { SystemSettings } from '../types'

export default function AdminSettingsPage() {
  const [settings, setSettings] = useState<SystemSettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const [maxConfigs, setMaxConfigs] = useState(2)
  const [googlePlayUrl, setGooglePlayUrl] = useState('')
  const [appStoreUrl, setAppStoreUrl] = useState('')
  const [apkUrl, setApkUrl] = useState('')
  const [windowsUrl, setWindowsUrl] = useState('')

  useEffect(() => {
    const load = async () => {
      try {
        const { data } = await adminApi.getSettings()
        setSettings(data)
        setMaxConfigs(data.max_configs_per_user)
        setGooglePlayUrl(data.google_play_url ?? '')
        setAppStoreUrl(data.app_store_url ?? '')
        setApkUrl(data.apk_url ?? '')
        setWindowsUrl(data.windows_url ?? '')
      } catch {
        setError('Не удалось загрузить настройки')
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setError('')
    setSuccess('')
    try {
      const { data } = await adminApi.updateSettings({
        max_configs_per_user: maxConfigs,
        google_play_url: googlePlayUrl || null,
        app_store_url: appStoreUrl || null,
        apk_url: apkUrl || null,
        windows_url: windowsUrl || null,
      })
      setSettings(data)
      setSuccess('Настройки сохранены')
      setTimeout(() => setSuccess(''), 3000)
    } catch (err: unknown) {
      const message = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
        || 'Ошибка сохранения'
      setError(message)
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
      </div>
    )
  }

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Системные настройки</h1>

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4" />
          {error}
        </div>
      )}

      {success && (
        <div className="mb-4 p-3 bg-green-50 border border-green-200 rounded-lg text-sm text-green-700 flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4" />
          {success}
        </div>
      )}

      <form onSubmit={handleSave} className="space-y-6 max-w-lg">
        {/* VPN Config limit */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-base font-semibold text-gray-900 mb-4">Лимиты</h2>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Максимум конфигураций на пользователя
            </label>
            <input
              type="number"
              min={1}
              max={10}
              value={maxConfigs}
              onChange={(e) => setMaxConfigs(Number(e.target.value))}
              className="w-32 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
            />
            <p className="text-xs text-gray-500 mt-1">
              Лимит активных VPN конфигураций для каждого пользователя (1–10)
            </p>
          </div>
        </div>

        {/* Client download links */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-base font-semibold text-gray-900 mb-1">Ссылки на клиенты</h2>
          <p className="text-xs text-gray-500 mb-4">
            Отображаются пользователям на странице «Мои конфигурации». Оставьте пустым чтобы скрыть.
          </p>

          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Google Play (Android)
              </label>
              <input
                type="url"
                value={googlePlayUrl}
                onChange={(e) => setGooglePlayUrl(e.target.value)}
                placeholder="https://play.google.com/store/apps/..."
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                App Store (iOS)
              </label>
              <input
                type="url"
                value={appStoreUrl}
                onChange={(e) => setAppStoreUrl(e.target.value)}
                placeholder="https://apps.apple.com/..."
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                APK-файл (Android, прямая ссылка)
              </label>
              <input
                type="url"
                value={apkUrl}
                onChange={(e) => setApkUrl(e.target.value)}
                placeholder="https://example.com/app.apk"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Windows (.exe)
              </label>
              <input
                type="url"
                value={windowsUrl}
                onChange={(e) => setWindowsUrl(e.target.value)}
                placeholder="https://example.com/amneziawg-setup.exe"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm"
              />
            </div>
          </div>
        </div>

        {settings?.updated_at && (
          <p className="text-xs text-gray-400">
            Последнее обновление: {new Date(settings.updated_at).toLocaleString('ru-RU')}
            {settings.updated_by && ` (${settings.updated_by})`}
          </p>
        )}

        <button
          type="submit"
          disabled={saving}
          className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-lg transition font-medium disabled:opacity-50"
        >
          {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
          Сохранить
        </button>
      </form>
    </div>
  )
}
