<script setup>
// CRM 全局 AI 助手：常驻 CRM 各页右下角的悬浮球，点开就是对话。
//
// 2026-10-14 换成了**带工具的 agent**（Crm::Agent::Runner）：
// 原来这里是个「意图路由器」——AI 只判断你想干哪件事，然后跑写死的分支，
// 能查的只有 5 个固定指标（新增客户/待跟进/在谈商机/订单额/待办），
// 超出这几类就只能凭模型知识瞎聊、根本不碰你的库，也不会连着查几步。
//
// 现在换成真 agent：它自己决定调哪些工具、一轮里能连着查好几次
// （查客户 → 翻往来邮件 → 看订单 → 起草），而且取数跟着人的权限走。
// 壳（悬浮球、拖拽、位置记忆）原样保留，用户看到的入口没变。
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAiMascot from './CrmAiMascot.vue';
import CrmAgentPanel from 'dashboard/components-next/CRM/CrmAgentPanel.vue';
import CrmAgentAPI from 'dashboard/api/crm/agent';
import CrmAgentMemoriesAPI from 'dashboard/api/crm/agentMemories';

const open = ref(false);
const panelRef = ref(null);

// 历史对话：球上原来只有「新对话」，开过的那些从球里回不去，
// 只能跑去 AI 助手独立页找。
const historyOpen = ref(false);
const conversations = ref([]);
const historyLoading = ref(false);
const historyFailed = ref(false);

const loadHistory = async () => {
  historyLoading.value = true;
  historyFailed.value = false;
  try {
    const { data } = await CrmAgentAPI.get();
    conversations.value = data.payload || [];
  } catch {
    // 拉不到和「一条都没有」长得一样，不区分的话用户会以为对话丢了。
    conversations.value = [];
    historyFailed.value = true;
  } finally {
    historyLoading.value = false;
  }
};

// 助手记住的事。原来只能在对话里说「忘掉…」来删，而没人知道有这回事——
// 生产上一个人同时存着「叫我懒宝宝」和「不要叫懒宝宝」两条打架的记忆，
// 她自己既看不到也删不掉。
const memoryOpen = ref(false);
const memories = ref({ company: [], mine: [], may_edit_company: false });
const memoryLoading = ref(false);
const memoryFailed = ref(false);

const toggleHistory = () => {
  historyOpen.value = !historyOpen.value;
  if (historyOpen.value) loadHistory();
  memoryOpen.value = false;
};

const loadMemories = async () => {
  memoryLoading.value = true;
  memoryFailed.value = false;
  try {
    const { data } = await CrmAgentMemoriesAPI.get();
    memories.value = data;
  } catch {
    memoryFailed.value = true;
  } finally {
    memoryLoading.value = false;
  }
};

const toggleMemory = () => {
  memoryOpen.value = !memoryOpen.value;
  if (memoryOpen.value) loadMemories();
  historyOpen.value = false;
};

const forgetMemory = async row => {
  await CrmAgentMemoriesAPI.delete(row.id);
  loadMemories();
};

const memoryEmpty = computed(
  () => !memories.value.company.length && !memories.value.mine.length
);

const openConversation = async id => {
  historyOpen.value = false;
  try {
    await panelRef.value?.open(id);
  } catch {
    // 对话可能已被删，重拉一次列表让它从列表里消失
    loadHistory();
  }
};

const newChat = () => {
  historyOpen.value = false;
  panelRef.value?.reset();
};

// 名单之外的人不显示悬浮球（后端 Crm::AgentController 会再判一次）。
//
// 两处收起来：
// · 「AI 助手」独立页本身就是这个对话，再浮一颗球上去点开的是**另一个**会话，
//   用户会以为自己刚问的那句丢了。
// · 团队沟通页有自己的底部输入栏，球会挡住发送键。
//
// 这两条原先写在 CrmLayout 里。球挂到全局外壳（Dashboard.vue）之后那一层没了，
// 规则跟着搬进组件——放在挂载点上，每多一个挂载点就得抄一遍。
const HIDE_ON = ['crm_agent_index', 'crm_team_chat_index'];
const route = useRoute();
const currentUser = useMapGetter('getCurrentUser');
const canUse = computed(
  () => currentUser.value?.crm_agent === true && !HIDE_ON.includes(route.name)
);

