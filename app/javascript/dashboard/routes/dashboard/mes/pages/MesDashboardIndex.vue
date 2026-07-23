<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';

const { accountId, accountScopedRoute } = useAccount();
const router = useRouter();

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

// 「待我审批 / 待我接单」已移至独立板块「我的待办」(mes_todo_index)。

const kpis = computed(() => {
  const m = data.value?.month || {};
  return [
    { label: '在产订单', value: data.value?.inProduction ?? 0, accent: 'iris' },
    { label: '完成数', value: Math.round(m.completed || 0), accent: 'teal' },
    {
      label: '良率',
      value: m.yieldRate != null ? `${(m.yieldRate * 100).toFixed(1)}%` : '—',
      accent: 'blue',
    },
    {
      label: '质检合格率',
      value: m.qcPassRate != null ? `${(m.qcPassRate * 100).toFixed(1)}%` : '—',
      accent: 'teal',
    },
    { label: '出货数', value: m.shipped ?? 0, accent: 'violet' },
  ];
});
const ACCENT = {
  iris: 'text-n-iris-11',
  teal: 'text-n-teal-11',
  blue: 'text-n-blue-11',
  violet: 'text-n-violet-11',
};

const stageBars = computed(() => {
  const dist = data.value?.stageDistribution || {};
  const max = Math.max(1, ...Object.values(dist));
  return STAGE_ORDER.map(s => ({
    stage: s,
    label: stageLabel(s),
    count: dist[s] || 0,
    pct: Math.round(((dist[s] || 0) / max) * 100),
  }));
});

// —— 按时交货率（按产品线）——
const ONTIME_LINES = [
  { code: 'COMMERCIAL_DISPLAY', label: '商显设备' },
  { code: 'INDUSTRIAL_CONTROL', label: '工控类' },
  { code: 'TABLET', label: '平板电脑' },
];
const onTimeRow = code => data.value?.onTime?.[code] || null;
const onTimePct = code => {
  const r = onTimeRow(code);
  return r && r.total ? Math.round(r.rate * 100) : null;
};
const onTimeLabel = code => {
  const r = onTimeRow(code);
  return r && r.total ? `${onTimePct(code)}% (${r.on_time}/${r.total})` : '—';
};
const onTimeBar = code => {
  const p = onTimePct(code);
  if (p == null) return 'bg-n-slate-4';
  if (p >= 90) return 'bg-n-teal-9';
  if (p >= 70) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
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

const load = async () => {
  loading.value = true;
  const [startDate, endDate] = periodDates(period.value);
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
    };
  } finally {
    loading.value = false;
  }
};

const selectPeriod = key => {
  if (period.value === key) return;
  period.value = key;
  load();
};

