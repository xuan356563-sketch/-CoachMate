import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    host: '127.0.0.1',
    port: 5176,
    strictPort: true,
    proxy: {
      '/ops': {
        target: 'http://127.0.0.1:8001',
        changeOrigin: false,
      },
    },
  },
})
