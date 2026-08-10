<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import TiktokDashboardAPI from 'dashboard/api/tiktok/dashboard';
import { useTiktokShopsStore } from 'dashboard/stores/tiktok/shops';
import CrmAreaChart from 'dashboard/components-next/CRM/charts/CrmAreaChart.vue';

// TikTok 数据看板：按月 + 店铺汇总。KPI 卡 + 每日趋势（RMB）+ 分店铺明细。
// 金额一律用录入时的 RMB 快照汇总，口径稳定。
const CARD_GRADIENTS = [
  'from-n-iris-3 to-n-iris-5',
  'from-n-iris-4 to-n-blue-4',
  'from-n-blue-3 to-n-iris-5',
  'from-n-iris-3 to-n-iris-6',
];

const shopsStore = useTiktokShopsStore();
const shops = ref([]);
const loading = ref(false);
const data = ref(null);

const thisMonth = () => new Date().toISOString().slice(0, 7);
const filters = ref({ month: thisMonth(), teamId: '' });

const cny = v =>
  `¥${Number(v || 0).toLocaleString('zh-CN', { maximumFractionDigits: 0 })}`;
const pct = v => (v == null ? '—' : `${(v * 100).toFixed(1)}%`);

// 团队筛选项：从可见店铺的所属部门去重得出（不额外调管理员专属的部门接口）。
const teams = computed(() => {
  const map = new Map();
  shops.value.forEach(s => {
    if (s.departmentId) map.set(s.departmentId, s.departmentName);
  });
  return [...map].map(([id, name]) => ({ id, name }));
});

const summary = computed(() => data.value?.summary || {});
const byTeam = computed(() => data.value?.by_team || []);
const daily = computed(() => data.value?.daily || []);

const kpis = computed(() => {
  const s = summary.value;
  return [
    {
      label: '总销售额 (RMB)',
      value: cny(s.amount_cny),
      sub: filters.value.month,
      icon: 'i-lucide-wallet',
    },
    {
      label: '总订单',
      value: s.total_orders || 0,
      sub: '笔',
      icon: 'i-lucide-shopping-cart',
    },
    {
      label: '总台数',
      value: s.total_units || 0,
      sub: '台',
      icon: 'i-lucide-package',
    },
    {
      label: '最终签收 (实发)',
      value: s.shipped_units || 0,
      sub: `达人 ${s.influencer_units || 0} 台`,
      icon: 'i-lucide-truck',
    },
  ];
});

const trend = computed(() => ({
  labels: daily.value.map(d => d.date.slice(5)),
  data: daily.value.map(d => Number(d.amount_cny || 0)),
  empty: !daily.value.length,
}));

