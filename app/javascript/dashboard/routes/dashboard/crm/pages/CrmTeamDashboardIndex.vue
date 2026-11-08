<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmBlackSalesTrend from 'dashboard/components-next/CRM/charts/CrmBlackSalesTrend.vue';
import CrmAreaChart from 'dashboard/components-next/CRM/charts/CrmAreaChart.vue';
import { usesClassicContentColors } from 'dashboard/components-next/CRM/charts/chartColors';
import { useThemeSignal } from 'dashboard/components-next/CRM/charts/useThemeSignal';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const { accountId } = useAccount();

const data = ref(null);
const loading = ref(true);
const selectedTeamId = ref(null);

// 月份/年份筛选：默认当月，切换后重新拉取该月团队实绩与目标。
const now = new Date();
const selectedYear = ref(now.getFullYear());
const selectedMonth = ref(now.getMonth() + 1);

// 年+月合成一个紫玻璃 MonthPicker（值 'YYYY-MM'）；团队用 SelectCard（见 teams 之后）。
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

// 默认选哪个队：上次看的 > 自己所属的队 > 列表第一个。
// 后端按名称排序，「1688」这种数字队名永远排最前，只取第一个的话
// 管理员每次打开都是它，每次都得手动再切一遍。
const defaultTeamId = payload => {
  const ids = payload.teams.map(x => x.id);
  const last = LocalStorage.get(LOCAL_STORAGE_KEYS.CRM_TEAM_DASHBOARD_TEAM);
  if (ids.includes(last)) return last;
  if (ids.includes(payload.current_team_id)) return payload.current_team_id;
  return ids[0];
};

