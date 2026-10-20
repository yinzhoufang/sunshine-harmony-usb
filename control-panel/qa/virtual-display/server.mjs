import { createServer } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
const root = path.dirname(fileURLToPath(import.meta.url))
const project = path.resolve(root, '../..')
const server = await createServer({
  configFile: false, root,
  publicDir: path.join(project, 'src/renderer/public'),
  plugins: [vue()],
  css: { preprocessorOptions: { less: { javascriptEnabled: true, additionalData: '@import "@/styles/variables.less"; @import "@/styles/mixins.less";' } } },
  resolve: { alias: [
    { find: '@tauri-apps/api/core', replacement: path.join(root, 'mock.js') },
    { find: '@tauri-apps/api/event', replacement: path.join(root, 'mock.js') },
    { find: '@', replacement: path.join(project, 'src/renderer') },
  ] },
  server: { host: '127.0.0.1', port: 5190, strictPort: true, fs: { allow: [project] } },
})
await server.listen()
console.log('Virtual display fixture: http://127.0.0.1:5190 (mock state, no host operations)')
