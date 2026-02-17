import { useState, useEffect, useCallback } from 'react'
import { Wifi, WifiOff, ArrowDownToLine, ArrowUpFromLine, RefreshCw, Loader2 } from 'lucide-react'
import { monitoringApi } from '../api/monitoring'
import type { MonitoringOverview } from '../api/monitoring'

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B'
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  const i = Math.floor(Math.log(bytes) / Math.log(1024))
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${units[i]}`
}

export default function MonitoringPage() {
  const [data, setData] = useState<MonitoringOverview | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async (showRefresh = false) => {
    if (showRefresh) setRefreshing(true)
    try {
      const { data: overview } = await monitoringApi.getOverview()
      setData(overview)
    } catch {
      // ignore
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [])

  useEffect(() => {
    load()
    const interval = setInterval(() => load(), 30000)
    return () => clearInterval(interval)
  }, [load])

  if (loading || !data) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
      </div>
    )
  }

  const activeConns = data.live_connections.filter(c => c.is_active)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Мониторинг</h1>
        <button
          onClick={() => load(true)}
          disabled={refreshing}
          className="flex items-center gap-2 px-3 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 transition disabled:opacity-50"
        >
          <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
          Обновить
        </button>
      </div>

      {/* Stats cards */}
      <div className="grid gap-4 sm:grid-cols-3 mb-6">
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 bg-green-50 rounded-lg flex items-center justify-center">
              <Wifi className="w-5 h-5 text-green-600" />
            </div>
            <span className="text-sm text-gray-600">Активных подключений</span>
          </div>
          <p className="text-3xl font-bold text-gray-900">{data.stats.active_connections}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 bg-blue-50 rounded-lg flex items-center justify-center">
              <ArrowDownToLine className="w-5 h-5 text-blue-600" />
            </div>
            <span className="text-sm text-gray-600">Получено</span>
          </div>
          <p className="text-3xl font-bold text-gray-900">{formatBytes(data.stats.total_bytes_received)}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 bg-purple-50 rounded-lg flex items-center justify-center">
              <ArrowUpFromLine className="w-5 h-5 text-purple-600" />
            </div>
            <span className="text-sm text-gray-600">Отправлено</span>
          </div>
          <p className="text-3xl font-bold text-gray-900">{formatBytes(data.stats.total_bytes_sent)}</p>
        </div>
      </div>

      {/* Daily traffic chart (simple bar chart) */}
      {data.daily_traffic.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-5 mb-6">
          <h3 className="font-semibold text-gray-900 mb-4">Трафик за 7 дней</h3>
          <div className="flex items-end gap-2 h-32">
            {data.daily_traffic.map((day) => {
              const total = day.bytes_sent + day.bytes_received
              const maxTraffic = Math.max(...data.daily_traffic.map(d => d.bytes_sent + d.bytes_received))
              const height = maxTraffic > 0 ? (total / maxTraffic) * 100 : 0

              return (
                <div key={day.date} className="flex-1 flex flex-col items-center gap-1">
                  <div className="w-full flex flex-col justify-end" style={{ height: '100px' }}>
                    <div
                      className="bg-blue-500 rounded-t w-full min-h-[2px]"
                      style={{ height: `${Math.max(height, 2)}%` }}
                      title={`${formatBytes(total)} (${day.connections} подкл.)`}
                    />
                  </div>
                  <span className="text-xs text-gray-400">
                    {new Date(day.date).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short' })}
                  </span>
                </div>
              )
            })}
          </div>
          <div className="flex items-center gap-4 mt-3 text-xs text-gray-500">
            <span>Суммарный трафик (отправлено + получено) по дням</span>
          </div>
        </div>
      )}

      {/* Live connections table */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-5 py-4 border-b border-gray-100">
          <h3 className="font-semibold text-gray-900">
            Подключения ({activeConns.length} активных / {data.live_connections.length} всего)
          </h3>
        </div>
        {data.live_connections.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-500">
            <WifiOff className="w-8 h-8 text-gray-300 mx-auto mb-2" />
            Нет подключений
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-gray-50">
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Статус</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Протокол</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Интерфейс</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Клиент</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Endpoint</th>
                  <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Получено</th>
                  <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Отправлено</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {data.live_connections.map((conn, i) => (
                  <tr key={i} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${
                        conn.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'
                      }`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${conn.is_active ? 'bg-green-500' : 'bg-gray-400'}`} />
                        {conn.is_active ? 'Online' : 'Offline'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 uppercase">{conn.protocol}</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{conn.interface}</td>
                    <td className="px-4 py-3 text-sm text-gray-900 font-mono">
                      {conn.client_name || conn.public_key?.slice(0, 16) || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 font-mono">{conn.endpoint || '—'}</td>
                    <td className="px-4 py-3 text-sm text-gray-600 text-right">{formatBytes(conn.bytes_received)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600 text-right">{formatBytes(conn.bytes_sent)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
