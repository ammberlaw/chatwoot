<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const { accountId } = useAccount();

const now = new Date();
const nowYear = now.getFullYear();
const nowMonth = now.getMonth(); // 0-11

const loading = ref(true);
const saving = ref(false);
const months = ref([]);
const year = ref(nowYear);
const selMonth = ref(nowMonth); // 0-11
const tableMetric = ref('amount'); // amount | customer
const amountInput = ref('');
const countInput = ref('');

const yearOptions = [nowYear - 2, nowYear - 1, nowYear, nowYear + 1];

const api = () => `/api/v1/accounts/${accountId.value}/crm`;

const fetchData = async () => {
  loading.value = true;
  try {
    const { data } = await axios.get(`${api()}/my_target`, {
      params: { year: year.value },
    });
    months.value = data.months;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);
watch(year, () => {
  selMonth.value = year.value === nowYear ? nowMonth : 0;
  fetchData();
});

const yuan = micros => (micros || 0) / 1_000_000;
const money = micros => {
  const n = Math.round(yuan(micros));
  return `${n < 0 ? '-¥' : '¥'}${Math.abs(n).toLocaleString()}`;
};
const signedMoney = micros => {
  const n = Math.round(yuan(micros));
  return `${n > 0 ? '+' : n < 0 ? '-' : ''}¥${Math.abs(n).toLocaleString()}`;
};
const signedInt = n => `${n > 0 ? '+' : n < 0 ? '-' : ''}${Math.abs(Math.round(n))}`;

// ── 结转计算：季度内逐月滚，每季度初(0/3/6/9)清零 ──
const rows = computed(() => {
  const src = months.value;
  if (!src.length) return [];
  const out = [];
  let cumBase = 0;
  let cumActual = 0;
  let cumBaseC = 0;
  let cumActualC = 0;
  for (let m = 0; m < 12; m += 1) {
    if (m % 3 === 0) {
      cumBase = 0;
      cumActual = 0;
      cumBaseC = 0;
      cumActualC = 0;
    }
    const row = src[m];
    const isFuture =
      year.value > nowYear || (year.value === nowYear && m > nowMonth);
    const carryAmount = isFuture ? 0 : cumBase - cumActual;
    const carryCount = isFuture ? 0 : cumBaseC - cumActualC;
    const baseAmount = row.base_amount_micros;
    const baseCount = row.base_count;
    out.push({
      month: m,
      baseId: row.base_id,
      baseAmount,
      baseCount,
      carryAmount,
      carryCount,
      effAmount: baseAmount + carryAmount,
      effCount: baseCount + carryCount,
      actualAmount: row.actual_amount_micros,
      actualCount: row.actual_count,
      hasActivity: baseAmount > 0 || baseCount > 0 || row.actual_count > 0,
      isFuture,
    });
    cumBase += baseAmount;
    cumActual += row.actual_amount_micros;
    cumBaseC += baseCount;
    cumActualC += row.actual_count;
  }
  return out;
});

const sel = computed(() => rows.value[selMonth.value]);

// 达成率：有效目标 ≤ 0（结余已覆盖）视为 100%
const pct = (actual, effTarget) => {
  if (effTarget <= 0) return actual >= 0 ? 100 : null;
  return (actual / effTarget) * 100;
};
const barClass = p => {
  if (p == null) return 'bg-n-slate-6';
  if (p >= 100) return 'bg-n-teal-9';
  if (p >= 60) return 'bg-n-blue-9';
  if (p >= 30) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};
const dot = p => {
  if (p == null) return '·';
  if (p >= 100) return '🟢';
  if (p >= 60) return '🔵';
  if (p >= 30) return '🟠';
  return '🔴';
};
const barWidth = p => `${Math.min(100, Math.max(2, p ?? 0))}%`;

const metricLine = (actual, effTarget, isMoney) => {
  const p = pct(actual, effTarget);
  const fmt = n => (isMoney ? money(n) : String(Math.round(n)));
  return {
    barClass: barClass(p),
    barWidth: barWidth(p),
    text: `${fmt(actual)} / ${fmt(effTarget)}${p == null ? '' : `（${Math.round(p)}%）`}`,
  };
};

// 本季度至今累计（结转按季度清零，顶部展示本季度整体达标）
const ytd = computed(() => {
  const isCurrentYear = year.value === nowYear;
  const from = isCurrentYear ? Math.floor(nowMonth / 3) * 3 : 0;
  const upto = isCurrentYear ? nowMonth : 11;
  let base = 0;
  let act = 0;
  for (let m = from; m <= upto; m += 1) {
    base += rows.value[m]?.baseAmount ?? 0;
    act += rows.value[m]?.actualAmount ?? 0;
  }
  return { base, act, isCurrentYear, ahead: act - base };
});

const daysLeft = computed(() => {
  if (year.value !== nowYear || selMonth.value !== nowMonth) return null;
  const end = new Date(year.value, selMonth.value + 1, 1);
  return Math.ceil((end.getTime() - now.getTime()) / 86_400_000);
});

const remainingAmount = computed(() =>
  sel.value ? Math.max(0, sel.value.effAmount - sel.value.actualAmount) : 0
);

// 选中月变化时用其基础目标预填编辑框
watch(
  sel,
  s => {
    if (!s) return;
    amountInput.value = s.baseAmount > 0 ? String(Math.round(yuan(s.baseAmount))) : '';
    countInput.value = s.baseCount > 0 ? String(s.baseCount) : '';
  },
  { immediate: true }
);

const selectMonth = m => {
  selMonth.value = m;
};

const canSave = computed(() => {
  const a = String(amountInput.value ?? '').trim();
  const c = String(countInput.value ?? '').trim();
  const aOk = a !== '' && Number(a) >= 0;
  const cOk = c !== '' && Number.isInteger(Number(c)) && Number(c) >= 0;
  return !saving.value && (aOk || cOk);
});

const saveTarget = async () => {
  if (!canSave.value || !sel.value) return;
  saving.value = true;
  const a = String(amountInput.value ?? '').trim();
  const c = String(countInput.value ?? '').trim();
  const payload = {
    target_amount_micros: a !== '' ? Math.round(Number(a) * 1_000_000) : 0,
    target_order_count: c !== '' ? Number(c) : 0,
  };
  const monthLabel = `${year.value}-${String(selMonth.value + 1).padStart(2, '0')}`;
  try {
    if (sel.value.baseId) {
      await axios.patch(`${api()}/sales_targets/${sel.value.baseId}`, {
        target: payload,
      });
    } else {
      await axios.post(`${api()}/sales_targets`, {
        target: {
          ...payload,
          name: `${monthLabel} 目标`,
          target_month: `${monthLabel}-01`,
        },
      });
    }
    await fetchData();
    useAlert('目标已保存');
  } catch {
    useAlert('保存失败');
  } finally {
    saving.value = false;
  }
};

const cell = (r, isAmt) => {
  const base = isAmt ? r.baseAmount : r.baseCount;
  const carry = isAmt ? r.carryAmount : r.carryCount;
  const eff = isAmt ? r.effAmount : r.effCount;
  const act = isAmt ? r.actualAmount : r.actualCount;
  const fv = n => (isAmt ? money(n) : String(Math.round(n)));
  const fc = n => (isAmt ? signedMoney(n) : signedInt(n));
  const p = r.isFuture ? null : pct(act, eff);
  const showActual = !r.isFuture && (r.hasActivity || act > 0);
  return {
    base: base > 0 ? fv(base) : '—',
    carry: r.isFuture || carry === 0 ? '—' : fc(carry),
    carryUp: carry > 0,
    eff: fv(eff),
    actual: showActual ? fv(act) : '—',
    achieve: p == null ? '—' : `${dot(p)} ${Math.round(p)}%`,
  };
};
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 p-6 overflow-auto bg-n-background">
    <div class="flex flex-wrap items-center gap-3">
      <h1 class="text-xl font-medium text-n-slate-12">🎯 我的目标</h1>
      <select
        v-model.number="year"
        class="h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
      >
        <option v-for="y in yearOptions" :key="y" :value="y">{{ y }}年</option>
      </select>
      <span v-if="!loading" class="text-xs text-n-slate-11">
        {{ ytd.isCurrentYear ? '本季度至今' : '全年' }}：已完成
        {{ money(ytd.act) }} / 目标 {{ money(ytd.base) }}（{{
          ytd.ahead >= 0
            ? `领先 ${money(ytd.ahead)}`
            : `落后 ${money(-ytd.ahead)}`
        }}）· 未完成结转下月、每季度清零
      </span>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">加载中…</div>

    <template v-else-if="sel">
      <!-- 聚焦月卡片 -->
      <div class="p-4 border rounded-xl border-n-blue-8 bg-n-solid-1">
        <div class="font-medium text-n-slate-12">
          {{ year }}年{{ selMonth + 1 }}月 · 有效目标 {{ money(sel.effAmount) }}
        </div>
        <div class="mt-1 text-xs text-n-slate-11">
          基础目标 {{ money(sel.baseAmount) }}
          <template v-if="sel.carryAmount !== 0">
            ·
            <span :class="sel.carryAmount > 0 ? 'text-n-amber-11' : 'text-n-teal-11'">
              {{ sel.carryAmount > 0 ? '上月缺口' : '上月结余' }}
              {{ signedMoney(sel.carryAmount) }}
            </span>
          </template>
        </div>
        <div class="flex flex-col gap-2 mt-3">
          <div
            v-for="line in [
              { label: '成交额', m: metricLine(sel.actualAmount, sel.effAmount, true) },
              { label: '新客户', m: metricLine(sel.actualCount, sel.effCount, false) },
            ]"
            :key="line.label"
            class="flex items-center gap-3 text-sm"
          >
            <span class="text-xs w-12 shrink-0 text-n-slate-11">
              {{ line.label }}
            </span>
            <div class="flex-1 h-4 overflow-hidden rounded-full bg-n-alpha-2">
              <div
                class="h-full rounded-full"
                :class="line.m.barClass"
                :style="{ width: line.m.barWidth }"
              />
            </div>
            <span class="text-xs text-right w-52 shrink-0 text-n-slate-11">
              {{ line.m.text }}
            </span>
          </div>
        </div>
        <div class="pt-2 mt-3 text-xs border-t border-dashed border-n-weak text-n-slate-11">
          <span v-if="sel.isFuture">该月未开始 · 仅显示基础目标,结转到该月时才结算</span>
          <span v-else-if="sel.effAmount > 0">
            距本月有效目标还差
            <strong class="text-n-slate-12">{{ money(remainingAmount) }}</strong>
          </span>
          <span v-else>上月结余已覆盖本月目标 ✓</span>
          <span v-if="daysLeft != null" class="ml-4">
            剩 <strong class="text-n-slate-12">{{ daysLeft }}</strong> 天
          </span>
        </div>
      </div>

      <!-- 12 个月明细表 -->
      <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
        <div class="flex items-center justify-between mb-3">
          <span class="font-medium text-n-slate-12">月度明细</span>
          <div class="flex gap-1">
            <button
              v-for="opt in [
                { k: 'amount', l: '成交额' },
                { k: 'customer', l: '新成交客户' },
              ]"
              :key="opt.k"
              class="h-7 px-3 text-xs border rounded-lg"
              :class="
                tableMetric === opt.k
                  ? 'bg-n-blue-9 text-white border-n-blue-9'
                  : 'border-n-weak text-n-slate-11'
              "
              @click="tableMetric = opt.k"
            >
              {{ opt.l }}
            </button>
          </div>
        </div>
        <table class="w-full text-xs">
          <thead class="text-n-slate-10">
            <tr class="border-b border-n-weak">
              <th class="px-2 py-2 font-medium text-left">月份</th>
              <th class="px-2 py-2 font-medium text-right">基础目标</th>
              <th class="px-2 py-2 font-medium text-right">结转</th>
              <th class="px-2 py-2 font-medium text-right">有效目标</th>
              <th class="px-2 py-2 font-medium text-right">已完成</th>
              <th class="px-2 py-2 font-medium text-right">达成</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="r in rows"
              :key="r.month"
              class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
              :class="{
                'bg-n-alpha-2': r.month === selMonth,
                'text-n-slate-10': r.isFuture,
              }"
              @click="selectMonth(r.month)"
            >
              <td class="px-2 py-2 text-n-slate-12">{{ r.month + 1 }}月</td>
              <td class="px-2 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').base }}
              </td>
              <td
                class="px-2 py-2 text-right"
                :class="
                  cell(r, tableMetric === 'amount').carry === '—'
                    ? 'text-n-slate-10'
                    : cell(r, tableMetric === 'amount').carryUp
                      ? 'text-n-amber-11'
                      : 'text-n-teal-11'
                "
              >
                {{ cell(r, tableMetric === 'amount').carry }}
              </td>
              <td class="px-2 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').eff }}
              </td>
              <td class="px-2 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').actual }}
              </td>
              <td class="px-2 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').achieve }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 就地编辑基础目标 -->
      <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
        <div class="font-medium text-n-slate-12">
          设定 / 修改 {{ year }}年{{ selMonth + 1 }}月 基础目标
        </div>
        <div class="flex flex-wrap items-center gap-3 mt-3">
          <label class="flex items-center gap-2">
            <span class="text-xs text-n-slate-11">成交额 ¥</span>
            <input
              v-model="amountInput"
              type="number"
              min="0"
              step="1000"
              placeholder="如 100000"
              class="h-8 px-2 text-sm border rounded-lg w-36 border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex items-center gap-2">
            <span class="text-xs text-n-slate-11">新客户数</span>
            <input
              v-model="countInput"
              type="number"
              min="0"
              step="1"
              placeholder="如 5"
              class="h-8 px-2 text-sm border rounded-lg w-28 border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <button
            class="h-8 px-4 text-sm text-white rounded-lg bg-n-blue-9 disabled:opacity-50"
            :disabled="!canSave"
            @click="saveTarget"
          >
            {{ saving ? '保存中…' : sel.baseId ? '更新目标' : '设定目标' }}
          </button>
        </div>
        <div class="mt-2 text-xs text-n-slate-10">
          这里设的是「基础目标」；结转由系统按未完成额自动逐月累加,无需手填。成交额、新客户数至少填一项,留空按
          0 记。新客户 = 本月首次成交的客户（按客户去重）。
        </div>
      </div>
    </template>
  </div>
</template>
