import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { fileURLToPath, URL } from 'node:url';

// 浏览器调试时把 /api 与 /auth 代理到本机 CRM dev 栈(:3001)，规避跨域。
// 打包进 App 后走 CapacitorHttp 原生请求，不经过这里。
const DEV_BACKEND = 'http://localhost:3001';

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: {
    host: true,
    port: 5273,
    proxy: {
      '/api': { target: DEV_BACKEND, changeOrigin: true },
      '/auth': { target: DEV_BACKEND, changeOrigin: true },
    },
  },
  build: { outDir: 'dist', target: 'es2020', sourcemap: false },
});
