<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import TiktokTodayAPI from 'dashboard/api/tiktok/today';

// TikTok 今日速览：一屏看当天各店售出数据（老板每天扫一眼），不用选月份。
const loading = ref(false);
const data = ref(null);

const cny = v =>
  `¥${Number(v || 0).toLocaleString('zh-CN', { maximumFractionDigits: 0 })}`;
const pct = v => (v == null ? '—' : `${(v * 100).toFixed(1)}%`);

const summary = computed(() => data.value?.summary || {});
const shops = computed(() => data.value?.shops || []);

// 今日 vs 昨日环比：销售额 / 订单 / 台数（较所示日的前一天）。昨日为 0 时不显示涨跌。
const dayCompare = computed(() => {
  const dc = data.value?.day_compare || {};
  const t = dc.today || {};
  const y = dc.yesterday || {};
  const delta = (a, b) => {
    const na = Number(a || 0);
    const nb = Number(b || 0);
    if (!nb) return null;
    return (na - nb) / nb;
  };
  return [
    {
      label: '销售额',
      value: cny(t.amount_cny),
      change: delta(t.amount_cny, y.amount_cny),
    },
    {
      label: '订单',
      value: `${Number(t.total_orders || 0)} 笔`,
      change: delta(t.total_orders, y.total_orders),
    },
    {
      label: '台数',
      value: `${Number(t.total_units || 0)} 台`,
      change: delta(t.total_units, y.total_units),
    },
  ];
});
const changePct = v => `${v > 0 ? '+' : ''}${(v * 100).toFixed(1)}%`;

const dateLabel = computed(() => {
  const d = data.value?.date;
  if (!d) return '';
  const wd = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  const dt = new Date(`${d}T00:00:00`);
  return `${d} · ${wd[dt.getDay()]}`;
});

const CARD_GRADIENTS = [
  'from-n-iris-3 to-n-iris-5',
  'from-n-iris-4 to-n-blue-4',
  'from-n-blue-3 to-n-iris-5',
  'from-n-iris-3 to-n-iris-6',
];

const kpis = computed(() => {
  const s = summary.value;
  return [
    {
      label: '今日售出台数',
      value: s.total_units || 0,
      sub: `签收 ${s.shipped_units || 0} · 达人 ${s.influencer_units || 0}`,
      icon: 'i-lucide-package',
    },
    {
      label: '今日销售额 (RMB)',
      value: cny(s.amount_cny),
      sub: dateLabel.value,
      icon: 'i-lucide-wallet',
    },
    {
      label: '今日订单',
      value: s.total_orders || 0,
      sub: '笔',
      icon: 'i-lucide-shopping-cart',
    },
    {
      label: '今日取消率',
      value: pct(s.cancel_rate),
      sub: `取消 ${s.cancelled_units || 0} 台`,
      icon: 'i-lucide-circle-slash',
    },
  ];
});