onMounted(() => {
  load();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto">
    <div class="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">生产看板</h1>
      <div
        class="flex gap-0.5 p-0.5 rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black1"
      >
        <button
          v-for="p in PERIODS"
          :key="p.key"
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-md transition-colors duration-100"
          :class="
            period === p.key
              ? 'bg-n-solid-3 text-n-slate-12 shadow-sm'
              : 'text-n-slate-10 hover:text-n-slate-12'
          "
          @click="selectPeriod(p.key)"
        >
          {{ p.label }}
        </button>
      </div>
    </div>

    <div v-if="loading" class="py-10 text-center text-n-slate-11">加载中…</div>

    <div v-else class="grid grid-cols-1 gap-4 px-6 pb-6 lg:grid-cols-3">
      <!-- KPI 行 -->
      <div class="grid grid-cols-2 gap-4 lg:col-span-3 lg:grid-cols-5">
        <div
          v-for="k in kpis"
          :key="k.label"
          class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak"
        >
          <div class="text-sm text-n-slate-11">{{ k.label }}</div>
          <div class="mt-1 text-2xl font-semibold" :class="ACCENT[k.accent]">
            {{ k.value }}
          </div>
        </div>
      </div>

      <!-- 阶段分布 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak">
        <div class="mb-3 font-medium text-n-slate-12">在产 · 阶段分布</div>
        <div class="flex flex-col gap-2">
          <div
            v-for="b in stageBars"
            :key="b.stage"
            class="flex items-center gap-2"
          >
            <span class="w-24 text-xs shrink-0 text-n-slate-11">{{
              b.label
            }}</span>
            <div class="flex-1 h-3 overflow-hidden rounded-full bg-n-slate-3">
              <div
                class="h-full rounded-full bg-n-iris-9"
                :style="{ width: `${b.pct}%` }"
              />
            </div>
            <span class="w-6 text-xs text-right text-n-slate-12">{{
              b.count
            }}</span>
          </div>
        </div>
      </div>

      <!-- 按时交货率 · 按产品线 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak">
        <div class="mb-3 font-medium text-n-slate-12">
          按时交货率 · 按产品线
        </div>
        <div class="flex flex-col gap-3">
          <div
            v-for="l in ONTIME_LINES"
            :key="l.code"
            class="flex items-center gap-2"
          >
            <span class="w-16 text-xs shrink-0 text-n-slate-11">
              {{ l.label }}
            </span>
            <div class="flex-1 h-3 overflow-hidden rounded-full bg-n-slate-3">
              <div
                class="h-full rounded-full"
                :class="onTimeBar(l.code)"
                :style="{ width: `${onTimePct(l.code) || 0}%` }"
              />
            </div>
            <span class="text-xs text-right w-28 text-n-slate-12">
              {{ onTimeLabel(l.code) }}
            </span>
          </div>
        </div>
        <p class="mt-2 text-xs text-n-slate-10">
          出货日 ≤ 期望交期即按时；按所选时段统计。
        </p>
      </div>

      <!-- 交期预警 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak">
        <div class="mb-3 font-medium text-n-slate-12">交期预警</div>
        <div
          v-if="!data.overdue.length && !data.dueSoon.length"
          class="text-sm text-n-slate-11"
        >
          暂无逾期或临近交期。
        </div>
        <ul class="flex flex-col gap-2">
          <li
            v-for="o in data.overdue"
            :key="`ov-${o.id}`"
            class="flex items-center justify-between text-sm cursor-pointer group"
            @click="goOrder(o.order_no)"
          >
            <span class="text-n-slate-12 group-hover:underline">
              {{ o.order_no }} · {{ o.product_name }}
            </span>
            <span class="text-n-ruby-11">已逾期 {{ o.days }} 天</span>
          </li>
          <li
            v-for="o in data.dueSoon"
            :key="`ds-${o.id}`"
            class="flex items-center justify-between text-sm cursor-pointer group"
            @click="goOrder(o.order_no)"
          >
            <span class="text-n-slate-12 group-hover:underline">
              {{ o.order_no }} · {{ o.product_name }}
            </span>
            <span class="text-n-amber-11">距交期 {{ o.days }} 天</span>
          </li>
        </ul>
      </div>

      <!-- 超时未接单（装死）：管理视图，谁在拖一眼可见 -->
      <div
        v-if="data.unacked.length"
        class="p-5 rounded-xl lg:col-span-3 bg-n-ruby-2 border border-n-ruby-6"
      >
        <div class="mb-3 font-medium text-n-ruby-11">
          🔴 超时未接单 ({{ data.unacked.length }})
        </div>
        <ul class="flex flex-col gap-2">
          <li
            v-for="o in data.unacked"
            :key="`ua-${o.id}`"
            class="flex items-center justify-between text-sm cursor-pointer group"
            @click="goOrder(o.order_no)"
          >
            <span class="text-n-slate-12 group-hover:underline">
              {{ o.order_no }} · {{ o.product_name }} ·
              {{ stageLabel(o.stage) }}
            </span>
            <span class="text-n-ruby-11">已 {{ o.hours }} 小时未接单</span>
          </li>
        </ul>
      </div>

      <!-- 滞留卡点 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak">
        <div class="mb-3 font-medium text-n-slate-12">滞留卡点(≥3 天)</div>
        <div v-if="!data.stalled.length" class="text-sm text-n-slate-11">
          无滞留单据。
        </div>
        <ul class="flex flex-col gap-2">
          <li
            v-for="o in data.stalled"
            :key="`st-${o.id}`"
            class="flex items-center justify-between text-sm cursor-pointer group"
            @click="goOrder(o.order_no)"
          >
            <span class="text-n-slate-12 group-hover:underline">
              {{ o.order_no }} · {{ stageLabel(o.stage) }}
            </span>
            <span class="text-n-amber-11">滞留 {{ o.days }} 天</span>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
