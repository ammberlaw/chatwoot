<script setup>
// CRM AI 助手的对话面板。侧栏独立页和客户详情面板共用这一个组件。
//
// 为什么要轮询：agent 一轮要连调几次工具、十几秒到一分钟，后端是丢进后台任务跑的，
// 这里按会话 status 轮询，RUNNING 就接着等（见 Crm::AgentRunJob）。
import {
  ref,
  computed,
  nextTick,
  onMounted,
  onBeforeUnmount,
  watch,
} from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAgentAPI from 'dashboard/api/crm/agent';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  // 从客户详情面板进来时带上，对话默认就在谈这个客户
  crmCustomerId: { type: [Number, String], default: null },
  // 独立页会把高度撑满；面板里嵌用传 false
  fullHeight: { type: Boolean, default: true },
});

const conversation = ref(null);
const messages = computed(() => conversation.value?.messages || []);
const input = ref('');
const starting = ref(false);
const scroller = ref(null);
let timer = null;

const running = computed(() => conversation.value?.status === 'RUNNING');
const busy = computed(() => running.value || starting.value);

const scrollToEnd = async () => {
  await nextTick();
  const el = scroller.value;
  if (el) el.scrollTop = el.scrollHeight;
};

const stopPolling = () => {
  if (timer) clearInterval(timer);
  timer = null;
};

// 2 秒一次：再快纯属浪费，再慢用户会以为卡住了。
const startPolling = () => {
  stopPolling();
  timer = setInterval(async () => {
    if (!conversation.value) return;
    try {
      const { data } = await CrmAgentAPI.show(conversation.value.id);
      conversation.value = data.payload;
      if (!running.value) stopPolling();
      scrollToEnd();
    } catch {
      stopPolling();
    }
  }, 2000);
};

const ensureConversation = async () => {
  if (conversation.value) return conversation.value;
  starting.value = true;
  try {
    const { data } = await CrmAgentAPI.create(props.crmCustomerId);
    conversation.value = data.payload;
    return conversation.value;
  } finally {
    starting.value = false;
  }
};

const send = async () => {
  const text = input.value.trim();
  if (!text || busy.value) return;
  try {
    const conv = await ensureConversation();
    input.value = '';
    const { data } = await CrmAgentAPI.sendMessage(conv.id, text);
    conversation.value = data.payload;
    scrollToEnd();
    startPolling();
  } catch (error) {
    useAlert(error?.response?.data?.error || '发送失败');
  }
};

// 换客户（客户详情面板里切到别的客户）就重开一轮对话，免得上下文串台。
watch(
  () => props.crmCustomerId,
  () => {
    stopPolling();
    conversation.value = null;
  }
);

const reset = () => {
  stopPolling();
  conversation.value = null;
  input.value = '';
};

onMounted(scrollToEnd);
onBeforeUnmount(stopPolling);

defineExpose({ reset });

// 快捷问法：新用户不知道能问什么，给几条踩得准的
const SHORTCUTS = [
  '把这个客户最近的往来邮件总结一下，谈到哪一步了',
  '这个客户值不值得跟？看看成交记录和最近互动',
  '根据最近邮件，起草一封跟进邮件',
];
const useShortcut = text => {
  input.value = text;
  send();
};
</script>

<template>
  <div
    class="flex flex-col min-h-0"
    :class="fullHeight ? 'h-full' : 'h-[32rem]'"
  >
    <div ref="scroller" class="flex-1 min-h-0 px-1 overflow-y-auto">
      <div
        v-if="!messages.length"
        class="flex flex-col gap-2 px-3 py-6 text-sm text-n-slate-11"
      >
        <p>
          我能查客户、翻往来邮件做总结、查产品和报价，还能把邮件和 PI 写成草稿。
        </p>
        <p class="text-xs">
          草稿都不会自动发出去——写好放在草稿箱/PI 列表里，你核对后自己点发送。
        </p>
        <div class="flex flex-col gap-1 mt-2">
          <button
            v-for="s in SHORTCUTS"
            :key="s"
            type="button"
            class="px-3 py-2 text-xs text-left border rounded-lg reset-base border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="useShortcut(s)"
          >
            {{ s }}
          </button>
        </div>
      </div>

      <div
        v-for="m in messages"
        :key="m.id"
        class="px-1 py-1.5"
        :class="m.role === 'user' ? 'flex justify-end' : ''"
      >
        <!-- 它中间查了什么，摆出来。不摆的话 AI 说什么就是什么，没人判断得出结论从哪来。 -->
        <div
          v-if="m.role === 'tool'"
          class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-md text-n-slate-11 bg-n-alpha-1"
        >
          <span class="i-lucide-search size-3 shrink-0" />
          {{ m.content }}
        </div>
        <div
          v-else-if="m.role === 'user'"
          class="max-w-[85%] px-3 py-2 text-sm rounded-2xl whitespace-pre-wrap bg-n-iris-9 text-white"
        >
          {{ m.content }}
        </div>
        <div
          v-else
          class="max-w-[92%] px-3 py-2 text-sm rounded-2xl whitespace-pre-wrap bg-n-alpha-1 text-n-slate-12"
        >
          {{ m.content }}
        </div>
      </div>

      <div
        v-if="running"
        class="flex items-center gap-2 px-3 py-2 text-xs text-n-slate-11"
      >
        <span class="i-lucide-loader-circle size-3.5 shrink-0 animate-spin" />
        正在查…（要几十秒，可以先去忙别的）
      </div>
    </div>

    <div class="flex items-end gap-2 px-1 pt-2 border-t border-n-weak">
      <textarea
        v-model="input"
        rows="2"
        placeholder="问点什么…（回车发送，Shift+回车换行）"
        class="flex-1 px-3 py-2 text-sm border rounded-xl outline-none resize-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
        :disabled="busy"
        @keydown.enter.exact.prevent="send"
      />
      <Button
        label="发送"
        color="iris"
        size="sm"
        :is-loading="busy"
        :disabled="!input.trim()"
        @click="send"
      />
    </div>
  </div>
</template>
