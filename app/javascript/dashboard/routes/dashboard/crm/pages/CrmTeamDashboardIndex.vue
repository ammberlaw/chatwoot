<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

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

const money = micros => `¥${Math.round((micros || 0) / 1_000_000).toLocaleString()}`;

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
  if (p >= 30) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};
const barWidth = p => `${Math.min(100, Math.max(2, p ?? 0))}%`;

const kpiCompletion = computed(() =>
  totals.value.targetAmount > 0
    ? `${Math.round((totals.value.actualAmount / totals.value.targetAmount) * 100)}%`
    : '—'
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
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 p-6 overflow-auto bg-n-background">
    <div class="flex items-center gap-3">
      <h1 class="text-xl font-medium text-n-slate-12">
        👥 {{ t('CRM.TEAM_DASHBOARD.HEADER') }}
      </h1>
      <select
        v-if="teams.length"
        v-model.number="selectedTeamId"
        class="h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
      >
        <option v-for=" team_ in teams" :key="team_.id" :value="team_.id">
          {{ team_.name }}
        </option>
      </select>
      <span class="text-sm text-n-slate-11">{{ data?.month_label }}</span>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.TEAM_DASHBOARD.LOADING') }}
    </div>

    <div
      v-else-if="!teams.length"
      class="p-8 text-sm text-center border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-11"
    >
      {{ t('CRM.TEAM_DASHBOARD.EMPTY') }}
    </div>

    <template v-else-if="team">
      <!-- 3 KPI -->
      <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="text-xs text-n-slate-11">本月成交额</div>
          <div class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ money(totals.actualAmount) }}
          </div>
          <div class="mt-1 text-xs text-n-slate-10">
            目标 {{ money(totals.targetAmount) }}
          </div>
        </div>
        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="text-xs text-n-slate-11">本月新成交客户</div>
          <div class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ totals.actualCount }}
          </div>
          <div class="mt-1 text-xs text-n-slate-10">
            目标 {{ totals.targetCount }}
          </div>
        </div>
        <div class="p-4 border rounded-xl border-n-blue-9 bg-n-blue-9 text-white">
          <div class="text-xs text-white/80">成交额完成率</div>
          <div class="mt-1 text-2xl font-bold">{{ kpiCompletion }}</div>
          <div class="mt-1 text-xs text-white/80">
            组员 {{ totals.memberCount }} 人
          </div>
        </div>
      </div>

      <!-- 团队合计 -->
      <div class="p-4 border rounded-xl border-n-blue-8 bg-n-solid-1">
        <div class="mb-3 font-medium text-n-slate-12">
          团队合计 · {{ team.name }}
        </div>
        <div class="flex flex-col gap-2">
          <div
            v-for="line in [
              { label: '成交额', m: metricLine(totals.actualAmount, totals.targetAmount, true) },
              { label: '新成交客户', m: metricLine(totals.actualCount, totals.targetCount, false) },
            ]"
            :key="line.label"
            class="flex items-center gap-3 text-sm"
          >
            <span class="text-xs w-16 shrink-0 text-n-slate-11">
              {{ line.label }}
            </span>
            <div class="flex-1 h-4 overflow-hidden rounded-full bg-n-alpha-2">
              <div
                class="h-full rounded-full"
                :class="line.m.barClass"
                :style="{ width: line.m.barWidth }"
              />
            </div>
            <span class="text-xs text-right w-44 shrink-0 text-n-slate-11">
              {{ line.m.text }}
            </span>
          </div>
        </div>
      </div>

      <!-- 组员完成率 -->
      <div class="text-xs font-medium text-n-slate-11">组员完成率</div>
      <div
        v-if="!team.members.length"
        class="p-4 text-sm border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-11"
      >
        该团队暂无组员。可在「系统设置 → CRM 团队」分配组员。
      </div>
      <div
        v-for="member in team.members"
        :key="member.id"
        class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="mb-2 font-medium text-n-slate-12">{{ member.name }}</div>
        <div class="flex flex-col gap-2">
          <div
            v-for="line in [
              { label: '成交额', m: metricLine(member.actual_amount_micros, member.target_amount_micros, true) },
              { label: '新成交客户', m: metricLine(member.actual_count, member.target_count, false) },
            ]"
            :key="line.label"
            class="flex items-center gap-3 text-sm"
          >
            <span class="text-xs w-16 shrink-0 text-n-slate-11">
              {{ line.label }}
            </span>
            <div class="flex-1 h-4 overflow-hidden rounded-full bg-n-alpha-2">
              <div
                class="h-full rounded-full"
                :class="line.m.barClass"
                :style="{ width: line.m.barWidth }"
              />
            </div>
            <span class="text-xs text-right w-44 shrink-0 text-n-slate-11">
              {{ line.m.text }}
            </span>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
