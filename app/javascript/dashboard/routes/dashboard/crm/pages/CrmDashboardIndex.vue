<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';

import CrmAreaChart from 'dashboard/components-next/CRM/charts/CrmAreaChart.vue';
import CrmBarChart from 'dashboard/components-next/CRM/charts/CrmBarChart.vue';
import CrmDoughnutChart from 'dashboard/components-next/CRM/charts/CrmDoughnutChart.vue';
import {
  themeColor,
  isClassicTheme,
} from 'dashboard/components-next/CRM/charts/chartColors';
import { useThemeSignal } from 'dashboard/components-next/CRM/charts/useThemeSignal';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

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

// 月份筛选桥接到紫玻璃 MonthPicker（值 'YYYY-MM'，拆合回写年/月两个 ref）。
const pad = n => String(n).padStart(2, '0');
const monthModel = computed({
  get: () => `${selectedYear.value}-${pad(selectedMonth.value)}`,
  set: v => {
    const [y, m] = (v || '').split('-');
    if (y && m) {
      selectedYear.value = Number(y);
      selectedMonth.value = Number(m);
    }
  },
});
// 季度 / 年度用紫玻璃 SelectCard。
const quarterOptions = [1, 2, 3, 4].map(q => ({ value: q, label: `Q${q}` }));
const yearSelectOptions = yearOptions.map(y => ({ value: y, label: `${y}年` }));

const { isCrmSales } = useCrmRole();
// 普通业务无公司看板权限：无论 URL 参数如何都走个人口径（后端同样强制）。
const scope = computed(() =>
  route.query.scope === 'mine' || isCrmSales.value ? 'mine' : 'company'
);

