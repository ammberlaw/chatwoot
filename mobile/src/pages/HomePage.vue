<script setup>
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { useAuthStore } from '@/stores/auth';
import {
  fetchHomeStats,
  fetchStats,
  fetchScheduleEvents,
  fetchEmailCounts,
  fetchApprovalCounts,
} from '@/api/crm';
import { money, num, shortDateTime } from '@/utils/format';
import { MODULE_GROUPS, HOME_SHORTCUTS } from '@/constants/modules';

defineOptions({ name: 'HomePage' });

const router = useRouter();
const auth = useAuthStore();

const home = ref({});
const stats = ref({});
const events = ref([]);
const mailCounts = ref({});
const approvalCounts = ref({});
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

const greeting = computed(() => {
  const h = new Date().getHours();
  if (h < 6) return '夜深了';
  if (h < 12) return '早上好';
  if (h < 18) return '下午好';
  return '晚上好';
});

// 待办：点进去直接落到对应模块，不用自己再翻
const todos = computed(() => [
  {
    label: '待跟进',
    value: home.value.crm?.follow_up_due || 0,
    to: { name: 'customers' },
  },
  {
    label: '已逾期',
    value: home.value.crm?.overdue || 0,
    to: { name: 'customers' },
    warn: true,
  },
  {
    label: '待我审批',
    value: approvalCounts.value.todo || 0,
    to: { name: 'approvals' },
  },
  {
    label: '未读邮件',
    value: mailCounts.value.unread || 0,
    to: { name: 'mail' },
  },
]);

// 九宫格快捷入口：按 HOME_SHORTCUTS 的顺序取，且只留路由里真实存在的
const allModules = MODULE_GROUPS.flatMap(g => g.items);
const shortcuts = computed(() =>
  HOME_SHORTCUTS.map(n => allModules.find(m => m.name === n)).filter(
    m => m && router.hasRoute(m.name)
  )
);

const yearly = computed(() => stats.value.period_stats?.yearly || {});
const kpis = computed(() => [
  { label: '本年成交额', value: money(yearly.value.amount_micros) },
  { label: '成交订单', value: yearly.value.order_count ?? 0 },
  { label: '成交客户', value: yearly.value.deal_customers ?? 0 },
  { label: '新客户', value: yearly.value.new_customers ?? 0 },
]);

// 本月目标完成度：没设目标就不显示这块，免得摆个 0%
const target = computed(() => {
  const t = stats.value.target;
  if (!num(t?.amount_micros)) return null;
  const done = num(t.month_amount_micros);
  const total = num(t.amount_micros);
  return { done, total, percent: Math.min(100, Math.round((done / total) * 100)) };
});

const load = async () => {
  loading.value = true;
  failed.value = false;
  const today = new Date().toISOString().slice(0, 10);
  // 五个来源互不依赖，一起发；任一失败不拖垮整页
  const [h, s, e, mc, ac] = await Promise.allSettled([
    fetchHomeStats(),
    fetchStats({ scope: 'mine' }),
    fetchScheduleEvents({ from: today, to: today }),
    fetchEmailCounts(),
    fetchApprovalCounts(),
  ]);
  if (h.status === 'fulfilled') {
    home.value = h.value.data || {};
    staleAt.value = h.value.fromCache ? h.value.at : null;
  }
  if (s.status === 'fulfilled') stats.value = s.value.data || {};
  if (e.status === 'fulfilled') events.value = e.value.data?.payload || [];
  if (mc.status === 'fulfilled') mailCounts.value = mc.value.data || {};
  if (ac.status === 'fulfilled') approvalCounts.value = ac.value.data || {};
  // 全挂了才算失败；部分成功仍然渲染
  failed.value = [h, s, e, mc, ac].every(r => r.status === 'rejected');
  loading.value = false;
};

onMounted(load);
onActivated(() => {
  if (!loading.value) load();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader
      title="工作台"
      :subtitle="`${greeting}，${auth.user?.name || auth.user?.email || ''}`"
    />

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState :loading="loading" :failed="failed" :stale-at="staleAt" @retry="load">
        <!-- 待办 -->
        <div class="grid grid-cols-4 overflow-hidden wt-card">
          <button
            v-for="t in todos"
            :key="t.label"
            type="button"
            class="py-3 border-r last:border-r-0 border-n-weak active:bg-n-alpha-1"
            @click="router.push(t.to)"
          >
            <div
              class="text-xl font-bold"
              :class="t.warn && t.value ? 'text-n-ruby-11' : 'text-n-slate-12'"
            >
              {{ t.value }}
            </div>
            <div class="mt-0.5 text-xs text-n-slate-10">{{ t.label }}</div>
          </button>
        </div>

        <!-- 快捷入口 -->
        <div v-if="shortcuts.length" class="grid grid-cols-4 gap-y-4 p-3 mt-3 wt-card">
          <button
            v-for="m in shortcuts"
            :key="m.name"
            type="button"
            class="flex flex-col items-center gap-1.5"
            @click="router.push({ name: m.name })"
          >
            <span
              class="grid rounded-xl size-10 place-items-center bg-n-iris-3 text-n-iris-11"
            >
              <span class="size-5" :class="m.icon" />
            </span>
            <span class="text-[11px] leading-none text-n-slate-11">{{ m.label }}</span>
          </button>
        </div>

        <!-- 本年业绩 -->
        <div class="grid grid-cols-2 gap-3 mt-3">
          <div
            v-for="k in kpis"
            :key="k.label"
            class="p-4 shadow-sm rounded-2xl bg-gradient-to-br from-n-iris-3 to-n-iris-5"
          >
            <div class="text-xs font-medium truncate text-n-slate-11">{{ k.label }}</div>
            <div class="mt-1 text-xl font-bold truncate text-n-slate-12">{{ k.value }}</div>
          </div>
        </div>

        <!-- 本月目标 -->
        <div v-if="target" class="p-4 mt-3 wt-card">
          <div class="flex items-baseline justify-between">
            <span class="text-xs font-medium text-n-slate-11">本月目标</span>
            <span class="text-sm font-semibold text-n-slate-12">{{ target.percent }}%</span>
          </div>
          <div class="h-2 mt-2 overflow-hidden rounded-full bg-n-alpha-1">
            <div class="h-full rounded-full bg-n-iris-9" :style="{ width: `${target.percent}%` }" />
          </div>
          <p class="mt-2 text-xs text-n-slate-10">
            {{ money(target.done) }} / {{ money(target.total) }}
          </p>
        </div>

        <!-- 今日日程 -->
        <h2 class="mt-4 mb-2 text-xs font-semibold tracking-wide text-n-slate-10">今日日程</h2>
        <p v-if="!events.length" class="py-6 text-sm text-center text-n-slate-11">
          今天没有安排
        </p>
        <ul v-else class="overflow-hidden wt-card">
          <li
            v-for="(ev, i) in events"
            :key="`${ev.id}-${i}`"
            class="flex items-start gap-3 px-3 py-3 border-b last:border-b-0 border-n-weak"
          >
            <span class="flex-none mt-1 rounded-full size-2 bg-n-iris-9" />
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate text-n-slate-12" :class="ev.done ? 'line-through text-n-slate-10' : ''">
                {{ ev.title }}
              </div>
              <div class="mt-0.5 text-xs text-n-slate-10">
                {{ ev.all_day ? '全天' : shortDateTime(ev.starts_at) }}
                <template v-if="ev.customer_name"> · {{ ev.customer_name }}</template>
                <template v-if="ev.location"> · {{ ev.location }}</template>
              </div>
            </div>
          </li>
        </ul>

        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
