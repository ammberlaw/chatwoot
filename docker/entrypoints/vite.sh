#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

# node_modules 命名卷里的 pnpm 虚拟store用绝对路径 /chatwoot 指向依赖，但 CRM 独立栈把
# 应用挂在 /app → .bin/vite 的软链目标 /chatwoot/... 解析不到，vite 启动即崩（:3001 白屏）。
# 补一个 /chatwoot → /app 桥接软链（容器重建后会丢，故放 entrypoint）。仅当 /chatwoot 不存在时建；
# MES 栈应用根本身就是 /chatwoot（真实目录），会跳过、不受影响。
[ -e /chatwoot ] || ln -sfn /app /chatwoot

# node_modules 是持久化命名卷；仅在缺依赖时安装，避免每次重启都 store prune +
# --force 全量重下 1100+ 包（网络抖动会卡死启动）。改 package.json 后手动 pnpm install。
if [ ! -x node_modules/.bin/vite ]; then
  pnpm install
fi

echo "Ready to run Vite development server."

exec "$@"
