<script setup>
import { ref, computed, onMounted } from 'vue';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchTeamDashboard } from '@/api/crm';
import { money, num } from '@/utils/format';

defineOptions({ name: 'TeamDashboardPage' });

const ref_ = new Date();
const year = ref(ref_.getFullYear());
const month = ref(ref_.getMonth() + 1);
const monthLabel = ref('');
const teams = ref([]);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

// 后端按角色收口可见团队：管理员看全部，其余只看自己团队
const totals = computed(() =>
  teams.value.map(t => ({
    id: t.id,
    name: t.name,
    members: t.members,
    actual: t.members.reduce((s, m) => s + num(m.actual_amount_micros), 0),
    target: t.members.reduce((s, m) => s + num(m.target_amount_micros), 0),
    newCustomers: t.members.reduce((s, m) => s + num(m.actual_count), 0),
  }))
);

const pct = (actual, target) => {
  const a = num(actual);
  const t = num(target);
  if (t <= 0) return a > 0 ? 100 : null;
  return (a / t) * 100;
};
const barClass = p => {
  if (p == null) return 'bg-n-slate-6';
  if (p >= 100) return 'bg-n-teal-9';
  if (p >= 60) return 'bg-n-blue-9';
  if (p >= 30) return 'bg-n-iris-9';
  return 'bg-n-ruby-9';
};
const barWidth = p => `${Math.min(100, Math.max(2, p ?? 0))}%`;
const fmtPct = p => (p == null ? '—' : `${Math.round(p)}%`);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchTeamDashboard({ year: year.value, month: month.value });
    teams.value = r.data?.teams || [];
    monthLabel.value = r.data?.month_label || '';
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const shiftMonth = d => {
  const dt = new Date(year.value, month.value - 1 + d, 1);
  year.value = dt.getFullYear();
  month.value = dt.getMonth() + 1;
  load();
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back title="团队看板" :subtitle="monthLabel">
      <template #actions>
        <button
          type="button"
          aria-label="上个月"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
          @click="shiftMonth(-1)"
        >
          <span class="size-5 i-lucide-chevron-left" />
        </button>
        <button
          type="button"
          aria-label="下个月"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
          @click="shiftMonth(1)"
        >
          <span class="size-5 i-lucide-chevron-right" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!teams.length"
        :stale-at="staleAt"
        empty-text="你还没有加入任何团队"
        @retry="load"
      >
        <template v-for="t in totals" :key="t.id">
          <div class="p-4 mt-3 first:mt-0 wt-card">
            <div class="flex items-baseline justify-between">
              <span class="text-sm font-semibold text-n-slate-12">{{ t.name }}</span>
              <span class="text-sm font-semibold text-n-slate-12">
                {{ fmtPct(pct(t.actual, t.target)) }}
              </span>
            </div>
            <div class="h-2 mt-2 overflow-hidden rounded-full bg-n-alpha-1">
              <div
                class="h-full rounded-full"
                :class="barClass(pct(t.actual, t.target))"
                :style="{ width: barWidth(pct(t.actual, t.target)) }"
              />
            </div>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ money(t.actual) }} / {{ money(t.target) }} · 新成交 {{ t.newCustomers }} 家
            </p>
          </div>

          <ul v-if="t.members.length" class="mt-2 overflow-hidden wt-card">
            <li
              v-for="m in t.members"
              :key="m.id"
              class="px-3 py-3 border-b last:border-b-0 border-n-weak"
            >
              <div class="flex items-baseline justify-between">
                <span class="text-sm truncate text-n-slate-12">{{ m.name }}</span>
                <span class="flex-none ml-2 text-xs text-n-slate-11">
                  {{ fmtPct(pct(m.actual_amount_micros, m.target_amount_micros)) }}
                </span>
              </div>
              <div class="h-1.5 mt-1.5 overflow-hidden rounded-full bg-n-alpha-1">
                <div
                  class="h-full rounded-full"
                  :class="barClass(pct(m.actual_amount_micros, m.target_amount_micros))"
                  :style="{
                    width: barWidth(pct(m.actual_amount_micros, m.target_amount_micros)),
                  }"
                />
              </div>
              <p class="mt-1.5 text-xs text-n-slate-10">
                {{ money(m.actual_amount_micros) }} / {{ money(m.target_amount_micros) }}
                · 新成交 {{ m.actual_count }} 家
              </p>
            </li>
          </ul>
        </template>
        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
