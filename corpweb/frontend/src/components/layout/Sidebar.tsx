import { NavLink } from 'react-router-dom'
import { LayoutDashboard, Shield, Users, Settings, Wifi, FileText, SlidersHorizontal } from 'lucide-react'
import { useAuthStore } from '../../store/authStore'
import { cn } from '../../utils/cn'

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  cn(
    'flex items-center gap-3 px-4 py-2.5 rounded-lg text-sm font-medium transition',
    isActive
      ? 'bg-blue-50 text-blue-700'
      : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'
  )

interface SidebarProps {
  onNavigate?: () => void
}

export default function Sidebar({ onNavigate }: SidebarProps) {
  const { user } = useAuthStore()
  const isAdmin = user?.role === 'admin'

  return (
    <aside className="w-64 bg-white border-r border-gray-200 min-h-[calc(100vh-4rem)] p-4">
      <nav className="space-y-1" onClick={onNavigate}>
        <NavLink to="/dashboard" className={navLinkClass}>
          <LayoutDashboard className="w-5 h-5" />
          Мои конфиги
        </NavLink>

        {isAdmin && (
          <>
            <div className="pt-4 pb-2 px-4">
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">
                Администрирование
              </p>
            </div>
            <NavLink to="/admin/users" className={navLinkClass}>
              <Users className="w-5 h-5" />
              Пользователи
            </NavLink>
            <NavLink to="/admin/settings" className={navLinkClass}>
              <Settings className="w-5 h-5" />
              Настройки
            </NavLink>
            <NavLink to="/admin/dashboard" className={navLinkClass}>
              <Shield className="w-5 h-5" />
              Статистика
            </NavLink>
            <NavLink to="/admin/monitoring" className={navLinkClass}>
              <Wifi className="w-5 h-5" />
              Мониторинг
            </NavLink>
            <div className="pt-3 pb-1 px-4">
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">
                AntiZapret
              </p>
            </div>
            <NavLink to="/admin/antizapret/settings" className={navLinkClass}>
              <SlidersHorizontal className="w-5 h-5" />
              Настройки AZ
            </NavLink>
            <NavLink to="/admin/antizapret/files" className={navLinkClass}>
              <FileText className="w-5 h-5" />
              Редактор файлов
            </NavLink>
          </>
        )}
      </nav>
    </aside>
  )
}
