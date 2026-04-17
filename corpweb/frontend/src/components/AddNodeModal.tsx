import { useState, useEffect, useRef } from 'react'
import { X, Copy, Check, Loader2, CheckCircle, AlertCircle } from 'lucide-react'
import { createNode, getNode } from '../api/nodes'

interface AddNodeModalProps {
  onClose: () => void
  onCreated: () => void
}

type Step = 1 | 2 | 3

const CP_URL = window.location.origin

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <button
      onClick={handleCopy}
      title="Скопировать"
      className="flex items-center gap-1 px-2 py-1 rounded text-xs text-gray-500 hover:bg-gray-200 transition shrink-0"
    >
      {copied ? <Check className="w-3.5 h-3.5 text-green-600" /> : <Copy className="w-3.5 h-3.5" />}
      {copied ? 'Скопировано' : 'Копировать'}
    </button>
  )
}

function CodeBlock({ code }: { code: string }) {
  return (
    <div className="rounded-lg bg-gray-900 text-gray-100 text-xs font-mono overflow-x-auto">
      <div className="flex items-start justify-between gap-2 px-3 py-2.5">
        <pre className="whitespace-pre-wrap break-all leading-relaxed flex-1">{code}</pre>
        <CopyButton text={code} />
      </div>
    </div>
  )
}

export default function AddNodeModal({ onClose, onCreated }: AddNodeModalProps) {
  const [step, setStep] = useState<Step>(1)

  // Step 1 form
  const [hostname, setHostname] = useState('')
  const [privateIp, setPrivateIp] = useState('')
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState('')

  // Step 2 polling
  const [nodeId, setNodeId] = useState<number | null>(null)
  const [enrollToken, setEnrollToken] = useState('')
  const [pollStatus, setPollStatus] = useState<'waiting' | 'ok' | 'error'>('waiting')
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // Step 3
  const [createdHostname, setCreatedHostname] = useState('')

  // Clean up polling on unmount
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [])

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault()
    setCreating(true)
    setError('')
    try {
      const result = await createNode(hostname.trim(), privateIp.trim())
      setNodeId(result.id)
      setEnrollToken(result.enroll_token)
      setCreatedHostname(hostname.trim())
      setStep(2)
      startPolling(result.id)
    } catch (err: unknown) {
      const detail = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
      setError(detail || 'Ошибка создания ноды')
    } finally {
      setCreating(false)
    }
  }

  const startPolling = (id: number) => {
    pollRef.current = setInterval(async () => {
      try {
        const node = await getNode(id)
        if (node.health === 'ok') {
          clearInterval(pollRef.current!)
          pollRef.current = null
          setPollStatus('ok')
        }
      } catch {
        // keep polling on transient errors
      }
    }, 3000)
  }

  const handleProceedToStep3 = () => {
    if (pollRef.current) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
    setStep(3)
    onCreated()
  }

  // Commands for step 2
  const azSetupCmd = `curl -fsSL https://raw.githubusercontent.com/your-org/antizapret/main/install.sh | bash`
  const agentInstallCmd = `curl -fsSL "${CP_URL}/api/v1/agent/install.sh?token=${enrollToken}" | bash`

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-2xl shadow-xl max-w-xl w-full p-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-5">
          <div>
            <h2 className="text-xl font-bold text-gray-900">Добавить ноду</h2>
            <p className="text-xs text-gray-400 mt-0.5">Шаг {step} из 3</p>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-500 hover:text-gray-700 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Step indicator */}
        <div className="flex items-center gap-2 mb-6">
          {([1, 2, 3] as Step[]).map((s) => (
            <div key={s} className="flex items-center gap-2">
              <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold transition ${
                s < step
                  ? 'bg-green-500 text-white'
                  : s === step
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-400'
              }`}>
                {s < step ? <Check className="w-3.5 h-3.5" /> : s}
              </div>
              {s < 3 && <div className={`h-0.5 w-8 rounded ${s < step ? 'bg-green-400' : 'bg-gray-200'}`} />}
            </div>
          ))}
        </div>

        {/* Step 1: Form */}
        {step === 1 && (
          <form onSubmit={handleCreate} className="space-y-4">
            {error && (
              <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0" />
                {error}
              </div>
            )}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Hostname</label>
              <input
                type="text"
                value={hostname}
                onChange={e => setHostname(e.target.value)}
                placeholder="node-01.example.com"
                required
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none font-mono text-sm"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Внутренний IP</label>
              <input
                type="text"
                value={privateIp}
                onChange={e => setPrivateIp(e.target.value)}
                placeholder="10.0.0.10"
                required
                pattern="^\d{1,3}(\.\d{1,3}){3}$"
                title="Введите корректный IPv4-адрес"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none font-mono text-sm"
              />
            </div>
            <div className="flex gap-3 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="flex-1 px-4 py-2.5 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition font-medium"
              >
                Отмена
              </button>
              <button
                type="submit"
                disabled={creating}
                className="flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-lg transition font-medium disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {creating && <Loader2 className="w-4 h-4 animate-spin" />}
                Создать
              </button>
            </div>
          </form>
        )}

        {/* Step 2: Install commands + polling */}
        {step === 2 && nodeId !== null && (
          <div className="space-y-4">
            <p className="text-sm text-gray-600">
              Нода <span className="font-semibold">{createdHostname}</span> создана. Выполните команды на сервере:
            </p>

            {/* Command 1 */}
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1.5">
                1. Установка AntiZapret
              </p>
              <CodeBlock code={azSetupCmd} />
            </div>

            {/* Command 2 */}
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1.5">
                2. Установка агента
              </p>
              <CodeBlock code={agentInstallCmd} />
            </div>

            {/* Poll status */}
            <div className={`p-3 rounded-lg flex items-center gap-2 text-sm ${
              pollStatus === 'ok'
                ? 'bg-green-50 border border-green-200 text-green-700'
                : 'bg-blue-50 border border-blue-200 text-blue-700'
            }`}>
              {pollStatus === 'ok' ? (
                <>
                  <CheckCircle className="w-4 h-4 shrink-0" />
                  Нода вышла в онлайн!
                </>
              ) : (
                <>
                  <Loader2 className="w-4 h-4 animate-spin shrink-0" />
                  Ожидание первого пинга от агента...
                </>
              )}
            </div>

            <div className="flex gap-3 pt-1">
              <button
                type="button"
                onClick={() => {
                  if (pollRef.current) clearInterval(pollRef.current)
                  onClose()
                }}
                className="flex-1 px-4 py-2.5 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition font-medium"
              >
                Закрыть
              </button>
              <button
                type="button"
                onClick={handleProceedToStep3}
                className="flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-lg transition font-medium flex items-center justify-center gap-2"
              >
                Далее
              </button>
            </div>
          </div>
        )}

        {/* Step 3: Balancer redirect */}
        {step === 3 && (
          <div className="space-y-4">
            <div className="p-3 bg-green-50 border border-green-200 rounded-lg flex items-center gap-2 text-sm text-green-700">
              <CheckCircle className="w-4 h-4 shrink-0" />
              Нода <span className="font-semibold mx-1">{createdHostname}</span> добавлена успешно.
            </div>

            <p className="text-sm text-gray-700">
              Нода добавлена. Перейдите в раздел <span className="font-semibold">«Балансировка»</span> чтобы включить её.
            </p>

            <div className="flex gap-3 pt-1">
              <button
                onClick={onClose}
                className="flex-1 px-4 py-2.5 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition font-medium"
              >
                Закрыть
              </button>
              <button
                onClick={onClose}
                className="flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-lg transition font-medium"
              >
                Перейти к балансировке
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
