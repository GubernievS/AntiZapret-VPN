import { useState, useEffect, useCallback } from 'react'
import { RefreshCw, Loader2, WifiOff, ArrowDownToLine, ArrowUpFromLine } from 'lucide-react'
import { getConnections, getTraffic } from '../api/monitoring'
import type { ActiveConnection, TrafficStats } from '../api/monitoring'

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Б'
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ']
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${units[i]}`
}

function formatBytesPerSec(bps: number): string {
  if (bps === 0) return '0 Б/с'
  const units = ['Б/с', 'КБ/с', 'МБ/с', 'ГБ/с']
  const i = Math.min(Math.floor(Math.log(bps) / Math.log(1024)), units.length - 1)
  return `${(bps / Math.pow(1024, i)).toFixed(1)} ${units[i]}`
}

function formatHandshakeAge(seconds: number): string {
  if (seconds < 60) return `${seconds}с назад`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}м назад`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}ч назад`
  return `${Math.floor(seconds / 86400)}д назад`
}

function interfaceLabel(iface: string): string {
  if (iface.includes('az') || iface.includes('antizapret')) return 'AZ'
  if (iface.includes('vpn')) return 'VPN'
  return iface
}

export default function MonitoringPage() {
  const [connections, setConnections] = useState<ActiveConnection[]>([])
  const [traffic, setTraffic] = useState<TrafficStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [nodeFilter, setNodeFilter] = useState<string>('')

  const load = useCallback(async (showRefresh = false) => {
    if (showRefresh) setRefreshing(true)
    try {
      const [conns, traf] = await Promise.all([
        getConnections(nodeFilter || undefined),
        getTraffic(),
      ])
      setConnections(conns)
      setTraffic(traf)
    } catch {
      // ignore transient errors
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [nodeFilter])

  useEffect(() => {
    load()
    const interval = setInterval(() => load(true), 30000)
    return () => clearInterval(interval)
  }, [load])

  // Collect unique node names for the filter dropdown
  const allNodes = Array.from(
    new Set([
      ...(traffic?.per_node.map(n => n.hostname) ?? []),
      ...connections.map(c => c.node),
    ])
  ).sort()

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

      {/* Traffic per node */}
      {traffic && traffic.per_node.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-5 mb-6">
          <h2 className="font-semibold text-gray-900 mb-4">Трафик по нодам</h2>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {traffic.per_node.map(node => (
              <div key={node.hostname} className="bg-gray-50 rounded-lg p-3">
                <p className="text-sm font-medium text-gray-900 font-mono mb-2">{node.hostname}</p>
                <div className="flex items-center gap-4 text-xs text-gray-600">
                  <span className="flex items-center gap-1">
                    <ArrowDownToLine className="w-3 h-3 text-blue-500" />
                    {formatBytesPerSec(node.rx_bytes_per_sec)}
                  </span>
                  <span className="flex items-center gap-1">
                    <ArrowUpFromLine className="w-3 h-3 text-green-500" />
                    {formatBytesPerSec(node.tx_bytes_per_sec)}
                  </span>
                </div>
              </div>
            ))}
          </div>
          <div className="mt-3 pt-3 border-t border-gray-100 flex items-center gap-4 text-sm text-gray-600">
            <span className="text-gray-400">Суммарно:</span>
            <span className="flex items-center gap-1">
              <ArrowDownToLine className="w-3.5 h-3.5 text-blue-500" />
              {formatBytesPerSec(traffic.total_rx_bytes_per_sec)}
            </span>
            <span className="flex items-center gap-1">
              <ArrowUpFromLine className="w-3.5 h-3.5 text-green-500" />
              {formatBytesPerSec(traffic.total_tx_bytes_per_sec)}
            </span>
          </div>
        </div>
      )}

      {/* Connections */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between gap-4">
          <h2 className="font-semibold text-gray-900">
            Активные подключения ({connections.length})
          </h2>
          {allNodes.length > 0 && (
            <select
              value={nodeFilter}
              onChange={e => setNodeFilter(e.target.value)}
              className="text-sm border border-gray-300 rounded-lg px-3 py-1.5 outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="">Все ноды</option>
              {allNodes.map(n => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
          )}
        </div>

        {connections.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-500">
            <WifiOff className="w-8 h-8 text-gray-300 mx-auto mb-2" />
            Нет активных подключений
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-200">
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Клиент</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Нода</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Интерфейс</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Endpoint</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Хендшейк</th>
                  <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase">RX</th>
                  <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase">TX</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {connections.map((conn, i) => (
                  <tr key={i} className="hover:bg-gray-50 transition">
                    <td className="px-4 py-3 text-sm font-mono text-gray-900">
                      {conn.client_name || <span className="text-gray-400">—</span>}
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-gray-600">{conn.node}</td>
                    <td className="px-4 py-3">
                      <span className="inline-flex px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">
                        {interfaceLabel(conn.interface)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-gray-600">
                      {conn.endpoint || <span className="text-gray-400">—</span>}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-500">
                      {conn.handshake_age > 0 ? formatHandshakeAge(conn.handshake_age) : '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 text-right font-mono">{formatBytes(conn.rx_bytes)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600 text-right font-mono">{formatBytes(conn.tx_bytes)}</td>
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
