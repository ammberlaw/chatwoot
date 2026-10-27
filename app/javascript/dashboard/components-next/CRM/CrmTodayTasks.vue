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
import ScheduleAPI from 'dashboard/api/crm/scheduleEvents';

const { accountId, accountScopedRoute } = useAccount();
const route = useRoute();

// 全员可见：里面不只有日程，还有 MES 接单/审批/过账、订单审核、绩效考核——
// 仓库和车间岗没有 CRM 权限但一样有事要办（后端 Crm::MyDay 按各自权限算）。
// 日程页自己那一屏是完整列表，那页上不浮这个。
const canUse = computed(() => route.name !== 'crm_schedule_index');

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

// 只取今天这一格。逾期的不往这儿塞——这个窗是「今天做什么」，
// 混进几十条积压就又变成那个没人看的列表了（侧栏角标分开报逾期）。
const load = async () => {
  if (!canUse.value) return;
  loading.value = true;
  try {
    const { data } = await ScheduleAPI.myDay(accountId.value);
    rows.value = data?.payload || [];
  } catch {
    rows.value = [];
  } finally {
    loading.value = false;
  }
};

// 日程按「这一次发生」唯一，业务待办的 id 后端已经是唯一 key。
const keyOf = row =>
  row.type === 'schedule' ? `${row.id}@${row.occurrence_date}` : row.id;

// 勾掉：先在本地划掉再发请求，手感跟得上；失败就把它放回来。
// 按「这一次发生」的日期销，不是按今天——重复日程一天可能有多次发生。
// 只有日程能打勾。业务待办得去那张单上真做那个动作，这里只负责把人带过去——
// 在这儿「勾掉」一张待审的出库单是假的，单子并没有被审。
//
// 勾掉后**留在列表里划掉**，不移走：当场消失会让人怀疑自己是不是点错了，
// 而且一天下来看不见自己做完了什么。再点一下能取消（后端 toggle_done 本来就是开关）。
const toggle = async row => {
  if (row.type !== 'schedule') return;

  const key = keyOf(row);
  if (acting.value === key) return;

  acting.value = key;
  const before = row.done;
  row.done = !before;
  try {
    await ScheduleAPI.toggleDone(accountId.value, row.id, row.occurrence_date);
  } catch {
    row.done = before;
  } finally {
    acting.value = null;
  }
};

// 标题上那个数字是「还要做几件」，不含已勾掉的——做完一件就该看见它减一。
const pendingCount = computed(() => rows.value.filter(r => !r.done).length);

// 勾掉的沉到底（后端已排好），前端只管渲染，不再二次排序——
// 二次排序会让刚勾掉的那条当场跳走，又变回「消失」的观感。

let timer = null;
onMounted(() => {
  load();
  // 两分钟拉一次：新来的客户邮件会自动往日程里塞「回复客户来信」，
  // 不刷新的话这个窗会停在打开页面那一刻。
  timer = setInterval(load, 120000);
});
onBeforeUnmount(() => clearInterval(timer));

// 绑定而不是写死：裸中文属性会被 vue/no-bare-strings 拦下。
const DRAG_HINT = 'to do list（可拖动）';

// 标签（时间点 / 回信 / 待接单 / 待过账…）后端算好了，前端不再推一遍。
const goTo = row =>
  row.route ? accountScopedRoute(row.route, {}, row.query || {}) : null;
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
        <span class="text-heading-3 text-[#262722]">{{ 'to do list' }}</span>
        <span class="text-label-small text-n-slate-10">{{ pendingCount }}</span>
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
          {{ '今天没有待办' }}
        </p>
        <template v-for="row in rows" :key="keyOf(row)">
          <!-- 日程：能直接勾掉 -->
          <button
            v-if="row.type === 'schedule'"
            type="button"
            class="flex items-start w-full gap-2 px-2 py-1.5 text-left transition-colors rounded-lg reset-base hover:bg-n-alpha-1"
            :disabled="acting === keyOf(row)"
            @click="toggle(row)"
          >
            <span
              class="mt-0.5 shrink-0 size-4"
              :class="[
                row.done
                  ? 'i-lucide-square-check-big text-n-slate-11'
                  : 'i-lucide-square text-n-slate-8',
                acting === keyOf(row) ? 'opacity-40' : '',
              ]"
            />
            <span class="min-w-0">
              <span
                class="block text-sm truncate"
                :class="
                  row.done
                    ? 'line-through decoration-n-slate-8 text-n-slate-10'
                    : 'text-[#262722]'
                "
                >{{ row.title }}</span
              >
              <span class="block text-label-small text-n-slate-10">{{
                row.label
              }}</span>
            </span>
          </button>
          <!-- 业务待办：勾不掉（单子并没有被审），只能带人去那张单上做 -->
          <router-link
            v-else
            :to="goTo(row)"
            class="flex items-start w-full gap-2 px-2 py-1.5 transition-colors rounded-lg hover:bg-n-alpha-1"
          >
            <span
              class="mt-1 shrink-0 size-1.5 rounded-full bg-n-amber-9"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1">
              <span class="block text-sm truncate text-[#262722]">{{
                row.title
              }}</span>
              <span class="block text-label-small text-n-slate-10">{{
                row.label
              }}</span>
            </span>
            <span
              class="mt-1 shrink-0 size-3.5 text-n-slate-9 i-lucide-arrow-up-right"
              aria-hidden="true"
            />
          </router-link>
        </template>
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
