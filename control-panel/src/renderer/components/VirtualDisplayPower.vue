<template>
  <section class="vdd-power" :aria-busy="requesting" :aria-label="text.title">
    <div class="vdd-power-copy">
      <div class="vdd-power-title">
        <el-icon><Monitor /></el-icon>
        <strong>{{ text.title }}</strong>
        <el-tag size="small" effect="plain" :type="model.active ? 'success' : 'info'" role="status">{{ text.states[model.phase] }}</el-tag>
      </div>
      <p>{{ text.description }}</p>
      <p v-if="state?.vdd?.awaiting_confirmation" class="vdd-power-note">{{ text.confirmHint }}</p>
      <p v-else-if="state?.vdd?.cooldown" class="vdd-power-note">{{ text.waitHint }}</p>
      <p v-else-if="state?.vdd?.keep_enabled && model.active" class="vdd-power-note">{{ text.keepHint }}</p>
      <el-alert v-if="error" class="vdd-power-error" type="error" :closable="false" :title="text.errors[virtualDisplayError(error)]" />
      <details v-if="error" class="vdd-power-details"><summary>{{ text.details }}</summary><p>{{ error }}</p></details>
    </div>
    <div class="vdd-power-actions">
      <el-switch :model-value="!!model.active" :disabled="model.disabled" :loading="requesting || model.changing"
        :aria-label="text.title" @change="setPower" />
      <el-button size="small" :loading="loading" :disabled="requesting" @click="refresh">{{ text.refresh }}</el-button>
    </div>
  </section>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'
import { ElMessageBox } from 'element-plus'
import { Monitor } from '@element-plus/icons-vue'
import { useI18n } from '../desktop/i18n/index.js'
import { virtualDisplayPower, virtualDisplayError } from '../composables/virtualDisplayPower.js'

const { t } = useI18n()
const text = computed(() => t.value.vddSettings.power)
const state = ref(null)
const requesting = ref(false)
const requestedActive = ref(true)
const loading = ref(false)
const error = ref('')
const model = computed(() => virtualDisplayPower(state.value, requesting.value, requestedActive.value))
let timer, generation = 0, disposed = false, pendingOperation = 0, readFailed = false

async function refresh() {
  if (loading.value || requesting.value) return
  const request = ++generation
  loading.value = true
  try {
    const result = await invoke('get_virtual_display_power')
    if (disposed || request !== generation) return
    state.value = result
    if (readFailed) { error.value = ''; readFailed = false }
    if (pendingOperation && result.operation?.id === pendingOperation) {
      if (result.operation.state === 'failed') error.value = result.operation.error || 'VDD_POWER_REJECTED'
      if (result.operation.state !== 'running') pendingOperation = 0
    }
  } catch (e) {
    if (!disposed && request === generation) { error.value = String(e); state.value = null; readFailed = true }
  } finally {
    if (request === generation) loading.value = false
  }
}

async function setPower(enabled) {
  if (model.value.disabled) return
  ++generation
  requestedActive.value = enabled
  requesting.value = true
  error.value = ''
  let allowInterrupt = false
  try {
    for (;;) {
      try {
        const result = await invoke('set_virtual_display_power', { enabled, allowInterrupt })
        if (disposed) return
        state.value = result.tray_state
        pendingOperation = result.operation_id || 0
        break
      } catch (e) {
        if (!String(e).includes('VDD_STREAMING_CONFIRM_REQUIRED') || allowInterrupt) throw e
        await ElMessageBox.confirm(text.value.streamWarning, text.value.title, {
          type: 'warning', confirmButtonText: text.value.closeAnyway, cancelButtonText: text.value.cancel,
        })
        allowInterrupt = true
      }
    }
  } catch (e) {
    if (!disposed && e !== 'cancel' && e !== 'close') error.value = String(e)
  } finally {
    requesting.value = false
    loading.value = false
    if (!disposed) await refresh()
  }
}

onMounted(() => { refresh(); timer = setInterval(refresh, 2000) })
onUnmounted(() => { disposed = true; ++generation; clearInterval(timer) })
</script>

<style scoped>
.vdd-power { display: flex; align-items: center; justify-content: space-between; gap: 24px; padding: 20px 24px; margin: 0 0 24px; border: 1px solid var(--el-border-color-light); border-radius: 16px; background: var(--el-fill-color-extra-light); }
.vdd-power-copy { min-width: 0; flex: 1; }
.vdd-power-title { display: flex; align-items: center; flex-wrap: wrap; gap: 10px; color: var(--el-text-color-primary); font-size: 16px; }
.vdd-power-title > .el-icon { color: var(--el-color-primary); font-size: 21px; }
.vdd-power-copy > p { color: var(--el-text-color-secondary); font-size: 13px; line-height: 1.6; margin: 8px 0 0; }
.vdd-power-copy > .vdd-power-note { color: var(--el-color-primary); }
.vdd-power-actions { display: flex; flex-shrink: 0; align-items: center; gap: 18px; }
.vdd-power-error { margin-top: 12px; }
.vdd-power-details { margin-top: 8px; color: var(--el-text-color-secondary); font-size: 12px; overflow-wrap: anywhere; }
.vdd-power-details summary { cursor: pointer; }
@media (max-width: 600px) { .vdd-power { align-items: flex-start; flex-direction: column; padding: 18px; gap: 14px; } .vdd-power-actions { align-self: flex-end; } }
</style>
