<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import TiktokDashboardAPI from 'dashboard/api/tiktok/dashboard';
import { useTiktokShopsStore } from 'dashboard/stores/tiktok/shops';
import CrmAreaChart from 'dashboard/components-next/CRM/charts/CrmAreaChart.vue';
import CrmDoughnutChart from 'dashboard/components-next/CRM/charts/CrmDoughnutChart.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import { usesClassicContentColors } from 'dashboard/components-next/CRM/charts/chartColors';
import { useThemeSignal } from 'dashboard/components-next/CRM/charts/useThemeSignal';
// TikTok 数据看板：按月 + 店铺汇总。KPI 卡 + 每日趋势（RMB）+ 分店铺明细。
// 金额一律用录入时的 RMB 快照汇总，口径稳定。
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
// 紫玻璃团队筛选下拉选项（含「全部团队」）
const teamFilterOptions = computed(() => [
  { value: '', label: '全部团队' },
  ...teams.value.map(t => ({ value: t.id, label: t.name })),
]);

const summary = computed(() => data.value?.summary || {});
const byTeam = computed(() => data.value?.by_team || []);
const daily = computed(() => data.value?.daily || []);

// 订单来源饼图：本月四类订单来源占比（联盟直播/联盟/商品卡/商家）。
// 中性内容主题使用金黄 / 石墨 / 蓝灰 / 浅沙色，其它主题保留原色板。
const themeSignal = useThemeSignal();
const SOURCE_META = [
  { key: 'alliance_live', label: '联盟直播订单', color: '#8B5CF6' },
  { key: 'alliance', label: '联盟订单', color: '#14B8A6' },
  { key: 'product_card', label: '商品卡订单', color: '#F5A524' },
  { key: 'merchant', label: '商家订单', color: '#FB7185' },
];
const sourceColors = computed(() => {
  // eslint-disable-next-line no-void -- track body theme changes for the canvas palette
  void themeSignal.value;
  return usesClassicContentColors()
    ? ['#ffc53d', '#292d35', '#9dafbd', '#f2dbac']
    : SOURCE_META.map(row => row.color);
});
const bySource = computed(() => {
  const src = data.value?.by_source || {};
  const rows = SOURCE_META.map((m, index) => ({
    ...m,
    color: sourceColors.value[index],
    dotClass: usesClassicContentColors()
      ? ['bg-[#ffc53d]', 'bg-[#292d35]', 'bg-[#9dafbd]', 'bg-[#f2dbac]'][index]
      : ['bg-[#8B5CF6]', 'bg-[#14B8A6]', 'bg-[#F5A524]', 'bg-[#FB7185]'][index],
    value: Number(src[m.key] || 0),
  }));
  const total = rows.reduce((s, r) => s + r.value, 0);
  return {
    rows: rows.map(r => ({
      ...r,
      pct: total ? r.value / total : 0,
    })),
    total,
    labels: rows.map(r => r.label),
    data: rows.map(r => r.value),
    colors: rows.map(r => r.color),
    empty: total === 0,
  };
});

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
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-slate-2 rounded-3xl border border-n-weak"
  >
    <div
      class="flex flex-col w-full max-w-[1440px] gap-4 px-4 py-4 mx-auto sm:px-6 sm:py-6"
    >
      <!-- 头部 -->
      <div
        class="flex flex-wrap items-center justify-between gap-3 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3"
      >
        <h1 class="text-heading-1 text-n-slate-12">TikTok 数据看板</h1>
        <div class="flex flex-wrap items-center gap-2">
          <MonthPicker
            v-model="filters.month"
            trigger-class="w-40 h-10"
            :clearable="false"
            @change="load"
          />
          <SelectCard
            v-model="filters.teamId"
            :options="teamFilterOptions"
            trigger-class="w-40 h-10"
            @update:model-value="load"
          />
        </div>
      </div>

      <div v-if="loading" class="py-16 text-label text-center text-n-slate-10">
        加载中…
      </div>

      <template v-else>
        <!-- KPI 卡 -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <div
            v-for="(kpi, i) in kpis"
            :key="kpi.label"
            class="flex items-start gap-3 p-5 border rounded-2xl min-h-32"
            :class="
              i === 0
                ? 'bg-[#1e222b] border-[#1e222b] text-white'
                : 'bg-n-solid-1 border-n-weak text-n-slate-12'
            "
          >
            <div
              class="flex items-center justify-center shrink-0 size-6 mt-0.5"
              :class="i === 0 ? 'text-white/80' : 'text-n-slate-11'"
            >
              <span class="size-6" :class="kpi.icon" />
            </div>
            <div>
              <div
                class="text-label"
                :class="i === 0 ? 'text-white/80' : 'text-n-slate-11'"
              >
                {{ kpi.label }}
              </div>
              <div
                class="mt-2 text-3xl font-semibold leading-tight tabular-nums"
              >
                {{ kpi.value }}
              </div>
              <div
                class="mt-1 text-label-small"
                :class="i === 0 ? 'text-white/60' : 'text-n-slate-10'"
              >
                {{ kpi.sub }}
              </div>
            </div>
          </div>
        </div>

        <!-- 平均取消率/有效率条 -->
        <div
          class="flex flex-wrap gap-x-5 gap-y-2 px-1 py-1 text-label-small sm:text-label"
        >
          <div class="flex items-center gap-2">
            <span class="text-n-slate-11">平均取消率</span>
            <b
              :class="
                summary.cancel_rate > 0.3 ? 'text-n-ruby-11' : 'text-n-slate-12'
              "
            >
              {{ pct(summary.cancel_rate) }}
            </b>
          </div>
          <div class="flex items-center gap-2 border-l border-n-weak pl-5">
            <span class="text-n-slate-11">平均订单有效率</span>
            <b class="text-n-slate-12">{{ pct(summary.valid_rate) }}</b>
          </div>
          <div class="flex items-center gap-2 border-l border-n-weak pl-5">
            <span class="text-n-slate-11">当天取消台数</span>
            <b class="text-n-slate-12">{{ summary.cancelled_units || 0 }}</b>
          </div>
        </div>

        <div class="grid grid-cols-1 items-stretch gap-4 xl:grid-cols-5">
          <!-- 每日销售额趋势 -->
          <div
            class="min-w-0 p-5 border rounded-2xl border-n-weak bg-n-solid-1 xl:col-span-3"
          >
            <h2 class="mb-4 text-heading-2 text-n-slate-12">
              每日销售额趋势（RMB）
            </h2>
            <div class="h-48">
              <CrmAreaChart
                v-if="!trend.empty"
                :labels="trend.labels"
                :data="trend.data"
                :value-format="cny"
                :tension="0"
                :point-radius="4"
              />
              <div
                v-else
                class="flex items-center justify-center h-full text-label text-n-slate-10"
              >
                本月暂无数据
              </div>
            </div>
          </div>

          <!-- 订单来源占比（本月，按订单数） -->
          <div
            class="min-w-0 p-5 border rounded-2xl border-n-weak bg-n-solid-1 xl:col-span-2"
          >
            <h2 class="mb-4 text-heading-2 text-n-slate-12">
              订单来源占比（本月）
            </h2>
            <div
              v-if="bySource.empty"
              class="flex items-center justify-center h-48 text-label text-n-slate-10"
            >
              本月暂无订单来源数据（录入时填写四类订单即可）
            </div>
            <div
              v-else
              class="flex min-h-48 flex-col items-center justify-center gap-4 sm:h-48 sm:flex-row xl:gap-3"
            >
              <div
                class="relative size-36 shrink-0 sm:size-40 xl:size-32 2xl:size-40"
              >
                <CrmDoughnutChart
                  :labels="bySource.labels"
                  :data="bySource.data"
                  :colors="bySource.colors"
                  :value-format="v => `${v} 笔`"
                >
                  <template #center>
                    <span class="text-label-small text-n-slate-10">总订单</span>
                    <span class="text-2xl font-bold text-n-slate-12">
                      {{ bySource.total }}
                    </span>
                  </template>
                </CrmDoughnutChart>
              </div>
              <div class="flex w-full min-w-0 flex-1 flex-col gap-3">
                <div
                  v-for="row in bySource.rows"
                  :key="row.key"
                  class="flex items-center gap-2 text-label-small"
                >
                  <span
                    class="rounded-full size-2.5 shrink-0"
                    :class="row.dotClass"
                  />
                  <span class="min-w-0 flex-1 text-n-slate-11">{{
                    row.label
                  }}</span>
                  <span
                    class="shrink-0 font-medium tabular-nums text-n-slate-12"
                  >
                    {{ row.value }} 笔
                  </span>
                  <span
                    class="w-12 shrink-0 text-right tabular-nums text-n-slate-10"
                  >
                    {{ pct(row.pct) }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 分团队明细 -->
        <div class="p-5 border rounded-2xl border-n-weak bg-n-solid-1">
          <h2 class="mb-4 text-heading-2 text-n-slate-12">分团队明细</h2>

          <!-- 手机卡片 -->
          <div class="flex flex-col gap-2 md:hidden">
            <div
              v-for="row in byTeam"
              :key="row.team_id ?? 'none'"
              class="p-3 border rounded-xl border-n-weak bg-n-solid-1"
            >
              <div class="flex items-center gap-2">
                <span class="font-medium truncate text-n-slate-12">
                  {{ row.team_name }}
                </span>
                <span class="flex-1" />
                <span
                  class="text-label font-medium tabular-nums shrink-0 text-n-slate-12"
                >
                  {{ cny(row.amount_cny) }}
                </span>
              </div>
              <div
                class="grid grid-cols-2 mt-2 gap-x-3 gap-y-1 text-label-small text-n-slate-11"
              >
                <div>店铺数：{{ row.shop_count }}</div>
                <div>订单：{{ row.total_orders }}</div>
                <div>台数：{{ row.total_units }}</div>
                <div>实发：{{ row.shipped_units }}</div>
                <div>达人：{{ row.influencer_units }}</div>
                <div>有效率：{{ pct(row.valid_rate) }}</div>
                <div
                  :class="
                    row.cancel_rate > 0.3
                      ? 'text-n-ruby-11 font-medium'
                      : 'text-n-slate-11'
                  "
                >
                  取消率：{{ pct(row.cancel_rate) }}
                </div>
              </div>
            </div>
            <div
              v-if="!byTeam.length"
              class="py-10 text-label text-center text-n-slate-10"
            >
              本月暂无数据
            </div>
          </div>

          <HScrollButtons />
          <div class="hidden overflow-x-auto md:block">
            <table class="w-full text-label">
              <thead>
                <tr class="text-label-small text-left text-n-slate-11">
                  <th class="py-2 pr-3 font-medium whitespace-nowrap">团队</th>
                  <th
                    class="py-2 px-3 font-medium text-right whitespace-nowrap"
                  >
                    店铺数
                  </th>
                  <th
                    class="py-2 px-3 font-medium text-right whitespace-nowrap"
                  >
                    销售额 (RMB)
                  </th>
                  <th
                    class="py-2 px-3 font-medium text-right whitespace-nowrap"
                  >
                    订单
                  </th>
                  <th
                    class="py-2 px-3 font-medium text-right whitespace-nowrap"
                  >
                    台数
                  </th>
                  <th
                    class="py-2 px-3 font-medium text-right whitespace-nowrap"
                  >
                    实发
                  </th>
                  <th
                    class="py-2 px-3 font-medium text-right whitespace-nowrap"
                  >
                    达人
                  </th>
                  <th
                    class="py-2 px-3 font-medium text-right whitespace-nowrap"
                  >
                    取消率
                  </th>
                  <th
                    class="py-2 pl-3 font-medium text-right whitespace-nowrap"
                  >
                    有效率
                  </th>
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
                    <div class="flex items-center justify-end gap-2">
                      {{ pct(row.valid_rate) }}
                      <progress
                        v-if="row.valid_rate != null"
                        :value="row.valid_rate"
                        max="1"
                        :aria-label="`有效率 ${pct(row.valid_rate)}`"
                        class="h-1.5 w-16 overflow-hidden rounded-full [&::-webkit-progress-bar]:bg-n-slate-3 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-n-amber-9 [&::-moz-progress-bar]:bg-n-amber-9"
                      />
                    </div>
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