const STAGE_LABELS = {
  NEEDS_CONFIRMED: '需求确认',
  SAMPLING: '样品中',
  WON: '已成交',
  LOST: '输单',
};
const STAGE_COLORS = {
  NEEDS_CONFIRMED: 'iris-6',
  SAMPLING: 'iris-8',
  WON: 'iris-10',
  LOST: 'ruby-9',
};
// 经典灰专属：商机阶段用黄黑灰（炭黑/金黄/灰/浅灰）。
const CLASSIC_STAGE_COLORS = {
  NEEDS_CONFIRMED: '#2a2e37',
  SAMPLING: '#f5c451',
  WON: '#6b6f78',
  LOST: '#b9bcc4',
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

// 长春花紫色系柔和渐变：跨卡紫→靛→蓝轻微流动，无绿。完整字面量供 Tailwind 收录。
const CARD_GRADIENTS = [
  'from-n-iris-3 to-n-iris-5',
  'from-n-iris-4 to-n-blue-4',
  'from-n-blue-3 to-n-iris-5',
  'from-n-iris-3 to-n-iris-6',
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

// themeSignal：body class（主题）变化时自增。图表色板 chartPalette()/themeColor()
// 读 DOM 非响应式，切主题不会自动重算；下面产色的 computed 依赖它即可跟随切换。
const themeSignal = useThemeSignal();

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

// ── 商机阶段（柱状图，与其它图表统一 Chart.js 风格） ──
const stageChart = computed(() => {
  void themeSignal.value;
  const byStage = stats.value?.trends?.opportunity_amount_by_stage || {};
  const rows = Object.keys(STAGE_LABELS)
    .map(stage => ({ stage, micros: byStage[stage] || 0 }))
    .filter(r => r.micros);
  return {
    labels: rows.map(r => STAGE_LABELS[r.stage]),
    data: rows.map(r => toYuan(r.micros)),
    colors: rows.map(r =>
      isClassicTheme()
        ? CLASSIC_STAGE_COLORS[r.stage]
        : themeColor(STAGE_COLORS[r.stage])
    ),
    empty: !rows.length,
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
  void themeSignal.value;
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

// ── 业务员成交排行（横向柱，跟随所选期间，按下单日期）──
const periodMonths = computed(() => {
  if (period.value === 'year') return Array.from({ length: 12 }, (_, i) => i);
  if (period.value === 'quarter') {
    const q = Math.floor((selectedMonth.value - 1) / 3);
    return [q * 3, q * 3 + 1, q * 3 + 2];
  }
  return [selectedMonth.value - 1];
});
const ownerRank = computed(() => {
  const by = stats.value?.team?.by_owner_monthly || {};
  const months = periodMonths.value;
  const rows = Object.entries(by)
    .map(([name, arr]) => [name, months.reduce((s, i) => s + (arr[i] || 0), 0)])
    .filter(([, v]) => v)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 50);
  return {
    labels: rows.map(([k]) => k),
    data: rows.map(([, v]) => toYuan(v)),
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

// ── 经典灰专属：图表改 HTML 排版（黄黑灰）。响应式跟随主题切换（无需刷新）。──
// isClassic 依赖 themeSignal 重算，图表用它做 :key 重绘。
const isClassic = computed(() => {
  void themeSignal.value;
  return isClassicTheme();
});
const RANK_PALETTE = ['#f5c451', '#2a2e37', '#6b6f78', '#b9bcc4'];
const isLightBar = c => c === '#f5c451' || c === '#b9bcc4';

// 商机阶段：横向标签长条
const classicStageBars = computed(() => {
  const { labels, data, colors } = stageChart.value;
  const max = Math.max(...data, 1);
  return labels.map((label, i) => ({
    label,
    amount: moneyYuan(data[i]),
    pct: Math.max((data[i] / max) * 100, 10),
    color: colors[i],
  }));
});

// 排行/回复/完善度：奖牌序号 + 头像 + 进度条 行
const buildRankRows = (chart, { inverse = false, fmt }) => {
  const { labels, data } = chart;
  if (!labels.length) return [];
  const max = Math.max(...data, 1);
  const min = Math.min(...data);
  return labels.map((name, i) => {
    let pct = Math.max((data[i] / max) * 100, 6);
    if (inverse) {
      pct = max === min ? 100 : ((max - data[i]) / (max - min)) * 76 + 24;
    }
    const color = RANK_PALETTE[Math.min(i, RANK_PALETTE.length - 1)];
    return {
      name,
      initial: (name || '?').slice(0, 1),
      value: fmt(data[i]),
      pct,
      color,
      dark: isLightBar(color),
    };
  });
};
const classicRank = computed(() =>
  buildRankRows(ownerRank.value, { fmt: moneyYuan })
);
const classicCompleteness = computed(() =>
  buildRankRows(ownerCompleteness.value, { fmt: scoreFmt })
);

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
        <MonthPicker
          v-if="period === 'month'"
          v-model="monthModel"
          align="right"
          trigger-class="w-36 h-9"
          :clearable="false"
        />
        <SelectCard
          v-else-if="period === 'quarter'"
          v-model="selectedQuarter"
          :options="quarterOptions"
          align="right"
          trigger-class="w-24"
        />
        <SelectCard
          v-else
          v-model="selectedYear"
          :options="yearSelectOptions"
          align="right"
          trigger-class="w-24"
        />
      </div>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.DASHBOARD.LOADING') }}
    </div>

    <div
      v-else-if="error"
      role="alert"
      class="flex flex-col items-center gap-3 p-10 text-center border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
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

      <!-- ═══ 第 2 行：业务员成交排行 + 目标仪表 ═══ -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div
          class="p-5 border shadow-sm lg:col-span-2 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            业务员成交排行
            <span class="ml-1 text-sm font-normal text-n-slate-10">
              · {{ periodLabel }}
            </span>
          </h2>
          <div class="h-72">
            <div
              v-if="ownerRank.empty"
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              暂无成交数据
            </div>
            <div
              v-else-if="isClassic"
              class="flex flex-col h-full gap-3 overflow-y-auto pr-1"
            >
              <div
                v-for="(row, i) in classicRank"
                :key="row.name"
                class="flex items-center gap-2.5"
              >
                <div
                  class="grid text-[11px] font-bold rounded size-5 place-items-center shrink-0"
                  :style="{
                    backgroundColor: row.color,
                    color: row.dark ? '#26340a' : '#fff',
                  }"
                >
                  {{ i + 1 }}
                </div>
                <div
                  class="grid rounded-lg size-7 place-items-center bg-n-slate-3 text-[11px] font-bold text-n-slate-11 shrink-0"
                >
                  {{ row.initial }}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="text-[13px] font-medium truncate text-n-slate-12">
                    {{ row.name }}
                  </div>
                  <div
                    class="h-1.5 mt-1 overflow-hidden rounded-full bg-n-slate-3"
                  >
                    <div
                      class="h-full rounded-full"
                      :style="{
                        width: row.pct + '%',
                        backgroundColor: row.color,
                      }"
                    />
                  </div>
                </div>
                <div class="text-[13px] font-bold text-n-slate-12 shrink-0">
                  {{ row.value }}
                </div>
              </div>
            </div>
            <CrmBarChart
              v-else
              :key="themeSignal"
              :labels="ownerRank.labels.slice(0, 8)"
              :data="ownerRank.data.slice(0, 8)"
              horizontal
              show-values
              :value-format="moneyYuan"
            />
          </div>
        </div>

        <div
          class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
        >
          <h2 class="mb-2 text-base font-medium text-n-slate-12">
            本月目标完成率
          </h2>
          <template v-if="targetProgress">
            <div class="h-48 mx-auto max-w-[16rem]">
              <CrmDoughnutChart
                :key="themeSignal"
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
        <!-- 左栏堆叠两张小卡：订单金额趋势 + 商机阶段分布 -->
        <div class="flex flex-col gap-4 lg:col-span-2">
          <div
            class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <h2 class="mb-4 text-base font-medium text-n-slate-12">
              订单金额趋势
            </h2>
            <div class="h-40">
              <CrmAreaChart
                v-if="!trendChart.empty"
                :key="themeSignal"
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
            class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-base font-medium text-n-slate-12">商机阶段分布</h2>
              <span v-if="winRate != null" class="text-xs text-n-slate-11">
                成交转化率
                <span class="font-semibold text-n-iris-11">{{ winRate }}%</span>
              </span>
            </div>
            <div class="h-40">
              <div
                v-if="stageChart.empty"
                class="flex items-center justify-center h-full text-sm text-n-slate-10"
              >
                暂无商机数据
              </div>
              <div
                v-else-if="isClassic"
                class="flex flex-col justify-center h-full gap-3"
              >
                <div
                  v-for="row in classicStageBars"
                  :key="row.label"
                  class="flex items-center gap-3"
                >
                  <div
                    class="w-20 text-[13px] font-medium text-n-slate-11 shrink-0"
                  >
                    {{ row.label }}
                  </div>
                  <div class="flex-1 h-7 overflow-hidden rounded-lg bg-n-slate-3">
                    <div
                      class="h-full rounded-lg"
                      :style="{
                        width: row.pct + '%',
                        backgroundColor: row.color,
                      }"
                    />
                  </div>
                  <div
                    class="w-24 text-[13px] font-bold text-right text-n-slate-12 shrink-0"
                  >
                    {{ row.amount }}
                  </div>
                </div>
              </div>
              <CrmBarChart
                v-else
                :key="themeSignal"
                :labels="stageChart.labels"
                :data="stageChart.data"
                :colors="stageChart.colors"
                show-values
                :value-format="moneyYuan"
              />
            </div>
          </div>
        </div>

        <div
          class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            客户来源占比
          </h2>
          <template v-if="!sourceDonut.empty">
            <div class="relative h-40 mx-auto max-w-[12rem]">
              <CrmDoughnutChart
                :key="themeSignal"
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

      <!-- ═══ 第 4 行：累计概览 + 业务员资料完善度 ═══ -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div
          class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
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
        <div
          class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            业务员资料完善度（越高越好）
          </h2>
          <div class="h-72">
            <div
              v-if="ownerCompleteness.empty"
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              暂无完善度数据
            </div>
            <div
              v-else-if="isClassic"
              class="flex flex-col h-full gap-3 overflow-y-auto pr-1"
            >
              <div
                v-for="(row, i) in classicCompleteness"
                :key="row.name"
                class="flex items-center gap-2.5"
              >
                <div
                  class="grid text-[11px] font-bold rounded size-5 place-items-center shrink-0"
                  :style="{
                    backgroundColor: row.color,
                    color: row.dark ? '#26340a' : '#fff',
                  }"
                >
                  {{ i + 1 }}
                </div>
                <div
                  class="grid rounded-lg size-7 place-items-center bg-n-slate-3 text-[11px] font-bold text-n-slate-11 shrink-0"
                >
                  {{ row.initial }}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="text-[13px] font-medium truncate text-n-slate-12">
                    {{ row.name }}
                  </div>
                  <div
                    class="h-1.5 mt-1 overflow-hidden rounded-full bg-n-slate-3"
                  >
                    <div
                      class="h-full rounded-full"
                      :style="{
                        width: row.pct + '%',
                        backgroundColor: row.color,
                      }"
                    />
                  </div>
                </div>
                <div class="text-[13px] font-bold text-n-slate-12 shrink-0">
                  {{ row.value }}
                </div>
              </div>
            </div>
            <CrmBarChart
              v-else
              :key="themeSignal"
              :labels="ownerCompleteness.labels"
              :data="ownerCompleteness.data"
              horizontal
              show-values
              :value-format="scoreFmt"
            />
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
