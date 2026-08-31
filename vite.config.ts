import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  // dev server 跑在独立 docker 容器里，rails 经 ViteRuby::DevServerProxy 以
  // Host: vite:3036 转发过来；vite 6 的 allowedHosts 默认会拦掉，需放行该主机名。
  server: {
    allowedHosts: ['localhost', 'vite', 'chatwoot-int-vite'],
    // HMR websocket 客户端连的是【宿主发布端口】。CRM 独立栈把容器内 3036 发布到宿主 3037
    // （避免与 MES 的 3036 撞），浏览器须连 3037，否则 ws 连不上、报错阻断 SPA 启动（白屏）。
    // 由 VITE_HMR_CLIENT_PORT 指定；未设（MES/base=3036:3036）走 vite 默认端口。
    ...(process.env.VITE_HMR_CLIENT_PORT
      ? { hmr: { clientPort: Number(process.env.VITE_HMR_CLIENT_PORT) } }
      : {}),
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
});
