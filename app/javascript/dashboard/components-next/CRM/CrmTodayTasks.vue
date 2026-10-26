<script setup>
// 「今天要做的事」悬浮窗：常驻左下角，列今天的日程，能直接打勾。
//
// 为什么要常驻：日程表原先没人用不是因为界面不好看，是因为它不会来找你——
// 实查 181 条日程只有 8 条被标记完成过（4.4%）。推送解决「早上知道有什么事」，
// 这个窗解决「一天里随时看得见、顺手就能勾掉」。勾一次的成本越低，这份清单才越可信。
//
// 可拖动 + 记住位置，和 AI 球同一套做法。不是为了花哨——实测这个界面**没有一个
// 固定位置是空的**：内容区左下角在客户列表是表格行的复选框，在邮件中心是整列
// 文件夹导航（新建文件夹/待回复/重要/等付款），右下角是 AI 球和各页的行操作按钮。
// 固定在哪儿都会压住别人的功能，所以交给用户自己挪，位置存本地。
//
// 手机端左下角是侧栏按钮，而且小屏上浮窗本就挤，只在 md 以上显示。
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import ScheduleAPI from 'dashboard/api/crm/scheduleEvents';

const { accountId, accountScopedRoute } = useAccount();
const route = useRoute();
const currentUser = useMapGetter('getCurrentUser');

// 日程是 CRM 的东西，没有 CRM 权限的人不显示（仓库/车间那些岗位看了是空的）。
// 日程页自己那一屏就是完整列表，再浮一个重复的没意义。
const canUse = computed(
  () =>
    currentUser.value?.can_access_crm === true &&
    route.name !== 'crm_schedule_index'
);

// 默认收起：收起只剩一条标题（44px），数字照样看得见，点一下展开。
// 展开/收起记在本地，常用的人开一次就一直开着。
const open = ref(false);
const loading = ref(false);
const rows = ref([]);
const acting = ref(null);

// ── 位置（可拖动，记在本地，按距左下角的偏移存）────────────────
const POS_KEY = 'crmTodayTasksPos';
const COLLAPSED_H = 44; // 收起时的高度，用来夹取拖动范围
// 默认落在内容区左下角，不是视口左下角——视口左下角是侧栏（实测 212px 宽），
// 默认就压在导航和头像上。236 让开侧栏；之后用户想挪哪儿挪哪儿。
const DEFAULT_LEFT = 236;
const pos = ref({ left: DEFAULT_LEFT, bottom: 24 });
try {
  const saved = JSON.parse(localStorage.getItem(POS_KEY) || 'null');
  if (saved && Number.isFinite(saved.left) && Number.isFinite(saved.bottom)) {
    pos.value = saved;
  }
} catch {
  // 忽略损坏的本地存储
}
const boxStyle = computed(() => ({
  left: `${pos.value.left}px`,
  bottom: `${pos.value.bottom}px`,
}));

let startX = 0;
let startY = 0;
let startLeft = 0;
let startBottom = 0;
let moved = false;

const onPointerMove = e => {
  if (Math.abs(e.clientX - startX) > 3 || Math.abs(e.clientY - startY) > 3)
    moved = true;
  const left = Math.min(
    Math.max(startLeft + (e.clientX - startX), 8),
    window.innerWidth - 308
  );
  const bottom = Math.min(
    Math.max(startBottom - (e.clientY - startY), 8),
    window.innerHeight - COLLAPSED_H - 8
  );
  pos.value = { left, bottom };
};
const onPointerUp = () => {
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointerup', onPointerUp);
  if (!moved) return;

  try {
    localStorage.setItem(POS_KEY, JSON.stringify(pos.value));
  } catch {
    // 存储不可用则忽略（位置仍在本次会话生效）
  }
};
const onPointerDown = e => {
  moved = false;
  startX = e.clientX;
  startY = e.clientY;
  startLeft = pos.value.left;
  startBottom = pos.value.bottom;
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp);
};

const STORAGE_KEY = 'crmTodayTasksOpen';
try {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved !== null) open.value = saved === '1';
} catch {
  // 忽略损坏的本地存储
}
// 拖动后不触发展开；纯点击（未拖动）才开合。
const toggleOpen = () => {
  if (moved) return;

  open.value = !open.value;
  try {
    localStorage.setItem(STORAGE_KEY, open.value ? '1' : '0');
  } catch {
    // 本地存储不可用不影响使用
  }
};

