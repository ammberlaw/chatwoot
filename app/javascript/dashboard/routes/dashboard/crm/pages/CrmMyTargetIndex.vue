<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

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
const yearSelectOptions = yearOptions.map(y => ({ value: y, label: `${y}年` }));

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
const sign = n => {
  if (n > 0) return '+';
  if (n < 0) return '-';
  return '';
};
const signedMoney = micros => {
  const n = Math.round(yuan(micros));
  return `${sign(n)}¥${Math.abs(n).toLocaleString()}`;
};
const signedInt = n => `${sign(n)}${Math.abs(Math.round(n))}`;

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
    const baseAmount = Number(row.base_amount_micros) || 0;
    const baseCount = Number(row.base_count) || 0;
    const actualAmount = Number(row.actual_amount_micros) || 0;
    const actualCount = Number(row.actual_count) || 0;
    out.push({
      month: m,
      baseId: row.base_id,
      baseAmount,
      baseCount,
      carryAmount,
      carryCount,
      effAmount: baseAmount + carryAmount,
      effCount: baseCount + carryCount,
      actualAmount,
      actualCount,
      hasActivity: baseAmount > 0 || baseCount > 0 || actualCount > 0,
      isFuture,
    });
    cumBase += baseAmount;
    cumActual += actualAmount;
    cumBaseC += baseCount;
    cumActualC += actualCount;
  }
  return out;
});

const sel = computed(() => rows.value[selMonth.value]);