const toggle = () => {
  open.value = !open.value;
  if (!open.value) historyOpen.value = false;
};

// —— 悬浮图标可拖动 + 记忆位置（按距右下角的偏移存 localStorage）——
const STORAGE_KEY = 'crmAiAssistantPos';
const LAUNCHER = 104; // size-[104px]
const PANEL_W = 440;
const PANEL_H = 620;
const pos = ref({ right: 24, bottom: 24 });
try {
  const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
  if (saved && Number.isFinite(saved.right) && Number.isFinite(saved.bottom)) {
    pos.value = saved;
  }
} catch {
  // 忽略损坏的本地存储
}

// 视口尺寸要响应式：换窗口大小/旋转屏幕时得重新夹取，否则原来在视口内的位置
// 换到小屏上就落到外面去了，而且刷新也救不回来——值一直存在 localStorage 里。
const vw = ref(window.innerWidth);
const vh = ref(window.innerHeight);

// 球本身也必须夹取。原来只有展开的面板做了夹取，球直接用存的偏移渲染——
// 拖到屏幕外、或换了更小的窗口，球就跑到看不见的地方，用户只会觉得「AI 球不见了」。
// （和待办浮层 2026-10-28 那次出界是同一类问题。）
const clampedPos = computed(() => ({
  right: Math.min(Math.max(pos.value.right, 8), Math.max(vw.value - LAUNCHER - 8, 8)),
  bottom: Math.min(Math.max(pos.value.bottom, 8), Math.max(vh.value - LAUNCHER - 8, 8)),
}));

const launcherStyle = computed(() => ({
  right: `${clampedPos.value.right}px`,
  bottom: `${clampedPos.value.bottom}px`,
}));

// 面板贴着图标位置弹出，并夹取在视口内确保完整可见。
const panelSize = ref({ width: PANEL_W, height: PANEL_H });
const panelOrigin = ref(null);
const panelBox = () => ({
  width: Math.min(panelSize.value.width, vw.value - 16),
  height: Math.min(panelSize.value.height, vh.value - 16),
});

// 夹取结果写回去：不写回的话，下次打开又从那个越界的旧值开始算。
const syncViewport = () => {
  vw.value = window.innerWidth;
  vh.value = window.innerHeight;
  if (panelOrigin.value) {
    const { width, height } = panelBox();
    panelOrigin.value = {
      left: Math.max(8, Math.min(panelOrigin.value.left, vw.value - width - 8)),
      top: Math.max(8, Math.min(panelOrigin.value.top, vh.value - height - 8)),
    };
  }
  const fixed = clampedPos.value;
  if (fixed.right !== pos.value.right || fixed.bottom !== pos.value.bottom) {
    pos.value = fixed;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(fixed));
    } catch {
      // 忽略：存不进去不影响这次显示
    }
  }
};

onMounted(() => {
  syncViewport();
  window.addEventListener('resize', syncViewport);
});
onBeforeUnmount(() => window.removeEventListener('resize', syncViewport));
const panelStyle = computed(() => {
  const width = Math.min(panelSize.value.width, vw.value - 16);
  const height = Math.min(panelSize.value.height, vh.value - 16);
  const left = Math.max(8, Math.min(
    panelOrigin.value?.left ?? vw.value - pos.value.right - width,
    vw.value - width - 8
  ));
  const top = Math.max(8, Math.min(
    panelOrigin.value?.top ?? vh.value - pos.value.bottom - height,
    vh.value - height - 8
  ));
  return { left: `${left}px`, top: `${top}px`, width: `${width}px`, height: `${height}px` };
});
// 面板拖动：按住头部空白处挪窗口。原来只有球能拖，面板一打开就钉在球旁边，
// 挡住正文时只能先关掉再把球拖走、重新打开。
// 位置和尺寸一样只在本次会话里记，刷新回到贴着球弹出的默认位置。
let dragStart;
const dragPanel = e => {
  if (!dragStart) return;
  const { width, height } = panelBox();
  panelOrigin.value = {
    left: Math.max(8, Math.min(dragStart.left + e.clientX - dragStart.x, vw.value - width - 8)),
    top: Math.max(8, Math.min(dragStart.top + e.clientY - dragStart.y, vh.value - height - 8)),
  };
};

