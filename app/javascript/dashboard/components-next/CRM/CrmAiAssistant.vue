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
import { ref, computed, onBeforeUnmount } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAgentPanel from 'dashboard/components-next/CRM/CrmAgentPanel.vue';

const open = ref(false);
const panelRef = ref(null);

// 名单之外的人不显示悬浮球（后端 Crm::AgentController 会再判一次）。
const currentUser = useMapGetter('getCurrentUser');
const canUse = computed(() => currentUser.value?.crm_agent === true);

const toggle = () => {
  open.value = !open.value;
};

// —— 悬浮图标可拖动 + 记忆位置（按距右下角的偏移存 localStorage）——
const STORAGE_KEY = 'crmAiAssistantPos';
const LAUNCHER = 56; // size-14
const PANEL_W = 380;
const PANEL_H = 560;
const pos = ref({ right: 24, bottom: 24 });
try {
  const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
  if (saved && Number.isFinite(saved.right) && Number.isFinite(saved.bottom)) {
    pos.value = saved;
  }
} catch {
  // 忽略损坏的本地存储
}

const launcherStyle = computed(() => ({
  right: `${pos.value.right}px`,
  bottom: `${pos.value.bottom}px`,
}));
// 面板贴着图标位置弹出，并夹取在视口内确保完整可见。
const panelStyle = computed(() => {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const right = Math.min(
    Math.max(pos.value.right, 8),
    Math.max(vw - PANEL_W - 8, 8)
  );
  const bottom = Math.min(
    Math.max(pos.value.bottom, 8),
    Math.max(vh - PANEL_H - 8, 8)
  );
  return { right: `${right}px`, bottom: `${bottom}px` };
});

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
    class="fixed z-50 flex items-center justify-center text-white rounded-full shadow-lg cursor-move touch-none select-none size-14 bg-gradient-to-br from-n-iris-9 to-n-violet-10 shadow-n-iris-9/30 hover:scale-105 transition-transform"
    title="AI 助手（可拖动）"
    @pointerdown="onPointerDown"
    @click="onLauncherClick"
  >
    <span class="pointer-events-none i-ph-sparkle-fill size-6" />
  </button>

  <!-- 对话面板 -->
  <div
    v-else-if="canUse"
    :style="panelStyle"
    class="fixed z-50 flex flex-col overflow-hidden border shadow-2xl w-[380px] max-w-[calc(100vw-2rem)] h-[560px] max-h-[calc(100vh-6rem)] rounded-2xl border-white/60 bg-n-solid-1/95 backdrop-blur-xl"
  >
    <div
      class="flex items-center gap-2 px-4 py-3 border-b border-n-weak bg-gradient-to-r from-n-iris-3 to-n-violet-3"
    >
      <span class="i-ph-sparkle-fill size-4 text-n-iris-11" />
      <span class="text-sm font-semibold text-n-slate-12">AI 助手</span>
      <button
        type="button"
        class="ml-auto mr-1 text-n-slate-10 hover:text-n-slate-12"
        title="新对话"
        @click="panelRef?.reset()"
      >
        <span class="i-lucide-rotate-ccw size-3.5" />
      </button>
      <button
        type="button"
        class="text-n-slate-10 hover:text-n-slate-12"
        title="关闭"
        @click="toggle"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>

    <div class="flex-1 min-h-0 px-3 py-2">
      <CrmAgentPanel ref="panelRef" />
    </div>
  </div>
</template>
