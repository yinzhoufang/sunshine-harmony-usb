// A configured USB mode is distinct from a healthy cable connection.
export function harmonyConnectionState(status) {
  if (!status) return 'unknown'
  if (!status.enabled) return status.server_ready ? 'network' : 'hostOffline'
  if (!status.hdc_available) return 'hdcMissing'
  if (!status.device_connected) return 'waiting'
  if (!status.healthy && status.relay_ready && status.mappings < 7) return 'recovering'
  return status.healthy ? 'connected' : 'incomplete'
}

export function harmonyErrorKey(error) {
  const code = String(error || '').split(':')[0].trim()
  return ['HDC_MISSING', 'USB_NO_DEVICE', 'USB_SELECT_DEVICE', 'USB_DEVICE_OFFLINE',
    'PYTHON_MISSING', 'BRIDGE_MISSING', 'RELAY_PORT_CONFLICT', 'USB_UAC_CANCELLED', 'USB_RESOURCES_MISSING',
    'SWITCH_ROLLED_BACK', 'ROLLBACK_FAILED', 'SWITCH_BUSY'].includes(code) ? code : 'unknown'
}
