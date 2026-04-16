import { X, Activity, Clock, Network } from 'lucide-react'
import type { NodeInfo } from '../api/nodes'

interface NodeDetailProps {
  node: NodeInfo
  onClose: () => void
}

function formatDate(iso: string | null): string {
  if (!iso) return 'Нет данных'
  return new Date(iso).toLocaleString('ru-RU')
}

function healthLabel(health: string | null): string {
  switch (health) {
    case 'ok': return 'Онлайн'
    case 'degraded': return 'Деградирован'
    case 'down': return 'Недоступен'
    default: return 'Неизвестно'
  }
}

function healthBadgeClass(health: string | null): string {
  switch (health) {
    case 'ok': return 'bg-green-100 text-green-700'
    case 'degraded': return 'bg-yellow-100 text-yellow-700'
    case 'down': return 'bg-red-100 text-red-700'
    default: return 'bg-gray-100 text-gray-600'
  }
}

export default function NodeDetail({ node, onClose }: NodeDetailProps) {
  const activePeersAz = node.metrics?.active_peers_az ?? null
  const activePeersVpn = node.metrics?.active_peers_vpn ?? null
  const appliedFiles = node.applied_sha ? Object.entries(node.applied_sha) : []

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-2xl shadow-xl max-w-lg w-full p-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-5">
          <div>
            <h2 className="text-xl font-bold text-gray-900">{node.hostname}</h2>
            <p className="text-sm text-gray-500 font-mono">{node.private_ip}</p>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-500 hover:text-gray-700 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Status row */}
        <div className="grid grid-cols-3 gap-3 mb-5">
          <div className="bg-gray-50 rounded-xl p-3">
            <div className="flex items-center gap-1.5 text-xs text-gray-500 mb-1">
              <Activity className="w-3.5 h-3.5" />
              Статус
            </div>
            <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${healthBadgeClass(node.health)}`}>
              {healthLabel(node.health)}
            </span>
          </div>

          <div className="bg-gray-50 rounded-xl p-3">
            <div className="flex items-center gap-1.5 text-xs text-gray-500 mb-1">
              <Network className="w-3.5 h-3.5" />
              Пиры AZ / VPN
            </div>
            <p className="text-sm font-semibold text-gray-800">
              {activePeersAz !== null ? activePeersAz : '—'}
              {' / '}
              {activePeersVpn !== null ? activePeersVpn : '—'}
            </p>
          </div>

          <div className="bg-gray-50 rounded-xl p-3">
            <div className="flex items-center gap-1.5 text-xs text-gray-500 mb-1">
              <Clock className="w-3.5 h-3.5" />
              Последний пинг
            </div>
            <p className="text-xs font-medium text-gray-700">{formatDate(node.last_seen)}</p>
          </div>
        </div>

        {/* Synced files */}
        <div>
          <h3 className="text-sm font-semibold text-gray-700 mb-2">
            Синхронизированные файлы
            {appliedFiles.length > 0 && (
              <span className="ml-2 text-xs font-normal text-gray-400">({appliedFiles.length})</span>
            )}
          </h3>
          {appliedFiles.length === 0 ? (
            <p className="text-sm text-gray-400 py-3 text-center">Нет данных о файлах</p>
          ) : (
            <div className="bg-gray-50 rounded-xl overflow-hidden border border-gray-100">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-100">
                    <th className="text-left px-3 py-2 text-xs font-semibold text-gray-500 uppercase">Файл</th>
                    <th className="text-left px-3 py-2 text-xs font-semibold text-gray-500 uppercase">SHA-256</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {appliedFiles.map(([path, sha]) => (
                    <tr key={path} className="hover:bg-white transition">
                      <td className="px-3 py-2 font-mono text-xs text-gray-700 break-all">{path}</td>
                      <td className="px-3 py-2 font-mono text-xs text-gray-500">{sha.slice(0, 12)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div className="mt-5 flex justify-end">
          <button
            onClick={onClose}
            className="px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition font-medium text-sm"
          >
            Закрыть
          </button>
        </div>
      </div>
    </div>
  )
}
