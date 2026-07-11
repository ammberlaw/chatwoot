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
const activeTab = ref('overview');

// 业绩统计部件的本地状态（切换无需重新请求）
const period = ref('month'); // month | quarter | year
const selectedMonth = ref(new Date().getMonth() + 1); // 1-12

const scope = computed(() =>
  route.query.scope === 'mine' ? 'mine' : 'company'
);

const STAGE_LABELS = {
  NEEDS_CONFIRMED: '需求确认（已报价）',
  SAMPLING: '样品中',
  WON: '已成交',
  LOST: '输单',
};

const SOURCE_LABELS = {
  ALIBABA: '阿里巴巴国际站',
  WEBSITE: '官网',
  EXHIBITION: '展会',
  REFERRAL: '转介绍',
  EMAIL: '邮件开发',
  OTHER: '其他',
};

const TABS = [
  { key: 'overview', label: '业绩概览' },
  { key: 'trends', label: '趋势与转化' },
  { key: 'team', label: '团队与客户' },
];

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

const money = micros => `¥${Math.round((micros || 0) / 1_000_000).toLocaleString()}`;

// ── Tab① 业绩统计：按 period + 选中月读取对应桶 ──
const periodStat = computed(() => {
  const ps = stats.value?.period_stats;
  if (!ps) return { amount_micros: 0, order_count: 0, deal_customers: 0, new_customers: 0 };
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
    { label: '成交额', value: money(s.amount_micros), hero: true },
    { label: '成交订单数', value: s.order_count },
    { label: '成交客户数', value: s.deal_customers },
    { label: '新成交客户数', value: s.new_customers },
  ];
});

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

// ── Tab② 趋势 ──
const monthlyBars = computed(() => {
  const arr = stats.value?.trends?.monthly_amount_micros || [];
  const max = Math.max(1, ...arr);
  const current = new Date().getMonth() + 1;
  return arr.map((v, i) => ({
    month: i + 1,
    value: v,
    pct: v ? Math.max(3, Math.round((v / max) * 100)) : 0,
    active: i + 1 === current,
  }));
});

// 通用横向条形：对象 {key: value} → 排序后的行，附百分比与格式化值
const toBars = (obj, { labels, format } = {}) => {
  const entries = Object.entries(obj || {}).filter(([, v]) => v);
  const max = Math.max(1, ...entries.map(([, v]) => v));
  return entries
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => ({
      label: labels ? labels[k] || k : k,
      value: format ? format(v) : v,
      pct: Math.max(3, Math.round((v / max) * 100)),
    }));
};

const stageBars = computed(() =>
  Object.keys(STAGE_LABELS)
    .map(stage => {
      const v = stats.value?.trends?.opportunity_amount_by_stage?.[stage] || 0;
      return { stage, label: STAGE_LABELS[stage], raw: v };
    })
    .filter(r => r.raw)
    .map((r, _, arr) => {
      const max = Math.max(1, ...arr.map(x => x.raw));
      return { ...r, value: money(r.raw), pct: Math.max(3, Math.round((r.raw / max) * 100)) };
    })
);

const sourceBars = computed(() =>
  toBars(stats.value?.source_breakdown, { labels: SOURCE_LABELS })
);

// ── Tab③ 团队与客户 ──
const totalCards = computed(() => {
  const tt = stats.value?.totals;
  if (!tt) return [];
  return [
    { label: '客户总数', value: tt.total_customers },
    { label: '成交客户数', value: tt.won_customers },
    { label: '进行中商机', value: tt.open_opportunities },
    { label: '订单总额（累计）', value: money(tt.total_order_amount_micros), hero: true },
    { label: '新成交客户（累计）', value: tt.dealt_customers_total },
    { label: '公海客户', value: tt.public_pool_customers },
    {
      label: '平均回复时长',
      value: tt.avg_reply_latency_hours != null ? `${tt.avg_reply_latency_hours}h` : '—',
    },
  ];
});

