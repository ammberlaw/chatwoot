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
import CrmTodoMascot from './CrmTodoMascot.vue';

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
const COLLAPSED_H = 104; // 收起时的高度，用来夹取拖动范围
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
// 视口尺寸要做成响应式的。
//
// 原来 boxStyle 直接读 window.innerWidth/innerHeight——computed 只在**响应式**依赖变化时
// 重算，而 window 尺寸不是响应式的。于是换个屏幕、缩放窗口、甚至浏览器更新后窗口变矮，
// 位置都不会重新夹取：localStorage 里存的还是上一个尺寸下的坐标，浮层就卡在视口外
// 下不来（2026-10-27 生产：Ken 的 to do list 展开后顶在屏幕上沿，只露出半张卡片）。
const vw = ref(window.innerWidth);
const vh = ref(window.innerHeight);
const boxEl = ref(null);

// 展开后的真实高度。原来写死 368，但列表区是 max-h-320 + 标题 48 + 内边距，
// 实际约 376；标题长的时候更高。写死的数字只要比真值小，顶部就会被切掉一截。
const panelHeight = () => {
  const measured = boxEl.value?.offsetHeight;
  if (measured) return measured;

  return open.value ? Math.min(376, vh.value - 16) : COLLAPSED_H;
};

const clampPos = ({ left, bottom }) => ({
  left: Math.max(8, Math.min(left, vw.value - (open.value ? 328 : 112))),
  bottom: Math.max(8, Math.min(bottom, vh.value - panelHeight() - 8)),
});

const boxStyle = computed(() => {
  const { left, bottom } = clampPos(pos.value);
  return { left: `${left}px`, bottom: `${bottom}px` };
});

// 视口变了就把坐标**真正改掉并存回去**，而不只是渲染时临时夹一下——
// 否则换回大屏它又跳回那个越界的老位置。
const syncViewport = () => {
  vw.value = window.innerWidth;
  vh.value = window.innerHeight;
  const fixed = clampPos(pos.value);
  if (fixed.left === pos.value.left && fixed.bottom === pos.value.bottom)
    return;

  pos.value = fixed;
  try {
    localStorage.setItem(POS_KEY, JSON.stringify(fixed));
  } catch {
    // 存储不可用则忽略
  }
};

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
    vw.value - (open.value ? 328 : 112)
  );
  const bottom = Math.min(
    Math.max(startBottom - (e.clientY - startY), 8),
    vh.value - panelHeight() - 8
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
let sizeObserver = null;

onMounted(() => {
  syncViewport();
  window.addEventListener('resize', syncViewport);
  // 光在挂载时夹一次不够：那一刻列表还没渲染出来，量到的高度只有收起时那么点，
  // 夹出来的位置按小高度算，等内容撑开（实测 370px）顶部就又出界了
  // ——2026-10-27 实测存成 bottom=885、顶部切掉 255px 就是这么来的。
  // 所以盯着元素自身的尺寸变化：展开、收起、待办条数变化、标题换行，都会重夹一次。
  if (window.ResizeObserver && boxEl.value) {
    sizeObserver = new ResizeObserver(() => syncViewport());
    sizeObserver.observe(boxEl.value);
  }
  load();
  // 两分钟拉一次：新来的客户邮件会自动往日程里塞「回复客户来信」，
  // 不刷新的话这个窗会停在打开页面那一刻。
  timer = setInterval(load, 120000);
});
onBeforeUnmount(() => {
  clearInterval(timer);
  window.removeEventListener('resize', syncViewport);
  sizeObserver?.disconnect();
});

// 绑定而不是写死：裸中文属性会被 vue/no-bare-strings 拦下。
const DRAG_HINT = 'to do list（可拖动）';

// 标签（时间点 / 回信 / 待接单 / 待过账…）后端算好了，前端不再推一遍。
const goTo = row =>
  row.route ? accountScopedRoute(row.route, {}, row.query || {}) : null;
</script>

<template>
  <div
    v-if="canUse"
    ref="boxEl"
    :style="boxStyle"
    class="fixed z-[54] hidden md:block max-w-[calc(100vw-16px)] max-h-[calc(100dvh-16px)] font-sans antialiased"
    :class="open ? 'w-[320px] overflow-hidden rounded-2xl border border-[#e7e7e4] bg-white shadow-[0_12px_40px_-12px_rgba(0,0,0,0.25)]' : 'size-[104px]'"
  >
    <button v-if="!open" type="button" class="relative flex size-[104px] cursor-move touch-none select-none items-center justify-center rounded-full border-0 bg-transparent p-0 transition-transform hover:-translate-y-1 motion-reduce:transform-none" :title="DRAG_HINT" :aria-label="`打开 to do list，${pendingCount} 项待办（可拖动）`" @pointerdown="onPointerDown" @click="toggleOpen">
      <CrmTodoMascot class="pointer-events-none size-[104px] shrink-0 drop-shadow-md" />
      <span v-if="pendingCount" class="pointer-events-none absolute right-1 top-1 flex h-6 min-w-6 items-center justify-center rounded-full bg-[#fff3cc] px-1 text-label-small !font-medium text-[#8d6914] ring-2 ring-white">{{ pendingCount > 99 ? '99+' : pendingCount }}</span>
    </button>
    <!-- 展开时标题固定，列表独立滚动。 -->
    <div v-else class="bg-white">
      <button
        type="button"
        class="flex h-12 items-center w-full gap-2.5 px-4 cursor-move touch-none select-none reset-base"
        :aria-expanded="open"
        :title="DRAG_HINT"
        @pointerdown="onPointerDown"
        @click="toggleOpen"
      >
        <CrmTodoMascot class="size-8 shrink-0" />
        <span class="text-heading-3 !font-medium text-[#262722]">{{ 'to do list' }}</span>
        <span class="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-[#fff3cc] px-1.5 text-label-small !font-medium tabular-nums text-[#8d6914]">{{ pendingCount }}</span>
        <span
          class="ml-auto shrink-0 size-4 text-n-slate-10"
          :class="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="open" class="min-h-0 border-t border-[#f0f0ed] p-2 max-h-[min(320px,calc(100dvh-80px))] overflow-y-auto overscroll-contain">
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
            class="flex items-start w-full gap-2.5 px-3 py-2.5 text-left transition-colors rounded-lg reset-base hover:bg-n-alpha-1"
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
                class="block text-label !font-normal !leading-5 truncate"
                :class="
                  row.done
                    ? 'line-through decoration-n-slate-8 text-n-slate-10'
                    : 'text-[#262722]'
                "
                >{{ row.title }}</span
              >
              <span class="mt-1 block text-label-small !font-normal text-[#92959c]">{{
                row.label
              }}</span>
            </span>
          </button>
          <!-- 业务待办：勾不掉（单子并没有被审），只能带人去那张单上做 -->
          <router-link
            v-else
            :to="goTo(row)"
            class="flex items-start w-full gap-2.5 px-3 py-2.5 transition-colors rounded-lg hover:bg-n-alpha-1"
          >
            <span
              class="mt-1.5 shrink-0 size-1.5 rounded-full bg-[#e7b942]"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1">
              <span class="block text-label !font-normal !leading-5 truncate text-[#262722]">{{
                row.title
              }}</span>
              <span class="mt-1 block text-label-small !font-normal text-[#92959c]">{{
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
  </div>
</template>