// 达成率：有效目标 ≤ 0（结余已覆盖）视为 100%
const pct = (actual, effTarget) => {
  // 兜底：任一侧不是有限数就不显示百分比，别把 NaN% 甩给用户
  if (!Number.isFinite(actual) || !Number.isFinite(effTarget)) return null;
  if (effTarget <= 0) return actual >= 0 ? 100 : null;
  return (actual / effTarget) * 100;
};
const barClass = p => {
  if (p == null) return 'bg-n-slate-6';
  if (p >= 100) return 'bg-n-teal-9';
  if (p >= 60) return 'bg-n-blue-9';
  if (p >= 30) return 'bg-n-iris-9';
  return 'bg-n-ruby-9';
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
    amountInput.value =
      s.baseAmount > 0 ? String(Math.round(yuan(s.baseAmount))) : '';
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
    achieve: p == null ? '—' : `${Math.round(p)}%`,
  };
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full gap-6 p-4 sm:p-8 overflow-auto bg-white rounded-3xl"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          我的目标
        </h1>
        <p v-if="!loading" class="mt-0.5 text-sm text-n-slate-11">
          {{ ytd.isCurrentYear ? '本季度至今' : '全年' }} 已完成
          {{ money(ytd.act) }} / {{ money(ytd.base) }} ·
          {{
            ytd.ahead >= 0
              ? `领先 ${money(ytd.ahead)}`
              : `落后 ${money(-ytd.ahead)}`
          }}
          · 未完成结转下月、每季度清零
        </p>
      </div>
      <SelectCard
        v-model="year"
        :options="yearSelectOptions"
        align="right"
        trigger-class="w-28"
      />
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">加载中…</div>

    <template v-else-if="sel">
      <div class="grid grid-cols-1 gap-5 lg:grid-cols-[1fr_1.4fr]">
        <section class="relative overflow-hidden rounded-3xl bg-[#fff4cc] p-5 sm:p-6 text-[#252630]">
          <div class="absolute -right-12 -top-16 size-56 rounded-full border-[32px] border-white/40 pointer-events-none" />
          <div class="relative">
            <div class="flex items-center gap-2 text-label text-[#86703a]">
              <span class="i-lucide-target size-5" />
              {{ year }}年{{ selMonth + 1 }}月目标
            </div>
            <p class="mt-4 text-label text-[#86703a]">有效成交额目标</p>
            <p class="mt-2 text-3xl sm:text-4xl font-semibold tabular-nums tracking-tight">{{ money(sel.effAmount) }}</p>
            <div class="mt-4 grid grid-cols-2 gap-4 border-t border-[#eadba8] pt-3">
              <div><p class="text-label-small text-[#8a7749]">基础目标</p><p class="mt-1 text-heading-2 font-semibold">{{ money(sel.baseAmount) }}</p></div>
              <div><p class="text-label-small text-[#8a7749]">上月结转</p><p class="mt-1 text-heading-2 font-semibold">{{ signedMoney(sel.carryAmount) }}</p></div>
            </div>
            <div class="mt-4 inline-flex items-center gap-2 rounded-full bg-white/65 px-3 py-2 text-label-small text-[#7d6936]">
              <span class="i-lucide-calendar-days size-4" />
              {{ sel.isFuture ? '该月尚未开始' : daysLeft != null ? `本月剩余 ${daysLeft} 天` : '历史月份' }}
            </div>
          </div>
        </section>
        <section class="rounded-3xl border border-[#e8eaed] bg-white p-5 sm:p-6">
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-heading-2 font-semibold text-[#24272b]">目标进度</h2>
            <span class="text-label-small text-[#92969c]">{{ selMonth + 1 }}月</span>
          </div>
          <div class="mt-4 space-y-4">
            <div v-for="metric in [
              { label: '成交额', actual: sel.actualAmount, target: sel.effAmount, money: true, color: 'bg-[#b6d9aa]' },
              { label: '新成交客户', actual: sel.actualCount, target: sel.effCount, money: false, color: 'bg-[#edce76]' },
            ]" :key="metric.label">
              <div class="flex items-center justify-between gap-3">
                <span class="text-label text-[#737880]">{{ metric.label }}</span>
                <span class="text-label-small font-medium text-[#686d75]">{{ sel.isFuture ? '未开始' : metric.target <= 0 && metric.actual === 0 ? '暂无有效目标' : `${Math.round(pct(metric.actual, metric.target) || 0)}%` }}</span>
              </div>
              <div class="mt-2 flex items-baseline gap-2 tabular-nums">
                <strong class="text-3xl font-semibold text-[#24272b]">{{ metric.money ? money(metric.actual) : metric.actual }}</strong>
                <span class="text-label text-[#92969c]">/ {{ metric.money ? money(metric.target) : `${metric.target} 位` }}</span>
              </div>
              <div class="mt-2 h-2 overflow-hidden rounded-full bg-[#f0f1f3]">
                <div class="h-full rounded-full transition-all duration-500" :class="metric.color" :style="{ width: metric.target <= 0 && metric.actual === 0 ? '0%' : metricLine(metric.actual, metric.target, metric.money).barWidth }" />
              </div>
            </div>
          </div>
          <div class="mt-4 flex items-center gap-2 border-t border-[#eeeff1] pt-4 text-label-small text-[#858a91]">
            <span class="i-lucide-info size-4 shrink-0" />
            {{ sel.isFuture ? '结转将在进入该月份时结算' : sel.effAmount > 0 ? `距离目标还差 ${money(remainingAmount)}` : sel.baseAmount === 0 && sel.carryAmount === 0 ? '可在下方设置本月基础目标' : '上月结余已覆盖本月目标' }}
          </div>
        </section>
      </div>

      <div class="grid grid-cols-1 items-start gap-5 xl:grid-cols-[minmax(0,1.8fr)_minmax(280px,1fr)]">
      <!-- 12 个月明细表 -->
      <div
        class="p-4 sm:p-5 border rounded-3xl border-[#e8eaed] bg-white"
      >
        <div class="flex items-center justify-between mb-2">
          <h2 class="text-heading-2 font-semibold text-n-slate-12">月度明细</h2>
          <!-- 走全站统一的槽（data-tabbar + aria-selected，样式在 _next-colors.scss）：
               灰槽 + 深色选中块。别在这儿再写底色/阴影，写了会跟统一规则打架。 -->
          <div data-tabbar="page" class="my-0">
            <button
              v-for="opt in [
                { k: 'amount', l: '成交额' },
                { k: 'customer', l: '新成交客户' },
              ]"
              :key="opt.k"
              :aria-selected="tableMetric === opt.k"
              @click="tableMetric = opt.k"
            >
              {{ opt.l }}
            </button>
          </div>
        </div>
        <!-- 手机卡片 -->
        <div class="flex max-h-80 overflow-y-auto flex-col gap-2 md:hidden">
          <div
            v-for="r in rows"
            :key="r.month"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            :class="{
              'ring-1 ring-n-iris-9': r.month === selMonth,
              'opacity-70': r.isFuture,
            }"
            @click="selectMonth(r.month)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ r.month + 1 }}月
              </span>
              <span class="flex-1" />
              <span class="text-xs shrink-0 text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').achieve }}
              </span>
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-2 text-xs text-n-slate-11"
            >
              <span
                >基础目标：{{ cell(r, tableMetric === 'amount').base }}</span
              >
              <span
                :class="
                  cell(r, tableMetric === 'amount').carry === '—'
                    ? ''
                    : cell(r, tableMetric === 'amount').carryUp
                      ? 'text-n-iris-11'
                      : 'text-n-teal-11'
                "
              >
                结转：{{ cell(r, tableMetric === 'amount').carry }}
              </span>
              <span>有效目标：{{ cell(r, tableMetric === 'amount').eff }}</span>
              <span
                >已完成：{{ cell(r, tableMetric === 'amount').actual }}</span
              >
            </div>
          </div>
        </div>

        <div class="hidden max-h-80 overflow-y-auto md:block">
        <table class="w-full text-label-small tabular-nums">
          <thead class="sticky top-0 z-10 bg-white text-n-slate-10">
            <tr class="border-b border-n-weak">
              <th class="px-3 py-2 font-medium text-left">月份</th>
              <th class="px-3 py-2 font-medium text-right">基础目标</th>
              <th class="px-3 py-2 font-medium text-right">结转</th>
              <th class="px-3 py-2 font-medium text-right">有效目标</th>
              <th class="px-3 py-2 font-medium text-right">已完成</th>
              <th class="px-3 py-2 font-medium text-right">达成</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="r in rows"
              :key="r.month"
              class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
              :class="{
                'bg-[#fff6da]': r.month === selMonth,
                'text-n-slate-10': r.isFuture,
              }"
              @click="selectMonth(r.month)"
            >
              <td class="px-3 py-2 text-n-slate-12">{{ r.month + 1 }}月</td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').base }}
              </td>
              <td
                class="px-3 py-2 text-right"
                :class="
                  cell(r, tableMetric === 'amount').carry === '—'
                    ? 'text-n-slate-10'
                    : cell(r, tableMetric === 'amount').carryUp
                      ? 'text-n-iris-11'
                      : 'text-n-teal-11'
                "
              >
                {{ cell(r, tableMetric === 'amount').carry }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').eff }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').actual }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ cell(r, tableMetric === 'amount').achieve }}
              </td>
            </tr>
          </tbody>
        </table>
        </div>
      </div>

      <!-- 就地编辑基础目标 -->
      <div
        class="p-5 sm:p-7 border rounded-3xl border-[#e8eaed] bg-white"
      >
        <h2 class="text-heading-2 font-semibold text-n-slate-12">
          设定 / 修改 {{ year }}年{{ selMonth + 1 }}月 基础目标
        </h2>
        <div class="flex flex-col items-stretch gap-4 mt-4">
          <label class="flex flex-col items-start gap-2">
            <span class="text-label text-n-slate-11">成交额 ¥</span>
            <input
              v-model="amountInput"
              type="number"
              min="0"
              step="1000"
              class="h-9 px-2 text-sm border rounded-lg w-36 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
            />
          </label>
          <label class="flex flex-col items-start gap-2">
            <span class="text-label text-n-slate-11">新客户数</span>
            <input
              v-model="countInput"
              type="number"
              min="0"
              step="1"
              class="h-9 px-2 text-sm border rounded-lg w-28 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
            />
          </label>
          <button
            class="h-10 px-4 text-label font-semibold transition-colors rounded-xl !bg-[#ffd34f] !text-[#29251b] motion-reduce:transition-none hover:!bg-[#f5c53d] disabled:!bg-[#fff0b5] disabled:!text-[#786533] disabled:opacity-100 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#d7ad36]"
            :disabled="!canSave"
            @click="saveTarget"
          >
            {{ saving ? '保存中…' : sel.baseId ? '更新目标' : '设定目标' }}
          </button>
        </div>
        <div class="mt-3 text-xs text-n-slate-10">
          这里设的是「基础目标」；结转由系统按未完成额自动逐月累加,无需手填。成交额、新客户数至少填一项,留空按
          0 记。新客户 = 本月首次成交的客户（按客户去重）。
        </div>
      </div>
      </div>
    </template>
  </div>
</template>
