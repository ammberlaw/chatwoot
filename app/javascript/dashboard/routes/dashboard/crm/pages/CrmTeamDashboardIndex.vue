<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmKpiCard from 'dashboard/components-next/CRM/CrmKpiCard.vue';
import { usesClassicContentColors } from 'dashboard/components-next/CRM/charts/chartColors';
import { useThemeSignal } from 'dashboard/components-next/CRM/charts/useThemeSignal';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import CrmSentEmailRankChart from 'dashboard/components-next/CRM/CrmSentEmailRankChart.vue';

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

// 长春花紫色系柔和渐变（跨卡 紫→靛→蓝，无绿）。完整字面量供 Tailwind 收录。
const CARD_GRADIENTS = [
  'from-n-iris-3 to-n-iris-5',
  'from-n-iris-4 to-n-blue-4',
  'from-n-blue-3 to-n-iris-5',
];

// ── 经典灰：带环比和走势的 KPI 卡；其余主题保持原来的渐变卡不动 ──
const themeSignal = useThemeSignal();
const isClassicKpi = computed(() => {
  void themeSignal.value;
  return usesClassicContentColors();
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

// 本月/上月的团队合计完成率，用来给「目标完成率」那张卡算 pt 差
const ratio = row => {
  const target = Number(row.target_amount_micros || 0);
  return target > 0 ? (Number(row.amount_micros || 0) / target) * 100 : null;
};

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

// 完成率那张卡不套 KPI 卡的骨架：大弧包着数字，底下挂实绩/目标
const GAUGE_PATH = 'M12,80 A68,68 0 0 1 148,80';
const GAUGE_LEN = Math.PI * 68;
const gaugePct = computed(() => ratio(monthRow(selectedMonth.value)));
const gaugeDash = computed(() => {
  const done = Math.min(100, Math.max(0, gaugePct.value || 0));
  return `${((done / 100) * GAUGE_LEN).toFixed(2)} ${GAUGE_LEN.toFixed(2)}`;
});
const gaugeText = computed(() =>
  gaugePct.value === null ? '—' : `${Math.round(gaugePct.value)}%`
);

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
</script>

<template>
  <div
    class="flex flex-col w-full h-full gap-4 px-4 py-4 sm:p-6 overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
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
      <!-- KPI -->
      <div class="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">
        <!-- 经典灰：带环比和走势的卡（见 CrmKpiCard） -->
        <template v-if="isClassicKpi">
          <CrmKpiCard
            v-for="kpi in classicKpis"
            :key="`c-${kpi.label}`"
            :label="kpi.label"
            :value="kpi.value"
            :unit="kpi.unit"
            :icon="kpi.icon"
            :delta="kpi.delta"
            :viz="kpi.viz"
          />
          <div
            class="flex flex-col p-4 sm:p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
          >
            <h3 class="text-heading-3 text-n-slate-12">目标完成率</h3>
            <div class="flex flex-col items-center justify-center flex-1 mt-2">
              <div class="relative">
                <svg
                  width="160"
                  height="92"
                  viewBox="0 0 160 92"
                  class="block max-w-full"
                  aria-hidden="true"
                >
                  <path
                    :d="GAUGE_PATH"
                    fill="none"
                    stroke-width="16"
                    stroke-linecap="round"
                    class="stroke-n-slate-4"
                  />
                  <path
                    :d="GAUGE_PATH"
                    fill="none"
                    stroke-width="16"
                    stroke-linecap="round"
                    :stroke-dasharray="gaugeDash"
                    class="stroke-n-amber-9"
                  />
                </svg>
                <div
                  class="absolute inset-x-0 text-2xl font-bold text-center bottom-5 tabular-nums text-n-slate-12"
                >
                  {{ gaugeText }}
                </div>
              </div>
              <div class="mt-1 text-label-small text-n-slate-10">
                <span class="font-semibold text-n-slate-12">
                  {{ money(totals.actualAmount) }}
                </span>
                / {{ money(totals.targetAmount) }}
              </div>
            </div>
          </div>
        </template>
        <!-- 其余主题：暖橙浅渐变卡 -->
        <template v-else>
          <div
            v-for="(kpi, i) in kpiCards"
            :key="kpi.label"
            class="flex flex-col justify-between p-5 shadow-sm rounded-2xl bg-gradient-to-br min-h-[8rem]"
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
        </template>
      </div>

      <!-- 组员完成率：成交额 / 新客各一张表 -->
      <div
        v-if="!team.members.length"
        class="p-5 text-sm border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150 text-n-slate-11"
      >
        该团队暂无组员。可在「组织架构 → CRM 团队」分配组员。
      </div>
      <div v-else class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div
          v-for="table in memberTables"
          :key="table.key"
          class="overflow-hidden border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
        >
          <div class="p-5 pb-4">
            <h2 class="text-heading-2 text-n-slate-12">{{ table.title }}</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full min-w-[32rem]">
              <thead>
                <tr class="border-y border-n-weak bg-n-alpha-1">
                  <th
                    class="px-5 py-2 text-left text-label-small text-n-slate-10 whitespace-nowrap"
                  >
                    组员
                  </th>
                  <th
                    class="px-3 py-2 text-right text-label-small text-n-slate-10 whitespace-nowrap"
                  >
                    {{ table.valueHead }}
                  </th>
                  <th
                    class="px-3 py-2 text-right text-label-small text-n-slate-10 whitespace-nowrap"
                  >
                    目标
                  </th>
                  <th
                    class="px-3 py-2 text-left text-label-small text-n-slate-10 whitespace-nowrap"
                  >
                    完成率
                  </th>
                  <th
                    class="px-5 py-2 text-right text-label-small text-n-slate-10 whitespace-nowrap"
                  >
                    较上月
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in table.rows"
                  :key="row.id"
                  class="border-b border-n-weak last:border-b-0"
                >
                  <td class="px-5 py-3">
                    <div class="flex items-center gap-2.5">
                      <span
                        class="grid border rounded-full size-7 shrink-0 place-items-center text-label-small border-n-weak bg-n-alpha-1 text-n-slate-11"
                      >
                        {{ row.initials }}
                      </span>
                      <span class="text-sm truncate text-n-slate-12">
                        {{ row.name }}
                      </span>
                    </div>
                  </td>
                  <td
                    class="px-3 py-3 text-sm text-right whitespace-nowrap tabular-nums text-n-slate-12"
                  >
                    {{ row.actual }}
                  </td>
                  <td
                    class="px-3 py-3 text-sm text-right whitespace-nowrap tabular-nums text-n-slate-11"
                  >
                    {{ row.target }}
                  </td>
                  <td class="px-3 py-3">
                    <div class="flex items-center gap-2.5 min-w-[7.5rem]">
                      <span
                        class="flex-1 h-1.5 overflow-hidden rounded-full bg-n-slate-4"
                      >
                        <span
                          class="block h-full rounded-full"
                          :class="row.status?.bar || 'bg-n-slate-6'"
                          :style="{ width: row.barWidth }"
                        />
                      </span>
                      <span
                        class="w-9 text-sm font-semibold text-right tabular-nums text-n-slate-12"
                      >
                        {{ row.pctText }}
                      </span>
                    </div>
                  </td>
                  <td class="px-5 py-3 text-right whitespace-nowrap">
                    <span
                      class="font-semibold text-label-small tabular-nums"
                      :class="deltaTone(row.deltaPt)"
                    >
                      {{ deltaText(row.deltaPt) }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- 发信排行：全公司口径，和团队下拉无关，所以放在团队块外面单独一张 -->
      <CrmSentEmailRankChart
        :rows="sentEmailRanking"
        :period-label="`${data?.month_label || ''} · 全公司`"
        empty-text="本月还没有发出去的邮件"
      />
    </template>
  </div>
</template>
