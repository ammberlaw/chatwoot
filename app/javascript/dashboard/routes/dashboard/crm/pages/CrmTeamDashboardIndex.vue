<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmDoughnutChart from 'dashboard/components-next/CRM/charts/CrmDoughnutChart.vue';

const { t } = useI18n();
const { accountId } = useAccount();

const data = ref(null);
const loading = ref(true);
const selectedTeamId = ref(null);

const fetchData = async () => {
  loading.value = true;
  try {
    const { data: payload } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/team_dashboard`
    );
    data.value = payload;
    if (payload.teams.length && selectedTeamId.value == null) {
      selectedTeamId.value = payload.teams[0].id;
    }
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

const money = micros =>
  `¥${Math.round((micros || 0) / 1_000_000).toLocaleString()}`;

const teams = computed(() => data.value?.teams || []);
const team = computed(
  () => teams.value.find(x => x.id === selectedTeamId.value) || teams.value[0]
);

const totals = computed(() => {
  const m = team.value?.members || [];
  return {
    actualAmount: m.reduce((s, r) => s + r.actual_amount_micros, 0),
    actualCount: m.reduce((s, r) => s + r.actual_count, 0),
    targetAmount: m.reduce((s, r) => s + r.target_amount_micros, 0),
    targetCount: m.reduce((s, r) => s + r.target_count, 0),
    memberCount: m.length,
  };
});

const pct = (actual, target) => (target > 0 ? (actual / target) * 100 : null);

// 完成率配色：达标绿 / 良好蓝 / 偏低橙 / 落后红 / 无目标灰
const barClass = p => {
  if (p == null) return 'bg-n-slate-6';
  if (p >= 100) return 'bg-n-teal-9';
  if (p >= 60) return 'bg-n-blue-9';
  if (p >= 30) return 'bg-n-iris-9';
  return 'bg-n-ruby-9';
};
const barWidth = p => `${Math.min(100, Math.max(2, p ?? 0))}%`;

const completionPct = computed(() =>
  totals.value.targetAmount > 0
    ? Math.round((totals.value.actualAmount / totals.value.targetAmount) * 100)
    : null
);

// 单条指标：实绩/目标 + 百分比
const metricLine = (actual, target, isMoney) => {
  const p = pct(actual, target);
  const fmt = n => (isMoney ? money(n) : String(Math.round(n)));
  return {
    p,
    barClass: barClass(p),
    barWidth: barWidth(p),
    text: `${fmt(actual)} / ${fmt(target)}${p == null ? '' : `（${Math.round(p)}%）`}`,
  };
};

// 长春花紫色系柔和渐变（跨卡 紫→靛→蓝，无绿）。完整字面量供 Tailwind 收录。
const CARD_GRADIENTS = [
  'from-n-iris-3 to-n-iris-5',
  'from-n-iris-4 to-n-blue-4',
  'from-n-blue-3 to-n-iris-5',
];

// KPI 顶卡
const kpiCards = computed(() => [
  {
    label: '本月成交额',
    value: money(totals.value.actualAmount),
    sub: `目标 ${money(totals.value.targetAmount)}`,
    icon: 'i-lucide-wallet',
  },
  {
    label: '本月新成交客户',
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
    class="flex flex-col w-full h-full gap-4 p-6 overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          {{ t('CRM.TEAM_DASHBOARD.HEADER') }}
        </h1>
        <p class="mt-0.5 text-sm text-n-slate-11">
          {{ data?.month_label }}
        </p>
      </div>
      <select
        v-if="teams.length"
        v-model.number="selectedTeamId"
        class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
      >
        <option v-for="team_ in teams" :key="team_.id" :value="team_.id">
          {{ team_.name }}
        </option>
      </select>
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
      <!-- KPI 暖橙浅卡 -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
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
      </div>

      <!-- 团队合计进度 + 完成率仪表 -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div
          class="p-5 border shadow-sm lg:col-span-2 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
        >
          <h2 class="mb-4 text-base font-medium text-n-slate-12">
            团队合计 · {{ team.name }}
          </h2>
          <div class="flex flex-col gap-4">
            <div
              v-for="line in [
                {
                  label: '成交额',
                  m: metricLine(totals.actualAmount, totals.targetAmount, true),
                },
                {
                  label: '新成交客户',
                  m: metricLine(totals.actualCount, totals.targetCount, false),
                },
              ]"
              :key="line.label"
              class="flex items-center gap-3 text-sm"
            >
              <span class="w-16 text-xs shrink-0 text-n-slate-11">
                {{ line.label }}
              </span>
              <div
                class="flex-1 h-2.5 overflow-hidden rounded-full bg-n-alpha-2"
              >
                <div
                  class="h-full rounded-full"
                  :class="line.m.barClass"
                  :style="{ width: line.m.barWidth }"
                />
              </div>
              <span class="w-48 text-xs text-right shrink-0 text-n-slate-12">
                {{ line.m.text }}
              </span>
            </div>
          </div>
        </div>

        <div
          class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
        >
          <h2 class="mb-2 text-base font-medium text-n-slate-12">
            成交额完成率
          </h2>
          <template v-if="completionPct != null">
            <div class="h-40 mx-auto max-w-[14rem]">
              <CrmDoughnutChart
                :data="[
                  Math.min(100, completionPct),
                  Math.max(0, 100 - completionPct),
                ]"
                gauge
                cutout="78%"
              >
                <template #center>
                  <div class="text-3xl font-bold text-n-slate-12">
                    {{ completionPct }}%
                  </div>
                </template>
              </CrmDoughnutChart>
            </div>
            <div class="text-center text-n-slate-11">
              <span class="font-medium text-n-slate-12">
                {{ money(totals.actualAmount) }}
              </span>
              / {{ money(totals.targetAmount) }}
            </div>
          </template>
          <div
            v-else
            class="flex items-center justify-center py-10 text-sm text-n-slate-10"
          >
            本团队未设定目标
          </div>
        </div>
      </div>

      <!-- 组员完成率 -->
      <div>
        <h2 class="mb-3 text-base font-medium text-n-slate-12">组员完成率</h2>
        <div
          v-if="!team.members.length"
          class="p-5 text-sm border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150 text-n-slate-11"
        >
          该团队暂无组员。可在「系统设置 → CRM 团队」分配组员。
        </div>
        <div v-else class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div
            v-for="member in team.members"
            :key="member.id"
            class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <div class="mb-3 font-medium text-n-slate-12">
              {{ member.name }}
            </div>
            <div class="flex flex-col gap-4">
              <div
                v-for="line in [
                  {
                    label: '成交额',
                    m: metricLine(
                      member.actual_amount_micros,
                      member.target_amount_micros,
                      true
                    ),
                  },
                  {
                    label: '新成交客户',
                    m: metricLine(
                      member.actual_count,
                      member.target_count,
                      false
                    ),
                  },
                ]"
                :key="line.label"
                class="flex items-center gap-3 text-sm"
              >
                <span class="w-16 text-xs shrink-0 text-n-slate-11">
                  {{ line.label }}
                </span>
                <div
                  class="flex-1 h-2.5 overflow-hidden rounded-full bg-n-alpha-2"
                >
                  <div
                    class="h-full rounded-full"
                    :class="line.m.barClass"
                    :style="{ width: line.m.barWidth }"
                  />
                </div>
                <span class="w-44 text-xs text-right shrink-0 text-n-slate-12">
                  {{ line.m.text }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
