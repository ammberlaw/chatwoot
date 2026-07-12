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
    allowedHosts: ['localhost', 'vite'],
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
