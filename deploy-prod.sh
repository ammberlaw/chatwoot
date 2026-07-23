#!/usr/bin/env bash
#
# Wintouch-CRM 生产部署脚本（在本机 Mac 运行，编排 rsync + 远程构建）
# 生产：腾讯云 43.136.84.15 · docker compose · 镜像 wintouch-crm:prod
#
# 用法：
#   ./deploy-prod.sh              正常部署（同步→构建→迁移→重启→验证）
#   ./deploy-prod.sh --no-migrate 跳过数据库迁移（无迁移文件时略快）
#   ./deploy-prod.sh --stop       构建前停应用容器（低内存保命，8G 机型无需）
#   ./deploy-prod.sh --prune       部署后清理构建缓存（缓存膨胀时用）
#   ./deploy-prod.sh --help        查看帮助
#
set -euo pipefail

# ── 可用环境变量覆盖 ──
REPO_DIR="${REPO_DIR:-/Users/amberlaw/acrm-migration/chatwoot}"
SSH_KEY="${SSH_KEY:-$HOME/Desktop/CRM.pem}"
SERVER="${SERVER:-ubuntu@43.136.84.15}"
REMOTE_DIR="${REMOTE_DIR:-wintouch-crm}"      # 服务器 ~/wintouch-crm
COMPOSE="docker-compose.prod.yaml"
APP_URL="${APP_URL:-http://43.136.84.15/}"
SSH_OPTS=(-i "$SSH_KEY" -o ConnectTimeout=15 -o ServerAliveInterval=10 -o StrictHostKeyChecking=accept-new)

DO_MIGRATE=1
DO_STOP=0
DO_PRUNE=0
for arg in "$@"; do
  case "$arg" in
    --no-migrate) DO_MIGRATE=0 ;;
    --stop) DO_STOP=1 ;;
    --prune) DO_PRUNE=1 ;;
    --help|-h)
      sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "未知参数：${arg} （--help 看用法）"; exit 1 ;;
  esac
done

# ── 输出辅助 ──
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=''; G=''; Y=''; R=''; N=''; fi
step() { echo; echo "${B}▶ $*${N}"; }
ok()   { echo "${G}✓ $*${N}"; }
warn() { echo "${Y}! $*${N}"; }
die()  { echo "${R}✗ $*${N}"; exit 1; }

# 重试包装：跨境链路会抖，ssh/rsync 断了自动重来（最多 15 次，每次间隔 15s）
retry() {
  local n=0
  until "$@"; do
    n=$((n + 1))
    [ "$n" -ge 15 ] && die "重试 15 次仍失败：$*"
    warn "第 $n 次失败，15s 后重试…"
    sleep 15
  done
}

remote() { ssh "${SSH_OPTS[@]}" "$SERVER" "$@"; }

# ── 0. 预检 ──
step "预检"
[ -f "$SSH_KEY" ] || die "找不到 SSH 私钥：$SSH_KEY"
cd "$REPO_DIR" || die "找不到仓库目录：$REPO_DIR"
SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"   # 在仓库目录里先算好，避免 cwd 漂移写空版本号
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo -)"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  warn "工作区有未提交改动——它们也会被部署（rsync 同步的是当前文件，不是最后一次提交）"
fi
ok "仓库 $BRANCH @ ${SHA:0:9}"
retry remote 'echo ok' >/dev/null && ok "SSH 连通 $SERVER"

# ── 1. 同步代码 ──
step "同步代码到 ~/${REMOTE_DIR} （rsync 增量）"
retry rsync -az --delete --timeout=60 \
  --exclude .git --exclude tmp --exclude log --exclude storage \
  --exclude node_modules --exclude .codex --exclude coverage \
  --exclude '.env' --exclude '.env.*' \
  -e "ssh ${SSH_OPTS[*]}" \
  ./ "$SERVER:~/$REMOTE_DIR/"
ok "代码已同步"

# ── 2. 补版本号 + 后台构建 ──
step "构建生产镜像（后台跑，不怕 SSH 掉线）"
STOP_CMD=""
[ "$DO_STOP" = 1 ] && STOP_CMD="sudo docker compose -f $COMPOSE stop rails sidekiq >/dev/null 2>&1;"
retry remote "cd ~/$REMOTE_DIR && \
  sed -i 's|RUN git rev-parse HEAD > /app/.git_sha|RUN echo $SHA > /app/.git_sha|' docker/Dockerfile && \
  ${STOP_CMD} nohup sudo docker compose -f $COMPOSE build rails > ~/build.log 2>&1 & sleep 3; echo started" >/dev/null
ok "构建已启动，等待完成（增量约 10–20 分钟）…"

# 轮询构建日志直到出现 Built / 失败
while true; do
  STATUS="$(remote "grep -c 'wintouch-crm:prod Built' ~/build.log 2>/dev/null || true; grep -ciE 'error|failed to solve|did not complete' ~/build.log 2>/dev/null || true" 2>/dev/null || echo '0 0')"
  BUILT="$(echo "$STATUS" | sed -n '1p')"
  ERRS="$(echo "$STATUS" | sed -n '2p')"
  if [ "${BUILT:-0}" != 0 ]; then ok "镜像构建完成"; break; fi
  if [ "${ERRS:-0}" != 0 ]; then
    remote 'tail -20 ~/build.log' || true
    die "构建疑似失败（build.log 有 error），请上服务器 tail ~/build.log 排查"
  fi
  sleep 30
done

# ── 3. 数据库迁移 ──
if [ "$DO_MIGRATE" = 1 ]; then
  step "数据库迁移"
  retry remote "cd ~/$REMOTE_DIR && sudo docker compose -f $COMPOSE run --rm rails bundle exec rails db:migrate 2>&1 | grep -iE 'migrat|error' | tail -8 || true"
  ok "迁移完成"
fi

# ── 4. 重启应用（强制用新镜像重建） ──
step "用新镜像重启 rails + sidekiq"
retry remote "cd ~/$REMOTE_DIR && sudo docker compose -f $COMPOSE up -d --force-recreate rails sidekiq 2>&1 | tail -3"
ok "服务已重启"

# ── 4b. 品牌自愈：重申 Wintouch（防 installation_configs 被重置回 Chatwoot） ──
step "重申品牌 Wintouch"
retry remote "cd ~/$REMOTE_DIR && sudo docker compose -f $COMPOSE exec -T rails bundle exec rails wintouch:brand 2>&1 | tail -2" || warn "品牌重申失败，可手动 rails wintouch:brand"
ok "品牌已确保为 Wintouch"

# ── 5. 健康检查 ──
step "健康检查"
HTTP=000
for _ in $(seq 1 12); do
  HTTP="$(remote "curl -s -o /dev/null -w '%{http_code}' http://localhost/" 2>/dev/null || echo 000)"
  [ "$HTTP" = 200 ] && break
  sleep 5
done
if [ "$HTTP" = 200 ]; then ok "站点返回 200"; else die "站点返回 ${HTTP} ·请检查 sudo docker compose -f $COMPOSE logs rails"; fi
remote "cd ~/$REMOTE_DIR && sudo docker compose -f $COMPOSE ps --format '{{.Name}} {{.Status}}'" || true

# ── 6. 可选清理构建缓存 ──
if [ "$DO_PRUNE" = 1 ]; then
  step "清理构建缓存"
  retry remote 'sudo docker builder prune --reserved-space 4GB -f' || true
  ok "缓存已清理"
fi

echo
ok "部署完成 · $BRANCH @ ${SHA:0:9} · $APP_URL"
