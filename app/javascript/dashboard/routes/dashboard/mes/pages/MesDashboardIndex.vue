<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';

const { accountId, accountScopedRoute } = useAccount();
const router = useRouter();

const STAGE_LABELS = {
  SALES_CONFIRMED: '销售订单确定',
  BOM_READY: '工程BOM',
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

const kpis = computed(() => {
  const m = data.value?.month || {};
  return [
    { label: '在产订单', value: data.value?.inProduction ?? 0, accent: 'iris' },
    { label: '本月完成', value: Math.round(m.completed || 0), accent: 'teal' },
    {
      label: '本月良率',
      value: m.yieldRate != null ? `${(m.yieldRate * 100).toFixed(1)}%` : '—',
      accent: 'blue',
    },
    {
      label: '质检合格率',
      value: m.qcPassRate != null ? `${(m.qcPassRate * 100).toFixed(1)}%` : '—',
      accent: 'teal',
    },
    { label: '本月出货', value: m.shipped ?? 0, accent: 'violet' },
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

const goOrder = () => router.push(accountScopedRoute('mes_production_orders_index'));

onMounted(async () => {
  try {
    const { data: res } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/dashboard`
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
      shortages: res.shortages || [],
    };
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto">
    <div class="px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">生产看板</h1>
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
          <div v-for="b in stageBars" :key="b.stage" class="flex items-center gap-2">
            <span class="w-24 text-xs shrink-0 text-n-slate-11">{{ b.label }}</span>
            <div class="flex-1 h-3 overflow-hidden rounded-full bg-n-slate-3">
              <div class="h-full rounded-full bg-n-iris-9" :style="{ width: `${b.pct}%` }" />
            </div>
            <span class="w-6 text-xs text-right text-n-slate-12">{{ b.count }}</span>
          </div>
        </div>
      </div>

      <!-- 交期预警 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak">
        <div class="mb-3 font-medium text-n-slate-12">交期预警</div>
        <div v-if="!data.overdue.length && !data.dueSoon.length" class="text-sm text-n-slate-11">
          暂无逾期或临近交期。
        </div>
        <ul class="flex flex-col gap-2">
          <li
            v-for="o in data.overdue"
            :key="`ov-${o.id}`"
            class="flex items-center justify-between text-sm cursor-pointer"
            @click="goOrder"
          >
            <span class="text-n-slate-12">{{ o.order_no }} · {{ o.product_name }}</span>
            <span class="text-n-ruby-11">已逾期 {{ o.days }} 天</span>
          </li>
          <li
            v-for="o in data.dueSoon"
            :key="`ds-${o.id}`"
            class="flex items-center justify-between text-sm cursor-pointer"
            @click="goOrder"
          >
            <span class="text-n-slate-12">{{ o.order_no }} · {{ o.product_name }}</span>
            <span class="text-n-amber-11">距交期 {{ o.days }} 天</span>
          </li>
        </ul>
      </div>

      <!-- 滞留卡点 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak">
        <div class="mb-3 font-medium text-n-slate-12">滞留卡点(≥3 天)</div>
        <div v-if="!data.stalled.length" class="text-sm text-n-slate-11">无滞留单据。</div>
        <ul class="flex flex-col gap-2">
          <li
            v-for="o in data.stalled"
            :key="`st-${o.id}`"
            class="flex items-center justify-between text-sm cursor-pointer"
            @click="goOrder"
          >
            <span class="text-n-slate-12">
              {{ o.order_no }} · {{ stageLabel(o.stage) }}
            </span>
            <span class="text-n-amber-11">滞留 {{ o.days }} 天</span>
          </li>
        </ul>
      </div>

      <!-- 短缺物料 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak lg:col-span-2">
        <div class="mb-3 font-medium text-n-slate-12">短缺物料</div>
        <div v-if="!data.shortages.length" class="text-sm text-n-slate-11">库存充足。</div>
        <div v-else class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <div
            v-for="(s, i) in data.shortages"
            :key="i"
            class="flex items-center justify-between px-3 py-2 text-sm rounded-lg bg-n-ruby-2"
          >
            <span class="text-n-slate-12">{{ s.material_name }}</span>
            <span class="text-n-ruby-11">
              {{ s.qty }} / 安全 {{ s.safety_stock }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
