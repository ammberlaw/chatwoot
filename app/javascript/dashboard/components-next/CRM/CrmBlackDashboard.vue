<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmAreaChart from './charts/CrmAreaChart.vue';
import CrmBarChart from './charts/CrmBarChart.vue';
import CrmDoughnutChart from './charts/CrmDoughnutChart.vue';
import CrmSentEmailRankChart from './CrmSentEmailRankChart.vue';

const props = defineProps({
  isMine: { type: Boolean, default: false },
  periodLabel: { type: String, required: true },
  periodNoun: { type: String, required: true },
  gmv: { type: Object, required: true },
  summary: { type: Array, required: true },
  target: { type: Object, default: null },
  trend: { type: Object, required: true },
  rank: { type: Array, required: true },
  customers: { type: Array, required: true },
  stages: { type: Array, required: true },
  sources: { type: Object, required: true },
  completeness: { type: Array, required: true },
  privateCustomers: { type: Number, default: 0 },
  privateCompleteness: { type: Number, default: null },
  emailRows: { type: Array, required: true },
  winRate: { type: Number, default: null },
  moneyFormat: { type: Function, required: true },
  initials: { type: Function, required: true },
});
defineEmits(['customer']);
const { t } = useI18n();
const bars = computed(() => {
  const series = props.gmv.viz.series;
  const max = Math.max(...series, 1);
  return series.map((value, index) => ({
    x: index * 24 + 2,
    h: (value / max) * 76,
    active: index === series.length - 1,
  }));
});
const selectedMonth = ref(null);
const trendBars = computed(() => {
  const max = Math.max(...props.trend.data, 1);
  const active = selectedMonth.value ?? props.trend.activeIndex;
  return props.trend.data.map((value, index) => ({
    value,
    label: props.trend.labels[index],
    height: Math.max(6, (value / max) * 184),
    active: index === active,
    x: index * 54 + 5,
  }));
});
const deltaColor = computed(() => {
  if (props.gmv.delta?.dir === 'down') return 'text-[#be4638]';
  if (props.gmv.delta?.dir === 'up') return 'text-[#278161]';
  return 'text-[#85887f]';
});
const sourceColors = [
  '#191b1b',
  '#ffd052',
  '#acae9f',
  '#dadbd2',
  '#f0dca2',
  '#7e8473',
];
const rankColor = index => {
  if (index === 0) return '#ffd052';
  return index < 3 ? '#191b1b' : '#d7d9d0';
};
const rankChart = computed(() => ({
  names: props.rank.slice(0, 8).map(row => row.name.split(' ')[0]),
  values: props.rank.slice(0, 8).map(row => row.amount),
  colors: props.rank.slice(0, 8).map((_, i) => rankColor(i)),
}));
const compactYuan = value =>
  value >= 10000
    ? `¥${(value / 10000).toFixed(1)}万`
    : props.moneyFormat(value);
const customerTotal = computed(() =>
  props.customers.reduce((total, customer) => total + customer.amount, 0)
);
const customerShare = customer =>
  customerTotal.value
    ? Math.round((customer.amount / customerTotal.value) * 100)
    : 0;
const sourceShare = index =>
  props.sources.total
    ? Math.round((props.sources.data[index] / props.sources.total) * 100)
    : 0;
</script>

