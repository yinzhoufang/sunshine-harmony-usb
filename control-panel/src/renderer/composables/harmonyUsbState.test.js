import test from 'node:test'
import assert from 'node:assert/strict'
import { harmonyConnectionState, harmonyErrorKey } from './harmonyUsbState.js'

test('USB selection never implies that a missing cable or relay is connected', () => {
  const selected = { enabled: true, hdc_available: true, server_ready: true }
  assert.equal(harmonyConnectionState(selected), 'waiting')
  assert.equal(harmonyConnectionState({ ...selected, device_connected: true }), 'incomplete')
  assert.equal(harmonyConnectionState({ ...selected, device_connected: true, healthy: true }), 'connected')
  assert.equal(harmonyConnectionState({ ...selected, hdc_available: false }), 'hdcMissing')
})
test('network mode reports a stopped host instead of a healthy connection', () => {
  assert.equal(harmonyConnectionState({ enabled: false, server_ready: false }), 'hostOffline')
  assert.equal(harmonyConnectionState({ enabled: false, server_ready: true }), 'network')
})
test('rollback and canceled elevation have distinct recovery instructions', () => {
  assert.equal(harmonyErrorKey('SWITCH_ROLLED_BACK: HDC_FAILED'), 'SWITCH_ROLLED_BACK')
  assert.equal(harmonyErrorKey('USB_UAC_CANCELLED: operation canceled'), 'USB_UAC_CANCELLED')
  assert.equal(harmonyErrorKey('new error'), 'unknown')
})