const todayStr = () => new Date().toISOString().slice(0, 10);

// 只取今天这一格。逾期的不往这儿塞——这个窗是「今天做什么」，
// 混进几十条积压就又变成那个没人看的列表了（侧栏角标分开报逾期）。
const load = async () => {
  if (!canUse.value) return;
  loading.value = true;
  try {
    const d = todayStr();
    const { data } = await ScheduleAPI.get(accountId.value, { from: d, to: d });
    rows.value = (data?.payload || []).filter(o => !o.done);
  } catch {
    rows.value = [];
  } finally {
    loading.value = false;
  }
};

const keyOf = row => `${row.id}@${row.occurrence_date}`;

// 勾掉：先在本地划掉再发请求，手感跟得上；失败就把它放回来。
// 按「这一次发生」的日期销，不是按今天——重复日程一天可能有多次发生。
const toggle = async row => {
  const key = keyOf(row);
  if (acting.value) return;
  acting.value = key;
  const before = rows.value;
  rows.value = rows.value.filter(r => keyOf(r) !== key);
  try {
    await ScheduleAPI.toggleDone(accountId.value, row.id, row.occurrence_date);
  } catch {
    rows.value = before;
  } finally {
    acting.value = null;
  }
};

let timer = null;
onMounted(() => {
  load();
  // 两分钟拉一次：新来的客户邮件会自动往日程里塞「回复客户来信」，
  // 不刷新的话这个窗会停在打开页面那一刻。
  timer = setInterval(load, 120000);
});
onBeforeUnmount(() => clearInterval(timer));

// 绑定而不是写死：裸中文属性会被 vue/no-bare-strings 拦下。
const DRAG_HINT = '今天要做的（可拖动）';

const KIND_LABEL = {
  reply_reminder: '回信',
  opp_follow_up: '商机',
  follow_up: '跟进',
};
const labelOf = row =>
  row.all_day
    ? KIND_LABEL[row.kind] || '全天'
    : (row.starts_at || '').slice(11, 16);
</script>

<template>
  <div
    v-if="canUse"
    :style="boxStyle"
    class="fixed z-[54] hidden md:block w-[300px] rounded-2xl bg-n-amber-9 shadow-lg shadow-black/10 overflow-hidden"
  >
    <!-- 外层黄底只露出底部一条，内层白卡装内容——参考图的层次做法 -->
    <div class="m-1 mb-0 bg-white rounded-xl ring-1 ring-inset ring-black/5">
      <button
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2.5 cursor-move touch-none select-none reset-base"
        :title="DRAG_HINT"
        @pointerdown="onPointerDown"
        @click="toggleOpen"
      >
        <span class="text-heading-3 text-[#262722]">{{ '今天要做的' }}</span>
        <span class="text-label-small text-n-slate-10">{{ rows.length }}</span>
        <span
          class="ml-auto shrink-0 size-4 text-n-slate-10"
          :class="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="open" class="px-1.5 pb-2 max-h-[280px] overflow-y-auto">
        <p
          v-if="!rows.length && !loading"
          class="px-2 py-3 text-label-small text-n-slate-10"
        >
          {{ '今天没有安排' }}
        </p>
        <button
          v-for="row in rows"
          :key="keyOf(row)"
          type="button"
          class="flex items-start w-full gap-2 px-2 py-1.5 text-left transition-colors rounded-lg reset-base hover:bg-n-alpha-1"
          :disabled="acting === keyOf(row)"
          @click="toggle(row)"
        >
          <span
            class="mt-0.5 shrink-0 size-4 rounded border border-n-slate-6 i-lucide-square"
            :class="acting === keyOf(row) ? 'opacity-40' : ''"
          />
          <span class="min-w-0">
            <span class="block text-sm truncate text-[#262722]">{{
              row.title
            }}</span>
            <span class="block text-label-small text-n-slate-10">{{
              labelOf(row)
            }}</span>
          </span>
        </button>
      </div>
    </div>

    <router-link
      v-if="open"
      :to="accountScopedRoute('crm_schedule_index')"
      class="flex items-center justify-between px-3 py-2 text-label-small text-[#4a4328] hover:text-[#262722]"
    >
      {{ '打开日程' }}
      <span class="shrink-0 size-3.5 i-lucide-arrow-right" />
    </router-link>
  </div>
</template>
