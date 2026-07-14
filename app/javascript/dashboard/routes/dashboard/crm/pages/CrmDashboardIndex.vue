<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

import CrmAreaChart from 'dashboard/components-next/CRM/charts/CrmAreaChart.vue';
import CrmBarChart from 'dashboard/components-next/CRM/charts/CrmBarChart.vue';
import CrmDoughnutChart from 'dashboard/components-next/CRM/charts/CrmDoughnutChart.vue';
import { themeColor } from 'dashboard/components-next/CRM/charts/chartColors';

const { t } = useI18n();
const route = useRoute();
const { accountId } = useAccount();

const stats = ref(null);
const loading = ref(true);
const error = ref(false);

const period = ref('month'); // month | quarter | year
const selectedMonth = ref(new Date().getMonth() + 1); // 1-12
const selectedYear = ref(new Date().getFullYear());
const yearOptions = [
  new Date().getFullYear() - 2,
  new Date().getFullYear() - 1,
  new Date().getFullYear(),
];

// 季度 ↔ selectedMonth 互映（季度用当季首月定位对应桶）
const selectedQuarter = computed({
  get: () => Math.floor((selectedMonth.value - 1) / 3) + 1,
  set: q => {
    selectedMonth.value = (q - 1) * 3 + 1;
  },
});

const scope = computed(() =>
  route.query.scope === 'mine' ? 'mine' : 'company'
);

const STAGE_LABELS = {
  NEEDS_CONFIRMED: '需求确认',
  SAMPLING: '样品中',
  WON: '已成交',
  LOST: '输单',
};
// 液态玻璃竖柱：浅色 iris 渐变，越接近成交越实；输单浅粉
const STAGE_GRADIENTS = {
  NEEDS_CONFIRMED: 'from-n-iris-3 to-n-iris-6',
  SAMPLING: 'from-n-iris-4 to-n-iris-7',
  WON: 'from-n-iris-5 to-n-iris-8',
  LOST: 'from-n-ruby-3 to-n-ruby-5',
};

const SOURCE_LABELS = {
  ALIBABA: '阿里巴巴国际站',
  WEBSITE: '官网',
  EXHIBITION: '展会',
  EMAIL: '邮件开发',
  OTHER: '其他',
};
// 环形图冷色系（紫-靛-蓝，无黄，切片可区分又协调）
const SOURCE_COLOR_KEYS = [
  'iris-9',
  'iris-9',
  'blue-9',
  'iris-6',
  'iris-6',
  'blue-6',
];

// KPI 浅卡图标 chip 配色（长春花冷调）。
const ACCENTS = {
  green: { text: 'text-n-iris-11', soft: 'bg-n-iris-3' },
  iris: { text: 'text-n-iris-11', soft: 'bg-n-iris-3' },
};

// MedFlow 式多色柔和渐变：跨卡黄→薄荷绿→蜜桃橙流动。完整字面量供 Tailwind 收录。
const CARD_GRADIENTS = [
  'from-n-iris-3 to-n-teal-3',
  'from-n-teal-3 to-n-iris-3',
  'from-n-iris-3 to-n-iris-5',
  'from-n-iris-4 to-n-teal-4',
];