const load = async () => {
  loading.value = true;
  try {
    const { data: payload } = await TiktokDashboardAPI.show({
      month: filters.value.month,
      team_id: filters.value.teamId,
    });
    data.value = payload;
  } catch (e) {
    useAlert(e?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

onMounted(async () => {
  try {
    shops.value = await shopsStore.get();
  } catch (e) {
    /* 店铺取不到不阻塞看板 */
  }
  await load();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto">
    <div class="flex flex-col w-full max-w-6xl gap-4 px-8 py-6 mx-auto">
      <!-- 头部 -->
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h1 class="text-xl font-semibold text-n-slate-12">TikTok 数据看板</h1>
        <div class="flex items-center gap-2">
          <input
            v-model="filters.month"
            type="month"
            class="w-40 h-10 pl-3 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            @change="load"
          />
          <select
            v-model="filters.teamId"
            class="w-40 h-10 pl-3 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            @change="load"
          >
            <option value="">全部团队</option>
            <option v-for="tm in teams" :key="tm.id" :value="tm.id">
              {{ tm.name }}
            </option>
          </select>
        </div>
      </div>

      <div v-if="loading" class="py-16 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <template v-else>
        <!-- KPI 卡 -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <div
            v-for="(kpi, i) in kpis"
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

        <!-- 平均取消率/有效率条 -->
        <div
          class="flex flex-wrap gap-x-6 gap-y-1 px-5 py-3 text-sm border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45"
        >
          <div class="flex items-center gap-1">
            <span class="text-n-slate-11">平均取消率</span>
            <b
              :class="
                summary.cancel_rate > 0.3 ? 'text-n-ruby-11' : 'text-n-slate-12'
              "
            >
              {{ pct(summary.cancel_rate) }}
            </b>
          </div>
          <div class="flex items-center gap-1">
            <span class="text-n-slate-11">平均订单有效率</span>
            <b class="text-n-slate-12">{{ pct(summary.valid_rate) }}</b>
          </div>
          <div class="flex items-center gap-1">
            <span class="text-n-slate-11">当天取消台数</span>
            <b class="text-n-slate-12">{{ summary.cancelled_units || 0 }}</b>
          </div>
        </div>

        <!-- 每日销售额趋势 -->
        <div
          class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            每日销售额趋势（RMB）
          </h2>
          <div class="h-64">
            <CrmAreaChart
              v-if="!trend.empty"
              :labels="trend.labels"
              :data="trend.data"
              :value-format="cny"
            />
            <div
              v-else
              class="flex items-center justify-center h-full text-sm text-n-slate-10"
            >
              本月暂无数据
            </div>
          </div>
        </div>

        <!-- 分团队明细 -->
        <div
          class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">分团队明细</h2>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-xs text-left text-n-slate-11">
                  <th class="py-2 pr-3 font-medium">团队</th>
                  <th class="py-2 px-3 font-medium text-right">店铺数</th>
                  <th class="py-2 px-3 font-medium text-right">销售额 (RMB)</th>
                  <th class="py-2 px-3 font-medium text-right">订单</th>
                  <th class="py-2 px-3 font-medium text-right">台数</th>
                  <th class="py-2 px-3 font-medium text-right">实发</th>
                  <th class="py-2 px-3 font-medium text-right">达人</th>
                  <th class="py-2 px-3 font-medium text-right">取消率</th>
                  <th class="py-2 pl-3 font-medium text-right">有效率</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in byTeam"
                  :key="row.team_id ?? 'none'"
                  class="border-t border-n-weak"
                >
                  <td class="py-2.5 pr-3 whitespace-nowrap text-n-slate-12">
                    {{ row.team_name }}
                  </td>
                  <td
                    class="py-2.5 px-3 text-right tabular-nums text-n-slate-11"
                  >
                    {{ row.shop_count }}
                  </td>
                  <td
                    class="py-2.5 px-3 text-right tabular-nums font-medium text-n-slate-12"
                  >
                    {{ cny(row.amount_cny) }}
                  </td>
                  <td
                    class="py-2.5 px-3 text-right tabular-nums text-n-slate-11"
                  >
                    {{ row.total_orders }}
                  </td>
                  <td
                    class="py-2.5 px-3 text-right tabular-nums text-n-slate-11"
                  >
                    {{ row.total_units }}
                  </td>
                  <td
                    class="py-2.5 px-3 text-right tabular-nums text-n-slate-11"
                  >
                    {{ row.shipped_units }}
                  </td>
                  <td
                    class="py-2.5 px-3 text-right tabular-nums text-n-slate-11"
                  >
                    {{ row.influencer_units }}
                  </td>
                  <td
                    class="py-2.5 px-3 text-right tabular-nums"
                    :class="
                      row.cancel_rate > 0.3
                        ? 'text-n-ruby-11 font-medium'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ pct(row.cancel_rate) }}
                  </td>
                  <td
                    class="py-2.5 pl-3 text-right tabular-nums text-n-slate-11"
                  >
                    {{ pct(row.valid_rate) }}
                  </td>
                </tr>
                <tr v-if="!byTeam.length">
                  <td colspan="9" class="py-10 text-center text-n-slate-10">
                    本月暂无数据
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
