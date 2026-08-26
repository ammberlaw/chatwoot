#!/usr/bin/env bash
# 部署前漂移闸 —— 在生产服务器上运行。
#
# 作用：比对「正在运行的容器 /app」与「构建源目录」的 app/ 全量代码 md5。
# 任一文件不一致即退出码 1 并分类列出差异，阻止你在漂移状态下 docker build。
#
# 为什么需要它：多窗口/多会话/多 worktree 各自 docker cp / rsync 部署时，
# 某个热修可能只落到运行容器、没同步回构建源（或反之）。一旦从构建源 build，
# 那些没对齐的改动会被静默回退——线上功能"无故消失"的头号真凶。build 前强制
# 跑这道闸，让所有差异在部署前当场暴露。
#
# 用法（在生产机上）：
#   bash scripts/predeploy-check.sh
#   CONTAINER=wintouch-crm-rails-1 BUILD_SRC=$HOME/wintouch-crm bash scripts/predeploy-check.sh
#
# 判读：
#   [仅容器有 / 内容不同]  = 危险：从构建源 build 会删除/回退这些线上改动 → 先同步回构建源
#   [仅构建源有]           = 本次即将新增部署的文件（通常是你的预期改动）
# 退出码 0 = 完全一致；1 = 存在任意差异（需人工确认后再决定是否 build）。
set -uo pipefail

CONTAINER="${CONTAINER:-wintouch-crm-rails-1}"
BUILD_SRC="${BUILD_SRC:-$HOME/wintouch-crm}"

# 纳入对比的代码文件（不含编译产物/依赖）。内联写法，避免经变量传参时括号/glob 被本地展开。
FINDCMD='find app -type f \( -name "*.rb" -o -name "*.vue" -o -name "*.js" -o -name "*.jbuilder" -o -name "*.erb" -o -name "*.rake" \) -exec md5sum {} +'

img="$(mktemp)"; src="$(mktemp)"
trap 'rm -f "$img" "$src"' EXIT

docker exec "$CONTAINER" sh -c "cd /app && $FINDCMD" 2>/dev/null | awk '{print $2"\t"$1}' | sort > "$img"
sh -c "cd '$BUILD_SRC' && $FINDCMD" 2>/dev/null | awk '{print $2"\t"$1}' | sort > "$src"

if [ ! -s "$img" ]; then echo "❌ 无法读取运行容器 $CONTAINER（是否在运行？）"; exit 2; fi
if [ ! -s "$src" ]; then echo "❌ 无法读取构建源 $BUILD_SRC"; exit 2; fi

echo "运行容器: $CONTAINER ($(wc -l < "$img") 文件)   构建源: $BUILD_SRC ($(wc -l < "$src") 文件)"

only_img="$(comm -23 <(cut -f1 "$img") <(cut -f1 "$src"))"
only_src="$(comm -13 <(cut -f1 "$img") <(cut -f1 "$src"))"
differ="$(join -t "$(printf '\t')" "$img" "$src" | awk -F'\t' '$2 != $3 { print $1 }')"

n_img=$(printf '%s' "$only_img" | grep -c . || true)
n_src=$(printf '%s' "$only_src" | grep -c . || true)
n_diff=$(printf '%s' "$differ" | grep -c . || true)

if [ "$n_img" -eq 0 ] && [ "$n_src" -eq 0 ] && [ "$n_diff" -eq 0 ]; then
  echo "✅ 零漂移：运行容器与构建源完全一致，可安全 build。"
  exit 0
fi

echo
[ "$n_img" -gt 0 ] && { echo "⚠️  仅容器有 / build 会删除回退（$n_img，危险）："; printf '%s\n' "$only_img" | sed 's/^/    - /'; }
[ "$n_diff" -gt 0 ] && { echo "⚠️  内容不一致（$n_diff，确认是否含线上热修未回灌构建源）："; printf '%s\n' "$differ" | sed 's/^/    ~ /'; }
[ "$n_src" -gt 0 ] && { echo "ℹ️  仅构建源有 / 本次将新增部署（$n_src）："; printf '%s\n' "$only_src" | sed 's/^/    + /'; }
echo
echo "❌ 存在漂移。逐条确认后再决定是否 build（危险类差异务必先同步回构建源）。"
exit 1
