<script setup>
/* global axios */
import { ref, reactive, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmBarChart from 'dashboard/components-next/CRM/charts/CrmBarChart.vue';
import CrmDoughnutChart from 'dashboard/components-next/CRM/charts/CrmDoughnutChart.vue';
import { themeColor } from 'dashboard/components-next/CRM/charts/chartColors';

const { accountId, accountScopedRoute } = useAccount();
const router = useRouter();

// 统一玻璃卡样式（对齐 CRM 看板）。
const CARD =
  'p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150';

const STAGE_LABELS = {
  SALES_CONFIRMED: '销售订单确定',
  BOM_READY: '工程/PMC BOM',
  PURCHASING: '采购原料',
  MATERIAL_INBOUND: '原料入库',
  PICKING: '生产领料',
  PRODUCTION: '生产',
  FG_INBOUND: '成品入库',
  SHIPPED: '销售出库',
};
const STAGE_ORDER = Object.keys(STAGE_LABELS);
const stageLabel = s => STAGE_LABELS[s] || s;

const data = ref(null);
const loading = ref(true);

// —— KPI ——（渐变卡 + 图标，对齐 CRM 看板暖色卡）
const KPI_META = [
  {
    icon: 'i-lucide-factory',
    tint: 'text-n-iris-11',
    grad: 'from-n-iris-3 to-n-iris-5',
  },
  {
    icon: 'i-lucide-circle-check-big',
    tint: 'text-n-teal-11',
    grad: 'from-n-teal-3 to-n-teal-5',
  },
  {
    icon: 'i-lucide-gauge',
    tint: 'text-n-blue-11',
    grad: 'from-n-blue-3 to-n-iris-5',
  },
  {
    icon: 'i-lucide-shield-check',
    tint: 'text-n-teal-11',
    grad: 'from-n-teal-3 to-n-blue-4',
  },
  {
    icon: 'i-lucide-truck',
    tint: 'text-n-violet-11',
    grad: 'from-n-violet-3 to-n-iris-5',
  },
];
const kpis = computed(() => {
  const m = data.value?.month || {};
  return [
    {
      label: '在产订单',
      value: data.value?.inProduction ?? 0,
      sub: '当前流转中',
    },
    {
      label: '完成数',
      value: Math.round(m.completed || 0),
      sub: '本期报工累计',
    },
    {
      label: '良率',
      value: m.yieldRate != null ? `${(m.yieldRate * 100).toFixed(1)}%` : '—',
      sub: '完成 / (完成+报废)',
    },
    {
      label: '质检合格率',
      value: m.qcPassRate != null ? `${(m.qcPassRate * 100).toFixed(1)}%` : '—',
      sub: '本期质检通过率',
    },
    { label: '出货数', value: m.shipped ?? 0, sub: '本期已出库' },
  ];
});

// —— 在产·阶段分布（横向柱状图）——
const stageChart = computed(() => {
  const dist = data.value?.stageDistribution || {};
  return {
    labels: STAGE_ORDER.map(stageLabel),
    data: STAGE_ORDER.map(s => dist[s] || 0),
    empty: STAGE_ORDER.every(s => !dist[s]),
  };
});

// —— 按时交货率（按产品线，半圆仪表）——
const ONTIME_LINES = [
  { code: 'COMMERCIAL_DISPLAY', label: '商显工控' },
  { code: 'TABLET', label: '平板电脑' },
];
const onTimeRow = code => data.value?.onTime?.[code] || null;
const onTimePct = code => {
  const r = onTimeRow(code);
  return r && r.total ? Math.round(r.rate * 100) : null;
};
const onTimeSub = code => {
  const r = onTimeRow(code);
  return r && r.total ? `${r.on_time}/${r.total} 单` : '暂无出货';
};
const onTimeGaugeColor = code => {
  const p = onTimePct(code);
  if (p == null) return themeColor('slate-6');
  if (p >= 90) return themeColor('teal-9');
  if (p >= 70) return themeColor('amber-9');
  return themeColor('ruby-9');
};

// —— 各环节接单平均响应时长（只算工作时间；可下钻到人）——
const ACK_SLA_SECONDS = 4 * 3600; // 4 工作小时接单时限，作进度条/配色满格
const ackRows = computed(() =>
  (data.value?.ackResponse || []).map(r => ({
    stage: r.stage,
    label: r.label,
    count: r.count,
    avgSeconds: r.avg_seconds,
    people: (r.people || []).map(p => ({
      name: p.name,
      count: p.count,
      avgSeconds: p.avg_seconds,
    })),
  }))
);
const fmtDuration = secs => {
  if (secs == null) return '—';
  const h = secs / 3600;
  if (h >= 1) return `${h.toFixed(1)}h`;
  return `${Math.max(1, Math.round(secs / 60))}m`;
};
const ackPct = secs =>
  Math.min(100, Math.round((secs / ACK_SLA_SECONDS) * 100));
const ackBar = secs => {
  const ratio = secs / ACK_SLA_SECONDS;
  if (ratio <= 0.5) return 'bg-n-teal-9';
  if (ratio <= 1) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};
const ackPillTone = secs => {
  const ratio = secs / ACK_SLA_SECONDS;
  if (ratio <= 0.5) return 'bg-n-teal-3 text-n-teal-11';
  if (ratio <= 1) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-ruby-3 text-n-ruby-11';
};
const ackExpanded = reactive({});
const toggleAck = stage => {
  ackExpanded[stage] = !ackExpanded[stage];
};

// 点交期预警/滞留订单 → 跳订单页并按订单号搜索、自动打开详情面板。
const goOrder = orderNo =>
  router.push(
    accountScopedRoute('mes_production_orders_index', {}, { q: orderNo })
  );

// —— 时间筛选 ——
const PERIODS = [
  { key: 'this_month', label: '本月' },
  { key: 'last_month', label: '上月' },
  { key: 'last_7', label: '近7天' },
  { key: 'last_30', label: '近30天' },
];
const period = ref('this_month');
// 取数模式：preset 快捷段 / month 指定年月。
const mode = ref('preset');
const CUR_YEAR = new Date().getFullYear();
const YEARS = Array.from({ length: 6 }, (_, i) => CUR_YEAR - 4 + i); // 前4年~明年
const MONTHS = [
  { v: 0, label: '全年' },
  ...Array.from({ length: 12 }, (_, i) => ({ v: i + 1, label: `${i + 1}月` })),
];
const pickYear = ref(CUR_YEAR);
const pickMonth = ref(new Date().getMonth() + 1);
const periodLabel = computed(() => {
  if (mode.value === 'month') {
    return `${pickYear.value}年${pickMonth.value ? `${pickMonth.value}月` : '·全年'}`;
  }
  return PERIODS.find(p => p.key === period.value)?.label || '';
});
const fmt = d =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate()
  ).padStart(2, '0')}`;
const periodDates = key => {
  const now = new Date();
  if (key === 'last_month') {
    return [
      fmt(new Date(now.getFullYear(), now.getMonth() - 1, 1)),
      fmt(new Date(now.getFullYear(), now.getMonth(), 0)),
    ];
  }
  if (key === 'last_7' || key === 'last_30') {
    const s = new Date(now);
    s.setDate(s.getDate() - (key === 'last_7' ? 6 : 29));
    return [fmt(s), fmt(now)];
  }
  return [fmt(new Date(now.getFullYear(), now.getMonth(), 1)), fmt(now)]; // this_month
};

// 指定年月：整月首末日；月为 0（全年）则整年。
const monthRange = () => {
  const y = pickYear.value;
  const mo = pickMonth.value;
  if (mo === 0) return [fmt(new Date(y, 0, 1)), fmt(new Date(y, 11, 31))];
  return [fmt(new Date(y, mo - 1, 1)), fmt(new Date(y, mo, 0))];
};

const load = async () => {
  loading.value = true;
  const [startDate, endDate] =
    mode.value === 'month' ? monthRange() : periodDates(period.value);
  try {
    const { data: res } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/dashboard`,
      { params: { start_date: startDate, end_date: endDate } }
    );
    // camel 化：后端 snake，手动取常用字段
    data.value = {
      inProduction: res.in_production,
      stageDistribution: res.stage_distribution,
      month: res.month
        ? {
            completed: res.month.completed,
            scrap: res.month.scrap,
            shipped: res.month.shipped,
            yieldRate: res.month.yield_rate,
            qcPassRate: res.month.qc_pass_rate,
          }
        : {},
      overdue: res.overdue || [],
      dueSoon: res.due_soon || [],
      stalled: res.stalled || [],
      unacked: res.unacked || [],
      onTime: res.on_time || {},
      ackResponse: res.ack_response || [],
    };
  } finally {
    loading.value = false;
  }
};

