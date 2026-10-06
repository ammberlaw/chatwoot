#!/usr/bin/env bash
#
# 把 ops/ 里的 nginx 配置和法务静态页与生产机对账，或推上去。
#
# 用法：
#   ./ops/sync-nginx.sh           对账（只读）
#   ./ops/sync-nginx.sh --push    推送（备份 → 覆盖 → nginx -t → reload，失败回滚）
#
set -euo pipefail

SERVER="${SERVER:-ubuntu@43.136.84.15}"
SSH_OPTS=(-o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")

OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 仓库相对路径 → 生产机绝对路径
FILES=(
  "nginx/sites-available/wintouch-crm:/etc/nginx/sites-available/wintouch-crm"
  "nginx/snippets/wintouch-proxy.conf:/etc/nginx/snippets/wintouch-proxy.conf"
  "nginx/snippets/wintouch-static-cache.conf:/etc/nginx/snippets/wintouch-static-cache.conf"
  "nginx/conf.d/wintouch-cache.conf:/etc/nginx/conf.d/wintouch-cache.conf"
  "legal/privacy.html:/var/www/wintouch-legal/privacy.html"
)

DO_PUSH=0
for arg in "$@"; do
  case "$arg" in
    --push) DO_PUSH=1 ;;
    --help|-h) sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：${arg} （--help 看用法）"; exit 1 ;;
  esac
done

remote() { ssh "${SSH_OPTS[@]}" "$SERVER" "$@"; }

# ── 对账 ──
# 逐个文件取生产内容跟本地 diff。比 md5 清单好的地方是差异能直接看见，
# certbot 自己加的那几行一眼认得出来（见 README）。
DIFFERENT=()
for pair in "${FILES[@]}"; do
  local_rel="${pair%%:*}"; remote_path="${pair#*:}"
  local_file="$OPS_DIR/$local_rel"
  [ -f "$local_file" ] || { echo "✗ 仓库里缺文件：ops/$local_rel"; exit 1; }

  if remote "sudo cat '$remote_path'" 2>/dev/null | diff -q - "$local_file" >/dev/null 2>&1; then
    echo "= ops/$local_rel"
  else
    echo "≠ ops/$local_rel  ← 与 $remote_path 不一致"
    remote "sudo cat '$remote_path'" 2>/dev/null | diff -u - "$local_file" | sed 's/^/    /' || true
    DIFFERENT+=("$pair")
  fi
done

if [ "${#DIFFERENT[@]}" -eq 0 ]; then
  echo "生产与仓库一致。"
  exit 0
fi

if [ "$DO_PUSH" = 0 ]; then
  echo
  echo "有 ${#DIFFERENT[@]} 个文件不一致。确认上面的差异就是你要改的，再跑 --push。"
  echo "如果差异是 certbot 自己写的，该把生产那份拉回仓库，而不是推上去。"
  exit 1
fi

# ── 推送 ──
STAMP="$(date +%Y%m%d-%H%M%S)"
BAK="/etc/nginx/.wintouch-bak-$STAMP"
echo
echo "→ 备份到服务器 $BAK"
remote "sudo mkdir -p '$BAK'"
for pair in "${DIFFERENT[@]}"; do
  remote_path="${pair#*:}"
  remote "sudo cp --parents '$remote_path' '$BAK/' 2>/dev/null || true"
done

for pair in "${DIFFERENT[@]}"; do
  local_rel="${pair%%:*}"; remote_path="${pair#*:}"
  echo "→ 推送 ops/$local_rel"
  scp "${SSH_OPTS[@]}" "$OPS_DIR/$local_rel" "$SERVER:/tmp/wtops-push" >/dev/null
  remote "sudo mkdir -p \"\$(dirname '$remote_path')\" && sudo cp /tmp/wtops-push '$remote_path' && sudo rm -f /tmp/wtops-push"
done

echo "→ nginx -t"
if remote "sudo nginx -t" 2>&1 | sed 's/^/    /'; then
  remote "sudo systemctl reload nginx"
  echo "✓ 已 reload。备份留在 $BAK"
else
  echo "✗ nginx -t 不过，回滚"
  remote "sudo cp -r '$BAK'/* / && sudo nginx -t && sudo systemctl reload nginx"
  echo "已回滚到推送前的状态。"
  exit 1
fi
