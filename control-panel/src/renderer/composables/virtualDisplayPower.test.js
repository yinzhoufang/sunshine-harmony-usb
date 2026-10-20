import test from 'node:test'
import assert from 'node:assert/strict'
import { virtualDisplayPower, virtualDisplayError } from './virtualDisplayPower.js'

test('unknown Core state cannot be mistaken for a confirmed switched-off display', () => {
  assert.equal(virtualDisplayPower(null).phase, 'unknown')
  assert.equal(virtualDisplayPower(null).disabled, true)
})
test('accepted create remains pending until the Core actually creates the display', () => {
  const model = virtualDisplayPower({ vdd: { active: false, cooldown: true }, operation: { action: 'vdd_create', state: 'running' } })
  assert.equal(model.active, false)
  assert.equal(model.phase, 'starting')
  assert.equal(model.disabled, true)
})
test('created display awaiting the Core confirmation is not reported as a completed action', () => {
  assert.equal(virtualDisplayPower({ vdd: { active: true, awaiting_confirmation: true } }).phase, 'confirming')
})
test('close only displays off after the actual Core state changes', () => {
  const stopping = virtualDisplayPower({ vdd: { active: true }, operation: { action: 'vdd_destroy', state: 'running' } })
  assert.equal(stopping.active, true)
  assert.equal(stopping.phase, 'stopping')
  assert.equal(virtualDisplayPower({ vdd: { active: false } }).phase, 'off')
})
test('cooldown retains the correct state and temporarily disables repeated clicks', () => {
  const model = virtualDisplayPower({ vdd: { active: true, cooldown: true } })
  assert.equal(model.phase, 'on')
  assert.equal(model.disabled, true)
  assert.equal(model.changing, false)
})
test('driver, offline and rejected operation errors remain distinguishable', () => {
  assert.equal(virtualDisplayError('VDD_DRIVER_UNAVAILABLE'), 'driver')
  assert.equal(virtualDisplayError('Request tray state failed: connection refused'), 'offline')
  assert.equal(virtualDisplayError('VDD_POWER_BUSY'), 'busy')
  assert.equal(virtualDisplayError('Failed to close virtual display'), 'failed')
})
test('close confirmation uses the requested action instead of a previous create operation', () => {
  assert.equal(virtualDisplayPower({ vdd: { active: true }, operation: { action: 'vdd_create', state: 'succeeded' } }, true, false).phase, 'stopping')
})
