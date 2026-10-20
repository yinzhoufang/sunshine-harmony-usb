import { createApp } from 'vue'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import '../../src/renderer/styles/element-theme.less'
import VddSettings from '../../src/renderer/components/VddSettings.vue'
import { scenario } from './mock.js'
localStorage.setItem('language','zh')
createApp(VddSettings).use(ElementPlus).mount('#app')
for (const id of ['confirm','stream','offline','online']) document.getElementById(id).onclick=()=>scenario(id)
document.getElementById('theme').onclick=()=>{ document.documentElement.dataset.bsTheme=document.documentElement.dataset.bsTheme==='dark'?'light':'dark' }
const style=document.createElement('style');style.textContent='body{margin:0;background:#f4f8fd;font-family:system-ui,sans-serif}[data-bs-theme=dark] body{background:#181a1f}.fixture-tools{padding:12px;text-align:center;font-size:12px;color:#74818d}.fixture-tools button{margin:4px}#app{max-width:1120px;margin:auto}.vdd-settings-wrapper{position:relative!important;height:auto!important}';document.head.append(style)
