// This file is only aliased by this QA server, never by the production build.
let enabled = true
export async function invoke(command, args) {
  if (command === 'harmony_usb_set_mode') enabled = args.enabled
  if (command === 'harmony_usb_get_status' || command === 'harmony_usb_set_mode') return {
    enabled, healthy: true, hdc_available: true, devices: ['USB-TABLET'], device_id: 'USB-TABLET',
    device_connected: true, mappings: enabled ? 7 : 0, relay_ready: enabled, tunnels_connected: enabled,
    server_ready: true, port: enabled ? 48989 : 47989,
  }
  if (command === 'parse_sunshine_config') return { locale: 'zh' }
  if (command === 'get_controller_hub_config') return { gamepad: 'auto' }
  if (command === 'get_virtual_microphone_status') return { supported: true, enabled: false }
  if (command === 'usbip_get_status') return { ready: false }
  return {}
}
export async function listen() { return () => {} }
export async function emit() {}
