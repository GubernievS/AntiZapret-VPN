interface ToggleProps {
  label?: string
  value: boolean
  onChange: (v: boolean) => void
  disabled?: boolean
}

export default function Toggle({ label, value, onChange, disabled = false }: ToggleProps) {
  const handleClick = () => {
    if (disabled) return
    onChange(!value)
  }

  const switchClasses = `relative inline-flex h-5 w-9 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 ${
    value ? 'bg-blue-600' : 'bg-gray-300'
  } ${disabled ? 'opacity-50 cursor-not-allowed' : ''}`

  const knobClasses = `inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow transition-transform ${
    value ? 'translate-x-4' : 'translate-x-0.5'
  }`

  if (label === undefined) {
    return (
      <button
        type="button"
        role="switch"
        aria-checked={value}
        aria-disabled={disabled}
        disabled={disabled}
        onClick={handleClick}
        className={switchClasses}
      >
        <span className={knobClasses} />
      </button>
    )
  }

  return (
    <label
      className={`flex items-center justify-between py-2 group ${
        disabled ? 'cursor-not-allowed' : 'cursor-pointer'
      }`}
    >
      <span className={`text-sm ${disabled ? 'text-gray-400' : 'text-gray-700 group-hover:text-gray-900'}`}>
        {label}
      </span>
      <button
        type="button"
        role="switch"
        aria-checked={value}
        aria-disabled={disabled}
        disabled={disabled}
        onClick={handleClick}
        className={switchClasses}
      >
        <span className={knobClasses} />
      </button>
    </label>
  )
}
