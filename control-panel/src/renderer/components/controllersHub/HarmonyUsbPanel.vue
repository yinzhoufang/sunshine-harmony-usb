<template>
  <section class="chub-panel harmony-transport" :aria-busy="busy">
    <div class="chub-section-head">
      <span class="chub-section-label">◈ {{ text.title }}</span>
      <span class="chub-section-rule"></span>
      <el-button size="small" :loading="loading" :disabled="busy" @click="refresh">{{ t.deviceHub.refresh }}</el-button>
    </div>
    <p class="chub-hint">{{ text.intro }}</p>
    <el-skeleton v-if="!status && loading" :rows="3" animated />
    <div v-else class="chub-card harmony-mode-card" :class="{ 'is-usb': status?.enabled }">
      <div class="harmony-mode-heading">
        <div class="harmony-mode-copy">
          <strong>{{ text.switchLabel }}</strong>
          <span class="chub-hint">{{ status?.enabled ? text.usbHint : text.networkHint }}</span>
        </div>
        <el-switch :model-value="!!status?.enabled" :loading="busy" :disabled="busy || !status"
          :aria-label="text.switchLabel" @change="switchMode" />
      </div>
      <div class="harmony-mode-status" aria-live="polite">
        <el-tag effect="plain" :type="status?.healthy ? 'success' : 'info'">{{ text.states[connectionState] }}</el-tag>
        <span v-if="status?.enabled" class="harmony-address">Moonlight · <strong>127.0.0.2</strong></span>
        <span v-else class="chub-hint">{{ text.networkAddress }}</span>
      </div>
      <div v-if="status?.devices?.length > 1" class="harmony-device-row">
        <label for="harmony-device">{{ text.device }}</label>
        <el-select id="harmony-device" v-model="selectedDevice" :disabled="busy" :placeholder="text.selectDevice">
          <el-option v-for="id in status.devices" :key="id" :label="id" :value="id" />
        </el-select>
      </div>
      <p v-else-if="status?.enabled && status?.device_connected" class="chub-hint harmony-device-name">{{ text.device }} · {{ status.device_id }}</p>
      <p class="chub-hint harmony-restart-note">{{ text.restartHint }}</p>
      <template v-if="busy">
        <el-progress :percentage="progress" :stroke-width="6" :show-text="false" />
        <p class="chub-hint" role="status">{{ text.stages[stage] || text.stages.checking }}</p>
      </template>
      <el-button v-if="status?.enabled && !status?.healthy && !busy" size="small" @click="switchMode(true)">{{ text.repair }}</el-button>
    </div>
    <el-alert v-if="error" class="chub-notice" type="error" :closable="false" :title="text.errors[harmonyErrorKey(error)]" />
    <details v-if="error" class="chub-disclosure chub-disclosure--inline harmony-details">
      <summary>{{ text.details }}<span class="chub-disclosure-mark">▸</span></summary>
      <pre>{{ error }}</pre>
    </details>
    <p v-if="status?.enabled" class="chub-hint harmony-cable-help">{{ text.cableHelp }}</p>
  </section>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { ElMessage } from 'element-plus'
import { useI18n } from '../../desktop/i18n/index.js'
import { harmonyConnectionState, harmonyErrorKey } from '../../composables/harmonyUsbState.js'

const { t } = useI18n()
const text = computed(() => t.value.deviceHub.harmonyUsb)
const status = ref(null)
const selectedDevice = ref('')
const loading = ref(false)
const busy = ref(false)
const error = ref('')
const stage = ref('checking')
const progress = ref(0)
const connectionState = computed(() => harmonyConnectionState(status.value))
let timer, unlisten
let disposed = false
let generation = 0

async function refresh() {
  if (busy.value || loading.value) return
  const request = ++generation
  loading.value = true
  try {
    const result = await invoke('harmony_usb_get_status')
    if (disposed || request !== generation) return
    status.value = result
    if (!selectedDevice.value || !result.devices?.includes(selectedDevice.value)) selectedDevice.value = result.device_id || ''
  } catch (e) {
    if (!disposed && request === generation) error.value = String(e)
  } finally {
    if (request === generation) loading.value = false
  }
}

async function switchMode(enabled) {
  if (busy.value || !status.value) return
  ++generation // Discard a slow health response from before this switch.
  busy.value = true
  error.value = ''
  stage.value = 'authorizing'
  progress.value = 2
  try {
    const result = await invoke('harmony_usb_set_mode', { enabled, deviceId: selectedDevice.value || null })
    if (disposed) return
    status.value = result
    ElMessage.success(enabled ? text.value.enabledToast : text.value.disabledToast)
  } catch (e) {
    if (!disposed) error.value = String(e)
  } finally {
    loading.value = false
    busy.value = false
    if (!disposed) await refresh()
  }
}

onMounted(async () => {
  unlisten = await listen('harmony-usb-progress', ({ payload }) => {
    if (!busy.value) return
    stage.value = payload.stage
    progress.value = payload.progress
  })
  if (disposed) { unlisten(); return }
  await refresh()
  if (!disposed) timer = setInterval(refresh, 8000)
})
onUnmounted(() => { disposed = true; ++generation; clearInterval(timer); unlisten?.() })
</script>

<style scoped>
.harmony-transport { margin-bottom: 28px; }
.harmony-mode-card { padding: 20px; border-left: 4px solid var(--el-border-color); }
.harmony-mode-card.is-usb { border-left-color: var(--chub-primary); }
.harmony-mode-heading, .harmony-mode-status, .harmony-device-row { display: flex; align-items: center; gap: 16px; }
.harmony-mode-heading { justify-content: space-between; }
.harmony-mode-copy { display: flex; flex-direction: column; gap: 6px; }
.harmony-mode-copy strong { font-size: 16px; }
.harmony-mode-copy .chub-hint { margin: 0; }
.harmony-mode-status { flex-wrap: wrap; margin-top: 18px; }
.harmony-mode-status .chub-hint { margin: 0; }
.harmony-address { color: var(--el-text-color-regular); font-size: 13px; }
.harmony-address strong { color: var(--chub-primary-deep); }
.harmony-restart-note { margin: 16px 0 0; }
.harmony-device-row { margin-top: 16px; flex-wrap: wrap; }
.harmony-device-row .el-select { width: 260px; max-width: 100%; }
.harmony-device-name { overflow-wrap: anywhere; }
.harmony-details pre { white-space: pre-wrap; overflow-wrap: anywhere; font-size: 12px; }
.harmony-cable-help { margin-bottom: 0; }
.harmony-mode-card .el-progress { margin-top: 14px; }
</style>