const load = async () => {
  loading.value = true;
  try {
    const { data: payload } = await TiktokTodayAPI.get();
    data.value = payload;
  } catch (e) {
    useAlert(e?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex flex-col w-full max-w-6xl gap-4 px-4 py-4 mx-auto sm:px-8 sm:py-6"
    >
      <!-- 头部 -->
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">今日速览</h1>
        <span class="text-sm text-n-slate-11">
          {{ dateLabel }} ·
          <b class="text-n-slate-12">{{ data?.recorded_shops || 0 }}</b>
          /
          {{ data?.total_shops || 0 }} 店已录入
        </span>
      </div>

      <div v-if="loading" class="py-16 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <template v-else>
        <!-- 今日 vs 昨日环比 -->
        <div
          class="flex flex-wrap items-stretch gap-x-8 gap-y-3 px-5 py-4 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45"
        >
          <div class="flex items-center gap-1.5 text-sm text-n-slate-11">
            <span class="i-lucide-calendar-clock size-4 text-n-iris-11" />
            今日 vs 昨日
          </div>
          <div
            v-for="item in dayCompare"
            :key="item.label"
            class="flex flex-col gap-0.5"
          >
            <span class="text-xs text-n-slate-10">{{ item.label }}</span>
            <div class="flex items-baseline gap-2">
              <span class="text-lg font-bold text-n-slate-12">
                {{ item.value }}
              </span>
              <span
                v-if="item.change != null"
                class="text-xs font-medium"
                :class="item.change >= 0 ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                <span
                  class="size-3 align-middle"
                  :class="
                    item.change >= 0
                      ? 'i-lucide-trending-up'
                      : 'i-lucide-trending-down'
                  "
                />
                {{ changePct(item.change) }}
              </span>
              <span v-else class="text-xs text-n-slate-9">昨日无</span>
            </div>
          </div>
        </div>

        <!-- 今日 KPI -->
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

        <!-- 各店今日 -->
        <div
          class="p-4 border shadow-sm sm:p-5 rounded-2xl border-white/60 bg-n-solid-1/45"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">各店今日</h2>

          <!-- 手机卡片 -->
          <div class="flex flex-col gap-2 md:hidden">
            <div
              v-for="row in shops"
              :key="`m-${row.shop_id}`"
              class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
              :class="{ 'opacity-50': !row.has_data }"
            >
              <div class="flex items-center gap-2">
                <span class="font-medium truncate text-n-slate-12">
                  {{ row.shop_name }}
                </span>
                <span class="flex-1" />
                <span
                  v-if="row.has_data"
                  class="text-lg font-bold shrink-0 tabular-nums text-n-slate-12"
                >
                  {{ row.total_units }}
                </span>
                <span v-else class="text-xs shrink-0 text-n-slate-9">
                  今日未录入
                </span>
              </div>
              <div class="mt-1 text-xs text-n-slate-11">
                团队：{{ row.team_name || '—' }}
              </div>
              <div
                v-if="row.has_data"
                class="flex flex-wrap mt-2 text-xs gap-x-3 gap-y-1 text-n-slate-11"
              >
                <span>订单：{{ row.total_orders }}</span>
                <span>销售额：{{ cny(row.amount_cny) }}</span>
                <span>签收：{{ row.shipped_units }}</span>
                <span>达人：{{ row.influencer_units }}</span>
                <span
                  :class="
                    row.cancel_rate > 0.3 ? 'text-n-ruby-11 font-medium' : ''
                  "
                >
                  取消率：{{ pct(row.cancel_rate) }}
                </span>
              </div>
            </div>
            <div
              v-if="!shops.length"
              class="py-10 text-sm text-center text-n-slate-10"
            >
              暂无店铺，先到「店铺设置」新增。
            </div>
          </div>

          <div class="hidden overflow-x-auto md:block">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-xs text-left text-n-slate-11">
                  <th class="py-2 pr-3 font-medium">店铺</th>
                  <th class="py-2 px-3 font-medium">团队</th>
                  <th class="py-2 px-3 font-medium text-right">售出台数</th>
                  <th class="py-2 px-3 font-medium text-right">订单</th>
                  <th class="py-2 px-3 font-medium text-right">销售额 (RMB)</th>
                  <th class="py-2 px-3 font-medium text-right">签收</th>
                  <th class="py-2 px-3 font-medium text-right">达人</th>
                  <th class="py-2 pl-3 font-medium text-right">取消率</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in shops"
                  :key="row.shop_id"
                  class="border-t border-n-weak"
                  :class="{ 'opacity-50': !row.has_data }"
                >
                  <td class="py-2.5 pr-3 whitespace-nowrap text-n-slate-12">
                    {{ row.shop_name }}
                  </td>
                  <td class="py-2.5 px-3 whitespace-nowrap text-n-slate-11">
                    {{ row.team_name || '—' }}
                  </td>
                  <td
                    v-if="row.has_data"
                    class="py-2.5 px-3 text-right tabular-nums font-medium text-n-slate-12"
                  >
                    {{ row.total_units }}
                  </td>
                  <td
                    v-else
                    class="py-2.5 px-3 text-xs text-right text-n-slate-9"
                    colspan="6"
                  >
                    今日未录入
                  </td>
                  <template v-if="row.has_data">
                    <td
                      class="py-2.5 px-3 text-right tabular-nums text-n-slate-11"
                    >
                      {{ row.total_orders }}
                    </td>
                    <td
                      class="py-2.5 px-3 text-right tabular-nums text-n-slate-12"
                    >
                      {{ cny(row.amount_cny) }}
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
                      class="py-2.5 pl-3 text-right tabular-nums"
                      :class="
                        row.cancel_rate > 0.3
                          ? 'text-n-ruby-11 font-medium'
                          : 'text-n-slate-11'
                      "
                    >
                      {{ pct(row.cancel_rate) }}
                    </td>
                  </template>
                </tr>
                <tr v-if="!shops.length">
                  <td colspan="8" class="py-10 text-center text-n-slate-10">
                    暂无店铺，先到「店铺设置」新增。
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