const stopPanelDrag = () => {
  dragStart = null;
  window.removeEventListener('pointermove', dragPanel);
  window.removeEventListener('pointerup', stopPanelDrag);
  window.removeEventListener('pointercancel', stopPanelDrag);
};

const startPanelDrag = e => {
  // 头部上的按钮（历史/新对话/关闭）照常点，别被拖拽吞掉
  if (e.button !== 0 || e.target.closest('button')) return;
  const rect = e.currentTarget.parentElement.getBoundingClientRect();
  dragStart = { x: e.clientX, y: e.clientY, left: rect.left, top: rect.top };
  historyOpen.value = false;
  window.addEventListener('pointermove', dragPanel);
  window.addEventListener('pointerup', stopPanelDrag);
  window.addEventListener('pointercancel', stopPanelDrag);
};

let resizeStart;
const resizePanel = e => {
  if (!resizeStart) return;
  panelSize.value = {
    width: Math.min(Math.max(360, resizeStart.width + e.clientX - resizeStart.x), vw.value - resizeStart.left - 8),
    height: Math.min(Math.max(420, resizeStart.height + e.clientY - resizeStart.y), vh.value - resizeStart.top - 8),
  };
};
const stopResize = () => {
  resizeStart = null;
  window.removeEventListener('pointermove', resizePanel);
  window.removeEventListener('pointerup', stopResize);
  window.removeEventListener('pointercancel', stopResize);
};
const startResize = e => {
  if (e.button !== 0) return;
  const rect = e.currentTarget.parentElement.getBoundingClientRect();
  panelOrigin.value = { left: rect.left, top: rect.top };
  resizeStart = { x: e.clientX, y: e.clientY, width: rect.width, height: rect.height, left: rect.left, top: rect.top };
  e.currentTarget.setPointerCapture(e.pointerId);
  window.addEventListener('pointermove', resizePanel);
  window.addEventListener('pointerup', stopResize);
  window.addEventListener('pointercancel', stopResize);
};
onBeforeUnmount(stopResize);
onBeforeUnmount(stopPanelDrag);

let startX = 0;
let startY = 0;
let startRight = 0;
let startBottom = 0;
let moved = false;
const onPointerMove = e => {
  const dx = e.clientX - startX;
  const dy = e.clientY - startY;
  if (Math.abs(dx) > 4 || Math.abs(dy) > 4) moved = true;
  // 右偏移随左移增大、下偏移随上移增大
  const right = Math.min(
    Math.max(startRight - dx, 8),
    window.innerWidth - LAUNCHER - 8
  );
  const bottom = Math.min(
    Math.max(startBottom - dy, 8),
    window.innerHeight - LAUNCHER - 8
  );
  pos.value = { right, bottom };
};
const onPointerUp = () => {
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointerup', onPointerUp);
  if (moved) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(pos.value));
    } catch {
      // 存储不可用则忽略（位置仍在本次会话生效）
    }
  }
};
const onPointerDown = e => {
  moved = false;
  startX = e.clientX;
  startY = e.clientY;
  startRight = pos.value.right;
  startBottom = pos.value.bottom;
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp);
};
// 拖动后不触发打开；纯点击（未拖动）才开面板。
const onLauncherClick = () => {
  if (!moved) toggle();
};
onBeforeUnmount(() => {
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointerup', onPointerUp);
});
</script>

