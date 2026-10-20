import { createApp } from 'vue'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import '../../src/renderer/styles/element-theme.less'
import ControllersHub from '../../src/renderer/components/controllersHub/ControllersHub.vue'
localStorage.setItem('language', 'zh')
createApp(ControllersHub).use(ElementPlus).mount('#app')
const style = document.createElement('style')
style.textContent = 'body{margin:0;background:#f4f8fd;color:#254052;font-family:system-ui,sans-serif}#app{max-width:1000px;margin:24px auto;padding:0 24px 40px}.fixture-label{font-size:12px;color:#7b8f9c;text-align:center;margin:14px 0}'
document.head.append(style)