const teamAmountBars = computed(() =>
  toBars(stats.value?.team?.by_team_amount, { format: money })
);
const ownerAmountBars = computed(() =>
  toBars(stats.value?.team?.by_owner_amount, { format: money })
);
const ownerCustomerBars = computed(() =>
  toBars(stats.value?.team?.by_owner_won_customers)
);
const ownerCompletenessBars = computed(() =>
  toBars(stats.value?.team?.by_owner_completeness, { format: v => `${v}分` })
);
const ownerLatencyBars = computed(() =>
  toBars(stats.value?.team?.by_owner_reply_latency, { format: v => `${v}h` })
);
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 p-6 overflow-auto bg-n-background">
    <div class="flex items-center justify-between">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{
          scope === 'mine'
            ? t('CRM.DASHBOARD.HEADER_MINE')
            : t('CRM.DASHBOARD.HEADER_COMPANY')
        }}
      </h1>
      <span class="text-sm text-n-slate-11">
        {{ stats?.year || new Date().getFullYear() }}年
      </span>
    </div>

    <!-- Tab 切换 -->
    <div class="flex gap-1 border-b border-n-weak">
      <button
        v-for="tab in TABS"
        :key="tab.key"
        class="px-4 py-2 -mb-px text-sm border-b-2 transition-colors"
        :class="
          activeTab === tab.key
            ? 'border-n-blue-9 text-n-blue-11 font-medium'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="activeTab = tab.key"
      >
        {{ tab.label }}
      </button>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.DASHBOARD.LOADING') }}
    </div>

    <template v-else>
      <!-- ═══ Tab① 业绩概览 ═══ -->
      <div v-show="activeTab === 'overview'" class="flex flex-col gap-4">
        <div class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="flex flex-wrap items-center gap-3 mb-4">
            <span class="font-medium text-n-slate-12">📊 业绩统计</span>
            <div class="flex gap-1">
              <button
                v-for="p in [
                  { k: 'month', l: '月度' },
                  { k: 'quarter', l: '季度' },
                  { k: 'year', l: '年度' },
                ]"
                :key="p.k"
                class="h-8 px-3 text-sm border rounded-lg"
                :class="
                  period === p.k
                    ? 'bg-n-blue-9 text-white border-n-blue-9'
                    : 'border-n-weak text-n-slate-11'
                "
                @click="period = p.k"
              >
                {{ p.l }}
              </button>
            </div>
            <select
              v-if="period !== 'year'"
              v-model.number="selectedMonth"
              class="h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <option v-for="m in 12" :key="m" :value="m">{{ m }}月</option>
            </select>
            <span class="text-xs text-n-slate-10">
              {{ periodLabel }} · {{ scope === 'mine' ? '我的' : '全公司' }}
            </span>
          </div>
          <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
            <div
              v-for="kpi in salesKpis"
              :key="kpi.label"
              class="p-4 border rounded-xl border-n-weak"
              :class="kpi.hero ? 'bg-n-blue-9 text-white' : 'bg-n-solid-2'"
            >
              <div
                class="text-xs"
                :class="kpi.hero ? 'text-white/80' : 'text-n-slate-11'"
              >
                {{ kpi.label }}
              </div>
              <div class="mt-1 text-2xl font-bold">{{ kpi.value }}</div>
            </div>
          </div>
        </div>

        <div
          v-if="targetProgress"
          class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="mb-3 font-medium text-n-slate-12">🎯 本月目标完成率</div>
          <div class="flex items-end gap-3">
            <span class="text-3xl font-bold text-n-slate-12">
              {{ targetProgress.pct }}%
            </span>
            <span class="mb-1 text-sm text-n-slate-11">
              {{ targetProgress.done }} / {{ targetProgress.target }}
            </span>
          </div>
          <div class="h-3 mt-3 overflow-hidden rounded-full bg-n-alpha-2">
            <div
              class="h-full rounded-full bg-n-teal-9"
              :style="{ width: `${targetProgress.pct}%` }"
            />
          </div>
        </div>
        <div
          v-else
          class="p-5 text-sm border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-11"
        >
          本月尚未设定目标。前往「数据看板 → 我的目标」设定。
        </div>
      </div>

      <!-- ═══ Tab② 趋势与转化 ═══ -->
      <div v-show="activeTab === 'trends'" class="flex flex-col gap-4">
        <div class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="mb-4 font-medium text-n-slate-12">订单金额趋势（按月）</div>
          <div class="flex items-end h-48 gap-2">
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
                  :title="money(bar.value)"
                />
              </div>
              <div
                class="mt-1 text-[10px]"
                :class="
                  bar.active ? 'font-bold text-n-blue-11' : 'text-n-slate-10'
                "
              >
                {{ bar.month }}月
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
            <div class="mb-4 font-medium text-n-slate-12">商机金额（按阶段）</div>
            <div v-if="!stageBars.length" class="text-sm text-n-slate-10">
              暂无商机数据
            </div>
            <div class="flex flex-col gap-2">
              <div
                v-for="row in stageBars"
                :key="row.stage"
                class="flex items-center gap-2 text-sm"
              >
                <span class="w-16 text-xs shrink-0 text-n-slate-11">
                  {{ row.label }}
                </span>
                <div class="flex-1 h-4 overflow-hidden rounded bg-n-alpha-1">
                  <div
                    class="h-full rounded bg-n-iris-8"
                    :style="{ width: `${row.pct}%` }"
                  />
                </div>
                <span class="text-xs text-right w-20 shrink-0 text-n-slate-11">
                  {{ row.value }}
                </span>
              </div>
            </div>
          </div>

          <div class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
            <div class="mb-4 font-medium text-n-slate-12">客户来源占比</div>
            <div v-if="!sourceBars.length" class="text-sm text-n-slate-10">
              暂无客户来源数据
            </div>
            <div class="flex flex-col gap-2">
              <div
                v-for="row in sourceBars"
                :key="row.label"
                class="flex items-center gap-2 text-sm"
              >
                <span class="text-xs w-28 shrink-0 text-n-slate-11">
                  {{ row.label }}
                </span>
                <div class="flex-1 h-4 overflow-hidden rounded bg-n-alpha-1">
                  <div
                    class="h-full rounded bg-n-teal-8"
                    :style="{ width: `${row.pct}%` }"
                  />
                </div>
                <span class="w-8 text-xs text-right shrink-0 text-n-slate-11">
                  {{ row.value }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ═══ Tab③ 团队与客户 ═══ -->
      <div v-show="activeTab === 'team'" class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
          <div
            v-for="card in totalCards"
            :key="card.label"
            class="p-4 border rounded-xl border-n-weak"
            :class="card.hero ? 'bg-n-blue-9 text-white' : 'bg-n-solid-1'"
          >
            <div
              class="text-xs"
              :class="card.hero ? 'text-white/80' : 'text-n-slate-11'"
            >
              {{ card.label }}
            </div>
            <div class="mt-1 text-2xl font-bold">{{ card.value }}</div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div
            v-for="section in [
              { title: '各团队成交金额', rows: teamAmountBars, color: 'bg-n-blue-8' },
              { title: '各业务员成交金额', rows: ownerAmountBars, color: 'bg-n-blue-8' },
              { title: '各业务员成交客户数', rows: ownerCustomerBars, color: 'bg-n-teal-8' },
              { title: '各业务员资料完善度（平均）', rows: ownerCompletenessBars, color: 'bg-n-iris-8' },
              { title: '各业务员平均回复时长（越短越好）', rows: ownerLatencyBars, color: 'bg-n-amber-8' },
            ]"
            :key="section.title"
            class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <div class="mb-4 font-medium text-n-slate-12">
              {{ section.title }}
            </div>
            <div v-if="!section.rows.length" class="text-sm text-n-slate-10">
              暂无数据
            </div>
            <div class="flex flex-col gap-2">
              <div
                v-for="row in section.rows"
                :key="row.label"
                class="flex items-center gap-2 text-sm"
              >
                <span class="text-xs truncate w-28 shrink-0 text-n-slate-11">
                  {{ row.label }}
                </span>
                <div class="flex-1 h-4 overflow-hidden rounded bg-n-alpha-1">
                  <div
                    class="h-full rounded"
                    :class="section.color"
                    :style="{ width: `${row.pct}%` }"
                  />
                </div>
                <span class="text-xs text-right w-20 shrink-0 text-n-slate-11">
                  {{ row.value }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