const fetchStats = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/stats`,
      {
        params: {
          scope: scope.value === 'mine' ? 'mine' : undefined,
          year: selectedYear.value,
        },
      }
    );
    stats.value = data;
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchStats);
watch([scope, selectedYear], fetchStats);

const toYuan = micros => Math.round((micros || 0) / 1_000_000);
const money = micros => `¥${toYuan(micros).toLocaleString()}`;
const moneyYuan = v => `¥${Math.round(v).toLocaleString()}`;
const hoursFmt = v => `${v}h`;
const scoreFmt = v => `${v}分`;

// ── KPI（按 period 读桶 + 真实环比） ──
const periodStat = computed(() => {
  const ps = stats.value?.period_stats;
  if (!ps)
    return {
      amount_micros: 0,
      order_count: 0,
      deal_customers: 0,
      new_customers: 0,
    };
  if (period.value === 'year') return ps.yearly;
  if (period.value === 'quarter') {
    const q = Math.floor((selectedMonth.value - 1) / 3);
    return ps.quarterly[q] || ps.quarterly[0];
  }
  return ps.monthly[selectedMonth.value - 1] || ps.monthly[0];
});

const periodLabel = computed(() => {
  const y = stats.value?.year || new Date().getFullYear();
  if (period.value === 'year') return `${y}年`;
  if (period.value === 'quarter') {
    return `${y}年 Q${Math.floor((selectedMonth.value - 1) / 3) + 1}`;
  }
  return `${y}年${selectedMonth.value}月`;
});

const salesKpis = computed(() => {
  const s = periodStat.value;
  return [
    {
      label: 'GMV',
      value: money(s.amount_micros),
      sub: periodLabel.value,
      icon: 'i-lucide-wallet',
    },
    {
      label: '成交订单数',
      value: s.order_count,
      sub: '笔',
      icon: 'i-lucide-shopping-bag',
    },
    {
      label: '成交客户数',
      value: s.deal_customers,
      sub: '家',
      icon: 'i-lucide-building-2',
    },
    {
      label: '新成交客户数',
      value: s.new_customers,
      sub: '家',
      icon: 'i-lucide-user-plus',
    },
  ];
});

// ── 目标完成率（半圆仪表） ──
const targetProgress = computed(() => {
  const targetMicros = stats.value?.target?.amount_micros || 0;
  const done = stats.value?.target?.month_amount_micros || 0;
  if (!targetMicros) return null;
  return {
    target: money(targetMicros),
    done: money(done),
    pct: Math.min(100, Math.round((done / targetMicros) * 100)),
  };
});

// ── 月度成交额趋势（面积图） ──
const trendChart = computed(() => {
  const arr = stats.value?.trends?.monthly_amount_micros || [];
  const current = new Date().getMonth() + 1;
  return {
    labels: arr.map((_, i) => `${i + 1}月`),
    data: arr.map(toYuan),
    activeIndex: current - 1,
    empty: !arr.some(v => v),
  };
});

// ── 商机阶段（液态玻璃竖柱） ──
const stageChart = computed(() => {
  const byStage = stats.value?.trends?.opportunity_amount_by_stage || {};
  const cntStage = stats.value?.trends?.opportunity_count_by_stage || {};
  const rows = Object.keys(STAGE_LABELS)
    .map(stage => ({
      stage,
      micros: byStage[stage] || 0,
      count: cntStage[stage] || 0,
    }))
    .filter(r => r.micros || r.count);
  const max = Math.max(1, ...rows.map(r => r.micros));
  return {
    empty: !rows.length,
    bars: rows.map(r => ({
      stage: r.stage,
      label: STAGE_LABELS[r.stage],
      amount: toYuan(r.micros),
      count: r.count,
      heightPct: Math.max(Math.round((r.micros / max) * 100), r.micros ? 8 : 4),
      gradient: STAGE_GRADIENTS[r.stage],
      isLost: r.stage === 'LOST',
    })),
  };
});

// 转化率：已成交金额 / 全部商机金额
const winRate = computed(() => {
  const byStage = stats.value?.trends?.opportunity_amount_by_stage || {};
  const total = Object.values(byStage).reduce((a, b) => a + (b || 0), 0);
  if (!total) return null;
  return Math.round(((byStage.WON || 0) / total) * 100);
});

// ── 客户来源占比（环形） ──
const sourceDonut = computed(() => {
  const breakdown = stats.value?.source_breakdown || {};
  const rows = Object.entries(breakdown)
    .filter(([k, v]) => v && k !== 'REFERRAL')
    .sort((a, b) => b[1] - a[1]);
  return {
    labels: rows.map(([k]) => SOURCE_LABELS[k] || k),
    data: rows.map(([, v]) => v),
    colors: rows.map((_, i) =>
      themeColor(SOURCE_COLOR_KEYS[i % SOURCE_COLOR_KEYS.length])
    ),
    total: rows.reduce((a, [, v]) => a + v, 0),
    empty: !rows.length,
  };
});

// ── 业务员成交排行（横向柱） ──
const ownerRank = computed(() => {
  const by = stats.value?.team?.by_owner_amount || {};
  const rows = Object.entries(by)
    .filter(([, v]) => v)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8);
  return {
    labels: rows.map(([k]) => k),
    data: rows.map(([, v]) => toYuan(v)),
    empty: !rows.length,
  };
});

// ── 业务员平均回复时长（越短越好，升序排） ──
const ownerLatency = computed(() => {
  const by = stats.value?.team?.by_owner_reply_latency || {};
  const rows = Object.entries(by)
    .filter(([, v]) => v != null)
    .sort((a, b) => a[1] - b[1])
    .slice(0, 8);
  return {
    labels: rows.map(([k]) => k),
    data: rows.map(([, v]) => v),
    empty: !rows.length,
  };
});

// ── 业务员资料完善度（越高越好，降序排） ──
const ownerCompleteness = computed(() => {
  const by = stats.value?.team?.by_owner_completeness || {};
  const rows = Object.entries(by)
    .filter(([, v]) => v != null)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8);
  return {
    labels: rows.map(([k]) => k),
    data: rows.map(([, v]) => v),
    empty: !rows.length,
  };
});

// ── 累计概览 ──
const totalCards = computed(() => {
  const tt = stats.value?.totals;
  if (!tt) return [];
  return [
    {
      label: '客户总数',
      value: tt.total_customers,
      accent: 'green',
      icon: 'i-lucide-users',
    },
    {
      label: '成交客户数',
      value: tt.won_customers,
      accent: 'green',
      icon: 'i-lucide-user-check',
    },
    {
      label: '进行中商机',
      value: tt.open_opportunities,
      accent: 'iris',
      icon: 'i-lucide-target',
    },
    {
      label: '公海客户',
      value: tt.public_pool_customers,
      accent: 'iris',
      icon: 'i-lucide-waves',
    },
    {
      label: '订单总额（累计）',
      value: money(tt.total_order_amount_micros),
      accent: 'green',
      icon: 'i-lucide-banknote',
    },
    {
      label: '平均回复时长',
      value:
        tt.avg_reply_latency_hours != null
          ? `${tt.avg_reply_latency_hours}h`
          : '—',
      accent: 'iris',
      icon: 'i-lucide-clock',
    },
  ];
});

const PERIODS = [
  { k: 'month', l: '月度' },
  { k: 'quarter', l: '季度' },
  { k: 'year', l: '年度' },
];
</script>

<template>
  <div
    class="flex flex-col w-full h-full gap-4 p-6 overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 顶栏 -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          {{
            scope === 'mine'
              ? t('CRM.DASHBOARD.HEADER_MINE')
              : t('CRM.DASHBOARD.HEADER_COMPANY')
          }}
        </h1>
        <p class="mt-0.5 text-sm text-n-slate-11">
          {{ periodLabel }} ·
          {{ scope === 'mine' ? '我的业绩' : '全公司概览' }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <div class="flex items-center h-9 gap-1 px-1 rounded-lg bg-n-alpha-1">
          <button
            v-for="p in PERIODS"
            :key="p.k"
            :aria-pressed="period === p.k"
            class="h-7 px-3 text-sm transition-colors rounded-md shrink-0 whitespace-nowrap motion-reduce:transition-none focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
            :class="
              period === p.k
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="period = p.k"
          >
            {{ p.l }}
          </button>
        </div>
        <select
          v-if="period === 'month'"
          v-model.number="selectedMonth"
          class="h-9 px-2 text-sm border rounded-lg shrink-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
        >
          <option v-for="m in 12" :key="m" :value="m">{{ m }}月</option>
        </select>
        <select
          v-else-if="period === 'quarter'"
          v-model.number="selectedQuarter"
          class="h-9 px-2 text-sm border rounded-lg shrink-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
        >
          <option v-for="q in 4" :key="q" :value="q">Q{{ q }}</option>
        </select>
        <select
          v-else
          v-model.number="selectedYear"
          class="h-9 px-2 text-sm border rounded-lg shrink-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
        >
          <option v-for="y in yearOptions" :key="y" :value="y">{{ y }}年</option>
        </select>
      </div>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.DASHBOARD.LOADING') }}
    </div>

    <div
      v-else-if="error"
      role="alert"
      class="flex flex-col items-center gap-3 p-10 text-center border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
    >
      <span class="i-lucide-cloud-off size-8 text-n-slate-10" />
      <p class="text-sm text-n-slate-11">数据加载失败，请检查网络后重试。</p>
      <button
        class="h-9 px-4 text-sm font-medium transition-colors rounded-lg bg-n-iris-9 text-n-slate-12 motion-reduce:transition-none hover:bg-n-iris-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
        @click="fetchStats"
      >
        重新加载
      </button>
    </div>

    <template v-else>
      <!-- ═══ 第 1 行：KPI ═══ -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <!-- MedFlow 式暖色浅渐变卡（深字 + 真实涨跌角标） -->
        <div
          v-for="(kpi, i) in salesKpis"
          :key="kpi.label"
          class="flex flex-col justify-between p-5 shadow-sm rounded-2xl bg-gradient-to-br min-h-[8.5rem]"
          :class="CARD_GRADIENTS[i]"
        >
          <div
            class="flex items-center justify-center rounded-lg size-9 bg-n-solid-1/70 text-n-iris-11"
          >
            <span class="size-5" :class="[kpi.icon]" />
          </div>
          <div>
            <div class="mt-4 text-sm font-medium text-n-slate-11">
              {{ kpi.label }}
            </div>
            <div class="mt-1 text-2xl font-bold text-n-slate-12">
              {{ kpi.value }}
            </div>
            <div class="mt-1 text-xs text-n-slate-10">{{ kpi.sub }}</div>
          </div>
        </div>
      </div>

      <!-- ═══ 第 2 行：商机阶段漏斗 + 目标仪表 ═══ -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div
          class="p-5 border shadow-sm lg:col-span-2 rounded-2xl border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-base font-medium text-n-slate-12">商机阶段分布</h2>
            <span v-if="winRate != null" class="text-xs text-n-slate-11">
              成交转化率
              <span class="font-semibold text-n-iris-11">{{ winRate }}%</span>
            </span>
          </div>
          <div class="h-64">
            <div v-if="!stageChart.empty" class="flex items-end gap-3 pt-3">
              <div
                v-for="bar in stageChart.bars"
                :key="bar.stage"
                class="flex flex-col items-center flex-1 min-w-0"
              >
                <div
                  class="flex flex-col items-center justify-end w-full gap-2 h-[204px]"
                >
                  <span
                    class="text-[13px] font-bold text-n-slate-12 whitespace-nowrap"
                  >
                    {{ moneyYuan(bar.amount) }}
                  </span>
                  <div
                    class="relative w-14 overflow-hidden border shadow-lg rounded-t-2xl rounded-b-md border-white/80 bg-gradient-to-b shadow-n-iris-9/30"
                    :class="bar.gradient"
                    :style="{ height: `${bar.heightPct}%` }"
                  >
                    <div
                      class="absolute top-1 h-1/3 inset-x-1 rounded-t-xl bg-gradient-to-b from-white/70 to-transparent"
                    />
                  </div>
                </div>
                <span
                  class="mt-3 text-[13px] font-medium"
                  :class="bar.isLost ? 'text-n-ruby-11' : 'text-n-slate-11'"
                >
                  {{ bar.label }}
                </span>
                <span class="mt-0.5 text-[11px] text-n-slate-10">
                  {{ bar.count }} 个
                </span>
              </div>
            </div>
            <div
              v-else
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              暂无商机数据
            </div>
          </div>
        </div>

        <div
          class="p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
        >
          <h2 class="mb-2 text-base font-medium text-n-slate-12">
            本月目标完成率
          </h2>
          <template v-if="targetProgress">
            <div class="h-48 mx-auto max-w-[16rem]">
              <CrmDoughnutChart
                :data="[targetProgress.pct, 100 - targetProgress.pct]"
                gauge
                cutout="78%"
              >
                <template #center>
                  <div class="text-3xl font-bold text-n-slate-12">
                    {{ targetProgress.pct }}%
                  </div>
                </template>
              </CrmDoughnutChart>
            </div>
            <div class="text-center text-n-slate-11">
              <span class="font-medium text-n-slate-12">
                {{ targetProgress.done }}
              </span>
              / {{ targetProgress.target }}
            </div>
          </template>
          <div
            v-else
            class="flex flex-col items-center justify-center gap-1 py-10 text-center"
          >
            <span class="i-lucide-target size-6 text-n-slate-10" />
            <p class="text-sm text-n-slate-11">本月尚未设定目标</p>
            <p class="text-xs text-n-slate-10">前往「我的目标」设定</p>
          </div>
        </div>
      </div>

      <!-- ═══ 第 3 行：趋势面积图 + 来源环形 ═══ -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div
          class="p-5 border shadow-sm lg:col-span-2 rounded-2xl border-n-weak bg-n-solid-1"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            订单金额趋势
          </h2>
          <div class="h-64">
            <CrmAreaChart
              v-if="!trendChart.empty"
              :labels="trendChart.labels"
              :data="trendChart.data"
              :active-index="trendChart.activeIndex"
              :value-format="moneyYuan"
            />
            <div
              v-else
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              暂无趋势数据
            </div>
          </div>
        </div>

        <div
          class="p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            客户来源占比
          </h2>
          <template v-if="!sourceDonut.empty">
            <div class="relative h-40 mx-auto max-w-[12rem]">
              <CrmDoughnutChart
                :labels="sourceDonut.labels"
                :data="sourceDonut.data"
                :colors="sourceDonut.colors"
              >
                <template #center>
                  <div class="text-xl font-bold text-n-slate-12">
                    {{ sourceDonut.total }}
                  </div>
                  <div class="text-xs text-n-slate-10">客户</div>
                </template>
              </CrmDoughnutChart>
            </div>
            <div class="flex flex-col gap-1.5 mt-4">
              <div
                v-for="(label, i) in sourceDonut.labels"
                :key="label"
                class="flex items-center gap-2 text-sm"
              >
                <span
                  class="inline-block rounded-full size-2.5 shrink-0"
                  :style="{ backgroundColor: sourceDonut.colors[i] }"
                />
                <span class="truncate text-n-slate-11">{{ label }}</span>
                <span class="ml-auto font-medium text-n-slate-12">
                  {{ sourceDonut.data[i] }}
                </span>
              </div>
            </div>
          </template>
          <div
            v-else
            class="flex items-center justify-center h-56 text-sm text-n-slate-10"
          >
            暂无来源数据
          </div>
        </div>
      </div>

      <!-- ═══ 第 4 行：业务员排行 + 累计概览 ═══ -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div
          class="p-5 border shadow-sm lg:col-span-2 rounded-2xl border-n-weak bg-n-solid-1"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            业务员成交排行
          </h2>
          <div class="h-72">
            <CrmBarChart
              v-if="!ownerRank.empty"
              :labels="ownerRank.labels"
              :data="ownerRank.data"
              horizontal
              show-values
              :value-format="moneyYuan"
            />
            <div
              v-else
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              暂无成交数据
            </div>
          </div>
        </div>

        <div
          class="p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">累计概览</h2>
          <div class="flex flex-col gap-2">
            <div
              v-for="card in totalCards"
              :key="card.label"
              class="flex items-center gap-3 p-2 rounded-lg hover:bg-n-alpha-1"
            >
              <div
                class="flex items-center justify-center rounded-lg size-9 shrink-0"
                :class="[ACCENTS[card.accent].soft, ACCENTS[card.accent].text]"
              >
                <span class="size-5" :class="[card.icon]" />
              </div>
              <span class="text-sm text-n-slate-11">{{ card.label }}</span>
              <span class="ml-auto text-base font-bold text-n-slate-12">
                {{ card.value }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- ═══ 第 5 行：业务员回复时长 + 资料完善度 ═══ -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div class="p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1">
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            业务员平均回复时长（越短越好）
          </h2>
          <div class="h-64">
            <CrmBarChart
              v-if="!ownerLatency.empty"
              :labels="ownerLatency.labels"
              :data="ownerLatency.data"
              horizontal
              show-values
              :value-format="hoursFmt"
            />
            <div
              v-else
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              暂无回复时长数据
            </div>
          </div>
        </div>

        <div class="p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1">
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            业务员资料完善度（越高越好）
          </h2>
          <div class="h-64">
            <CrmBarChart
              v-if="!ownerCompleteness.empty"
              :labels="ownerCompleteness.labels"
              :data="ownerCompleteness.data"
              horizontal
              show-values
              :value-format="scoreFmt"
            />
            <div
              v-else
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              暂无完善度数据
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