<template>
  <!-- 悬浮触发按钮（可拖动，位置记忆） -->
  <button
    v-if="canUse && !open"
    type="button"
    :style="launcherStyle"
    class="fixed z-[55] flex items-center justify-center rounded-full cursor-move touch-none select-none size-[104px] p-0 bg-transparent hover:-translate-y-1 hover:scale-110 active:scale-95 transition-transform motion-reduce:transition-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-blue-500"
    title="AI 助手（可拖动）"
    @pointerdown="onPointerDown"
    @click="onLauncherClick"
  >
    <CrmAiMascot
      class="pointer-events-none shrink-0 size-[104px] drop-shadow-md animate-ai-cloud-idle motion-reduce:animate-none"
    />
  </button>

  <!-- 对话面板。
       用 v-show 而不是 v-if：v-if 会在关闭时把整个面板卸载，CrmAgentPanel 里的
       conversation、滚动位置、没发出去的半截问句全跟着没了，再打开就是一轮新对话
       （2026-10-30 反馈：关掉再打开，刚才问的东西找不回来了）。
       隐藏着也留在 DOM 里，还在跑的那一轮会继续轮询，回来时答案已经在那儿了。
       球那边的条件本来就带 !open，两者仍然互斥。 -->
  <div
    v-if="canUse"
    v-show="open"
    :style="panelStyle"
    class="fixed z-[55] flex flex-col overflow-hidden border shadow-2xl rounded-2xl border-[#e8e8e8] bg-white font-sans antialiased text-label !text-[14px] !font-normal !leading-6 !tracking-normal"
  >
    <div
      class="flex items-center gap-0.5 px-4 py-2.5 bg-white cursor-move select-none"
      title="按住拖动"
      @pointerdown="startPanelDrag"
    >
      <span class="text-heading-3 !font-sans !text-[14px] !font-medium !tracking-normal text-[#202124]">AI 助手</span>
      <button
        type="button"
        class="ml-auto inline-flex items-center gap-1 whitespace-nowrap rounded-lg px-1.5 py-1 text-label !font-sans !text-[13px] !font-normal !tracking-normal text-[#6b7078] hover:bg-black/5 hover:text-[#202124]"
        title="新对话"
        @click="newChat"
      >
        <span class="i-lucide-plus size-4 shrink-0" aria-hidden="true" />
        <span>新对话</span>
      </button>
      <div class="relative">
        <button
          type="button"
          class="inline-flex items-center rounded-lg p-1 text-[#6b7078] hover:bg-black/5 hover:text-[#202124]"
          title="历史记录"
          aria-label="历史记录"
          @click="toggleHistory"
        >
          <span class="i-lucide-history size-4 shrink-0" aria-hidden="true" />
        </button>

        <div
          v-if="historyOpen"
          class="absolute right-0 z-10 mt-1 flex max-h-80 w-72 flex-col overflow-auto rounded-xl border border-[#e8e8e8] bg-white py-1 shadow-xl"
        >
          <span
            v-if="historyLoading && !conversations.length"
            class="px-3 py-2 text-label !text-[13px] text-[#858a92]"
          >
            加载中…
          </span>
          <span
            v-else-if="historyFailed"
            class="px-3 py-2 text-label !text-[13px] text-[#858a92]"
          >
            取不到历史对话
          </span>
          <span
            v-else-if="!conversations.length"
            class="px-3 py-2 text-label !text-[13px] text-[#858a92]"
          >
            还没有对话
          </span>
          <button
            v-for="c in conversations"
            :key="c.id"
            type="button"
            class="flex items-center gap-2 px-3 py-2 text-left hover:bg-black/5"
            @click="openConversation(c.id)"
          >
            <span
              class="min-w-0 flex-1 truncate text-label !text-[13px] text-[#202124]"
            >
              {{ c.title }}
            </span>
            <span
              v-if="c.crm_customer_name"
              class="shrink-0 text-label !text-[12px] text-[#858a92]"
            >
              {{ c.crm_customer_name }}
            </span>
          </button>
        </div>
      </div>

      <div class="relative">
        <button
          type="button"
          class="inline-flex items-center rounded-lg p-1 text-[#6b7078] hover:bg-black/5 hover:text-[#202124]"
          title="它记住的事"
          aria-label="它记住的事"
          @click="toggleMemory"
        >
          <span class="i-lucide-brain size-4 shrink-0" aria-hidden="true" />
        </button>

        <div
          v-if="memoryOpen"
          class="absolute right-0 z-10 mt-1 flex max-h-80 w-80 flex-col overflow-auto rounded-xl border border-[#e8e8e8] bg-white py-1 shadow-xl"
        >
          <span
            v-if="memoryLoading"
            class="px-3 py-2 text-label !text-[13px] text-[#858a92]"
          >
            加载中…
          </span>
          <span
            v-else-if="memoryFailed"
            class="px-3 py-2 text-label !text-[13px] text-[#858a92]"
          >
            取不到
          </span>
          <!-- 空着时不能只说「还没有」：这功能没人知道，得顺手说清怎么让它记 -->
          <span
            v-else-if="memoryEmpty"
            class="px-3 py-2 text-label !text-[13px] leading-5 text-[#858a92]"
          >
            还没记住什么。跟它说「以后都…」「别再…」，它就会一直记着。
          </span>
          <template v-else>
            <span
              v-if="memories.company.length"
              class="px-3 pt-2 pb-1 text-label !text-[12px] text-[#858a92]"
            >
              公司规矩 · 对所有人算数
            </span>
            <div
              v-for="m in memories.company"
              :key="m.id"
              class="flex items-start gap-2 px-3 py-1.5 group/mem hover:bg-black/5"
            >
              <span
                class="flex-1 min-w-0 text-label !text-[13px] leading-5 text-[#202124]"
              >
                {{ m.content }}
              </span>
              <button
                v-if="memories.may_edit_company"
                type="button"
                class="mt-0.5 hidden shrink-0 rounded p-0.5 text-[#858a92] hover:text-[#202124] group-hover/mem:block"
                title="删掉这条"
                @click="forgetMemory(m)"
              >
                <span class="i-lucide-x size-3.5 shrink-0" />
              </button>
            </div>
            <span
              v-if="memories.mine.length"
              class="px-3 pt-2 pb-1 text-label !text-[12px] text-[#858a92]"
            >
              我的习惯
            </span>
            <div
              v-for="m in memories.mine"
              :key="m.id"
              class="flex items-start gap-2 px-3 py-1.5 group/mem hover:bg-black/5"
            >
              <span
                class="flex-1 min-w-0 text-label !text-[13px] leading-5 text-[#202124]"
              >
                {{ m.content }}
              </span>
              <button
                type="button"
                class="mt-0.5 hidden shrink-0 rounded p-0.5 text-[#858a92] hover:text-[#202124] group-hover/mem:block"
                title="删掉这条"
                @click="forgetMemory(m)"
              >
                <span class="i-lucide-x size-3.5 shrink-0" />
              </button>
            </div>
          </template>
        </div>
      </div>

      <button
        type="button"
        class="ml-0.5 inline-flex items-center rounded-lg p-1 text-[#858a92] hover:bg-black/5 hover:text-[#202124]"
        title="关闭"
        @click="toggle"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>

    <div class="flex-1 min-h-0 px-5 pb-4">
      <CrmAgentPanel ref="panelRef" floating-layout />
    </div>
    <button
      type="button"
      aria-label="拖动调整 AI 助手窗口大小"
      title="拖动调整大小"
      class="absolute bottom-1 right-1 flex size-6 touch-none select-none items-center justify-center rounded-br-xl border-0 bg-transparent p-0 text-[#aaa] hover:text-[#333] cursor-nwse-resize"
      @pointerdown.stop.prevent="startResize"
    >
      <span class="i-lucide-grip size-3.5" aria-hidden="true" />
    </button>
  </div>
</template>
