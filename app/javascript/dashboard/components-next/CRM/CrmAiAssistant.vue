<script setup>
/* global axios */
// CRM 全局对话式 AI 助手（对标小满「专业 Agent 调度中枢」）：一句话直达——
// 问数（新增客户/待跟进/在谈商机/订单额/我的待办）、写邮件、客户背调、外贸知识问答。
// 常驻在 CRM 布局层，悬浮右下角；对话为临时会话（不落库，精简）。
import { ref, computed, nextTick, onBeforeUnmount } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmComposeStore } from 'dashboard/stores/crm/compose';

const { accountId } = useAccount();
const composeStore = useCrmComposeStore();

const open = ref(false);
const input = ref('');
const loading = ref(false);
const messages = ref([]); // { role: 'user'|'assistant', text, kind?, data? }
const scrollRef = ref(null);

const QUICK = [
  '近30天新增了多少客户',
  '有哪些客户该跟进了',
  '现在在谈的商机金额',
  '本月成交订单额',
];

const scrollToBottom = () => {
  nextTick(() => {
    if (scrollRef.value)
      scrollRef.value.scrollTop = scrollRef.value.scrollHeight;
  });
};

const toggle = () => {
  open.value = !open.value;
  if (open.value) scrollToBottom();
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

const send = async text => {
  const q = (text ?? input.value).trim();
  if (!q || loading.value) return;
  input.value = '';
  messages.value.push({ role: 'user', text: q });
  loading.value = true;
  scrollToBottom();
  try {
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/crm/ai/ask`,
      { message: q }
    );
    messages.value.push({
      role: 'assistant',
      text: data.reply || '',
      kind: data.kind,
      data: data.data,
    });
  } catch (e) {
    messages.value.push({
      role: 'assistant',
      text: e.response?.data?.message || 'AI 出错了，请稍后再试。',
    });
  } finally {
    loading.value = false;
    scrollToBottom();
  }
};

// compose 结果 →「用此稿写信」：把草稿带入常驻写信窗。
const useDraft = data => {
  composeStore.open({ subject: data?.subject, body: data?.body });
};
</script>

<template>
  <!-- 悬浮触发按钮（可拖动，位置记忆） -->
  <button
    v-if="!open"
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
    v-else
    :style="panelStyle"
    class="fixed z-50 flex flex-col overflow-hidden border shadow-2xl w-[380px] max-w-[calc(100vw-2rem)] h-[560px] max-h-[calc(100vh-6rem)] rounded-2xl border-white/60 bg-n-solid-1/95 backdrop-blur-xl"
  >
    <!-- 头部 -->
    <div
      class="flex items-center gap-2 px-4 py-3 border-b border-n-weak bg-gradient-to-r from-n-iris-3 to-n-violet-3"
    >
      <span class="i-ph-sparkle-fill size-4 text-n-iris-11" />
      <span class="text-sm font-semibold text-n-slate-12">AI 助手</span>
      <button
        type="button"
        class="ml-auto text-n-slate-10 hover:text-n-slate-12"
        title="关闭"
        @click="toggle"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>

    <!-- 消息区 -->
    <div ref="scrollRef" class="flex-1 px-4 py-3 space-y-3 overflow-y-auto">
      <!-- 空态：引导 + 快捷问题 -->
      <div v-if="!messages.length" class="flex flex-col gap-3">
        <p class="text-sm text-n-slate-11">
          你好，我可以帮你查数据、写邮件、做客户背调。试试问我：
        </p>
        <div class="flex flex-col gap-1.5">
          <button
            v-for="q in QUICK"
            :key="q"
            type="button"
            class="px-3 py-2 text-xs text-left transition-colors border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
            @click="send(q)"
          >
            {{ q }}
          </button>
        </div>
      </div>

      <!-- 对话气泡 -->
      <div
        v-for="(m, i) in messages"
        :key="i"
        class="flex"
        :class="m.role === 'user' ? 'justify-end' : 'justify-start'"
      >
        <div
          class="max-w-[85%] rounded-2xl px-3 py-2 text-sm whitespace-pre-wrap break-words"
          :class="
            m.role === 'user'
              ? 'bg-n-iris-9 text-white rounded-br-sm'
              : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm'
          "
        >
          {{ m.text }}
          <!-- 写邮件草稿：主题预览 +「用此稿写信」 -->
          <div
            v-if="m.kind === 'compose' && m.data"
            class="mt-2 p-2 rounded-lg bg-n-solid-1/70 border border-n-weak text-n-slate-11"
          >
            <div v-if="m.data.subject" class="mb-1 font-medium text-n-slate-12">
              {{ m.data.subject }}
            </div>
            <div class="line-clamp-3 text-xs opacity-80">{{ m.data.body }}</div>
            <button
              type="button"
              class="inline-flex items-center gap-1 mt-2 px-2.5 py-1 text-xs font-semibold rounded-md text-n-iris-11 bg-n-iris-3 hover:bg-n-iris-4"
              @click="useDraft(m.data)"
            >
              <span class="i-lucide-pen-line size-3.5" />用此稿写信
            </button>
          </div>
        </div>
      </div>

      <!-- 加载态 -->
      <div v-if="loading" class="flex justify-start">
        <div
          class="px-3 py-2 text-sm rounded-2xl rounded-bl-sm bg-n-alpha-2 text-n-slate-10 animate-pulse"
        >
          正在思考…
        </div>
      </div>
    </div>

    <!-- 输入区 -->
    <div class="flex items-end gap-2 px-3 py-3 border-t border-n-weak">
      <textarea
        v-model="input"
        rows="1"
        placeholder="问我任何 CRM 相关的事…"
        class="flex-1 px-3 py-2 text-sm border rounded-lg resize-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-iris-8 max-h-24"
        @keydown.enter.exact.prevent="send()"
      />
      <button
        type="button"
        class="flex items-center justify-center text-white rounded-lg shrink-0 size-9 bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
        :disabled="loading || !input.trim()"
        title="发送"
        @click="send()"
      >
        <span class="i-lucide-send size-4" />
      </button>
    </div>
  </div>
</template>
