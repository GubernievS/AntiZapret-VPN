import { useState, useEffect, useCallback } from 'react'
import {
  Users, Shield, Wifi, RefreshCw, Loader2, CheckCircle, XCircle, AlertCircle,
  ArrowDownToLine, ArrowUpFromLine, Clock
} from 'lucide-react'
import { getDashboard } from '../api/dashboard'
import type { DashboardData, DashboardNode } from '../api/dashboard'

function formatBytes(bytesPerSec: number): string {
  if (bytesPerSec === 0) return '0 Б/с'
  const units = ['Б/с', 'КБ/с', 'МБ/с', 'ГБ/с']
  const i = Math.min(Math.floor(Math.log(bytesPerSec) / Math.log(1024)), units.length - 1)
  return `${(bytesPerSec / Math.pow(1024, i)).toFixed(1)} ${units[i]}`
}

function formatLastSeen(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  const diff = Math.floor((Date.now() - d.getTime()) / 1000)
  if (diff < 60) return `${diff}с назад`
  if (diff < 3600) return `${Math.floor(diff / 60)}м назад`
  if (diff < 86400) return `${Math.floor(diff / 3600)}ч назад`
  return d.toLocaleDateString('ru-RU')
}

function healthBadgeClass(health: string | null): string {
  switch (health) {
    case 'ok': return 'bg-green-100 text-green-700'
    case 'degraded': return 'bg-yellow-100 text-yellow-700'
    case 'down': return 'bg-red-100 text-red-700'
    default: return 'bg-gray-100 text-gray-500'
  }
}

function healthLabel(health: string | null): string {
  switch (health) {
    case 'ok': return 'Онлайн'
    case 'degraded': return 'Деградирован'
    case 'down': return 'Недоступен'
    default: return 'Неизвестно'
  }
}

function SyncIcon({ synced }: { synced: boolean }) {
  return synced
    ? <span title="Синхронизировано"><CheckCircle className="w-4 h-4 text-green-500" /></span>
    : <span title="Не синхронизировано"><XCircle className="w-4 h-4 text-yellow-500" /></span>
}

const SEGMENT_COLORS = [
  'bg-blue-500', 'bg-green-500', 'bg-purple-500', 'bg-orange-500',
  'bg-pink-500', 'bg-cyan-500', 'bg-yellow-500', 'bg-red-500',
]

