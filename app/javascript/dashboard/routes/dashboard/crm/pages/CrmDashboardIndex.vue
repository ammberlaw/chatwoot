<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const route = useRoute();
const { accountId } = useAccount();

const stats = ref(null);
const loading = ref(true);

const scope = computed(() =>
  route.query.scope === 'mine' ? 'mine' : 'company'
);

const STAGE_LABELS = {
  INITIAL_CONTACT: '初步接触',
  NEEDS_CONFIRMED: '需求确认',
  QUOTED: '已报价',
  NEGOTIATING: '谈判中',
  SAMPLING: '样品中',
  WON: '已成交',
  LOST: '已丢单',
};

const fetchStats = async () => {
  loading.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/stats`,
      { params: { scope: scope.value === 'mine' ? 'mine' : undefined } }
    );
    stats.value = data;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchStats);
watch(scope, fetchStats);

const money = micros => `¥ ${((micros || 0) / 1_000_000).toLocaleString()}`;

const kpis = computed(() => {
  if (!stats.value) return [];
  const s = stats.value;
  return [
    { label: '本月成交额', value: money(s.month_amount_micros), hero: true },
    { label: '本月订单数', value: s.month_order_count },
    { label: '本月成交客户', value: s.month_deal_customers },
    { label: '新成交客户', value: s.month_new_customers },
    { label: scope.value === 'mine' ? '我的客户' : '客户总数', value: s.total_customers },
    { label: '公海客户', value: s.public_pool_customers },
    { label: '推进中商机', value: s.open_opportunities },
  ];
});

const monthlyBars = computed(() => {
  if (!stats.value) return [];
  const entries = Object.entries(stats.value.monthly_amount_micros || {});
  const max = Math.max(1, ...entries.map(([, v]) => v));
  const current = new Date().getMonth() + 1;
  return entries.map(([m, v]) => ({
    month: Number(m),
    value: v,
    pct: Math.max(2, Math.round((v / max) * 100)),
    active: Number(m) === current,
  }));
});

const funnelRows = computed(() => {
  if (!stats.value) return [];
  const funnel = stats.value.funnel || {};
  const max = Math.max(1, ...Object.values(funnel));
  return Object.keys(STAGE_LABELS).map(stage => ({
    stage,
    label: STAGE_LABELS[stage],
    count: funnel[stage] || 0,
    pct: Math.max(2, Math.round(((funnel[stage] || 0) / max) * 100)),
  }));
});

const targetProgress = computed(() => {
  const targetMicros = stats.value?.target?.amount_micros || 0;
  if (!targetMicros) return null;
  const done = stats.value.month_amount_micros || 0;
  return {
    target: money(targetMicros),
    done: money(done),
    pct: Math.min(100, Math.round((done / targetMicros) * 100)),
  };
});
</script>

<template>
  <div class="flex flex-col w-full h-full gap-5 p-6 overflow-auto bg-n-background">
    <div class="flex items-center justify-between">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{
          scope === 'mine'
            ? t('CRM.DASHBOARD.HEADER_MINE')
            : t('CRM.DASHBOARD.HEADER_COMPANY')
        }}
      </h1>
      <span class="text-sm text-n-slate-11">{{ new Date().getFullYear() }}年</span>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.DASHBOARD.LOADING') }}
    </div>

    <template v-else>
      <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
        <div
          v-for="kpi in kpis"
          :key="kpi.label"
          class="p-4 border rounded-xl border-n-weak"
          :class="kpi.hero ? 'bg-n-blue-9 text-white' : 'bg-n-solid-1'"
        >
          <div class="text-xs" :class="kpi.hero ? 'text-white/80' : 'text-n-slate-11'">
            {{ kpi.label }}
          </div>
          <div class="mt-1 text-2xl font-bold">{{ kpi.value }}</div>
        </div>

        <div
          v-if="targetProgress"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="text-xs text-n-slate-11">本月目标完成率</div>
          <div class="mt-1 text-2xl font-bold">{{ targetProgress.pct }}%</div>
          <div class="h-2 mt-2 overflow-hidden rounded-full bg-n-alpha-2">
            <div
              class="h-full rounded-full bg-n-teal-9"
              :style="{ width: `${targetProgress.pct}%` }"
            />
          </div>
          <div class="mt-1 text-xs text-n-slate-11">
            {{ targetProgress.done }} / {{ targetProgress.target }}
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div class="p-5 border lg:col-span-2 rounded-xl border-n-weak bg-n-solid-1">
          <div class="mb-4 font-medium text-n-slate-12">成交额趋势（按月）</div>
          <div class="flex items-end h-40 gap-2">
            <div
              v-for="bar in monthlyBars"
              :key="bar.month"
              class="flex flex-col items-center flex-1 h-full"
            >
              <div class="flex items-end justify-center flex-1 w-full">
                <div
                  class="w-2/3 rounded-t"
                  :class="bar.active ? 'bg-n-blue-9' : 'bg-n-blue-4'"
                  :style="{ height: `${bar.pct}%` }"
                />
              </div>
              <div
                class="mt-1 text-[10px]"
                :class="bar.active ? 'font-bold text-n-blue-11' : 'text-n-slate-10'"
              >
                {{ bar.month }}月
              </div>
            </div>
          </div>
        </div>

        <div class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="mb-4 font-medium text-n-slate-12">商机漏斗</div>
          <div class="flex flex-col gap-2">
            <div
              v-for="row in funnelRows"
              :key="row.stage"
              class="flex items-center gap-2 text-sm"
            >
              <span class="w-16 text-xs text-n-slate-11">{{ row.label }}</span>
              <div class="flex-1 h-4 overflow-hidden rounded bg-n-alpha-1">
                <div
                  class="h-full rounded bg-n-iris-8"
                  :style="{ width: `${row.pct}%` }"
                />
              </div>
              <span class="w-6 text-xs text-right text-n-slate-11">
                {{ row.count }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