const fetchData = async () => {
  loading.value = true;
  try {
    const { data: payload } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/team_dashboard`,
      { params: { year: selectedYear.value, month: selectedMonth.value } }
    );
    data.value = payload;
    if (payload.teams.length && selectedTeamId.value == null) {
      selectedTeamId.value = defaultTeamId(payload);
    }
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);
watch([selectedYear, selectedMonth], fetchData);
// 记住这次看的队，下次打开直接落在同一个队。
watch(selectedTeamId, id => {
  if (id != null)
    LocalStorage.set(LOCAL_STORAGE_KEYS.CRM_TEAM_DASHBOARD_TEAM, id);
});

const money = micros =>
  `¥${Math.round((micros || 0) / 1_000_000).toLocaleString()}`;

const teams = computed(() => data.value?.teams || []);
// 业务员发信排行：**全公司口径**（不随上面选的团队变），跟 CRM 数据看板共用同一张图。
// 这张榜就是要横向比全公司谁跑得勤，只给本队成员看不出高低。
const sentEmailRanking = computed(() => data.value?.sent_email_ranking || []);
const teamSelectOptions = computed(() =>
  teams.value.map(x => ({ value: x.id, label: x.name }))
);
const team = computed(
  () => teams.value.find(x => x.id === selectedTeamId.value) || teams.value[0]
);

const totals = computed(() => {
  const m = team.value?.members || [];
  // 金额字段后端由 SUM(numeric) 返回，JSON 里是字符串，直接 + 会字符串拼接导致 ¥NaN；统一 Number() 相加。
  return {
    actualAmount: m.reduce(
      (s, r) => s + Number(r.actual_amount_micros || 0),
      0
    ),
    actualCount: m.reduce((s, r) => s + Number(r.actual_count || 0), 0),
    targetAmount: m.reduce(
      (s, r) => s + Number(r.target_amount_micros || 0),
      0
    ),
    targetCount: m.reduce((s, r) => s + Number(r.target_count || 0), 0),
    memberCount: m.length,
  };
});

const themeSignal = useThemeSignal();
const isClassicKpi = computed(
  () => themeSignal.value >= 0 && usesClassicContentColors()
);
const isClassicBlack = computed(
  () =>
    themeSignal.value >= 0 && document.body.classList.contains('theme-classic')
);
const blackTeamPct = computed(() =>
  totals.value.targetAmount > 0
    ? (totals.value.actualAmount / totals.value.targetAmount) * 100
    : null
);
const blackEmailBars = computed(() => {
  const rows = sentEmailRanking.value.filter(row => Number(row.count) > 0);
  const max = Math.max(...rows.map(row => Number(row.count)), 1);
  return rows.map(row => ({ ...row, pct: (Number(row.count) / max) * 100 }));
});

// 后端给的本年逐月团队合计，用来算环比、画走势
const monthly = computed(() => team.value?.monthly || []);
const monthRow = m => monthly.value[m - 1] || { amount_micros: 0, count: 0 };

// 走势只画到所选月份为止——把还没发生的月份画成 0 会看着像断崖
const series = key =>
  monthly.value.slice(0, selectedMonth.value).map(r => Number(r?.[key] || 0));

// 环比那行要和走势图挤在一张窄卡里，完整金额会被截断，参照值缩写成万/亿
const compactMoney = micros => {
  const yuan = Math.round((micros || 0) / 1_000_000);
  const abs = Math.abs(yuan);
  if (abs >= 100000000) return `¥${(yuan / 100000000).toFixed(2)}亿`;
  if (abs >= 10000) return `¥${(yuan / 10000).toFixed(1)}万`;
  return `¥${yuan.toLocaleString()}`;
};

const makeDelta = (key, { money: isMoney = false, fmt = v => v } = {}) => {
  if (selectedMonth.value <= 1 || !monthly.value.length) return null;
  const cur = Number(monthRow(selectedMonth.value)[key] || 0);
  const was = Number(monthRow(selectedMonth.value - 1)[key] || 0);
  if (cur === was)
    return { text: '持平', dir: 'flat', vs: `较上月 ${fmt(was)}` };
  const diff = Math.abs(cur - was);
  const sign = cur > was ? '+' : '−';
  let text = `${sign}${diff}`;
  if (isMoney) {
    // 上月是 0 时算不出百分比，直接报差额
    text =
      was === 0
        ? `${sign}${fmt(diff)}`
        : `${sign}${((diff / was) * 100).toFixed(1)}%`;
  }
  return { text, dir: cur > was ? 'up' : 'down', vs: `较上月 ${fmt(was)}` };
};

// 保留各主题原有的完成率口径：经典黑取成员合计，其余取月度汇总。
const ratio = row => {
  const target = Number(row.target_amount_micros || 0);
  return target > 0 ? (Number(row.amount_micros || 0) / target) * 100 : null;
};
const gaugePct = computed(() => ratio(monthRow(selectedMonth.value)));
const completionPct = computed(() =>
  isClassicBlack.value ? blackTeamPct.value : gaugePct.value
);

// 组员按完成率分三档：达标 ≥80%、进行中 50–79%、其余落后（没设目标的不计）
const memberBuckets = computed(() => {
  const rows = (team.value?.members || []).filter(
    m => Number(m.target_amount_micros) > 0
  );
  const pcts = rows.map(
    m => (Number(m.actual_amount_micros) / Number(m.target_amount_micros)) * 100
  );
  return {
    good: pcts.filter(x => x >= 80).length,
    warn: pcts.filter(x => x >= 50 && x < 80).length,
    crit: pcts.filter(x => x < 50).length,
  };
});

const classicKpis = computed(() => {
  const cur = monthRow(selectedMonth.value);
  const prev =
    selectedMonth.value > 1 ? monthRow(selectedMonth.value - 1) : null;

  const achievedNow = Number(cur.achieved_members || 0);
  const achievedWas = prev ? Number(prev.achieved_members || 0) : null;
  let achievedDelta = null;
  if (achievedWas !== null) {
    const diff = achievedNow - achievedWas;
    achievedDelta =
      diff === 0
        ? { text: '持平', dir: 'flat', vs: `上月也是 ${achievedWas} 人` }
        : {
            text: `${diff > 0 ? '+' : '−'}${Math.abs(diff)}`,
            dir: diff > 0 ? 'up' : 'down',
            vs: `较上月 ${achievedWas} 人`,
          };
  }

  const b = memberBuckets.value;
  return [
    {
      label: '团队成交额',
      value: money(totals.value.actualAmount),
      icon: 'i-lucide-banknote',
      delta: makeDelta('amount_micros', { money: true, fmt: compactMoney }),
      viz: { type: 'line', series: series('amount_micros') },
    },
    {
      // 新客逐月多半是个位数甚至 0，跟上月比没什么信息量，参照值给当月目标
      label: '新成交客户',
      value: totals.value.actualCount,
      unit: '家',
      icon: 'i-lucide-user-plus',
      delta: (d => d && { ...d, vs: `目标 ${totals.value.targetCount} 家` })(
        makeDelta('count')
      ),
      viz: { type: 'bars', series: series('count') },
    },
    {
      label: '组员达标',
      value: achievedNow,
      unit: `/ ${totals.value.memberCount} 人`,
      icon: 'i-lucide-users',
      delta: achievedDelta,
      viz: {
        type: 'split',
        rows: [
          { label: '达标', value: b.good, tone: 'good' },
          { label: '进行中', value: b.warn, tone: 'warn' },
          { label: '落后', value: b.crit, tone: 'crit' },
        ],
      },
    },
  ];
});

// ── 组员完成率：成交额 / 新成交客户各一张表 ──
// 分档口径和上面「组员达标」那张卡一致：达标 ≥80%、进行中 50–79%、其余落后。
const STATUS_STEPS = [
  {
    min: 80,
    label: '达标',
    tone: 'good',
    bar: 'bg-n-teal-9',
    pill: 'bg-n-teal-3 text-n-teal-11',
    dot: 'bg-n-teal-9',
  },
  {
    min: 50,
    label: '进行中',
    tone: 'warn',
    bar: 'bg-n-slate-11',
    pill: 'bg-n-amber-3 text-n-amber-11',
    dot: 'bg-n-amber-9',
  },
  {
    min: 0,
    label: '落后',
    tone: 'crit',
    bar: 'bg-n-slate-8',
    pill: 'bg-n-ruby-3 text-n-ruby-11',
    dot: 'bg-n-ruby-9',
  },
];
// 「较上月」那一格：没有上月数据时显示 —，省得模板里再套一层 v-else
const deltaText = pt => {
  if (pt === null) return '—';
  if (pt === 0) return '0pt';
  return `${pt > 0 ? '+' : '−'}${Math.abs(pt)}pt`;
};
const deltaTone = pt => {
  if (pt === null || pt === 0) return 'text-n-slate-10';
  return pt > 0 ? 'text-n-teal-11' : 'text-n-ruby-11';
};

const statusOf = pct =>
  STATUS_STEPS.find(s => pct >= s.min) || STATUS_STEPS.at(-1);

const initialsOf = name =>
  (name || '?')
    .split(/\s+/)
    .map(w => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

const buildRows = ({
  actualKey,
  targetKey,
  prevActualKey,
  prevTargetKey,
  fmt,
}) =>
  (team.value?.members || [])
    .map(m => {
      const target = Number(m[targetKey] || 0);
      const pct =
        target > 0 ? (Number(m[actualKey] || 0) / target) * 100 : null;
      const prevTarget = Number(m[prevTargetKey] || 0);
      const prevPct =
        m[prevTargetKey] == null || prevTarget === 0
          ? null
          : (Number(m[prevActualKey] || 0) / prevTarget) * 100;
      const status = pct === null ? null : statusOf(pct);
      return {
        id: m.id,
        name: m.name,
        initials: initialsOf(m.name),
        actual: fmt(m[actualKey]),
        target: fmt(m[targetKey]),
        pct,
        pctText: pct === null ? '—' : `${Math.round(pct)}%`,
        barWidth: `${Math.min(100, Math.max(2, pct ?? 0))}%`,
        status,
        deltaPt:
          pct === null || prevPct === null ? null : Math.round(pct - prevPct),
      };
    })
    .sort((a, b) => (b.pct ?? -1) - (a.pct ?? -1));

const memberTables = computed(() => [
  {
    key: 'amount',
    title: '成交额完成率',
    valueHead: '成交额',
    rows: buildRows({
      actualKey: 'actual_amount_micros',
      targetKey: 'target_amount_micros',
      prevActualKey: 'prev_amount_micros',
      prevTargetKey: 'prev_target_amount_micros',
      fmt: money,
    }),
  },
  {
    key: 'count',
    title: '新成交客户完成率',
    valueHead: '新客',
    rows: buildRows({
      actualKey: 'actual_count',
      targetKey: 'target_count',
      prevActualKey: 'prev_count',
      prevTargetKey: 'prev_target_count',
      fmt: v => `${Math.round(Number(v) || 0)} 家`,
    }),
  },
]);

// KPI 顶卡
const kpiCards = computed(() => [
  {
    label: '成交额',
    value: money(totals.value.actualAmount),
    sub: `目标 ${money(totals.value.targetAmount)}`,
    icon: 'i-lucide-banknote',
  },
  {
    label: '新成交客户',
    value: totals.value.actualCount,
    sub: `目标 ${totals.value.targetCount}`,
    icon: 'i-lucide-user-plus',
  },
  {
    label: '组员人数',
    value: totals.value.memberCount,
    sub: '人',
    icon: 'i-lucide-users',
  },
]);
const overviewCards = computed(() => [
  { ...kpiCards.value[0], delta: classicKpis.value[0].delta },
  kpiCards.value[1],
  { ...classicKpis.value[2], sub: classicKpis.value[2].unit },
]);
const overviewTones = ['bg-n-iris-3', 'bg-n-iris-4', 'bg-n-blue-3'];
const memberHeaders = computed(() => [
  '组员',
  '目标',
  '完成率',
  t('CRM.TEAM_DASHBOARD.ROW_DELTA'),
]);
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full gap-4 px-4 py-4 sm:p-6 overflow-auto backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
    :class="
      isClassicBlack &&
      '!gap-6 !bg-white !border-[#e9eae6] !shadow-none !backdrop-blur-none !p-6'
    "
  >
    <div
      class="flex flex-wrap items-center justify-between gap-3 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center"
    >
      <div>
        <h1 class="text-n-slate-12 text-heading-1">
          {{ t('CRM.TEAM_DASHBOARD.HEADER') }}
        </h1>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <MonthPicker
          v-model="monthModel"
          align="right"
          trigger-class="w-36 h-9"
          :clearable="false"
        />
        <SelectCard
          v-if="teams.length"
          v-model="selectedTeamId"
          :options="teamSelectOptions"
          align="right"
          trigger-class="w-32"
        />
      </div>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.TEAM_DASHBOARD.LOADING') }}
    </div>

    <div
      v-else-if="!teams.length"
      class="p-8 text-sm text-center border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150 text-n-slate-11"
    >
      {{ t('CRM.TEAM_DASHBOARD.EMPTY') }}
    </div>

    <template v-else-if="team">
      <div class="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <section
          v-for="(kpi, index) in overviewCards"
          :key="kpi.label"
          class="min-w-0 rounded-2xl border border-n-weak p-5"
          :class="
            isClassicBlack
              ? 'bg-[#f5f6f2] [.theme-porcelain_&]:bg-n-solid-1'
              : isClassicKpi
                ? 'bg-n-solid-1'
                : overviewTones[index]
          "
        >
          <h2 class="text-heading-3 text-n-slate-11">{{ kpi.label }}</h2>
          <div class="mt-3 flex flex-wrap items-baseline gap-2">
            <strong
              class="text-3xl font-semibold tabular-nums text-n-slate-12"
              >{{ kpi.value }}</strong
            >
            <span v-if="kpi.unit" class="text-label-small text-n-slate-11">{{
              kpi.unit
            }}</span>
          </div>
          <div
            class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-label-small text-n-slate-11"
          >
            <strong
              v-if="kpi.delta"
              :class="
                kpi.delta.dir === 'up'
                  ? 'text-n-teal-11'
                  : kpi.delta.dir === 'down'
                    ? 'text-n-ruby-11'
                    : ''
              "
              >{{ kpi.delta.text }}</strong
            >
            <span>{{
              kpi.delta?.vs ||
              (!kpi.unit ? kpi.sub : kpiCards[2].value + ' ' + kpiCards[2].sub)
            }}</span>
          </div>
        </section>
        <section
          class="min-w-0 rounded-2xl border p-5"
          :class="
            isClassicBlack
              ? 'border-transparent bg-[#ffd052] text-[#191b1b] [.theme-porcelain_&]:border-n-weak [.theme-porcelain_&]:bg-n-solid-1'
              : 'border-n-iris-5 bg-n-iris-3 text-n-slate-12'
          "
        >
          <h2 class="text-heading-3">
            {{ t('CRM.DASHBOARD.DESIGN.ACHIEVED') }}
          </h2>
          <strong class="mt-3 block text-3xl font-semibold tabular-nums">{{
            completionPct === null ? '—' : `${Math.round(completionPct)}%`
          }}</strong>
          <svg
            class="my-3 h-1.5 w-full"
            viewBox="0 0 100 6"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect
              width="100"
              height="6"
              rx="3"
              class="fill-current opacity-10"
            />
            <rect
              :width="Math.min(100, Math.max(0, completionPct || 0))"
              height="6"
              rx="3"
              class="fill-current"
            />
          </svg>
          <p class="text-label-small">
            {{
              t('CRM.TEAM_DASHBOARD.ROW_TARGET', {
                target: money(totals.targetAmount),
              })
            }}
          </p>
        </section>
      </div>

      <div class="grid items-start gap-4 xl:grid-cols-2">
        <section
          v-for="table in memberTables"
          :key="table.key"
          class="min-w-0 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1"
        >
          <div class="flex items-baseline justify-between gap-3 p-5 pb-4">
            <h2 class="text-heading-2 font-semibold text-n-slate-12">
              {{ table.title }}
            </h2>
            <span class="text-label-small text-n-slate-11"
              >{{ totals.memberCount }} {{ kpiCards[2].sub }}</span
            >
          </div>
          <p
            v-if="!table.rows.length"
            class="px-5 pb-5 text-label text-n-slate-11"
          >
            {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
          </p>
          <div v-else class="max-h-96 overflow-auto">
            <table class="w-full min-w-[32rem] text-label-small tabular-nums">
              <thead
                class="sticky top-0 border-y border-n-weak bg-n-slate-2 text-n-slate-11"
              >
                <tr>
                  <th class="px-5 py-2 text-left font-medium">
                    {{ memberHeaders[0] }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ table.valueHead }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ memberHeaders[1] }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ memberHeaders[2] }}
                  </th>
                  <th class="px-5 py-2 text-right font-medium">
                    {{ memberHeaders[3] }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="(row, index) in table.rows"
                  :key="row.id"
                  class="text-n-slate-12 hover:bg-n-slate-2"
                >
                  <td class="px-5 py-3">
                    <div class="flex items-center gap-3">
                      <span class="w-4 shrink-0 text-n-slate-10">{{
                        String(index + 1).padStart(2, '0')
                      }}</span>
                      <span
                        class="max-w-40 truncate text-label"
                        :title="row.name"
                        >{{ row.name }}</span
                      >
                    </div>
                  </td>
                  <td
                    class="whitespace-nowrap px-3 py-3 text-right font-semibold"
                  >
                    {{ row.actual }}
                  </td>
                  <td
                    class="whitespace-nowrap px-3 py-3 text-right text-n-slate-11"
                  >
                    {{ row.target }}
                  </td>
                  <td class="px-3 py-3 text-right">
                    <span
                      class="inline-flex rounded-md px-2 py-1"
                      :class="row.status?.pill || 'text-n-slate-11'"
                      >{{ row.pctText }}</span
                    >
                  </td>
                  <td
                    class="whitespace-nowrap px-5 py-3 text-right"
                    :class="deltaTone(row.deltaPt)"
                  >
                    {{ deltaText(row.deltaPt) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <div
        class="grid items-start gap-4 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]"
      >
        <section
          class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
        >
          <h2 class="mb-4 text-heading-2 font-semibold text-n-slate-12">
            {{ t('CRM.DASHBOARD.DESIGN.TREND') }}
          </h2>
          <CrmBlackSalesTrend
            v-if="monthly.length && isClassicKpi"
            :labels="
              monthly
                .slice(0, selectedMonth)
                .map((row, index) =>
                  t('CRM.TEAM_DASHBOARD.MONTH', { month: index + 1 })
                )
            "
            :data="series('amount_micros').map(value => value / 1000000)"
            :value-format="value => compactMoney(value * 1000000)"
          />
          <div v-else-if="monthly.length" class="h-60">
            <CrmAreaChart
              :labels="
                monthly
                  .slice(0, selectedMonth)
                  .map((row, index) =>
                    t('CRM.TEAM_DASHBOARD.MONTH', { month: index + 1 })
                  )
              "
              :data="series('amount_micros')"
              :value-format="compactMoney"
            />
          </div>
          <p v-else class="py-12 text-center text-label text-n-slate-11">
            {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
          </p>
        </section>
        <section
          class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-heading-2 font-semibold text-n-slate-12">
              {{ t('CRM.DASHBOARD.DESIGN.EMAIL_RANK') }}
            </h2>
            <span class="text-label-small text-n-slate-11">{{
              t('CRM.TEAM_DASHBOARD.ALL_COMPANY')
            }}</span>
          </div>
          <p
            v-if="!blackEmailBars.length"
            class="py-8 text-label text-n-slate-11"
          >
            {{ t('CRM.DASHBOARD.DESIGN.NO_SENT_EMAIL') }}
          </p>
          <ol
            v-else
            class="mt-4 max-h-80 list-none overflow-y-auto divide-y divide-n-weak"
          >
            <li
              v-for="(row, index) in blackEmailBars"
              :key="row.id || row.name"
              class="flex items-center gap-3 py-3 first:pt-0 last:pb-0"
            >
              <span
                class="w-5 shrink-0 text-label-small tabular-nums text-n-slate-10"
                >{{ String(index + 1).padStart(2, '0') }}</span
              >
              <div class="min-w-0 flex-1">
                <div
                  class="flex justify-between gap-3 text-label text-n-slate-12"
                >
                  <span class="truncate" :title="row.name">{{ row.name }}</span>
                  <strong class="shrink-0 tabular-nums">{{
                    t('CRM.DASHBOARD.DESIGN.EMAIL_COUNT', { count: row.count })
                  }}</strong>
                </div>
                <svg
                  class="mt-2 h-1 w-full"
                  viewBox="0 0 100 4"
                  preserveAspectRatio="none"
                  aria-hidden="true"
                >
                  <rect width="100" height="4" rx="2" class="fill-n-slate-3" />
                  <rect
                    :width="row.pct"
                    height="4"
                    rx="2"
                    :class="isClassicKpi ? 'fill-[#ffd052]' : 'fill-n-iris-9'"
                  />
                </svg>
              </div>
            </li>
          </ol>
        </section>
      </div>
    </template>
  </div>
</template>