function LoadDistributionBar({ nodes }: { nodes: DashboardNode[] }) {
  const total = nodes.reduce((sum, n) => sum + n.active_peers_antizapret + n.active_peers_vpn, 0)
  if (total === 0) {
    return <p className="text-sm text-gray-400 py-2">Нет активных клиентов</p>
  }

  return (
    <div className="space-y-3">
      <div className="flex h-4 rounded-full overflow-hidden gap-px">
        {nodes.map((node, i) => {
          const peers = node.active_peers_antizapret + node.active_peers_vpn
          const pct = (peers / total) * 100
          if (pct === 0) return null
          return (
            <div
              key={node.id}
              className={`${SEGMENT_COLORS[i % SEGMENT_COLORS.length]} transition-all`}
              style={{ width: `${pct}%` }}
              title={`${node.hostname}: ${peers} клиентов (${pct.toFixed(1)}%)`}
            />
          )
        })}
      </div>
      <div className="flex flex-wrap gap-x-4 gap-y-1">
        {nodes.map((node, i) => {
          const peers = node.active_peers_antizapret + node.active_peers_vpn
          const pct = ((peers / total) * 100).toFixed(1)
          return (
            <div key={node.id} className="flex items-center gap-1.5 text-xs text-gray-600">
              <div className={`w-2.5 h-2.5 rounded-sm ${SEGMENT_COLORS[i % SEGMENT_COLORS.length]}`} />
              <span className="font-mono">{node.hostname}</span>
              <span className="text-gray-400">{peers} ({pct}%)</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}

function NodeCard({ node }: { node: DashboardNode }) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4 min-w-[220px] flex-1">
      <div className="flex items-start justify-between gap-2 mb-3">
        <p className="text-sm font-semibold text-gray-900 font-mono truncate">{node.hostname}</p>
        <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap ${healthBadgeClass(node.health)}`}>
          {healthLabel(node.health)}
        </span>
      </div>

      <div className="space-y-1.5 text-xs text-gray-600">
        <div className="flex items-center justify-between">
          <span className="text-gray-400">Пиры AZ / VPN</span>
          <span className="font-medium text-gray-900">
            {node.active_peers_antizapret} / {node.active_peers_vpn}
          </span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-gray-400 flex items-center gap-1">
            <ArrowDownToLine className="w-3 h-3" /> Входящий
          </span>
          <span className="font-mono">{formatBytes(node.rx_bytes_per_sec)}</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-gray-400 flex items-center gap-1">
            <ArrowUpFromLine className="w-3 h-3" /> Исходящий
          </span>
          <span className="font-mono">{formatBytes(node.tx_bytes_per_sec)}</span>
        </div>
        <div className="flex items-center justify-between pt-1 border-t border-gray-100">
          <span className="flex items-center gap-1 text-gray-400">
            <SyncIcon synced={node.synced} />
            {node.synced ? 'Синхр.' : 'Не синхр.'}
          </span>
          <span className="flex items-center gap-1 text-gray-400">
            <Clock className="w-3 h-3" />
            {formatLastSeen(node.last_seen)}
          </span>
        </div>
      </div>
    </div>
  )
}

export default function AdminDashboardPage() {
  const [data, setData] = useState<DashboardData | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async (showRefresh = false) => {
    if (showRefresh) setRefreshing(true)
    else setLoading(true)
    setError('')
    try {
      const result = await getDashboard()
      setData(result)
    } catch {
      setError('Не удалось загрузить данные дашборда')
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [])

  useEffect(() => {
    load()
    const interval = setInterval(() => load(true), 30000)
    return () => clearInterval(interval)
  }, [load])

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
        <h1 className="text-2xl font-bold text-gray-900">Дашборд</h1>
        <button
          onClick={() => load(true)}
          disabled={refreshing}
          className="flex items-center gap-2 px-3 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 transition disabled:opacity-50"
        >
          <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
          Обновить
        </button>
      </div>

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0" />
          {error}
          <button onClick={() => setError('')} className="ml-auto text-red-500 hover:text-red-700">&times;</button>
        </div>
      )}

      {data && (
        <>
          {/* Totals */}
          <div className="grid gap-4 sm:grid-cols-3 mb-6">
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 bg-green-50 rounded-lg flex items-center justify-center">
                  <Wifi className="w-5 h-5 text-green-600" />
                </div>
                <span className="text-sm text-gray-600">Активных клиентов</span>
              </div>
              <p className="text-3xl font-bold text-gray-900">{data.totals.active_clients}</p>
            </div>
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 bg-blue-50 rounded-lg flex items-center justify-center">
                  <Shield className="w-5 h-5 text-blue-600" />
                </div>
                <span className="text-sm text-gray-600">Конфигураций всего</span>
              </div>
              <p className="text-3xl font-bold text-gray-900">{data.totals.total_configs}</p>
            </div>
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 bg-purple-50 rounded-lg flex items-center justify-center">
                  <Users className="w-5 h-5 text-purple-600" />
                </div>
                <span className="text-sm text-gray-600">Пользователей</span>
              </div>
              <p className="text-3xl font-bold text-gray-900">{data.totals.total_users}</p>
            </div>
          </div>

          {/* Node cards */}
          {data.nodes.length > 0 && (
            <div className="mb-6">
              <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wider mb-3">Ноды</h2>
              <div className="flex gap-4 flex-wrap">
                {data.nodes.map(node => (
                  <NodeCard key={node.id} node={node} />
                ))}
              </div>
            </div>
          )}

          {/* Load distribution */}
          {data.nodes.length > 0 && (
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <h2 className="font-semibold text-gray-900 mb-4">Распределение нагрузки</h2>
              <LoadDistributionBar nodes={data.nodes} />
            </div>
          )}
        </>
      )}
    </div>
  )
}
