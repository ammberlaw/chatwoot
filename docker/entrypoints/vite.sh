#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

# node_modules 是持久化命名卷；仅在缺依赖时安装，避免每次重启都 store prune +
# --force 全量重下 1100+ 包（网络抖动会卡死启动）。改 package.json 后手动 pnpm install。
if [ ! -x node_modules/.bin/vite ]; then
  pnpm install
fi

echo "Ready to run Vite development server."

exec "$@"
