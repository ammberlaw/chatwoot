#!/usr/bin/env bash
# 部署前本地闸 —— 在**本机**跑，不是在服务器上。
#
# 和 scripts/predeploy-check.sh 的分工：
#   predeploy-check.sh  在服务器上比「运行容器 vs 构建源」——防构建把线上热修回退
#   本脚本              在本机比「本地代码树 vs 生产运行容器」——防该推的没推
#
# 为什么要有它（2026-10-27 一天踩了两次）：
#   ① 只按 `git status` 的脏文件列清单部署，结果 Dashboard.vue / config/routes.rb
#      这两个「已提交但生产一直落后」的文件没推 → AI 球和待办悬浮窗在线上消失、
#      my_day 接口 404。脏文件清单 ≠ 该部署的清单。
#   ② Crm::KpiSheetPolicy 少了 pending_count?，角标接口上线即 500，
#      每个人打开页面撞一次。仓库里本来就有 spec 能拦住，但没人在部署前跑它。
#
# 用法：bash scripts/predeploy-local.sh
# 退出码 0 = 可以部署；1 = 有问题，先看输出。
set -uo pipefail

HOST="${HOST:-ubuntu@43.136.84.15}"
CONTAINER="${CONTAINER:-wintouch-crm-rails-1}"
DEV_CONTAINER="${DEV_CONTAINER:-wintouch-crm-rails-1}"
SSH="ssh -o ConnectTimeout=15"
RC=0

echo "══════ 1/3  守门 spec（能拦住 Pundit 500 这类上线即崩的错）══════"
SPECS="spec/policies/crm_mes_custom_action_coverage_spec.rb"
for s in spec/services/crm/agent/system_map_spec.rb \
         spec/services/crm/agent/inline_feature_coverage_spec.rb \
         spec/services/mes/todo_assignment_spec.rb \
         spec/services/crm/sales_order_assignment_spec.rb; do
  [ -f "$s" ] && SPECS="$SPECS $s"
done
# shellcheck disable=SC2086
# ⚠️ 只在**显示**上挑出摘要行；失败判定仍然读整份日志（下面那个 grep），
# 别改成管道过滤——截断日志正是当初漏推 10 个文件那次的根因。
if docker exec -e RAILS_ENV=test "$DEV_CONTAINER" bundle exec rspec $SPECS 2>&1 | tee /tmp/predeploy_spec.log | grep -E "examples?, .* failures?"; then
  grep -qE "[1-9][0-9]* failures?" /tmp/predeploy_spec.log && { echo "❌ spec 有失败，别部署"; RC=1; }
else
  echo "❌ spec 跑不起来"; RC=1
fi

echo
echo "══════ 2/3  本地代码树 vs 生产运行容器 ══════"
FIND='find app config lib db -type f \( -name "*.rb" -o -name "*.jbuilder" -o -name "*.vue" -o -name "*.js" -o -name "*.json" -o -name "*.yml" \) -not -path "*/node_modules/*" -not -name "._*"'
loc="$(mktemp)"; rem="$(mktemp)"
trap 'rm -f "$loc" "$rem"' EXIT

# macOS 的 md5 -r 与 Linux 的 md5sum 输出列序不同，统一成「路径 哈希」
eval "$FIND" | xargs md5 -r 2>/dev/null | awk '{print $2" "$1}' | LC_ALL=C sort > "$loc"
$SSH "$HOST" "sudo docker exec $CONTAINER sh -c 'cd /app && export LC_ALL=C && $FIND | xargs md5sum 2>/dev/null | awk \"{print \\\$2\\\" \\\"\\\$1}\" | LC_ALL=C sort'" > "$rem"

[ -s "$rem" ] || { echo "❌ 读不到生产容器"; exit 2; }
echo "本地 $(wc -l < "$loc") 文件 / 生产 $(wc -l < "$rem") 文件"

echo
echo "── 本次该部署的（内容不同 + 本地独有）──"
join "$loc" "$rem" | awk '$2!=$3{print "  → "$1}'
join -v1 "$loc" "$rem" | awk '{print "  + "$1"（生产还没有）"}'

echo
echo "── ⚠️ 只在生产有：别覆盖，先搞清是谁的热修 ──"
onlyprod="$(join -v2 "$loc" "$rem" | wc -l | tr -d ' ')"
if [ "$onlyprod" != "0" ]; then
  join -v2 "$loc" "$rem" | awk '{print "  ! "$1}'
  echo "  （$onlyprod 个。先反向合回 git，否则重建会把它们抹掉）"
  RC=1
else
  echo "  无"
fi

echo
echo "══════ 3/3  根目录构建配置 ══════"
# 为什么单列一节：上面那个 find 只扫 app/config/lib/db，根目录的 tailwind.config.js
# 一直在盲区里。漏推它的后果最阴——新 utility/animate 类名不会被生成，
# 构建不报错、页面也不报错，就是动画/样式静默失效（2026-10-28 Codex 改了动画关键帧时发现）。
ROOTCFG="tailwind.config.js postcss.config.js vite.config.ts vite.shared.ts package.json Gemfile Gemfile.lock"
rootdiff=0
for f in $ROOTCFG; do
  [ -f "$f" ] || continue
  l="$(md5 -q "$f" 2>/dev/null)"
  r="$($SSH "$HOST" "sudo docker exec $CONTAINER md5sum /app/$f 2>/dev/null | awk '{print \$1}'")"
  if [ -z "$r" ]; then
    echo "  ? $f（生产读不到）"
  elif [ "$l" != "$r" ]; then
    echo "  → $f"; rootdiff=$((rootdiff+1))
  fi
done
[ "$rootdiff" = "0" ] && echo "  无差异"

echo
[ "$RC" = "0" ] && echo "✅ 可以部署" || echo "❌ 先处理上面的问题"
exit $RC
