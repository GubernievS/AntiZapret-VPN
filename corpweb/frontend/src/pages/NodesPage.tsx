import { useState, useEffect, useCallback } from 'react'
import { ServerCog, Trash2, Info, Loader2, AlertCircle, RefreshCw } from 'lucide-react'
import { listNodes, deleteNode } from '../api/nodes'
import type { NodeInfo } from '../api/nodes'
import AddNodeModal from '../components/AddNodeModal'
import NodeDetail from '../components/NodeDetail'

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

function formatLastSeen(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return d.toLocaleString('ru-RU')
}

function activePeers(node: NodeInfo): string {
  if (!node.metrics) return '—'
  const az = node.metrics.active_peers_antizapret ?? null
  const vpn = node.metrics.active_peers_vpn ?? null
  if (az === null && vpn === null) return '—'
  return `${az ?? '?'} / ${vpn ?? '?'}`
}

export default function NodesPage() {
  const [nodes, setNodes] = useState<NodeInfo[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [actionId, setActionId] = useState<number | null>(null)

  const [showAddModal, setShowAddModal] = useState(false)
  const [detailNode, setDetailNode] = useState<NodeInfo | null>(null)

  const loadNodes = useCallback(async () => {
    setError('')
    try {
      const data = await listNodes()
      setNodes(data)
    } catch {
      setError('Не удалось загрузить ноды')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadNodes()
  }, [loadNodes])

  const handleDelete = async (node: NodeInfo) => {
    if (!confirm(`Удалить ноду "${node.hostname}"?`)) return
    setActionId(node.id)
    try {
      await deleteNode(node.id)
      await loadNodes()
    } catch (err: unknown) {
      const detail = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
      setError(detail || 'Ошибка удаления')
    } finally {
      setActionId(null)
    }
  }

  const handleNodeCreated = () => {
    loadNodes()
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
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Ноды</h1>
        <div className="flex items-center gap-2">
          <button
            onClick={() => { setLoading(true); loadNodes() }}
            title="Обновить"
            className="p-2.5 border border-gray-300 rounded-lg hover:bg-gray-50 text-gray-600 transition"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
          <button
            onClick={() => setShowAddModal(true)}
            className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-lg transition font-medium"
          >
            <ServerCog className="w-4 h-4" />
            Добавить ноду
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0" />
          {error}
          <button onClick={() => setError('')} className="ml-auto text-red-500 hover:text-red-700">&times;</button>
        </div>
      )}

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Hostname</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">IP</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Статус</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Пиры AZ / VPN</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Последний пинг</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Действия</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {nodes.map(node => (
                <tr key={node.id} className="hover:bg-gray-50 transition">
                  <td className="px-4 py-3">
                    <p className="text-sm font-medium text-gray-900 font-mono">{node.hostname}</p>
                    <p className="text-xs text-gray-400">#{node.id}</p>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600 font-mono">{node.private_ip}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${healthBadgeClass(node.health)}`}>
                      {healthLabel(node.health)}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">{activePeers(node)}</td>
                  <td className="px-4 py-3 text-sm text-gray-500">{formatLastSeen(node.last_seen)}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-end gap-1">
                      <button
                        onClick={() => setDetailNode(node)}
                        title="Детали"
                        className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-500 hover:text-gray-700 transition"
                      >
                        <Info className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => handleDelete(node)}
                        disabled={actionId === node.id}
                        title="Удалить"
                        className="p-1.5 rounded-lg hover:bg-red-50 text-gray-500 hover:text-red-600 transition disabled:opacity-50"
                      >
                        {actionId === node.id
                          ? <Loader2 className="w-4 h-4 animate-spin" />
                          : <Trash2 className="w-4 h-4" />
                        }
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {nodes.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-4 py-10 text-center text-sm text-gray-400">
                    Нет зарегистрированных нод
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showAddModal && (
        <AddNodeModal
          onClose={() => setShowAddModal(false)}
          onCreated={handleNodeCreated}
        />
      )}

      {detailNode && (
        <NodeDetail
          node={detailNode}
          onClose={() => setDetailNode(null)}
        />
      )}
    </div>
  )
}
