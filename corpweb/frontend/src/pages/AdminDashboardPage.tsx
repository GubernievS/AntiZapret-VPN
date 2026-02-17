import { useState, useEffect } from 'react'
import { Users, Shield, Wifi, Settings, Loader2 } from 'lucide-react'
import { adminApi } from '../api/admin'
import type { DashboardStats } from '../types'

function StatCard({ icon: Icon, label, value, sub, color }: {
  icon: typeof Users
  label: string
  value: number
  sub?: string
  color: string
}) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-5">
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${color}`}>
          <Icon className="w-5 h-5" />
        </div>
        <span className="text-sm font-medium text-gray-600">{label}</span>
      </div>
      <p className="text-3xl font-bold text-gray-900">{value}</p>
      {sub && <p className="text-xs text-gray-500 mt-1">{sub}</p>}
    </div>
  )
}

export default function AdminDashboardPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const load = async () => {
      try {
        const { data } = await adminApi.getDashboard()
        setStats(data)
      } catch {
        // ignore
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  if (loading || !stats) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
      </div>
    )
  }

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Статистика</h1>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-8">
        <StatCard
          icon={Users}
          label="Пользователи"
          value={stats.users.total}
          sub={`Активных: ${stats.users.active} / Заблокировано: ${stats.users.blocked}`}
          color="bg-blue-50 text-blue-600"
        />
        <StatCard
          icon={Shield}
          label="Конфигурации"
          value={stats.configs.total}
          sub={`AntiZapret: ${stats.configs.awg_antizapret} / VPN: ${stats.configs.awg_vpn}`}
          color="bg-green-50 text-green-600"
        />
        <StatCard
          icon={Wifi}
          label="Подключения"
          value={stats.connections.active}
          sub="Активных сейчас"
          color="bg-purple-50 text-purple-600"
        />
        <StatCard
          icon={Settings}
          label="Макс. конфигов"
          value={stats.settings.max_configs_per_user}
          sub="На пользователя"
          color="bg-orange-50 text-orange-600"
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <h3 className="font-semibold text-gray-900 mb-4">Пользователи по типу</h3>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">Google OAuth</span>
              <div className="flex items-center gap-2">
                <div className="w-32 bg-gray-100 rounded-full h-2">
                  <div
                    className="bg-blue-500 rounded-full h-2"
                    style={{ width: `${stats.users.total ? (stats.users.google / stats.users.total) * 100 : 0}%` }}
                  />
                </div>
                <span className="text-sm font-medium text-gray-900 w-8 text-right">{stats.users.google}</span>
              </div>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">Локальные</span>
              <div className="flex items-center gap-2">
                <div className="w-32 bg-gray-100 rounded-full h-2">
                  <div
                    className="bg-gray-500 rounded-full h-2"
                    style={{ width: `${stats.users.total ? (stats.users.local / stats.users.total) * 100 : 0}%` }}
                  />
                </div>
                <span className="text-sm font-medium text-gray-900 w-8 text-right">{stats.users.local}</span>
              </div>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <h3 className="font-semibold text-gray-900 mb-4">Конфигурации по типу</h3>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">AWG-AntiZapret</span>
              <div className="flex items-center gap-2">
                <div className="w-32 bg-gray-100 rounded-full h-2">
                  <div
                    className="bg-green-500 rounded-full h-2"
                    style={{ width: `${stats.configs.total ? (stats.configs.awg_antizapret / stats.configs.total) * 100 : 0}%` }}
                  />
                </div>
                <span className="text-sm font-medium text-gray-900 w-8 text-right">{stats.configs.awg_antizapret}</span>
              </div>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">AWG-VPN</span>
              <div className="flex items-center gap-2">
                <div className="w-32 bg-gray-100 rounded-full h-2">
                  <div
                    className="bg-purple-500 rounded-full h-2"
                    style={{ width: `${stats.configs.total ? (stats.configs.awg_vpn / stats.configs.total) * 100 : 0}%` }}
                  />
                </div>
                <span className="text-sm font-medium text-gray-900 w-8 text-right">{stats.configs.awg_vpn}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