const selectPeriod = key => {
  if (mode.value === 'preset' && period.value === key) return;
  mode.value = 'preset';
  period.value = key;
  load();
};

// 切到「指定年月」并按当前年月下拉取数。
const selectMonth = () => {
  mode.value = 'month';
  load();
};

onMounted(() => {
  load();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full gap-4 p-6 overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 顶栏 -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          生产看板
        </h1>
        <p class="mt-0.5 text-sm text-n-slate-11">
          {{ periodLabel }} · 生产全局概览
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <div class="flex items-center h-9 gap-1 px-1 rounded-lg bg-n-alpha-1">
          <button
            v-for="p in PERIODS"
            :key="p.key"
            type="button"
            class="h-7 px-3 text-sm font-medium transition-colors rounded-md shrink-0 motion-reduce:transition-none focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
            :class="
              mode === 'preset' && period === p.key
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="selectPeriod(p.key)"
          >
            {{ p.label }}
          </button>
        </div>
        <!-- 指定年月：两个独立下拉（月含「全年」）；month 模式时描边高亮 -->
        <select
          v-model.number="pickYear"
          class="h-9 pl-2.5 pr-1 text-sm leading-none border rounded-lg cursor-pointer shrink-0 bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
          :class="mode === 'month' ? 'border-n-iris-8' : 'border-n-weak'"
          @change="selectMonth"
        >
          <option v-for="y in YEARS" :key="y" :value="y">{{ y }}年</option>
        </select>
        <select
          v-model.number="pickMonth"
          class="h-9 pl-2.5 pr-1 text-sm leading-none border rounded-lg cursor-pointer shrink-0 bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
          :class="mode === 'month' ? 'border-n-iris-8' : 'border-n-weak'"
          @change="selectMonth"
        >
          <option v-for="m in MONTHS" :key="m.v" :value="m.v">
            {{ m.label }}
          </option>
        </select>
      </div>
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 gap-2 text-sm text-n-slate-11"
    >
      <span class="i-lucide-loader-circle size-4 animate-spin" /> 加载中…
    </div>

    <template v-else>
      <!-- KPI 行 -->
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 xl:grid-cols-5">
        <div
          v-for="(k, i) in kpis"
          :key="k.label"
          class="flex flex-col justify-between p-4 shadow-sm rounded-2xl bg-gradient-to-br min-h-[7.5rem]"
          :class="KPI_META[i].grad"
        >
          <div
            class="flex items-center justify-center rounded-lg size-8 bg-n-solid-1/70"
            :class="KPI_META[i].tint"
          >
            <span class="size-4" :class="KPI_META[i].icon" />
          </div>
          <div>
            <div class="mt-2 text-xs font-medium text-n-slate-11">
              {{ k.label }}
            </div>
            <div class="text-2xl font-bold leading-tight text-n-slate-12">
              {{ k.value }}
            </div>
            <div class="mt-0.5 text-[11px] text-n-slate-10">{{ k.sub }}</div>
          </div>
        </div>
      </div>

      <!-- 超时未接单：置顶红色告警条（有才显示） -->
      <div
        v-if="data.unacked.length"
        class="p-5 border shadow-sm rounded-2xl border-n-ruby-6 bg-n-ruby-2/60 backdrop-blur-2xl backdrop-saturate-150"
      >
        <div class="flex items-center gap-2 mb-3 font-medium text-n-ruby-11">
          <span class="i-lucide-alarm-clock-off size-4" />
          超时未接单 · {{ data.unacked.length }}
        </div>
        <ul class="flex flex-col gap-1.5">
          <li
            v-for="o in data.unacked"
            :key="`ua-${o.id}`"
            class="flex items-center justify-between gap-3 px-2 py-1.5 -mx-2 text-sm rounded-lg cursor-pointer group hover:bg-n-ruby-3/50"
            @click="goOrder(o.order_no)"
          >
            <span class="truncate text-n-slate-12 group-hover:underline">
              {{ o.order_no }} · {{ o.product_name }} ·
              {{ stageLabel(o.stage) }}
              <span class="text-n-slate-10">
                · 负责人：{{
                  o.owner_names && o.owner_names.length
                    ? o.owner_names.join('、')
                    : '未配置'
                }}
              </span>
            </span>
            <span
              class="px-2 py-0.5 text-xs font-medium rounded-full shrink-0 bg-n-ruby-3 text-n-ruby-11"
            >
              已 {{ o.hours }}h 未接
            </span>
          </li>
        </ul>
      </div>

      <!-- 阶段分布 + 按时交货率 -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div class="lg:col-span-2" :class="CARD">
          <h2
            class="flex items-center gap-2 mb-3 text-base font-medium text-n-slate-12"
          >
            <span class="i-lucide-bar-chart-3 size-4 text-n-slate-11" />
            在产 · 阶段分布
          </h2>
          <div class="h-64">
            <CrmBarChart
              v-if="!stageChart.empty"
              :labels="stageChart.labels"
              :data="stageChart.data"
              horizontal
              show-values
            />
            <div
              v-else
              class="flex flex-col items-center justify-center h-full gap-1 text-n-slate-10"
            >
              <span class="i-lucide-inbox size-6" />
              <span class="text-sm">暂无在产订单</span>
            </div>
          </div>
        </div>

        <div :class="CARD">
          <h2
            class="flex items-center gap-2 mb-2 text-base font-medium text-n-slate-12"
          >
            <span class="i-lucide-truck size-4 text-n-slate-11" />
            按时交货率
          </h2>
          <div class="grid grid-cols-2 gap-2">
            <div
              v-for="l in ONTIME_LINES"
              :key="l.code"
              class="flex flex-col items-center"
            >
              <div class="relative w-full h-28 max-w-[10rem]">
                <CrmDoughnutChart
                  :data="[
                    onTimePct(l.code) || 0,
                    100 - (onTimePct(l.code) || 0),
                  ]"
                  :colors="[onTimeGaugeColor(l.code)]"
                  gauge
                  cutout="80%"
                >
                  <template #center>
                    <div class="text-xl font-bold text-n-slate-12">
                      {{
                        onTimePct(l.code) != null
                          ? `${onTimePct(l.code)}%`
                          : '—'
                      }}
                    </div>
                  </template>
                </CrmDoughnutChart>
              </div>
              <div class="text-sm font-medium text-n-slate-12">
                {{ l.label }}
              </div>
              <div class="text-xs text-n-slate-10">{{ onTimeSub(l.code) }}</div>
            </div>
          </div>
          <p class="mt-2 text-xs text-center text-n-slate-10">
            出货日 ≤ 期望交期即按时
          </p>
        </div>
      </div>

      <!-- 各环节接单平均响应时长（可下钻到人） -->
      <div :class="CARD">
        <h2
          class="flex items-center gap-2 mb-3 text-base font-medium text-n-slate-12"
        >
          <span class="i-lucide-timer size-4 text-n-slate-11" />
          各环节接单平均响应时长
        </h2>
        <div v-if="!ackRows.length" class="text-sm text-n-slate-10">
          本时段暂无接单记录。
        </div>
        <div v-else class="flex flex-col gap-1">
          <template v-for="r in ackRows" :key="r.stage">
            <button
              type="button"
              class="flex items-center gap-3 px-2 py-2 -mx-2 text-sm rounded-lg hover:bg-n-alpha-1"
              @click="toggleAck(r.stage)"
            >
              <span
                class="size-3.5 shrink-0 text-n-slate-10"
                :class="
                  ackExpanded[r.stage]
                    ? 'i-lucide-chevron-down'
                    : 'i-lucide-chevron-right'
                "
              />
              <span class="text-left w-28 shrink-0 text-n-slate-12">
                {{ r.label }}
              </span>
              <div
                class="flex-1 h-2 overflow-hidden rounded-full bg-n-slate-3 min-w-16"
              >
                <div
                  class="h-full rounded-full"
                  :class="ackBar(r.avgSeconds)"
                  :style="{ width: `${ackPct(r.avgSeconds)}%` }"
                />
              </div>
              <span
                class="px-2 py-0.5 w-16 text-xs font-semibold text-center rounded-full shrink-0"
                :class="ackPillTone(r.avgSeconds)"
              >
                {{ fmtDuration(r.avgSeconds) }}
              </span>
              <span class="text-right w-12 text-n-slate-10">
                {{ r.count }} 单
              </span>
            </button>
            <div
              v-if="ackExpanded[r.stage]"
              class="flex flex-col gap-1 pb-2 pl-9"
            >
              <div
                v-for="p in r.people"
                :key="p.name"
                class="flex items-center gap-3 text-xs text-n-slate-11"
              >
                <span class="flex items-center gap-1.5 text-left w-28 shrink-0">
                  <span class="i-lucide-user size-3 text-n-slate-10" />
                  {{ p.name }}
                </span>
                <span class="flex-1" />
                <span class="w-16 font-medium text-right text-n-slate-12">
                  {{ fmtDuration(p.avgSeconds) }}
                </span>
                <span class="text-right w-12">{{ p.count }} 单</span>
              </div>
            </div>
          </template>
        </div>
        <p class="mt-2 text-xs text-n-slate-10">
          接单响应 = 进入本环节到接单，只算工作时间（工作日
          8:00–17:30、跳周末与节假日）；按所选时段内发生的接单统计，未接单不计入（进度条以
          4 工作小时接单时限为满格）。
        </p>
      </div>

      <!-- 交期预警 + 滞留卡点 -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div :class="CARD">
          <h2
            class="flex items-center gap-2 mb-3 text-base font-medium text-n-slate-12"
          >
            <span class="i-lucide-calendar-clock size-4 text-n-slate-11" />
            交期预警
          </h2>
          <div
            v-if="!data.overdue.length && !data.dueSoon.length"
            class="flex flex-col items-center gap-1 py-6 text-n-slate-10"
          >
            <span class="i-lucide-calendar-check size-6" />
            <span class="text-sm">暂无逾期或临近交期</span>
          </div>
          <ul class="flex flex-col gap-1.5">
            <li
              v-for="o in data.overdue"
              :key="`ov-${o.id}`"
              class="flex items-center justify-between gap-3 px-2 py-1.5 -mx-2 text-sm rounded-lg cursor-pointer group hover:bg-n-alpha-1"
              @click="goOrder(o.order_no)"
            >
              <span class="flex items-center gap-2 truncate">
                <span class="rounded-full size-1.5 shrink-0 bg-n-ruby-9" />
                <span class="truncate text-n-slate-12 group-hover:underline">
                  {{ o.order_no }} · {{ o.product_name }}
                </span>
              </span>
              <span
                class="px-2 py-0.5 text-xs font-medium rounded-full shrink-0 bg-n-ruby-3 text-n-ruby-11"
              >
                逾期 {{ o.days }} 天
              </span>
            </li>
            <li
              v-for="o in data.dueSoon"
              :key="`ds-${o.id}`"
              class="flex items-center justify-between gap-3 px-2 py-1.5 -mx-2 text-sm rounded-lg cursor-pointer group hover:bg-n-alpha-1"
              @click="goOrder(o.order_no)"
            >
              <span class="flex items-center gap-2 truncate">
                <span class="rounded-full size-1.5 shrink-0 bg-n-amber-9" />
                <span class="truncate text-n-slate-12 group-hover:underline">
                  {{ o.order_no }} · {{ o.product_name }}
                </span>
              </span>
              <span
                class="px-2 py-0.5 text-xs font-medium rounded-full shrink-0 bg-n-amber-3 text-n-amber-11"
              >
                距交期 {{ o.days }} 天
              </span>
            </li>
          </ul>
        </div>

        <div :class="CARD">
          <h2
            class="flex items-center gap-2 mb-3 text-base font-medium text-n-slate-12"
          >
            <span class="i-lucide-hourglass size-4 text-n-slate-11" />
            滞留卡点（≥3 天）
          </h2>
          <div
            v-if="!data.stalled.length"
            class="flex flex-col items-center gap-1 py-6 text-n-slate-10"
          >
            <span class="i-lucide-check-check size-6" />
            <span class="text-sm">无滞留单据</span>
          </div>
          <ul class="flex flex-col gap-1.5">
            <li
              v-for="o in data.stalled"
              :key="`st-${o.id}`"
              class="flex items-center justify-between gap-3 px-2 py-1.5 -mx-2 text-sm rounded-lg cursor-pointer group hover:bg-n-alpha-1"
              @click="goOrder(o.order_no)"
            >
              <span class="flex items-center gap-2 truncate">
                <span class="rounded-full size-1.5 shrink-0 bg-n-amber-9" />
                <span class="truncate text-n-slate-12 group-hover:underline">
                  {{ o.order_no }} · {{ stageLabel(o.stage) }}
                </span>
              </span>
              <span
                class="px-2 py-0.5 text-xs font-medium rounded-full shrink-0 bg-n-amber-3 text-n-amber-11"
              >
                滞留 {{ o.days }} 天
              </span>
            </li>
          </ul>
        </div>
      </div>
    </template>
  </div>
</template>