<template>
  <div data-black-dashboard-design class="flex flex-col gap-8 min-w-0">
    <div class="grid gap-7 xl:grid-cols-12 xl:gap-10 items-stretch">
      <div class="contents">
        <section class="order-1 min-w-0 text-[#191b1b] xl:col-span-8">
          <div
            class="flex items-end justify-between gap-4 px-1 pt-3 pb-7 sm:px-2"
          >
            <div class="min-w-0">
              <div class="flex items-center gap-2 text-label text-[#585c52]">
                <span class="i-lucide-arrow-up-right size-4 text-[#ffd052]" />
                {{ t('CRM.DASHBOARD.DESIGN.REVENUE') }}
                <span class="text-label-small text-[#85887f]">{{
                  gmv.label
                }}</span>
              </div>
              <div
                class="mt-3 text-[clamp(1.8rem,4.8vw,4.1rem)] font-semibold leading-none tracking-tight tabular-nums break-all"
              >
                {{ gmv.value }}
              </div>
              <div
                class="flex flex-wrap items-center gap-x-2 gap-y-1 mt-3 text-label-small"
              >
                <span
                  v-if="gmv.delta"
                  class="font-semibold"
                  :class="deltaColor"
                  >{{ gmv.delta.text }}</span
                >
                <span class="text-[#85887f]">{{
                  gmv.delta?.vs || periodLabel
                }}</span>
              </div>
            </div>
            <div
              v-if="bars.length"
              class="hidden w-[35%] max-w-56 sm:block shrink-0"
            >
              <svg
                width="100%"
                height="92"
                :viewBox="`0 0 ${bars.length * 24} 92`"
                preserveAspectRatio="none"
                aria-hidden="true"
              >
                <rect
                  v-for="(bar, i) in bars"
                  :key="i"
                  :x="bar.x"
                  :y="88 - bar.h"
                  width="15"
                  :height="Math.max(2, bar.h)"
                  rx="3"
                  :fill="bar.active ? '#ffd052' : '#d7d9d0'"
                />
              </svg>
              <p class="mt-1 text-right text-label-small text-[#85887f]">
                {{ t('CRM.DASHBOARD.DESIGN.MONTHLY_REVENUE') }}
              </p>
            </div>
          </div>
          <div
            class="grid grid-cols-3 divide-x divide-[#e2e4dc] border-t border-[#e2e4dc] px-0 py-4"
          >
            <div
              v-for="metric in summary"
              :key="metric.label"
              class="px-3 first:pl-2 sm:px-5"
            >
              <div class="text-label-small text-[#85887f]">
                {{ metric.label }}
              </div>
              <div class="flex items-baseline gap-1.5 mt-1.5">
                <span class="text-2xl font-semibold tabular-nums">{{
                  metric.value
                }}</span>
                <span class="text-label-small text-[#85887f]">{{
                  metric.sub
                }}</span>
              </div>
            </div>
          </div>
        </section>
        <section
          class="order-3 xl:col-span-8 min-w-0 p-6 sm:p-7 bg-[#f6f7f3] rounded-3xl"
        >
          <div class="flex flex-wrap items-center justify-between gap-2 mb-5">
            <h2 class="text-heading-2 text-[#191b1b]">
              {{
                isMine
                  ? t('CRM.DASHBOARD.DESIGN.TREND')
                  : t('CRM.DASHBOARD.DESIGN.TEAM_RANK')
              }}
            </h2>
            <span
              class="px-3 py-1 rounded-full bg-[#fff5cf] text-label-small text-[#725e25]"
              >{{ periodLabel }}</span
            >
          </div>
          <div v-if="isMine" class="h-56 min-w-0">
            <CrmAreaChart
              v-if="!trend.empty"
              :labels="trend.labels"
              :data="trend.data"
              :active-index="trend.activeIndex"
              :value-format="moneyFormat"
            />
            <div
              v-else
              class="grid h-full text-label text-[#85887f] place-items-center"
            >
              {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
            </div>
          </div>
          <template v-else-if="rank.length">
            <div class="hidden sm:block h-56 min-w-0">
              <CrmBarChart
                :labels="rankChart.names"
                :data="rankChart.values"
                :colors="rankChart.colors"
                show-values
                :value-format="compactYuan"
              />
            </div>
            <ol class="flex flex-col sm:hidden">
              <li
                v-for="(person, i) in rank.slice(0, 8)"
                :key="person.name"
                class="flex items-center gap-3 py-3 border-b border-[#f0f1ed] last:border-0 text-label-small"
              >
                <span
                  class="grid size-6 rounded-md font-semibold shrink-0 place-items-center"
                  :class="
                    i === 0
                      ? 'bg-[#ffd052] text-[#191b1b]'
                      : 'bg-[#f1f2ef] text-[#85887f]'
                  "
                  >{{ i + 1 }}</span
                >
                <span class="truncate min-w-0">{{ person.name }}</span
                ><strong class="ml-auto tabular-nums whitespace-nowrap">{{
                  person.value
                }}</strong>
              </li>
            </ol>
            <details class="mt-4 border-t border-[#eceee6] pt-3">
              <summary
                class="cursor-pointer text-label-small text-[#85887f] focus-visible:outline-2 focus-visible:outline-[#a77800]"
              >
                {{ t('CRM.DASHBOARD.DESIGN.ALL_RANK') }} · {{ rank.length }}
              </summary>
              <div
                class="grid gap-x-6 mt-2 sm:grid-cols-2 max-h-64 overflow-y-auto"
              >
                <div
                  v-for="(person, i) in rank"
                  :key="person.name"
                  class="flex items-center gap-2 py-2 text-label-small"
                >
                  <span class="w-4 text-[#85887f]">{{ i + 1 }}</span
                  ><span>{{ person.name }}</span
                  ><strong class="ml-auto tabular-nums">{{
                    person.value
                  }}</strong>
                </div>
              </div>
            </details>
          </template>
          <div
            v-else
            class="grid h-56 text-label text-[#85887f] place-items-center"
          >
            {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
          </div>
        </section>
      </div>
      <div class="contents">
        <section
          class="order-2 xl:col-span-4 xl:self-stretch flex flex-col justify-between p-6 sm:p-7 rounded-[1.75rem] bg-[#ffd052] text-[#191b1b]"
        >
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-heading-2">
              {{ periodNoun }}{{ t('CRM.DASHBOARD.DESIGN.TARGET') }}
            </h2>
            <span class="i-lucide-target size-5" />
          </div>
          <template v-if="target">
            <div class="flex items-center justify-between gap-4 mt-5">
              <div>
                <div
                  class="text-[3.4rem] font-semibold leading-none tracking-tight tabular-nums"
                >
                  {{ target.pct }}<span class="text-2xl">%</span>
                </div>
                <p class="mt-2 text-label-small text-[#5c501e]">
                  {{ t('CRM.DASHBOARD.DESIGN.ACHIEVED') }}
                </p>
              </div>
              <svg
                class="w-28 shrink-0"
                viewBox="0 0 120 80"
                aria-hidden="true"
              >
                <path
                  d="M12 66 A48 48 0 0 1 108 66"
                  fill="none"
                  stroke="#fff0bc"
                  stroke-width="14"
                  stroke-linecap="round"
                />
                <path
                  d="M12 66 A48 48 0 0 1 108 66"
                  fill="none"
                  stroke="#191b1b"
                  stroke-width="14"
                  stroke-linecap="round"
                  pathLength="100"
                  :stroke-dasharray="`${target.pct} 100`"
                />
              </svg>
            </div>
            <div
              class="grid grid-cols-2 gap-4 pt-3 mt-3 border-t border-black/15 text-label-small"
            >
              <div>
                <p class="text-[#5c501e]">
                  {{ t('CRM.DASHBOARD.DESIGN.TARGET_AMOUNT') }}
                </p>
                <p class="mt-1 font-semibold tabular-nums">
                  {{ target.target }}
                </p>
              </div>
              <div>
                <p class="text-[#5c501e]">
                  {{ t('CRM.DASHBOARD.DESIGN.REMAINING') }}
                </p>
                <p class="mt-1 font-semibold tabular-nums">
                  {{ target.remaining }}
                </p>
              </div>
            </div>
          </template>
          <p v-else class="py-8 text-label text-[#5c501e]">
            {{ t('CRM.DASHBOARD.DESIGN.NO_TARGET') }}
          </p>
        </section>
        <section
          class="order-4 xl:col-span-4 min-w-0 h-[434px] flex flex-col p-6 sm:p-7 rounded-3xl border border-[#e9eae6] bg-white"
        >
          <div class="flex items-center justify-between gap-3 mb-4">
            <h2
              class="text-heading-2 font-semibold tracking-tight text-[#191b1b]"
            >
              {{ t('CRM.DASHBOARD.DESIGN.CUSTOMER_RANK') }}
            </h2>
            <span
              class="text-label-small text-[#85887f] whitespace-nowrap font-inter tabular-nums"
              >{{ periodLabel }}</span
            >
          </div>
          <div
            v-if="!customers.length"
            class="flex-1 grid place-items-center text-label text-[#85887f]"
          >
            {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
          </div>
          <template v-else>
            <button
              class="relative shrink-0 w-full h-[116px] overflow-hidden rounded-2xl bg-[#191b1b] px-4 py-3 text-left group focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#a77800]"
              @click="$emit('customer', customers[0].id)"
            >
              <span
                class="absolute right-2 -bottom-5 text-[108px] font-interDisplay font-semibold leading-none tracking-[-0.09em] text-white/[0.06] pointer-events-none"
                aria-hidden="true"
                >{{ String(1).padStart(2, '0') }}</span
              >
              <div class="relative flex items-center gap-2">
                <span class="h-1.5 w-1.5 rounded-full bg-[#ffd052] shrink-0" />
                <span
                  class="truncate text-heading-3 font-interDisplay font-medium text-white"
                  :title="customers[0].name"
                  >{{ customers[0].name }}</span
                >
              </div>
              <div
                class="relative mt-2 font-interDisplay text-[30px] leading-none font-semibold tracking-[-0.05em] tabular-nums text-[#ffd052]"
              >
                {{ moneyFormat(Math.round(customers[0].amount / 1000000)) }}
              </div>
              <div
                class="relative mt-2 flex justify-between gap-2 text-label-small text-white/60"
              >
                <span
                  >{{ t('CRM.DASHBOARD.DESIGN.ORDERS') }}
                  {{ customers[0].orders }}</span
                >
                <span
                  >{{ t('CRM.DASHBOARD.DESIGN.TOP_FIVE_SHARE') }}
                  <strong class="font-inter font-medium text-white"
                    >{{ customerShare(customers[0]) }}%</strong
                  ></span
                >
              </div>
            </button>
            <div class="flex-1 flex flex-col justify-evenly mt-2 min-h-0">
              <button
                v-for="(customer, i) in customers.slice(1)"
                :key="customer.id"
                class="group flex items-center gap-3 w-full min-w-0 py-2 text-left focus-visible:outline-2 focus-visible:outline-[#a77800]"
                @click="$emit('customer', customer.id)"
              >
                <span
                  class="w-5 shrink-0 font-interDisplay text-[18px] font-light tabular-nums text-[#b7bab0]"
                  >{{ String(i + 2).padStart(2, '0') }}</span
                >
                <div class="min-w-0 flex-1">
                  <div class="flex justify-between items-baseline gap-2">
                    <span
                      class="truncate text-label-small font-interDisplay font-medium text-[#191b1b] group-hover:text-[#9a6c00]"
                      :title="customer.name"
                      >{{ customer.name }}</span
                    >
                    <strong
                      class="font-interDisplay text-[15px] font-semibold tracking-[-0.04em] tabular-nums shrink-0 text-[#191b1b]"
                      >{{
                        moneyFormat(Math.round(customer.amount / 1000000))
                      }}</strong
                    >
                  </div>
                  <svg
                    class="w-full h-1 mt-2"
                    viewBox="0 0 100 4"
                    preserveAspectRatio="none"
                    role="img"
                    :aria-label="`${t('CRM.DASHBOARD.DESIGN.TOP_FIVE_SHARE')} ${customerShare(customer)}%`"
                  >
                    <rect width="100" height="4" rx="2" fill="#f1f2ee" />
                    <rect
                      :width="customerShare(customer)"
                      height="4"
                      rx="2"
                      fill="#d3b65e"
                    />
                  </svg>
                </div>
              </button>
            </div>
          </template>
        </section>
      </div>
    </div>
    <div
      class="grid gap-6 items-start xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]"
    >
      <section v-if="!isMine" class="min-w-0 px-2 py-5">
        <div class="flex items-center justify-between gap-3 mb-5">
          <h2 class="text-heading-2 text-[#191b1b]">
            {{ t('CRM.DASHBOARD.DESIGN.TREND') }}
          </h2>
          <span class="text-label-small text-[#85887f]">{{
            t('CRM.DASHBOARD.DESIGN.ANNUAL_TREND')
          }}</span>
        </div>
        <div v-if="!trend.empty" class="min-w-0 overflow-x-auto pt-2">
          <svg
            viewBox="0 0 648 290"
            class="w-full min-w-[480px]"
            role="img"
            :aria-label="t('CRM.DASHBOARD.DESIGN.TREND')"
          >
            <g
              v-for="(bar, index) in trendBars"
              :key="index"
              class="cursor-pointer"
              role="button"
              tabindex="0"
              :aria-label="`${bar.label}: ${moneyFormat(bar.value)}`"
              @click="selectedMonth = index"
              @keydown.enter="selectedMonth = index"
              @keydown.space.prevent="selectedMonth = index"
            >
              <rect
                :x="bar.x"
                y="64"
                width="42"
                height="184"
                rx="21"
                fill="#f3f4f0"
              />
              <rect
                :x="bar.x"
                :y="248 - bar.height"
                width="42"
                :height="bar.height"
                rx="21"
                :fill="bar.active ? '#ffd052' : '#191b1b'"
              />
              <g v-if="bar.active">
                <rect
                  :x="Math.min(536, Math.max(0, bar.x - 35))"
                  y="10"
                  width="112"
                  height="32"
                  rx="16"
                  fill="#ffd052"
                />
                <path :d="`M ${bar.x + 14} 40 l 7 8 l 7 -8`" fill="#ffd052" />
                <text
                  :x="Math.min(536, Math.max(0, bar.x - 35)) + 56"
                  y="31"
                  text-anchor="middle"
                  fill="#191b1b"
                  font-size="12"
                  font-weight="600"
                >
                  {{ compactYuan(bar.value) }}
                </text>
              </g>
              <text
                :x="bar.x + 21"
                y="275"
                text-anchor="middle"
                fill="#85887f"
                font-size="11"
              >
                {{ bar.label }}
              </text>
            </g>
          </svg>
        </div>
        <div
          v-else
          class="grid h-56 text-label text-[#85887f] place-items-center"
        >
          {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
        </div>
      </section>
      <section v-else class="p-6 bg-white border rounded-2xl border-[#e9eae6]">
        <h2 class="text-heading-2">
          {{ t('CRM.DASHBOARD.DESIGN.PRIVATE_CUSTOMERS') }}
        </h2>
        <div class="flex items-baseline gap-2 mt-5">
          <strong class="text-4xl tabular-nums">{{ privateCustomers }}</strong
          ><span class="text-label text-[#85887f]">{{
            t('CRM.DASHBOARD.DESIGN.CUSTOMERS_UNIT')
          }}</span>
        </div>
        <div
          v-if="privateCompleteness != null"
          class="flex items-center justify-between pt-4 mt-5 border-t border-[#e9eae6] text-label"
        >
          <span>{{ t('CRM.DASHBOARD.DESIGN.COMPLETENESS') }}</span
          ><strong>{{
            t('CRM.DASHBOARD.DESIGN.SCORE', { score: privateCompleteness })
          }}</strong>
        </div>
      </section>
      <section class="min-w-0 p-6 bg-white border border-[#e9eae6] rounded-3xl">
        <h2 class="mb-4 text-heading-2 text-[#191b1b]">
          {{ t('CRM.DASHBOARD.DESIGN.SOURCES') }}
        </h2>
        <div v-if="!sources.empty" class="flex flex-wrap items-center gap-6">
          <div class="relative h-48 w-48 shrink-0">
            <CrmDoughnutChart
              :labels="sources.labels"
              :data="sources.data"
              :colors="sourceColors"
              cutout="65%"
              continuous
            >
              <template #center>
                <strong
                  class="font-interDisplay text-[32px] font-semibold tracking-[-0.06em] leading-none tabular-nums"
                  >{{ sources.total }}</strong
                ><span class="mt-1.5 text-label-small text-[#96998f]">{{
                  t('CRM.DASHBOARD.DESIGN.SOURCE_TOTAL')
                }}</span>
              </template>
            </CrmDoughnutChart>
          </div>
          <div class="flex flex-col gap-3 flex-1 min-w-[10rem] pr-4">
            <div
              v-for="(source, i) in sources.labels"
              :key="source"
              class="flex items-center gap-2 min-w-0 text-label-small"
            >
              <svg width="7" height="7" class="shrink-0" aria-hidden="true">
                <circle
                  cx="3.5"
                  cy="3.5"
                  r="3.5"
                  :fill="sourceColors[i % sourceColors.length]"
                /></svg
              ><span class="flex-1 truncate text-[#585c52]" :title="source">{{
                source
              }}</span
              ><strong class="w-8 shrink-0 tabular-nums"
                >{{ sourceShare(i) }}%</strong
              >
            </div>
          </div>
        </div>
        <div
          v-else
          class="grid h-56 text-label text-[#85887f] place-items-center"
        >
          {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
        </div>
      </section>
    </div>
    <div
      class="grid items-start gap-8 xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)] xl:gap-10"
    >
      <div class="w-full min-w-0">
        <CrmSentEmailRankChart
          v-if="!isMine"
          :rows="emailRows"
          :period-label="periodLabel"
        />
      </div>
      <section class="min-w-0 px-2 py-5">
        <div class="flex flex-wrap items-center justify-between gap-2 mb-5">
          <h2 class="text-heading-2 text-[#191b1b]">
            {{ t('CRM.DASHBOARD.DESIGN.PIPELINE') }}
          </h2>
          <span
            v-if="winRate != null"
            class="flex items-center gap-1 text-label-small text-[#85887f]"
            >{{ t('CRM.DASHBOARD.DESIGN.WIN_RATE') }}
            <strong class="text-[#191b1b]">{{ winRate }}%</strong></span
          >
        </div>
        <div v-if="!stages.length" class="py-8 text-label text-[#85887f]">
          {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
        </div>
        <div v-for="stage in stages" :key="stage.label" class="mb-4 last:mb-0">
          <div
            class="flex items-center justify-between gap-3 mb-2 text-label-small"
          >
            <span>{{ stage.label }}</span
            ><strong class="tabular-nums">{{ stage.amount }}</strong>
          </div>
          <svg
            class="w-full h-7"
            viewBox="0 0 400 28"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect width="400" height="28" rx="9" fill="#f3f4f0" />
            <rect
              :width="stage.pct * 4"
              height="28"
              rx="9"
              :fill="stage.won ? '#ffd052' : '#191b1b'"
            />
          </svg>
        </div>
      </section>
    </div>
    <div class="flex flex-wrap items-start gap-6">
      <section
        v-if="!isMine"
        class="w-full max-w-[38rem] min-w-0 p-6 sm:p-7 bg-[#f6f7f3] rounded-3xl"
      >
        <h2 class="mb-5 text-heading-2 text-[#191b1b]">
          {{ t('CRM.DASHBOARD.DESIGN.TEAM_COMPLETENESS') }}
        </h2>
        <div v-if="!completeness.length" class="py-8 text-label text-[#85887f]">
          {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
        </div>
        <div class="grid sm:grid-cols-2 gap-x-8 max-h-72 overflow-y-auto pr-1">
          <div
            v-for="person in completeness"
            :key="person.name"
            class="flex items-center gap-3 py-3 border-b border-[#f0f1ed] last:border-0"
          >
            <span
              class="grid size-7 rounded-full bg-[#f1f2ef] text-label-small place-items-center"
              >{{ initials(person.name) }}</span
            ><span class="text-label-small">{{ person.name }}</span
            ><strong class="ml-auto text-label-small tabular-nums">{{
              person.value
            }}</strong>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
