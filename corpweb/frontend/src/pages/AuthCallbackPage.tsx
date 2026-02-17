import { useEffect } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useAuthStore } from '../store/authStore'

/**
 * Handles Google OAuth callback redirect.
 * URL: /auth/callback?token=<access_token>
 */
export default function AuthCallbackPage() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const { setTokenFromCallback, fetchMe } = useAuthStore()

  useEffect(() => {
    const token = searchParams.get('token')

    if (token) {
      setTokenFromCallback(token)
      fetchMe().then(() => {
        navigate('/dashboard', { replace: true })
      })
    } else {
      navigate('/login', { replace: true })
    }
  }, [searchParams, setTokenFromCallback, fetchMe, navigate])

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto mb-4" />
        <p className="text-gray-600">Авторизация...</p>
      </div>
    </div>
  )
}
