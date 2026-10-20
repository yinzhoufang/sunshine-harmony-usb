export function virtualDisplayPower(state, requesting = false, requestedActive = true) {
  if (!state?.vdd) return { active: false, phase: 'unknown', disabled: true, changing: requesting }
  const { active, cooldown, awaiting_confirmation: confirming } = state.vdd
  const operation = state.operation || {}
  const changing = requesting || (['vdd_create', 'vdd_destroy'].includes(operation.action) && operation.state === 'running')
  const starting = requesting ? requestedActive : operation.action !== 'vdd_destroy'
  const phase = confirming ? 'confirming' : changing ? (starting ? 'starting' : 'stopping') : active ? 'on' : 'off'
  return { active, phase, changing, disabled: changing || !!confirming || !!cooldown }
}

export function virtualDisplayError(error) {
  const text = String(error || '')
  if (text.includes('VDD_POWER_BUSY') || /cooling down|already in progress/i.test(text)) return 'busy'
  if (/VDD_DRIVER_|repair ZakoVDD|install ZakoVDD/.test(text)) return 'driver'
  if (/connect|Request tray state failed/i.test(text)) return 'offline'
  return 'failed'
}
