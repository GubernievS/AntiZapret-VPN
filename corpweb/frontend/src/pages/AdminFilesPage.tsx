import { useState, useEffect, useCallback } from 'react'
import { Save, RefreshCw, Loader2, AlertCircle, CheckCircle2 } from 'lucide-react'
import { antizapretApi, type FileType } from '../api/antizapret'

const FILE_TABS: { key: FileType; label: string; description: string }[] = [
  {
    key: 'include_hosts',
    label: 'Включить хосты',
    description: 'Хосты, принудительно добавляемые в список AntiZapret (по одному на строку)',
  },
  {
    key: 'exclude_hosts',
    label: 'Исключить хосты',
    description: 'Хосты, исключаемые из списка AntiZapret (по одному на строку)',
  },
  {
    key: 'include_ips',
    label: 'Включить IP',
    description: 'IP-адреса и подсети, принудительно добавляемые в маршрутизацию (по одному на строку)',
  },
  {
    key: 'exclude_ips',
    label: 'Исключить IP из VPN',
    description: 'IP-адреса и подсети которые НЕ будут маршрутизироваться через VPN. Формат: A.B.C.D/M, по одной записи на строку.',
  },
  {
    key: 'allow_ips',
    label: 'Разрешить прямой доступ',
    description: 'IP-адреса исключённые из защиты от атак (allowlist). Формат: A.B.C.D/M, по одной записи на строку.',
  },
  {
    key: 'forward_ips',
    label: 'Прямая маршрутизация IP',
    description: 'IP-адреса для прямой маршрутизации без проксирования. Формат: A.B.C.D/M, по одной записи на строку.',
  },
  {
    key: 'include_adblock_hosts',
    label: 'Блокировка рекламы (+)',
    description: 'Домены для дополнительной блокировки рекламы. По одному домену на строку.',
  },
  {
    key: 'exclude_adblock_hosts',
    label: 'Блокировка рекламы (−)',
    description: 'Домены исключённые из блокировки рекламы. По одному домену на строку.',
  },
  {
    key: 'remove_hosts',
    label: 'Исключить из обработки',
    description: 'Домены полностью исключённые из обработки AntiZapret. По одному домену на строку.',
  },
]

export default function AdminFilesPage() {
  const [activeTab, setActiveTab] = useState<FileType>('include_hosts')
  const [contents, setContents] = useState<Record<FileType, string>>(
    Object.fromEntries(FILE_TABS.map(t => [t.key, ''])) as Record<FileType, string>
  )
  const [loading, setLoading] = useState<Record<FileType, boolean>>(
    Object.fromEntries(FILE_TABS.map(t => [t.key, false])) as Record<FileType, boolean>
  )
  const [saving, setSaving] = useState(false)
  const [applying, setApplying] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saveSuccess, setSaveSuccess] = useState(false)
  const [applySuccess, setApplySuccess] = useState(false)

  const loadFile = useCallback(async (fileType: FileType) => {
    setLoading(prev => ({ ...prev, [fileType]: true }))
    setError(null)
    try {
      const data = await antizapretApi.getFile(fileType)
      setContents(prev => ({ ...prev, [fileType]: data.content }))
    } catch {
      setError(`Не удалось загрузить файл: ${fileType}`)
    } finally {
      setLoading(prev => ({ ...prev, [fileType]: false }))
    }
  }, [])

  useEffect(() => {
    FILE_TABS.forEach(t => loadFile(t.key))
  }, [loadFile])

  const handleSaveAndApply = async () => {
    setSaving(true)
    setSaveSuccess(false)
    setApplySuccess(false)
    setError(null)
    try {
      await antizapretApi.saveFile(activeTab, contents[activeTab])
      setSaveSuccess(true)
      setApplying(true)
      const { waitForApply } = await import('../api/applyStatus')
      const result = await waitForApply('/root/antizapret/config')
      if (result.warning) {
        setError(`Применено с предупреждением: ${result.warning}`)
      } else {
        setApplySuccess(true)
        setTimeout(() => setApplySuccess(false), 5000)
      }
    } catch {
      setError('Ошибка при сохранении')
    } finally {
      setSaving(false)
      setApplying(false)
    }
  }

  const activeTabInfo = FILE_TABS.find(t => t.key === activeTab)!

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Редактировать файлы</h1>
        <p className="text-sm text-gray-500 mt-1">
          Редактирование конфигурационных файлов AntiZapret. Сохранение автоматически применяет изменения на всех нодах.
        </p>
      </div>

      {error && (
        <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
          <AlertCircle className="w-4 h-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex gap-4">
          {FILE_TABS.map(tab => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={`py-2 px-1 border-b-2 text-sm font-medium transition-colors ${
                activeTab === tab.key
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Editor */}
      <div className="bg-white rounded-xl border border-gray-200 shadow-sm">
        <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
          <div>
            <p className="text-sm font-medium text-gray-700">{activeTabInfo.label}</p>
            <p className="text-xs text-gray-400 mt-0.5">{activeTabInfo.description}</p>
          </div>
          <button
            onClick={() => loadFile(activeTab)}
            disabled={loading[activeTab]}
            className="p-1.5 text-gray-400 hover:text-gray-600 rounded-lg hover:bg-gray-100"
            title="Перезагрузить"
          >
            <RefreshCw className={`w-4 h-4 ${loading[activeTab] ? 'animate-spin' : ''}`} />
          </button>
        </div>

        {loading[activeTab] ? (
          <div className="flex items-center justify-center py-16">
            <Loader2 className="w-6 h-6 animate-spin text-gray-400" />
          </div>
        ) : (
          <textarea
            value={contents[activeTab]}
            onChange={e => setContents(prev => ({ ...prev, [activeTab]: e.target.value }))}
            rows={16}
            spellCheck={false}
            className="w-full p-4 font-mono text-sm text-gray-800 bg-gray-50 rounded-b-xl resize-y focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-inset"
            placeholder="# Одна запись на строку"
          />
        )}
      </div>

      {/* Actions */}
      <div className="flex items-center gap-3">
        <button
          onClick={handleSaveAndApply}
          disabled={saving || applying || loading[activeTab]}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {(saving || applying) ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
          {applying ? 'Применяю на нодах...' : 'Сохранить'}
        </button>

        {saveSuccess && (
          <span className="flex items-center gap-1.5 text-sm text-green-600">
            <CheckCircle2 className="w-4 h-4" /> Файл сохранён
          </span>
        )}
        {applySuccess && (
          <span className="flex items-center gap-1.5 text-sm text-green-600">
            <CheckCircle2 className="w-4 h-4" /> Изменения применены
          </span>
        )}
      </div>

      <div className="text-xs text-gray-400 space-y-0.5">
        <p>• Файлы расположены в <code className="bg-gray-100 px-1 rounded">/root/antizapret/config/</code></p>
        <p>• «Применить» запускает <code className="bg-gray-100 px-1 rounded">/root/antizapret/doall.sh</code> — операция занимает 1–5 минут</p>
      </div>
    </div>
  )
}
