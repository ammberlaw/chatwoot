#!/usr/bin/env bash
# 部署后冒烟闸 —— 在生产服务器上运行（部署完立即跑）。
#
# 作用：三段验证，一条不过即退出码 1：
#   1) 健康：宿主 127.0.0.1:3000 首页返回 200（直连绕开 nginx 的下划线头坑）。
#   2) 关键接口探针：未带 token 访问核心 API，预期 401/403（鉴权拦截 = 控制器正常加载）。
#      若返回 500/502 = 该控制器启动即报错（代码/加载回退），立即暴露。
#   3) marker 核对：运行容器内 grep 本轮关键修复的方法/口径是否在（防重建静默回退）。
#
# 用法（生产机）：  bash scripts/smoke.sh
#   CONTAINER=... ACCOUNT_ID=1 BASE=http://127.0.0.1:3000 bash scripts/smoke.sh
set -uo pipefail

CONTAINER="${CONTAINER:-wintouch-crm-rails-1}"
BASE="${BASE:-http://127.0.0.1:3000}"
ACCOUNT_ID="${ACCOUNT_ID:-1}"
fail=0

echo "── 1) 健康 ──"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/" || echo 000)
if [ "$code" = "200" ]; then echo "  ✅ / = 200"; else echo "  ❌ / = $code"; fail=1; fi

echo "── 2) 关键接口探针（未认证应 401/403，出现 5xx = 控制器加载失败）──"
probe() { # $1=路径说明 $2=path
  local c; c=$(curl -s -o /dev/null -w '%{http_code}' "$BASE$2" || echo 000)
  case "$c" in
    401|403|422|404) echo "  ✅ $1 = $c";;
    5*|000|502)      echo "  ❌ $1 = $c（控制器可能启动即报错）"; fail=1;;
    *)               echo "  ⚠️  $1 = $c（非预期，请人工确认）";;
  esac
}
A="/api/v1/accounts/$ACCOUNT_ID"
probe "crm/customers"        "$A/crm/customers"
probe "crm/pis"             "$A/crm/pis"
probe "crm/quotes"          "$A/crm/quotes"
probe "crm/sales_orders"    "$A/crm/sales_orders"
probe "crm/emails"          "$A/crm/emails"
probe "crm/sales_targets"   "$A/crm/sales_targets"
probe "mes/dashboard"       "$A/mes/dashboard"
probe "mes/stock_entries"   "$A/mes/stock_entries"
probe "tiktok/profit_records" "$A/tiktok/profit_records"

echo "── 3) 运行容器 marker（关键修复是否在位）──"
marker() { # $1=说明 $2=grep模式 $3=文件
  local n; n=$(docker exec "$CONTAINER" sh -c "grep -c -- \"$2\" \"$3\" 2>/dev/null" || echo 0)
  if [ "${n:-0}" -ge 1 ]; then echo "  ✅ $1"; else echo "  ❌ $1（缺失，可能被重建回退）"; fail=1; fi
}
marker "IDOR 收口·visible_customers"   "def visible_customers"        /app/app/controllers/api/v1/accounts/crm/base_controller.rb
marker "IDOR 收口·PI fetch"            "scope_docs_visible(Current.account.crm_pis)" /app/app/controllers/api/v1/accounts/crm/pis_controller.rb
marker "币种折算·我的目标"             "RMB_AMOUNT_MICROS_SQL"        /app/app/controllers/api/v1/accounts/crm/my_target_controller.rb
marker "币种折算·经营月报"             "RMB_AMOUNT_MICROS_SQL"        /app/app/services/crm/monthly_report_service.rb
marker "TikTok 利润门禁"               "ensure_profit_access"         /app/app/controllers/api/v1/accounts/tiktok/profit_records_controller.rb
marker "授权补丁·stage_blob 策略"      "def stage_blob?"              /app/app/policies/mes/stock_entry_policy.rb

echo
if [ "$fail" -eq 0 ]; then echo "✅ 冒烟全过。"; exit 0; else echo "❌ 冒烟有未过项，请排查后再对外放量。"; exit 1; fi
