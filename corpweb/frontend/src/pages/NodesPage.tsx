import { useState, useEffect, useCallback } from 'react'
import { ServerCog, Trash2, Info, Loader2, AlertCircle, RefreshCw, CheckCircle } from 'lucide-react'
import { listNodes, deleteNode } from '../api/nodes'
import type { NodeInfo } from '../api/nodes'
import { getBalancer, updateBalancer } from '../api/balancer'
import type { BalancerNode } from '../api/balancer'
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

  // Balancer state
  const [balancerNodes, setBalancerNodes] = useState<BalancerNode[]>([])
  const [balancerEdits, setBalancerEdits] = useState<Record<string, { weight: number; enabled: boolean }>>({})
  const [balancerLoading, setBalancerLoading] = useState(false)
  const [balancerSaving, setBalancerSaving] = useState(false)
  const [balancerError, setBalancerError] = useState('')
  const [balancerSuccess, setBalancerSuccess] = useState(false)
  const [cpIp, setCpIp] = useState('')
  const [cpIpEditing, setCpIpEditing] = useState(false)
  const [cpIpDraft, setCpIpDraft] = useState('')

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

  const loadBalancer = useCallback(async () => {
    setBalancerLoading(true)
    try {
      const result = await getBalancer()
      setBalancerNodes(result.nodes)
      const edits: Record<string, { weight: number; enabled: boolean }> = {}
      for (const n of result.nodes) {
        edits[n.ip] = { weight: n.weight, enabled: n.enabled }
      }
      setBalancerEdits(edits)
      if (result.cp_ip) {
        setCpIp(result.cp_ip)
        setCpIpDraft(result.cp_ip)
      }
    } catch {
      // ignore — balancer section will just show nothing
    } finally {
      setBalancerLoading(false)
    }
  }, [])

  useEffect(() => {
    loadNodes()
    loadBalancer()
  }, [loadNodes, loadBalancer])

  const handleSaveBalancer = async () => {
    setBalancerError('')
    setBalancerSuccess(false)

    // Validate: enabled weights sum to 100
    const enabledNodes = balancerNodes.filter(n => balancerEdits[n.ip]?.enabled)
    const totalWeight = enabledNodes.reduce((sum, n) => sum + (balancerEdits[n.ip]?.weight ?? 0), 0)
    if (enabledNodes.length > 0 && totalWeight !== 100) {
      setBalancerError(`Сумма весов включённых нод должна быть 100%. Сейчас: ${totalWeight}%`)
      return
    }

    setBalancerSaving(true)
    try {
      const payload = balancerNodes.map(n => ({
        ip: n.ip,
        weight: balancerEdits[n.ip]?.weight ?? n.weight,
        enabled: balancerEdits[n.ip]?.enabled ?? n.enabled,
      }))
      const result = await updateBalancer(payload)
      setBalancerNodes(result.nodes)
      const edits: Record<string, { weight: number; enabled: boolean }> = {}
      for (const n of result.nodes) {
        edits[n.ip] = { weight: n.weight, enabled: n.enabled }
      }
      setBalancerEdits(edits)
      setBalancerSuccess(true)
      setTimeout(() => setBalancerSuccess(false), 3000)
    } catch (err: unknown) {
      const detail = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
      setBalancerError(detail || 'Ошибка сохранения балансировки')
    } finally {
      setBalancerSaving(false)
    }
  }

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
            onClick={() => { loadNodes(); loadBalancer() }}
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

      {/* Balancer section */}
      <div className="mt-8">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">Балансировка</h2>
          {balancerLoading && <Loader2 className="w-4 h-4 text-blue-600 animate-spin" />}
        </div>

        {/* CP IP */}
        <div className="mb-4 p-3 bg-gray-50 border border-gray-200 rounded-lg flex items-center gap-3">
          <span className="text-sm text-gray-600 whitespace-nowrap">IP балансировщика:</span>
          {cpIpEditing ? (
            <>
              <input
                type="text"
                value={cpIpDraft}
                onChange={e => setCpIpDraft(e.target.value)}
                className="px-2 py-1 border border-gray-300 rounded text-sm font-mono w-40"
                placeholder="92.118.85.140"
              />
              <button
                onClick={async () => {
                  try {
                    const { updateCpIp } = await import('../api/balancer')
                    await updateCpIp(cpIpDraft)
                    setCpIp(cpIpDraft)
                    setCpIpEditing(false)
                  } catch { setBalancerError('Ошибка сохранения IP') }
                }}
                className="px-2 py-1 bg-blue-600 text-white text-xs rounded hover:bg-blue-700"
              >Сохранить</button>
              <button
                onClick={() => { setCpIpDraft(cpIp); setCpIpEditing(false) }}
                className="px-2 py-1 text-gray-500 text-xs hover:text-gray-700"
              >Отмена</button>
            </>
          ) : (
            <>
              <span className="text-sm font-mono font-semibold text-gray-900">{cpIp || 'не задан'}</span>
              <button
                onClick={() => setCpIpEditing(true)}
                className="text-xs text-blue-600 hover:underline"
              >Изменить</button>
            </>
          )}
        </div>

        {balancerError && (
          <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0" />
            {balancerError}
            <button onClick={() => setBalancerError('')} className="ml-auto text-red-500 hover:text-red-700">&times;</button>
          </div>
        )}

        {balancerSuccess && (
          <div className="mb-4 p-3 bg-green-50 border border-green-200 rounded-lg text-sm text-green-700 flex items-center gap-2">
            <CheckCircle className="w-4 h-4 shrink-0" />
            Балансировка сохранена и применена.
          </div>
        )}

        {balancerNodes.length === 0 && !balancerLoading ? (
          <div className="bg-white rounded-xl border border-gray-200 px-4 py-8 text-center text-sm text-gray-400">
            Нет нод для балансировки
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-200">
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Hostname</th>
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">IP</th>
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Статус</th>
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Вес, %</th>
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase">Включена</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {balancerNodes.map(node => {
                    const edit = balancerEdits[node.ip] ?? { weight: node.weight, enabled: node.enabled }
                    return (
                      <tr key={node.id} className="hover:bg-gray-50 transition">
                        <td className="px-4 py-3 text-sm font-medium text-gray-900 font-mono">{node.hostname}</td>
                        <td className="px-4 py-3 text-sm text-gray-600 font-mono">{node.ip}</td>
                        <td className="px-4 py-3">
                          <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${healthBadgeClass(node.health)}`}>
                            {node.health === 'ok' ? 'Онлайн' : node.health === 'degraded' ? 'Деградирован' : node.health === 'down' ? 'Недоступен' : 'Неизвестно'}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <input
                            type="number"
                            min={0}
                            max={100}
                            value={edit.weight}
                            onChange={e => {
                              const val = Math.max(0, Math.min(100, parseInt(e.target.value) || 0))
                              setBalancerEdits(prev => ({
                                ...prev,
                                [node.ip]: { ...edit, weight: val },
                              }))
                            }}
                            className="w-20 px-2 py-1 border border-gray-300 rounded-lg text-sm outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                          />
                        </td>
                        <td className="px-4 py-3">
                          <button
                            type="button"
                            onClick={() =>
                              setBalancerEdits(prev => ({
                                ...prev,
                                [node.ip]: { ...edit, enabled: !edit.enabled },
                              }))
                            }
                            className={`relative inline-flex h-5 w-9 items-center rounded-full transition ${
                              edit.enabled ? 'bg-blue-600' : 'bg-gray-300'
                            }`}
                          >
                            <span
                              className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow transition ${
                                edit.enabled ? 'translate-x-4' : 'translate-x-1'
                              }`}
                            />
                          </button>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
            <div className="px-4 py-3 border-t border-gray-100 flex items-center justify-between">
              <p className="text-xs text-gray-400">
                Сумма весов включённых нод должна равняться 100%
              </p>
              <button
                onClick={handleSaveBalancer}
                disabled={balancerSaving}
                className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition disabled:opacity-50"
              >
                {balancerSaving && <Loader2 className="w-4 h-4 animate-spin" />}
                Сохранить
              </button>
            </div>
          </div>
        )}
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
